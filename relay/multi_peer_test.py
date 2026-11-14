# One host and two guests over mock Steam, without Java or the game.
import contextlib
import os
import select
import socket
import sys
import tempfile
import time
from pathlib import Path

from selftest import relay_dir, start_relay


def udp_socket():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    return s


def wait_for_log(process, directory, marker):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"{directory}: relay exited with {process.returncode}")
        log = (Path(directory) / "relay.log").read_text(encoding="utf-8", errors="replace")
        if marker in log:
            return
        time.sleep(0.05)
    raise RuntimeError(f"{directory}: did not log {marker!r}")


def stop_relay(process):
    if process.poll() is None:
        process.kill()
    process.wait(timeout=5)


def exchange(server, clients, rounds=20, timeout=20):
    """Every client gets only its own echo; the server sees one UDP endpoint per player.

    clients maps a player name (bytes) to (game socket, destination address).
    Send each round to all players before reading any replies. Retry lost datagrams.
    """
    names = {s: name for name, (s, _) in clients.items()}
    endpoints = {}
    deadline = time.monotonic() + timeout
    for seq in range(rounds):
        pending = set(clients)
        next_send = 0
        while pending:
            now = time.monotonic()
            if now >= deadline:
                raise RuntimeError(f"round {seq}: no echo for {sorted(pending)}")
            if now >= next_send:
                for name in pending:
                    s, dest = clients[name]
                    s.sendto(name + b":" + str(seq).encode(), dest)
                next_send = now + 0.15
            readable, _, _ = select.select([server, *names], [], [], 0.05)
            for s in readable:
                data, addr = s.recvfrom(65536)
                if s == server:
                    name = data.split(b":", 1)[0]
                    if name not in clients:
                        raise RuntimeError(f"unexpected server payload {data!r}")
                    if name in endpoints and endpoints[name] != addr:
                        raise RuntimeError(f"{name!r} changed server endpoint")
                    if any(other != name and endpoint == addr for other, endpoint in endpoints.items()):
                        raise RuntimeError(f"{name!r} shares a server endpoint with another player")
                    endpoints[name] = addr
                    server.sendto(b"echo:" + data, addr)
                else:
                    name = names[s]
                    if not data.startswith(b"echo:" + name + b":"):
                        raise RuntimeError(f"{name!r} received another player's data: {data!r}")
                    if data == b"echo:" + name + b":" + str(seq).encode():
                        pending.discard(name)
    if set(endpoints) != set(clients):
        raise RuntimeError(f"missing server endpoints: {endpoints}")
    return endpoints


def main():
    with tempfile.TemporaryDirectory(prefix="w3relay-multi-") as root, contextlib.ExitStack() as stack:
        mock_dir = os.path.join(root, "mocksteam")
        os.makedirs(mock_dir)
        server = stack.enter_context(udp_socket())
        local_game = stack.enter_context(udp_socket())
        # Reserve two distinct ports until their join relays are ready to bind them.
        reserved = [stack.enter_context(udp_socket()) for _ in range(2)]
        dirs = []

        def launch(name, steam_id, args):
            d = relay_dir(root, name)
            dirs.append(d)
            process = start_relay(d, mock_dir, steam_id, name, args)
            stack.callback(stop_relay, process)
            return process, d

        try:
            host, d = launch("Host", 1001, ["host", "--server-port", str(server.getsockname()[1]), "--no-invite"])
            wait_for_log(host, d, "Lobby ready:")
            clients = {b"host": (local_game, server.getsockname())}
            for i, reservation in enumerate(reserved, 1):
                port = reservation.getsockname()[1]
                reservation.close()
                guest, d = launch(f"Guest{i}", 1001 + i, ["join", "--local-port", str(port)])
                # Join in sequence; the mock stores membership in a shared file.
                wait_for_log(guest, d, "Joined ")
                clients[f"guest{i}".encode()] = (stack.enter_context(udp_socket()), ("127.0.0.1", port))
            endpoints = exchange(server, clients)
            print(f"20 echoes per player, distinct server endpoints: {endpoints}")
            print("RESULT: PASS")
            return 0
        except (OSError, RuntimeError) as exc:
            print(f"FAIL: {exc}")
            print("RESULT: FAIL")
            return 1
        finally:
            for d in dirs:
                print(f"--- {Path(d).name} relay ---")
                log = Path(d) / "relay.log"
                if log.exists():
                    print(log.read_text(encoding="utf-8", errors="replace"))


if __name__ == "__main__":
    sys.exit(main())
