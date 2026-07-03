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
# Plugins inherit the bot's full shell — all helpers (reply_text, run_agent,
# run_qoder_agent, run_opencode_agent, memory_*, contact_*, bridge_*, ...) are in scope. Prefer run_agent over run_qoder_agent so the current /model is honored. Keep them small.
#
# LAZY LOADING (D): instead of sourcing every plugin file at startup, we pre-scan
# the files for their `register_command "..."` lines and cache that to a manifest
# (state/.cache/plugins.manifest, keyed by directory mtimes). At runtime each
# plugin file is sourced only on its first dispatch. This keeps startup fast and
# lets us keep adding plugins without paying their parse cost. Disable with
# BOT_PLUGIN_LAZY=0 (or via existing PLUGINS_DISABLE_LAZY=1).

PLUGINS_DIR="${PLUGINS_DIR:-$SCRIPT_DIR/plugins}"
PLUGINS_EXTRA_DIR="${PLUGINS_EXTRA_DIR:-$SCRIPT_DIR/plugins-extra}"

# Parallel indexed arrays (bash 3.2 has no associative arrays).
_PLUGIN_CMDS=()
_PLUGIN_FNS=()
_PLUGIN_HELPS=()
_PLUGIN_FILES=()  # source path; "" means "already loaded" / runtime-registered

register_command() {
  local cmd="$1" fn="$2" help="${3:-}"
  if [[ -z "$cmd" || -z "$fn" ]]; then
    echo "register_command: usage /cmd handler [help]" >&2; return 1
  fi
  _PLUGIN_CMDS+=( "$cmd" )
  _PLUGIN_FNS+=( "$fn" )
  _PLUGIN_HELPS+=( "$help" )
  _PLUGIN_FILES+=( "" )   # registered at runtime — already in scope
}

# _register_lazy <cmd> <fn> <help> <file>  — internal, used by manifest replay.
_register_lazy() {
  _PLUGIN_CMDS+=( "$1" )
  _PLUGIN_FNS+=( "$2" )
  _PLUGIN_HELPS+=( "$3" )
  _PLUGIN_FILES+=( "$4" )
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

# _scan_one_plugin <file>  — emits TAB-separated rows: cmd \t fn \t help \t file
# Reads `register_command "<cmd>" <fn> "<help>"` lines without sourcing the file.
_scan_one_plugin() {
  local f="$1"
  awk -v F="$f" '
    /^[[:space:]]*register_command[[:space:]]+/ {
      # Strip leading "register_command " and trailing comment.
      sub(/^[[:space:]]*register_command[[:space:]]+/, "")
      sub(/#.*$/, "")
      # Trim trailing whitespace.
      sub(/[[:space:]]+$/, "")

      cmd=""; fn=""; help=""; rest=$0
      # cmd: quoted or bareword
      if (match(rest, /^"[^"]*"/)) {
        cmd=substr(rest, RSTART+1, RLENGTH-2); rest=substr(rest, RSTART+RLENGTH)
      } else if (match(rest, /^[^[:space:]]+/)) {
        cmd=substr(rest, RSTART, RLENGTH); rest=substr(rest, RSTART+RLENGTH)
      } else next
      sub(/^[[:space:]]+/, "", rest)
      # fn: bareword
      if (match(rest, /^[A-Za-z_][A-Za-z_0-9]*/)) {
        fn=substr(rest, RSTART, RLENGTH); rest=substr(rest, RSTART+RLENGTH)
      } else next
      sub(/^[[:space:]]+/, "", rest)
      # help (optional): quoted or rest of line
      if (match(rest, /^"[^"]*"/)) {
        help=substr(rest, RSTART+1, RLENGTH-2)
      } else if (match(rest, /^'\''[^'\'']*'\''/)) {
        help=substr(rest, RSTART+1, RLENGTH-2)
      } else {
        help=rest
      }
      gsub(/\t/, " ", help)
      printf "%s\t%s\t%s\t%s\n", cmd, fn, help, F
    }
  ' "$f" 2>/dev/null
}

# _plugins_dir_stamp <dir>  — newline-joined "name<TAB>mtime" used as cache key.
_plugins_dir_stamp() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo ""; return; }
  local f
  for f in "$dir"/*.sh; do
    [[ -f "$f" ]] || continue
    local mt; mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    printf '%s\t%s\n' "$(basename "$f")" "$mt"
  done
}

_plugins_build_manifest() {
  # Emits TAB-separated rows for every plugin file we should expose (respecting
  # disabled / extra-enabled lists).  Rows: cmd \t fn \t help \t file
  local disabled_file="${BOT_HOME:-${STATE_DIR:-./state}}/plugins.disabled"
  local enabled_extra="${BOT_HOME:-${STATE_DIR:-./state}}/plugins.extra.enabled"
  local f base

  if [[ -d "$PLUGINS_DIR" ]]; then
    for f in "$PLUGINS_DIR"/*.sh; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f" .sh)
      if [[ -f "$disabled_file" ]] && LC_ALL=C grep -qx "$base" "$disabled_file" 2>/dev/null; then
        continue
      fi
      _scan_one_plugin "$f"
    done
  fi

  if [[ -d "$PLUGINS_EXTRA_DIR" ]]; then
    local all="${PLUGINS_EXTRA_ALL:-0}"
    for f in "$PLUGINS_EXTRA_DIR"/*.sh; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f" .sh)
      if [[ "$all" != "1" ]]; then
        [[ -f "$enabled_extra" ]] || continue
        LC_ALL=C grep -qx "$base" "$enabled_extra" 2>/dev/null || continue
      fi
      if [[ -f "$disabled_file" ]] && LC_ALL=C grep -qx "$base" "$disabled_file" 2>/dev/null; then
        continue
      fi
      _scan_one_plugin "$f"
    done
  fi
}

# _plugins_eager_load — original behaviour: source every plugin file at startup.
_plugins_eager_load() {
  local disabled_file="${BOT_HOME:-${STATE_DIR:-./state}}/plugins.disabled"
  local enabled_extra="${BOT_HOME:-${STATE_DIR:-./state}}/plugins.extra.enabled"
  local f base

  if [[ -d "$PLUGINS_DIR" ]]; then
    for f in "$PLUGINS_DIR"/*.sh; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f" .sh)
      if [[ -f "$disabled_file" ]] && LC_ALL=C grep -qx "$base" "$disabled_file" 2>/dev/null; then
        declare -F log >/dev/null 2>&1 && log "plugin skipped (disabled): $base" || true
        continue
      fi
      if ! source "$f"; then
        declare -F log >/dev/null 2>&1 && log "plugin load FAIL: $f" || echo "plugin load FAIL: $f" >&2
      fi
    done
  fi

  if [[ -d "$PLUGINS_EXTRA_DIR" ]]; then
    local all="${PLUGINS_EXTRA_ALL:-0}"
    for f in "$PLUGINS_EXTRA_DIR"/*.sh; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f" .sh)
      if [[ "$all" != "1" ]]; then
        [[ -f "$enabled_extra" ]] || continue
        LC_ALL=C grep -qx "$base" "$enabled_extra" 2>/dev/null || continue
      fi
      if [[ -f "$disabled_file" ]] && LC_ALL=C grep -qx "$base" "$disabled_file" 2>/dev/null; then
        continue
      fi
      if ! source "$f"; then
        declare -F log >/dev/null 2>&1 && log "plugin-extra load FAIL: $f" || echo "plugin-extra load FAIL: $f" >&2
      fi
    done
  fi
}

plugins_load() {
  if [[ "${BOT_PLUGIN_LAZY:-1}" != "1" || "${PLUGINS_DISABLE_LAZY:-0}" == "1" ]]; then
    _plugins_eager_load
    return
  fi

  local cache_dir="${BOT_HOME:-${STATE_DIR:-./state}}/.cache"
  mkdir -p "$cache_dir" 2>/dev/null
  local manifest="$cache_dir/plugins.manifest"
  local stamp_file="$cache_dir/plugins.stamp"

  local stamp_now
  stamp_now=$(printf '%s\n%s\n' \
    "$(_plugins_dir_stamp "$PLUGINS_DIR")" \
    "$(_plugins_dir_stamp "$PLUGINS_EXTRA_DIR")")

  local stamp_old=""
  [[ -f "$stamp_file" ]] && stamp_old=$(cat "$stamp_file" 2>/dev/null)
  if [[ ! -f "$manifest" || "$stamp_now" != "$stamp_old" ]]; then
    _plugins_build_manifest > "$manifest.tmp" 2>/dev/null
    mv "$manifest.tmp" "$manifest" 2>/dev/null
    printf '%s' "$stamp_now" > "$stamp_file" 2>/dev/null
    declare -F log >/dev/null 2>&1 && log "plugins: manifest rebuilt ($(wc -l < "$manifest" | tr -d ' ') rows)" || true
  fi

  local cmd fn help file
  while IFS=$'\t' read -r cmd fn help file; do
    [[ -z "$cmd" || -z "$fn" || -z "$file" ]] && continue
    _register_lazy "$cmd" "$fn" "$help" "$file"
  done < "$manifest"
}

# Reload all plugins (used by /plugins reload). Clears manifest + arrays.
plugins_reload() {
  _PLUGIN_CMDS=(); _PLUGIN_FNS=(); _PLUGIN_HELPS=(); _PLUGIN_FILES=()
  rm -f "${BOT_HOME:-${STATE_DIR:-./state}}/.cache/plugins.manifest" \
        "${BOT_HOME:-${STATE_DIR:-./state}}/.cache/plugins.stamp" 2>/dev/null
  plugins_load
}

# _ensure_plugin_loaded <idx>  — sources the plugin file if not yet loaded.
_ensure_plugin_loaded() {
  local idx="$1"
  local file="${_PLUGIN_FILES[$idx]:-}"
  [[ -z "$file" ]] && return 0   # already in scope (eager-loaded or runtime-registered)
  [[ -f "$file" ]] || return 0
  # Marker so we don't re-source: set BEFORE sourcing in case the file calls
  # back into plugins_load (paranoid).
  _PLUGIN_FILES[$idx]=""
  if ! source "$file"; then
    declare -F log >/dev/null 2>&1 && log "plugin lazy-source FAIL: $file" || echo "plugin lazy-source FAIL: $file" >&2
    return 1
  fi
}

plugin_dispatch() {
  # plugin_dispatch <to> <key> <text>  — returns 0 if a plugin handled it
  local to="$1" key="$2" text="$3"
  local cmd="${text%% *}" rest=""
  [[ "$text" != "$cmd" ]] && rest="${text#* }"

  # Per-message file-based alias resolution (so /alias works across forked workers).
  # 顺序：chat 级 → 全局
  local alias_dir="${BOT_HOME:-./state}/aliases"
  local resolved=""
  if [[ -s "${alias_dir}/${key}.tsv" ]]; then
    resolved=$(awk -F'\t' -v a="$cmd" '$1==a {print $2; exit}' "${alias_dir}/${key}.tsv" 2>/dev/null)
  fi
  if [[ -z "$resolved" && -s "${alias_dir}/_global.tsv" ]]; then
    resolved=$(awk -F'\t' -v a="$cmd" '$1==a {print $2; exit}' "${alias_dir}/_global.tsv" 2>/dev/null)
  fi
  if [[ -n "$resolved" ]]; then
    cmd="$resolved"
  fi

  local idx; idx=$(_plugin_lookup "$cmd") || return 1
  _ensure_plugin_loaded "$idx"
  # 记一笔调用：BOT_HOME/metrics/commands.tsv 行: epoch\tcmd
  local mdir="${BOT_HOME:-./state}/metrics"
  mkdir -p "$mdir" 2>/dev/null
  printf '%s\t%s\n' "$(date +%s)" "$cmd" >> "$mdir/commands.tsv" 2>/dev/null || true
  "${_PLUGIN_FNS[$idx]}" "$to" "$key" "$rest"
}

plugin_help() {
  # Pretty list for /help — ASCII command names only (drop CJK aliases).
  ((${#_PLUGIN_CMDS[@]}==0)) && return 0
  echo "— Plugins —"
  local i pairs
  pairs=$(for ((i=0; i<${#_PLUGIN_CMDS[@]}; i++)); do
    # skip CJK / non-ASCII command names (alias rows)
    if printf '%s' "${_PLUGIN_CMDS[$i]}" | LC_ALL=C grep -q '[^[:print:]]\|[^ -~]'; then
      continue
    fi
    printf '%s\t%s\n' "${_PLUGIN_CMDS[$i]}" "${_PLUGIN_HELPS[$i]}"
  done | sort -u)
  printf '%s\n' "$pairs" | awk -F'\t' '{printf "  %-28s %s\n", $1, $2}'
}
