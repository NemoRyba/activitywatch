import argparse
import os
from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass
class AgentConfig:
    host: str
    port: int
    protocol: str
    timeout: float
    batch_max_ops: int
    batch_max_bytes: int
    interval: float
    testing: bool
    once: bool
    verbose: bool
    device_id: Optional[str]
    device_name: Optional[str]


def parse_args(argv: Optional[Sequence[str]] = None) -> AgentConfig:
    parser = argparse.ArgumentParser(prog="aw-agent-windows")
    parser.add_argument(
        "--host",
        default=os.environ.get("AW_FLEET_SERVER_HOST", "127.0.0.1"),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("AW_FLEET_SERVER_PORT", "5600")),
    )
    parser.add_argument(
        "--protocol",
        default=os.environ.get("AW_FLEET_SERVER_PROTOCOL", "http"),
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("AW_FLEET_TIMEOUT", "30")),
    )
    parser.add_argument(
        "--batch-max-ops",
        type=int,
        default=int(os.environ.get("AW_FLEET_BATCH_MAX_OPS", "500")),
    )
    parser.add_argument(
        "--batch-max-bytes",
        type=int,
        default=int(os.environ.get("AW_FLEET_BATCH_MAX_BYTES", str(1024 * 1024))),
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=float(os.environ.get("AW_FLEET_INTERVAL", "10")),
    )
    parser.add_argument("--device-id", default=os.environ.get("AW_DEVICE_ID"))
    parser.add_argument("--device-name", default=os.environ.get("AW_DEVICE_NAME"))
    parser.add_argument("--testing", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    return AgentConfig(
        host=args.host,
        port=args.port,
        protocol=args.protocol,
        timeout=args.timeout,
        batch_max_ops=args.batch_max_ops,
        batch_max_bytes=args.batch_max_bytes,
        interval=args.interval,
        testing=args.testing,
        once=args.once,
        verbose=args.verbose,
        device_id=args.device_id,
        device_name=args.device_name,
    )
