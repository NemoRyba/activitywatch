import sys

import pytest

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")

if sys.platform == "win32":
    from aw_watcher_session.windows import (
        WTS_ACTIVE,
        WTS_DISCONNECTED,
        WTS_SESSIONSTATE_LOCK,
        WTS_SESSIONSTATE_UNKNOWN,
        WTS_SESSIONSTATE_UNLOCK,
        _classify_state,
        resolve_lock_state,
        session_flags_to_locked,
    )


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")
def test_session_flags_to_locked_normal_mapping():
    assert session_flags_to_locked(WTS_SESSIONSTATE_LOCK) is True
    assert session_flags_to_locked(WTS_SESSIONSTATE_UNLOCK) is False
    assert session_flags_to_locked(WTS_SESSIONSTATE_UNKNOWN) is None
    assert session_flags_to_locked(None) is None


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")
def test_session_flags_to_locked_reversed_mapping():
    assert session_flags_to_locked(WTS_SESSIONSTATE_LOCK, reverse=True) is False
    assert session_flags_to_locked(WTS_SESSIONSTATE_UNLOCK, reverse=True) is True


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")
def test_resolve_lock_state_prefers_session_flags():
    locked, source = resolve_lock_state(WTS_SESSIONSTATE_LOCK, False)
    assert locked is True
    assert source == "wts-session-flags"


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")
def test_resolve_lock_state_falls_back_to_desktop():
    locked, source = resolve_lock_state(None, True)
    assert locked is True
    assert source == "input-desktop"


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only watcher")
def test_classify_state_locked_and_disconnected():
    assert _classify_state("Stepik", WTS_ACTIVE, True) == (
        "locked",
        "workstation-lock",
    )
    assert _classify_state("Stepik", WTS_DISCONNECTED, False) == (
        "disconnected",
        "wts-disconnected",
    )
