#!/usr/bin/env bash
# scripts/stop.sh — kill ALL mini_bot processes (watchdog, bot, wxlink, lark
# subscriber, /bg runners). Use this between dev restarts to prevent zombies.
#
# Usage:  scripts/stop.sh
#         BOT_HOME=/path/to/mini_bot scripts/stop.sh

set -u
BOT_HOME="${BOT_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

pids=()
add_match() {
  local pat="$1" p
  for p in $(pgrep -f "$pat" 2>/dev/null); do
    pids+=( "$p" )
  done
}

# Order matters: watchdog first so it doesn't respawn things.
add_match "scripts/watchdog\.sh"
add_match "${BOT_HOME}/bot\.sh"
add_match "wxlink\.py.*subscribe"
add_match "lark-cli event \+subscribe"
add_match "lark_event_parser\.py"
add_match "@larksuite/cli/bin/lark-cli event \+subscribe"

# Dedupe.
if ((${#pids[@]} > 0)); then
  uniq_pids=$(printf '%s\n' "${pids[@]}" | sort -un)
  echo "killing PIDs:"; echo "$uniq_pids" | tr '\n' ' '; echo
  for p in $uniq_pids; do
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 1
  for p in $uniq_pids; do
    kill -KILL "$p" 2>/dev/null || true
  done
fi

rm -f "$BOT_HOME/state/watchdog.pid"
rm -f "$HOME/.lark-cli/locks/subscribe_"*.lock 2>/dev/null || true
echo "done."
