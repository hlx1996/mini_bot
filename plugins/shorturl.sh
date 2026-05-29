# plugins/shorturl.sh — /shorturl <url>
# 走 is.gd（免 key、稳定）。

plugin_shorturl() {
  local to="$1"; local key="$2"; local rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/shorturl <url>
例：/shorturl https://github.com/some/very/long/path"
    return 0
  fi
  if [[ ! "$rest" =~ ^https?:// ]]; then
    reply_text "$to" "❌ 需要 http(s):// 开头的完整 URL"
    return 1
  fi
  local enc; enc=$(jq -rn --arg s "$rest" '$s|@uri')
  local short
  # tinyurl 兼容 GFW，免 key
  short=$(curl -sSL --max-time 15 \
    "https://tinyurl.com/api-create.php?url=${enc}" 2>/dev/null)
  # fallback: is.gd
  if [[ -z "$short" || "$short" =~ ^Error ]]; then
    short=$(curl -sSLk --max-time 15 \
      "https://is.gd/create.php?format=simple&url=${enc}" 2>/dev/null)
  fi
  if [[ -z "$short" || "$short" =~ ^Error ]]; then
    reply_text "$to" "❌ 短链生成失败：${short:-无响应}"
    return 1
  fi
  reply_text "$to" "🔗 ${short}"
}

register_command "/shorturl" plugin_shorturl "短链接：/shorturl <url>"
register_command "/短链"     plugin_shorturl "短链接：/短链 <url>"
