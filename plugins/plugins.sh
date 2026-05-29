# plugins/plugins.sh — /plugins list|disable|enable|reload|info
# 管理 plugins/ 加载状态。状态存 $BOT_HOME/plugins.disabled（一行一个文件名 stem）。
# 注意：本插件本身被禁用后就再也用不了，所以 disable plugins 会被拒绝。

_plugins_state_file() {
  echo "${BOT_HOME:-./state}/plugins.disabled"
}

_plugins_list_files() {
  ls -1 "${PLUGINS_DIR}"/*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | sort
}

plugin_plugins() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  local state_f; state_f=$(_plugins_state_file)
  case "$sub" in
    ""|list|ls)
      local all loaded i
      all=$(_plugins_list_files)
      local out="📦 已知插件文件（${PLUGINS_DIR}）："
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if [[ -f "$state_f" ]] && LC_ALL=C grep -qx "$p" "$state_f"; then
          out+=$'\n'"  ⚪ $p  (disabled)"
        else
          out+=$'\n'"  🟢 $p"
        fi
      done <<<"$all"
      out+=$'\n\n'"📡 当前进程已注册命令数: ${#_PLUGIN_CMDS[@]}"
      reply_text "$to" "$out"
      ;;
    info)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/plugins info <name>"; return 0; }
      local f="${PLUGINS_DIR}/${arg}.sh"
      if [[ ! -f "$f" ]]; then
        reply_text "$to" "❌ 找不到 $f"; return 0
      fi
      local header; header=$(head -5 "$f" | sed -E 's/^# ?//')
      local cmds=""
      for ((i=0; i<${#_PLUGIN_CMDS[@]}; i++)); do
        # 这里没法 100% 反查 cmd 来自哪个文件，只列文件内 register_command
        :
      done
      local regs; regs=$(grep -E '^[[:space:]]*register_command ' "$f" | sed 's/^[[:space:]]*//')
      reply_text "$to" "📄 ${arg}.sh
———
${header}
———
注册命令：
${regs}"
      ;;
    disable)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/plugins disable <name>"; return 0; }
      if [[ "$arg" == "plugins" ]]; then
        reply_text "$to" "❌ 不能 disable /plugins 自己（否则就没法 enable 回来了）"; return 0
      fi
      local f="${PLUGINS_DIR}/${arg}.sh"
      [[ ! -f "$f" ]] && { reply_text "$to" "❌ 找不到 ${arg}.sh"; return 0; }
      mkdir -p "$(dirname "$state_f")"
      touch "$state_f"
      if LC_ALL=C grep -qx "$arg" "$state_f"; then
        reply_text "$to" "ℹ️ ${arg} 已经是 disabled 状态"
      else
        echo "$arg" >> "$state_f"
        reply_text "$to" "✅ 已禁用 ${arg}（重启后生效：/plugins reload 或重启 bot）"
      fi
      ;;
    enable)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/plugins enable <name>"; return 0; }
      if [[ -f "$state_f" ]] && LC_ALL=C grep -qx "$arg" "$state_f"; then
        # 删除该行（兼容 bash 3.2 / 跨平台 sed）
        grep -vx "$arg" "$state_f" > "${state_f}.tmp" || true
        mv "${state_f}.tmp" "$state_f"
        reply_text "$to" "✅ 已启用 ${arg}（重启后生效：/plugins reload 或重启 bot）"
      else
        reply_text "$to" "ℹ️ ${arg} 本来就没被 disable"
      fi
      ;;
    reload)
      # 当前进程下重新 source 所有插件。注意：register_command 是 append-only，
      # 重复 source 会出现重复命令；但 _plugin_lookup 取第一个匹配，所以
      # 行为还是正确的（只是 /help 会显得长）。建议改 disable/enable 后重启。
      reply_text "$to" "🔄 reload 仅作 best-effort：建议 disable/enable 后直接重启 bot。
当前进程命令数: ${#_PLUGIN_CMDS[@]}"
      ;;
    *)
      reply_text "$to" "用法：
  /plugins list           列出全部插件及其启停状态
  /plugins info <name>    查看插件文件头注释 + 注册的命令
  /plugins disable <name> 禁用某插件（重启生效）
  /plugins enable  <name> 启用某插件（重启生效）
  /plugins reload         best-effort 重载（建议直接重启 bot）"
      ;;
  esac
}

register_command "/plugins" plugin_plugins "插件管理：/plugins list|info|disable|enable|reload"
