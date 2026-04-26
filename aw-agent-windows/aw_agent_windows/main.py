import logging
import time
from typing import Any, Dict, List, Optional, Sequence

import requests
from aw_core.log import setup_logging

from .config import parse_args
from .identity import build_agent_identity
from .outbox import SyncOutbox, canonical_json
from .sync_client import FleetSyncClient

logger = logging.getLogger(__name__)


def _fit_batch(ops: List[Dict[str, Any]], max_bytes: int) -> List[Dict[str, Any]]:
    batch = []
    for op in ops:
        candidate = batch + [op]
        encoded = canonical_json({"ops": candidate})
        if batch and len(encoded.encode("utf8")) > max_bytes:
            break
        batch = candidate
    return batch


def sync_once(outbox: SyncOutbox, client: FleetSyncClient, agent: Dict[str, str], batch_max_ops: int, batch_max_bytes: int) -> int:
    streams = outbox.get_streams()
    if not streams:
        return 0

    handshake = client.handshake(agent, streams)
    acked_by_stream = {
        row["stream_id"]: int(row["last_acked_seq"])
        for row in handshake.get("streams", [])
    }

    uploaded = 0
    for stream in streams:
        stream_id = str(stream["stream_id"])
        if stream_id in acked_by_stream:
            outbox.mark_acked(stream_id, acked_by_stream[stream_id])

        while True:
            local_acked = acked_by_stream.get(stream_id, int(stream["last_acked_seq"]))
            ops = outbox.list_unacked_ops(
                stream_id,
                after_seq=local_acked,
                limit=batch_max_ops,
            )
            if not ops:
                break

            batch = _fit_batch(ops, batch_max_bytes)
            if not batch:
                batch = [ops[0]]

            outbox.touch_sync_attempt(stream_id)
            response = client.upload_batch(
                agent_id=agent["agent_id"],
                stream_id=stream_id,
                from_seq=int(batch[0]["seq"]),
                to_seq=int(batch[-1]["seq"]),
                ops=batch,
            )
            acked = int(response["acked_through_seq"])
            outbox.mark_acked(stream_id, acked)
            acked_by_stream[stream_id] = acked
            uploaded += len(batch)

    return uploaded


def main(argv: Optional[Sequence[str]] = None) -> None:
    args = parse_args(argv)
    setup_logging(
        name="aw-agent-windows",
        testing=args.testing,
        verbose=args.verbose,
        log_stderr=True,
        log_file=True,
    )

    outbox = SyncOutbox(testing=args.testing)
    agent = build_agent_identity(
        device_id=args.device_id,
        device_name=args.device_name,
    )
    outbox.get_or_create_agent(agent)

    client = FleetSyncClient(
        host=args.host,
        port=args.port,
        protocol=args.protocol,
        timeout=args.timeout,
    )

    while True:
        try:
            uploaded = sync_once(
                outbox,
                client,
                agent,
                batch_max_ops=args.batch_max_ops,
                batch_max_bytes=args.batch_max_bytes,
            )
            logger.info("sync cycle complete, uploaded_ops=%s", uploaded)
        except requests.RequestException as exc:
            logger.warning("sync request failed: %s", exc)
        except Exception:
            logger.exception("sync loop failed")

        if args.once:
            return
        time.sleep(args.interval)
