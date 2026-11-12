# Publishes a GitHub release and uploads its package. The token comes from gh_api (Git's credential
# manager, never printed). Usage: gh_release.py <owner/repo> <tag> [notes file.md] [asset] [--prerelease]
# Without a notes file the release notes are CHANGELOG.md's section for the tag; with one, its first line is
# the release title and the rest the body. Either way the changelog must hold that version's section: a
# version is written down there when it is published, which is the only time that file changes.
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


CHANGELOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "CHANGELOG.md")


def changelog_notes(tag):
    """The changelog's section for this tag as (title, body), from a heading of the form
    "## [0.6.1] - 2026-11-12 - what the release is about"."""
    version = tag[1:] if tag.startswith("v") else tag
    heading = f"## [{version}]"
    text = open(CHANGELOG, encoding="utf-8").read()
    start = text.find("\n" + heading)
    if start < 0:
        sys.exit(f"CHANGELOG.md has no section for {version}. A version is written down there as it is "
                 f"published: add '{heading} - <date> - <what it is about>' and what it brings, then publish.")
    start += 1
    end = text.find("\n## ", start)
    section = text[start:end if end > 0 else len(text)].strip().split("\n")
    about = section[0].split(" - ", 2)
    title = f"v{version} - {about[2].strip()}" if len(about) > 2 else f"v{version}"
    return title, "\n".join(section[1:]).strip()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    repo, tag = args[0], args[1]
    rest = args[2:]
    notes_path = next((a for a in rest if a.lower().endswith(".md")), None)
    asset = next((a for a in rest if not a.lower().endswith(".md")), None)
    # also the check that this version has been written into the changelog
    title, body = changelog_notes(tag)
    if notes_path:
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
