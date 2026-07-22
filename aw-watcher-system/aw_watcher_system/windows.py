import ctypes
from dataclasses import dataclass


class FILETIME(ctypes.Structure):
    _fields_ = [
        ("dwLowDateTime", ctypes.c_uint32),
        ("dwHighDateTime", ctypes.c_uint32),
    ]


@dataclass(frozen=True)
class CpuTimes:
    idle: int
    total: int


def _filetime_to_int(value: FILETIME) -> int:
    return (int(value.dwHighDateTime) << 32) | int(value.dwLowDateTime)


def read_cpu_times() -> CpuTimes:
    idle = FILETIME()
    kernel = FILETIME()
    user = FILETIME()

    success = ctypes.windll.kernel32.GetSystemTimes(
        ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user)
    )
    if not success:
        raise ctypes.WinError()

    idle_time = _filetime_to_int(idle)
    kernel_time = _filetime_to_int(kernel)
    user_time = _filetime_to_int(user)
    return CpuTimes(idle=idle_time, total=kernel_time + user_time)


def calculate_cpu_percent(previous: CpuTimes, current: CpuTimes) -> float:
    idle_delta = current.idle - previous.idle
    total_delta = current.total - previous.total
    if total_delta <= 0:
        return 0.0

    busy_delta = max(total_delta - idle_delta, 0)
    percent = (busy_delta / total_delta) * 100.0
    return min(max(percent, 0.0), 100.0)
