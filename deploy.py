# Installs the Witcher Online port from the repo into the game folder, recording every file in a manifest so
# `uninstall` removes exactly what was installed. Existing files that are not ours are backed up first.
# Usage: deploy.py install [--scripts-only] [--no-gwent] [--extra <dir>=<game-relative dir> ...] | deploy.py uninstall
# Game files a deploy leaves out on purpose (the 4.04 Gwent menu of an older install) are hidden until uninstall.
import argparse
import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import BRIDGE, GAME, UAL, WO as REPO, WORK  # noqa: E402

MANIFEST = os.path.join(WORK, "deploy-manifest.json")
BACKUPS = os.path.join(WORK, "backups", "deploy")

# Witcher Online's 4.04 Gwent menu overrides: the port wraps the 5.01 CR4GwintGameMenu instead (gwentDuel.ws, and
# gwentHooks.ws adds the two methods the 4.04 override declared)
GWENT_OVERRIDES = ("gwintManager.ws", "gwintGameMenu.ws")
# the mod's own bundle is the 4.04 Gwent board (gwint_game.redswf). The 5.01 board is built into
# WitcherOnline\gwent\out and comes with --extra <WitcherOnline>\gwent\out\modWitcherOnline\content=mods\modWitcherOnline\content
GWENT_BUNDLE = (os.path.join("mods", "modWitcherOnline", "content", "blob0.bundle"),
                os.path.join("mods", "modWitcherOnline", "content", "metadata.store"))
REPO_GAME_FILES = os.path.join(REPO, "witcher")


def mappings(a):
    if a.no_repo:
        return
    # the ASI loader and the native bridge: every script deploy imports their natives
    x64 = os.path.join("bin", "x64_dx12")
    yield os.path.join(UAL, "dinput8.dll"), os.path.join(x64, "dinput8.dll")
    yield os.path.join(BRIDGE, "build", "Release", "WitcherNativeBridge.asi"), os.path.join(x64, "WitcherNativeBridge.asi")
    w = os.path.join(REPO, "witcher")
    yield os.path.join(w, "mods", "modWitcherOnline"), os.path.join("mods", "modWitcherOnline")
    yield os.path.join(w, "mods", "modWitcherOnlineCompat"), os.path.join("mods", "modWitcherOnlineCompat")
    if a.dlc or not a.scripts_only:
        yield os.path.join(w, "dlc", "dlcWitcherOnline"), os.path.join("dlc", "dlcWitcherOnline")
    # the options panel's definitions: the scripts read those vars, so they go even with --scripts-only
    yield os.path.join(w, "bin", "config"), os.path.join("bin", "config")
    if a.scripts_only:
        return
    yield os.path.join(REPO, "client", "build", "Release", "WitcherOnlineClient.asi"), os.path.join("bin", "x64_dx12", "WitcherOnlineClient.asi")


def skipped(a, rel, src):
    """Why `src` does not go to `rel`: None (it goes), "note" (not a game file) or "drop" (a game file this deploy
    must not have; a copy already in the game folder that is not ours is hidden while deployed)."""
    name = rel.split("\\")[-1]
    if name in GWENT_OVERRIDES:
        return "drop"
    if rel in {norm(p) for p in GWENT_BUNDLE} and (a.no_gwent or is_under(src, REPO_GAME_FILES)):
        return "drop"
    # install notes at the mod root (input.settings.txt etc.) are not game files
    if rel.rsplit("\\", 1)[0] == "mods\\modWitcherOnline" and name.endswith((".txt", ".csv")):
        return "note"
    return None


def is_under(path, folder):
    return os.path.normcase(os.path.abspath(path)).startswith(os.path.normcase(os.path.abspath(folder)) + os.sep)


BACKSLASH = chr(92)
EXTENDED_PREFIX = BACKSLASH * 2 + "?" + BACKSLASH   # the extended-length prefix, which Win32 takes unnormalised


def lp(path):
    """`path` in the extended-length form once it is long enough to need it, so copies work from or to folders deeper
    than MAX_PATH (260 characters) without Windows' long-path setting (e.g. a clone under a deep temp folder). Such a
    path reaches Win32 unnormalised, so every separator in it must be a backslash: MSYS2's Python leaves forward
    slashes in os.path.abspath, and a prefixed path that keeps them fails with "file not found"."""
    path = os.path.abspath(path)
    if os.name != "nt" or path.startswith(EXTENDED_PREFIX) or len(path) < 240:
        return path
    return EXTENDED_PREFIX + path.replace("/", BACKSLASH)


def norm(rel):
    # one spelling per path: "a/b" and "a\\b" must never be two manifest entries
    return os.path.normpath(rel).replace("/", "\\")


def load_manifest():
    if not os.path.exists(MANIFEST):
        return {"files": [], "backups": {}, "hidden": {}}
    m = json.load(open(MANIFEST, encoding="utf-8"))
    m["files"] = sorted({norm(f) for f in m["files"]})
    m["backups"] = {norm(k): v for k, v in m["backups"].items()}
    # game files that are not ours, moved out of the way while deployed (e.g. an older install's 4.04 Gwent menu)
    m["hidden"] = {norm(k): v for k, v in m.get("hidden", {}).items()}
    return m


def install_file(src, rel, manifest):
    dst = os.path.join(GAME, rel)
    if os.path.exists(dst) and rel not in manifest["files"]:
        bak = os.path.join(BACKUPS, time.strftime("%Y%m%d-%H%M%S"), rel)
        os.makedirs(lp(os.path.dirname(bak)), exist_ok=True)
        shutil.copy2(lp(dst), lp(bak))
        manifest["backups"][rel] = bak
        print(f"backed up {rel} -> {bak}")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    # a game that just exited may hold its files for a few seconds more
    for attempt in range(10):
        try:
            shutil.copy2(lp(src), lp(dst))
            break
        except PermissionError:
            if attempt == 9:
                raise
            time.sleep(1)
    if rel not in manifest["files"]:
        manifest["files"].append(rel)


def install(a):
    manifest = load_manifest()
    pairs = list(mappings(a)) + [tuple(e.split("=", 1)) for e in a.extra]
    wanted = {}
    unwanted = set()
    for src, rel_root in pairs:
        if os.path.isfile(src):
            wanted[norm(rel_root)] = src
            continue
        for dp, _, fns in os.walk(src):
            for f in fns:
                rel = norm(os.path.join(rel_root, os.path.relpath(os.path.join(dp, f), src)))
                why = skipped(a, rel, os.path.join(dp, f))
                if why is None:
                    wanted[rel] = os.path.join(dp, f)
                elif why == "drop":
                    unwanted.add(rel)
    try:
        for rel in wanted:
            # a hidden file this deploy overwrites after all: uninstall restores it like any other backup
            if rel in manifest["hidden"]:
                manifest["backups"][rel] = manifest["hidden"].pop(rel)
        for rel, src in wanted.items():
            install_file(src, rel, manifest)
        # drop files deployed earlier that this deploy no longer includes (e.g. after --no-gwent or without --dlc)
        for rel in [r for r in manifest["files"] if r not in wanted]:
            remove(rel, manifest)
        # after the removals: one of them may have put back a file that this deploy leaves out
        for rel in sorted(unwanted - set(wanted)):
            hide(rel, manifest)
    finally:
        # also after a failed copy: uninstall must know every file that went in
        save_manifest(manifest)
    print(f"installed {len(wanted)} files; manifest has {len(manifest['files'])}")


def save_manifest(manifest):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), indent=1)


def hide(rel, manifest):
    """Moves a game file that is not ours out of the game folder (into the backups) until uninstall."""
    dst = os.path.join(GAME, rel)
    if rel in manifest["hidden"] or not os.path.exists(dst):
        return
    bak = os.path.join(BACKUPS, time.strftime("%Y%m%d-%H%M%S"), rel)
    os.makedirs(lp(os.path.dirname(bak)), exist_ok=True)
    shutil.copy2(lp(dst), lp(bak))
    os.remove(dst)
    manifest["hidden"][rel] = bak
    print(f"hid {rel} (this deploy leaves it out) -> {bak}")


def remove(rel, manifest):
    dst = os.path.join(GAME, rel)
    if os.path.exists(dst):
        os.remove(dst)
    manifest["files"].remove(rel)
    bak = manifest["backups"].pop(rel, None)
    if bak and os.path.exists(lp(bak)):
        shutil.copy2(lp(bak), lp(dst))
        print(f"restored {rel}")
    d = os.path.dirname(dst)
    while d.startswith(GAME) and d != GAME and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)


def uninstall():
    manifest = load_manifest()
    try:
        for rel in list(manifest["files"]):
            remove(rel, manifest)
        for rel, bak in list(manifest["hidden"].items()):
            dst = os.path.join(GAME, rel)
            if os.path.exists(lp(bak)) and not os.path.exists(dst):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(lp(bak), lp(dst))
                print(f"restored hidden {rel}")
            if os.path.exists(dst):
                del manifest["hidden"][rel]
    finally:
        save_manifest(manifest)
    left = manifest["files"] + list(manifest["hidden"])
    print("uninstalled; manifest empty" if not left else f"left: {left}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["install", "uninstall"])
    ap.add_argument("--scripts-only", action="store_true")
    ap.add_argument("--no-gwent", action="store_true", help="no Gwent board (blob0.bundle, metadata.store) from any source")
    ap.add_argument("--dlc", action="store_true", help="also install dlc\\dlcWitcherOnline (player ghost templates, emotes)")
    ap.add_argument("--no-repo", action="store_true", help="install only the --extra sources (e.g. a built package)")
    ap.add_argument("--extra", action="append", default=[], help="<abs src>=<game-relative dst>")
    a = ap.parse_args()
    install(a) if a.action == "install" else uninstall()


if __name__ == "__main__":
    sys.exit(main())
