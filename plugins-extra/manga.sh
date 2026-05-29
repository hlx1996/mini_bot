# plugins/manga.sh — /manga <关键词>  jikan.moe
plugin_manga() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/manga <关键词>"; return 0; }
  local enc; enc=$(pu_url_encode "$rest")
  local j; j=$(pu_http_get "https://api.jikan.moe/v4/manga?q=${enc}&limit=3" 10) || {
    reply_text "$to" "❌ jikan.moe 不可达"; return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
arr = d.get('data') or []
if not arr: print('（无）'); sys.exit()
out=[]
for a in arr[:3]:
  t = a.get('title') or '?'
  vols = a.get('volumes') or '?'
  chap = a.get('chapters') or '?'
  sc = a.get('score') or '?'
  url = a.get('url') or ''
  syn = (a.get('synopsis') or '').strip().replace('\n',' ')[:200]
  out.append(f'📚 {t}')
  out.append(f'  📖 {vols} 卷 / {chap} 话  ⭐ {sc}')
  out.append(f'  🔗 {url}')
  if syn: out.append(f'  📝 {syn}')
  out.append('')
print('\n'.join(out))
" 2>/dev/null)
  [[ -z "$out" ]] && out="❌ 解析失败"
  reply_text "$to" "$out"
}
register_command "/manga" plugin_manga "查漫画 (MyAnimeList)：/manga <关键词>"
