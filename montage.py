# Cuts the recordings of filmed runs into a captioned reel of what co-op does.
# Usage: montage.py <out.mp4> <run folder>[:chapter[,chapter...]] ...
#   montage.py work/dist/reel.mp4 work/runs/2026...-film work/runs/2026...-scene_follow
# run_test.py writes video.json beside the recording, saying on which clock its first frame was taken, so a line in a
# bot's log maps straight onto a place in the video. Chapters come from the bots' own marks: "FILM chapter <name>" in
# a filmed session, "SCENARIO <name> start" in a run of scenarios. Segments are cut, captioned (CAPTIONS below),
# faded and joined. ffmpeg does the work.
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "C\\:/Windows/Fonts/segoeui.ttf"
SEGMENT_MAX = 20.0      # no segment outstays its welcome
# how long each chapter is given, where the usual twenty seconds is wrong for it
LENGTH = {"fight": 30.0, "ride": 24.0, "menu": 14.0, "scene_follow": 12.0}
SEGMENT_SKIP = 1.5      # the first seconds of a chapter are the bots getting into place
SKIP = {"ride": 0.5, "meet": 5.0}   # ...and a chapter that wants more or less of its own opening says so
                        # (the ride is cut from before its mark: the member walks to the horse and climbs
                        # on while the two of them are still gathering)
TAIL = {"wound": 6.0, "loot": 5.0}   # chapters whose point lands at the very end: keep rolling into the next
TITLE = 3.0             # how long the opening card stays

# What each chapter is there to show. The second line is the version it came in.
CAPTIONS = {
    # a filmed session (the film scenario), chapter by chapter
    "meet": ("Chat and emotes carry", "0.5.0"),
    "ride": ("Riding one horse together", "0.6.1"),
    "run": ("Your friend's Geralt, in your own world", "0.4.0"),
    "fight": ("The same monsters in both worlds", "0.4.0 - 0.7.0"),
    "bolt": ("Crossbow: the bolt and the aim carry", "0.6.0"),
    "wound": ("A killing blow takes a limb, in both worlds", "0.7.0"),
    "loot": ("Loot from a shared kill reaches both", "0.5.0"),
    "axii": ("Axii's puppet fights for the party", "not released yet"),
    "menu": ("The player menu, rebuilt for Remastered", "0.5.0"),
    # scenarios filmed on their own
    "social": ("Chat and emotes carry", "0.5.0"),
    "player_menu": ("The player menu, rebuilt for Remastered", "0.5.0"),
    "ride_along": ("Riding one horse together", "0.6.1"),
    "shared_enemy": ("The same monsters in both worlds", "0.4.0 - 0.7.0"),
    "enemy_attacks": ("Their attacks land on both of you", "0.5.0"),
    "leader_bolt": ("Crossbow: the bolt and the aim carry", "0.6.0"),
    "leader_aim": ("Crossbow: the bolt and the aim carry", "0.6.0"),
    "kill_wound": ("A monster comes apart in both worlds", "0.7.0"),
    "kill_loot": ("Loot from a shared kill reaches both", "0.5.0"),
    "axii_puppet": ("Axii's puppet fights for the party", "not released yet"),
    "scene_follow": ("Watching your friend's cutscene", "0.6.1"),
    "quest_catchup": ("Joining late catches you up on quests", "0.6.1"),
    "quest_sync": ("Quest progress carries", "0.5.0"),
    "link_ping": ("Your ping, on the party HUD", "0.7.0"),
    "trade": ("Trading, player to player", "0.4.0"),
}


# Where a run of a single scenario becomes worth watching, in whichever log says it first. A run of one scenario
# writes no chapter marks, so without this its segment would start at the first frame.
MARKERS = {
    "scene_follow": "is watching the leader's cutscene",
    "quest_catchup": "CATCHUP member pages=",
}
LEAD_IN = 3.0           # start a little before that line


def stamp(line):
    """The seconds-of-day a bot log line carries, or None."""
    m = re.match(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d)", line)
    if not m:
        return None
    h, mi, s, ms = (int(m.group(i)) for i in range(1, 5))
    return h * 3600 + mi * 60 + s + ms / 1000.0


def first_frame(run_dir):
    """When the recording's first frame was taken, on the same clock as the logs (None: an older run)."""
    path = os.path.join(run_dir, "video.json")
    if not os.path.exists(path):
        return None
    return stamp(json.load(open(path)).get("started", ""))


def marks_of(lines):
    """[(chapter, seconds-of-day)] for every chapter mark in a bot's log."""
    out = []
    for line in lines:
        m = re.search(r"FILM chapter (\S+)|SCENARIO (\S+) start", line)
        at = stamp(line)
        if m and at is not None:
            out.append((m.group(1) or m.group(2), at))
    return out


def marker_at(run_dir, text):
    """When either bot first wrote this line, in seconds of day (None: never, or nothing to look for)."""
    if not text:
        return None
    for name in ("BotA.log", "BotB.log"):
        path = os.path.join(run_dir, name)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8", errors="replace"):
            if text in line and stamp(line) is not None:
                return stamp(line)
    return None


def segments(run_dir, only):
    """(chapter, start, end) in seconds from the start of that run's video."""
    lines = open(os.path.join(run_dir, "BotA.log"), encoding="utf-8", errors="replace").read().split("\n")
    stamps = [stamp(x) for x in lines if stamp(x) is not None]
    if not stamps:
        return []
    marks = marks_of(lines)
    zero = first_frame(run_dir)
    if zero is None:
        # an older run: the recording began at the line --record-from waited for, which for a session of scenarios
        # is its first mark, and for a single scenario is its first log line
        zero = marks[0][1] if marks else stamps[0]
    if not marks:
        name = os.path.basename(run_dir).split("-")[-1]
        start = 0.0
        at = marker_at(run_dir, MARKERS.get(name, ""))
        if at is not None:
            start = max(0.0, at - zero - LEAD_IN)
        return [(name, start, min(start + SEGMENT_MAX + SEGMENT_SKIP, stamps[-1] - zero))]
    out = []
    for i, (name, at) in enumerate(marks):
        end = marks[i + 1][1] if i + 1 < len(marks) else stamps[-1]
        if only and name not in only:
            continue
        if at - zero < -1.0:
            continue        # a chapter that ran before the first frame is not in this video
        out.append((name, max(0.0, at - zero), end - zero))
    return out


def split_arg(arg):
    """"<run folder>", "<run folder>:a,b", "<run folder>+30" -> (folder, {a, b}, skip seconds). A drive's own
    colon is not a separator, and a path MSYS wrote (/c/Users/...) is turned back into one this Python can open.
    The skip is for a run whose games were still loading when the recording began."""
    skip = None
    head, plus, tail = arg.rpartition("+")
    if plus and tail.isdigit():
        arg, skip = head, float(tail)
    head, sep, tail = arg.rpartition(":")
    if sep and head and len(head) > 1 and "/" not in tail and "\\" not in tail:
        run_dir, only = head, set(tail.split(","))
    else:
        run_dir, only = arg, set()
    if re.match(r"^/[a-zA-Z]/", run_dir):
        run_dir = run_dir[1].upper() + ":" + run_dir[2:]
    return run_dir, only, skip


def esc(text):
    return text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’")


def caption(name):
    what, version = CAPTIONS.get(name, (name.replace("_", " "), ""))
    # who is who: the first game's window is on the left, the one that joined it on the right
    sides = (f"drawtext=fontfile='{FONT}':text='the host':fontsize=17:fontcolor=white@0.85:x=14:y=12"
             f":box=1:boxcolor=black@0.45:boxborderw=7"
             f",drawtext=fontfile='{FONT}':text='their friend':fontsize=17:fontcolor=white@0.85:x=(w/2)+14:y=12"
             f":box=1:boxcolor=black@0.45:boxborderw=7")
    box = (f"drawtext=fontfile='{FONT}':text='{esc(what)}':fontsize=30:fontcolor=white:x=(w-tw)/2:y=h-96"
           f":box=1:boxcolor=black@0.55:boxborderw=14")
    if version:
        box += (f",drawtext=fontfile='{FONT}':text='{esc(version)}':fontsize=20:fontcolor=0xd8c08a"
                f":x=(w-tw)/2:y=h-52:box=1:boxcolor=black@0.45:boxborderw=8")
    return sides + "," + box


def cut(src, start, length, name, out, size):
    text = caption(name)
    fade = f"fade=t=in:st=0:d=0.4,fade=t=out:st={max(0.5, length - 0.4):.2f}:d=0.4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}", "-i", src,
                    "-t", f"{length:.2f}", "-vf", f"scale={size},{text},{fade}",
                    "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-an", out], check=True)


def title_card(out, size, lines):
    w, h = size.split("x")
    draws = []
    for i, (text, fontsize, dy) in enumerate(lines):
        draws.append(f"drawtext=fontfile='{FONT}':text='{esc(text)}':fontsize={fontsize}:fontcolor=white"
                     f":x=(w-tw)/2:y=(h/2)+{dy}")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
                    f"color=c=0x101014:s={w}x{h}:d={TITLE}:r=30", "-vf",
                    ",".join(draws) + f",fade=t=in:st=0:d=0.5,fade=t=out:st={TITLE - 0.5}:d=0.5",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", out],
                   check=True)


def main():
    out_path = os.path.abspath(sys.argv[1])
    work = os.path.join(os.path.dirname(out_path), "montage-parts")
    os.makedirs(work, exist_ok=True)
    size = os.environ.get("MONTAGE_SIZE", "1280x360")
    parts = []

    card = os.path.join(work, "000-title.mp4")
    title_card(card, size, [("W3Coop", 64, -60), ("The Witcher 3 co-op: what is new since 0.4.0", 28, 10)])
    parts.append(card)

    n = 0
    for arg in sys.argv[2:]:
        run_dir, only, skip = split_arg(arg)
        src = os.path.join(run_dir, "video.mp4")
        if not os.path.exists(src):
            print(f"  (no video.mp4 in {run_dir})")
            continue
        for name, start, end in segments(run_dir, only):
            if skip is not None:
                start, end = skip, max(end, skip + SEGMENT_MAX)
            longest = LENGTH.get(name, SEGMENT_MAX)
            skip_in = max(0.0, SKIP.get(name, SEGMENT_SKIP))
            length = min(longest, end + TAIL.get(name, 0.0) - start - skip_in)
            if length < 4:
                print(f"  (skipped {name}: only {length:.1f}s of it)")
                continue
            n += 1
            part = os.path.join(work, f"{n:03d}-{name}.mp4")
            cut(src, start + skip_in, length, name, part, size)
            parts.append(part)
            print(f"  {name}: {length:.0f}s from {start + skip_in:.0f}s in")

    listing = os.path.join(work, "parts.txt")
    with open(listing, "w", encoding="utf-8") as f:
        for p in parts:
            f.write("file '" + p.replace("\\", "/") + "'\n")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listing,
                    "-c", "copy", out_path], check=True)
    size_mb = os.path.getsize(out_path) / 1e6
    print(f"{out_path}: {len(parts) - 1} segment(s), {size_mb:.1f} MB")


main()
