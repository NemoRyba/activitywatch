from aw_watcher_audio.state import (
    EndpointLevel,
    active_roles,
    activity_state,
    clamp_threshold,
    max_peak,
    parse_roles,
)


def test_activity_state_reports_no_device_without_levels():
    assert activity_state([], 0.01) == "no_device"


def test_activity_state_reports_active_above_threshold():
    levels = [EndpointLevel(flow="playback", role="console", peak=0.02)]
    assert activity_state(levels, 0.01) == "active"


def test_activity_state_reports_silent_below_threshold():
    levels = [EndpointLevel(flow="microphone", role="communications", peak=0.01)]
    assert activity_state(levels, 0.03) == "silent"


def test_max_peak_clamps_values():
    levels = [
        EndpointLevel(flow="playback", role="console", peak=-1.0),
        EndpointLevel(flow="playback", role="multimedia", peak=2.0),
    ]
    assert max_peak(levels) == 1.0


def test_active_roles_returns_roles_above_threshold_once():
    levels = [
        EndpointLevel(flow="playback", role="console", peak=0.02),
        EndpointLevel(flow="playback", role="console", peak=0.03),
        EndpointLevel(flow="playback", role="communications", peak=0.0),
    ]
    assert active_roles(levels, 0.01) == ["console"]


def test_clamp_threshold():
    assert clamp_threshold(-1) == 0.0
    assert clamp_threshold(2) == 1.0


def test_parse_roles():
    assert parse_roles("media,comms,console,unknown,media") == [
        "multimedia",
        "communications",
        "console",
    ]

