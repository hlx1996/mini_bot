# plugins/admin.sh — /whitelist /admin /lang
# 派发到 bot.sh 里的 handle_whitelist / handle_admin / lang_set / lang_get。

plugin_whitelist() {
  local to="$1" key="$2" rest="$3"
  if ! is_admin "${G_FROM:-}"; then
    reply_text "$to" "需要管理员权限。"; return 0
  fi
  handle_whitelist "$to" "$rest"
}

plugin_admin() {
  local to="$1" key="$2" rest="$3"
  if [[ ! -s "${ADMINS_FILE:-}" ]]; then
    : # bootstrap: 首个 /admin add 调用者自动成为 admin
  elif ! is_admin "${G_FROM:-}"; then
    reply_text "$to" "需要管理员权限。"; return 0
  fi
  handle_admin "$to" "$rest"
}

plugin_lang() {
  local to="$1" key="$2" rest="$3"
  local nl="${rest%% *}"
  case "$nl" in
    en|zh)
      lang_set "$key" "$nl"
      if [[ "$nl" == "en" ]]; then
        reply_text "$to" "🌐 Language set to English"
      else
        reply_text "$to" "🌐 语言已切换为中文"
      fi ;;
    ""|show) reply_text "$to" "current lang: $(lang_get "$key") — use /lang en | /lang zh" ;;
    *) reply_text "$to" "用法：/lang [en|zh]" ;;
  esac
}

register_command "/whitelist" plugin_whitelist "[admin] 白名单管理：/whitelist add|rm|list <id>"
register_command "/admin"     plugin_admin     "管理员：/admin add|rm|list <id>"
register_command "/lang"      plugin_lang      "切换 /help 语言：/lang [en|zh]"
