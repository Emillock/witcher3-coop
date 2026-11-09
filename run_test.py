# Multi-instance test harness: local Witcher Online server + N game clients driven by the w3test bot.
# Prints RESULT: PASS/FAIL. Only kills processes it started.
# Usage: run_test.py <scenario>[,<scenario>...] [--bots N] [--duration 60] [--stagger 5] [--timeout 420] [--save SUBSTR]
#        run_test.py --matrix FILE [--bots N] ...
# Several scenarios separated by commas run as one session: the games load once and the bots go from one scenario to
# the next when the harness says so (control file), cleaning up in between. --matrix FILE runs a session whose entries
# carry their own settings (session_matrix.py); a hung entry or a game that ended starts fresh games for the next one.
# The games start minimized and are never activated (--window).
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
import session_matrix as sm  # noqa: E402
from config import GAME, USER_W3_DOCS, WO, WORK  # noqa: E402
from sandbox import make_sandbox  # noqa: E402
from w3run import (BITMAPINFOHEADER, EXE, FocusWatch, arrange, capture_window, game_window, gdi32,  # noqa: E402
                   startup_info, user32, windows_of, wt)

SERVER_JAR = os.path.join(WO, "server", "build", "WitcherServer.jar")
RUNS = os.path.join(WORK, "runs")
GAME_ARGS = os.environ.get("W3T_GAME_ARGS", "-windowed -width 640 -height 360 -debugscripts -noraytracing").split()


# scenarios where the leader waits for the member to load and join before acting
LONG_SCENARIOS = ("shared_enemy", "enemy_attacks", "handoff", "reactions", "twin_match", "quest_sync", "dialog_sync",
                  "facts_sync", "puppet_follow", "puppet_walk", "puppet_glide", "enemy_moves", "enemy_summons", "enemy_spells", "real_encounter",
                  "enemy_projectiles", "member_combat", "enemy_effects", "sign_visuals", "showcase", "attack_view", "member_death", "leader_death", "enemy_crowd", "enemy_sounds", "trade", "encounter_mismatch", "player_effects", "mounted_fight", "party_hud", "follow_travel", "party_invite", "puppet_timeout", "player_menu", "clock_sync", "sign_anim", "sign_cast", "cutscene_wait", "npc_match", "quest_behind", "kill_loot", "gwent_vanilla", "gwent_selftest", "gwent_duel")
# scenarios for one game (no co-op): their default --bots
SINGLE_BOT_SCENARIOS = ("gwent_vanilla", "gwent_selftest")


GWENT_DUEL = "gwent_duel"
GWENT_DECKS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "w3test", "gwent_decks.txt")
DUEL_LOGDIFF = os.path.join(WO, "gwent", "tools", "duel_logdiff.py")


def default_duration(scenario: str) -> int:
    if scenario == GWENT_DUEL:
        return 600
    return 300 if scenario in LONG_SCENARIOS else 60


def expand_gwent_decks(value: str, decks_file: str = GWENT_DECKS_FILE) -> str:
    """W3T_GWENT_DECKS with every name from w3test/gwent_decks.txt replaced by its "leader+card+..." list."""
    named = {}
    with open(decks_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                name, _, cards = line.partition(":")
                named[name.strip()] = cards.strip()
    return ",".join(named.get(entry.strip(), entry.strip()) for entry in value.split(","))


def script_int_seed(value: str) -> str:
    """W3T_GWENT_SEED as the script reads it (a 32-bit int): a uint seed from 2^31 to 2^32 - 1 becomes the signed
    value with the same bits, so the board's uint(seed) gets the seed back. Anything else is returned unchanged."""
    try:
        seed = int(value.strip())
    except ValueError:
        return value
    if 2 ** 31 <= seed < 2 ** 32:
        return str(seed - 2 ** 32)
    return value


GWENT_AUTOPLAY_SWITCHES = ("W3T_GWENT_MULLIGAN", "W3T_GWENT_LEADER_FIRST")


def gwent_autoplay_switches(env: dict) -> list[str]:
    """The gwent_duel autoplay switches set in env ("NAME=value"), which the test mod hands to both boards:
    W3T_GWENT_MULLIGAN=1 redraws two cards at the mulligan, W3T_GWENT_LEADER_FIRST=1 plays a usable leader first."""
    return [f"{name}={env[name]}" for name in GWENT_AUTOPLAY_SWITCHES if env.get(name)]


def gwent_logdiff(run_dir: str, n: int) -> tuple[int, str]:
    """Compares the two bots' duel logs with WitcherOnline's duel_logdiff.py; returns (exit code, its output)."""
    if n < 2:
        return 0, "skipped (one bot)"
    return gwent_logdiff_files([os.path.join(run_dir, bot_name(i) + ".log") for i in range(2)])


def gwent_logdiff_files(logs: list[str]) -> tuple[int, str]:
    """duel_logdiff.py on these two log files; returns (exit code, its output)."""
    out = subprocess.run([sys.executable, "-I", DUEL_LOGDIFF] + logs, capture_output=True, text=True, timeout=120)
    return out.returncode, (out.stdout + out.stderr).strip()


DUEL_END_RE = re.compile(r"DUEL END result=(\w+)")
# an end of game token (version.matchId.seq.E.winner.hash) in a duel_logdiff line
END_TOKEN_RE = re.compile(r"\b\d+\.[0-9a-f]+g\d+\.\d+\.E\.")
OPPOSITE_RESULT = {"win": "loss", "loss": "win", "draw": "draw", "nocontest": "nocontest"}


def gwent_results_agree(run_dir: str, n: int, exited: bool = False) -> tuple[bool, str]:
    """Whether the two bots' last DUEL END results fit together (win with loss, draw with draw, no contest with no
    contest; with exited, W3T_GWENT_EXIT_AT, bot 1 quit its game mid-match: bot 0 no contest, bot 1 none); returns
    (ok, the two results)."""
    if n < 2:
        return True, "skipped (one bot)"
    texts = []
    for i in range(2):
        try:
            with open(os.path.join(run_dir, bot_name(i) + ".log"), encoding="utf-8", errors="replace") as f:
                texts.append(f.read())
        except OSError:
            texts.append("")
    return gwent_results_agree_texts(texts, exited)


def gwent_results_agree_texts(texts: list[str], exited: bool = False) -> tuple[bool, str]:
    """gwent_results_agree on the two bots' log texts (or a session entry's parts of them)."""
    results = []
    for text in texts[:2]:
        found = DUEL_END_RE.findall(text)
        results.append(found[-1] if found else "none")
    if exited:
        ok = results == ["nocontest", "none"]
    else:
        ok = OPPOSITE_RESULT.get(results[0]) == results[1]
    return ok, f"{bot_name(0)} {results[0]}, {bot_name(1)} {results[1]}"


def bot_settings(entry: sm.Entry, base_env: dict) -> dict[str, str]:
    """A matrix entry's settings as the bots get them: names from w3test/gwent_decks.txt become inline decks and the
    seed is passed as the script reads it (as run_test.py does for one gwent_duel run)."""
    settings = sm.entry_settings(entry, base_env)
    if settings["W3T_GWENT_DECKS"]:
        settings["W3T_GWENT_DECKS"] = expand_gwent_decks(settings["W3T_GWENT_DECKS"])
    if settings["W3T_GWENT_SEED"]:
        settings["W3T_GWENT_SEED"] = script_int_seed(settings["W3T_GWENT_SEED"])
    return settings


def window_mode(requested: str, shots: float, record: float) -> str:
    """How the games' windows start: "minimized" (never focused), or "noactivate" (shown but never activated) when
    asked for or when screenshots or a recording need a window that draws (PrintWindow gets nothing from a minimized
    one)."""
    if requested:
        return requested
    return "noactivate" if shots > 0 or record > 0 else "minimized"


def gwent_logdiff_verdict(rc: int, text: str, corrupt_at: str) -> tuple[bool, str]:
    """Judges duel_logdiff's outcome: clean logs (rc 0), or with W3T_GWENT_CORRUPT_AT=<seq> the first divergence
    exactly at that seq (the corrupted message), with W3T_GWENT_CORRUPT_AT=end at an end of game message (E);
    returns (ok, reason when not ok)."""
    first = text.splitlines()[0] if text else str(rc)
    if not corrupt_at:
        return rc == 0, f"duel logs diverged: {first}"
    if corrupt_at.strip() == "end":
        ok = rc == 1 and first.startswith("DIVERGED at seq=") and END_TOKEN_RE.search(first) is not None
        return ok, f"expected duel_logdiff to diverge at an E message (W3T_GWENT_CORRUPT_AT=end), got: {first}"
    wanted = f"DIVERGED at seq={corrupt_at.strip()}:"
    return rc == 1 and first.startswith(wanted), f"expected duel_logdiff {wanted} (W3T_GWENT_CORRUPT_AT), got: {first}"


def segment(log, scenario):
    # a session's log from where `scenario` started
    i = log.find(f"SCENARIO {scenario} start")
    return log[i:] if i >= 0 else log


def bot_name(i):
    return "Bot" + "ABCDEFGH"[i]


def missing_test_build():
    # without w3test.asi nothing points a game at its sandbox: it would use (and write) the owner's Documents
    files = (r"bin\x64_dx12\dinput8.dll", r"bin\x64_dx12\w3test.asi", r"mods\modW3Test")
    return [f for f in files if not os.path.exists(os.path.join(GAME, f))]


def owner_docs_state():
    # the owner's Documents\The Witcher 3 and its saves, which no test instance may write
    state = {}
    for d in (USER_W3_DOCS, os.path.join(USER_W3_DOCS, "gamesaves")):
        if os.path.isdir(d):
            for e in os.scandir(d):
                if e.is_file():
                    state[e.path] = (e.stat().st_size, e.stat().st_mtime_ns)
    return state


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


MONEY_RE = re.compile(r"GWENT duel money before=(-?\d+) after=(-?\d+)")


class MatrixRun:
    """A --matrix session: its entries with their settings and time limits, and each entry's verdict."""

    def __init__(self, entries: list[sm.Entry], base_env: dict, root: str, bots: int):
        self.entries = entries
        self.settings = [bot_settings(e, base_env) for e in entries]
        self.root = root
        self.bots = bots
        self.unstarted_why = ""   # why the last launch ended before its entry under way had started

    def scenarios(self) -> list[str]:
        """The session's scenario names, in entry order (the bots' W3T_SCENARIOS)."""
        return [e.scenario for e in self.entries]

    def control(self, index: int) -> str:
        """The control file that starts entry `index`, or ends the session past the last entry."""
        if index >= len(self.entries):
            return sm.END_CONTROL
        return sm.control_text(index, self.settings[index])

    def limit(self, index: int) -> int:
        """Seconds entry `index` gets once started (its "duration", else its scenario's default)."""
        entry = self.entries[index]
        return entry.duration or default_duration(entry.scenario)

    def judge(self, index: int, logs: dict, ok: bool, why: str) -> tuple[bool, str]:
        """An entry's verdict. The bots' parts of the session log are kept in entries\\<NN>-<label>\\; a gwent_duel
        entry is also checked as one gwent_duel run is: duel_logdiff on those parts and the two bots' results."""
        entry = self.entries[index]
        folder = os.path.join(self.root, "entries", f"{index + 1:02d}-{entry.label}")
        os.makedirs(folder, exist_ok=True)
        paths = []
        for i in range(self.bots):
            paths.append(os.path.join(folder, bot_name(i) + ".log"))
            with open(paths[-1], "w", encoding="utf-8") as f:
                f.write(logs[i])
        if entry.scenario != GWENT_DUEL or self.bots < 2:
            return ok, why
        money = ", ".join(f"{bot_name(i)} " + ("{}->{}".format(*m[-1]) if (m := MONEY_RE.findall(logs[i])) else "none")
                          for i in range(self.bots))
        print(f"--- {entry.label} money: {money}", flush=True)
        settings = self.settings[index]
        mode = settings["W3T_GWENT_LOGDIFF"] or "fail"
        rc, text = gwent_logdiff_files(paths[:2])
        print(f"--- {entry.label} duel_logdiff ({mode}): rc={rc} {text}", flush=True)
        diff_ok, diff_why = gwent_logdiff_verdict(rc, text, settings["W3T_GWENT_CORRUPT_AT"])
        if not diff_ok and mode != "report" and ok:
            ok, why = False, diff_why
        agree, results = gwent_results_agree_texts([logs[0], logs[1]], bool(settings["W3T_GWENT_EXIT_AT"]))
        print(f"--- {entry.label} duel results: {results}", flush=True)
        if not agree and ok:
            ok, why = False, f"the bots' duel results do not fit together: {results}"
        return ok, why


def launch(a: argparse.Namespace, game_args: list[str], run_dir: str, session: list[str], results: list,
           timeout: float, matrix: MatrixRun | None = None, start: int = 0,
           watch: FocusWatch | None = None) -> tuple[list[str], str]:
    """One launch: the local server (and relays), a.bots games, and the run loop, until the run is over, every
    session entry is decided, or (matrix) an entry hung or a game ended; then everything it started is stopped.
    A session's (name, ok, why) verdicts are appended to results. With a matrix the session starts at entry `start`.
    Returns (the owner's Documents files that changed, why the launch ended: "done", "timeout", "owner", "failed",
    or with a matrix "hung", "exited", or "unstarted" when the entry under way never started: no result is
    appended for it then, and matrix.unstarted_why says why)."""
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
    if matrix:
        sm.write_control(control, matrix.control(start))
    elif session:
        open(control, "w").write("go 0")
    owner_before, owner_touched = owner_docs_state(), []
    end = "timeout"
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
                       W3T_GRACE=str(a.grace), W3T_MONSTER=a.monster, W3T_WINDOW=a.window,
                       W3T_LOG=os.path.join(run_dir, bot_name(i) + ".log"))
            if session:
                # the harness times each scenario; the bots never give up by themselves
                env.update(W3T_SCENARIO="session", W3T_SCENARIOS=",".join(session), W3T_CONTROL=control, W3T_DURATION="100000")
            if matrix:
                env["W3T_MATRIX"] = "1"  # the test mod's matrix-only behaviour (EndCombat)
            p = subprocess.Popen([EXE] + game_args, cwd=os.path.dirname(EXE), env=env, startupinfo=startup_info(a.window))
            procs.append(p)
            if watch:
                watch.add(p.pid, bot_name(i))
            print(f"[{time.time() - t0:6.1f}s] started {bot_name(i)} pid={p.pid}", flush=True)
            if i + 1 < a.bots:
                time.sleep(a.stagger)
                if a.serial:
                    wait_in_world(os.path.join(run_dir, bot_name(i) + ".log"), 240, t0, procs)

        seen = {}
        next_stats = 0
        shooter = None
        while time.time() - t0 < timeout:
            owner_now = owner_docs_state()
            owner_touched = sorted(os.path.basename(f) for f in set(owner_before) | set(owner_now)
                                   if owner_before.get(f) != owner_now.get(f))
            if owner_touched:
                print(f"[{time.time() - t0:6.1f}s] STOP: the owner's Documents changed ({', '.join(owner_touched)}): "
                      "a game is not using its sandbox", flush=True)
                end = "owner"
                break
            # side by side, in bot order, so no window covers another (minimized ones stay where they are)
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
            if matrix and len(procs) == a.bots and len(results) < len(session):
                # the entry under way: on to the next once every bot passed it or reported its failure; if it hangs,
                # this launch ends and the next entry gets fresh games
                index = len(results)
                entry = matrix.entries[index]
                limit = matrix.limit(index) + (150 if index == start else 30)  # the first one waits for the loading
                logs = {i: sm.cut_entry(read_log(run_dir, i), index, entry.scenario) for i in range(a.bots)}
                state = sm.entry_state(list(logs.values()), entry.scenario, time.time() - go_at, limit)
                if state == "hung" and not sm.entry_started(list(logs.values())):
                    matrix.unstarted_why = f"no bot started it within {limit} s"
                    print(f"[{time.time() - t0:6.1f}s] {entry.label} not started within {limit} s: ending this launch", flush=True)
                    end = "unstarted"
                    break
                if state != "running":
                    ok, why = check(entry.scenario, logs, a.bots)
                    if state == "hung":
                        ok, why = False, f"not decided within {limit} s: {why}"
                    ok, why = matrix.judge(index, logs, ok, why)
                    results.append((entry.label, ok, why))
                    print(f"[{time.time() - t0:6.1f}s] RESULT {entry.label}: {'PASS' if ok else 'FAIL'} ({why}) [{time.time() - go_at:.0f}s]", flush=True)
                    go_at = time.time()
                    if state == "hung":
                        print(f"[{time.time() - t0:6.1f}s] {entry.label} hung: ending this launch", flush=True)
                        end = "hung"
                        break
                    if any(("rc", i) in seen for i in range(len(procs))) and len(results) < len(session):
                        # a game quit on purpose during this entry (W3T_GWENT_EXIT_AT): the next one gets fresh games
                        print(f"[{time.time() - t0:6.1f}s] {entry.label} ended a game: the next entry gets fresh games", flush=True)
                        end = "exited"
                        break
                    sm.write_control(control, matrix.control(index + 1))
            elif session and len(procs) == a.bots and len(results) < len(session):
                # the scenario under way: on to the next once every bot passed it (or reported its failure), or it
                # took too long
                name = session[len(results)]
                limit = default_duration(name) + (150 if not results else 30)  # the first one waits for the loading
                logs = {i: segment(read_log(run_dir, i), name) for i in range(a.bots)}
                passed = all(re.search(rf"PASS condition met at t=\S+ scenario={re.escape(name)}(\s|$)", logs[i]) for i in logs)
                decided = sm.entry_state(list(logs.values()), name, 0, limit) == "decided"
                if passed or decided or time.time() - go_at > limit:
                    ok, why = check(name, logs, a.bots)
                    if not passed and not decided:
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
                end = "done"
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
                            if "Error" in text or "error" in text or cls == "#32770":
                                for kc, kt in kids:
                                    if kt:
                                        print(f"      {kc}: {kt[:600]!r}", flush=True)
                elif ("rc", i) not in seen:
                    seen[("rc", i)] = rc
                    print(f"[{time.time() - t0:6.1f}s] {bot_name(i)} exited rc={rc}", flush=True)
            if matrix:
                # a game ended (crashed, or its bot cannot go on) before the session was over: the entry under way
                # failed, the next one gets fresh games
                gone = [i for i in range(len(procs)) if ("rc", i) in seen]
                exits = [f"{bot_name(i)} rc={seen[('rc', i)]}" for i in gone]
                if exits and len(results) < len(session):
                    index = len(results)
                    entry = matrix.entries[index]
                    logs = {i: sm.cut_entry(read_log(run_dir, i), index, entry.scenario) for i in range(a.bots)}
                    if all(sm.planned_exit(matrix.settings[index], i, seen[("rc", i)], logs[i]) for i in gone):
                        # bot 1 quit its game on purpose (W3T_GWENT_EXIT_AT): the entry goes on to its verdict
                        if ("planned", index) not in seen:
                            seen[("planned", index)] = True
                            print(f"[{time.time() - t0:6.1f}s] {entry.label}: {', '.join(exits)} quit on purpose (W3T_GWENT_EXIT_AT)", flush=True)
                    elif not sm.entry_started(list(logs.values())):
                        matrix.unstarted_why = f"a game ended before it started ({', '.join(exits)})"
                        print(f"[{time.time() - t0:6.1f}s] {entry.label} not started: {matrix.unstarted_why}", flush=True)
                        end = "unstarted"
                        break
                    else:
                        _, why = check(entry.scenario, logs, a.bots)
                        why = f"a game ended during it ({', '.join(exits)}): {why}"
                        matrix.judge(index, logs, False, why)
                        results.append((entry.label, False, why))
                        print(f"[{time.time() - t0:6.1f}s] RESULT {entry.label}: FAIL ({why}) [{time.time() - go_at:.0f}s]", flush=True)
                        end = "exited"
                        break
            # a failed bot decides the run; its peers would only wait for the timeout
            elif any(seen.get(("rc", i)) not in (None, 0) for i in range(len(procs))):
                print(f"[{time.time() - t0:6.1f}s] a bot failed; stopping the run", flush=True)
                end = "failed"
                break
            if alive == 0:
                end = "done"
                break
            time.sleep(1)
        else:
            if matrix and len(procs) == a.bots and len(results) < len(session):
                # the run's own timeout: an entry that had started is reported as interrupted (not "not run")
                index = len(results)
                entry = matrix.entries[index]
                logs = {i: sm.cut_entry(read_log(run_dir, i), index, entry.scenario) for i in range(a.bots)}
                if sm.entry_started(list(logs.values())):
                    _, why = check(entry.scenario, logs, a.bots)
                    why = f"interrupted by the run's timeout after {time.time() - go_at:.0f} s: {why}"
                    matrix.judge(index, logs, False, why)
                    results.append((entry.label, False, why))
                    print(f"[{time.time() - t0:6.1f}s] RESULT {entry.label}: FAIL ({why}) [{time.time() - go_at:.0f}s]", flush=True)
    finally:
        shots_stop.set()
        if recorder:
            recorder.join(90)
        for i, p in enumerate(procs):
            if p.poll() is None:
                p.kill()
                print(f"stopped {bot_name(i)}", flush=True)
            if watch:
                watch.remove(p.pid)
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

    for i in range(a.bots):
        log = read_log(run_dir, i)
        last_wo = [l for l in log.splitlines() if " WO " in l][-1:]
        print(f"--- {bot_name(i)}: {len(log.splitlines())} log lines; last WO line: {last_wo}")
    return owner_touched, end


def run_matrix(a: argparse.Namespace, game_args: list[str], entries: list[sm.Entry], watch: FocusWatch) -> int:
    """Runs a matrix's entries in shared game launches: one launch until an entry hangs or a game ends, then fresh
    games from the next entry on. A failed entry is not retried; an entry that never started gets one more try in
    fresh games. Prints one RESULT line per entry and the total; returns the exit code."""
    root = os.path.join(RUNS, time.strftime("%Y%m%d-%H%M%S") + f"-matrix{len(entries)}"
                        + ("-steam" if a.steam_box else "-relay" if a.relay else ""))
    os.makedirs(root)
    print(f"run dir: {root}", flush=True)
    matrix = MatrixRun(entries, dict(os.environ), root, a.bots)
    for entry in entries:
        print(f"entry {entry.index + 1} {entry.label}: {entry.scenario} "
              + " ".join(f"{k}={v}" for k, v in entry.env.items()) + (f" duration={entry.duration}" if entry.duration else ""), flush=True)
    session = matrix.scenarios()
    results = []
    t0 = time.time()
    start, launches, owner_touched = 0, 0, []
    retried: set[int] = set()
    while start is not None:
        if a.timeout:
            timeout = a.timeout - (time.time() - t0)
            if timeout <= 0:
                print(f"[{time.time() - t0:6.1f}s] the run's --timeout ({a.timeout} s) is used up: no more launches", flush=True)
                break
        else:
            timeout = sum(matrix.limit(i) + 30 for i in range(start, len(entries))) + 150 + 420
        launches += 1
        run_dir = root if launches == 1 else os.path.join(root, f"launch{launches}")
        os.makedirs(run_dir, exist_ok=True)
        print(f"[{time.time() - t0:6.1f}s] launch {launches}: entries {start + 1} to {len(entries)} in {run_dir}", flush=True)
        owner_touched, end = launch(a, game_args, run_dir, session, results, timeout, matrix, start, watch)
        print(f"[{time.time() - t0:6.1f}s] launch {launches} ended ({end}) after {len(results)} of {len(entries)} entries", flush=True)
        if end == "unstarted" and not owner_touched:
            entry = entries[len(results)]
            if sm.retry_unstarted(entry.index, retried):
                print(f"[{time.time() - t0:6.1f}s] {entry.label} did not start ({matrix.unstarted_why}): one more try in fresh games", flush=True)
            else:
                why = f"not started in two launches ({matrix.unstarted_why})"
                results.append((entry.label, False, why))
                print(f"[{time.time() - t0:6.1f}s] RESULT {entry.label}: FAIL ({why}) [0s]", flush=True)
        start = sm.next_launch(len(results), len(entries), "owner" if owner_touched else end)
    for entry in entries[len(results):]:
        results.append((entry.label, False, "not run (the run stopped first)"))
        print(f"RESULT {entry.label}: FAIL (not run (the run stopped first)) [0s]")
    passed = sum(ok for _, ok, _ in results)
    ok = passed == len(entries)
    why = f"{passed}/{len(entries)} entries passed in {launches} launch(es), {time.time() - t0:.0f} s"
    if owner_touched:
        ok, why = False, f"the owner's Documents changed: {', '.join(owner_touched)}"
    watch.stop()
    print(f"--- focus: {watch.summary()}")
    print(f"RESULT: {'PASS' if ok else 'FAIL'} ({why})")
    return 0 if ok else 1


def main() -> int:
    """Parses the command line, runs one scenario, a comma session or a --matrix, and prints RESULT; returns the
    exit code (0 when everything passed)."""
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", nargs="?", default="", help="a scenario, or several separated by commas (a session)")
    ap.add_argument("--matrix", help="a JSON file of session entries, each with its own settings (session_matrix.py)")
    ap.add_argument("--window", choices=("minimized", "noactivate"),
                    help="how the games' windows start; they are never activated (default minimized; noactivate "
                         "with --shots or --record, which need a window that draws)")
    ap.add_argument("--bots", type=int, help="game instances (default 2; 1 for single-game scenarios like gwent_vanilla)")
    ap.add_argument("--duration", type=int, help="in-game seconds before a bot fails (default 60; enemy scenarios 300)")
    ap.add_argument("--stagger", type=int, default=5, help="seconds between starting the bots")
    ap.add_argument("--serial", action="store_true", help="start each bot only once the one before is in the world "
                                                          "(one loading screen at a time; slower)")
    ap.add_argument("--timeout", type=int, help="seconds for the whole run (default 420; gwent_duel: its duration + 420; "
                                                "--matrix: every entry's time plus the loading)")
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
    entries = None
    if a.matrix:
        if a.scenario:
            ap.error("give a scenario or --matrix, not both")
        try:
            entries = sm.load_matrix(a.matrix)
        except (OSError, ValueError) as e:
            print(f"bad matrix: {e}")
            print("RESULT: FAIL (bad matrix)")
            return 2
        a.scenario = "matrix"
        if a.bots is None:
            a.bots = 1 if all(e.scenario in SINGLE_BOT_SCENARIOS for e in entries) else 2
    elif not a.scenario:
        ap.error("a scenario or --matrix is needed")
    if a.bots is None:
        a.bots = 1 if a.scenario in SINGLE_BOT_SCENARIOS else 2
    a.window = window_mode(a.window or "", a.shots, a.record)
    if a.window == "minimized" and (a.shots > 0 or a.record > 0):
        print("note: --shots and --record capture nothing from minimized windows", flush=True)
    missing = missing_test_build()
    if missing:
        print(f"the test build is not deployed ({', '.join(missing)} missing; compile.sh deploys it): the games would "
              "use the owner's Documents. Nothing started.")
        print("RESULT: FAIL (the test build is not deployed)")
        return 2
    if a.steam_box:
        a.relay = True
    game_args = list(GAME_ARGS)
    if a.size:
        os.environ["W3T_RESOLUTION"] = a.size  # sandbox.py writes it into the settings
        for flag, value in zip(("-width", "-height"), a.size.split("x")):
            if flag in game_args:
                game_args[game_args.index(flag) + 1] = value
    print(f"windows: {a.window}", flush=True)
    watch = FocusWatch()
    watch.start()
    if entries:
        if a.duration is None:
            a.duration = 100000
        return run_matrix(a, game_args, entries, watch)
    session = a.scenario.split(",") if "," in a.scenario else []
    if a.duration is None:
        a.duration = default_duration(a.scenario)
    if a.timeout is None:
        a.timeout = a.duration + 420 if a.scenario == GWENT_DUEL else 420
    if a.scenario == GWENT_DUEL and os.environ.get("W3T_GWENT_DECKS"):
        # the bots get inline decks: names from w3test/gwent_decks.txt become "leader+card+..."
        os.environ["W3T_GWENT_DECKS"] = expand_gwent_decks(os.environ["W3T_GWENT_DECKS"])
        print(f"W3T_GWENT_DECKS={os.environ['W3T_GWENT_DECKS']}", flush=True)
    if a.scenario == GWENT_DUEL and os.environ.get("W3T_GWENT_SEED"):
        # StringToInt reads "4000000000" as 0 (not forced); pass the same 32 bits as a signed int
        os.environ["W3T_GWENT_SEED"] = script_int_seed(os.environ["W3T_GWENT_SEED"])
        print(f"W3T_GWENT_SEED={os.environ['W3T_GWENT_SEED']}", flush=True)
    if a.scenario == GWENT_DUEL:
        for switch in gwent_autoplay_switches(dict(os.environ)):
            print(switch, flush=True)

    run_dir = os.path.join(RUNS, time.strftime("%Y%m%d-%H%M%S") + "-" + (f"session{len(session)}" if session else a.scenario)
                           + ("-steam" if a.steam_box else "-relay" if a.relay else "")
                           + ("-" + re.sub(r"\.w2ent$", "", a.monster.split("\\")[-1]) if a.monster else ""))
    os.makedirs(run_dir)
    print(f"run dir: {run_dir}", flush=True)

    results = []  # a session's (scenario, ok, why)
    owner_touched, _ = launch(a, game_args, run_dir, session, results, a.timeout, watch=watch)
    watch.stop()
    print(f"--- focus: {watch.summary()}")
    logs = {i: read_log(run_dir, i) for i in range(a.bots)}
    if session:
        for name in session[len(results):]:
            results.append((name, False, "not run (the session ended first)"))
            print(f"RESULT {name}: FAIL (not run (the session ended first)) [0s]")
        passed = sum(ok for _, ok, _ in results)
        ok, why = passed == len(session), f"{passed}/{len(session)} scenarios passed"
    else:
        ok, why = check(a.scenario, logs, a.bots)
    if a.scenario == GWENT_DUEL:
        # W3T_GWENT_LOGDIFF=report: print the comparison but do not fail on it (before moves and random streams are
        # synced the two boards are expected to differ)
        mode = os.environ.get("W3T_GWENT_LOGDIFF", "fail")
        rc, text = gwent_logdiff(run_dir, a.bots)
        print(f"--- duel_logdiff ({mode}): rc={rc} {text}")
        diff_ok, diff_why = gwent_logdiff_verdict(rc, text, os.environ.get("W3T_GWENT_CORRUPT_AT", ""))
        if not diff_ok and mode != "report" and ok:
            ok, why = False, diff_why
        agree, results = gwent_results_agree(run_dir, a.bots, bool(os.environ.get("W3T_GWENT_EXIT_AT")))
        print(f"--- duel results: {results}")
        if not agree and ok:
            ok, why = False, f"the bots' duel results do not fit together: {results}"
    if owner_touched:
        ok, why = False, f"the owner's Documents changed: {', '.join(owner_touched)}"
    print(f"RESULT: {'PASS' if ok else 'FAIL'} ({why})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
