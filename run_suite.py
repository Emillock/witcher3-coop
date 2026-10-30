# Runs several run_test.py scenarios and prints a summary table. Scenarios that can share a game run as one session
# (the games load once); the others get fresh games each.
# Usage: run_suite.py [--steam-box BOX [--all]] [--duration S] [--no-session] [scenario ...]   (default: every
# scenario; over Steam a subset)
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from config import WORK  # noqa: E402
from run_test import missing_test_build  # noqa: E402

# enemy_moves last in a session: its leader fights the bandit itself, which carries over (combat state)
SCENARIOS = ["see_each_other", "movement", "version_check", "party_hud", "horse_ride", "social", "trade", "player_effects", "shared_enemy", "enemy_attacks", "mounted_fight", "reactions", "twin_match", "encounter_mismatch", "handoff", "quest_sync",
             "dialog_sync", "facts_sync", "puppet_walk", "real_encounter", "enemy_projectiles", "member_combat", "enemy_effects", "sign_visuals", "attack_view",
             "enemy_spells", "enemy_moves", "enemy_crowd", "member_death", "leader_death"]  # puppet_walk also checks what puppet_follow does
# over Steam only the transport differs: these cover connecting, movement, the co-op channel both ways and the snapshot
STEAM_SCENARIOS = ["movement", "shared_enemy", "member_combat", "sign_visuals"]
# need fresh games: they change the save's quests and facts, join late on purpose, travel 1 km to a nest, or (attack_view)
# need the leader's monster to go for the leader alone, which leftovers of other scenarios upset, or (member_death)
# reload a save (member_death, leader_death)
FRESH = ["quest_sync", "dialog_sync", "facts_sync", "real_encounter", "attack_view", "member_death", "leader_death"]


def plan(scenarios, sessions):
    # the run_test.py runs: one session of everything that can share a game, then the rest one by one
    shared = [s for s in scenarios if s not in FRESH] if sessions else []
    rest = [s for s in scenarios if s not in shared]
    return ([",".join(shared)] if len(shared) > 1 else shared) + rest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*")
    ap.add_argument("--steam-box", help="run over real Steam (see run_test.py --steam-box); default scenarios: STEAM_SCENARIOS")
    ap.add_argument("--all", action="store_true", help="every scenario, also over Steam")
    ap.add_argument("--duration", type=int, default=300)
    ap.add_argument("--no-session", action="store_true", help="fresh games for every scenario (slower)")
    a = ap.parse_args()
    if not a.scenarios:
        a.scenarios = STEAM_SCENARIOS if a.steam_box and not a.all else SCENARIOS

    missing = missing_test_build()
    if missing:
        print(f"the test build is not deployed ({', '.join(missing)} missing; compile.sh deploys it)")
        return 2
    label = "steam" if a.steam_box else "local"
    os.makedirs(os.path.join(WORK, "runs"), exist_ok=True)
    rows = []
    for run in plan(a.scenarios, not a.no_session):
        out = os.path.join(WORK, "runs", f"suite_{label}_{run.split(',')[0]}_{time.strftime('%H%M%S')}.out")
        cmd = [sys.executable, os.path.join(HERE, "run_test.py"), run, "--duration", str(a.duration), "--timeout", "3600" if "," in run else "900"]
        if a.steam_box:
            cmd += ["--steam-box", a.steam_box]
        t0 = time.time()
        with open(out, "w") as f:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
        text = open(out, encoding="utf-8", errors="replace").read()
        if "," in run:
            found = {m.group(1): m for m in re.finditer(r"RESULT (\S+): (PASS|FAIL) \((.*)\) \[(\d+)s\]", text)}
            for scenario in run.split(","):
                m = found.get(scenario)
                rows.append((scenario, m.group(2) if m else "ERROR", int(m.group(4)) if m else 0, m.group(3) if m else "no result line"))
                print(f"{scenario:16} {rows[-1][1]:5} {rows[-1][2]:4}s  {rows[-1][3][:110]}", flush=True)
            print(f"  (one session, {int(time.time() - t0)}s in all)", flush=True)
        else:
            m = re.search(r"RESULT: (PASS|FAIL) \((.*)\)", text)
            rows.append((run, m.group(1) if m else "ERROR", int(time.time() - t0), m.group(2) if m else "no result line"))
            print(f"{run:16} {rows[-1][1]:5} {rows[-1][2]:4}s  {rows[-1][3][:110]}", flush=True)
        if "the owner's Documents changed" in text or "the test build is not deployed" in text:
            print("stopping the suite: see " + out, flush=True)
            break

    passed = sum(r[1] == "PASS" for r in rows)
    print(f"{label}: {passed}/{len(rows)} passed")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
