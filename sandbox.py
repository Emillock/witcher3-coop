# Per-instance "Documents" sandbox for test runs: copies of the owner's Witcher 3 settings (and optionally one
# save). w3test.asi points the game at it through W3T_DOCUMENTS, so tests never touch the owner's folder.
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import GAME, USER_W3_DOCS  # noqa: E402
from preset_expand import expand_preset  # noqa: E402

OWNER_W3_DOCS = USER_W3_DOCS
SETTINGS_FILES = ("dx12user.settings", "input.settings", "profile.settings", "mods.settings")
GRAPHICS_XML = os.path.join(GAME, "bin", "config", "r4game", "user_config_matrix", "pc", "graphics.xml")
TEST_RESOLUTION = "640x360"

# On top of the game's own "low" preset: 30 FPS cap, no AA/upscaling/frame generation, no post effects.
# Two DX12 instances with the owner's ray-traced settings crashed the GPU driver once.
TEST_EXTRAS = {
    "Engine": {"LimitFPS": "30"},
    "Viewport": {"VSync": "false", "Resolution": f'"{TEST_RESOLUTION}"'},
    "Rendering": {"SSREnabled": "false"},
    "PostProcess": {"AAMode": "0", "EnableDLSSRR": "false", "DLSSGMode": "0", "FSRFramegen": "0",
                    "XessFrameGeneration": "false", "AllowMotionBlur": "false", "AllowBloom": "false",
                    "AllowLensEffects": "false"},
}


def test_preset():
    preset = expand_preset(GRAPHICS_XML, "0")
    for group, pairs in TEST_EXTRAS.items():
        preset.setdefault(group, {}).update(pairs)
    # run_test.py --size
    preset["Viewport"]["Resolution"] = f'"{os.environ.get("W3T_RESOLUTION", TEST_RESOLUTION)}"'
    return preset


def set_settings(path, values):
    """Sets [section] key=value pairs in a REDengine .settings file, keeping its newline style."""
    text = open(path, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    for section, pairs in values.items():
        header = f"[{section}]"
        if header not in lines:
            lines += [header] + [f"{k}={v}" for k, v in pairs.items()] + [""]
            continue
        start = lines.index(header) + 1
        end = start
        while end < len(lines) and not lines[end].startswith("["):
            end += 1
        body = lines[start:end]
        for k, v in pairs.items():
            hit = [i for i, l in enumerate(body) if l.split("=", 1)[0] == k]
            if hit:
                body[hit[0]] = f"{k}={v}"
            else:
                body.insert(0, f"{k}={v}")
        lines[start:end] = body
    open(path, "wb").write(nl.join(lines).encode("utf-8"))


def make_sandbox(docs, save_filter=None):
    """Creates <docs>\\The Witcher 3 with settings copies; with save_filter (str), also the newest matching save.
    Returns the copied save's file name or None."""
    w3 = os.path.join(docs, "The Witcher 3")
    if os.path.exists(docs):
        shutil.rmtree(docs)
    os.makedirs(os.path.join(w3, "gamesaves"))
    for name in SETTINGS_FILES:
        src = os.path.join(OWNER_W3_DOCS, name)
        if os.path.exists(src):
            shutil.copy2(src, w3)
    if os.path.exists(os.path.join(w3, "dx12user.settings")):
        set_settings(os.path.join(w3, "dx12user.settings"), test_preset())
    if save_filter is None:
        return None
    saves_dir = os.path.join(OWNER_W3_DOCS, "gamesaves")
    saves = [f for f in os.listdir(saves_dir) if f.endswith(".sav") and save_filter in f]
    newest = max(saves, key=lambda f: os.path.getmtime(os.path.join(saves_dir, f)))
    for ext in (".sav", ".png"):
        src = os.path.join(saves_dir, newest[:-4] + ext)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(w3, "gamesaves"))
    return newest
