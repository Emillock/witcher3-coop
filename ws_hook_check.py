# Checks a WitcherScript mod's annotations (@wrapMethod/@replaceMethod/@addMethod/@addField) against a vanilla script tree.
# Heuristic parser (no compiler): finds classes/states, their methods' parameter types and return types, and fields.
# Usage: ws_hook_check.py <vanilla scripts dir> <mod scripts dir> [<extra dep scripts dir> ...]
import os
import re
import sys
from collections import defaultdict


def read_ws(path):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xff\xfe"):
        return raw[2:].decode("utf-16-le", "replace")
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8", "replace")
    if len(raw) > 1 and raw[1:2] == b"\0":
        return raw.decode("utf-16-le", "replace")
    return raw.decode("utf-8", "replace")


def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append('""')
            i = j + 1
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def match_brace(src, open_idx):
    depth = 0
    for k in range(open_idx, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return k
    return len(src) - 1


CLASS_RE = re.compile(r"\b(?:class|struct)\s+(\w+)(?:\s+extends\s+(\w+))?[^{;]*\{")
STATE_RE = re.compile(r"\bstate\s+(\w+)\s+in\s+(\w+)(?:\s+extends\s+(\w+))?[^{;]*\{")
FUNC_RE = re.compile(r"\b(function|event)\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*([\w<>\[\] ,]+?))?\s*(?=[{;])")
FIELD_RE = re.compile(r"(?:^|[;{}\s])(?:(?:private|protected|public|editable|saved|const|import|inlined|autobind|hint)\s+)*var\s+([\w\s,]+?)\s*:\s*([\w<>\[\] ,]+?)\s*(?:=|;)")
ANNO_RE = re.compile(r"@(wrapMethod|replaceMethod|addMethod|addField)\((\w+)\)\s*")


def norm_params(p):
    types = []
    for part in [x.strip() for x in p.split(",") if x.strip()]:
        part = re.sub(r"\b(optional|out|inout)\b", r"\1", part)
        if ":" in part:
            names, typ = part.rsplit(":", 1)
            mods = " ".join(w for w in names.split() if w in ("optional", "out"))
            types.append((mods + " " + typ.strip()).strip().lower())
        else:
            types.append(part.lower())
    return tuple(types)


def norm_ret(r):
    return (r or "void").strip().lower()


def index_tree(root, classes, methods, fields, parents):
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith(".ws"):
                continue
            src = strip_comments(read_ws(os.path.join(dp, f)))
            for rx, is_state in ((CLASS_RE, False), (STATE_RE, True)):
                for m in rx.finditer(src):
                    if is_state:
                        name = f"{m.group(2)}::{m.group(1)}"
                        parent = m.group(3)
                    else:
                        name, parent = m.group(1), m.group(2)
                    body_end = match_brace(src, m.end() - 1)
                    body = src[m.end():body_end]
                    # only top-level members of this body
                    depth, top = 0, []
                    for ch in body:
                        if ch == "{":
                            depth += 1
                            top.append(" ")
                        elif ch == "}":
                            depth -= 1
                            top.append(";")
                        else:
                            top.append(ch if depth == 0 else " ")
                    top = "".join(top)
                    classes[name].add(os.path.relpath(os.path.join(dp, f), root))
                    if parent:
                        parents[name] = parent
                    for fm in FUNC_RE.finditer(top):
                        methods[name][fm.group(2)] = (norm_params(fm.group(3)), norm_ret(fm.group(4)))
                    for vm in FIELD_RE.finditer(top):
                        for v in vm.group(1).split(","):
                            fields[name].add(v.strip())


def lookup(cls, member, methods, fields, parents):
    c = cls
    while c:
        if member in methods.get(c, {}):
            return c, methods[c][member]
        if member in fields.get(c, set()):
            return c, "field"
        c = parents.get(c)
    return None, None


def main():
    vanilla, mod, deps = sys.argv[1], sys.argv[2], sys.argv[3:]
    V = [defaultdict(set), defaultdict(dict), defaultdict(set), {}]
    index_tree(vanilla, *V)
    D = [defaultdict(set), defaultdict(dict), defaultdict(set), {}]
    for d in deps:
        index_tree(d, *D)
    print(f"vanilla: {len(V[0])} classes/states indexed")

    problems, ok = [], 0
    for dp, _, fs in os.walk(mod):
        for f in fs:
            if not f.endswith(".ws"):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, mod)
            src = strip_comments(read_ws(path))
            for am in ANNO_RE.finditer(src):
                kind, cls = am.group(1), am.group(2)
                rest = src[am.end():am.end() + 600]
                in_vanilla = cls in V[0]
                in_deps = cls in D[0]
                if not in_vanilla and not in_deps:
                    problems.append(f"{rel}: @{kind}({cls}) -> class not in vanilla" + (" (no dep scripts given)" if not deps else " or deps"))
                    continue
                src_idx = V if in_vanilla else D
                if kind == "addField":
                    fm = re.match(r"(?:(?:private|protected|public|editable|saved)\s+)*var\s+(\w+)", rest)
                    name = fm.group(1) if fm else "?"
                    owner, sig = lookup(cls, name, src_idx[1], src_idx[2], src_idx[3])
                    if owner:
                        problems.append(f"{rel}: @addField({cls}) {name} collides with existing member in {owner}")
                    else:
                        ok += 1
                    continue
                fm = FUNC_RE.match(re.sub(r"^\s*(?:(?:private|protected|public|final|latent|entry|timer|exec|quest|cleanup|storyscene)\s+)*", "", rest))
                if not fm:
                    problems.append(f"{rel}: @{kind}({cls}) could not parse following declaration: {rest[:80]!r}")
                    continue
                name, params, ret = fm.group(2), norm_params(fm.group(3)), norm_ret(fm.group(4))
                owner, sig = lookup(cls, name, src_idx[1], src_idx[2], src_idx[3])
                if kind == "addMethod":
                    if owner:
                        problems.append(f"{rel}: @addMethod({cls}) {name} collides with existing method in {owner}")
                    else:
                        ok += 1
                    continue
                # wrapMethod / replaceMethod need the method declared on that exact class
                if name not in src_idx[1].get(cls, {}):
                    where = f" (found on ancestor {owner})" if owner else ""
                    problems.append(f"{rel}: @{kind}({cls}) {name} -> method not declared on {cls}{where}")
                    continue
                vp, vr = src_idx[1][cls][name]
                if vp != params or vr != ret:
                    problems.append(f"{rel}: @{kind}({cls}) {name} signature differs: mod {params}->{ret} vs game {vp}->{vr}")
                else:
                    ok += 1
    print(f"annotations OK: {ok}")
    print(f"problems: {len(problems)}")
    for p in problems:
        print("  - " + p)


if __name__ == "__main__":
    main()
