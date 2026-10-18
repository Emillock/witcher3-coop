import sys
raw = open(sys.argv[1], "rb").read()
if raw.startswith(b"\xff\xfe"): s = raw[2:].decode("utf-16-le")
elif raw.startswith(b"\xef\xbb\xbf"): s = raw[3:].decode("utf-8")
elif len(raw) > 1 and raw[1:2] == b"\0": s = raw.decode("utf-16-le")
else: s = raw.decode("utf-8", "replace")
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(s.replace("\r\n", "\n"))
print(sys.argv[1].rsplit("/",1)[-1], "bom:", raw[:3].hex(), "len", len(raw))
