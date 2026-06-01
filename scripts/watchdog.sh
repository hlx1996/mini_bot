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
WD_PID=$$
cd "$REPO_DIR"
# Make ~/.local/bin and ~/Library/Python/*/bin visible for pip-installed CLIs
# (yt-dlp / tesseract / etc may live there on macOS/Linux without root).
for _p in "$HOME/.local/bin" "$HOME/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
  [[ -d "$_p" && ":$PATH:" != *":$_p:"* ]] && PATH="$_p:$PATH"
done
for _p in "$HOME"/Library/Python/*/bin; do
  [[ -d "$_p" && ":$PATH:" != *":$_p:"* ]] && PATH="$_p:$PATH"
done
export PATH
export BOT_HOME="$STATE_DIR"
# Load .env (optional) — for AZURE_SPEECH_KEY / OPENAI_API_KEY / etc
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a; . "$REPO_DIR/.env"; set +a
fi

# ── Connection health monitor ────────────────────────────────────────────────
# The Feishu WSS / WeChat long-poll can enter a "reconnect storm" on a hostile
# corporate network: the subscriber process stays alive but its connection is
# dead, so events stop flowing for minutes-to-an-hour while the SDK retries.
# bot.sh's normal exit-restart never triggers because nothing crashes. This
# monitor detects the storm (events.jsonl gone stale AND a lark err log actively
# logging timeouts) and restarts bot.sh, whose startup reaper clears the dead
# subscriber and re-establishes a fresh connection. Disable with BOT_HEALTH=0.
_mtime() {  # portable st_mtime (epoch): macOS `stat -f`, Linux `stat -c`
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}
health_monitor() {
  local interval="${BOT_HEALTH_INTERVAL:-90}"
  local stale="${BOT_HEALTH_STALE:-240}"
  local storm="${BOT_HEALTH_STORM:-3}"
  local cooldown="${BOT_HEALTH_COOLDOWN:-300}"
  local evlog="$LOG_DIR/events.jsonl"
  local marker="$LOG_DIR/health.lastrestart"
  while true; do
    sleep "$interval"
    # Self-terminate if our watchdog is gone (avoids orphaned monitors piling up
    # across watchdog restarts).
    kill -0 "$WD_PID" 2>/dev/null || exit 0
    [[ "${BOT_HEALTH:-1}" == "1" ]] || continue
    [[ -f "$evlog" ]] || continue
    local now ev_age ev_m
    now=$(date +%s); ev_m=$(_mtime "$evlog"); ev_age=$((now - ev_m))
    # Fresh events → connection is delivering → healthy.
    (( ev_age < stale )) && continue
    # Events are stale. Distinguish "idle (nobody messaging)" from "storm" by
    # requiring a lark err log that is (a) actively being written and (b) full of
    # timeout/reconnect lines. A healthy idle connection writes neither.
    local errf storming=0 em c
    for errf in "$LOG_DIR"/lark-*.err; do
      [[ -f "$errf" ]] || continue
      em=$(_mtime "$errf")
      (( now - em > interval * 2 )) && continue
      c=$(tail -n 80 "$errf" 2>/dev/null \
            | grep -cE 'operation timed out|receive message failed|reconnect|connection.*(reset|closed)')
      (( c >= storm )) && storming=1
    done
    (( storming == 0 )) && continue
    # Cooldown: don't thrash-restart.
    if [[ -f "$marker" ]]; then
      local mm; mm=$(_mtime "$marker")
      (( now - mm < cooldown )) && continue
    fi
    : > "$marker"
    echo "[health $(date +%FT%T)] reconnect storm detected (events stale ${ev_age}s, lark err storming) → restarting bot.sh" >> "$LOG_DIR/health.log"
    local bp
    for bp in $(pgrep -f "$REPO_DIR/bot.sh" 2>/dev/null); do
      [[ "$bp" == "$WD_PID" ]] && continue
      kill "$bp" 2>/dev/null
    done
  done
}
health_monitor &

while true; do
  bash "$REPO_DIR/bot.sh" >> "$LOG_DIR/watchdog.out" 2>> "$LOG_DIR/watchdog.err"
  echo "[watchdog $(date +%FT%T)] bot.sh exited rc=$?, restarting in 5s" >> "$LOG_DIR/watchdog.err"
  sleep 5
done
