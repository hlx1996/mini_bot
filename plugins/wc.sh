# plugins/wc.sh — /wc <text>  字数/词数/行数（含 CJK 字符）
plugin_wc() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/wc <文本>
返回行数 / 词数 / 字符数 / CJK 字符数 / 字节数"
    return 0
  fi
  local out; out=$(python3 -c "
import sys, re
t = sys.argv[1]
lines = t.count('\n') + (0 if t.endswith('\n') or not t else 1)
words = len(t.split())
chars = len(t)
cjk = sum(1 for c in t if '\u4e00' <= c <= '\u9fff' or '\u3040' <= c <= '\u30ff' or '\uac00' <= c <= '\ud7af')
bts = len(t.encode('utf-8'))
print(f'📏 lines={lines}  words={words}  chars={chars}  cjk={cjk}  bytes={bts}')
" "$rest")
  reply_text "$to" "$out"
}
register_command "/wc" plugin_wc "字数统计：/wc <文本>"
