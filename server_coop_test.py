# Checks the Witcher Online server's COOP channel without the game: two fake UDP clients store co-op state,
# the server rebroadcasts each player's latest value per channel to everyone, and ignores channels past the limit.
# Usage: server_coop_test.py [--port 41900]
import argparse
import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import WO  # noqa: E402

JAR = os.path.join(WO, "server", "build", "WitcherServer.jar")


def client(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("127.0.0.1", port))
    s.settimeout(0.2)
    return s


def send(s, *fields):
    s.send("\t".join(fields).encode())


def collect(s, seconds):
    """Latest COOP fields per (sender, channel) seen within `seconds`."""
    latest = {}
    end = time.time() + seconds
    while time.time() < end:
        try:
            parts = s.recv(65536).decode().split("\t")
        except socket.timeout:
            continue
        if parts[0] == "COOP" and len(parts) >= 4:
            latest[(parts[2], parts[3])] = parts[3:]
    return latest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=41900)
    a = ap.parse_args()

    server = subprocess.Popen(["java", "-jar", JAR, str(a.port)], cwd=os.path.dirname(JAR),
                              stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    failures = []
    try:
        time.sleep(2)
        alice, bob = client(a.port), client(a.port)

        send(alice, "COOP", "Alice", "en", "7", "1", "0")
        send(bob, "COOP", "Bob", "hit", "Alice", "7", "1")
        got = collect(bob, 1.0)
        if got.get(("Alice", "en")) != ["en", "7", "1", "0"]:
            failures.append(f"Bob did not get Alice's 'en' state: {got}")
        if got.get(("Bob", "hit")) != ["hit", "Alice", "7", "1"]:
            failures.append(f"Bob did not get his own 'hit' state back: {got}")
        if ("Bob", "hit") not in collect(alice, 1.0):
            failures.append("Alice did not get Bob's 'hit' state")

        # a newer value replaces the stored one
        send(alice, "COOP", "Alice", "en", "7", "2", "0")
        if collect(bob, 1.0).get(("Alice", "en")) != ["en", "7", "2", "0"]:
            failures.append("Alice's updated 'en' state did not replace the old one")

        # at most 8 channels per player, names up to 8 characters
        for channel in ("c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "toolongname"):
            send(alice, "COOP", "Alice", channel, "x")
        channels = sorted(ch for (who, ch) in collect(bob, 1.0) if who == "Alice")
        if len(channels) != 8 or "toolongname" in channels or "en" not in channels:
            failures.append(f"channel limit not applied: Alice's channels {channels}")

        # the old opcodes still work next to COOP
        send(alice, "MOVE", "Alice", "1", "0", "0", "0", "1", "0", "0", "0")
        seen_move = False
        end = time.time() + 1.0
        while time.time() < end and not seen_move:
            try:
                seen_move = bob.recv(65536).decode().startswith("MOVE\t")
            except socket.timeout:
                pass
        if not seen_move:
            failures.append("MOVE was not relayed")

        # a busy fight's snapshot is larger than 8 KB: it arrives whole (last: its rebroadcasts fill the sockets)
        big = "x" * 20000
        send(alice, "COOP", "Alice", "en", "7", "3", big)
        if collect(bob, 1.0).get(("Alice", "en")) != ["en", "7", "3", big]:
            failures.append("a 20 KB 'en' state did not arrive whole")
    finally:
        try:
            server.stdin.write(b"stop\n")
            server.stdin.flush()
            server.wait(5)
        except (OSError, subprocess.TimeoutExpired):
            server.kill()

    for f in failures:
        print("FAIL", f)
    print("RESULT:", "FAIL" if failures else "PASS")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
