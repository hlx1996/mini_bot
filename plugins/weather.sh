# plugins/weather.sh — /weather <城市|地名>
# 走 wttr.in（免 key、免代理），直接返回简版文字预报。

plugin_weather() {
  local to="$1"; local key="$2"; local rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/weather <城市|地名>
例：
  /weather Beijing
  /weather 上海
  /weather Tokyo"
    return 0
  fi
  local enc; enc=$(jq -rn --arg s "$rest" '$s|@uri')
  reply_text "$to" "🌤️ 查询天气：${rest} …"
  # wttr.in 简版：?format=4 一行；?T 纯文本无 ANSI；m 国际单位
  local oneline; oneline=$(curl -sSL --max-time 15 \
    -H 'Accept-Language: zh' \
    "https://wttr.in/${enc}?format=4&m" 2>/dev/null)
  local detail; detail=$(curl -sSL --max-time 25 \
    -H 'Accept-Language: zh' \
    "https://wttr.in/${enc}?T&n&m&0" 2>/dev/null)
  if [[ -z "$oneline" && -z "$detail" ]]; then
    reply_text "$to" "❌ 天气服务暂时无响应（wttr.in）"
    return 1
  fi
  reply_text "$to" "${oneline}

${detail}"
}

register_command "/weather" plugin_weather "查天气：/weather <城市|地名>"
