# plugins/quote.sh — /quote  名人金句
# zenquotes.io: 50 reqs/30min/IP（足够个人用）
# fallback: quotable.io

plugin_quote() {
  local to="$1" key="$2" rest="$3"
  local j
  j=$(pu_http_get "https://zenquotes.io/api/random" 5 2>/dev/null) || j=""
  local txt
  txt=$(printf '%s' "$j" | python3 -c "
import sys, json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list) and d:
        d=d[0]
        print(f\"💡 {d.get('q','')}\\n   — {d.get('a','')}\")
    else: print('')
except: print('')
" 2>/dev/null)
  if [[ -z "$txt" ]]; then
    j=$(pu_http_get "https://api.quotable.io/random" 5 2>/dev/null) || {
      reply_text "$to" "❌ quote API 都不可达"; return 0
    }
    txt=$(printf '%s' "$j" | python3 -c "
import sys, json
try:
    d=json.load(sys.stdin)
    print(f\"💡 {d.get('content','')}\\n   — {d.get('author','')}\")
except: print('')
")
  fi
  [[ -z "$txt" ]] && txt="❌ 解析失败"
  reply_text "$to" "$txt"
}

register_command "/quote" plugin_quote "名言金句（英文）"
