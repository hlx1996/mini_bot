# plugins/headers.sh — /headers <url>  HTTP 响应头
plugin_headers() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" || "$rest" != http* ]] && { reply_text "$to" "用法：/headers <url>"; return 0; }
  local h; h=$(curl -sSI -L --max-time 10 -A 'mini-bot/1.0' "$rest" 2>&1 | head -40) || h="(失败)"
  reply_text "$to" "📡 ${rest}
${h}"
}
register_command "/headers" plugin_headers "HTTP 响应头：/headers <url>"
