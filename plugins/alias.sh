# plugins/alias.sh — /alias 用户自定义命令别名（chat 级 / 全局）
# 持久化到 $BOT_HOME/aliases/{<key>,_global}.tsv，每行 "alias\ttarget"。
# 实际转发逻辑在 lib/plugins.sh 的 plugin_dispatch 里读 tsv 即时解析，
# 因此 add/rm 立即对所有 forked worker 生效（无需重启）。
#
# 注意：目标命令必须是 plugins/ 注册过的命令；指向 bot.sh case 分支命令的别名
# 不生效（因为 plugin_dispatch 失败后才走 case，转发后已是 plugin 路径）。

_ALIAS_DIR() { echo "${BOT_HOME:-./state}/aliases"; }

plugin_alias() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  local d; d=$(_ALIAS_DIR); mkdir -p "$d"
  local f_chat="${d}/${key}.tsv"
  local f_global="${d}/_global.tsv"

  case "$sub" in
    ""|list|ls)
      local out="🪶 别名（本会话 ${key}）："
      if [[ -s "$f_chat" ]]; then
        out+=$'\n'"$(awk -F$'\t' 'NF>=2 && $1!~/^#/ {printf "  %s → %s\n", $1, $2}' "$f_chat")"
      else
        out+=$'\n'"  （无）"
      fi
      out+=$'\n\n'"🌐 别名（全局）："
      if [[ -s "$f_global" ]]; then
        out+=$'\n'"$(awk -F$'\t' 'NF>=2 && $1!~/^#/ {printf "  %s → %s\n", $1, $2}' "$f_global")"
      else
        out+=$'\n'"  （无）"
      fi
      out+=$'\n\n'"用法：
  /alias add /qq /youtube      （chat 级）
  /alias add -g /翻 /translate （全局）
  /alias rm /qq
  /alias clear                  清本会话别名"
      reply_text "$to" "$out"
      ;;
    add)
      local scope_f="$f_chat"
      if [[ "$arg" == "-g "* || "$arg" == "--global "* ]]; then
        scope_f="$f_global"
        arg="${arg#* }"
      fi
      local an="${arg%% *}" tn="${arg#* }"
      if [[ -z "$an" || -z "$tn" || "$an" == "$tn" || "$an" != /* || "$tn" != /* ]]; then
        reply_text "$to" "用法：/alias add [-g] /<别名> /<目标命令>"; return 0
      fi
      touch "$scope_f"
      grep -v "^${an}	" "$scope_f" > "${scope_f}.tmp" 2>/dev/null || true
      mv "${scope_f}.tmp" "$scope_f"
      printf '%s\t%s\n' "$an" "$tn" >> "$scope_f"
      reply_text "$to" "✅ 已加 alias：${an} → ${tn}（即时生效）"
      ;;
    rm|del)
      local an="$arg"
      [[ -z "$an" ]] && { reply_text "$to" "用法：/alias rm /<别名>"; return 0; }
      local removed=0 ff
      for ff in "$f_chat" "$f_global"; do
        if [[ -s "$ff" ]] && grep -q "^${an}	" "$ff" 2>/dev/null; then
          grep -v "^${an}	" "$ff" > "${ff}.tmp" || true
          mv "${ff}.tmp" "$ff"
          removed=1
        fi
      done
      if (( removed )); then
        reply_text "$to" "✅ 已删除 ${an}"
      else
        reply_text "$to" "ℹ️ 没找到 ${an}"
      fi
      ;;
    clear)
      rm -f "$f_chat"
      reply_text "$to" "✅ 已清空本会话别名"
      ;;
    *)
      reply_text "$to" "用法：
  /alias                          列出别名
  /alias add /<别名> /<目标>      本会话
  /alias add -g /<别名> /<目标>   全局
  /alias rm /<别名>
  /alias clear                    清本会话"
      ;;
  esac
}

register_command "/alias" plugin_alias "别名管理：/alias [add|rm|clear|list]"
