# plugins/dict.sh — /dict <英文单词>
# dictionaryapi.dev（免 key），返回释义/例句/音标。

plugin_dict() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/dict <英文单词>"
    return 0
  fi
  local w; w=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rest")
  local j; j=$(curl -fsSL --max-time 8 "https://api.dictionaryapi.dev/api/v2/entries/en/${w}") || {
    reply_text "$to" "❌ 没查到 '${rest}'（仅支持英文单词）"
    return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
arr=json.load(sys.stdin)
if not arr: print('（无）'); sys.exit()
d=arr[0]
print(f\"📖 {d.get('word','-')}\")
phons=[p.get('text','') for p in d.get('phonetics',[]) if p.get('text')]
if phons: print('  🔤', '  '.join(phons[:2]))
print()
for m in d.get('meanings',[])[:3]:
    print(f\"【{m.get('partOfSpeech','-')}】\")
    for de in m.get('definitions',[])[:2]:
        print(f\"  • {de.get('definition','')}\")
        ex=de.get('example')
        if ex: print(f\"    例: {ex}\")
    syn=m.get('synonyms') or []
    if syn: print(f\"  近义: {', '.join(syn[:6])}\")
")
  reply_text "$to" "$out"
}

register_command "/dict" plugin_dict "英文词典：/dict <word>"
