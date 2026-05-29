# plugins/backup.sh — /backup（管理员）
# 派发到 bot.sh 的 handle_backup。is_admin 与 G_FROM 是 bot.sh 全局。

plugin_backup() {
  local to="$1" key="$2" rest="$3"
  if ! is_admin "$G_FROM"; then
    reply_text "$to" "需要管理员权限。"
    return 0
  fi
  handle_backup "$to" "$rest"
}

register_command "/backup" plugin_backup "[admin] 备份会话/状态：/backup [now|list|restore <id>]"
