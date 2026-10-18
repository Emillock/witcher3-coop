#!/usr/bin/env bash
# Deploys the Witcher Online scripts + client (with the compat stand-ins) and the test bot, then runs a
# compile-only check.
# Usage: compile.sh <tag> [extra deploy args...]
set -u
T=/c/Users/User/Desktop/repos/witcher3-coop-tools
W='C:\Users\User\Desktop\repos'
tag=$1; shift
cd "$T"
python -I deploy.py install --scripts-only --dlc --no-gwent \
  --extra "$W\\WitcherOnline\\client\\build\\Release\\WitcherOnlineClient.asi=bin\\x64_dx12\\WitcherOnlineClient.asi" \
  --extra "$W\\witcher3-coop-tools\\w3test\\modW3Test=mods\\modW3Test" \
  --extra "$W\\witcher3-coop-tools\\w3test\\build\\w3test.asi=bin\\x64_dx12\\w3test.asi" \
  "$@" | tail -1
WO_USERNAME=CompileBot WO_SERVER_IP=127.0.0.1 WO_SERVER_PORT=41999 python w3run.py --timeout 240 --tag "$tag" --errors "../work/compile/$tag.txt" --show 0 --sandbox "$W\\work\\sandbox-compile" -- -verifyscriptsandexit 2>&1 | grep -E "ERRORS|exited|killed"
f="../work/compile/$tag.txt"
if [ -f "$f" ]; then
  echo "errors: $(grep -c '^Error' "$f")  warnings: $(grep -c '^Warning' "$f")"
  grep "^Error" "$f" | sed -E 's/\(([0-9]+)\)/:\1/' | head -${SHOW:-60}
else
  echo "no compile errors"
fi
