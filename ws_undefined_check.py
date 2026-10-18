# Lists identifiers a WitcherScript mod calls (Name( or .Name() that no script tree in scope declares.
# Heuristic (no type checking): catches natives from missing dependency mods and API removed by a game patch.
# Usage: ws_undefined_check.py <mod scripts dir> <declaring tree> [<declaring tree> ...]
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ws_hook_check import read_ws, strip_comments  # noqa: E402

DECL_RE = re.compile(r"\b(?:function|event)\s+(\w+)\s*\(")
TYPE_RE = re.compile(r"\b(?:class|struct|enum|state)\s+(\w+)")
ENUM_BODY_RE = re.compile(r"\benum\s+\w+\s*\{([^}]*)\}", re.S)
CALL_RE = re.compile(r"(\.)?\b([A-Za-z_]\w*)\s*\(")
KEYWORDS = {
    "if", "while", "for", "switch", "return", "function", "event", "super", "parent", "virtual_parent", "new",
    "delete", "default", "case", "else", "do", "foreach", "in", "NameToString", "StringToName", "NameToFlashUInt",
    "IntToString", "FloatToString", "StrLen", "LogChannel", "Log", "this", "SpawnEntity", "array", "EnumGetMax",
}


def walk(root):
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(".ws"):
                yield os.path.join(dp, f)


def main():
    mod, trees = sys.argv[1], sys.argv[2:]
    declared = set()
    for t in trees + [mod]:
        for p in walk(t):
            src = strip_comments(read_ws(p))
            declared.update(DECL_RE.findall(src))
            declared.update(TYPE_RE.findall(src))
            for body in ENUM_BODY_RE.findall(src):
                declared.update(re.findall(r"\b([A-Za-z_]\w*)\b", body))
    used = defaultdict(list)
    for p in walk(mod):
        src = strip_comments(read_ws(p))
        for i, line in enumerate(src.splitlines(), 1):
            for m in CALL_RE.finditer(line):
                name = m.group(2)
                if name in declared or name in KEYWORDS:
                    continue
                if re.match(r"\s*(?:function|event)\b", line[max(0, m.start() - 20):m.start()][-20:]):
                    continue
                used[name].append(f"{os.path.relpath(p, mod)}:{i}")
    for name in sorted(used, key=lambda n: (-len(used[n]), n)):
        sites = used[name]
        print(f"{name:40s} {len(sites):4d}  e.g. {sites[0]}")


if __name__ == "__main__":
    main()
