# Paths shared by the tools. Repos are expected side by side:
#   <root>\<this repo>  <root>\WitcherOnline (port branch)  <root>\WitcherNativeBridge
#   <root>\deps\ultimate-asi-loader-9.7.4  <root>\work (runs, backups, manifest; created on demand)
# Without <root>\WitcherOnline, the mod is this repo's WitcherOnline submodule.
# Override with W3_GAME_DIR, W3C_ROOT, W3C_WORK.
import ctypes
import os
import re
import uuid
import winreg

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.environ.get("W3C_ROOT") or os.path.dirname(TOOLS))
WO = os.path.join(ROOT, "WitcherOnline")
if not os.path.isdir(WO):
    WO = os.path.join(TOOLS, "WitcherOnline")
BRIDGE = os.path.join(ROOT, "WitcherNativeBridge")
UAL = os.path.join(ROOT, "deps", "ultimate-asi-loader-9.7.4")
WORK = os.path.normpath(os.environ.get("W3C_WORK") or os.path.join(ROOT, "work"))


def _steam_game_dir():
    """Finds The Witcher 3 (app 292030) through Steam's library folders."""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
            steam = winreg.QueryValueEx(key, "SteamPath")[0]
    except OSError:
        return None
    libraries = [steam]
    vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
    if os.path.exists(vdf):
        libraries += [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', open(vdf, encoding="utf-8").read())]
    for lib in libraries:
        if os.path.exists(os.path.join(lib, "steamapps", "appmanifest_292030.acf")):
            return os.path.join(lib, "steamapps", "common", "The Witcher 3")
    return None


def _documents():
    """The user's Documents folder (follows OneDrive/folder redirection)."""
    folder = uuid.UUID("{FDD39AD0-238F-46AF-ADB4-6C85480369C7}")
    guid = (ctypes.c_byte * 16).from_buffer_copy(folder.bytes_le)
    path = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(guid, 0, None, ctypes.byref(path)) != 0:
        return os.path.join(os.environ["USERPROFILE"], "Documents")
    value = path.value
    ctypes.windll.ole32.CoTaskMemFree(path)
    return value


GAME = os.path.normpath(os.environ.get("W3_GAME_DIR") or _steam_game_dir() or r"C:\Program Files (x86)\Steam\steamapps\common\The Witcher 3")
EXE = os.path.join(GAME, "bin", "x64_dx12", "witcher3.exe")
USER_W3_DOCS = os.path.join(_documents(), "The Witcher 3")
