# plugins/timer.sh — /timer <时间> [备注]
# 比 /pomodoro 更通用，支持 60s / 5m / 2h / HH:MM 格式。
# 数据：$BOT_HOME/timer/<PID>.{pid,meta}

_TIMER_DIR() { echo "${BOT_HOME:-./state}/timer"; }

_timer_parse_secs() {
  # 输出 seconds，失败输出 0
  local x="$1"
  case "$x" in
    *s|*S) echo $((${x%[sS]})) ;;
    *m|*M) echo $((${x%[mM]}*60)) ;;
    *h|*H) echo $((${x%[hH]}*3600)) ;;
    [0-9]*:[0-9]*)
      # HH:MM → 算到今天/明天的那个时刻
      python3 -c "
import sys, datetime
h, m = sys.argv[1].split(':')
now = datetime.datetime.now()
tgt = now.replace(hour=int(h), minute=int(m), second=0, microsecond=0)
if tgt <= now: tgt += datetime.timedelta(days=1)
print(int((tgt-now).total_seconds()))
" "$x" ;;
    [0-9]*) echo "$x" ;;
    *) echo 0 ;;
  esac
}

plugin_timer() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}"
  case "$sub" in
    ""|list|ls)
      local d; d=$(_TIMER_DIR); mkdir -p "$d"
      local n=0 out="⏰ 当前 timer："
      local f
      for f in "$d"/*.pid; do
        [[ -f "$f" ]] || continue
        local pid; pid=$(cat "$f" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
          n=$((n+1))
          out+="
  [$n] PID=${pid}  $(cat "${f%.pid}.meta" 2>/dev/null)"
        else
          rm -f "$f" "${f%.pid}.meta"
        fi
      done
      (( n == 0 )) && out+="
  （无）
用法：/timer 90s 烧水
      /timer 5m  开会
      /timer 22:30 早睡提醒
查看：/timer list   取消：/timer cancel <PID>"
      reply_text "$to" "$out"
      ;;
    cancel|stop|kill)
      local pid="${rest#* }"
      [[ -z "$pid" || "$pid" == "$sub" || ! "$pid" =~ ^[0-9]+$ ]] && { reply_text "$to" "用法：/timer cancel <PID>"; return 0; }
      if kill "$pid" 2>/dev/null; then
        reply_text "$to" "✅ 已取消 timer PID=${pid}"
        rm -f "$(_TIMER_DIR)/${pid}".pid "$(_TIMER_DIR)/${pid}".meta
      else
        reply_text "$to" "❌ PID=${pid} 不存在"
      fi
      ;;
    *)
      local spec="$sub" note=""
      [[ "$rest" != "$sub" ]] && note="${rest#* }"
      local secs; secs=$(_timer_parse_secs "$spec")
      if [[ ! "$secs" =~ ^[0-9]+$ ]] || (( secs < 1 )); then
        reply_text "$to" "❌ 时间格式无效: '${spec}'
支持：90s / 5m / 2h / 22:30 / 纯数字(秒)"
        return 0
      fi
      (( secs > 24*3600 )) && { reply_text "$to" "❌ 太长（>24h）"; return 0; }
      local d; d=$(_TIMER_DIR); mkdir -p "$d"
      local end; end=$(date -v +"${secs}S" '+%H:%M:%S' 2>/dev/null || date -d "+${secs} seconds" '+%H:%M:%S' 2>/dev/null)
      (
        sleep "$secs"
        local msg="⏰ 时间到（${spec}）"
        [[ -n "$note" ]] && msg+="：${note}"
        reply_text "$to" "$msg" 2>/dev/null || true
        rm -f "${d}/$$.pid" "${d}/$$.meta"
      ) &
      local pid=$!
      echo "$pid" > "${d}/${pid}.pid"
      printf '%s\n' "${spec}  end~${end}  note=${note}" > "${d}/${pid}.meta"
      reply_text "$to" "⏰ Timer 启动：${spec}  →  ${end:-+${secs}s}
PID=${pid}   取消：/timer cancel ${pid}"
      ;;
  esac
}

register_command "/timer" plugin_timer "通用 timer：/timer <90s|5m|2h|22:30> [备注]"
