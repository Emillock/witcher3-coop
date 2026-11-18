# Cuts the recordings of filmed runs into a captioned reel of what co-op does.
# Usage: montage.py <out.mp4> <run folder>[:scenario[,scenario...]] ...
#   montage.py work/dist/reel.mp4 work/runs/2026...-session9 work/runs/2026...-scene_follow:scene_follow
# A run's video.mp4 starts at the line --record-from waited for, so every segment's place in it is the
# difference between two stamps in the bot's own log: no guessing, and a re-filmed run needs no new figures.
# Segments are cut, captioned (CAPTIONS below), faded and joined. ffmpeg does the work.
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "C\\:/Windows/Fonts/segoeui.ttf"
SEGMENT_MAX = 26.0      # no segment outstays its welcome
SEGMENT_SKIP = 2.0      # the first seconds of a scenario are the bots getting into place
TITLE = 3.0             # how long the opening card stays

# What each scenario is there to show. The second line is the version it came in.
CAPTIONS = {
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


def stamp(line):
    """The seconds-of-day a bot log line carries, or None."""
    m = re.match(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d) ", line)
    if not m:
        return None
    h, mi, s, ms = (int(m.group(i)) for i in range(1, 5))
    return h * 3600 + mi * 60 + s + ms / 1000.0


def segments(run_dir, only):
    """(scenario, start, end) in seconds from the start of that run's video."""
    log = os.path.join(run_dir, "BotA.log")
    lines = open(log, encoding="utf-8", errors="replace").read().split("\n")
    marks = []
    for line in lines:
        m = re.search(r"SCENARIO (\S+) start", line)
        if m and stamp(line) is not None:
            marks.append((m.group(1), stamp(line)))
    # The recording began when --record-from was seen in this log, which for a session is its first scenario's
    # start line; the video keeps real time from there, so a stamp minus that is a place in the video.
    zero = marks[0][1] if marks else None
    if not marks:                           # a single-scenario run: the whole thing is one segment
        starts = [stamp(x) for x in lines if stamp(x) is not None]
        name = os.path.basename(run_dir).split("-")[-1]
        if not starts:
            return []
        zero = next((stamp(x) for x in lines if "BOT start" in x), starts[0])
        # The second game opens its window a little after the first, and until it does the frames taken from
        # that half of the screen are of whatever is behind it. Start once that bot is in its game.
        settle = 0.0
        other = os.path.join(run_dir, "BotB.log")
        if os.path.exists(other):
            for line in open(other, encoding="utf-8", errors="replace"):
                if "BOT start" in line and stamp(line) is not None:
                    settle = max(0.0, stamp(line) - zero) + 5.0
                    break
        return [(name, settle, min(settle + SEGMENT_MAX, starts[-1] - zero))]
    out = []
    for i, (name, at) in enumerate(marks):
        end = marks[i + 1][1] if i + 1 < len(marks) else None
        if end is None:
            end = max((stamp(x) for x in lines if stamp(x) is not None), default=at + SEGMENT_MAX)
        if only and name not in only:
            continue
        out.append((name, at - zero, end - zero))
    return out


def split_arg(arg):
    """"<run folder>", "<run folder>:a,b", "<run folder>+30" -> (folder, {a, b}, skip seconds). A drive's own
    colon is not a separator, and a path MSYS wrote (/c/Users/...) is turned back into one this Python can open.
    The skip is for a run whose games were still loading when the recording began: until a game paints, the
    frames taken from its half of the screen are of whatever is behind it."""
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
    box = (f"drawtext=fontfile='{FONT}':text='{esc(what)}':fontsize=30:fontcolor=white:x=(w-tw)/2:y=h-96"
           f":box=1:boxcolor=black@0.55:boxborderw=14")
    if version:
        box += (f",drawtext=fontfile='{FONT}':text='{esc(version)}':fontsize=20:fontcolor=0xd8c08a"
                f":x=(w-tw)/2:y=h-52:box=1:boxcolor=black@0.45:boxborderw=8")
    return box


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
            length = min(SEGMENT_MAX, end - start - SEGMENT_SKIP)
            if length < 4:
                print(f"  (skipped {name}: only {length:.1f}s of it)")
                continue
            n += 1
            part = os.path.join(work, f"{n:03d}-{name}.mp4")
            cut(src, start + SEGMENT_SKIP, length, name, part, size)
            parts.append(part)
            print(f"  {name}: {length:.0f}s from {start + SEGMENT_SKIP:.0f}s in")

    listing = os.path.join(work, "parts.txt")
    with open(listing, "w", encoding="utf-8") as f:
        for p in parts:
            f.write("file '" + p.replace("\\", "/") + "'\n")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listing,
                    "-c", "copy", out_path], check=True)
    size_mb = os.path.getsize(out_path) / 1e6
    print(f"{out_path}: {len(parts) - 1} segment(s), {size_mb:.1f} MB")


main()
