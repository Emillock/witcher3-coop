# Runs several run_test.py scenarios and prints a summary table. Scenarios that can share a game run as one session
# (the games load once); the others get fresh games each.
# Usage: run_suite.py [--steam-box BOX [--all]] [--duration S] [--no-session] [scenario ...]   (default: every
# scenario; over Steam a subset). The scenario gwent_duel runs every entry of GWENT_DUEL_MATRIX (not in the default).
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
             "enemy_spells", "enemy_moves", "enemy_crowd", "member_death", "leader_death", "follow_travel", "party_invite", "puppet_timeout", "gwent_vanilla", "gwent_selftest"]  # puppet_walk also checks what puppet_follow does
# over Steam only the transport differs: these cover connecting, movement, the co-op channel both ways and the snapshot
STEAM_SCENARIOS = ["movement", "shared_enemy", "member_combat", "sign_visuals"]
# need fresh games: they change the save's quests and facts, join late on purpose, travel 1 km to a nest, or (attack_view)
# need the leader's monster to go for the leader alone, which leftovers of other scenarios upset, or (member_death)
# reload a save (member_death, leader_death), or (gwent_vanilla, gwent_selftest) run in one game only
FRESH = ["quest_sync", "dialog_sync", "facts_sync", "real_encounter", "attack_view", "member_death", "leader_death", "follow_travel", "party_invite", "puppet_timeout", "gwent_vanilla", "gwent_selftest"]


# gwent_duel deck/seed matrix: one two-bot gwent_duel run per entry (label, W3T_* settings), in this order.
# Canonical order of simultaneous effects (spec 7.4, WitcherOnline Task 13): every pair and seed tried for a divergence
# is kept. On the board before that change pirate_ske,pirate_ske seed 1 diverged at seq 8 (round 1, scorch and muster
# landings: clan_dimun_pirate's scorch); muster_nml,muster_nml seeds 1 and 2 were tried too (both passed). Seeds 2 to 5
# of pirate_ske add round 3 perks of both seats with the change.
# Decisions, coin toss and mulligan (Task 12): its matrix, the corrupt check, a tricks pair and the leader-first pairs.
GWENT_DUEL_MATRIX = [
    (f"pirate_ske-pirate_ske-s{seed}", {"W3T_GWENT_DECKS": "pirate_ske,pirate_ske", "W3T_GWENT_SEED": seed}) for seed in ["1", "2", "3", "4", "5"]
] + [
    ("muster_nml-muster_nml-s1", {"W3T_GWENT_DECKS": "muster_nml,muster_nml", "W3T_GWENT_SEED": "1"}),
    ("muster_nml-muster_nml-s2", {"W3T_GWENT_DECKS": "muster_nml,muster_nml", "W3T_GWENT_SEED": "2"}),
] + [
    (f"{pair.replace(',', '-')}-s{seed}", {"W3T_GWENT_DECKS": pair, "W3T_GWENT_SEED": seed, "W3T_GWENT_MULLIGAN": "1"})
    for pair in ["medic_nr,leaders_nilf", "agile_medic,plain_nml", "scotial,nml", "Nilf,North", "nml,nml"]
    for seed in ["1", "12345"]
] + [
    ("corrupt-plain_nr-plain_nilf-s1", {"W3T_GWENT_DECKS": "plain_nr,plain_nilf", "W3T_GWENT_SEED": "1", "W3T_GWENT_CORRUPT_AT": "8",
                                         "W3T_GWENT_EXPECT": "nocontest", "W3T_GWENT_REASON": "desync"}),
    ("tricks_nr-tricks_nilf-s12345", {"W3T_GWENT_DECKS": "tricks_nr,tricks_nilf", "W3T_GWENT_SEED": "12345"}),
    ("leaderfirst-bin_nml-view_nilf-s1", {"W3T_GWENT_DECKS": "bin_nml,view_nilf", "W3T_GWENT_SEED": "1", "W3T_GWENT_MULLIGAN": "1",
                                           "W3T_GWENT_LEADER_FIRST": "1"}),
    ("leaderfirst-weather_nml-res_nml-s1", {"W3T_GWENT_DECKS": "weather_nml,res_nml", "W3T_GWENT_SEED": "1", "W3T_GWENT_MULLIGAN": "1",
                                             "W3T_GWENT_LEADER_FIRST": "1"}),
]
GWENT_DUEL = "gwent_duel"
GWENT_DUEL_SWITCHES = ["W3T_GWENT_DECKS", "W3T_GWENT_SEED", "W3T_GWENT_MULLIGAN", "W3T_GWENT_LEADER_FIRST", "W3T_GWENT_CORRUPT_AT",
                       "W3T_GWENT_EXPECT", "W3T_GWENT_REASON"]


def run_gwent_matrix(label):
    # runs every GWENT_DUEL_MATRIX entry as its own gwent_duel (its own W3T_* settings, run_test.py's gwent_duel
    # duration and timeout); returns the summary rows
    rows = []
    for name, settings in GWENT_DUEL_MATRIX:
        out = os.path.join(WORK, "runs", f"suite_{label}_gwent_duel_{name}_{time.strftime('%H%M%S')}.out")
        env = {k: v for k, v in os.environ.items() if k not in GWENT_DUEL_SWITCHES}
        env.update(settings)
        t0 = time.time()
        with open(out, "w") as f:
            subprocess.run([sys.executable, os.path.join(HERE, "run_test.py"), GWENT_DUEL], stdout=f, stderr=subprocess.STDOUT, env=env)
        text = open(out, encoding="utf-8", errors="replace").read()
        m = re.search(r"RESULT: (PASS|FAIL) \((.*)\)", text)
        rows.append((f"{GWENT_DUEL} {name}", m.group(1) if m else "ERROR", int(time.time() - t0), m.group(2) if m else "no result line"))
        print(f"{rows[-1][0]:40} {rows[-1][1]:5} {rows[-1][2]:4}s  {rows[-1][3][:110]}", flush=True)
    return rows


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
    if GWENT_DUEL in a.scenarios:
        a.scenarios = [s for s in a.scenarios if s != GWENT_DUEL]
        rows += run_gwent_matrix(label)
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
