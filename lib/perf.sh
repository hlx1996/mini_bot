# lib/perf.sh — performance / cost-shaping helpers.
#
# Centralizes the optimization machinery (lazy MCP detection, injected-context
# capping, short-message reply cache, long-session auto-compress). Sourced by
# bot.sh; depends on globals: BOT_HOME, MCP_CONFIG, SESS_DIR, LOG_DIR,
# QODER_BIN, and the helpers reset_session / memory_add / get_session_uuid /
# log defined in bot.sh. All toggles are env-var-driven; defaults are
# conservative.

# ---------- model-tier gating ------------------------------------------------
# The optimizations below are most valuable on the expensive 'ultimate' tier;
# on cheaper / faster tiers we'd rather pay a few cents more for a noticeably
# better answer. _is_thrifty_model echoes 1 when we should save tokens and 0
# when we should let the model do its best work.
#
# BOT_THRIFTY_MODELS: space-separated list of model names that trigger thrifty
#   mode (default: "ultimate"). Match is substring + case-insensitive so e.g.
#   "ultimate-50" also counts.
# BOT_THRIFTY=force / BOT_THRIFTY=off: hard override regardless of model.

_is_thrifty_model() {
  local m="${1:-}"
  case "${BOT_THRIFTY:-auto}" in
    force|on|1) echo 1; return ;;
    off|0)      echo 0; return ;;
  esac
  [[ -z "$m" ]] && { echo 0; return; }
  local lm; lm=$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')
  local pat
  for pat in ${BOT_THRIFTY_MODELS:-ultimate}; do
    [[ "$lm" == *"$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')"* ]] && { echo 1; return; }
  done
  echo 0
}

# ---------- lazy MCP detection (B2) -----------------------------------------

# Cached, newline-joined list of MCP server names (rebuilt only when mcp.json changes).
_mcp_server_names() {
  [[ -f "$MCP_CONFIG" ]] || { echo ""; return; }
  local cache="$BOT_HOME/.cache/mcp.names"
  local stamp="$BOT_HOME/.cache/mcp.mtime"
  mkdir -p "$BOT_HOME/.cache" 2>/dev/null
  local mt; mt=$(stat -f %m "$MCP_CONFIG" 2>/dev/null || stat -c %Y "$MCP_CONFIG" 2>/dev/null || echo 0)
  if [[ -f "$cache" && -f "$stamp" ]] && [[ "$(cat "$stamp" 2>/dev/null)" == "$mt" ]]; then
    cat "$cache"; return
  fi
  jq -r '.mcpServers // {} | keys[]' "$MCP_CONFIG" 2>/dev/null > "$cache"
  printf '%s' "$mt" > "$stamp"
  cat "$cache"
}

# _prompt_wants_mcp <prompt> — returns 0 if the prompt looks like it needs an
# MCP-backed tool (mentions a server name, or contains a generic capability
# keyword such as "browser", "fs", "filesystem", "github", "fetch", "shell").
# Disable lazy MCP entirely with BOT_MCP_LAZY=0 (always attach when mcp.json
# exists).
_prompt_wants_mcp() {
  [[ "${BOT_MCP_LAZY:-1}" != "1" ]] && return 0
  [[ -f "$MCP_CONFIG" ]] || return 1
  local p="$1" lt names n
  lt=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  if [[ "$lt" =~ (mcp|browser|browse|playwright|filesystem|fs|文件系统|github|gitlab|fetch|抓取|shell|terminal|命令行|database|sql) ]]; then
    return 0
  fi
  names=$(_mcp_server_names)
  [[ -z "$names" ]] && return 1
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    local nl; nl=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')
    [[ "$lt" == *"$nl"* ]] && return 0
  done <<<"$names"
  return 1
}

# ---------- injected-context cap (B3) ---------------------------------------
# Hard cap on the total non-conversation context (RAG + pin + URL + hooks)
# stitched onto a single turn. Default 4000 chars (~1100 tokens). Override
# via BOT_INJECT_MAX.

_inject_cap()      { echo "${BOT_INJECT_MAX:-4000}"; }
_inject_remaining(){ local used="${1:-0}"; local cap; cap=$(_inject_cap); local r=$((cap-used)); (( r<0 )) && r=0; echo "$r"; }
_inject_clip() {
  # _inject_clip <text> <max-chars> — emit at most max chars; clipped chunks
  # are tagged with a trailing marker so the model knows it didn't see the rest.
  local txt="$1" max="$2"
  (( ${#txt} <= max )) && { printf '%s' "$txt"; return; }
  printf '%s…[clipped]' "${txt:0:max}"
}

# ---------- short-message response cache (B4) -------------------------------
# Caches model replies for trivial repeated messages. Saves an entire LLM
# round-trip when the same chat sends the same short text within TTL.
# Disable with BOT_REPLY_CACHE=0. Tune TTL via BOT_REPLY_CACHE_TTL (seconds).

_reply_cache_dir() { local d="$BOT_HOME/.cache/replies"; mkdir -p "$d" 2>/dev/null; echo "$d"; }

# Hash-based key. Includes soul + model + skill override so persona changes
# don't collide across cached entries.
_reply_cache_key() {
  local key="$1" text="$2" soul="$3" model="$4"
  local override="${G_SKILL_OVERRIDE:-}"
  printf '%s|%s|%s|%s|%s' "$soul" "$model" "$override" "$key" "$text" \
    | shasum 2>/dev/null | awk '{print $1}'
}

# Returns 0 if this turn is eligible for response caching.
# $1=text, $2=chat_type (direct|group), $3=#attachments
_reply_cache_eligible() {
  [[ "${BOT_REPLY_CACHE:-1}" == "1" ]] || return 1
  local text="$1" ctype="${2:-direct}" natt="${3:-0}"
  [[ "$ctype" == "group" ]] && return 1
  (( natt > 0 )) && return 1
  [[ -z "$text" ]] && return 1
  [[ "$text" == /* ]] && return 1
  [[ "$text" == *$'\n'* ]] && return 1
  (( ${#text} > ${BOT_REPLY_CACHE_MAXLEN:-30} )) && return 1
  # Time-sensitive / live-data — never cache.
  local lt; lt=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  if [[ "$lt" =~ (现在|今天|今晚|刚才|最新|最近|实时|此刻|now|today|tonight|latest|current|天气|股价|股票|价格|汇率|新闻|headlines|温度|气温|时间|几点|date|time|weather|news|price|stock|bitcoin|btc|eth|tomorrow|明天|后天) ]]; then
    return 1
  fi
  return 0
}

# Get cached reply if fresh; echoes reply on stdout. Returns 1 if miss/expired.
_reply_cache_get() {
  local h="$1" ttl="${BOT_REPLY_CACHE_TTL:-3600}"
  [[ -n "$h" ]] || return 1
  local f; f="$(_reply_cache_dir)/$h"
  [[ -f "$f" ]] || return 1
  local now mt age
  now=$(date +%s)
  mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  age=$((now - mt))
  if (( age > ttl )); then
    rm -f "$f" 2>/dev/null
    return 1
  fi
  cat "$f"
}

_reply_cache_put() {
  local h="$1" reply="$2"
  [[ -n "$h" && -n "$reply" ]] || return 0
  local f; f="$(_reply_cache_dir)/$h"
  printf '%s' "$reply" > "$f" 2>/dev/null || true
}

# ---------- session auto-compress (C) ---------------------------------------
# Tracks running char-count of conversation per session. When it crosses
# BOT_COMPRESS_AT (default 120000 chars ≈ ~34k tokens), summarize the session
# in the background, append the summary to chat memory, and reset the session.
# The next turn starts fresh with the summary visible via build_system_prompt.

_session_chars_path() { echo "$SESS_DIR/$1.chars"; }

# _session_chars_bump <key> <delta>  → echoes new total
_session_chars_bump() {
  local key="$1" delta="$2" f cur new
  f=$(_session_chars_path "$key")
  cur=0; [[ -s "$f" ]] && cur=$(cat "$f" 2>/dev/null || echo 0)
  new=$((cur + delta))
  printf '%s' "$new" > "$f" 2>/dev/null || true
  printf '%s' "$new"
}

_session_chars_reset() { : > "$(_session_chars_path "$1")" 2>/dev/null || true; }

# Background: ask qoder to summarize the resumed session, append to memory,
# then reset_session so the next turn doesn't re-ship full history.
_session_compress() {
  local key="$1" model="$2" workspace="$3"
  local uuid; uuid=$(get_session_uuid "$key")
  uuid="${uuid//[$'\n\r\t ']/}"
  [[ -z "$uuid" ]] && return 0
  [[ -f "$SESS_DIR/$key.started" ]] || return 0
  local prompt='Summarize this conversation so far in 5-8 short bullet points covering: durable user preferences, ongoing tasks/projects, and any decisions already made. No greeting, no closing, just the bullets.'
  local summary
  summary=$("$QODER_BIN" -p "$prompt" -m "$model" --cwd "$workspace" \
            --permission-mode bypass_permissions \
            --reasoning-effort low --max-output-tokens 400 \
            --resume "$uuid" 2>>"$LOG_DIR/qoder.err")
  summary="${summary//$'\r'/}"
  [[ -z "$summary" ]] && { log "AUTO-COMPRESS key=$key — empty summary, skip"; return 0; }
  memory_add "$key" "[session_summary $(date +%F)] $summary"
  reset_session "$key"
  _session_chars_reset "$key"
  log "AUTO-COMPRESS key=$key — summarized & reset (summary ${#summary} chars)"
}

# ---------- model-select interceptor ------------------------------------------
# Always-available helpers for the /model select interactive flow. The state file
# is written by plugin_model (plugins/core.sh); the intercept must be available
# in every forked handler without waiting for lazy-load.

_model_select_state() { echo "$SESS_DIR/$1.model_select"; }

_model_select_pending() {
  local key="$1"
  [[ -f "$(_model_select_state "$key")" ]]
}

_model_select_catalog() {
  cat <<'CATALOG'
1|lite|Lite|1x
2|efficient|Efficient|1x
3|auto|Auto|2x
4|dfmodel|DeepSeek-V4-Flash|2x
5|dmodel|DeepSeek-V4-Pro|3x
6|gmodel|GLM-5|3x
7|gm51model|GLM-5.1|3x
8|kmodel|Kimi-K2.6|3x
9|mmodel|MiniMax-M2.7|3x
10|q35model|Qwen3.5-Plus|3x
11|qmodel|Qwen3.6-Plus|5x
12|qmodel_latest|Qwen3.7-Max|5x
13|performance|Performance|5x
14|ultimate|Ultimate|10x
CATALOG
}

_model_select_handle() {
  local to="$1" key="$2" text="$3"
  local sf; sf=$(_model_select_state "$key")
  [[ -f "$sf" ]] || return 1
  rm -f "$sf"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  if ! [[ "$text" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  local n="$text"
  local line; line=$(_model_select_catalog | sed -n "${n}p")
  if [[ -z "$line" ]]; then
    reply_text "$to" "❌ Out of range (1-14)"
    return 0
  fi
  local model_id; model_id=$(printf '%s' "$line" | cut -d'|' -f2)
  set_model_for_key "$key" "$model_id"
  local model_label; model_label=$(printf '%s' "$line" | cut -d'|' -f3)
  local model_cost; model_cost=$(printf '%s' "$line" | cut -d'|' -f4)
  reply_text "$to" "✅ 已切换模型为：${model_label} (${model_id}) [${model_cost} credit]"
  return 0
}
