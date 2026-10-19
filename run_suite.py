# Runs several run_test.py scenarios one after another and prints a summary table.
# Usage: run_suite.py [--steam-box BOX] [--duration S] [scenario ...]   (default: every scenario)
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from config import WORK  # noqa: E402

SCENARIOS = ["see_each_other", "movement", "shared_enemy", "enemy_attacks", "reactions", "twin_match", "handoff", "quest_sync",
             "dialog_sync", "facts_sync", "puppet_follow"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", default=SCENARIOS)
    ap.add_argument("--steam-box", help="run over real Steam (see run_test.py --steam-box)")
    ap.add_argument("--duration", type=int, default=300)
    a = ap.parse_args()

    label = "steam" if a.steam_box else "local"
    os.makedirs(os.path.join(WORK, "runs"), exist_ok=True)
    rows = []
    for scenario in a.scenarios:
        out = os.path.join(WORK, "runs", f"suite_{label}_{scenario}_{time.strftime('%H%M%S')}.out")
        cmd = [sys.executable, os.path.join(HERE, "run_test.py"), scenario, "--duration", str(a.duration), "--timeout", "900"]
        if a.steam_box:
            cmd += ["--steam-box", a.steam_box]
        t0 = time.time()
        with open(out, "w") as f:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
        text = open(out, encoding="utf-8", errors="replace").read()
        m = re.search(r"RESULT: (PASS|FAIL) \((.*)\)", text)
        rows.append((scenario, m.group(1) if m else "ERROR", int(time.time() - t0), m.group(2) if m else "no result line"))
        print(f"{scenario:16} {rows[-1][1]:5} {rows[-1][2]:4}s  {rows[-1][3][:110]}", flush=True)

    passed = sum(r[1] == "PASS" for r in rows)
    print(f"{label}: {passed}/{len(rows)} passed")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
