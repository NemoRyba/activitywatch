from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence


@dataclass(frozen=True)
class EndpointLevel:
    flow: str
    role: str
    peak: float
    device_id: Optional[str] = None


def clamp_threshold(value: float) -> float:
    return min(max(float(value), 0.0), 1.0)


def max_peak(levels: Iterable[EndpointLevel]) -> float:
    peak = 0.0
    for level in levels:
        peak = max(peak, min(max(float(level.peak), 0.0), 1.0))
    return peak


def activity_state(levels: Sequence[EndpointLevel], threshold: float) -> str:
    if not levels:
        return "no_device"
    return "active" if max_peak(levels) >= clamp_threshold(threshold) else "silent"


def active_roles(levels: Sequence[EndpointLevel], threshold: float) -> List[str]:
    threshold = clamp_threshold(threshold)
    roles = []
    for level in levels:
        if level.peak >= threshold and level.role not in roles:
            roles.append(level.role)
    return roles


def parse_roles(value: str) -> List[str]:
    aliases = {
        "console": "console",
        "multimedia": "multimedia",
        "media": "multimedia",
        "communications": "communications",
        "communication": "communications",
        "comms": "communications",
    }
    roles = []
    for part in str(value or "").split(","):
        role = aliases.get(part.strip().lower())
        if role and role not in roles:
            roles.append(role)
    return roles or ["console", "multimedia", "communications"]

