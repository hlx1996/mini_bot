# plugins/regex.sh — /regex <pattern> ::: <text>
# Python re.findall，返回所有匹配（含分组）
plugin_regex() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/regex <pattern> ::: <text>
例：/regex \\\\d+ ::: order 42 ships in 7 days"
    return 0
  fi
  case "$rest" in *":::"* ) : ;; * )
    reply_text "$to" "❌ 缺少分隔符 ':::': /regex <pattern> ::: <text>"; return 0 ;;
  esac
  local pat="${rest%%:::*}" txt="${rest#*:::}"
  pat="${pat% }"; txt="${txt# }"
  local out
  out=$(python3 -c "
import sys, re
pat = sys.argv[1]
txt = sys.argv[2]
try: rgx = re.compile(pat)
except re.error as e:
  print('❌ 无效正则:', e); sys.exit(0)
ms = list(rgx.finditer(txt))
if not ms: print('（无匹配）'); sys.exit(0)
print(f'🔍 命中 {len(ms)} 次:')
for i,m in enumerate(ms[:30],1):
  s = m.group(0)
  g = m.groups()
  if g:
    print(f'  [{i}] {s!r}  groups={g}')
  else:
    print(f'  [{i}] {s!r}')
if len(ms) > 30: print(f'  ... 还有 {len(ms)-30} 条')
" "$pat" "$txt" 2>&1)
  reply_text "$to" "$out"
}
register_command "/regex" plugin_regex "正则测试：/regex <pattern> ::: <text>"
