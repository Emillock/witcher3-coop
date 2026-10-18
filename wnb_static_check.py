# Offline replay of WitcherNativeBridge's binding logic (src/NativeBridge.cpp @ 415e1c1) against a witcher3.exe on disk.
# Read-only: maps file bytes to RVAs via the PE section table, no code from the exe or the bridge is executed.
import struct
import sys
from collections import Counter

REG_SIG = ("BA F8 00 00 00 48 8D 4D F0 41 B8 10 00 00 00 E8 ?? ?? ?? ?? "
           "48 8B 7D F0 33 D2 4C 8B 45 F8 48 8B CF E8 ?? ?? ?? ?? "
           "48 85 FF 74 ?? E8 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? "
           "48 8B C8 E8 ?? ?? ?? ?? 4C 8D 05 ?? ?? ?? ?? "
           "89 45 10 48 8D 55 10 48 8B CF E8 ?? ?? ?? ?? "
           "48 8B F8 EB ?? 48 8B FB E8 ?? ?? ?? ?? "
           "48 8B D7 48 8B C8 E8 ?? ?? ?? ??")
STRING_SIG = ("8B 15 ?? ?? ?? ?? 33 C9 41 B9 0E 00 00 00 89 54 24 ?? "
              "41 B8 01 00 00 00 48 C7 44 24 20 00 00 00 00 E8 ?? ?? ?? ?? 44 8B 44 24 ?? 48 8B C8 "
              "48 8B 15 ?? ?? ?? ?? 48 89 44 24 ?? E8 ?? ?? ?? ??")
# Pre-5.01 variant (the line the 5.01 commit replaced), to tell which build the exe resembles.
STRING_SIG_500 = ("8B 15 ?? ?? ?? ?? 33 C9 41 B9 0E 00 00 00 89 54 24 ?? "
                  "41 B8 01 00 00 00 E8 ?? ?? ?? ?? 44 8B 44 24 ?? 48 8B C8 "
                  "48 8B 15 ?? ?? ?? ?? 48 89 44 24 ?? E8 ?? ?? ?? ??")
PROLOGUE = bytes([0x48, 0x89, 0x6C, 0x24, 0x10, 0x48, 0x89, 0x74, 0x24, 0x18, 0x57, 0x48, 0x83, 0xEC, 0x20])
OFFSETS = {"alloc": 15, "memset": 33, "namePool": 43, "addName": 58,
           "functionCtor": 80, "scriptSystem": 93, "registerGlobal": 104}
OFF_NAME, OFF_IMPL = 48, 63
MIN_MATCHES = 32


def parse(sig):
    out = []
    for tok in sig.split():
        out.append(None if tok.startswith("?") else int(tok, 16))
    return out


def to_regex(sig):
    import re
    return re.compile(b"".join(b"." if b is None else re.escape(bytes([b])) for b in parse(sig)), re.S)


def main(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe:pe + 4] == b"PE\0\0"
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsz = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    timestamp = struct.unpack_from("<I", data, pe + 8)[0]
    secs = []
    for i in range(nsec):
        o = opt + optsz + i * 40
        name = data[o:o + 8].rstrip(b"\0").decode("latin1")
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
        chars = struct.unpack_from("<I", data, o + 36)[0]
        secs.append((name, va, vsize, rawptr, rawsize, chars))
    print(f"PE timestamp=0x{timestamp:08X} image_base=0x{image_base:X}")
    for s in secs:
        print(f"  section {s[0]:8s} va=0x{s[1]:08X} vsize=0x{s[2]:08X} raw=0x{s[3]:08X} rawsize=0x{s[4]:08X} exec={bool(s[5] & 0x20000000)}")

    def rva_to_off(rva):
        for name, va, vsize, rawptr, rawsize, _ in secs:
            if va <= rva < va + max(vsize, rawsize) and rva - va < rawsize:
                return rawptr + (rva - va)
        return None

    def off_to_rva(off):
        for name, va, vsize, rawptr, rawsize, _ in secs:
            if rawptr <= off < rawptr + rawsize:
                return va + (off - rawptr)
        return None

    # Bridge scans the FIRST executable section.
    text = next(s for s in secs if s[5] & 0x20000000)
    t_name, t_va, t_vsize, t_raw, t_rawsize, _ = text
    t_bytes = data[t_raw:t_raw + min(t_vsize, t_rawsize)]
    image_size = max(va + vsize for _, va, vsize, *_ in secs)

    def rel(site_rva, operand_off, insn_len):
        off = rva_to_off(site_rva + operand_off)
        disp = struct.unpack_from("<i", data, off)[0]
        return site_rva + insn_len + disp

    rx = to_regex(REG_SIG)
    sites = [t_va + m.start() for m in rx.finditer(t_bytes)]
    print(f"\nregistration sites in {t_name}: {len(sites)} (bridge needs >= {MIN_MATCHES})")
    natives = {}
    resolved = {}
    for k, o in OFFSETS.items():
        targets = Counter(rel(s + o, 1, 5) for s in sites)
        winner, agree = targets.most_common(1)[0] if targets else (None, 0)
        resolved[k] = winner
        print(f"  {k:15s} consensus {agree}/{len(sites)} -> rva 0x{winner:X}" if winner else f"  {k}: none")
    for s in sites:
        name_rva = rel(s + OFF_NAME, 3, 7)
        impl_rva = rel(s + OFF_IMPL, 3, 7)
        off = rva_to_off(name_rva)
        if off is None:
            continue
        raw = data[off:off + 96].split(b"\0")[0]
        if raw and all(32 <= c <= 126 for c in raw):
            natives[raw.decode()] = impl_rva
    print(f"  decoded native names: {len(natives)}; sample: {sorted(natives)[:8]}")

    all_agree = all(Counter(rel(s + o, 1, 5) for s in sites).most_common(1)[0][1] == len(sites) for o in OFFSETS.values()) if sites else False
    print(f"  full consensus (bridge requires all sites agree): {all_agree}")

    rg = resolved.get("registerGlobal")
    if rg:
        pro = data[rva_to_off(rg):rva_to_off(rg) + len(PROLOGUE)]
        print(f"\nregisterGlobal prologue matches expected: {pro == PROLOGUE} (got {pro.hex(' ')})")

    lc = natives.get("LogChannel")
    print(f"\nLogChannel native found: {lc is not None}" + (f" at rva 0x{lc:X}" if lc else ""))
    if lc:
        code_off = rva_to_off(lc)
        code = data[code_off:code_off + 0xC0 + 0x80]
        opcode_table = None
        for i in range(0x40):
            if code[i] in (0x48, 0x4C) and code[i + 1] == 0x8D and (code[i + 2] & 0xC7) == 0x05:
                cand = rel(lc + i, 3, 7)
                if 0 <= cand < image_size:
                    opcode_table = cand
                    break
        print(f"  opcode table lea found: {opcode_table is not None}" + (f" rva 0x{opcode_table:X}" if opcode_table else ""))
        if opcode_table:
            toff = rva_to_off(opcode_table)
            if toff is None:
                print("  opcode table lies in uninitialized data (filled at runtime); can't check entries offline")
            else:
                entries = struct.unpack_from("<32Q", data, toff)
                lo, hi = image_base + t_va, image_base + t_va + t_vsize
                inside = sum(1 for e in entries if e and lo <= e < hi)
                nonzero = sum(1 for e in entries if e)
                print(f"  opcode table entries: nonzero={nonzero}/32 inside_text={inside}")
        region = code[:0xC0]
        for label, sig in (("5.01 string pattern (current bridge)", STRING_SIG), ("5.00 string pattern (pre-5.01 bridge)", STRING_SIG_500)):
            n = len(list(to_regex(sig).finditer(region)))
            print(f"  {label}: {n} match(es) in LogChannel[0:0xC0] (bridge needs exactly 1)")


if __name__ == "__main__":
    main(sys.argv[1])
