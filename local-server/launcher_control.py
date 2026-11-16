"""Launcher lifecycle adapter for the existing source-built server; never installs a repack."""
import argparse
import time

from bootstrap import port_open
from manage import command, running, start, stop


def start_ready():
    start()
    print("Loading the local world. Please wait for 'Server ready'.", flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        if not running("worldserver") or not running("bnetserver"):
            raise RuntimeError("A server process exited during startup. Inspect server/logs before retrying.")
        if all(port_open(port) for port in (1119, 8081, 8085, 7878)):
            # SOAP is dispatched on the world thread, so a successful reply proves
            # initialization is complete, rather than only that a socket was bound.
            response = command("server info")
            if "Fault" in response or "server uptime" not in response.lower():
                raise RuntimeError("The world opened its ports but did not pass the readiness check.")
            print("Server ready. You can press PLAY NOW.", flush=True)
            return
        time.sleep(1)
    raise RuntimeError("Server startup did not finish within ten minutes; inspect server/logs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("start", "stop", "restart"))
    action = parser.parse_args().action
    if action in ("stop", "restart"):
        stop()
    if action in ("start", "restart"):
        start_ready()
