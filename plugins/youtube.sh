# plugins/youtube.sh — /youtube <url|关键词>
# 走 noembed.com（免 key）获取标题/作者/缩略图；关键词搜索走 piped.video API。
# yt-dlp 可选：如果本地装了，会用 yt-dlp 拿更详细信息（时长、views）。

_yt_extract_id() {
  python3 -c "
import re, sys, urllib.parse
u = sys.argv[1]
if 'youtu.be/' in u:
    print(u.split('youtu.be/')[1].split('?')[0].split('&')[0]); sys.exit()
if 'youtube.com' in u:
    q = urllib.parse.urlparse(u).query
    v = urllib.parse.parse_qs(q).get('v', [''])[0]
    if v: print(v); sys.exit()
    m = re.search(r'/(shorts|embed)/([\w-]+)', u)
    if m: print(m.group(2)); sys.exit()
print('')
" "$1"
}

plugin_youtube() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：
  /youtube <youtube-url>     视频信息
  /youtube <关键词>          搜索（top 5）"
    return 0
  fi

  if [[ "$rest" == http*://* ]]; then
    local vid; vid=$(_yt_extract_id "$rest")
    local url="$rest"
    if command -v yt-dlp >/dev/null 2>&1; then
      local j; j=$(yt-dlp --no-warnings --skip-download --dump-single-json "$url" 2>/dev/null) || j=""
      if [[ -n "$j" ]]; then
        local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print('🎬', d.get('title','-'))
print('👤', d.get('uploader','-'))
dur=d.get('duration') or 0
print(f\"⏱️ {dur//60}:{dur%60:02d}  👁  {d.get('view_count',0):,}  👍 {d.get('like_count') or '-'}\")
print('📅', d.get('upload_date','-'))
desc=(d.get('description') or '')[:300]
if desc: print('\\n📝', desc)
print('\\n🔗', d.get('webpage_url'))
")
        reply_text "$to" "$out"; return 0
      fi
    fi
    # noembed fallback
    local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$url")
    local j; j=$(curl -fsSL "https://noembed.com/embed?url=${enc}") || { reply_text "$to" "❌ 取不到 ${url}"; return 0; }
    local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
if d.get('error'): print('❌', d['error']); sys.exit()
print('🎬', d.get('title','-'))
print('👤', d.get('author_name','-'))
print('🔗', d.get('url') or d.get('thumbnail_url',''))
")
    reply_text "$to" "$out"
  else
    # search via yt-dlp (offline) → piped (网络兜底)
    local q="$rest"
    if command -v yt-dlp >/dev/null 2>&1; then
      local out
      out=$(yt-dlp --no-warnings --skip-download --flat-playlist \
              --print "%(title)s ||| %(uploader)s ||| %(duration)s ||| %(webpage_url)s" \
              "ytsearch5:${q}" 2>/dev/null)
      if [[ -n "$out" ]]; then
        local fmt; fmt=$(printf '%s' "$out" | python3 -c "
import sys
for ln in sys.stdin:
    p=[x.strip() for x in ln.strip().split('|||')]
    if len(p)<4: continue
    title,uploader,dur,url=p
    try: d=int(float(dur)); ts=f'{d//60}:{d%60:02d}'
    except: ts='-'
    print(f'🎬 {title}')
    print(f'  👤 {uploader}  ⏱️ {ts}')
    print(f'  🔗 {url}')
")
        reply_text "$to" "$fmt"
        return 0
      fi
    fi
    # piped 兜底
    local qenc; qenc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$q")
    local j=""
    for host in pipedapi.kavin.rocks pipedapi.adminforge.de api.piped.privacydev.net; do
      j=$(curl -fsSL --max-time 8 "https://${host}/search?q=${qenc}&filter=videos" 2>/dev/null) && [[ -n "$j" ]] && break
    done
    if [[ -z "$j" ]]; then
      reply_text "$to" "❌ YouTube 搜索不可达（piped 全挂、本机也没装 yt-dlp）
建议: brew install yt-dlp  或  pip install yt-dlp"
      return 0
    fi
    local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
items=d.get('items',[]) or []
if not items: print('（无结果）'); sys.exit()
for it in items[:5]:
    title=it.get('title','-')
    uploader=it.get('uploaderName','-')
    dur=it.get('duration',0) or 0
    url='https://youtube.com'+it.get('url','') if it.get('url','').startswith('/') else it.get('url','')
    print(f'🎬 {title}')
    print(f'  👤 {uploader}  ⏱️ {dur//60}:{dur%60:02d}')
    print(f'  🔗 {url}')
")
    reply_text "$to" "$out"
  fi
}

register_command "/youtube" plugin_youtube "YouTube 查询/搜索：/youtube <url|关键词>"
