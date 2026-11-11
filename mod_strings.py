# Writes the mod's .w3strings tables from its own en.csv, one per language the game has, in the format
# Remastered reads (version 164, each language under its own key). The text is the same English for every
# language: the mod has no translations, and a readable English label beats a blank row.
# Usage: mod_strings.py [--out <dir>]  (default: the mod's content folder in the WitcherOnline repo)
import os
import sys

from config import WO
from w3strings import KEYLESS, LANGUAGES, encode, read_csv

# every language the game ships a table for; the keyless ones get key 0 and no cipher
HANDLES = sorted({h for _, (h, _) in LANGUAGES.items() if h != "keyless"} | set(KEYLESS))


def main():
    content = os.path.join(WO, "witcher", "mods", "modWitcherOnline", "content")
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else content
    os.makedirs(out, exist_ok=True)
    rows = read_csv(os.path.join(content, "en.csv"))
    for handle in HANDLES:
        data = encode(rows, handle, 164)
        open(os.path.join(out, f"{handle}.w3strings"), "wb").write(data)
    print(f"{len(rows)} strings -> {len(HANDLES)} tables in {out} ({len(data)} bytes each)")


if __name__ == "__main__":
    main()
