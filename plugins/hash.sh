# plugins/hash.sh — /hash <algo> <text>  支持 md5/sha1/sha256/sha512
plugin_hash() {
  local to="$1" key="$2" rest="$3"
  local algo="${rest%% *}" arg=""
  [[ "$rest" != "$algo" ]] && arg="${rest#* }"
  case "$algo" in
    md5|sha1|sha256|sha512) : ;;
    "")
      reply_text "$to" "用法：/hash <md5|sha1|sha256|sha512> <文本>"; return 0 ;;
    *)
      reply_text "$to" "❌ 不支持的算法 '${algo}' (md5|sha1|sha256|sha512)"; return 0 ;;
  esac
  [[ -z "$arg" ]] && { reply_text "$to" "用法：/hash ${algo} <文本>"; return 0; }
  local h
  if command -v "${algo}sum" >/dev/null 2>&1; then
    h=$(printf '%s' "$arg" | "${algo}sum" | awk '{print $1}')
  elif command -v openssl >/dev/null 2>&1; then
    h=$(printf '%s' "$arg" | openssl dgst -"$algo" | awk '{print $NF}')
  elif command -v shasum >/dev/null 2>&1 && [[ "$algo" =~ ^sha ]]; then
    local bits="${algo#sha}"; [[ "$bits" == "1" ]] && bits=1
    h=$(printf '%s' "$arg" | shasum -a "$bits" | awk '{print $1}')
  elif command -v md5 >/dev/null 2>&1 && [[ "$algo" == "md5" ]]; then
    h=$(printf '%s' "$arg" | md5 -q)
  else
    reply_text "$to" "❌ 系统找不到合适的工具计算 ${algo}"; return 0
  fi
  reply_text "$to" "🔑 ${algo}: ${h}"
}
register_command "/hash" plugin_hash "哈希：/hash <md5|sha1|sha256|sha512> <文本>"
