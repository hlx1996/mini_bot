# plugins/readlater.sh — /readlater 稍后再读
# 数据：$BOT_HOME/readlater/<key>.tsv  每行: id\turl\ttitle\tts
# /readlater add <url>           抓取 title 入库
# /readlater list                列出
# /readlater rm <id>             删除一条
# /readlater read <id>           调 /web 总结
# /readlater clear

_RL_FILE() { echo "${BOT_HOME:-./state}/readlater/${1}.tsv"; }

plugin_readlater() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  local f; f=$(_RL_FILE "$key"); mkdir -p "$(dirname "$f")"
  touch "$f"

  case "$sub" in
    ""|list|ls)
      if [[ ! -s "$f" ]]; then
        reply_text "$to" "📚 稍后再读列表是空的。
用法：
  /readlater add <url>     入库（自动抓 title）
  /readlater list
  /readlater read <id>     用 /web 总结这一条
  /readlater rm <id>
  /readlater clear"
        return 0
      fi
      local out="📚 稍后再读："
      out+="$(awk -F'\t' '{printf "\n  [%s] %s\n     🔗 %s\n     📅 %s", $1, $3, $2, $4}' "$f")"
      reply_text "$to" "$out"
      ;;
    add)
      [[ -z "$arg" || "$arg" != http* ]] && { reply_text "$to" "用法：/readlater add <http://...>"; return 0; }
      local url="$arg"
      reply_text "$to" "📥 抓取 ${url} 标题…"
      local title; title=$(pu_http_get "$url" 6 2>/dev/null | python3 -c "
import sys, re, html
t = sys.stdin.read()
m = re.search(r'<title[^>]*>(.+?)</title>', t, re.I|re.S)
if m: print(html.unescape(m.group(1)).strip()[:200])
else: print('-')
")
      [[ -z "$title" || "$title" == "-" ]] && title="(no title)"
      local id; id=$(date +%s%N | tail -c 8)
      local ts; ts=$(date '+%Y-%m-%d %H:%M')
      printf '%s\t%s\t%s\t%s\n' "$id" "$url" "$title" "$ts" >> "$f"
      reply_text "$to" "✅ 已入库 [${id}]: ${title}"
      ;;
    rm|del)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/readlater rm <id>"; return 0; }
      if grep -q "^${arg}	" "$f"; then
        grep -v "^${arg}	" "$f" > "${f}.tmp" || true
        mv "${f}.tmp" "$f"
        reply_text "$to" "✅ 删除 [${arg}]"
      else
        reply_text "$to" "❌ 没找到 [${arg}]"
      fi
      ;;
    read)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/readlater read <id>"; return 0; }
      local url; url=$(awk -F'\t' -v id="$arg" '$1==id {print $2; exit}' "$f")
      [[ -z "$url" ]] && { reply_text "$to" "❌ 没找到 [${arg}]"; return 0; }
      reply_text "$to" "📖 调用 /web 总结 ${url} …"
      # 复用 plugins/web.sh
      if command -v plugin_web >/dev/null 2>&1; then
        plugin_web "$to" "$key" "$url"
      else
        reply_text "$to" "❌ plugin_web 不可用"
      fi
      ;;
    clear)
      rm -f "$f"
      reply_text "$to" "✅ 已清空"
      ;;
    *)
      reply_text "$to" "用法：/readlater [add|list|read|rm|clear]"
      ;;
  esac
}

register_command "/readlater" plugin_readlater "稍后再读：/readlater [add|list|read|rm|clear]"
register_command "/rl"        plugin_readlater "稍后再读 (短别名)：/rl [add|list|read|rm|clear]"
