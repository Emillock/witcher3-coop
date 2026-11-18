# Judges a filmed run or a cut reel on how it moves: how many frames really change, where a window froze, and where
# the picture jumped (a teleport looks like a cut). Reads ffmpeg's per-frame difference (scdet's mafd, 0 for a frame
# identical to the one before), so no decoding of pixels here.
# Usage: fluency.py <video.mp4> [--half left|right|both] [--freeze 0.4] [--jump 12] [--at 12.5,40,...]
import argparse
import os
import re
import subprocess
import sys
import tempfile

EPS = 0.05          # mafd below this: the frame is a repeat of the one before


def mafd(path, crop):
    """[(time, mafd)] for every frame, in order."""
    # a filter option cannot carry a drive's colon, so ffmpeg runs in the temp folder and writes a bare name there
    work = tempfile.gettempdir()
    name = "fluency-%d.txt" % os.getpid()
    vf = (crop + "," if crop else "") + "scdet=s=0:t=0,metadata=print:file=" + name
    subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.abspath(path), "-vf", vf, "-an", "-f", "null", "-"],
                   check=True, cwd=work)
    out = os.path.join(work, name)
    rows, t = [], 0.0
    for line in open(out, encoding="utf-8", errors="replace"):
        m = re.match(r"^frame:\s*\d+\s+pts:\s*\d+\s+pts_time:([\d.]+)", line)
        if m:
            t = float(m.group(1))
        m = re.search(r"lavfi\.scd\.mafd=([\d.]+)", line)
        if m:
            rows.append((t, float(m.group(1))))
    os.remove(out)
    return rows


def spans(rows, pred, least):
    """Runs of frames where pred holds, at least `least` seconds long."""
    out, start, prev = [], None, rows[0][0] if rows else 0.0
    for t, v in rows:
        if pred(v):
            if start is None:
                start = prev
        else:
            if start is not None and prev - start >= least:
                out.append((start, prev))
            start = None
        prev = t
    if start is not None and prev - start >= least:
        out.append((start, prev))
    return out


def find_jumps(rows, a):
    """Frames that differ from the one before far more than the frames around them do: a cut, or a teleport."""
    out = []
    half = 60       # about two seconds either side at 30 fps
    for i, (t, v) in enumerate(rows):
        if v < a.floor:
            continue
        near = sorted(x for _, x in rows[max(0, i - half):i + half])
        med = near[len(near) // 2] if near else 0.0
        if v >= a.jump * max(0.3, med):
            out.append((t, v, med))
    return out


def report(name, rows, a):
    live = [v for _, v in rows if v > EPS]
    dur = rows[-1][0] - rows[0][0] if len(rows) > 1 else 0.0
    print(f"\n{name}: {len(rows)} frames over {dur:.1f} s")
    if not rows:
        return
    print(f"  frames that changed: {len(live)} ({100.0 * len(live) / len(rows):.0f}%)"
          f" -> {len(live) / max(1e-6, dur):.1f} new pictures/s")
    if live:
        live.sort()
        print(f"  movement per frame (mafd): median {live[len(live) // 2]:.1f}, "
              f"90th {live[int(len(live) * 0.9)]:.1f}, max {live[-1]:.1f}")
    # a second-by-second floor: the worst stretches of a still picture
    frozen = spans(rows, lambda v: v <= EPS, a.freeze)
    print(f"  still for {a.freeze}s or more: {len(frozen)}" + (":" if frozen else ""))
    for s, e in frozen[:12]:
        print(f"    {s:7.1f} - {e:6.1f} s  ({e - s:.1f} s)")
    if len(frozen) > 12:
        print(f"    ... and {len(frozen) - 12} more")
    jumps = find_jumps(rows, a)
    print(f"  jumps (over {a.jump}x the movement around them, and at least {a.floor}): {len(jumps)}"
          + (":" if jumps else ""))
    for t, v, med in jumps[:20]:
        print(f"    {t:7.1f} s  mafd {v:5.1f}, {v / max(0.1, med):4.1f}x the {med:.1f} around it")
    if len(jumps) > 20:
        print(f"    ... and {len(jumps) - 20} more")
    # a floor on how alive each stretch is, which an average over the whole film would hide
    print("  new pictures a second, ten seconds at a time:")
    line, start = "", rows[0][0]
    for lo in range(int(rows[0][0]), int(rows[-1][0]), 10):
        live = [1 for t, v in rows if lo <= t < lo + 10 and v > EPS]
        line += f" {len(live) / 10.0:.0f}"
    print("   " + line)
    if a.at:
        print("  around the moments asked for:")
        for at in [float(x) for x in a.at.split(",") if x.strip()]:
            near = [(t, v) for t, v in rows if abs(t - at) <= 1.0]
            live_near = [v for _, v in near if v > EPS]
            print(f"    {at:7.1f} s  {len(live_near)} of {len(near)} frames changed, "
                  f"biggest {max([v for _, v in near], default=0):.1f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--half", default="both", choices=["left", "right", "both", "all"],
                    help="a filmed run is two windows side by side; judge one, or each in turn")
    ap.add_argument("--freeze", type=float, default=0.4, help="report a still picture this long or longer")
    ap.add_argument("--jump", type=float, default=3.5,
                    help="report a frame that differs this many times more than the frames around it do")
    ap.add_argument("--floor", type=float, default=8.0, help="...and by at least this much, so quiet stretches are left alone")
    ap.add_argument("--at", default="", help="also report the movement around these seconds")
    a = ap.parse_args()
    if not os.path.exists(a.video):
        sys.exit(f"no {a.video}")
    if a.half in ("both", "all"):
        report("whole picture", mafd(a.video, ""), a)
    if a.half in ("left", "all"):
        report("left window (the host)", mafd(a.video, "crop=iw/2:ih:0:0"), a)
    if a.half in ("right", "all"):
        report("right window (the friend)", mafd(a.video, "crop=iw/2:ih:iw/2:0"), a)


main()
