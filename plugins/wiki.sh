# plugins/wiki.sh — /wiki <关键词> [lang=zh|en|ja|...]
# Wikipedia REST summary API（无 key）。

plugin_wiki() {
  local to="$1" key="$2" rest="$3"
  local lang="zh"
  if [[ "$rest" =~ (^|[[:space:]])lang=([a-zA-Z_-]+) ]]; then
    lang="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])lang=${lang}([[:space:]]|\$)/ /g; s/^ +//; s/ +\$//")
  fi
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/wiki <关键词> [lang=zh|en|ja|...]"
    return 0
  fi
  local q; q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1].replace(' ','_')))" "$rest")
  local url="https://${lang}.wikipedia.org/api/rest_v1/page/summary/${q}"
  local j; j=$(curl -fsSL -A "mini_bot/1.0" "$url" 2>/dev/null) || {
    reply_text "$to" "❌ Wikipedia ${lang} 没找到 '${rest}'（试 lang=en）"
    return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
if d.get('type')=='disambiguation':
    print(f\"⚠️ '{d.get('title')}' 是消歧义页：{d.get('extract','')[:200]}\")
else:
    print(f\"📚 {d.get('title','-')}\")
    desc=d.get('description') or ''
    if desc: print(f\"  {desc}\")
    print()
    print((d.get('extract') or '-')[:1200])
    print()
    print('🔗', (d.get('content_urls',{}).get('desktop',{}) or {}).get('page',''))
")
  reply_text "$to" "$out"
}

register_command "/wiki" plugin_wiki "维基百科摘要：/wiki <关键词> [lang=zh|en|ja|...]"
