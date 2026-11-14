# How far a copy really is from the monster it copies, at the same instant, out of a puppet_follow run's logs.
# Usage: sync_error.py <run folder>       (a puppet_follow run's folder under work/runs)
# Run it on a run made with a fine tick and, to see what a real link does, with the link flags:
#   W3T_TICK=0.1 run_test.py puppet_follow --save ManualSave_5258b --delay 150 --jitter 60 --loss 5
# The member can only measure itself against the position it was told, which leaves out the whole trip. Both bots
# log their positions with a clock and both run on this one machine, so the leader's track is interpolated at each
# of the member's samples and the two are compared for real. W3T_NO_LEAD=1 on the run measures what a copy did
# before it was led (SetSyncLeadForTest).
import math
import re
import sys

LEADER = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d) MOVES leader monster at ([-\d.]+),([-\d.]+),([-\d.]+)")
MEMBER = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d) FOLLOW member puppet at ([-\d.]+),([-\d.]+),([-\d.]+)"
                    r" gap=([-\d.]+)")


def track(path, pattern):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pattern.match(line.strip())
        if m:
            h, mi, s, ms = (int(m.group(i)) for i in range(1, 5))
            t = h * 3600 + mi * 60 + s + ms / 1000.0
            out.append((t, float(m.group(5)), float(m.group(6)), float(m.group(7)),
                        float(m.group(8)) if pattern is MEMBER else 0.0))
    return out


def at(points, t):
    """The leader's position at t, interpolated between the samples around it (None outside the track)."""
    if not points or t < points[0][0] or t > points[-1][0]:
        return None
    lo, hi = 0, len(points) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if points[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    a, b = points[lo], points[hi]
    span = b[0] - a[0]
    k = 0.0 if span <= 0 else (t - a[0]) / span
    return tuple(a[1 + i] + (b[1 + i] - a[1 + i]) * k for i in range(3))


def main(run_dir):
    lead = track(run_dir + "/BotA.log", LEADER)
    mem = track(run_dir + "/BotB.log", MEMBER)
    errs, gaps, moving = [], [], 0
    for i, (t, x, y, z, gap) in enumerate(mem):
        p = at(lead, t)
        if not p:
            continue
        errs.append(math.dist((x, y, z), p))
        gaps.append(gap)
        if i and math.dist((x, y, z), (mem[i - 1][1], mem[i - 1][2], mem[i - 1][3])) > 0.05:
            moving += 1
    if not errs:
        sys.exit("no overlapping samples (is this a puppet_follow run?)")
    errs.sort()
    print(f"{len(errs)} samples, the copy moving in {moving} of them")
    print(f"true error against the monster: mean {sum(errs) / len(errs):.2f} m, median "
          f"{errs[len(errs) // 2]:.2f} m, 90th {errs[int(len(errs) * 0.9)]:.2f} m, max {max(errs):.2f} m")
    print(f"what the member can see (copy to the position it was told): mean {sum(gaps) / len(gaps):.2f} m, "
          f"max {max(gaps):.2f} m")
    speeds(lead, mem)


def speeds(lead, mem):
    """How evenly the copy moves against how evenly the monster does: a steady lag is invisible, a copy that
    stalls and then jumps is what a player calls stuttering."""
    def profile(points):
        out = []
        for a, b in zip(points, points[1:]):
            dt = b[0] - a[0]
            if 0.02 < dt < 0.5:
                out.append(math.dist(b[1:4], a[1:4]) / dt)
        return out

    lo, hi = profile(lead), profile(mem)
    if not lo or not hi:
        return
    for name, v in (("monster", lo), ("copy", hi)):
        mean = sum(v) / len(v)
        sd = math.sqrt(sum((x - mean) ** 2 for x in v) / len(v))
        print(f"{name:8} speed: mean {mean:.2f} m/s, sd {sd:.2f}, max {max(v):.2f}")
    moving = [x for x in hi if x > 0.2]
    stalls = sum(1 for x in hi if x < 0.3)
    jumps = sum(1 for x in hi if x > 2 * (sum(lo) / len(lo)) + 1)
    print(f"copy samples: {len(hi)}, moving {len(moving)}, near-still {stalls}, jumps {jumps}")


main(sys.argv[1].rstrip("/\\"))
