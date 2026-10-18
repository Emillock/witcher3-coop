# Game-free test of w3relay over the mock Steam DLL: echo "server" <- host relay <~mock steam~> join relay <- client.
# Also checks that a mock user who is not in the lobby cannot reach the server. Prints RESULT: PASS/FAIL.
import ctypes
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
SERVER_PORT, LOCAL_PORT = 42000, 42100


def relay_dir(root, name):
    d = os.path.join(root, name)
    os.makedirs(d)
    shutil.copy2(os.path.join(BUILD, "w3relay.exe"), d)
    shutil.copy2(os.path.join(BUILD, "mock", "steam_api64.dll"), d)
    return d


def start_relay(d, mock_dir, steam_id, name, args):
    env = dict(os.environ, MOCK_STEAM_DIR=mock_dir, MOCK_STEAM_ID=str(steam_id), MOCK_STEAM_NAME=name)
    log = open(os.path.join(d, "relay.log"), "w")
    return subprocess.Popen([os.path.join(d, "w3relay.exe")] + args, cwd=d, env=env, stdout=log,
                            stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)


def echo_server(stop, seen):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", SERVER_PORT))
    s.settimeout(0.2)
    while not stop.is_set():
        try:
            data, addr = s.recvfrom(65536)
        except socket.timeout:
            continue
        seen.append(data)
        s.sendto(b"echo:" + data, addr)
    s.close()


def main():
    root = tempfile.mkdtemp(prefix="w3relay-test-")
    mock_dir = os.path.join(root, "mocksteam")
    os.makedirs(mock_dir)
    stop, seen = threading.Event(), []
    threading.Thread(target=echo_server, args=(stop, seen), daemon=True).start()
    host = start_relay(relay_dir(root, "host"), mock_dir, 1001, "Host", ["host", "--server-port", str(SERVER_PORT), "--no-invite"])
    time.sleep(1.5)
    join = start_relay(relay_dir(root, "join"), mock_dir, 1002, "Friend", ["join", "--local-port", str(LOCAL_PORT)])
    # the game connects late (still loading) - longer than the relays' 20 s silence timeout
    time.sleep(25)

    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.settimeout(0.3)
    replies = set()
    deadline = time.time() + 20
    i = 0
    while time.time() < deadline and len(replies) < 20:
        client.sendto(b"pkt%d" % i, ("127.0.0.1", LOCAL_PORT))
        i += 1
        try:
            data, _ = client.recvfrom(65536)
            replies.add(data)
        except (socket.timeout, ConnectionResetError):
            pass

    # negative control: a stranger (not in the lobby) messages the host directly through the mock
    stranger = os.path.join(root, "stranger")
    os.makedirs(stranger)
    shutil.copy2(os.path.join(BUILD, "mock", "steam_api64.dll"), stranger)
    os.environ.update(MOCK_STEAM_DIR=mock_dir, MOCK_STEAM_ID="1003", MOCK_STEAM_NAME="Stranger")
    mock = ctypes.CDLL(os.path.join(stranger, "steam_api64.dll"))
    err = ctypes.create_string_buffer(1024)
    mock.SteamAPI_InitFlat(err)
    identity = ctypes.create_string_buffer(136)
    mock.SteamAPI_SteamNetworkingIdentity_SetSteamID64(identity, ctypes.c_uint64(1001))
    before = len(seen)
    for _ in range(20):
        mock.SteamAPI_ISteamNetworkingMessages_SendMessageToUser(None, identity, b"INTRUDER", 8, 0, 0)
        time.sleep(0.05)
    time.sleep(1.5)
    intruder_got_through = any(b"INTRUDER" in d for d in seen[before:])

    for p in (join, host):
        p.send_signal(subprocess.signal.CTRL_BREAK_EVENT)
    time.sleep(2)
    for p in (join, host):
        if p.poll() is None:
            p.kill()
    stop.set()
    logs = {n: open(os.path.join(root, n, "relay.log")).read() for n in ("host", "join")}
    for n, text in logs.items():
        print(f"--- {n} relay ---\n{text.strip()}")

    ok = len(replies) >= 20 and all(r.startswith(b"echo:pkt") for r in replies)
    print(f"echoed {len(replies)} distinct packets through the relays; intruder reached server: {intruder_got_through}")
    passed = ok and not intruder_got_through and "flowing" in logs["join"]
    print("RESULT: " + ("PASS" if passed else "FAIL"))
    shutil.rmtree(root, ignore_errors=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
