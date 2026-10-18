# Lists imported functions of a PE file, optionally filtered by DLL and function-name regex (read-only).
# Usage: pe_imports.py <pe file> [dll regex] [function regex]
import re
import struct
import sys


def main():
    path = sys.argv[1]
    dll_re = re.compile(sys.argv[2] if len(sys.argv) > 2 else ".", re.I)
    fn_re = re.compile(sys.argv[3] if len(sys.argv) > 3 else ".", re.I)
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    opt = pe + 24
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    optsz = struct.unpack_from("<H", d, pe + 20)[0]
    secs = []
    for i in range(nsec):
        o = opt + optsz + i * 40
        vs, va, rs, rp = struct.unpack_from("<IIII", d, o + 8)
        secs.append((va, vs, rp, rs))

    def off(rva):
        for va, vs, rp, rs in secs:
            if va <= rva < va + max(vs, rs):
                return rp + rva - va
        raise ValueError(hex(rva))

    imp_rva = struct.unpack_from("<I", d, opt + 112 + 8)[0]
    o = off(imp_rva)
    while True:
        ilt, _, _, name_rva, iat = struct.unpack_from("<IIIII", d, o)
        if name_rva == 0:
            break
        dll = d[off(name_rva):].split(b"\0")[0].decode()
        o += 20
        if not dll_re.search(dll):
            continue
        t = off(ilt or iat)
        names = []
        while True:
            entry = struct.unpack_from("<Q", d, t)[0]
            if entry == 0:
                break
            if not entry & (1 << 63):
                names.append(d[off(entry & 0x7FFFFFFF) + 2:].split(b"\0")[0].decode())
            t += 8
        hits = [n for n in names if fn_re.search(n)]
        if hits:
            print(f"{dll}: {', '.join(hits)}")


if __name__ == "__main__":
    main()
