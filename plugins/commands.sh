# plugins/commands.sh — /commands  列出所有 plugin 命令（含简短帮助）
# 区别于 bot.sh 内置的 /help（手写、分组）。本插件按字母序自动列出所有 register_command。

plugin_commands() {
  local to="$1" key="$2" rest="$3"
  local lang_now="zh"
  if command -v lang_get >/dev/null 2>&1; then
    lang_now=$(lang_get "$key" 2>/dev/null || echo zh)
  fi
  [[ "$rest" == "en" ]] && lang_now="en"
  [[ "$rest" == "zh" ]] && lang_now="zh"

  local n=${#_PLUGIN_CMDS[@]}
  local i lines=""
  for ((i=0; i<n; i++)); do
    local c="${_PLUGIN_CMDS[$i]}" h="${_PLUGIN_HELPS[$i]}"
    [[ -z "$h" ]] && h="-"
    lines+="$(printf '  %-18s  %s' "$c" "$h")
"
  done
  local sorted; sorted=$(printf '%s' "$lines" | sort -u)

  local header tail_
  if [[ "$lang_now" == "en" ]]; then
    header="🧩 Plugin commands (total ${n}):"
    tail_="
Tip: send /help for the built-in grouped help (bilingual)."
  else
    header="🧩 已注册插件命令（共 ${n} 条）："
    tail_="
提示：内置命令请发 /help（中英文双语 + 分组）。"
  fi
  reply_text "$to" "${header}
${sorted}
${tail_}"
}

register_command "/commands" plugin_commands "列出所有 plugin 命令（字母序）"
register_command "/cmds"     plugin_commands "同 /commands"
