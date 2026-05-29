# plugins/tldr.sh — /tldr <command>  tldr-pages 简明示例
plugin_tldr() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/tldr <command>
例：/tldr tar
    /tldr docker"; return 0; }
  local cmd; cmd=$(printf '%s' "$rest" | tr 'A-Z' 'a-z' | tr ' ' '-')
  local body=""
  local p
  for p in common linux osx; do
    body=$(pu_http_get "https://raw.githubusercontent.com/tldr-pages/tldr/main/pages/${p}/${cmd}.md" 6)
    if [[ -n "$body" && "$body" != *"404: Not Found"* ]]; then break; fi
    body=""
  done
  [[ -z "$body" ]] && { reply_text "$to" "❌ tldr 没收录: ${cmd}"; return 0; }
  reply_text "$to" "📖
${body}"
}
register_command "/tldr" plugin_tldr "命令速查 (tldr-pages)：/tldr <command>"
