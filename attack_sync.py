# How closely members' copies follow the leader's monsters' attacks in a run (both games on one PC, so the tick
# clock is shared): per attack, whether the copy started the same attack task and the same animation, and how long
# after the leader's monster (transfer: until the member got it; reaction: until its copy started: the leader's
# animation on its slot, or else its own attack task).
# Usage: attack_sync.py <run dir> [scenario]   (scenario: only that part of a session's logs)
import os
import statistics
import sys


def events(path, scenario):
    out = []
    started = scenario is None
    for line in open(path, encoding="utf-8", errors="replace"):
        if scenario and f"SCENARIO {scenario} start" in line:
            started = True
        elif scenario and started and "SCENARIO " in line and " start" in line and scenario not in line:
            break
        if not started or " SYNC " not in line:
            continue
        # "hh:mm:ss.mmm SYNC kind netId seq what engineTime wall=ms"
        parts = line.split()
        kind, net, seq, what = parts[2], parts[3], parts[4], parts[5]
        wall = int(parts[-1].split("=")[1])
        out.append((kind, int(net), int(seq), what, wall))
    return out


def pct(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))]


def main():
    run = sys.argv[1]
    scenario = sys.argv[2] if len(sys.argv) > 2 else None
    lead = events(os.path.join(run, "BotA.log"), scenario)
    memb = events(os.path.join(run, "BotB.log"), scenario)
    starts = {(n, s): (w, t) for k, n, s, w, t in [(e[0], e[1], e[2], e[3], e[4]) for e in lead] if k == "L"}
    lanims = {(n, s): w for k, n, s, w, t in lead if k == "LA"}
    lwindows = {(n, s): t for k, n, s, w, t in lead if k == "LA"}
    lhits = {}
    for k, n, s, w, t in lead:
        if k == "LH" and (n, s) not in lhits:
            lhits[(n, s)] = t
    early = {(n, s): w.split("/")[0] for k, n, s, w, t in lead if k == "LE"}
    got, copies, canims, slots, cwindows = {}, {}, {}, {}, {}
    for k, n, s, w, t in memb:
        if k == "R" and (n, s) not in got:
            got[(n, s)] = (w, t)
        elif k == "MS" and (n, s) in got and (n, s) not in slots:
            slots[(n, s)] = (w, t)
        elif k == "M" and (n, s) in got and (n, s) not in copies:
            copies[(n, s)] = (w, t)
        elif k == "MA" and (n, s) not in canims:
            canims[(n, s)] = w
            cwindows[(n, s)] = t
    # a slot start is the start of the leader's attack (same task) with its animation
    for a, (w, t) in slots.items():
        if a not in copies or copies[a][1] > t:
            copies[a] = (starts[a][0] if a in starts else "?", t)
    total = len(starts)
    received = [a for a in starts if a in got]
    started = [a for a in received if a in copies]
    same = [a for a in started if copies[a][0] == starts[a][0]]
    # the copy's animation: the one started on its slot, else its first hit window (an overlapping earlier swing's
    # hit window can come first)
    for a, (w, t) in slots.items():
        canims[a] = w
    anims = [a for a in started if a in lanims and a in canims]
    same_anim = [a for a in anims if lanims[a] == canims[a].split("#")[0]]
    transfer = [got[a][1] - starts[a][1] for a in received]
    reaction = [copies[a][1] - got[a][1] for a in started]
    delay = [copies[a][1] - starts[a][1] for a in started]
    print(f"leader attacks {total}, received {len(received)}, copy started {len(started)} ({len(slots)} on the slot), "
          f"same task {len(same)}, same animation {len(same_anim)} of {len(anims)}")
    tasks = {}
    for a in starts:
        tasks[starts[a][0]] = tasks.get(starts[a][0], 0) + 1
    print("tasks:", ", ".join(f"{k} x{v}" for k, v in sorted(tasks.items(), key=lambda kv: -kv[1])))
    catchups = [float(w) for k, n, s, w, t in memb if k == "MC"]
    if catchups:
        print(f"caught up {len(catchups)} slot attacks named late (behind median {statistics.median(catchups) * 1000:.0f} ms)")
    named = [a for a in early if a in lanims]
    if named:
        print(f"named early {len(early)}, as its hit window {sum(early[a] == lanims[a] for a in named)} of {len(named)}")
    for label, vals in (("transfer", transfer), ("reaction", reaction), ("delay", delay)):
        if vals:
            print(f"{label:9} median {statistics.median(vals):5.0f} ms   p90 {pct(vals, 0.9):5.0f} ms   max {max(vals):5.0f} ms")
    lags = [cwindows[a] - lwindows[a] for a in same_anim if a in cwindows and a in lwindows]
    if lags:
        print(f"hit window  median {statistics.median(lags):5.0f} ms   p90 {pct(lags, 0.9):5.0f} ms   max {max(lags):5.0f} ms "
              "(copy's after the leader's)")
    # hits early in an attack (before its hit window): did the copy's swing stop where the leader's did?
    early = [a for a in lhits if a in starts and lhits[a] - starts[a][1] < 1000 and (a not in lwindows or lhits[a] < lwindows[a])]
    if early:
        cut = [a for a in early if a not in lwindows]
        slotted = [a for a in cut if a in slots]
        print(f"hit before the hit window {len(early)}: leader's swing cut short {len(cut)}; of those started on the copy's "
              f"slot {len(slotted)}, cut short there too {sum(a not in cwindows for a in slotted)}")
    # moves: the leader's (LMV kind/anim) against the member's (MV: on the slot; MM: its own AI's move animation)
    lmoves = {(n, s): (w, t) for k, n, s, w, t in lead if k == "LMV"}
    mmoves = {}
    for k, n, s, w, t in memb:
        if k in ("MV", "MM") and (n, s) not in mmoves:
            mmoves[(n, s)] = (w, t)
    if lmoves:
        played = [a for a in lmoves if a in mmoves]
        same_move = [a for a in played if lmoves[a][0].split("/")[-1] == mmoves[a][0]]
        print(f"moves {len(lmoves)}, shown {len(played)}, same animation {len(same_move)}")
        mdelay = [mmoves[a][1] - lmoves[a][1] for a in played]
        if mdelay:
            print(f"move delay median {statistics.median(mdelay):5.0f} ms   p90 {pct(mdelay, 0.9):5.0f} ms   max {max(mdelay):5.0f} ms")
    # script effects: each one the leader's monster started (LF: the set playing now) and the copy's start (MF), within 2 s
    fx_starts, playing = [], {}
    for k, n, s, w, t in lead:
        if k == "LF":
            now = set() if w == "-" else set(w.split(","))
            fx_starts += [(n, f, t) for f in now - playing.get(n, set())]
            playing[n] = now
    if fx_starts:
        mfx = [(n, w, t) for k, n, s, w, t in memb if k == "MF"]
        fdelay = []
        for n, f, t in fx_starts:
            later = [mt - t for mn, mw, mt in mfx if mn == n and mw == f and -100 <= mt - t <= 2000]
            if later:
                fdelay.append(min(later))
        print(f"script effects started {len(fx_starts)} ({', '.join(sorted({f for n, f, t in fx_starts}))}), on the copy {len(fdelay)}"
              + (f", delay median {statistics.median(fdelay):.0f} ms max {max(fdelay):.0f} ms" if fdelay else ""))
    # effects put straight on the member's ghost (LD) and applied to the member (MD: type/result), hit effects (MW)
    ld = [w for k, n, s, w, t in lead if k == "LD"]
    md = [w for k, n, s, w, t in memb if k == "MD"]
    mw = [w for k, n, s, w, t in memb if k == "MW"]
    if ld or md or mw:
        print(f"direct effects sent {len(ld)}, applied {len(md)} ({', '.join(md[:8])}); hit effects shown {len(mw)} ({', '.join(mw[:4])})")
    ticks = [w for k, n, s, w, t in lead if k == "LU"]
    if ticks:
        print(f"damage ticks of tasks sent as hurts {len(ticks)}")
    missed = [a for a in received if a not in copies]
    other = [a for a in started if copies[a][0] != starts[a][0]]
    # an attack task the monster's tree replaced with another within 0.3 s, before anything named its animation, never
    # showed on the leader either (the copy plays the one that followed)
    named = {(n, s) for k, n, s, w, t in lead if k in ("LE", "LA")}
    order = sorted(starts, key=lambda a: starts[a][1])
    replaced = {a for a, b in zip(order, order[1:]) if a[0] == b[0] and a not in named and starts[b][1] - starts[a][1] < 300}
    if replaced & set(missed):
        print(f"replaced within 0.3 s before showing: {len(replaced & set(missed))}")
    missed = [a for a in missed if a not in replaced]
    if missed:
        print("not started:", ", ".join(f"{starts[a][0]}" for a in missed[:12]))
    if other:
        print("other task:", ", ".join(f"{starts[a][0]}->{copies[a][0]}" for a in other[:12]))
    diff = [a for a in anims if lanims[a] != canims[a]]
    if diff:
        print("other animation:", ", ".join(f"{lanims[a]}->{canims[a]}" for a in diff[:8]))


if __name__ == "__main__":
    main()
