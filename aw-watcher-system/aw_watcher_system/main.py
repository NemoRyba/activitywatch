import logging
import os
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
from .windows import calculate_cpu_percent, read_cpu_times

logger = logging.getLogger(__name__)


def main():
    if sys.platform != "win32":
        raise Exception("aw-watcher-system is only supported on Windows")

    args = parse_args()
    setup_logging(
        name="aw-watcher-system",
        testing=args.testing,
        verbose=args.verbose,
        log_stderr=True,
        log_file=True,
    )

    if args.poll_time <= 0:
        raise ValueError("--poll-time must be greater than 0")

    client = ActivityWatchClient(
        "aw-watcher-system", host=args.host, port=args.port, testing=args.testing
    )
    identity = resolve_identity(
        username=args.username or None,
        device_id=args.device_id or None,
        device_name=args.device_name or None,
        session_id=args.session_id or None,
        session_type=args.session_type or None,
    )
    central_mode = is_central_mode(args.central_mode)

    bucket_id = build_bucket_id(
        client.client_name, client.client_hostname, identity, central_mode=central_mode
    )
    bucket_data = build_bucket_metadata(
        identity, source="aw-central-v1" if central_mode else "aw-system"
    )
    bucket_data["metrics"] = "cpu"

    with client:
        client.create_bucket(bucket_id, "systemmetrics", queued=True, data=bucket_data)
        logger.info("aw-watcher-system started")
        heartbeat_loop(client, bucket_id, args.poll_time, identity)


def heartbeat_loop(client, bucket_id, poll_time, identity):
    previous = read_cpu_times()

    while True:
        try:
            sleep(poll_time)
            current = read_cpu_times()
            cpu_percent = calculate_cpu_percent(previous, current)
            previous = current

            now = datetime.now(timezone.utc)
            event_data = {
                "metric": "cpu_load",
                "cpu_percent": round(cpu_percent, 1),
                "cpu_idle_percent": round(100.0 - cpu_percent, 1),
                "cpu_count": os.cpu_count() or 0,
                "sample_seconds": poll_time,
                "username": identity["username"],
                "device_id": identity["device_id"],
                "device_name": identity["device_name"],
                "session_id": identity["session_id"],
                "session_type": identity["session_type"],
                "hostname": identity["hostname"],
            }

            event = Event(timestamp=now, data=event_data)
            client.heartbeat(
                bucket_id, event, pulsetime=poll_time + 1.0, queued=True
            )
        except KeyboardInterrupt:
            logger.info("aw-watcher-system stopped by keyboard interrupt")
            break
