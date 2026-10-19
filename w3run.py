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
# real pixel coordinates for window placement, also with display scaling
user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
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


SWP_NOSIZE, SWP_NOZORDER, SWP_NOACTIVATE = 0x0001, 0x0004, 0x0010
user32.GetWindowRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]


def game_window(pid):
    """The game's visible main window, if it has one yet."""
    for hwnd, cls, text, vis, _ in windows_of(pid):
        if vis and text == "The Witcher 3":
            return hwnd
    return None


def arrange(pids):
    """Places the games' windows left to right along the top of the primary screen's work area, without resizing
    or focusing them; wraps to a new row when the screen is full. Call repeatedly: the game moves its window
    while it starts."""
    area = wt.RECT()
    user32.SystemParametersInfoW(0x0030, 0, ctypes.byref(area), 0)  # SPI_GETWORKAREA
    x, y, row_height = area.left, area.top, 0
    for pid in pids:
        hwnd = game_window(pid)
        if not hwnd:
            continue
        r = wt.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        w, h = r.right - r.left, r.bottom - r.top
        if x > area.left and x + w > area.right:
            x, y, row_height = area.left, y + row_height, 0
        if (r.left, r.top) != (x, y):
            user32.SetWindowPos(hwnd, None, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)
        x += w
        row_height = max(row_height, h)


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wt.DWORD), ("biWidth", ctypes.c_long), ("biHeight", ctypes.c_long), ("biPlanes", wt.WORD),
                ("biBitCount", wt.WORD), ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
                ("biXPelsPerMeter", ctypes.c_long), ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", wt.DWORD),
                ("biClrImportant", wt.DWORD)]


gdi32 = ctypes.WinDLL("gdi32")
user32.GetDC.restype = wt.HDC
user32.GetDC.argtypes = [wt.HWND]
user32.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
user32.PrintWindow.argtypes = [wt.HWND, wt.HDC, wt.UINT]
user32.GetClientRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]
gdi32.CreateCompatibleDC.restype = wt.HDC
gdi32.CreateCompatibleDC.argtypes = [wt.HDC]
gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
gdi32.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
gdi32.SelectObject.restype = wt.HGDIOBJ
gdi32.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
gdi32.GetDIBits.argtypes = [wt.HDC, wt.HBITMAP, wt.UINT, wt.UINT, ctypes.c_void_p, ctypes.c_void_p, wt.UINT]
gdi32.DeleteObject.argtypes = [wt.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wt.HDC]


def capture_window(hwnd, path):
    """Saves the window's client area as a PNG (PrintWindow with PW_RENDERFULLCONTENT, so DirectX content is
    included even if another window covers it). Returns False if nothing was captured."""
    import struct
    import zlib

    r = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    w, h = r.right - r.left, r.bottom - r.top
    if w <= 0 or h <= 0:
        return False
    screen = user32.GetDC(None)
    mem = gdi32.CreateCompatibleDC(screen)
    bmp = gdi32.CreateCompatibleBitmap(screen, w, h)
    old = gdi32.SelectObject(mem, bmp)
    ok = user32.PrintWindow(hwnd, mem, 1 | 2)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
    header = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
    pixels = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mem, bmp, 0, h, pixels, ctypes.byref(header), 0)
    gdi32.SelectObject(mem, old)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(None, screen)
    if not ok:
        return False

    raw = bytearray()
    data = pixels.raw
    for y in range(h):
        row = data[y * w * 4:(y + 1) * w * 4]
        raw.append(0)
        rgb = bytearray(w * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]  # BGRA -> RGB
        raw += rgb

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
    return True


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
