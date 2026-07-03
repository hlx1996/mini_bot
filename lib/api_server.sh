#!/usr/bin/env bash
# lib/api_server.sh — Start/stop the mini_bot API proxy server.
# Env: BOT_API_PORT (default 9877), FUYAO_API_KEY, FUYAO_BASE_URL, QODER_BIN

BOT_API_PORT="${BOT_API_PORT:-9877}"
_API_PID_FILE="$SCRIPT_DIR/state/.api_server.pid"

start_api_server() {
  if [[ -f "$_API_PID_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$_API_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      log "api_server already running (pid=$old_pid)"
      return 0
    fi
    rm -f "$_API_PID_FILE"
  fi

  local env_args=()
  env_args+=( "BOT_API_PORT=$BOT_API_PORT" )
  [[ -n "${FUYAO_API_KEY:-}" ]] && env_args+=( "FUYAO_API_KEY=$FUYAO_API_KEY" )
  [[ -n "${FUYAO_BASE_URL:-}" ]] && env_args+=( "FUYAO_BASE_URL=$FUYAO_BASE_URL" )
  [[ -n "${QODER_BIN:-}" ]] && env_args+=( "QODER_BIN=$QODER_BIN" )

  env "${env_args[@]}" node "$SCRIPT_DIR/lib/api_server.js" \
    >>"$LOG_DIR/api_server.log" 2>&1 &
  local pid=$!
  printf '%s' "$pid" > "$_API_PID_FILE"
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    log "api_server started pid=$pid port=$BOT_API_PORT"
  else
    log "api_server FAILED to start (check $LOG_DIR/api_server.log)"
    rm -f "$_API_PID_FILE"
    return 1
  fi
}

stop_api_server() {
  if [[ -f "$_API_PID_FILE" ]]; then
    local pid
    pid=$(cat "$_API_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      sleep 1
      kill -9 "$pid" 2>/dev/null
      log "api_server stopped (pid=$pid)"
    fi
    rm -f "$_API_PID_FILE"
  fi
}
