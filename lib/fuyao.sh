#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao models: direct API or opencode harness.
# Direct mode: curl to Fuyao gateway (fast, streaming, no harness overhead).
# Harness mode: opencode run (full agent with tools — file read/write, shell, web search).
# Env: FUYAO_API_KEY, FUYAO_BASE_URL, FUYAO_DIRECT (default 1), OPENCODE_BIN, FUYAO_TIMEOUT

# No baked-in credentials — both come from .env or the environment. Copy
# .env.example to .env and fill these in; a missing key fails loudly rather than
# silently using someone else's quota.
FUYAO_API_KEY="${FUYAO_API_KEY:-}"
FUYAO_BASE_URL="${FUYAO_BASE_URL:-https://your-fuyao-gateway.example.com/v1}"
FUYAO_DIRECT="${FUYAO_DIRECT:-0}"
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
FUYAO_TIMEOUT="${FUYAO_TIMEOUT:-120}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

_oc_session_file() { echo "$SESS_DIR/$1.oc_session"; }
_oc_model_file() { echo "$SESS_DIR/$1.oc_model"; }

# run_fuyao_direct <prompt> <key> <workspace> <model> [attachments...]
# Direct curl to Fuyao gateway — no harness, fast, supports streaming.
# Falls back to run_opencode_agent if curl fails.
run_fuyao_direct() {
  local prompt="$1" key="$2" workspace="$3" model="$4"
  shift 4

  # Map "fuyao-coding-low/-high/-max" → upstream "fuyao-coding" + reasoning_effort
  local upstream_model="$model"
  local effort=""
  case "$model" in
    *-low)  upstream_model="${model%-low}";  effort="low" ;;
    *-high) upstream_model="${model%-high}"; effort="high" ;;
    *-max)  upstream_model="${model%-max}";  effort="max" ;;
  esac

  local sys_prompt
  local soul_name mem gmem
  soul_name=$(current_soul_for_key "$key" 2>/dev/null)
  sys_prompt=$(soul_text "$soul_name" 2>/dev/null || echo "你是一个有帮助的AI助手。")
  mem=$(memory_show "$key" 2>/dev/null)
  [[ "$mem" != "(本会话暂无记忆)" && -n "$mem" ]] && sys_prompt+=$'\n\n[记忆]:\n'"$mem"
  gmem=$(memory_show_global 2>/dev/null)
  [[ "$gmem" != "(全局记忆暂为空)" && -n "$gmem" ]] && sys_prompt+=$'\n\n[全局记忆]:\n'"$gmem"

  # Build JSON messages array
  local sys_escaped prompt_escaped
  sys_escaped=$(printf '%s' "$sys_prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
  prompt_escaped=$(printf '%s' "$prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

  # Include attachment contents in the prompt if any
  local extra_context=""
  for a in "$@"; do
    if [[ -f "$a" ]]; then
      local content
      content=$(cat "$a" 2>/dev/null)
      if [[ -n "$content" ]]; then
        local fname
        fname=$(basename "$a")
        extra_context+=$'\n\n['"$fname"']:\n'"$content"
      fi
    fi
  done
  if [[ -n "$extra_context" ]]; then
    local extra_escaped
    extra_escaped=$(printf '%s' "$extra_context" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    prompt_escaped=$(python3 -c "import json; a=json.loads($prompt_escaped); b=json.loads($extra_escaped); print(json.dumps(a+b))")
  fi

  local effort_json=""
  [[ -n "$effort" ]] && effort_json=$',\n  "reasoning_effort": "'"$effort"'"'

  local body
  body=$(cat <<ENDJSON
{
  "model": "$upstream_model",
  "messages": [
    {"role": "system", "content": $sys_escaped},
    {"role": "user", "content": $prompt_escaped}
  ],
  "stream": false,
  "max_tokens": 4096$effort_json
}
ENDJSON
)

  log "fuyao DIRECT model=$model upstream=$upstream_model effort=${effort:-none} prompt=${prompt:0:60}..."

  local raw_out; raw_out=$(mktemp -t fuyao_direct.XXXXXX)
  local http_code
  http_code=$(curl -sS --max-time "$FUYAO_TIMEOUT" -w '%{http_code}' \
    -X POST "${FUYAO_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${FUYAO_API_KEY}" \
    -d "$body" \
    -o "$raw_out" 2>>"$LOG_DIR/fuyao_direct.err")
  local curl_rc=$?

  if (( curl_rc != 0 )); then
    log "fuyao DIRECT curl failed (rc=$curl_rc http=$http_code)"
    rm -f "$raw_out"
    echo "(Fuyao 网关调用失败，curl rc=$curl_rc)"
    return 1
  fi

  if [[ "$http_code" != "200" ]]; then
    local err_body
    err_body=$(cat "$raw_out" | head -c 500)
    log "fuyao DIRECT HTTP $http_code: $err_body"
    rm -f "$raw_out"
    echo "(Fuyao 网关返回 HTTP $http_code)"
    return 1
  fi

  # Extract content (handle reasoning models where content may be null)
  local text
  text=$(jq -r '
    .choices[0].message //
    {content: "(无返回内容)"} |
    if .content != null then .content
    elif .reasoning != null then .reasoning
    else "(无返回内容)"
    end
  ' < "$raw_out" 2>/dev/null)
  rm -f "$raw_out"

  # Strip reasoning/thinking tags leaked by reasoning models
  if [[ "$text" == *"</think>"* ]]; then
    text="${text##*</think>}"
  fi

  # Trim whitespace
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"

  if [[ -z "$text" ]]; then
    log "fuyao DIRECT empty response model=$model"
    echo "(Fuyao 没有返回内容)"
    return 1
  fi

  local started_marker="$SESS_DIR/$key.started"
  touch "$started_marker"
  log "fuyao DIRECT OK model=$model chars=${#text}"
  printf '%s' "$text"
}

# _kill_tree <pid> — TERM then KILL a process and its direct children.
# opencode run spawns tool subprocesses; a bare `kill` leaves them reparented.
_kill_tree() {
  local pid="$1" child
  [[ -z "$pid" ]] && return 0
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    _kill_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null
  sleep 1
  kill -KILL "$pid" 2>/dev/null
  return 0
}

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

  # opencode >=2 dropped `run --dir`; the workspace is set by cd'ing the subshell
  # that launches it. `exec` keeps $! pointing at opencode itself, so _kill_tree
  # and bot.sh's heartbeat kill still address the real process.
  local args=( run -m "fuyao/$model" --dangerously-skip-permissions --format json )

  # IMPORTANT: prompt positional must come BEFORE `-f` flags. opencode's yargs
  # parser greedily absorbs every positional after `-f` as a file path, so
  # "opencode run -f sys.txt '1+1'" fails with "File not found: 1+1".
  args+=( "$prompt" )

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

  local raw_out; raw_out=$(mktemp -t oc_out.XXXXXX)
  local raw_err; raw_err=$(mktemp -t oc_err.XXXXXX)

  # Use per-session timeout if set (via /timeout), else FUYAO_TIMEOUT
  local _oc_timeout="$FUYAO_TIMEOUT"
  if [[ -s "$SESS_DIR/$key.timeout" ]]; then
    _oc_timeout=$(cat "$SESS_DIR/$key.timeout")
  fi

  # Run with timeout. stderr is captured per-run (not appended straight to the
  # shared log) so a failure can be reported back instead of silently surfacing
  # as an empty reply.
  ( cd "$workspace" && exec "$OPENCODE_BIN" "${args[@]}" ) \
    </dev/null >"$raw_out" 2>"$raw_err" &
  local oc_pid=$!
  # PID file contract: bot.sh reap_stale_runs() & heartbeat kill read this to
  # kill the opencode tree when this shell is dead (orphan prevention).
  printf '%s' "$oc_pid" > "$SESS_DIR/$key.oc_pid"
  local elapsed=0
  while kill -0 "$oc_pid" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if (( elapsed > _oc_timeout )); then
      log "opencode TIMEOUT after ${_oc_timeout}s, killing pid $oc_pid"
      _kill_tree "$oc_pid"
      break
    fi
  done
  wait "$oc_pid" 2>/dev/null
  local rc=$?
  rm -f "$SESS_DIR/$key.oc_pid"
  [[ -s "$raw_err" ]] && cat "$raw_err" >> "$LOG_DIR/opencode.err"

  # Check for error events in output (opencode >=2 nests the text at .error.message)
  local err_msg
  err_msg=$(jq -r 'select(.type=="error") | .error.message // .error.data.message // .error.type // empty' < "$raw_out" 2>/dev/null | head -1)
  if [[ -n "$err_msg" ]]; then
    log "opencode ERROR model=$model: $err_msg"
    rm -f "$raw_out" "$raw_err"
    # Context overflow → session is unusable, reset so next call starts fresh
    if [[ "$err_msg" == *"maximum context length"* || "$err_msg" == *"token"* ]]; then
      rm -f "$oc_sf" "$started_marker"
      log "opencode session reset due to context overflow"
    fi
    echo "(模型调用失败: $err_msg)"
    return 1
  fi

  # Capture the session ID whenever opencode created one, and mark the session
  # started if the run exited clean or at least produced a session. Gating both
  # on rc==0 would drop multi-turn continuity for runs that return valid text
  # but exit non-zero (rc used to be misread as 0 here, so this was never hit).
  local sid
  sid=$(head -1 "$raw_out" | jq -r '.sessionID // empty' 2>/dev/null)
  [[ -n "$sid" ]] && printf '%s' "$sid" > "$oc_sf"
  if [[ $rc -eq 0 || -n "$sid" ]]; then
    touch "$started_marker"
  fi

  # Extract text content from JSON events (preserve newlines between parts)
  local text
  text=$(jq -r 'select(.type=="text") | .part.text // empty' < "$raw_out" 2>/dev/null)
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  rm -f "$raw_out"

  if [[ -z "$text" ]]; then
    if (( elapsed > _oc_timeout )); then
      rm -f "$raw_err"
      echo "(模型响应超时，请稍后重试或切换模型)"
    else
      # Flag-parse errors and DB locks only ever reach stderr — they never arrive
      # as a JSON `error` event, so without this the real cause stays invisible
      # and every such failure looks like a plain empty reply.
      local reason
      reason=$(tail -3 "$raw_err" 2>/dev/null | tr -s '[:space:]' ' ')
      reason="${reason#"${reason%%[![:space:]]*}"}"
      reason="${reason%"${reason##*[![:space:]]}"}"
      rm -f "$raw_err"
      log "opencode returned empty (rc=$rc elapsed=${elapsed}s): ${reason:-<no stderr>}"
      # A transient SQLite lock fails the write cleanly and leaves the session
      # intact, so wiping it here would throw away the user's whole conversation
      # over an infrastructure blip. Only reset for genuinely unexplained empties.
      case "$reason" in
        *"database is locked"*|*"SQLITE_BUSY"*)
          log "opencode transient failure; keeping session ${oc_session:-<none>}"
          echo "(opencode 暂时不可用: ${reason:0:200})"
          ;;
        *)
          rm -f "$oc_sf" "$started_marker"
          if [[ -n "$reason" ]]; then
            echo "(opencode 调用失败: ${reason:0:200})"
          else
            echo "(opencode 没有返回内容，已重置会话，请重试)"
          fi
          ;;
      esac
    fi
    return 1
  fi

  rm -f "$raw_err"
  log "opencode OK model=$model chars=${#text}"
  printf '%s' "$text"
}
