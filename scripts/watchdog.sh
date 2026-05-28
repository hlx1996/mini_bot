#!/usr/bin/env bash
# mini_bot watchdog — respawns bot.sh on crash, idempotent on repeated runs.
REPO_DIR="/Users/xpeng/Projects/mini_bot"
STATE_DIR="/Users/xpeng/Projects/mini_bot/state"
LOG_DIR="/Users/xpeng/Projects/mini_bot/state/logs"
PID_FILE="/Users/xpeng/Projects/mini_bot/state/watchdog.pid"
mkdir -p "$LOG_DIR"
# already running?
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  exit 0
fi
echo $$ > "$PID_FILE"
cd "$REPO_DIR"
export BOT_HOME="$STATE_DIR"
# Load .env (optional) — for AZURE_SPEECH_KEY / OPENAI_API_KEY / etc
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a; . "$REPO_DIR/.env"; set +a
fi
while true; do
  bash "$REPO_DIR/bot.sh" >> "$LOG_DIR/watchdog.out" 2>> "$LOG_DIR/watchdog.err"
  echo "[watchdog $(date +%FT%T)] bot.sh exited rc=$?, restarting in 5s" >> "$LOG_DIR/watchdog.err"
  sleep 5
done
