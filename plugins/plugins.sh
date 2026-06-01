# plugins/plugins.sh — /plugins list|disable|enable|reload|info
# 管理 plugins/ 加载状态。状态存 $BOT_HOME/plugins.disabled（一行一个文件名 stem）。
# 注意：本插件本身被禁用后就再也用不了，所以 disable plugins 会被拒绝。

_plugins_state_file() {
  echo "${BOT_HOME:-./state}/plugins.disabled"
}

_plugins_list_files() {
  ls -1 "${PLUGINS_DIR}"/*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | sort
}

_plugins_extra_list_files() {
  ls -1 "${PLUGINS_EXTRA_DIR:-}"/*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | sort
}

_plugins_extra_state() {
  echo "${BOT_HOME:-./state}/plugins.extra.enabled"
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
      [[ ! -f "$f" && -f "${PLUGINS_EXTRA_DIR}/${arg}.sh" ]] && f="${PLUGINS_EXTRA_DIR}/${arg}.sh"
      if [[ ! -f "$f" ]]; then
        reply_text "$to" "❌ 找不到 ${arg}.sh (core 或 extra 均无)"; return 0
      fi
      local header; header=$(head -5 "$f" | sed -E 's/^# ?//')
      local regs; regs=$(grep -E '^[[:space:]]*register_command ' "$f" | sed 's/^[[:space:]]*//')
      reply_text "$to" "📄 ${arg}.sh  (${f#${SCRIPT_DIR}/})
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
      if declare -F plugins_reload >/dev/null 2>&1; then
        plugins_reload
        reply_text "$to" "🔄 已重载（懒加载 manifest 已重建）。当前命令数: ${#_PLUGIN_CMDS[@]}"
      else
        reply_text "$to" "🔄 reload 仅作 best-effort：建议 disable/enable 后直接重启 bot。
当前进程命令数: ${#_PLUGIN_CMDS[@]}"
      fi
      ;;
    extra)
      local sub2="${arg%% *}" name=""
      [[ "$arg" != "$sub2" ]] && name="${arg#* }"
      local efile; efile=$(_plugins_extra_state)
      case "$sub2" in
        ""|list|ls)
          local known; known=$(_plugins_extra_list_files)
          if [[ -z "$known" ]]; then
            reply_text "$to" "📦 plugins-extra/ 为空"; return 0
          fi
          local out="🧰 plugins-extra/ （opt-in，默认关闭）："
          while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            if [[ -f "$efile" ]] && LC_ALL=C grep -qx "$p" "$efile"; then
              out+=$'\n'"  🟢 $p  (enabled)"
            else
              out+=$'\n'"  ⚪ $p"
            fi
          done <<<"$known"
          out+=$'\n\n'"用法：/plugins extra enable <name>
      /plugins extra disable <name>
全部启用：环境变量 PLUGINS_EXTRA_ALL=1（重启 bot）"
          reply_text "$to" "$out"
          ;;
        enable)
          [[ -z "$name" ]] && { reply_text "$to" "用法：/plugins extra enable <name>"; return 0; }
          local ef="${PLUGINS_EXTRA_DIR}/${name}.sh"
          [[ ! -f "$ef" ]] && { reply_text "$to" "❌ 找不到 plugins-extra/${name}.sh"; return 0; }
          mkdir -p "$(dirname "$efile")"; touch "$efile"
          if LC_ALL=C grep -qx "$name" "$efile"; then
            reply_text "$to" "ℹ️ ${name} 本来就是 enabled"
          else
            echo "$name" >> "$efile"
            reply_text "$to" "✅ 已启用 extra ${name}（重启后生效）"
          fi
          ;;
        disable)
          [[ -z "$name" ]] && { reply_text "$to" "用法：/plugins extra disable <name>"; return 0; }
          if [[ -f "$efile" ]] && LC_ALL=C grep -qx "$name" "$efile"; then
            grep -vx "$name" "$efile" > "${efile}.tmp" || true
            mv "${efile}.tmp" "$efile"
            reply_text "$to" "✅ 已关闭 extra ${name}（重启后生效）"
          else
            reply_text "$to" "ℹ️ ${name} 本来就没启用"
          fi
          ;;
        *)
          reply_text "$to" "用法：/plugins extra [list|enable|disable] [name]"
          ;;
      esac
      ;;
    *)
      reply_text "$to" "用法：
  /plugins list           列出全部插件及其启停状态
  /plugins info <name>    查看插件文件头注释 + 注册的命令
  /plugins disable <name> 禁用某插件（重启生效）
  /plugins enable  <name> 启用某插件（重启生效）
  /plugins extra list     列出 opt-in 的 extra 插件
  /plugins extra enable <name>
  /plugins extra disable <name>
  /plugins reload         best-effort 重载（建议直接重启 bot）"
      ;;
  esac
}

register_command "/plugins" plugin_plugins "插件管理：/plugins list|info|disable|enable|reload"
