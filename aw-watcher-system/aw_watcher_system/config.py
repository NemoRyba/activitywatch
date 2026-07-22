import argparse
import sys

from aw_core.config import load_config_toml

default_config = """
[aw-watcher-system]
poll_time = 60
central_mode = false
username = ""
device_id = ""
device_name = ""
session_id = ""
session_type = ""

[aw-watcher-system-testing]
poll_time = 2
central_mode = false
username = ""
device_id = ""
device_name = ""
session_id = ""
session_type = ""
""".strip()


def load_config(testing: bool):
    section = "aw-watcher-system" + ("-testing" if testing else "")
    return load_config_toml("aw-watcher-system", default_config)[section]


def parse_args():
    testing = "--testing" in sys.argv
    config = load_config(testing)

    parser = argparse.ArgumentParser(
        description="A lightweight Windows system metrics watcher for ActivityWatch."
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
        help="Seconds between CPU samples.",
    )
    parser.add_argument("--verbose", dest="verbose", action="store_true")
    return parser.parse_args()
