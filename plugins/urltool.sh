# plugins/urltool.sh — /urltool encode|decode|parse
plugin_urltool() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  case "$sub" in
    enc|encode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/urltool enc <text>"; return 0; }
      reply_text "$to" "🔗 $(python3 -c 'import sys,urllib.parse as u;print(u.quote(sys.argv[1],safe=""))' "$arg")"
      ;;
    dec|decode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/urltool dec <text>"; return 0; }
      reply_text "$to" "🔗 $(python3 -c 'import sys,urllib.parse as u;print(u.unquote(sys.argv[1]))' "$arg")"
      ;;
    parse)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/urltool parse <url>"; return 0; }
      local out; out=$(python3 -c "
import sys, urllib.parse as u
p = u.urlparse(sys.argv[1])
print(f'scheme : {p.scheme}')
print(f'host   : {p.hostname}')
print(f'port   : {p.port or \"-\"}')
print(f'path   : {p.path}')
if p.query:
  print('query  :')
  for k,v in u.parse_qsl(p.query, keep_blank_values=True):
    print(f'  {k} = {v}')
if p.fragment: print(f'fragment: {p.fragment}')
" "$arg")
      reply_text "$to" "🔗
${out}"
      ;;
    *)
      reply_text "$to" "用法：/urltool enc|dec|parse <内容>"
      ;;
  esac
}
register_command "/urltool" plugin_urltool "URL 工具：/urltool enc|dec|parse"
