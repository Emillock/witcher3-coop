# Minimal GitHub REST client that takes the owner's token from Git's credential manager at call time
# (never printed or stored). Usage: gh_api.py <METHOD> <path> [json-body-file]
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request


def token():
    env = dict(os.environ, GCM_INTERACTIVE="never", GIT_TERMINAL_PROMPT="0")
    out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                         capture_output=True, text=True, env=env, timeout=30).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    raise SystemExit("no stored GitHub credential")


def api(method, path, body=None):
    req = urllib.request.Request("https://api.github.com" + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            text = r.read().decode()
            return r.status, json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "null")


if __name__ == "__main__":
    body = json.load(open(sys.argv[3], encoding="utf-8")) if len(sys.argv) > 3 else None
    status, data = api(sys.argv[1], sys.argv[2], body)
    print(status)
    print(json.dumps(data, indent=1)[:4000])
