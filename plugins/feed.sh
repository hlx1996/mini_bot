# plugins/feed.sh — /feed <rss-url>  抓 RSS/Atom 最新 5 条
plugin_feed() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" || "$rest" != http* ]] && { reply_text "$to" "用法：/feed <rss-url>"; return 0; }
  local body; body=$(pu_http_get "$rest" 12) || { reply_text "$to" "❌ 抓不到 ${rest}"; return 0; }
  local out; out=$(printf '%s' "$body" | python3 -c "
import sys, re, html
x = sys.stdin.read()
# 既支持 <item> (RSS) 又支持 <entry> (Atom)
items = re.findall(r'<item\b[^>]*>(.*?)</item>', x, re.S|re.I)
if not items:
  items = re.findall(r'<entry\b[^>]*>(.*?)</entry>', x, re.S|re.I)
if not items:
  print('（feed 没解析到条目）'); sys.exit()
def g(b, tag):
  m = re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'>', b, re.S|re.I)
  if not m: return ''
  v = m.group(1)
  cd = re.search(r'<!\[CDATA\[(.*?)\]\]>', v, re.S)
  if cd: v = cd.group(1)
  return html.unescape(re.sub(r'<[^>]+>','',v)).strip()
def glink(b):
  m = re.search(r'<link\b[^>]*href=\"([^\"]+)\"', b, re.I) or re.search(r'<link[^>]*>([^<]+)</link>', b, re.I)
  return m.group(1).strip() if m else ''
print('📰 最近 5 条：')
for it in items[:5]:
  t = g(it,'title') or '(no title)'
  l = glink(it)
  d = g(it,'pubDate') or g(it,'updated') or g(it,'published') or ''
  print(f'  • {t[:80]}')
  if d: print(f'    📅 {d[:40]}')
  if l: print(f'    🔗 {l}')
" 2>/dev/null)
  reply_text "$to" "$out"
}
register_command "/feed" plugin_feed "RSS/Atom：/feed <url>"
