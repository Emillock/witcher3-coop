# Snapshot (path -> size, mtime) for the folders the game may write; diff two snapshots.
# Usage: snap.py save <out.json> | snap.py diff <a.json> <b.json>
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import GAME, USER_W3_DOCS  # noqa: E402

LOCAL, ROAMING = os.environ["LOCALAPPDATA"], os.environ["APPDATA"]
ROOTS = [USER_W3_DOCS, os.path.join(LOCAL, "REDEngine"), os.path.join(LOCAL, "CD Projekt Red"), os.path.join(LOCAL, "mod.io"),
         os.path.join(ROAMING, "The Witcher 3"), os.path.join(ROAMING, "CD Projekt Red"), GAME]


def snap():
    out = {}
    for root in ROOTS:
        for dp, _, fns in os.walk(root):
            for f in fns:
                p = os.path.join(dp, f)
                try:
                    st = os.stat(p)
                    out[p] = [st.st_size, int(st.st_mtime)]
                except OSError:
                    pass
    return out


if sys.argv[1] == "save":
    json.dump(snap(), open(sys.argv[2], "w"))
else:
    a, b = json.load(open(sys.argv[2])), json.load(open(sys.argv[3]))
    for p in sorted(set(a) | set(b)):
        if p not in a:
            print("NEW    ", b[p][0], p)
        elif p not in b:
            print("GONE   ", p)
        elif a[p] != b[p]:
            print("CHANGED", a[p][0], "->", b[p][0], p)
