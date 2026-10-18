# Prints ASCII and UTF-16LE strings from a binary that match a regex (read-only).
# Usage: exe_strings.py <binary> <regex> [min_len]
import re
import sys


def strings(data, min_len):
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % min_len, data):
        yield m.start(), m.group().decode("ascii")
    for m in re.finditer(rb"(?:[\x20-\x7e]\x00){%d,}" % min_len, data):
        yield m.start(), m.group().decode("utf-16-le")


def main():
    data = open(sys.argv[1], "rb").read()
    key = re.compile(sys.argv[2])
    min_len = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    seen = set()
    for off, s in strings(data, min_len):
        if key.search(s) and s not in seen and len(s) < 200:
            seen.add(s)
            print(f"0x{off:08X} {s!r}")


if __name__ == "__main__":
    main()
