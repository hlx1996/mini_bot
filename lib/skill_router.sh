#!/usr/bin/env bash
# lib/skill_router.sh — keyword → skill routing.
# Mirrors lib/router.sh (model routing) but switches the SYSTEM PROMPT
# to a skill body for the matched message only. Per-chat + global lists.
#
# File format: one rule per line, TAB-separated:
#   <regex><TAB><skill-name>
# First match wins. Per-chat list is checked first, then global.
#
# Used by build_system_prompt: if G_SKILL_OVERRIDE is non-empty, treat that
# skill name as the active soul for this turn only (does NOT mutate the
# stuck soul).

_skill_routes_file_chat()   { printf '%s' "$SESS_DIR/$1.skill_routes"; }
_skill_routes_file_global() { printf '%s' "$BOT_HOME/skill_routes.tsv"; }

skill_routes_list() {
  local key="$1" f1 f2
  f1=$(_skill_routes_file_chat "$key"); f2=$(_skill_routes_file_global)
  local n=0
  if [[ -s "$f1" ]]; then
    echo "[本会话]"
    while IFS=$'\t' read -r rx sk; do
      n=$((n+1)); printf '  %d. %s → %s\n' "$n" "$rx" "$sk"
    done <"$f1"
  fi
  if [[ -s "$f2" ]]; then
    echo "[全局]"
    while IFS=$'\t' read -r rx sk; do
      n=$((n+1)); printf '  %d. %s → %s\n' "$n" "$rx" "$sk"
    done <"$f2"
  fi
  (( n == 0 )) && echo "(还没有规则。/skill route add <regex> <skill> [global])"
}

skill_routes_add() {
  local key="$1" regex="$2" skill="$3" scope="${4:-chat}"
  local f
  [[ "$scope" == "global" ]] && f=$(_skill_routes_file_global) || f=$(_skill_routes_file_chat "$key")
  mkdir -p "$(dirname "$f")"
  printf '%s\t%s\n' "$regex" "$skill" >>"$f"
}

skill_routes_rm() {
  local key="$1" idx="$2"
  local f1 f2 n=0 tmp matched_file=""
  f1=$(_skill_routes_file_chat "$key"); f2=$(_skill_routes_file_global)
  for f in "$f1" "$f2"; do
    [[ -s "$f" ]] || continue
    local lines; lines=$(wc -l <"$f" | tr -d ' ')
    if (( idx > n && idx <= n + lines )); then
      local local_idx=$((idx - n))
      tmp=$(mktemp); awk -v k="$local_idx" 'NR!=k' "$f" >"$tmp"; mv "$tmp" "$f"
      matched_file="$f"; break
    fi
    n=$((n + lines))
  done
  [[ -n "$matched_file" ]]
}

skill_routes_clear() {
  local key="$1" scope="${2:-chat}"
  if [[ "$scope" == "global" ]]; then rm -f "$(_skill_routes_file_global)"
  elif [[ "$scope" == "all" ]]; then rm -f "$(_skill_routes_file_chat "$key")" "$(_skill_routes_file_global)"
  else rm -f "$(_skill_routes_file_chat "$key")"
  fi
}

# Return the skill name that matches $text in $key, or empty.
skill_route_for_text() {
  local key="$1" text="$2"
  local f
  for f in "$(_skill_routes_file_chat "$key")" "$(_skill_routes_file_global)"; do
    [[ -s "$f" ]] || continue
    while IFS=$'\t' read -r rx sk; do
      [[ -z "$rx" || -z "$sk" ]] && continue
      if printf '%s' "$text" | grep -Eq -- "$rx"; then
        printf '%s' "$sk"; return 0
      fi
    done <"$f"
  done
  return 1
}
