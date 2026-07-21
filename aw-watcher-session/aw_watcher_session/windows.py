import ctypes
import getpass
import os
import sys
from dataclasses import dataclass
from ctypes import wintypes
from typing import Optional

WTS_CURRENT_SERVER_HANDLE = wintypes.HANDLE(0)

WTS_USER_NAME = 5
WTS_DOMAIN_NAME = 7
WTS_CONNECT_STATE = 8
WTS_CLIENT_PROTOCOL_TYPE = 16
WTS_SESSION_INFO_EX = 25

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

WTS_SESSIONSTATE_LOCK = 0
WTS_SESSIONSTATE_UNLOCK = 1
WTS_SESSIONSTATE_UNKNOWN = ctypes.c_long(0xFFFFFFFF).value

WINSTATIONNAME_LENGTH = 32
USERNAME_LENGTH = 20
DOMAIN_LENGTH = 17

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


class LARGE_INTEGER(ctypes.Structure):
    _fields_ = [("QuadPart", ctypes.c_longlong)]


class WTSINFOEX_LEVEL1_W(ctypes.Structure):
    _fields_ = [
        ("SessionId", wintypes.ULONG),
        ("SessionState", wintypes.DWORD),
        ("SessionFlags", wintypes.LONG),
        ("WinStationName", wintypes.WCHAR * (WINSTATIONNAME_LENGTH + 1)),
        ("UserName", wintypes.WCHAR * (USERNAME_LENGTH + 1)),
        ("DomainName", wintypes.WCHAR * (DOMAIN_LENGTH + 1)),
        ("LogonTime", LARGE_INTEGER),
        ("ConnectTime", LARGE_INTEGER),
        ("DisconnectTime", LARGE_INTEGER),
        ("LastInputTime", LARGE_INTEGER),
        ("CurrentTime", LARGE_INTEGER),
        ("IncomingBytes", wintypes.DWORD),
        ("OutgoingBytes", wintypes.DWORD),
        ("IncomingFrames", wintypes.DWORD),
        ("OutgoingFrames", wintypes.DWORD),
        ("IncomingCompressedBytes", wintypes.DWORD),
        ("OutgoingCompressedBytes", wintypes.DWORD),
    ]


class WTSINFOEX_LEVEL_W(ctypes.Union):
    _fields_ = [("WTSInfoExLevel1", WTSINFOEX_LEVEL1_W)]


class WTSINFOEXW(ctypes.Structure):
    _fields_ = [("Level", wintypes.DWORD), ("Data", WTSINFOEX_LEVEL_W)]


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
    session_flags: Optional[int]
    lock_source: Optional[str]


@dataclass
class SessionInfoEx:
    session_state: int
    session_flags: int
    username: Optional[str]
    domain: Optional[str]


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


def _query_session_info_ex(session_id: int) -> Optional[SessionInfoEx]:
    buffer = _query_session_buffer(session_id, WTS_SESSION_INFO_EX)
    if not buffer:
        return None
    try:
        info = ctypes.cast(buffer, ctypes.POINTER(WTSINFOEXW)).contents
        if info.Level != 1:
            return None
        level1 = info.Data.WTSInfoExLevel1
        return SessionInfoEx(
            session_state=int(level1.SessionState),
            session_flags=int(level1.SessionFlags),
            username=level1.UserName or None,
            domain=level1.DomainName or None,
        )
    finally:
        WTSFreeMemory(buffer)


def get_session_type(protocol_type: Optional[int]) -> str:
    if protocol_type == 2:
        return "rdp"
    if protocol_type == 0:
        return "console"
    return "interactive"


def session_flags_to_locked(session_flags: Optional[int], *, reverse: bool = False):
    if session_flags is None or session_flags == WTS_SESSIONSTATE_UNKNOWN:
        return None
    if session_flags == WTS_SESSIONSTATE_LOCK:
        return not reverse
    if session_flags == WTS_SESSIONSTATE_UNLOCK:
        return reverse
    return None


def resolve_lock_state(
    session_flags: Optional[int],
    desktop_locked: Optional[bool],
    *,
    session_flags_reversed: bool = False,
):
    locked = session_flags_to_locked(
        session_flags, reverse=session_flags_reversed
    )
    if locked is not None:
        return locked, "wts-session-flags"
    if desktop_locked is not None:
        return desktop_locked, "input-desktop"
    return False, None


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
    session_flags = None

    if session_id is not None:
        username = _query_session_string(session_id, WTS_USER_NAME)
        domain = _query_session_string(session_id, WTS_DOMAIN_NAME)
        connect_state = _query_session_u32(session_id, WTS_CONNECT_STATE)
        protocol_type = _query_session_u16(session_id, WTS_CLIENT_PROTOCOL_TYPE)
        info_ex = _query_session_info_ex(session_id)
        if info_ex is not None:
            username = username or info_ex.username
            domain = domain or info_ex.domain
            connect_state = (
                connect_state if connect_state is not None else info_ex.session_state
            )
            session_flags = info_ex.session_flags

    username = username or os.environ.get("USERNAME") or getpass.getuser() or "unknown"
    domain = domain or os.environ.get("USERDOMAIN")
    desktop_locked = None
    if connect_state in (None, WTS_ACTIVE, WTS_CONNECTED):
        # SessionFlags is the authoritative lock state on supported Windows versions.
        # The desktop-switch fallback exists for older APIs and edge cases.
        desktop_locked = is_input_desktop_locked()
    session_flags_reversed = (
        sys.getwindowsversion().major == 6 and sys.getwindowsversion().minor == 1
    )
    locked, lock_source = resolve_lock_state(
        session_flags,
        desktop_locked,
        session_flags_reversed=session_flags_reversed,
    )

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
        session_flags=session_flags,
        lock_source=lock_source,
    )
