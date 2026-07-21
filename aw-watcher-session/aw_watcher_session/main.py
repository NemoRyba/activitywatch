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
from .windows import get_current_session_snapshot

logger = logging.getLogger(__name__)


def main():
    if sys.platform != "win32":
        raise Exception("aw-watcher-session is only supported on Windows")

    args = parse_args()
    setup_logging(
        name="aw-watcher-session",
        testing=args.testing,
        verbose=args.verbose,
        log_stderr=True,
        log_file=True,
    )

    client = ActivityWatchClient(
        "aw-watcher-session", host=args.host, port=args.port, testing=args.testing
    )
    snapshot = get_current_session_snapshot()
    identity = resolve_identity(
        username=args.username or snapshot.username or None,
        device_id=args.device_id or None,
        device_name=args.device_name or None,
        session_id=args.session_id or snapshot.session_id or None,
        session_type=args.session_type or snapshot.session_type or None,
    )
    central_mode = is_central_mode(args.central_mode)

    bucket_id = build_bucket_id(
        client.client_name, client.client_hostname, identity, central_mode=central_mode
    )
    bucket_data = build_bucket_metadata(
        identity, source="aw-central-v1" if central_mode else "aw-session"
    )
    if snapshot.domain:
        bucket_data["domain"] = snapshot.domain

    with client:
        client.create_bucket(bucket_id, "sessionstate", queued=True, data=bucket_data)
        logger.info("aw-watcher-session started")
        heartbeat_loop(client, bucket_id, args.poll_time, identity)


def heartbeat_loop(client, bucket_id, poll_time, identity):
    while True:
        try:
            snapshot = get_current_session_snapshot()
            now = datetime.now(timezone.utc)

            event_data = {
                "state": snapshot.state,
                "reason": snapshot.reason,
                "username": identity["username"],
                "device_id": identity["device_id"],
                "device_name": identity["device_name"],
                "session_id": identity["session_id"],
                "session_type": snapshot.session_type or identity["session_type"],
                "hostname": identity["hostname"],
                "connect_state": snapshot.connect_state,
                "connect_state_name": snapshot.connect_state_name,
                "protocol_type": snapshot.protocol_type,
            }
            if snapshot.domain:
                event_data["domain"] = snapshot.domain
            if snapshot.session_flags is not None:
                event_data["session_flags"] = snapshot.session_flags
            if snapshot.lock_source:
                event_data["lock_source"] = snapshot.lock_source

            event = Event(timestamp=now, data=event_data)
            client.heartbeat(
                bucket_id, event, pulsetime=poll_time + 1.0, queued=True
            )
            sleep(poll_time)
        except KeyboardInterrupt:
            logger.info("aw-watcher-session stopped by keyboard interrupt")
            break
