# plugins/diff.sh — /diff <a> ::: <b>  文本 diff
plugin_diff() {
  local to="$1" key="$2" rest="$3"
  case "$rest" in *":::"*) : ;; *)
    reply_text "$to" "用法：/diff <a> ::: <b>"; return 0 ;;
  esac
  local a="${rest%%:::*}" b="${rest#*:::}"
  a="${a% }"; b="${b# }"
  local fa fb; fa=$(mktemp); fb=$(mktemp)
  printf '%s\n' "$a" > "$fa"
  printf '%s\n' "$b" > "$fb"
  local d; d=$(diff -u "$fa" "$fb" 2>&1)
  rm -f "$fa" "$fb"
  [[ -z "$d" ]] && d="(完全一致)"
  reply_text "$to" "📊 diff:
${d}"
}
register_command "/diff" plugin_diff "文本 diff：/diff <a> ::: <b>"
