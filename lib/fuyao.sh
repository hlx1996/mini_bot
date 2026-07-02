#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao models via opencode harness (full agent with tools).
# opencode provides: file read/write, shell, web search, session persistence.
# Env: OPENCODE_BIN (default: opencode)

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

_oc_session_file() { echo "$SESS_DIR/$1.oc_session"; }

# run_opencode_agent <prompt> <key> <workspace> <model> [attachments...]
# Mirrors run_qoder_agent but uses opencode as the harness.
run_opencode_agent() {
  local prompt="$1" key="$2" workspace="$3" model="$4"
  shift 4
  local attachments=( "$@" )

  local started_marker="$SESS_DIR/$key.started"
  local oc_sf; oc_sf=$(_oc_session_file "$key")

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
  "$OPENCODE_BIN" "${args[@]}" >"$raw_out" 2>>"$LOG_DIR/opencode.err"
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    touch "$started_marker"
    # Capture session ID from first JSON event (for future resume)
    local sid
    sid=$(head -1 "$raw_out" | jq -r '.sessionID // empty' 2>/dev/null)
    [[ -n "$sid" ]] && printf '%s' "$sid" > "$oc_sf"
  fi

  # Extract text content from JSON events
  local text
  text=$(jq -r 'select(.type=="text") | .part.text // empty' < "$raw_out" 2>/dev/null | tr -d '\n' | sed 's/^ *//')
  rm -f "$raw_out"

  if [[ -z "$text" ]]; then
    log "opencode returned empty (rc=$rc)"
    echo "(opencode 没有返回内容)"
    return 1
  fi

  log "opencode OK model=$model chars=${#text}"
  printf '%s' "$text"
}
