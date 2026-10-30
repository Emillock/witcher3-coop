# Multi-instance test harness: local Witcher Online server + N game clients driven by the w3test bot.
# Prints RESULT: PASS/FAIL. Only kills processes it started.
# Usage: run_test.py <scenario>[,<scenario>...] [--bots 2] [--duration 60] [--stagger 5] [--timeout 420] [--save SUBSTR]
# Several scenarios separated by commas run as one session: the games load once and the bots go from one scenario to
# the next when the harness says so (control file), cleaning up in between.
import argparse
import ctypes
import os
import re
import shutil
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import WO, WORK  # noqa: E402
from sandbox import make_sandbox  # noqa: E402
from w3run import BITMAPINFOHEADER, EXE, arrange, capture_window, game_window, gdi32, user32, windows_of, wt  # noqa: E402

SERVER_JAR = os.path.join(WO, "server", "build", "WitcherServer.jar")
RUNS = os.path.join(WORK, "runs")
GAME_ARGS = os.environ.get("W3T_GAME_ARGS", "-windowed -width 640 -height 360 -debugscripts -noraytracing").split()


# scenarios where the leader waits for the member to load and join before acting
LONG_SCENARIOS = ("shared_enemy", "enemy_attacks", "handoff", "reactions", "twin_match", "quest_sync", "dialog_sync",
                  "facts_sync", "puppet_follow", "puppet_walk", "puppet_glide", "enemy_moves", "enemy_summons", "enemy_spells", "real_encounter",
                  "enemy_projectiles", "member_combat", "enemy_effects", "sign_visuals", "showcase", "attack_view", "member_death", "leader_death", "enemy_crowd", "trade", "encounter_mismatch", "player_effects", "mounted_fight", "party_hud")


def default_duration(scenario):
    return 300 if scenario in LONG_SCENARIOS else 60


def segment(log, scenario):
    # a session's log from where `scenario` started
    i = log.find(f"SCENARIO {scenario} start")
    return log[i:] if i >= 0 else log


def bot_name(i):
    return "Bot" + "ABCDEFGH"[i]


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong)] + \
               [(n, ctypes.c_size_t) for n in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                                               "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                                               "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage",
                                               "PrivateUsage")]


def private_mb(pid):
    handle = ctypes.windll.kernel32.OpenProcess(0x1000 | 0x0010, False, pid)
    if not handle:
        return -1
    counters = PROCESS_MEMORY_COUNTERS_EX()
    counters.cb = ctypes.sizeof(counters)
    ok = ctypes.windll.psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb)
    ctypes.windll.kernel32.CloseHandle(handle)
    return counters.PrivateUsage // (1024 * 1024) if ok else -1


def gpu_used_mb():
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total,utilization.gpu",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10).stdout
        used, total, util = [x.strip() for x in out.splitlines()[0].split(",")]
        return f"{used}/{total} MB, {util}% busy"
    except (OSError, IndexError, ValueError, subprocess.TimeoutExpired):
        return "unknown"


RELAY_BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay", "build")


def start_relay(run_dir, mock_dir, name, steam_id, args):
    """w3relay with the mock steam_api64.dll next to it (one PC can't run two real Steam accounts)."""
    d = os.path.join(run_dir, name)
    os.makedirs(d)
    shutil.copy2(os.path.join(RELAY_BUILD, "w3relay.exe"), d)
    shutil.copy2(os.path.join(RELAY_BUILD, "mock", "steam_api64.dll"), d)
    env = dict(os.environ, MOCK_STEAM_DIR=mock_dir, MOCK_STEAM_ID=str(steam_id), MOCK_STEAM_NAME=name)
    return subprocess.Popen([os.path.join(d, "w3relay.exe")] + args, cwd=d, env=env,
                            stdout=open(os.path.join(d, "relay.log"), "w"), stderr=subprocess.STDOUT,
                            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)


SANDBOXIE_START = os.environ.get("SANDBOXIE_START", r"C:\Program Files\Sandboxie-Plus\Start.exe")


def relay_dir(run_dir, name):
    """A relay copy with the game's real steam_api64.dll next to it."""
    d = os.path.join(run_dir, name)
    os.makedirs(d)
    shutil.copy2(os.path.join(RELAY_BUILD, "w3relay.exe"), d)
    shutil.copy2(os.path.join(os.path.dirname(EXE), "steam_api64.dll"), d)
    return d


def wait_log(path, pattern, limit):
    deadline = time.time() + limit
    while time.time() < deadline:
        if os.path.exists(path):
            m = re.search(pattern, open(path, encoding="utf-8", errors="replace").read())
            if m:
                return m
        time.sleep(1)
    return None


def start_real_host(run_dir, port):
    """Host relay on this PC's own Steam; returns (process, lobby id or None)."""
    d = relay_dir(run_dir, "relay-host")
    proc = subprocess.Popen([os.path.join(d, "w3relay.exe"), "host", "--server-port", str(port), "--no-invite"], cwd=d,
                            stdout=open(os.path.join(d, "relay.log"), "w"), stderr=subprocess.STDOUT,
                            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    m = wait_log(os.path.join(d, "relay.log"), r"Lobby ready: (\d+)", 45)
    return proc, (m.group(1) if m else None)


def start_boxed_join(run_dir, box, name, lobby, local_port):
    """Joiner relay inside a Sandboxie box whose Steam is logged in to a second account. The box may write only
    under work\\runs, so the relay runs from there and logs to a file."""
    d = relay_dir(run_dir, name)
    exe, log = os.path.join(d, "w3relay.exe"), os.path.join(d, "relay.log")
    with open(os.path.join(d, "run.cmd"), "w") as f:
        f.write(f'@"{exe}" join --lobby {lobby} --local-port {local_port} > "{log}" 2>&1\n')
    subprocess.run([SANDBOXIE_START, f"/box:{box}", "cmd.exe", "/c", os.path.join(d, "run.cmd")], check=True)
    return wait_log(log, r"Joined .*'s game", 60) is not None


def stop_boxed_relays(run_dir):
    """Stops only the relay copies under this run (closing the whole box would also close its Steam)."""
    pattern = os.path.join(run_dir, "relay-*", "w3relay.exe").replace("/", "\\")
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    f"Get-CimInstance Win32_Process -Filter \"Name='w3relay.exe'\" | Where-Object {{ $_.ExecutablePath -like '{pattern}' }}"
                    " | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"], timeout=60)


def wait_in_world(log_path, limit, t0, procs):
    """Waits until a bot's log shows it reached the world (or `limit` seconds)."""
    deadline = time.time() + limit
    while time.time() < deadline:
        arrange([p.pid for p in procs])
        if os.path.exists(log_path):
            text = open(log_path, encoding="utf-8", errors="replace").read()
            if "BOT start" in text or " QUIT " in text:
                print(f"[{time.time() - t0:6.1f}s] {os.path.basename(log_path)[:-4]} is in the world", flush=True)
                return
        time.sleep(2)


def last_stride(log, marker):
    found = re.findall(re.escape(marker) + r".* stride=([0-9.]+)", log)
    return float(found[-1]) if found else 0.0


def shoot(run_dir, procs, a, stop):
    # both bots' windows every a.shots seconds, in a thread of its own so the 1 s main loop doesn't limit the rate;
    # with --shots-from, from that line in the first bot's log on, for --shots-for seconds
    os.makedirs(os.path.join(run_dir, "shots"), exist_ok=True)
    first = os.path.join(run_dir, bot_name(0) + ".log")
    start = None if a.shots_from else time.time()
    hwnds = {}
    while not stop.wait(a.shots):
        if start is None:
            if os.path.exists(first) and a.shots_from in open(first, encoding="utf-8", errors="replace").read():
                start = time.time()
            continue
        if a.shots_for and time.time() - start > a.shots_for:
            return
        stamp = time.strftime("%H%M%S") + f"_{int(time.time() * 100) % 100:02d}"
        for i, p in enumerate(procs):
            # finding the window walks every window on the desktop: once, again only if a capture fails
            hwnd = hwnds.get(i) or game_window(p.pid)
            hwnds[i] = hwnd
            if hwnd and not capture_window(hwnd, os.path.join(run_dir, "shots", f"{stamp}_{bot_name(i)}.png"), fast=a.shots < 1):
                hwnds[i] = None


def record(run_dir, procs, a, stop, fps=30):
    # films both bots' windows side by side, from --record-from in the first bot's log on, for --record seconds. Frames
    # are copied from the screen as the screenshots are (BitBlt without CAPTUREBLT; ffmpeg's gdigrab adds it, which
    # slowed both games to 5% speed) and piped to ffmpeg, which only encodes. A late copy repeats the last frame, so the
    # video keeps real time. The windows stay on top meanwhile.
    first = os.path.join(run_dir, bot_name(0) + ".log")
    while not (os.path.exists(first) and a.record_from in open(first, encoding="utf-8", errors="replace").read()):
        if stop.wait(0.5):
            return
    hwnds = [game_window(p.pid) for p in procs]
    rects = []
    for hwnd in hwnds:
        r = wt.RECT()
        user32.GetClientRect(hwnd, ctypes.byref(r))
        at = wt.POINT(0, 0)
        user32.ClientToScreen(hwnd, ctypes.byref(at))
        rects.append((at.x, at.y, (r.right - r.left) // 2 * 2, (r.bottom - r.top) // 2 * 2))  # even, for yuv420p
        user32.SetWindowPos(hwnd, wt.HWND(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010)  # TOPMOST; NOSIZE|NOMOVE|NOACTIVATE
    width, height = sum(r[2] for r in rects), max(r[3] for r in rects)
    screen = user32.GetDC(None)
    mem = gdi32.CreateCompatibleDC(screen)
    bmp = gdi32.CreateCompatibleBitmap(screen, width, height)
    old = gdi32.SelectObject(mem, bmp)
    header = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
    pixels = ctypes.create_string_buffer(width * height * 4)
    out = os.path.join(run_dir, "video.mp4")
    log = open(os.path.join(run_dir, "ffmpeg.log"), "w")
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "warning", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", f"{width}x{height}",
                           "-r", str(fps), "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", out],
                          stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
    print(f"recording {out}", flush=True)
    t0, frames, copies = time.time(), 0, 0
    try:
        while time.time() - t0 < a.record:
            x = 0
            for sx, sy, w, h in rects:
                gdi32.BitBlt(mem, x, 0, w, h, screen, sx, sy, 0x00CC0020)  # SRCCOPY
                x += w
            gdi32.GetDIBits(mem, bmp, 0, height, pixels, ctypes.byref(header), 0)
            copies += 1
            frame = pixels.raw
            while frames < int((time.time() - t0) * fps) + 1:
                ff.stdin.write(frame)
                frames += 1
            if stop.wait(max(0.0, t0 + frames / fps - time.time())):
                break
    finally:
        gdi32.SelectObject(mem, old)
        gdi32.DeleteObject(bmp)
        gdi32.DeleteDC(mem)
        user32.ReleaseDC(None, screen)
        ff.stdin.close()
        ff.wait(120)
        for hwnd in hwnds:
            user32.SetWindowPos(hwnd, wt.HWND(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010)  # NOTOPMOST
    print(f"recorded {out}: {frames} frames, {copies} copied ({copies / max(1e-3, time.time() - t0):.1f}/s), "
          f"ffmpeg rc={ff.returncode}", flush=True)


def read_log(run_dir, i):
    path = os.path.join(run_dir, bot_name(i) + ".log")
    return open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else ""


def check(scenario, logs, n):
    # the in-game bot decides pass/fail for its own instance; the harness requires every bot to pass
    reasons = []
    for i in range(n):
        if "PASS condition met" not in logs[i]:
            fail = [l for l in logs[i].splitlines() if " FAIL " in l]
            reasons.append(f"{bot_name(i)}: " + (fail[-1].split(" ", 1)[1] if fail else "no pass (did not finish)"))
    if scenario == "puppet_walk" and not reasons:
        # walking legs: the copy's foot swings like the leader's monster's (a slide alone swings it ~0.1 m)
        leader, copy = last_stride(logs[0], "MOVES leader"), last_stride(logs[1], "FOLLOW member")
        if leader < 0.3 or copy < 0.5 * leader:
            reasons.append(f"stride: leader's monster {leader:.2f} m, member's copy {copy:.2f} m")
        else:
            return True, f"every bot passed '{scenario}'; stride: leader's monster {leader:.2f} m, member's copy {copy:.2f} m"
    return not reasons, "; ".join(reasons) or f"every bot passed '{scenario}'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    ap.add_argument("--bots", type=int, default=2)
    ap.add_argument("--duration", type=int, help="in-game seconds before a bot fails (default 60; enemy scenarios 300)")
    ap.add_argument("--stagger", type=int, default=5, help="seconds between starting the bots")
    ap.add_argument("--serial", action="store_true", help="start each bot only once the one before is in the world "
                                                          "(one loading screen at a time; slower)")
    ap.add_argument("--timeout", type=int, default=420)
    ap.add_argument("--save", default="")
    ap.add_argument("--grace", type=int, default=900, help="seconds a bot stays after passing (the run ends when all pass)")
    ap.add_argument("--port", type=int, default=41000)
    ap.add_argument("--relay", action="store_true", help="bots after the first connect through w3relay (mock Steam)")
    ap.add_argument("--monster", default="", help="puppet scenarios: the leader's monster template (depot path)")
    ap.add_argument("--shots", type=float, default=0, help="save both bots' windows as PNG every this many seconds once all are in the world")
    ap.add_argument("--shots-from", default="", help="start the screenshots when this text appears in the first bot's log")
    ap.add_argument("--shots-for", type=float, default=0, help="stop the screenshots after this many seconds")
    ap.add_argument("--size", default="", help="window and render resolution, e.g. 960x540 (default 640x360)")
    ap.add_argument("--record", type=float, default=0, help="film both bots' windows side by side for this many seconds")
    ap.add_argument("--record-from", default="", help="start filming when this text appears in the first bot's log")
    ap.add_argument("--steam-box", help="real Steam: the host relay uses this PC's Steam, joiner relays run in this "
                                        "Sandboxie box, whose Steam is logged in to a second account")
    a = ap.parse_args()
    if a.steam_box:
        a.relay = True
    game_args = list(GAME_ARGS)
    if a.size:
        os.environ["W3T_RESOLUTION"] = a.size  # sandbox.py writes it into the settings
        for flag, value in zip(("-width", "-height"), a.size.split("x")):
            if flag in game_args:
                game_args[game_args.index(flag) + 1] = value
    session = a.scenario.split(",") if "," in a.scenario else []
    if a.duration is None:
        a.duration = default_duration(a.scenario)

    run_dir = os.path.join(RUNS, time.strftime("%Y%m%d-%H%M%S") + "-" + (f"session{len(session)}" if session else a.scenario)
                           + ("-steam" if a.steam_box else "-relay" if a.relay else "")
                           + ("-" + re.sub(r"\.w2ent$", "", a.monster.split("\\")[-1]) if a.monster else ""))
    os.makedirs(run_dir)
    print(f"run dir: {run_dir}", flush=True)

    server_log = open(os.path.join(run_dir, "server.log"), "w")
    server = subprocess.Popen(["java", "-jar", SERVER_JAR, str(a.port)], cwd=os.path.dirname(SERVER_JAR),
                              stdin=subprocess.PIPE, stdout=server_log, stderr=subprocess.STDOUT)
    time.sleep(2)

    relays = []
    if a.steam_box:
        host, lobby = start_real_host(run_dir, a.port)
        relays.append(host)
        if not lobby:
            print("the host relay did not create a Steam lobby; see relay-host\\relay.log", flush=True)
        for i in range(1, a.bots):
            joined = lobby and start_boxed_join(run_dir, a.steam_box, f"relay-{bot_name(i)}", lobby, a.port + 100 + i)
            print(f"{bot_name(i)}'s relay in box {a.steam_box}: {'joined the lobby' if joined else 'did NOT join'}", flush=True)
    elif a.relay:
        mock_dir = os.path.join(run_dir, "mocksteam")
        os.makedirs(mock_dir)
        relays.append(start_relay(run_dir, mock_dir, "relay-host", 1001, ["host", "--server-port", str(a.port), "--no-invite"]))
        time.sleep(1.5)
        for i in range(1, a.bots):
            relays.append(start_relay(run_dir, mock_dir, f"relay-{bot_name(i)}", 1001 + i,
                                      ["join", "--local-port", str(a.port + 100 + i)]))

    procs = []
    shots_stop = threading.Event()
    recorder = None
    control = os.path.join(run_dir, "control.txt")
    if session:
        open(control, "w").write("go 0")
    results = []  # a session's (scenario, ok, why)
    go_at = time.time()
    t0 = time.time()
    try:
        for i in range(a.bots):
            docs = os.path.join(run_dir, "docs-" + bot_name(i))
            save = make_sandbox(docs, a.save)
            print(f"[{time.time() - t0:6.1f}s] {bot_name(i)} sandbox with save {save}", flush=True)
            env = dict(os.environ, SteamAppId="292030", SteamGameId="292030", W3T_DOCUMENTS=docs,
                       WO_USERNAME=bot_name(i), WO_SERVER_IP="127.0.0.1",
                       WO_SERVER_PORT=str(a.port + 100 + i if a.relay and i > 0 else a.port),
                       W3T_SCENARIO=a.scenario, W3T_DURATION=str(a.duration), W3T_SAVE=a.save,
                       W3T_PEERS=str(a.bots - 1), W3T_ROLE="mover" if i == 0 else "observer",
                       W3T_GRACE=str(a.grace), W3T_MONSTER=a.monster,
                       W3T_LOG=os.path.join(run_dir, bot_name(i) + ".log"))
            if session:
                # the harness times each scenario; the bots never give up by themselves
                env.update(W3T_SCENARIO="session", W3T_SCENARIOS=",".join(session), W3T_CONTROL=control, W3T_DURATION="100000")
            p = subprocess.Popen([EXE] + game_args, cwd=os.path.dirname(EXE), env=env)
            procs.append(p)
            print(f"[{time.time() - t0:6.1f}s] started {bot_name(i)} pid={p.pid}", flush=True)
            if i + 1 < a.bots:
                time.sleep(a.stagger)
                if a.serial:
                    wait_in_world(os.path.join(run_dir, bot_name(i) + ".log"), 240, t0, procs)

        seen = {}
        next_stats = 0
        shooter = None
        while time.time() - t0 < a.timeout:
            # side by side, in bot order, so no window covers another
            arrange([p.pid for p in procs])
            if a.shots > 0 and len(procs) == a.bots and not shooter:
                shooter = threading.Thread(target=shoot, args=(run_dir, procs, a, shots_stop), daemon=True)
                shooter.start()
            if a.record > 0 and len(procs) == a.bots and not recorder:
                recorder = threading.Thread(target=record, args=(run_dir, procs, a, shots_stop))
                recorder.start()
            if time.time() >= next_stats:
                next_stats = time.time() + 15
                mem = ", ".join(f"{bot_name(i)} {private_mb(p.pid)} MB" for i, p in enumerate(procs) if p.poll() is None)
                print(f"[{time.time() - t0:6.1f}s] stats: {mem}; GPU {gpu_used_mb()}", flush=True)
            if session and len(procs) == a.bots and len(results) < len(session):
                # the scenario under way: on to the next once every bot passed it, or it took too long
                name = session[len(results)]
                limit = default_duration(name) + (150 if not results else 30)  # the first one waits for the loading
                logs = {i: segment(read_log(run_dir, i), name) for i in range(a.bots)}
                passed = all(re.search(rf"PASS condition met at t=\S+ scenario={re.escape(name)}(\s|$)", logs[i]) for i in logs)
                if passed or time.time() - go_at > limit:
                    ok, why = check(name, logs, a.bots)
                    if not passed:
                        ok, why = False, f"not passed within {limit} s: {why}"
                    results.append((name, ok, why))
                    print(f"[{time.time() - t0:6.1f}s] RESULT {name}: {'PASS' if ok else 'FAIL'} ({why}) [{time.time() - go_at:.0f}s]", flush=True)
                    go_at = time.time()
                    open(control, "w").write(f"go {len(results)}" if len(results) < len(session) else "end")
            # bots stay in the world after passing (peers may still need them); end once all have passed
            if not session and len(procs) == a.bots and all(
                    "PASS condition met" in open(os.path.join(run_dir, bot_name(i) + ".log"), encoding="utf-8", errors="replace").read()
                    for i in range(a.bots) if os.path.exists(os.path.join(run_dir, bot_name(i) + ".log"))) \
                    and all(os.path.exists(os.path.join(run_dir, bot_name(i) + ".log")) for i in range(a.bots)):
                print(f"[{time.time() - t0:6.1f}s] every bot passed; stopping the run", flush=True)
                break
            alive = 0
            for i, p in enumerate(procs):
                rc = p.poll()
                if rc is None:
                    alive += 1
                    for hwnd, cls, text, vis, kids in windows_of(p.pid):
                        key = (hwnd, text)
                        if text and seen.get(hwnd) != key:
                            seen[hwnd] = key
                            print(f"[{time.time() - t0:6.1f}s] {bot_name(i)} window {text!r}", flush=True)
                            if "Error" in text or "error" in text:
                                for kc, kt in kids:
                                    if kt:
                                        print(f"      {kc}: {kt[:600]!r}", flush=True)
                elif ("rc", i) not in seen:
                    seen[("rc", i)] = rc
                    print(f"[{time.time() - t0:6.1f}s] {bot_name(i)} exited rc={rc}", flush=True)
            # a failed bot decides the run; its peers would only wait for the timeout
            if any(seen.get(("rc", i)) not in (None, 0) for i in range(len(procs))):
                print(f"[{time.time() - t0:6.1f}s] a bot failed; stopping the run", flush=True)
                break
            if alive == 0:
                break
            time.sleep(1)
    finally:
        shots_stop.set()
        if recorder:
            recorder.join(90)
        for i, p in enumerate(procs):
            if p.poll() is None:
                p.kill()
                print(f"stopped {bot_name(i)}", flush=True)
        try:
            server.stdin.write(b"stop\n")
            server.stdin.flush()
        except OSError:
            pass
        for r in relays:
            r.send_signal(subprocess.signal.CTRL_BREAK_EVENT)
        time.sleep(1)
        if server.poll() is None:
            server.kill()
        server_log.close()
        for r in relays:
            if r.poll() is None:
                r.kill()
        if a.steam_box:
            stop_boxed_relays(run_dir)
        for name in sorted(os.listdir(run_dir)):
            if name.startswith("relay-"):
                text = open(os.path.join(run_dir, name, "relay.log"), encoding="utf-8", errors="replace").read()
                print(f"--- {name}: {' | '.join(text.strip().splitlines()[-4:])}")

    logs = {}
    for i in range(a.bots):
        logs[i] = read_log(run_dir, i)
        last_wo = [l for l in logs[i].splitlines() if " WO " in l][-1:]
        print(f"--- {bot_name(i)}: {len(logs[i].splitlines())} log lines; last WO line: {last_wo}")
    if session:
        for name in session[len(results):]:
            results.append((name, False, "not run (the session ended first)"))
            print(f"RESULT {name}: FAIL (not run (the session ended first)) [0s]")
        passed = sum(ok for _, ok, _ in results)
        ok, why = passed == len(session), f"{passed}/{len(session)} scenarios passed"
    else:
        ok, why = check(a.scenario, logs, a.bots)
    print(f"RESULT: {'PASS' if ok else 'FAIL'} ({why})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
