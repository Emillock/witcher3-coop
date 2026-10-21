# Builds the player package: a folder with the game's layout (copy its contents into the Witcher 3 folder) and a zip.
# Usage: build_package.py <version>
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from config import BRIDGE, TOOLS, UAL, WO, WORK  # noqa: E402

# 4.04 Gwent board files that would replace the Remastered Gwent UI, and the hooks that need them
GWENT_ONLY = {"gwintManager.ws", "gwintGameMenu.ws", "gwentHooks.ws", "blob0.bundle", "metadata.store"}


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


def main():
    version = sys.argv[1]
    out = os.path.join(WORK, "dist", f"W3Coop-{version}")
    if os.path.exists(out):
        shutil.rmtree(out)
    w = os.path.join(WO, "witcher")

    mod_src = os.path.join(w, "mods", "modWitcherOnline")
    copy_tree(mod_src, os.path.join(out, "mods", "modWitcherOnline"),
              lambda f, p: f in GWENT_ONLY or os.path.dirname(p) == mod_src)  # root files are install notes
    copy_tree(os.path.join(w, "mods", "modWitcherOnlineCompat"), os.path.join(out, "mods", "modWitcherOnlineCompat"))
    copy_tree(os.path.join(w, "dlc", "dlcWitcherOnline"), os.path.join(out, "dlc", "dlcWitcherOnline"))
    copy_tree(os.path.join(w, "bin", "config"), os.path.join(out, "bin", "config"))

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
