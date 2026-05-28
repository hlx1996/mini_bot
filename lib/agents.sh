#!/usr/bin/env bash
# lib/agents.sh — Sub-agent (/agent), team pipeline (/team), auto-memory (/automem).
# Depends on: SESS_DIR, MEM_DIR, WORK_ROOT, QODER_BIN, LOG_DIR,
#             soul_text, memory_add, model_for_key, log.

# ---------- Sub-agent / Team / Auto-memory (v5) ----------
#
# /agent <soul> <task>  — spawn a one-off qoder run with a different soul/persona,
#                          isolated session (no resume), returns its output inline.
# /team list|set|run    — define an ordered pipeline of personas. /team run forwards
#                          a single task through each persona, each one sees prior
#                          outputs as context.
# /automem on|off       — after each turn, ask qoder to extract 0..N durable facts
#                          and auto-append them to /memory.

# agent_run <soul-name> <prompt> <workspace> <model>  → echoes the reply
agent_run() {
  local soul_name="$1" prompt="$2" workspace="$3" model="$4"
  local sys; sys=$(soul_text "$soul_name")
  [[ -z "$sys" ]] && sys=$(soul_text default)
  local args=( -p "$prompt" -m "$model" --cwd "$workspace"
               --permission-mode bypass_permissions
               --append-system-prompt "$sys"
               --max-output-tokens 4000 )
  "$QODER_BIN" "${args[@]}" 2>>"$LOG_DIR/qoder.err"
}

# ---------- /team — multi-persona pipeline ----------
team_file()    { echo "$SESS_DIR/$1.team"; }
team_get()     { cat "$(team_file "$1")" 2>/dev/null; }
team_set()     { local k="$1"; shift; printf '%s\n' "$*" > "$(team_file "$k")"; }
team_clear()   { rm -f "$(team_file "$1")"; }

# team_run <key> <workspace> <model> <task>
team_run() {
  local key="$1" workspace="$2" model="$3" task="$4"
  local roles; roles=$(team_get "$key")
  [[ -z "$roles" ]] && { echo "(team 未配置，先 /team set <role1> <role2> …)"; return 1; }
  local ctx="$task" out combined=""
  for r in $roles; do
    local prompt="[Team task]: $task

[Conversation so far]:
$ctx

You are role: $r — focus on YOUR specialty, then hand off."
    out=$(agent_run "$r" "$prompt" "$workspace" "$model")
    [[ -z "$out" ]] && out="(role $r 没产出)"
    ctx="$ctx

[$r]:
$out"
    combined="$combined
━━ $r ━━
$out"
  done
  printf '%s' "$combined"
}

# ---------- /automem — auto-extract durable facts to memory ----------
automem_on()    { : > "$SESS_DIR/$1.automem"; }
automem_off()   { rm -f "$SESS_DIR/$1.automem"; }
automem_is_on() { [[ -f "$SESS_DIR/$1.automem" ]]; }

# automem_extract <key> <user_msg> <assistant_reply>
# Asks the model for 0..3 short factual statements worth remembering, appends to memory.
automem_extract() {
  local key="$1" user_msg="$2" reply="$3"
  automem_is_on "$key" || return 0
  local prompt; prompt=$(cat <<EOF
You are a memory extractor. Given the recent exchange below, output 0..3 short
DURABLE facts about the user (preferences, identity, ongoing projects, names).
- One fact per line, no bullets, no quotes.
- Skip ephemeral chat ("hi", "thanks"), opinions, jokes.
- If nothing worth saving, output a single line: NONE

[User]:
$user_msg

[Assistant reply]:
$reply
EOF
)
  local extracted
  extracted=$("$QODER_BIN" -p "$prompt" -m "$(model_for_key "$key")" \
              --cwd "$WORK_ROOT/$key" --permission-mode bypass_permissions \
              --max-output-tokens 200 2>>"$LOG_DIR/qoder.err")
  [[ -z "$extracted" ]] && return 0
  local added=0
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == "NONE" ]] && continue
    [[ ${#line} -lt 4 || ${#line} -gt 200 ]] && continue
    memory_add "$key" "$line"
    added=$((added+1))
  done <<<"$extracted"
  (( added > 0 )) && log "AUTOMEM key=$key +$added facts"
}
