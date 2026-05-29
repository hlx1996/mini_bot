# plugins/notes.sh — /notes 简易速记本
# 数据：$BOT_HOME/notes/<key>.md  追加 + 索引（每条带时间戳和编号）。

_NOTES_FILE() { echo "${BOT_HOME:-./state}/notes/${1}.md"; }

plugin_notes() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  local f; f=$(_NOTES_FILE "$key"); mkdir -p "$(dirname "$f")"

  case "$sub" in
    ""|list|ls)
      if [[ ! -s "$f" ]]; then
        reply_text "$to" "📝 还没记任何笔记。
用法：
  /notes add <内容>
  /notes list
  /notes rm <编号>
  /notes search <关键词>
  /notes clear"
        return 0
      fi
      reply_text "$to" "📝 笔记（${f}）：
$(awk '/^## / {n++; t=$0; sub(/^## /,"",t); printf "[%d] %s\n", n, t}' "$f" | tail -50)"
      ;;
    add)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/notes add <内容>"; return 0; }
      local ts; ts=$(date '+%Y-%m-%d %H:%M')
      printf '## %s\n%s\n\n' "$ts" "$arg" >> "$f"
      local n; n=$(grep -c '^## ' "$f")
      reply_text "$to" "✅ 已记 [${n}]: $(printf %s "$arg" | head -c 80)"
      ;;
    rm|del)
      [[ -z "$arg" || ! "$arg" =~ ^[0-9]+$ ]] && { reply_text "$to" "用法：/notes rm <编号>"; return 0; }
      local n="$arg"
      python3 - "$f" "$n" <<'PY'
import sys, re
f, n = sys.argv[1], int(sys.argv[2])
with open(f) as fp: txt = fp.read()
blocks = re.split(r'(?m)^## ', txt)
# blocks[0] is anything before first ##, rest are 1-indexed
if n < 1 or n > len(blocks)-1:
    print("OUT_OF_RANGE"); sys.exit()
del blocks[n]
out = blocks[0] + ('## ' + '## '.join(blocks[1:]) if len(blocks)>1 else '')
with open(f, 'w') as fp: fp.write(out)
print("OK")
PY
      reply_text "$to" "✅ 删除 [${n}]"
      ;;
    search|s|grep)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/notes search <关键词>"; return 0; }
      local hits; hits=$(grep -i -n "$arg" "$f" 2>/dev/null | head -20)
      [[ -z "$hits" ]] && hits="(无)"
      reply_text "$to" "🔎 搜索 '${arg}':
${hits}"
      ;;
    show|cat)
      [[ -z "$arg" || ! "$arg" =~ ^[0-9]+$ ]] && { reply_text "$to" "用法：/notes show <编号>"; return 0; }
      local body; body=$(python3 - "$f" "$arg" <<'PY'
import sys, re
f, n = sys.argv[1], int(sys.argv[2])
with open(f) as fp: txt = fp.read()
blocks = re.split(r'(?m)^## ', txt)
if n < 1 or n > len(blocks)-1: print("OUT"); sys.exit()
print('## ' + blocks[n].rstrip())
PY
)
      reply_text "$to" "$body"
      ;;
    clear)
      rm -f "$f"
      reply_text "$to" "✅ 已清空"
      ;;
    *)
      reply_text "$to" "用法：/notes list|add|rm|search|show|clear"
      ;;
  esac
}

register_command "/notes" plugin_notes "速记本：/notes [add|list|rm|search|show|clear]"
