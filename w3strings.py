# Reads and writes the game's .w3strings string tables (the format of its own files, version 162 and 164).
# Usage: w3strings.py decode <file.w3strings> [out.csv] | w3strings.py encode <file.csv> <lang> <out.w3strings>
#
# Layout: "RTSW", uint32 version, uint16 key1, then three blocks and the text, with uint16 key2 as the last two
# bytes of the file. key1<<16|key2 names the language, and the language's own magic both masks every string id
# (id ^ magic) and seeds the text's cipher. Each block is preceded by its count in the game's 6/7-bit varint.
# Each unit of the text is XORed with a key that starts at (magic >> 8) & 0xffff and rotates left one bit per
# unit, multiplied by the string's length + 1.
# Version 164 (Remastered) stores the text as UTF-8 bytes, one unit per byte; version 162 (the 4.x games) as
# UTF-16 code units, two bytes each. Offsets, lengths and the text's size are counted in those units either way,
# so a 162 file read as 164 gives nothing but noise - which is what a 4.x mod's table does on Remastered.
# Seven languages (ar, br, cn, esmx, kr, tr, ua) carry key 0 and magic 0: their ids are unmasked and their text
# is plain.
import csv
import os
import struct
import sys

# key -> (handle, magic), read from the game's own 5.01 files. The seven keyless languages share key 0.
KEYLESS = ("ar", "br", "cn", "esmx", "kr", "tr", "ua")
LANGUAGES = {
    0x00000000: ("keyless", 0x00000000),
    0x83496237: ("pl", 0x73946816),
    0x43975139: ("en", 0x79321793),
    0x75886138: ("de", 0x42791159),
    0x45931894: ("it", 0x12375973),
    0x23863176: ("fr", 0x75921975),
    0x24987354: ("cz", 0x21793217),
    0x18796651: ("es", 0x42387566),
    0x18632176: ("zh", 0x16875467),
    0x63481486: ("ru", 0x42386347),
    0x42378932: ("hu", 0x67823218),
    0x54834893: ("jp", 0x59825646),
}
BY_HANDLE = {handle: (key, magic) for key, (handle, magic) in LANGUAGES.items()}


def hash_key(key):
    """The game's hash of a string key: over its UTF-16 code units, h = h * 31 + unit."""
    h = 0
    for ch in key.lower():
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return h


def read_varint(buf, pos):
    """The game's 6-bit-then-7-bit varint: the first byte carries 6 bits, each next one 7."""
    result = shift = 0
    i = 1
    while True:
        b = buf[pos]
        pos += 1
        step, mask = 6, 255
        if b > 127:
            step, mask = 7, 127
        elif b > 63 and i == 1:
            mask = 63
        if shift < 32:
            result |= (b & mask) << shift
        shift += step
        if b < 64 or (i >= 3 and b < 128):
            return result, pos
        i += 1


def write_varint(value):
    if value == 0:
        return bytes([128])
    parts, left, i = [], value, 0
    while left > 0:
        parts.append(left & (63 if i == 0 else 255))
        left >>= 6 if i == 0 else 7
        i += 1
    out = bytearray()
    for i, val in enumerate(parts):
        if i < len(parts) - 1:
            val |= 128 if i >= 1 else (64 if val < 64 else 128)
        out.append(val)
    return bytes(out)


def cipher(units, magic, mask=0xFFFF):
    """XORs the text's units with the cipher (its own inverse). mask is 0xff for a 164 file's bytes."""
    key = (magic >> 8) & 0xFFFF
    out = []
    for unit in units:
        out.append(unit ^ ((((len(units) + 1) * key) & 0xFFFF) & mask))
        key = ((key << 1) | (key >> 15)) & 0xFFFF
    return out


def pack_text(text, magic, version):
    """The text's own units, ciphered: UTF-8 bytes on 164, UTF-16 code units on 162."""
    if version >= 164:
        return bytes(cipher(list(text.encode("utf-8")), magic, 0xFF))
    return b"".join(struct.pack("<H", u) for u in cipher([ord(c) for c in text], magic))


def unpack_text(data, at, length, magic, version):
    if version >= 164:
        return bytes(cipher(list(data[at:at + length]), magic, 0xFF)).decode("utf-8", "replace")
    units = cipher(list(struct.unpack_from(f"<{length}H", data, at)), magic)
    return "".join(chr(u) for u in units)


def decode(data):
    """-> (version, handle, [(id, key_hash, text)]). Entries without a key hash get 0."""
    if data[:4] != b"RTSW":
        sys.exit("not a .w3strings file")
    version = struct.unpack_from("<I", data, 4)[0]
    key = (struct.unpack_from("<H", data, 8)[0] << 16) | struct.unpack_from("<H", data, len(data) - 2)[0]
    if key not in LANGUAGES:
        sys.exit(f"unknown language key {key:#010x}")
    handle, magic = LANGUAGES[key]
    pos = 10
    count, pos = read_varint(data, pos)
    entries = []
    for _ in range(count):
        str_id, offset, strlen = struct.unpack_from("<3I", data, pos)
        pos += 12
        entries.append([str_id ^ magic, offset, strlen])
    count2, pos = read_varint(data, pos)
    keys = {}
    for _ in range(count2):
        key_hash, str_id = struct.unpack_from("<2I", data, pos)
        pos += 8
        keys[str_id ^ magic] = key_hash
    _, pos = read_varint(data, pos)  # the text's size in units
    width = 1 if version >= 164 else 2
    out = []
    for str_id, offset, strlen in entries:
        out.append((str_id, keys.get(str_id, 0), unpack_text(data, pos + offset * width, strlen, magic, version)))
    return version, handle, out


def encode(rows, handle, version=164):
    """rows: [(id, key_hash_or_0, text)] -> the file's bytes for `handle`."""
    key, magic = (0, 0) if handle in KEYLESS else BY_HANDLE[handle]
    width = 1 if version >= 164 else 2
    text = bytearray()
    block1 = []
    for str_id, _, s in sorted(rows, key=lambda r: r[0] ^ magic):
        packed = pack_text(s, magic, version)
        block1.append((str_id, len(text) // width, len(packed) // width))
        text += packed
        text += b"\0" * width
    out = bytearray(b"RTSW" + struct.pack("<I", version) + struct.pack("<H", key >> 16))
    out += write_varint(len(block1))
    for str_id, offset, strlen in block1:
        out += struct.pack("<3I", str_id ^ magic, offset, strlen)
    keyed = sorted(((h, i) for i, h, _ in ((r[0], r[1], r[2]) for r in rows) if h), key=lambda p: p[0])
    out += write_varint(len(keyed))
    for key_hash, str_id in keyed:
        out += struct.pack("<2I", key_hash, str_id ^ magic)
    out += write_varint(len(text) // width)   # the text's size in its own units, not always two bytes
    out += text
    out += struct.pack("<H", key & 0xFFFF)
    return bytes(out)


def read_csv(path):
    """The encoder's CSV: `;meta[language=xx]`, a header line, then `id|key(hex)|key(str)|text`."""
    rows = []
    with open(path, encoding="utf-8", newline="") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith(";"):
                continue
            parts = line.split("|", 3)
            if len(parts) < 4:
                continue
            str_id, key_hex, key_str, text = parts
            key_hash = int(key_hex, 16) if key_hex.strip() else (hash_key(key_str) if key_str.strip() else 0)
            rows.append((int(str_id), key_hash, text))
    return rows


def main():
    action = sys.argv[1]
    if action == "decode":
        version, handle, rows = decode(open(sys.argv[2], "rb").read())
        print(f"version {version}, language {handle}, {len(rows)} strings")
        out = sys.argv[3] if len(sys.argv) > 3 else None
        if out:
            with open(out, "w", encoding="utf-8", newline="") as f:
                w = csv.writer(f, delimiter="|", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
                f.write(f";meta[language={handle}]\n; id      |key(hex)|key(str)| text\n")
                for str_id, key_hash, text in rows:
                    w.writerow([str_id, f"{key_hash:08x}" if key_hash else "", "", text])
            print("wrote", out)
        else:
            for str_id, key_hash, text in rows[:20]:
                print(str_id, f"{key_hash:08x}", repr(text))
    elif action == "encode":
        rows = read_csv(sys.argv[2])
        data = encode(rows, sys.argv[3], int(os.environ.get("W3S_VERSION", 162)))
        open(sys.argv[4], "wb").write(data)
        print(f"wrote {sys.argv[4]}: {len(rows)} strings, {len(data)} bytes, language {sys.argv[3]}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
