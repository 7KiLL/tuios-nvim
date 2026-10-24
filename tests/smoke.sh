#!/usr/bin/env bash
# End-to-end check against a real (throwaway) tuios daemon.
#
# It creates a git repo and a fake "Claude" pane that makes two turns of changes,
# then runs tests/smoke.lua in headless nvim against them.
# Your real tuios sessions are not touched: everything runs on the server "tnv-test".
set -euo pipefail

plugin_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$(mktemp -d)"
repo="$work_dir/repo"

export TUIOS_SERVER=tnv-test
export TUIOS_SESSION=smoke

cleanup() {
  # Kill the session first, so the daemon does not save it and bring it back next run.
  tuios kill-session "$TUIOS_SESSION" >/dev/null 2>&1 || true
  tuios kill-server >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

# A repo with one commit.
mkdir -p "$repo"
cd "$repo"
git init -q -b main
git config user.email test@example.com
git config user.name test
printf 'local M = {}\n\nfunction M.add(a, b)\n  return a + b\nend\n\nfunction M.sub(a, b)\n  return a - b\nend\n\nreturn M\n' > math.lua
git add -A
git commit -qm init

# A daemon, and a pane that plays Claude. It runs `cat` so typed messages are harmless.
tuios start-server >/dev/null
tuios kill-session "$TUIOS_SESSION" >/dev/null 2>&1 || true  # left over from a run that crashed
tuios call new-session "{\"name\":\"$TUIOS_SESSION\",\"window_name\":\"claude\",\"cwd\":\"$repo\"}" >/dev/null
tuios send-text -s "$TUIOS_SESSION" -w claude 'exec cat
'

fake_turn() {
  tuios set-agent-state working -s "$TUIOS_SESSION" -w claude --harness claude-code
  eval "$1"
  sleep 1
  tuios set-agent-state done -s "$TUIOS_SESSION" -w claude --harness claude-code
  sleep 1
}
fake_turn "sed -i 's/return a + b/return a + b + 0/' math.lua"
fake_turn "sed -i 's/return a - b/return a - b -- turn 2/' math.lua"

# Run the Lua checks inside the repo, as a user would.
TUIOS_ENV=1 nvim --headless --clean \
  --cmd "set rtp+=$plugin_dir" \
  -c "runtime plugin/tuios-nvim.lua" \
  -c "luafile $plugin_dir/tests/smoke.lua" \
  "$repo/math.lua"
