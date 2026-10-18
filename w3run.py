# Launches witcher3.exe with given args, records the text of its top-level and child windows (dialogs), and
# stops it after a timeout. Only kills the process it started.
# Usage: w3run.py [--timeout S] [--keep] [--tag NAME] -- <game args...>
import argparse
import ctypes
import ctypes.wintypes as wt
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import EXE  # noqa: E402

user32 = ctypes.WinDLL("user32", use_last_error=True)
EnumWindowsProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
user32.EnumWindows.argtypes = [EnumWindowsProc, wt.LPARAM]
user32.EnumChildWindows.argtypes = [wt.HWND, EnumWindowsProc, wt.LPARAM]
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.GetWindowTextLengthW.argtypes = [wt.HWND]
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.GetClassNameW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.IsWindowVisible.argtypes = [wt.HWND]
user32.SendMessageTimeoutW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, ctypes.c_void_p, wt.UINT, wt.UINT, ctypes.POINTER(ctypes.c_size_t)]
WM_GETTEXT, WM_GETTEXTLENGTH, SMTO_ABORTIFHUNG = 0x000D, 0x000E, 0x0002


def window_text(hwnd):
    # WM_GETTEXT reads edit controls too (GetWindowText doesn't for other processes' edits)
    n = ctypes.c_size_t()
    if not user32.SendMessageTimeoutW(hwnd, WM_GETTEXTLENGTH, 0, None, SMTO_ABORTIFHUNG, 500, ctypes.byref(n)):
        return ""
    buf = ctypes.create_unicode_buffer(n.value + 1)
    user32.SendMessageTimeoutW(hwnd, WM_GETTEXT, n.value + 1, ctypes.cast(buf, ctypes.c_void_p), SMTO_ABORTIFHUNG, 500, ctypes.byref(n))
    return buf.value


def class_name(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, buf, 256)
    return buf.value


def windows_of(pid):
    found = []

    def top(hwnd, _):
        p = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid:
            kids = []

            def child(h, _):
                kids.append((class_name(h), window_text(h)))
                return True

            user32.EnumChildWindows(hwnd, EnumWindowsProc(child), 0)
            found.append((int(hwnd), class_name(hwnd), window_text(hwnd), bool(user32.IsWindowVisible(hwnd)), kids))
        return True

    user32.EnumWindows(EnumWindowsProc(top), 0)
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, default=180)
    ap.add_argument("--keep", action="store_true", help="don't kill at timeout")
    ap.add_argument("--tag", default="run")
    ap.add_argument("--errors", help="write the full script compilation error text here")
    ap.add_argument("--show", type=int, default=15, help="error lines to print")
    ap.add_argument("--sandbox", help="run in test mode with this Documents sandbox (settings copies, no saves)")
    ap.add_argument("game_args", nargs="*")
    a = ap.parse_args()
    env = dict(os.environ, SteamAppId="292030", SteamGameId="292030")
    if a.sandbox:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from sandbox import make_sandbox
        make_sandbox(a.sandbox)
        env.update(W3T_SCENARIO="verify", W3T_DOCUMENTS=a.sandbox, W3T_LOG=os.path.join(a.sandbox, "w3test.log"))
    t0 = time.time()
    proc = subprocess.Popen([EXE] + a.game_args, cwd=os.path.dirname(EXE), env=env)
    print(f"[{a.tag}] started pid={proc.pid} args={a.game_args}", flush=True)
    seen = {}
    while True:
        rc = proc.poll()
        for hwnd, cls, text, vis, kids in windows_of(proc.pid):
            if "Compilation Errors" in text:
                edits = [kt for kc, kt in kids if kc == "Edit" and kt]
                report = "\n".join(edits).replace("\r\n", "\n")
                lines = [l for l in report.splitlines() if l.strip()]
                if a.errors:
                    open(a.errors, "w", encoding="utf-8").write(report)
                print(f"[{a.tag}] +{time.time() - t0:6.1f}s SCRIPT COMPILATION ERRORS: {len(lines)} lines"
                      + (f" -> {a.errors}" if a.errors else ""), flush=True)
                for l in lines[:a.show]:
                    print(f"[{a.tag}]   {l}", flush=True)
                proc.kill()
                proc.wait()
                return 2
            key = (hwnd, text, cls)
            if seen.get(hwnd) != key:
                seen[hwnd] = key
                print(f"[{a.tag}] +{time.time() - t0:6.1f}s window cls={cls!r} visible={vis} title={text!r}", flush=True)
                for kc, kt in kids:
                    if kt and not kt.startswith("Compiling"):
                        print(f"[{a.tag}]     child {kc!r}: {kt[:500]!r}", flush=True)
        if rc is not None:
            print(f"[{a.tag}] exited rc={rc} (0x{rc & 0xFFFFFFFF:08X}) after {time.time() - t0:.1f}s", flush=True)
            return rc
        if time.time() - t0 > a.timeout:
            if a.keep:
                print(f"[{a.tag}] timeout, leaving pid={proc.pid} running", flush=True)
                return None
            proc.kill()
            proc.wait()
            print(f"[{a.tag}] killed after timeout {a.timeout}s", flush=True)
            return -1
        time.sleep(0.5)


if __name__ == "__main__":
    sys.exit(0 if main() in (0, None) else 1)
