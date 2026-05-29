# plugins/cheatsh — /cheat <cmd>[/topic]  cheat.sh
plugin_cheat() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/cheat <command>[/topic]
例：/cheat tar
    /cheat python/list comprehension
    /cheat git/commit"; return 0; }
  local enc; enc=$(printf '%s' "$rest" | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe="/+:"))')
  local body; body=$(curl -sSL --max-time 10 -A 'curl/8.0' "https://cheat.sh/${enc}?T" 2>/dev/null) || body=""
  [[ -z "$body" ]] && { reply_text "$to" "❌ cheat.sh 不可达"; return 0; }
  local len=${#body}
  if (( len > 3500 )); then
    body="${body:0:3500}
... (省略 $((len-3500)) 字)"
  fi
  reply_text "$to" "📘
${body}"
}
register_command "/cheat" plugin_cheat "速查 (cheat.sh)：/cheat <command>[/topic]"
