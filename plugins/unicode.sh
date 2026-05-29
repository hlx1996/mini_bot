# plugins/unicode.sh — /unicode <char|U+XXXX|name>
plugin_unicode() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/unicode <字符|U+XXXX|名字>
例：/unicode 我
    /unicode U+1F600
    /unicode SNOWMAN"; return 0; }
  local out; out=$(python3 -c "
import sys, unicodedata as u
s = sys.argv[1].strip()
# 三种输入
chars = []
if s.upper().startswith('U+'):
  try: chars = [chr(int(s[2:], 16))]
  except: pass
if not chars:
  try: chars = [u.lookup(s)]
  except: pass
if not chars:
  chars = list(s)[:8]
for c in chars:
  cp = ord(c)
  name = ''
  try: name = u.name(c)
  except ValueError: name = '(no name)'
  cat = u.category(c)
  print(f\"  {c}   U+{cp:04X}  {name}  [{cat}]\")
" "$rest" 2>&1)
  reply_text "$to" "🔤
${out}"
}
register_command "/unicode" plugin_unicode "Unicode 信息：/unicode <字符|U+XXXX|名字>"
