# plugins/base64.sh — /base64 encode/decode
plugin_base64() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  case "$sub" in
    enc|e|encode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/base64 enc <文本>"; return 0; }
      reply_text "$to" "🔐 $(printf '%s' "$arg" | base64)"
      ;;
    dec|d|decode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/base64 dec <base64>"; return 0; }
      local out; out=$(printf '%s' "$arg" | base64 -d 2>/dev/null) || { reply_text "$to" "❌ 解码失败"; return 0; }
      reply_text "$to" "🔓 ${out}"
      ;;
    *)
      reply_text "$to" "用法：/base64 enc|dec <内容>"
      ;;
  esac
}
register_command "/base64" plugin_base64 "Base64 编解码：/base64 enc|dec <内容>"
