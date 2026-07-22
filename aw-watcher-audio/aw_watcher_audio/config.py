import argparse
import sys

from aw_core.config import load_config_toml

default_config = """
[aw-watcher-audio]
poll_time = 10
heartbeat_time = 30
playback_threshold = 0.01
microphone_threshold = 0.03
include_levels = false
roles = "console,multimedia,communications"
central_mode = false
username = ""
device_id = ""
device_name = ""
session_id = ""
session_type = ""

[aw-watcher-audio-testing]
poll_time = 2
heartbeat_time = 5
playback_threshold = 0.01
microphone_threshold = 0.03
include_levels = false
roles = "console,multimedia,communications"
central_mode = false
username = ""
device_id = ""
device_name = ""
session_id = ""
session_type = ""
""".strip()


def load_config(testing: bool):
    section = "aw-watcher-audio" + ("-testing" if testing else "")
    return load_config_toml("aw-watcher-audio", default_config)[section]


def parse_args():
    testing = "--testing" in sys.argv
    config = load_config(testing)

    parser = argparse.ArgumentParser(
        description="A lightweight Windows audio activity watcher for ActivityWatch."
    )
    parser.add_argument("--host", dest="host")
    parser.add_argument("--port", dest="port")
    parser.add_argument("--testing", dest="testing", action="store_true")
    parser.add_argument(
        "--central-mode",
        dest="central_mode",
        action="store_true",
        default=config["central_mode"],
        help="Use richer bucket IDs and metadata for centralized multi-user collection.",
    )
    parser.add_argument("--username", dest="username", default=config["username"])
    parser.add_argument("--device-id", dest="device_id", default=config["device_id"])
    parser.add_argument("--device-name", dest="device_name", default=config["device_name"])
    parser.add_argument("--session-id", dest="session_id", default=config["session_id"])
    parser.add_argument(
        "--session-type", dest="session_type", default=config["session_type"]
    )
    parser.add_argument(
        "--poll-time",
        dest="poll_time",
        type=float,
        default=config["poll_time"],
        help="Seconds between local audio samples.",
    )
    parser.add_argument(
        "--heartbeat-time",
        dest="heartbeat_time",
        type=float,
        default=config["heartbeat_time"],
        help="Maximum seconds between heartbeats when audio state is unchanged.",
    )
    parser.add_argument(
        "--playback-threshold",
        dest="playback_threshold",
        type=float,
        default=config["playback_threshold"],
        help="Endpoint peak threshold for playback active state, 0.0 to 1.0.",
    )
    parser.add_argument(
        "--microphone-threshold",
        dest="microphone_threshold",
        type=float,
        default=config["microphone_threshold"],
        help="Endpoint peak threshold for microphone active state, 0.0 to 1.0.",
    )
    parser.add_argument(
        "--include-levels",
        dest="include_levels",
        action="store_true",
        default=config["include_levels"],
        help="Include rounded peak levels in events. Disabled by default to reduce churn.",
    )
    parser.add_argument(
        "--roles",
        dest="roles",
        default=config["roles"],
        help="Comma-separated default endpoint roles to sample: console,multimedia,communications.",
    )
    parser.add_argument("--verbose", dest="verbose", action="store_true")
    return parser.parse_args()

