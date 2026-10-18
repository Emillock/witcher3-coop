# Sets Key=Value inside [Section] of a REDengine .settings file (keeps newline style). Usage: set_setting.py <file> <section> <key> <value>
import sys
p, section, key, value = sys.argv[1:5]
text = open(p, "rb").read().decode("utf-8")
nl = "\r\n" if "\r\n" in text else "\n"
out, in_sec, done, seen_sec = [], False, False, False
for line in text.split(nl):
    if line.startswith("["):
        if in_sec and not done:
            out.append(f"{key}={value}")
            done = True
        in_sec = line.strip() == f"[{section}]"
        seen_sec = seen_sec or in_sec
    elif in_sec and line.split("=", 1)[0] == key:
        line, done = f"{key}={value}", True
    out.append(line)
if not seen_sec:
    out += [f"[{section}]", f"{key}={value}", ""]
open(p, "wb").write(nl.join(out).encode("utf-8"))
print(f"{p}: [{section}] {key}={value}")
