#!/usr/bin/env bash
# plugins/digest.sh — daily / on-demand chat-log summary
#
# Reads $EVENT_LOG (state/logs/events.jsonl) for events whose key matches the
# current chat, filters to "today" (or N hours back), then asks the current
# model to summarize.
#
# Usage:
#   /digest                        — list current digests (cron lines) for this chat
#   /digest now [hours]            — summarize last N hours immediately (default 24)
#   /digest add "<cron-expr>"      — schedule daily; expands to /digest now 24
#   /digest rm <cron-id>           — remove a scheduled digest
#
# The scheduled form just adds a regular /cron line whose prompt is
# "/digest now 24" — when cron fires, cron_fire dispatches it through
# handle_command, which lands back here via the plugin loader.

_digest_collect() {
  # _digest_collect <key> <hours>  → echoes "<author>: <text>" lines, oldest first
  local key="$1" hours="${2:-24}"
  local t0; t0=$(date -v-"${hours}"H +%s 2>/dev/null || date -d "-${hours} hours" +%s)
  [[ -f "$EVENT_LOG" ]] || return 0
  # Resolve key → (platform, account_name, from) via sidecars dropped by
  # handle_event. Much simpler and faster than recomputing shasum per row.
  local sc="$SESS_DIR/$key"
  local plat acct from
  plat=$(cat "${sc}.platform" 2>/dev/null) || plat=""
  acct=$(cat "${sc}.account"  2>/dev/null) || acct=""
  from=$(cat "${sc}.from"     2>/dev/null) || from=""
  [[ -z "$plat" || -z "$from" ]] && return 0
  jq -r --argjson t0 "$t0" --arg plat "$plat" --arg acct "$acct" --arg from "$from" '
    select((.ts // 0) >= $t0)
    | select(.kind=="event")
    | select((.platform // "") == $plat)
    | select((.account_name // .account_id // "default") == $acct)
    | select((.from // "") == $from)
    | "\(.from_name // .from // "?"): \(.text // "(media)")"
  ' "$EVENT_LOG" 2>/dev/null
}

plugin_digest() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}"; local args=""
  [[ "$rest" != "$sub" ]] && args="${rest#* }"

  case "$sub" in
    ""|list)
      local raw
      raw=$(crontab -l 2>/dev/null | grep -F "# wxcron:${key}:" | grep -F "/digest now" || true)
      if [[ -z "$raw" ]]; then
        reply_text "$to" "📋 本会话暂无定时摘要。

用法：
  /digest now [小时数]          立即总结最近 N 小时（默认 24）
  /digest add \"0 9 * * *\"       每天早上 9 点自动总结（cron 表达式）
  /digest rm <id>               删除（id 从 /digest list 拿）"
      else
        local out
        out=$(printf '%s\n' "$raw" | awk '
          {
            id=""; for(i=NF;i>=1;i--) if($i ~ /^wxcron:/){ split($i,p,":"); id=p[3]; break }
            expr=$1" "$2" "$3" "$4" "$5
            printf "  [%s] %s\n", id, expr
          }')
        reply_text "$to" "📋 已排定的摘要：
$out

/digest rm <id> 删除；/digest now 立即跑一次"
      fi
      return 0 ;;

    now)
      local hours="${args:-24}"
      [[ "$hours" =~ ^[0-9]+$ ]] || hours=24
      reply_text "$to" "📝 正在汇总最近 ${hours}h 的聊天…"
      local raw_lines line_count
      raw_lines=$(_digest_collect "$key" "$hours")
      line_count=$(printf '%s' "$raw_lines" | grep -c . || true)
      if (( line_count == 0 )); then
        reply_text "$to" "（最近 ${hours}h 这个会话没有可摘要的消息）"
        return 0
      fi
      # Cap to last ~400 lines to keep prompt manageable
      local clipped; clipped=$(printf '%s\n' "$raw_lines" | tail -n 400)
      local prompt="请用中文为下面的聊天日志写一份简明摘要（按主题分块；每块 1-3 句；最后列出 3-5 条「待办 / 跟进」）。仅基于日志内容，不要编造。

[聊天日志，约 ${line_count} 条，时间范围：最近 ${hours} 小时]
${clipped}"
      local workspace model ans
      workspace=$(cwd_resolve_workspace "$key" "$WORK_ROOT/$key"); mkdir -p "$workspace"
      model=$(model_for_key "$key")
      ans=$(run_qoder_agent "$prompt" "$key" "$workspace" "$model" 2>/dev/null) || ans=""
      [[ -z "$ans" ]] && ans="(摘要生成失败，看 logs/qoder.err)"
      reply_text "$to" "📰 最近 ${hours}h 摘要（$line_count 条消息）：

$ans"
      return 0 ;;

    add)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/digest add \"<cron 表达式>\"  例：/digest add \"0 9 * * *\""; return 0; }
      local expr="$args"
      # Strip leading/trailing quotes if user wrapped them
      expr="${expr#\"}"; expr="${expr%\"}"
      expr="${expr#\'}"; expr="${expr%\'}"
      if ! command -v add_cron_for_key >/dev/null 2>&1; then
        reply_text "$to" "❌ cron 子系统未初始化"; return 0
      fi
      local tag; tag=$(add_cron_for_key "$key" "$expr" "/digest now 24" "$to")
      reply_text "$to" "✅ 已排定每次按 [$expr] 自动总结过去 24h。tag=$tag"
      return 0 ;;

    rm|del|delete)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/digest rm <id>"; return 0; }
      if rm_cron_by_tag "$args"; then
        reply_text "$to" "🗑️  已删除：$args"
      else
        reply_text "$to" "❌ 没找到这个 id（/digest list 看看？）"
      fi
      return 0 ;;

    *)
      reply_text "$to" "未知子命令：${sub}。用法：/digest [list|now [hours]|add \"<cron>\"|rm <id>]"
      return 0 ;;
  esac
}

register_command "/digest" plugin_digest "聊天摘要：/digest now [小时] | add <cron> | rm <id>"
