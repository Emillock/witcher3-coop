# Lists type names a WitcherScript mod uses (var/param/return/array element types) that no tree in scope declares.
# Usage: ws_type_check.py <mod scripts dir> <declaring tree> [...]
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ws_hook_check import read_ws, strip_comments  # noqa: E402
from ws_undefined_check import walk, TYPE_RE  # noqa: E402

BUILTIN = {"int", "float", "bool", "string", "name", "CName", "byte", "Uint64", "Int64", "Uint32", "Int32", "Uint16",
           "Int16", "Uint8", "Int8", "void", "array", "handle", "Vector", "EulerAngles", "Matrix", "Color", "Box",
           "Sphere", "EngineTime", "GameTime", "SItemUniqueId", "IdTag", "EntityHandle", "CDateTime", "Double"}
USE_RE = re.compile(r":\s*(?:array\s*<\s*)?(?:handle\s*:\s*)?([A-Za-z_]\w*)")
DECL_EXTRA_RE = re.compile(r"\bimport\s+(?:abstract\s+|statemachine\s+)*(?:class|struct|enum)\s+(\w+)")


def main():
    mod, trees = sys.argv[1], sys.argv[2:]
    declared = set(BUILTIN)
    for t in trees + [mod]:
        for p in walk(t):
            src = strip_comments(read_ws(p))
            declared.update(TYPE_RE.findall(src))
            declared.update(DECL_EXTRA_RE.findall(src))
    used = defaultdict(list)
    for p in walk(mod):
        src = strip_comments(read_ws(p))
        for i, line in enumerate(src.splitlines(), 1):
            if "?" in line and "case" in line:
                continue
            for m in USE_RE.finditer(line):
                t = m.group(1)
                if t not in declared:
                    used[t].append(f"{os.path.relpath(p, mod)}:{i}")
    for t in sorted(used, key=lambda n: (-len(used[n]), n)):
        print(f"{t:36s} {len(used[t]):4d}  e.g. {used[t][0]}")


if __name__ == "__main__":
    main()
