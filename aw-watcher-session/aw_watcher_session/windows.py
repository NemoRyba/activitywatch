import ctypes
import getpass
import os
from dataclasses import dataclass
from ctypes import wintypes
from typing import Optional

WTS_CURRENT_SERVER_HANDLE = wintypes.HANDLE(0)

WTS_USER_NAME = 5
WTS_DOMAIN_NAME = 7
WTS_CONNECT_STATE = 8
WTS_CLIENT_PROTOCOL_TYPE = 16

WTS_ACTIVE = 0
WTS_CONNECTED = 1
WTS_CONNECT_QUERY = 2
WTS_SHADOW = 3
WTS_DISCONNECTED = 4
WTS_IDLE = 5
WTS_LISTEN = 6
WTS_RESET = 7
WTS_DOWN = 8
WTS_INIT = 9

DESKTOP_SWITCHDESKTOP = 0x0100

CONNECT_STATE_NAMES = {
    WTS_ACTIVE: "active",
    WTS_CONNECTED: "connected",
    WTS_CONNECT_QUERY: "connect-query",
    WTS_SHADOW: "shadow",
    WTS_DISCONNECTED: "disconnected",
    WTS_IDLE: "idle",
    WTS_LISTEN: "listen",
    WTS_RESET: "reset",
    WTS_DOWN: "down",
    WTS_INIT: "init",
}

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
wtsapi32 = ctypes.WinDLL("wtsapi32", use_last_error=True)
user32 = ctypes.WinDLL("user32", use_last_error=True)

ProcessIdToSessionId = kernel32.ProcessIdToSessionId
ProcessIdToSessionId.argtypes = [wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
ProcessIdToSessionId.restype = wintypes.BOOL

WTSQuerySessionInformationW = wtsapi32.WTSQuerySessionInformationW
WTSQuerySessionInformationW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.DWORD,
    ctypes.POINTER(ctypes.c_void_p),
    ctypes.POINTER(wintypes.DWORD),
]
WTSQuerySessionInformationW.restype = wintypes.BOOL

WTSFreeMemory = wtsapi32.WTSFreeMemory
WTSFreeMemory.argtypes = [ctypes.c_void_p]
WTSFreeMemory.restype = None

OpenInputDesktop = user32.OpenInputDesktop
OpenInputDesktop.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
OpenInputDesktop.restype = wintypes.HANDLE

SwitchDesktop = user32.SwitchDesktop
SwitchDesktop.argtypes = [wintypes.HANDLE]
SwitchDesktop.restype = wintypes.BOOL

CloseDesktop = user32.CloseDesktop
CloseDesktop.argtypes = [wintypes.HANDLE]
CloseDesktop.restype = wintypes.BOOL


@dataclass
class SessionSnapshot:
    session_id: str
    username: str
    domain: Optional[str]
    session_type: str
    state: str
    reason: str
    connect_state: Optional[int]
    connect_state_name: Optional[str]
    protocol_type: Optional[int]


def _query_session_buffer(session_id: int, info_class: int) -> Optional[ctypes.c_void_p]:
    buffer = ctypes.c_void_p()
    bytes_returned = wintypes.DWORD()
    success = WTSQuerySessionInformationW(
        WTS_CURRENT_SERVER_HANDLE,
        session_id,
        info_class,
        ctypes.byref(buffer),
        ctypes.byref(bytes_returned),
    )
    if not success:
        return None
    return buffer


def _query_session_string(session_id: int, info_class: int) -> Optional[str]:
    buffer = _query_session_buffer(session_id, info_class)
    if not buffer:
        return None
    try:
        value = ctypes.wstring_at(buffer)
        return value or None
    finally:
        WTSFreeMemory(buffer)


def _query_session_u32(session_id: int, info_class: int) -> Optional[int]:
    buffer = _query_session_buffer(session_id, info_class)
    if not buffer:
        return None
    try:
        return ctypes.cast(buffer, ctypes.POINTER(wintypes.DWORD)).contents.value
    finally:
        WTSFreeMemory(buffer)


def _query_session_u16(session_id: int, info_class: int) -> Optional[int]:
    buffer = _query_session_buffer(session_id, info_class)
    if not buffer:
        return None
    try:
        return ctypes.cast(buffer, ctypes.POINTER(wintypes.USHORT)).contents.value
    finally:
        WTSFreeMemory(buffer)


def get_current_session_id() -> Optional[int]:
    session_id = wintypes.DWORD()
    success = ProcessIdToSessionId(os.getpid(), ctypes.byref(session_id))
    if success:
        return int(session_id.value)
    return None


def get_session_type(protocol_type: Optional[int]) -> str:
    if protocol_type == 2:
        return "rdp"
    if protocol_type == 0:
        return "console"
    return "interactive"


def is_input_desktop_locked() -> bool:
    handle = OpenInputDesktop(0, False, DESKTOP_SWITCHDESKTOP)
    if not handle:
        return True
    try:
        return not bool(SwitchDesktop(handle))
    finally:
        CloseDesktop(handle)


def _classify_state(username: str, connect_state: Optional[int], locked: bool):
    if not username or username == "unknown":
        return "no_session", "no-user"

    if connect_state == WTS_DISCONNECTED:
        return "disconnected", "wts-disconnected"

    if connect_state in (WTS_ACTIVE, WTS_CONNECTED, None):
        if locked:
            return "locked", "workstation-lock"
        return "active", "interactive"

    if connect_state in (WTS_IDLE, WTS_CONNECT_QUERY, WTS_SHADOW, WTS_RESET):
        return "logged_in", "session-present"

    if connect_state in (WTS_LISTEN, WTS_DOWN, WTS_INIT):
        return "no_session", "session-unavailable"

    return "logged_in", "session-present"


def get_current_session_snapshot() -> SessionSnapshot:
    session_id = get_current_session_id()
    session_id_str = str(session_id) if session_id is not None else "unknown"

    username = None
    domain = None
    connect_state = None
    protocol_type = None

    if session_id is not None:
        username = _query_session_string(session_id, WTS_USER_NAME)
        domain = _query_session_string(session_id, WTS_DOMAIN_NAME)
        connect_state = _query_session_u32(session_id, WTS_CONNECT_STATE)
        protocol_type = _query_session_u16(session_id, WTS_CLIENT_PROTOCOL_TYPE)

    username = username or os.environ.get("USERNAME") or getpass.getuser() or "unknown"
    domain = domain or os.environ.get("USERDOMAIN")
    locked = False
    if connect_state in (None, WTS_ACTIVE, WTS_CONNECTED):
        locked = is_input_desktop_locked()

    state, reason = _classify_state(username, connect_state, locked)

    return SessionSnapshot(
        session_id=session_id_str,
        username=username,
        domain=domain,
        session_type=get_session_type(protocol_type),
        state=state,
        reason=reason,
        connect_state=connect_state,
        connect_state_name=CONNECT_STATE_NAMES.get(connect_state),
        protocol_type=protocol_type,
    )
