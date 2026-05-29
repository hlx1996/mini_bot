# plugins/calendar.sh — /calendar 日历提醒
# 数据：$BOT_HOME/calendar/<key>.tsv  行: id\tepoch\twhen_str\tevent
# 后台 watcher：每 60s 扫一次，到点就 reply_text 并删除该行。
# /calendar add <YYYY-MM-DD HH:MM> <event>
# /calendar list
# /calendar rm <id>
# /calendar clear

_CAL_FILE() { echo "${BOT_HOME:-./state}/calendar/${1}.tsv"; }
_CAL_DIR()  { echo "${BOT_HOME:-./state}/calendar"; }

_cal_watcher_start() {
  local d; d=$(_CAL_DIR); mkdir -p "$d"
  local pidf="${d}/.watcher.pid"
  if [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi
  (
    while true; do
      local now; now=$(date +%s)
      local f
      for f in "$d"/*.tsv; do
        [[ -f "$f" ]] || continue
        local chat; chat=$(basename "$f" .tsv)
        local tmp="${f}.tmp"; : > "$tmp"
        local line
        while IFS=$'\t' read -r id epoch when ev; do
          [[ -z "$id" ]] && continue
          if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch <= now )); then
            reply_text "$chat" "📅 日程提醒：${when}
${ev}" 2>/dev/null || true
          else
            printf '%s\t%s\t%s\t%s\n' "$id" "$epoch" "$when" "$ev" >> "$tmp"
          fi
        done < "$f"
        mv "$tmp" "$f"
      done
      sleep 60
    done
  ) >/dev/null 2>&1 &
  echo $! > "$pidf"
}

plugin_calendar() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  local f; f=$(_CAL_FILE "$key"); mkdir -p "$(dirname "$f")"; touch "$f"

  _cal_watcher_start

  case "$sub" in
    ""|list|ls)
      if [[ ! -s "$f" ]]; then
        reply_text "$to" "📅 日历空。
用法：
  /calendar add 2025-12-31 23:30 跨年倒数
  /calendar list
  /calendar rm <id>
  /calendar clear"
        return 0
      fi
      reply_text "$to" "📅 日程：
$(awk -F'\t' '{printf "  [%s] %s  →  %s\n", $1, $3, $4}' "$f" | sort -k3)"
      ;;
    add)
      # arg 形如 "2025-12-31 23:30 event content"
      local date_part="${arg%% *}"
      local rest1="${arg#* }"
      local time_part="${rest1%% *}"
      local ev="${rest1#* }"
      [[ -z "$ev" || "$ev" == "$rest1" ]] && { reply_text "$to" "用法：/calendar add YYYY-MM-DD HH:MM <事件>"; return 0; }
      local epoch
      epoch=$(date -j -f "%Y-%m-%d %H:%M" "${date_part} ${time_part}" +%s 2>/dev/null) || \
      epoch=$(date -d "${date_part} ${time_part}" +%s 2>/dev/null) || epoch=""
      [[ -z "$epoch" ]] && { reply_text "$to" "❌ 时间格式解析失败：${date_part} ${time_part}"; return 0; }
      local now; now=$(date +%s)
      (( epoch <= now )) && { reply_text "$to" "❌ 不能设置在过去：${date_part} ${time_part}"; return 0; }
      local id; id=$(date +%s | tail -c 6)
      printf '%s\t%s\t%s %s\t%s\n' "$id" "$epoch" "$date_part" "$time_part" "$ev" >> "$f"
      reply_text "$to" "✅ 已添加日程 [${id}] ${date_part} ${time_part}: ${ev}"
      ;;
    rm|del)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/calendar rm <id>"; return 0; }
      if grep -q "^${arg}	" "$f"; then
        grep -v "^${arg}	" "$f" > "${f}.tmp" || true
        mv "${f}.tmp" "$f"
        reply_text "$to" "✅ 删除 [${arg}]"
      else
        reply_text "$to" "❌ 没找到 [${arg}]"
      fi
      ;;
    clear)
      rm -f "$f"
      reply_text "$to" "✅ 已清空"
      ;;
    *)
      reply_text "$to" "用法：/calendar [add|list|rm|clear]"
      ;;
  esac
}

register_command "/calendar" plugin_calendar "日历提醒：/calendar [add|list|rm|clear]"
register_command "/cal"      plugin_calendar "日历提醒 (短别名)：/cal [add|list|rm|clear]"
