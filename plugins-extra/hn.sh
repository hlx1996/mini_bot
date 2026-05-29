# plugins/hn.sh — /hn  Hacker News top stories
# Firebase JSON API（免 key）。

plugin_hn() {
  local to="$1" key="$2" rest="$3"
  local n=10
  if [[ "$rest" =~ ^[0-9]+$ ]]; then n="$rest"; fi
  (( n > 30 )) && n=30
  local ids; ids=$(curl -fsSL --max-time 8 "https://hacker-news.firebaseio.com/v0/topstories.json") || {
    reply_text "$to" "❌ HN 不可达"; return 0
  }
  local picks; picks=$(printf '%s' "$ids" | python3 -c "
import sys, json
ids=json.load(sys.stdin)[:int(sys.argv[1])]
print('\n'.join(str(x) for x in ids))
" "$n")
  local out="📰 Hacker News Top ${n}
"
  local rank=0 sid
  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    rank=$((rank+1))
    local j; j=$(curl -fsSL --max-time 5 "https://hacker-news.firebaseio.com/v0/item/${sid}.json" 2>/dev/null) || continue
    local line; line=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
title=d.get('title','-')
score=d.get('score',0)
by=d.get('by','-')
url=d.get('url') or f\"https://news.ycombinator.com/item?id={d.get('id')}\"
print(f\"{sys.argv[1]:>2}. [{score:>4}] {title}\")
print(f\"     👤 {by}  🔗 {url}\")
" "$rank")
    out+="${line}
"
  done <<<"$picks"
  reply_text "$to" "$out"
}

register_command "/hn" plugin_hn "Hacker News Top：/hn [N=10]"
