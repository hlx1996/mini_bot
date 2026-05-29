# plugins/gitignore.sh — /gitignore <lang[,lang2,...]>
# 调 toptal.com/developers/gitignore/api/<list>
plugin_gitignore() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/gitignore <lang[,lang2,...]>
例：/gitignore python,node,macos
列表：https://docs.gitignore.io/install/command-line"
    return 0
  fi
  local q; q=$(printf '%s' "$rest" | tr -d ' ')
  local body; body=$(pu_http_get "https://www.toptal.com/developers/gitignore/api/${q}" 10) || {
    reply_text "$to" "❌ gitignore.io 不可达"; return 0
  }
  if [[ "$body" =~ ERROR ]] && [[ ${#body} -lt 300 ]]; then
    reply_text "$to" "❌ ${body}"; return 0
  fi
  # 太长就截断
  local len=${#body}
  if (( len > 3500 )); then
    body="${body:0:3500}
... (省略 $((len-3500)) 字)"
  fi
  reply_text "$to" "📄 .gitignore (${q}):
\`\`\`
${body}
\`\`\`"
}
register_command "/gitignore" plugin_gitignore ".gitignore 模板：/gitignore <lang[,lang2,...]>"
