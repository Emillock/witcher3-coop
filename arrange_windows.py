# Places every running Witcher 3 window side by side (oldest first), e.g. for a test run already in progress.
# Usage: arrange_windows.py [--watch SECONDS]
import argparse
import csv
import io
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w3run import arrange  # noqa: E402


def game_pids():
    out = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "Get-Process witcher3 -ErrorAction SilentlyContinue | Sort-Object StartTime | "
                          "Select-Object Id | ConvertTo-Csv -NoTypeInformation"], capture_output=True, text=True).stdout
    return [int(row["Id"]) for row in csv.DictReader(io.StringIO(out))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", type=float, default=0, help="keep them in place for this many seconds")
    a = ap.parse_args()
    end = time.time() + a.watch
    while True:
        pids = game_pids()
        arrange(pids)
        if time.time() >= end:
            print(f"arranged {len(pids)} window(s)")
            return 0
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
