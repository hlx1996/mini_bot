# plugins/lyrics.sh — /lyrics <artist> - <title>
# lrclib.net 免 key
plugin_lyrics() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/lyrics <artist> - <title>
例：/lyrics Adele - Hello
    /lyrics Hello   （只给名字也能搜，但匹配较差）"
    return 0
  fi
  local artist="" title=""
  if [[ "$rest" == *" - "* ]]; then
    artist="${rest%% - *}"
    title="${rest#* - }"
  else
    title="$rest"
  fi
  local enc_t enc_a
  enc_t=$(pu_url_encode "$title")
  enc_a=$(pu_url_encode "$artist")
  local url="https://lrclib.net/api/search?track_name=${enc_t}&artist_name=${enc_a}"
  local j; j=$(pu_http_get "$url" 8) || { reply_text "$to" "❌ lrclib 不可达"; return 0; }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
try: arr=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
if not arr: print('（无）'); sys.exit()
a = arr[0]
print(f\"🎵 {a.get('trackName','-')} — {a.get('artistName','-')}\")
print(f\"  📀 {a.get('albumName','-')}  ⏱️ {int(a.get('duration',0))}s\")
print('')
lyr = a.get('plainLyrics') or '(无纯文本歌词)'
print(lyr[:2500])
if len(lyr) > 2500: print('...')
" 2>/dev/null)
  reply_text "$to" "$out"
}
register_command "/lyrics" plugin_lyrics "查歌词 (lrclib)：/lyrics <artist> - <title>"
