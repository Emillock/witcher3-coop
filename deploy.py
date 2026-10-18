# Installs the Witcher Online port from the repo into the game folder, recording every file in a manifest so
# `uninstall` removes exactly what was installed. Existing files that are not ours are backed up first.
# Usage: deploy.py install [--scripts-only] [--no-gwent] [--extra <dir>=<game-relative dir> ...] | deploy.py uninstall
import argparse
import json
import os
import shutil
import sys
import time

GAME = r"D:\SteamLibrary\steamapps\common\The Witcher 3"
REPO = r"C:\Users\User\Desktop\repos\WitcherOnline"
WORK = r"C:\Users\User\Desktop\repos\work"
MANIFEST = os.path.join(WORK, "deploy-manifest.json")
BACKUPS = os.path.join(WORK, "backups", "deploy")

GWENT_OVERRIDES = ("gwintManager.ws", "gwintGameMenu.ws", "gwentHooks.ws")
# the mod's only bundle is the 4.04 Gwent board (gwint_game.redswf); it would replace the 5.x Gwent UI
GWENT_BUNDLE = (os.path.join("mods", "modWitcherOnline", "content", "blob0.bundle"),
                os.path.join("mods", "modWitcherOnline", "content", "metadata.store"))


def mappings(a):
    w = os.path.join(REPO, "witcher")
    yield os.path.join(w, "mods", "modWitcherOnline"), os.path.join("mods", "modWitcherOnline")
    if a.dlc or not a.scripts_only:
        yield os.path.join(w, "dlc", "dlcWitcherOnline"), os.path.join("dlc", "dlcWitcherOnline")
    if a.scripts_only:
        return
    yield os.path.join(w, "bin", "config"), os.path.join("bin", "config")
    yield os.path.join(REPO, "client", "build", "Release", "WitcherOnlineClient.asi"), os.path.join("bin", "x64_dx12", "WitcherOnlineClient.asi")


def skipped(a, rel):
    name = os.path.basename(rel)
    if a.no_gwent and (name in GWENT_OVERRIDES or rel in GWENT_BUNDLE):
        return True
    # install notes at the mod root (input.settings.txt etc.) are not game files
    return os.path.dirname(rel) == os.path.join("mods", "modWitcherOnline") and name.endswith((".txt", ".csv"))


def load_manifest():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST, encoding="utf-8"))
    return {"files": [], "backups": {}}


def install_file(src, rel, manifest):
    dst = os.path.join(GAME, rel)
    if os.path.exists(dst) and rel not in manifest["files"]:
        bak = os.path.join(BACKUPS, time.strftime("%Y%m%d-%H%M%S"), rel)
        os.makedirs(os.path.dirname(bak), exist_ok=True)
        shutil.copy2(dst, bak)
        manifest["backups"][rel] = bak
        print(f"backed up {rel} -> {bak}")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    if rel not in manifest["files"]:
        manifest["files"].append(rel)


def install(a):
    manifest = load_manifest()
    pairs = list(mappings(a)) + [tuple(e.split("=", 1)) for e in a.extra]
    wanted = {}
    for src, rel_root in pairs:
        if os.path.isfile(src):
            wanted[rel_root] = src
            continue
        for dp, _, fns in os.walk(src):
            for f in fns:
                rel = os.path.join(rel_root, os.path.relpath(os.path.join(dp, f), src))
                if not skipped(a, rel):
                    wanted[rel] = os.path.join(dp, f)
    for rel, src in wanted.items():
        install_file(src, rel, manifest)
    # drop files deployed earlier that this deploy no longer includes (e.g. after --no-gwent or without --dlc)
    for rel in [r for r in manifest["files"] if r not in wanted]:
        remove(rel, manifest)
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), indent=1)
    print(f"installed {len(wanted)} files; manifest has {len(manifest['files'])}")


def remove(rel, manifest):
    dst = os.path.join(GAME, rel)
    if os.path.exists(dst):
        os.remove(dst)
    manifest["files"].remove(rel)
    bak = manifest["backups"].pop(rel, None)
    if bak and os.path.exists(bak):
        shutil.copy2(bak, dst)
        print(f"restored {rel}")
    d = os.path.dirname(dst)
    while d.startswith(GAME) and d != GAME and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)


def uninstall():
    manifest = load_manifest()
    for rel in list(manifest["files"]):
        remove(rel, manifest)
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), indent=1)
    print("uninstalled; manifest empty" if not manifest["files"] else f"left: {manifest['files']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["install", "uninstall"])
    ap.add_argument("--scripts-only", action="store_true")
    ap.add_argument("--no-gwent", action="store_true")
    ap.add_argument("--dlc", action="store_true", help="also install dlc\\dlcWitcherOnline (player ghost templates, emotes)")
    ap.add_argument("--extra", action="append", default=[], help="<abs src>=<game-relative dst>")
    a = ap.parse_args()
    install(a) if a.action == "install" else uninstall()


if __name__ == "__main__":
    sys.exit(main())
