# plugins/license.sh — /license <name> 通过 GitHub API 拉 license 模板
plugin_license() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    local list
    list=$(pu_http_get "https://api.github.com/licenses" 8) || list=""
    local short
    short=$(printf '%s' "$list" | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except: print('-'); sys.exit()
print(', '.join(x.get('key','') for x in d if x.get('key')))" 2>/dev/null)
    reply_text "$to" "用法：/license <key>
常见：mit, apache-2.0, gpl-3.0, bsd-3-clause, mpl-2.0, unlicense
完整：${short:-(查询失败)}"
    return 0
  fi
  local k; k=$(printf '%s' "$rest" | tr 'A-Z' 'a-z')
  local body; body=$(pu_http_get "https://api.github.com/licenses/${k}" 10) || {
    reply_text "$to" "❌ GitHub API 不可达"; return 0
  }
  local content
  content=$(printf '%s' "$body" | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
if 'body' not in d:
  print('NOT_FOUND'); sys.exit()
print(d['name'])
print('---')
print(d['body'])
" 2>/dev/null)
  if [[ "$content" == "NOT_FOUND" || "$content" == "PARSE_ERR" ]]; then
    reply_text "$to" "❌ 找不到 license: ${k}"; return 0
  fi
  local len=${#content}
  if (( len > 3500 )); then
    content="${content:0:3500}
... (省略 $((len-3500)) 字)"
  fi
  reply_text "$to" "📜
${content}"
}
register_command "/license" plugin_license "开源协议模板：/license <key>"
