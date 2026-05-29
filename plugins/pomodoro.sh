# plugins/pomodoro.sh — /pomodoro <分钟> [备注]
# 简单番茄钟。用 bot.sh 现有的 cron 系统 (at-style one-shot) 或 sleep 后台任务。
# 这里走最朴素方案：fork 一个 sleep + reply_text。

_POMO_DIR() { echo "${BOT_HOME:-./state}/pomodoro"; }

plugin_pomodoro() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}"
  case "$sub" in
    ""|list|ls)
      local d; d=$(_POMO_DIR); mkdir -p "$d"
      local n=0 out="🍅 当前番茄钟："
      local f
      for f in "$d"/*.pid; do
        [[ -f "$f" ]] || continue
        local pid; pid=$(cat "$f" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
          n=$((n+1))
          local meta="${f%.pid}.meta"
          out+="
  [$n] PID=${pid}  $(cat "$meta" 2>/dev/null)"
        else
          rm -f "$f" "${f%.pid}.meta"
        fi
      done
      (( n == 0 )) && out+="
  （无）
用法：/pomodoro <分钟> [备注]   /pomodoro cancel <PID>"
      reply_text "$to" "$out"
      ;;
    cancel|stop|kill)
      local pid="${rest#* }"
      if [[ -z "$pid" || "$pid" == "$sub" || ! "$pid" =~ ^[0-9]+$ ]]; then
        reply_text "$to" "用法：/pomodoro cancel <PID>"; return 0
      fi
      if kill "$pid" 2>/dev/null; then
        reply_text "$to" "✅ 已取消番茄钟 PID=${pid}"
        rm -f "$(_POMO_DIR)/${pid}".pid "$(_POMO_DIR)/${pid}".meta
      else
        reply_text "$to" "❌ PID=${pid} 不存在或不属于你"
      fi
      ;;
    *)
      # /pomodoro <minutes> [note...]
      local mins="$sub"
      local note=""
      [[ "$rest" != "$sub" ]] && note="${rest#* }"
      if ! [[ "$mins" =~ ^[0-9]+$ ]]; then
        reply_text "$to" "用法：/pomodoro <分钟> [备注]
例：/pomodoro 25 写需求文档
查看：/pomodoro list   取消：/pomodoro cancel <PID>"
        return 0
      fi
      (( mins < 1 || mins > 240 )) && { reply_text "$to" "分钟数 1-240"; return 0; }
      local secs=$((mins*60))
      local d; d=$(_POMO_DIR); mkdir -p "$d"
      local end_h; end_h=$(date -v +"${mins}M" '+%H:%M' 2>/dev/null || date -d "+${mins} minutes" '+%H:%M' 2>/dev/null)
      # 后台等待 + 回 reply_text。需要 BOT_HOME / SCRIPT_DIR 都已 exported。
      (
        sleep "$secs"
        local msg="🍅⏰ 番茄钟结束（${mins} 分钟）"
        [[ -n "$note" ]] && msg+="：${note}"
        reply_text "$to" "$msg" 2>/dev/null || true
        rm -f "${d}/$$.pid" "${d}/$$.meta"
      ) &
      local pid=$!
      echo "$pid" > "${d}/${pid}.pid"
      printf '%s\n' "${mins}m  end~${end_h}  note=${note}" > "${d}/${pid}.meta"
      reply_text "$to" "🍅 番茄钟开始：${mins} 分钟  → ${end_h:-+${mins}m}
PID=${pid}   取消：/pomodoro cancel ${pid}"
      ;;
  esac
}

register_command "/pomodoro" plugin_pomodoro "番茄钟：/pomodoro <分钟> [备注] | list | cancel <PID>"
