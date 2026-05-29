# plugins/mute.sh — /mute /unmute /whoami /say
# 都是 bot.sh case 分支的薄包装，bot.sh 兜底分支保留。

plugin_mute() {
  local to="$1" key="$2" rest="$3"
  list_add "${MUTE_FILE:?MUTE_FILE not set}" "$key"
  reply_text "$to" "🔕 本会话已静音。发 /unmute 解除（或管理员代为解除）。"
}

plugin_unmute() {
  local to="$1" key="$2" rest="$3"
  if is_admin "${G_FROM:-}" || ! is_muted_key "$key"; then
    list_rm "${MUTE_FILE:?}" "$key"
    reply_text "$to" "🔔 已解除静音。"
  else
    reply_text "$to" "(你已静音；请管理员代你 /say 或加白名单解除)"
  fi
}

plugin_whoami() {
  local to="$1" key="$2" rest="$3"
  reply_text "$to" "user: ${G_FROM:-?}
name: ${G_FROM_NAME:-?}
account: ${G_ACCOUNT_NAME:-?} (${G_ACCOUNT_ID:-?})
chat_key: ${key}
admin: $(is_admin "${G_FROM:-}" && echo yes || echo no)
muted: $(is_muted_key "$key" && echo yes || echo no)
tts: $(tts_is_on "$key" && echo on || echo off)"
}

plugin_say() {
  local to="$1" key="$2" rest="$3"
  if ! is_admin "${G_FROM:-}"; then
    reply_text "$to" "需要管理员权限。"; return 0
  fi
  local tgt msg
  tgt="${rest%% *}"; msg="${rest#* }"
  if [[ -z "$tgt" || -z "$msg" || "$tgt" == "$msg" ]]; then
    reply_text "$to" "用法：/say <user-id> <text>"; return 0
  fi
  if reply_text "$tgt" "$msg"; then
    reply_text "$to" "✅ 已代发给 ${tgt}"
  fi
}

register_command "/mute"   plugin_mute   "本会话静音（bot 不再回复你）"
register_command "/unmute" plugin_unmute "解除静音"
register_command "/whoami" plugin_whoami "查看当前用户/会话信息"
register_command "/say"    plugin_say    "[admin] 代发：/say <user-id> <text>"
