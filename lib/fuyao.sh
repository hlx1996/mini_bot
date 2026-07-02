#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao models via opencode harness (full agent with tools).
# opencode provides: file read/write, shell, web search, session persistence.
# Env: OPENCODE_BIN (default: opencode), FUYAO_TIMEOUT (default: 120s)

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
FUYAO_TIMEOUT="${FUYAO_TIMEOUT:-120}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

_oc_session_file() { echo "$SESS_DIR/$1.oc_session"; }
_oc_model_file() { echo "$SESS_DIR/$1.oc_model"; }

# run_opencode_agent <prompt> <key> <workspace> <model> [attachments...]
# Mirrors run_qoder_agent but uses opencode as the harness.
run_opencode_agent() {
  local prompt="$1" key="$2" workspace="$3" model="$4"
  shift 4
  local attachments=( "$@" )

  local started_marker="$SESS_DIR/$key.started"
  local oc_sf; oc_sf=$(_oc_session_file "$key")
  local oc_mf; oc_mf=$(_oc_model_file "$key")

  # If model changed since last call, invalidate session
  local prev_model=""
  [[ -s "$oc_mf" ]] && prev_model=$(cat "$oc_mf")
  if [[ -n "$prev_model" && "$prev_model" != "$model" ]]; then
    log "opencode model changed ($prev_model -> $model), resetting session"
    rm -f "$oc_sf" "$started_marker"
  fi
  printf '%s' "$model" > "$oc_mf"

  local sys_prompt
  sys_prompt=$(build_system_prompt "$key")

  # Write AGENTS.md into workspace so opencode picks up the system prompt
  printf '# agent\n\n## system\n%s\n' "$sys_prompt" > "$workspace/AGENTS.md"

  local args=( run -m "fuyao/$model" --dangerously-skip-permissions
               --dir "$workspace" --format json )

  for a in ${attachments[@]+"${attachments[@]}"}; do
    args+=( -f "$a" )
  done

  # Session continuity: resume if we have a stored opencode session ID
  local oc_session=""
  if [[ -f "$started_marker" && -s "$oc_sf" ]]; then
    oc_session=$(cat "$oc_sf")
    args+=( --session "$oc_session" )
    log "opencode RESUME session=$oc_session model=$model cwd=$workspace"
  else
    log "opencode NEW model=$model cwd=$workspace"
  fi

  args+=( "$prompt" )

  local raw_out; raw_out=$(mktemp -t oc_out.XXXXXX)

  # Run with timeout
  "$OPENCODE_BIN" "${args[@]}" >"$raw_out" 2>>"$LOG_DIR/opencode.err" &
  local oc_pid=$!
  local elapsed=0
  while kill -0 "$oc_pid" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if (( elapsed > FUYAO_TIMEOUT )); then
      log "opencode TIMEOUT after ${FUYAO_TIMEOUT}s, killing pid $oc_pid"
      kill "$oc_pid" 2>/dev/null
      sleep 1; kill -9 "$oc_pid" 2>/dev/null
      break
    fi
  done
  wait "$oc_pid" 2>/dev/null
  local rc=$?

  # Check for error events in output
  local err_msg
  err_msg=$(jq -r 'select(.type=="error") | .error.data.message // .error.name // empty' < "$raw_out" 2>/dev/null | head -1)
  if [[ -n "$err_msg" ]]; then
    log "opencode ERROR model=$model: $err_msg"
    rm -f "$raw_out"
    echo "(模型调用失败: $err_msg)"
    return 1
  fi

  if [[ $rc -eq 0 ]]; then
    touch "$started_marker"
    # Capture session ID from first JSON event (for future resume)
    local sid
    sid=$(head -1 "$raw_out" | jq -r '.sessionID // empty' 2>/dev/null)
    [[ -n "$sid" ]] && printf '%s' "$sid" > "$oc_sf"
  fi

  # Extract text content from JSON events (preserve newlines between parts)
  local text
  text=$(jq -r 'select(.type=="text") | .part.text // empty' < "$raw_out" 2>/dev/null)
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  rm -f "$raw_out"

  if [[ -z "$text" ]]; then
    if (( elapsed > FUYAO_TIMEOUT )); then
      echo "(模型响应超时，请稍后重试或切换模型)"
    else
      log "opencode returned empty (rc=$rc)"
      # Session might be corrupted, clear it for next attempt
      rm -f "$oc_sf" "$started_marker"
      echo "(opencode 没有返回内容，已重置会话，请重试)"
    fi
    return 1
  fi

  log "opencode OK model=$model chars=${#text}"
  printf '%s' "$text"
}
