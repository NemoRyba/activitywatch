import logging
import sys
from datetime import datetime, timezone
from time import sleep

from aw_client import ActivityWatchClient
from aw_core.identity import (
    build_bucket_id,
    build_bucket_metadata,
    is_central_mode,
    resolve_identity,
)
from aw_core.log import setup_logging
from aw_core.models import Event

from .config import parse_args
from .state import active_roles, activity_state, clamp_threshold, max_peak, parse_roles
from .windows import AudioApiError, read_endpoint_levels

logger = logging.getLogger(__name__)


def main():
    if sys.platform != "win32":
        raise Exception("aw-watcher-audio is only supported on Windows")

    args = parse_args()
    setup_logging(
        name="aw-watcher-audio",
        testing=args.testing,
        verbose=args.verbose,
        log_stderr=True,
        log_file=True,
    )

    if args.poll_time <= 0:
        raise ValueError("--poll-time must be greater than 0")
    if args.heartbeat_time <= 0:
        raise ValueError("--heartbeat-time must be greater than 0")

    roles = parse_roles(args.roles)
    thresholds = {
        "playback": clamp_threshold(args.playback_threshold),
        "microphone": clamp_threshold(args.microphone_threshold),
    }

    client = ActivityWatchClient(
        "aw-watcher-audio", host=args.host, port=args.port, testing=args.testing
    )
    identity = resolve_identity(
        username=args.username or None,
        device_id=args.device_id or None,
        device_name=args.device_name or None,
        session_id=args.session_id or None,
        session_type=args.session_type or None,
    )
    central_mode = is_central_mode(args.central_mode)

    bucket_ids = {
        stream: build_bucket_id(
            f"{client.client_name}-{stream}",
            client.client_hostname,
            identity,
            central_mode=central_mode,
        )
        for stream in ("playback", "microphone")
    }

    base_bucket_data = build_bucket_metadata(
        identity, source="aw-central-v1" if central_mode else "aw-audio"
    )

    with client:
        for stream, bucket_id in bucket_ids.items():
            bucket_data = dict(base_bucket_data)
            bucket_data["stream"] = stream
            bucket_data["threshold"] = thresholds[stream]
            client.create_bucket(
                bucket_id,
                f"audio.{stream}",
                queued=True,
                data=bucket_data,
            )

        logger.info("aw-watcher-audio started")
        heartbeat_loop(
            client=client,
            bucket_ids=bucket_ids,
            poll_time=args.poll_time,
            heartbeat_time=args.heartbeat_time,
            thresholds=thresholds,
            roles=roles,
            include_levels=args.include_levels,
            identity=identity,
        )


def heartbeat_loop(
    client,
    bucket_ids,
    poll_time,
    heartbeat_time,
    thresholds,
    roles,
    include_levels,
    identity,
):
    previous_data = {}
    last_sent_at = {}
    pulsetime = heartbeat_time + poll_time + 5.0

    while True:
        try:
            now = datetime.now(timezone.utc)
            try:
                levels = read_endpoint_levels(roles)
                stream_data = {
                    stream: build_event_data(
                        stream=stream,
                        levels=levels.get(stream, []),
                        threshold=thresholds[stream],
                        roles=roles,
                        include_levels=include_levels,
                        identity=identity,
                    )
                    for stream in ("playback", "microphone")
                }
            except AudioApiError as error:
                logger.warning("Audio API sample failed: %s", error)
                stream_data = {
                    stream: build_error_event_data(
                        stream=stream,
                        threshold=thresholds[stream],
                        roles=roles,
                        identity=identity,
                    )
                    for stream in ("playback", "microphone")
                }

            for stream, event_data in stream_data.items():
                should_send = event_data != previous_data.get(stream)
                if not should_send:
                    last_sent = last_sent_at.get(stream)
                    should_send = (
                        last_sent is None
                        or (now - last_sent).total_seconds() >= heartbeat_time
                    )

                if not should_send:
                    continue

                event = Event(timestamp=now, data=event_data)
                client.heartbeat(
                    bucket_ids[stream],
                    event,
                    pulsetime=pulsetime,
                    queued=True,
                    commit_interval=heartbeat_time,
                )
                previous_data[stream] = event_data
                last_sent_at[stream] = now

            sleep(poll_time)
        except KeyboardInterrupt:
            logger.info("aw-watcher-audio stopped by keyboard interrupt")
            break


def build_event_data(stream, levels, threshold, roles, include_levels, identity):
    peak = max_peak(levels)
    data = {
        "state": activity_state(levels, threshold),
        "stream": stream,
        "threshold": threshold,
        "sample_roles": roles,
        "device_count": len(levels),
        "active_roles": active_roles(levels, threshold),
        "username": identity["username"],
        "device_id": identity["device_id"],
        "device_name": identity["device_name"],
        "session_id": identity["session_id"],
        "session_type": identity["session_type"],
        "hostname": identity["hostname"],
    }
    if include_levels:
        data["peak_percent"] = round(peak * 100.0, 1)
    return data


def build_error_event_data(stream, threshold, roles, identity):
    return {
        "state": "error",
        "stream": stream,
        "threshold": threshold,
        "sample_roles": roles,
        "device_count": 0,
        "active_roles": [],
        "username": identity["username"],
        "device_id": identity["device_id"],
        "device_name": identity["device_name"],
        "session_id": identity["session_id"],
        "session_type": identity["session_type"],
        "hostname": identity["hostname"],
    }

