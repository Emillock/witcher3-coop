# Builds the player package: a folder with the game's layout (copy its contents into the Witcher 3 folder) and a zip.
# Usage: build_package.py <version>
import os
import re
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from config import BRIDGE, TOOLS, UAL, WO, WORK  # noqa: E402

# Witcher Online's 4.04 Gwent files: the menu overrides that would replace the Remastered Gwent UI, and the mod's
# 4.04 board bundle. gwentHooks.ws stays: on 5.01 it defines the methods gwentDuel.ws calls (NotifyGwentMatchEnded,
# HandleOutgoingGwentAction), and without it the scripts do not compile. The 5.01 board is built by each player
# (WitcherOnline gwent/README.md).
GWENT_ONLY = {"gwintManager.ws", "gwintGameMenu.ws", "blob0.bundle", "metadata.store"}


def skip_mod_file(name: str, path: str, mod_src: str) -> bool:
    """True for a file under modWitcherOnline that the package leaves out: a 4.04 Gwent file or a root install note."""
    return name in GWENT_ONLY or os.path.dirname(path) == mod_src


def copy_tree(src, dst, skip=lambda name, path: False):
    for dp, _, fns in os.walk(src):
        for f in fns:
            path = os.path.join(dp, f)
            if skip(f, path):
                continue
            out = os.path.join(dst, os.path.relpath(path, src))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copy2(path, out)


def git_archive(repo, out_zip, *paths):
    subprocess.run(["git", "-C", repo, "archive", "--format=zip", "-o", out_zip, "HEAD", *paths], check=True)


def source_zip(repo, out_zip, *paths):
    """Tracked files from the working tree (the Witcher Online clone is partial, so `git archive` would
    download missing objects). Asset bundles are left out: they ship in the package itself."""
    files = subprocess.run(["git", "-C", repo, "ls-files", "--", *paths], capture_output=True, text=True, check=True).stdout.split("\n")
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in filter(None, files):
            path = os.path.join(repo, rel)
            if os.path.isfile(path) and not rel.endswith(".bundle"):
                z.write(path, rel)


def script_version():
    """The version the mod's scripts tell other players (CoopVersion() in coopEnemies.ws)."""
    path = os.path.join(WO, "witcher", "mods", "modWitcherOnline", "content", "scripts", "local", "coopEnemies.ws")
    text = open(path, encoding="utf-8").read()
    m = re.search(r'function CoopVersion\(\) : string\s*\{\s*return "([^"]+)";', text)
    return m.group(1) if m else None


def main():
    version = sys.argv[1]
    told = script_version()
    if told != version:
        sys.exit(f"the scripts say version {told} (CoopVersion in coopEnemies.ws); set it to {version} first")
    out = os.path.join(WORK, "dist", f"W3Coop-{version}")
    if os.path.exists(out):
        shutil.rmtree(out)
    w = os.path.join(WO, "witcher")

    mod_src = os.path.join(w, "mods", "modWitcherOnline")
    copy_tree(mod_src, os.path.join(out, "mods", "modWitcherOnline"), lambda f, p: skip_mod_file(f, p, mod_src))
    copy_tree(os.path.join(w, "mods", "modWitcherOnlineCompat"), os.path.join(out, "mods", "modWitcherOnlineCompat"))
    copy_tree(os.path.join(w, "dlc", "dlcWitcherOnline"), os.path.join(out, "dlc", "dlcWitcherOnline"))
    copy_tree(os.path.join(w, "bin", "config"), os.path.join(out, "bin", "config"))

    # The scene input table: a member needs a scene's input name to play the cutscene its leader is watching,
    # and the names are only in the game's own scene resources. Built from them once (scene_inputs.py), and
    # the same for everyone on this game version, so the package carries it.
    table = os.path.join(WORK, "scene_inputs.txt")
    if not os.path.exists(table):
        subprocess.run([sys.executable, os.path.join(TOOLS, "scene_inputs.py"), "--quiet"], check=True)
    shutil.copy2(table, os.path.join(out, "mods", "modWitcherOnline", "scene_inputs.txt"))

    x64 = os.path.join(out, "bin", "x64_dx12")
    os.makedirs(x64)
    shutil.copy2(os.path.join(UAL, "dinput8.dll"), x64)
    shutil.copy2(os.path.join(BRIDGE, "build", "Release", "WitcherNativeBridge.asi"), x64)
    shutil.copy2(os.path.join(WO, "client", "build", "Release", "WitcherOnlineClient.asi"), x64)

    wo_cfg = os.path.join(out, "bin", "WitcherOnline")
    os.makedirs(wo_cfg)
    with open(os.path.join(wo_cfg, "config.xml"), "w", newline="\r\n") as f:
        f.write('<?xml version="1.0"?>\n<Config>\n\t<Username>Player</Username>\n\t<ServerIP>127.0.0.1</ServerIP>\n\t<Port>40000</Port>\n</Config>\n')

    relay = os.path.join(out, "bin", "w3coop")
    os.makedirs(os.path.join(relay, "server"))
    shutil.copy2(os.path.join(TOOLS, "relay", "build", "w3relay.exe"), relay)
    shutil.copy2(os.path.join(WO, "server", "build", "WitcherServer.jar"), os.path.join(relay, "server"))
    for name in ("Host co-op.cmd", "Join co-op.cmd"):
        shutil.copy2(os.path.join(HERE, name), relay)

    docs = os.path.join(out, "W3Coop")
    os.makedirs(os.path.join(docs, "licenses"))
    os.makedirs(os.path.join(docs, "source"))
    shutil.copy2(os.path.join(HERE, "README.txt"), docs)
    shutil.copy2(os.path.join(WO, "LICENSE"), os.path.join(docs, "licenses", "WitcherOnline-GPL-3.0.txt"))
    shutil.copy2(os.path.join(BRIDGE, "LICENSE.txt"), os.path.join(docs, "licenses", "WitcherNativeBridge-MIT.txt"))
    shutil.copy2(os.path.join(UAL, "LICENSE"), os.path.join(docs, "licenses", "UltimateASILoader-MIT.txt"))
    # Witcher Online is GPL-3.0: ship the modified source with the binaries
    branch = subprocess.run(["git", "-C", WO, "branch", "--show-current"], capture_output=True, text=True, check=True).stdout.strip()
    source_zip(WO, os.path.join(docs, "source", f"WitcherOnline-{branch}.zip"), "client", "server", "witcher/mods", "LICENSE", "README.md")
    git_archive(TOOLS, os.path.join(docs, "source", "w3relay.zip"), "relay")
    # the bridge carries a fix for game build 5.0.0.1090142 (its string helper signature)
    source_zip(BRIDGE, os.path.join(docs, "source", "WitcherNativeBridge.zip"), "src", "include", "LICENSE.txt", "README.md",
               "WitcherNativeBridge.sln", "WitcherNativeBridge.vcxproj")

    zip_path = out + ".zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, fns in os.walk(out):
            for f in fns:
                path = os.path.join(dp, f)
                z.write(path, os.path.relpath(path, out))
    size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fns in os.walk(out) for f in fns)
    print(f"{out} ({size // (1024 * 1024)} MB), zip {os.path.getsize(zip_path) // (1024 * 1024)} MB")


if __name__ == "__main__":
    main()
