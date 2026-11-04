"""Tests for the player package's file filter (package/build_package.py), without building a package."""
import os
import sys

import pytest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "package"))
sys.path.insert(0, HERE)
import build_package  # noqa: E402
from config import WO  # noqa: E402

MOD_SRC = os.path.join(WO, "witcher", "mods", "modWitcherOnline")


def mod_files() -> dict[str, str]:
    """Every file under the Witcher Online mod folder, by name, with its path."""
    files = {}
    for dp, _, fns in os.walk(MOD_SRC):
        for f in fns:
            files.setdefault(f, os.path.join(dp, f))
    return files


@pytest.mark.skipif(not os.path.isdir(MOD_SRC), reason="no Witcher Online checkout next to this repo")
def test_package_keeps_the_gwent_duel_scripts():
    files = mod_files()
    for name in ("gwentHooks.ws", "gwentDuel.ws"):
        assert name in files, f"{name} is not in the Witcher Online scripts"
        assert not build_package.skip_mod_file(name, files[name], MOD_SRC), f"the package leaves out {name}"


@pytest.mark.skipif(not os.path.isdir(MOD_SRC), reason="no Witcher Online checkout next to this repo")
def test_package_leaves_out_the_404_gwent_files():
    files = mod_files()
    for name in ("gwintManager.ws", "gwintGameMenu.ws", "blob0.bundle", "metadata.store"):
        if name in files:
            assert build_package.skip_mod_file(name, files[name], MOD_SRC), f"the package ships {name}"


def test_package_filter_by_name_and_place():
    src = os.path.join("x", "modWitcherOnline")
    scripts = os.path.join(src, "content", "scripts", "local")
    assert not build_package.skip_mod_file("gwentHooks.ws", os.path.join(scripts, "gwentHooks.ws"), src)
    assert build_package.skip_mod_file("gwintGameMenu.ws", os.path.join(scripts, "gwintGameMenu.ws"), src)
    assert build_package.skip_mod_file("blob0.bundle", os.path.join(src, "content", "blob0.bundle"), src)
    assert build_package.skip_mod_file("INSTALL.txt", os.path.join(src, "INSTALL.txt"), src)
