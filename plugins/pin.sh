# plugins/pin.sh — /pin 常驻提示词（snippets cheatsheet）
# 实际数据/状态由 bot.sh 里的 pin_list / pin_enable / pin_disable / pin_add / pin_rm 处理。
# 本插件只把 /pin 的子命令派发逻辑搬出来。

plugin_pin() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  case "$sub" in
    ""|list|ls) reply_text "$to" "$(pin_list "$key")" ;;
    on)         pin_enable  "$key"; reply_text "$to" "📌 /pin 已开启，每次回复都会钉上这些文本" ;;
    off)        pin_disable "$key"; reply_text "$to" "已关闭 /pin" ;;
    add)
      local name body
      name="${arg%% *}"
      [[ "$arg" != "$name" ]] && body="${arg#* }" || body=""
      if [[ -z "$name" || -z "$body" ]]; then
        reply_text "$to" "用法：/pin add <名字> <内容>"
      else
        pin_add "$key" "$name" "$body"
        reply_text "$to" "✅ 已钉住: ${name} ($(printf %s "$body" | wc -c) bytes)"
      fi ;;
    rm|del)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/pin rm <名字>"; return 0; }
      pin_rm "$key" "$arg"
      reply_text "$to" "✅ 已删除 ${arg}" ;;
    *) reply_text "$to" "用法：/pin list | on | off | add <名字> <内容> | rm <名字>
说明：每次回复前都会无条件拼上这些文本（小抄/常驻提示）。
要做按需检索的知识库请用 /rag。
提示：往 \$BOT_HOME/pin/${key}/ 或 _global/ 直接放 .txt/.md 文件也可" ;;
  esac
}

register_command "/pin" plugin_pin "常驻提示词：/pin list|on|off|add <名字> <内容>|rm <名字>"
