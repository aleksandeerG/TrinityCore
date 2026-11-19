"""Launcher lifecycle adapter for the existing source-built server."""
import argparse
import time
from urllib.error import URLError

from bootstrap import port_open
from manage import command, running, start, stop


def world_ready():
    if not all(port_open(port) for port in (1119, 8081, 8085, 7878)):
        return False
    try:
        response = command("server info")
    except (URLError, TimeoutError):
        return False
    return "Fault" not in response and "server uptime" in response.lower()


def show_status():
    if not (running("worldserver") or running("bnetserver") or port_open(3317)):
        print("Server stopped.")
    elif running("worldserver") and running("bnetserver") and world_ready():
        print("Server ready.")
    else:
        print("Server is starting or some services are stopped.")


def start_ready():
    start()
    print("Loading the local world. Please wait for 'Server ready'.", flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        if not running("worldserver") or not running("bnetserver"):
            raise RuntimeError("A server process exited during startup. Inspect server/logs before retrying.")
        # SOAP is dispatched on the world thread after initialization.
        if world_ready():
            print("Server ready.", flush=True)
            return
        time.sleep(1)
    raise RuntimeError("Server startup did not finish within ten minutes; inspect server/logs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("start", "stop", "restart", "status"))
    action = parser.parse_args().action
    if action == "status":
        show_status()
    if action in ("stop", "restart"):
        stop()
    if action in ("start", "restart"):
        start_ready()
