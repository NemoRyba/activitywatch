import socket
from pathlib import Path
from typing import Dict, Optional
from uuid import uuid4

from aw_core.dirs import get_data_dir
from aw_core.identity import resolve_identity


def get_agent_id_path() -> Path:
    return Path(get_data_dir("aw-agent-windows")) / "agent_id"


def get_or_create_agent_id() -> str:
    path = get_agent_id_path()
    if path.exists():
        return path.read_text(encoding="utf8").strip()

    agent_id = str(uuid4())
    path.write_text(agent_id, encoding="utf8")
    return agent_id


def build_agent_identity(
    device_id: Optional[str] = None,
    device_name: Optional[str] = None,
) -> Dict[str, str]:
    identity = resolve_identity(
        device_id=device_id,
        device_name=device_name,
    )
    hostname = socket.gethostname() or identity["hostname"] or "unknown"
    return {
        "agent_id": get_or_create_agent_id(),
        "device_id": identity["device_id"],
        "device_name": identity["device_name"],
        "hostname": hostname,
    }
