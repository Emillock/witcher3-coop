# Puts a run's screenshots (run_test.py --shots) on one PNG: a row per moment, a column per bot, so the leader's
# monster and the member's copy of it can be compared frame by frame. Standard library only.
import argparse
import os
import re
import struct
import sys
import zlib


def read_png(path):
    # the harness writes 8-bit RGB with filter 0 on every row (w3run.capture_window)
    data = open(path, "rb").read()
    pos, idat, w, h = 8, b"", 0, 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    rows = []
    for y in range(h):
        row = raw[y * (w * 3 + 1):(y + 1) * (w * 3 + 1)]
        assert row[0] == 0, "unsupported PNG filter"
        rows.append(row[1:])
    return w, h, rows


def write_png(path, w, h, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\0" + bytes(r) for r in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", help="a run's shots folder")
    ap.add_argument("out")
    ap.add_argument("--start", default="", help="first moment, HHMMSS_cc as in the file names (default: the first)")
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--every", type=int, default=1, help="use every Nth moment")
    ap.add_argument("--crop", default="", help="x,y,w,h of each frame to keep (default: all of it)")
    ap.add_argument("--scale", type=int, default=1, help="enlarge each frame this many times (pixel copies)")
    ap.add_argument("--gain", type=float, default=1.0, help="brighten (night scenes) by this factor")
    a = ap.parse_args()

    moments = {}
    for name in os.listdir(a.shots):
        m = re.match(r"(\d{6}_\d{2})_(\w+)\.png$", name)
        if m:
            moments.setdefault(m.group(1), {})[m.group(2)] = os.path.join(a.shots, name)
    bots = sorted({b for v in moments.values() for b in v})
    stamps = [s for s in sorted(moments) if s >= a.start and len(moments[s]) == len(bots)][::a.every][:a.frames]
    if not stamps:
        sys.exit("no moment with every bot's frame")

    gap = 4
    w, h, _ = read_png(moments[stamps[0]][bots[0]])
    cx, cy, cw, ch = map(int, a.crop.split(",")) if a.crop else (0, 0, w, h)
    sheet_w = len(bots) * cw * a.scale + (len(bots) - 1) * gap
    brighten = bytes(min(255, int(v * a.gain)) for v in range(256))
    rows = []
    for k, s in enumerate(stamps):
        frames = [read_png(moments[s][b])[2] for b in bots]
        for y in range(cy, cy + ch):
            line = bytearray()
            for j, f in enumerate(frames):
                if j:
                    line += b"\xff" * (gap * 3)
                part = bytes(f[y][cx * 3:(cx + cw) * 3]).translate(brighten)
                line += b"".join(part[x * 3:x * 3 + 3] * a.scale for x in range(cw)) if a.scale > 1 else part
            rows.extend(bytearray(line) for _ in range(a.scale))
        if k + 1 < len(stamps):
            rows.extend(bytearray(b"\xff" * (sheet_w * 3)) for _ in range(gap))
    write_png(a.out, sheet_w, len(rows), rows)
    print(f"{a.out}: {len(stamps)} moments ({stamps[0]} .. {stamps[-1]}), columns {', '.join(bots)}")


if __name__ == "__main__":
    main()
