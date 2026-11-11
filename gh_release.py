# Publishes a GitHub release and uploads its package. The token comes from gh_api (Git's credential
# manager, never printed). Usage: gh_release.py <owner/repo> <tag> <notes file> [asset] [--prerelease]
# The notes file's first line is the release title; the rest is the body.
import os
import sys
import urllib.error
import urllib.request

from gh_api import api, token


def upload(repo, release_id, path):
    name = os.path.basename(path)
    size = os.path.getsize(path)
    url = f"https://uploads.github.com/repos/{repo}/releases/{release_id}/assets?name={name}"
    with open(path, "rb") as f:
        req = urllib.request.Request(url, method="POST", data=f)
        req.add_header("Authorization", "Bearer " + token())
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("Content-Type", "application/zip")
        req.add_header("Content-Length", str(size))
        try:
            with urllib.request.urlopen(req, timeout=1800) as r:
                return r.status
        except urllib.error.HTTPError as e:
            sys.exit(f"upload failed {e.code}: {e.read().decode()[:400]}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    repo, tag, notes_path = args[0], args[1], args[2]
    asset = args[3] if len(args) > 3 else None
    lines = open(notes_path, encoding="utf-8").read().split("\n")
    title, body = lines[0].strip(), "\n".join(lines[1:]).strip()
    status, data = api("POST", f"/repos/{repo}/releases", {
        "tag_name": tag, "name": title, "body": body,
        "prerelease": "--prerelease" in sys.argv, "draft": False,
    })
    if status != 201:
        sys.exit(f"release failed {status}: {str(data)[:400]}")
    print(f"created {data['html_url']} (id {data['id']})")
    if asset:
        print(f"uploaded {os.path.basename(asset)}: {upload(repo, data['id'], asset)}")


if __name__ == "__main__":
    main()
