# Exact-text edits for WitcherScript files that keep each file's newline style.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import WO  # noqa: E402

SCRIPTS = os.path.join(WO, "witcher", "mods", "modWitcherOnline", "content", "scripts")


def edit(rel, pairs, count_all=False):
    path = os.path.join(SCRIPTS, rel)
    s = open(path, newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    for old, new in pairs:
        old_n, new_n = old.replace("\n", nl), new.replace("\n", nl)
        n = s.count(old_n)
        if n == 0 or (n > 1 and not count_all):
            raise SystemExit(f"{rel}: expected exactly one match for {old[:70]!r}, found {n}")
        s = s.replace(old_n, new_n)
        print(f"{rel}: replaced {n}x {old.strip()[:60]!r}")
    open(path, "w", newline="").write(s)
