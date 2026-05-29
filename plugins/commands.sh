# plugins/commands.sh — /commands  列出所有 plugin 命令（含简短帮助）
# 区别于 bot.sh 内置的 /help（手写、分组）。本插件按字母序自动列出所有 register_command。

plugin_commands() {
  local to="$1" key="$2" rest="$3"
  local n=${#_PLUGIN_CMDS[@]}
  local i lines=""
  for ((i=0; i<n; i++)); do
    local c="${_PLUGIN_CMDS[$i]}" h="${_PLUGIN_HELPS[$i]}"
    [[ -z "$h" ]] && h="-"
    lines+="$(printf '  %-18s  %s' "$c" "$h")
"
  done
  # 按命令名排序
  local sorted; sorted=$(printf '%s' "$lines" | sort -u)
  reply_text "$to" "🧩 已注册插件命令（共 ${n} 条）：
${sorted}

提示：内置命令请发 /help（中英文双语 + 分组）。"
}

register_command "/commands" plugin_commands "列出所有 plugin 命令（字母序）"
register_command "/cmds"     plugin_commands "同 /commands"
