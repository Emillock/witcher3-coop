"""Builds the scene input table the mod needs to follow another player's cutscene.

`CStorySceneSystem.PlayScene(scene, input)` is the only way a script can start a scene, and it needs the name
of one of the scene's inputs. A game knows the path of the scene it is watching (CStoryScene.GetPath) but not
which input it entered at, and a scene's inputs are named by hand ("in_first_body", "Input", ...), so they
cannot be guessed. They are in the scene resource, so this reads every .w2scene out of the game's bundles once
and writes "<path>\tinput|input" lines for the client to look up at runtime.

A .w2scene is a CR2W resource: tables at 0x28 (10 x offset/count/crc32), table 0 raw strings, table 1 names
(8 bytes: offset into the strings block, hash), table 4 exports (<HHIIIII>: class name index, flags, parent,
data size, data offset, template, crc32). An export's data is one leading byte, then properties - name index
u16, type index u16, size u32 counted from the size field itself, value - ending at a zero name index. A
CStorySceneInput's name is its `inputName` String property; absent means the editor default, "Input".
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "WitcherOnline", "gwent",
                                "build"))
from pathlib import Path  # noqa: E402

import bundle  # noqa: E402

from config import GAME, WORK  # noqa: E402

DEFAULT_INPUT = "Input"
TABLES_AT = 0x28
EXPORT = struct.Struct("<HHIIIII")


def names_of(data: bytes) -> list[str]:
    soff = struct.unpack_from("<I", data, TABLES_AT)[0]
    noff, ncount = struct.unpack_from("<II", data, TABLES_AT + 12)
    out = []
    for i in range(ncount):
        rel = struct.unpack_from("<I", data, noff + 8 * i)[0]
        end = data.index(b"\0", soff + rel)
        out.append(data[soff + rel:end].decode("latin-1"))
    return out


def text_of(value: bytes) -> str:
    """A CR2W String: one length byte (0x80 set means one byte per character), then the characters."""
    if not value:
        return ""
    if value[0] & 0x80:
        return value[1:].decode("latin-1")
    return value[1:].decode("utf-16-le", "replace")


def properties(blob: bytes, names: list[str]):
    """Yields (name, type, value) for one export's serialized properties."""
    pos = 1   # one leading byte before the stream
    while pos + 8 <= len(blob):
        nidx, tidx = struct.unpack_from("<HH", blob, pos)
        if nidx == 0 or nidx >= len(names):
            return
        size = struct.unpack_from("<I", blob, pos + 4)[0]
        if size < 4 or pos + 4 + size > len(blob):
            return
        yield names[nidx], (names[tidx] if tidx < len(names) else ""), blob[pos + 8:pos + 4 + size]
        pos += 4 + size


def inputs_of(data: bytes) -> list[str]:
    """The scene's input names in resource order, each with a '*' when it leads straight into a cinematic
    section - a section whose isGameplay is false, which is what a cutscene is made of."""
    names = names_of(data)
    eoff, ecount = struct.unpack_from("<II", data, TABLES_AT + 12 * 4)
    blobs, classes = [], []
    for i in range(ecount):
        cls, _flags, _parent, dsize, doff, _template, _crc = EXPORT.unpack_from(data, eoff + 24 * i)
        classes.append(names[cls] if cls < len(names) else "")
        blobs.append(data[doff:doff + dsize])

    gameplay = {}
    for i, cls in enumerate(classes):
        if cls != "CStorySceneSection":
            continue
        gameplay[i] = False   # only stored when true, so an absent isGameplay means cinematic
        for pname, _ptype, value in properties(blobs[i], names):
            if pname == "isGameplay":
                gameplay[i] = bool(value and value[0])

    found = []
    for i, cls in enumerate(classes):
        if cls != "CStorySceneInput":
            continue
        name, nxt = DEFAULT_INPUT, -1
        for pname, ptype, value in properties(blobs[i], names):
            if pname == "inputName":
                name = text_of(value) or DEFAULT_INPUT
            elif pname == "nextLinkElement" and len(value) >= 4:
                nxt = struct.unpack_from("<i", value, 0)[0] - 1   # export ids are 1 based
        if gameplay.get(nxt, True) is False:
            name += "*"
        if name not in found:
            found.append(name)
    return found


def bundles(game: str) -> list[Path]:
    root = Path(game)
    return sorted(root.glob("content/content*/bundles/*.bundle")) + sorted(root.glob("dlc/*/content/*.bundle"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(WORK, "scene_inputs.txt"))
    ap.add_argument("--game", default=GAME)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    table: dict[str, list[str]] = {}
    failed = 0
    for path in bundles(a.game):
        scenes = [e for e in bundle.entries(path) if e.name.lower().endswith(".w2scene")]
        if not scenes:
            continue
        with open(path, "rb") as f:
            for entry in scenes:
                key = entry.name.lower().replace("/", "\\")
                if key in table:
                    continue   # the same scene in two bundles: the first one wins, as the game's own order does
                f.seek(entry.offset)
                raw = f.read(entry.csize)
                try:
                    data = bundle.decompress(raw, entry.size, entry.comp)
                    found = inputs_of(data)
                except Exception:
                    failed += 1
                    continue
                if found:
                    table[key] = found
        if not a.quiet:
            print(f"{path.name}: {len(scenes)} scenes, {len(table)} in the table so far", flush=True)

    out = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"# scene inputs for {os.path.basename(a.game)}; built by scene_inputs.py\n")
        for key in sorted(table):
            f.write(f"{key}\t{'|'.join(table[key])}\n")
    counts: dict[int, int] = {}
    for found in table.values():
        counts[len(found)] = counts.get(len(found), 0) + 1
    print(f"{len(table)} scenes -> {out}" + (f" ({failed} unreadable)" if failed else ""))
    print("inputs per scene: " + ", ".join(f"{n}: {counts[n]}" for n in sorted(counts)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
