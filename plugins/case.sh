# plugins/case.sh — /case <type> <text>  大小写/命名风格转换
# type: upper / lower / title / snake / camel / kebab / pascal
plugin_case() {
  local to="$1" key="$2" rest="$3"
  local tp="${rest%% *}" arg=""
  [[ "$rest" != "$tp" ]] && arg="${rest#* }"
  if [[ -z "$tp" || -z "$arg" ]]; then
    reply_text "$to" "用法：/case <upper|lower|title|snake|camel|kebab|pascal> <文本>"
    return 0
  fi
  local out; out=$(python3 -c "
import sys, re
t,s = sys.argv[1], sys.argv[2]
def words(x): return re.findall(r'[A-Za-z0-9]+', re.sub(r'([A-Z])', r' \\1', x))
if t=='upper': print(s.upper())
elif t=='lower': print(s.lower())
elif t=='title': print(s.title())
elif t=='snake': print('_'.join(w.lower() for w in words(s)))
elif t=='kebab': print('-'.join(w.lower() for w in words(s)))
elif t=='camel':
  w = words(s); print(w[0].lower() + ''.join(x.title() for x in w[1:])) if w else print('')
elif t=='pascal':
  print(''.join(x.title() for x in words(s)))
else: print('❌ 未知类型: '+t)
" "$tp" "$arg")
  reply_text "$to" "✏️ ${out}"
}
register_command "/case" plugin_case "大小写/命名转换：/case <upper|lower|title|snake|camel|kebab|pascal> <text>"
