#!/usr/bin/env bash
# lib/plugins.sh — drop-in plugin loader (bash 3.2-compatible — no assoc arrays).
#
# Each plugin lives in $PLUGINS_DIR (default: $SCRIPT_DIR/plugins) and is just
# a bash file that calls:
#
#   register_command "/foo" handler_func "短帮助行（出现在 /help 末尾）"
#
# The handler is invoked as:  handler_func "$to" "$key" "$rest"
# Return 0 if the plugin "ate" the message; non-zero falls through.
#
# Plugins inherit the bot's full shell — all helpers (reply_text, run_qoder_agent,
# memory_*, contact_*, bridge_*, ...) are in scope. Keep them small.

PLUGINS_DIR="${PLUGINS_DIR:-$SCRIPT_DIR/plugins}"

# Parallel indexed arrays (bash 3.2 has no associative arrays).
_PLUGIN_CMDS=()
_PLUGIN_FNS=()
_PLUGIN_HELPS=()

register_command() {
  local cmd="$1" fn="$2" help="${3:-}"
  if [[ -z "$cmd" || -z "$fn" ]]; then
    echo "register_command: usage /cmd handler [help]" >&2; return 1
  fi
  _PLUGIN_CMDS+=( "$cmd" )
  _PLUGIN_FNS+=( "$fn" )
  _PLUGIN_HELPS+=( "$help" )
}

_plugin_lookup() {
  # _plugin_lookup <cmd>  → echoes index, returns 1 if not found
  local target="$1" i
  for ((i=0; i<${#_PLUGIN_CMDS[@]}; i++)); do
    if [[ "${_PLUGIN_CMDS[$i]}" == "$target" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

plugins_load() {
  [[ -d "$PLUGINS_DIR" ]] || return 0
  local f
  for f in "$PLUGINS_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    if ! source "$f"; then
      command -v log >/dev/null 2>&1 && log "plugin load FAIL: $f" || echo "plugin load FAIL: $f" >&2
    fi
  done
}

plugin_dispatch() {
  # plugin_dispatch <to> <key> <text>  — returns 0 if a plugin handled it
  local to="$1" key="$2" text="$3"
  local cmd="${text%% *}" rest=""
  [[ "$text" != "$cmd" ]] && rest="${text#* }"
  local idx; idx=$(_plugin_lookup "$cmd") || return 1
  "${_PLUGIN_FNS[$idx]}" "$to" "$key" "$rest"
}

plugin_help() {
  # Pretty list for /help
  ((${#_PLUGIN_CMDS[@]}==0)) && return 0
  echo "— Plugins —"
  local i pairs
  pairs=$(for ((i=0; i<${#_PLUGIN_CMDS[@]}; i++)); do
    printf '%s\t%s\n' "${_PLUGIN_CMDS[$i]}" "${_PLUGIN_HELPS[$i]}"
  done | sort -u)
  printf '%s\n' "$pairs" | awk -F'\t' '{printf "  %-28s %s\n", $1, $2}'
}

