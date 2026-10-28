#!/usr/bin/env bash
# scripts/stop.sh — kill ALL mini_bot processes (watchdog, bot, wxlink, lark
# subscriber, /bg runners). Use this between dev restarts to prevent zombies.
#
# Usage:  scripts/stop.sh
#         BOT_HOME=/path/to/mini_bot/state scripts/stop.sh
#
# BOT_HOME means the STATE dir here, same as bot.sh / watchdog.sh /
# install-service.sh. Process matching must NOT use it: the watchdog exports
# BOT_HOME=$STATE_DIR, so keying the bot.sh pattern off BOT_HOME silently
# matched nothing and left every bot process alive while killing the watchdog.
# The repo path is derived from this script's own location instead.

set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${BOT_HOME:-$REPO_DIR/state}"

pids=()
add_match() {
  local pat="$1" p
  for p in $(pgrep -f "$pat" 2>/dev/null); do
    pids+=( "$p" )
  done
}

# Order matters: watchdog first so it doesn't respawn things.
# The watchdog pattern is deliberately not anchored to $REPO_DIR — README starts
# it as `./scripts/watchdog.sh`, and missing it would let it respawn the bot.
add_match "scripts/watchdog\.sh"
add_match "${REPO_DIR}/bot\.sh"
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

rm -f "$STATE_DIR/watchdog.pid"
rm -f "$HOME/.lark-cli/locks/subscribe_"*.lock 2>/dev/null || true
echo "done."
