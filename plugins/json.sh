# plugins/json.sh — /json format|min|get  对 JSON 文本做格式化/最小化/路径取值
plugin_json() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  case "$sub" in
    fmt|format|pretty)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/json fmt <json>"; return 0; }
      local out; out=$(printf '%s' "$arg" | python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin),ensure_ascii=False,indent=2))" 2>&1) || true
      reply_text "$to" "📋
${out}"
      ;;
    min|minify)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/json min <json>"; return 0; }
      local out; out=$(printf '%s' "$arg" | python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin),ensure_ascii=False,separators=(',',':')))" 2>&1) || true
      reply_text "$to" "📋 ${out}"
      ;;
    get|q)
      local path="${arg%% *}" data=""
      [[ "$arg" != "$path" ]] && data="${arg#* }"
      [[ -z "$path" || -z "$data" ]] && { reply_text "$to" "用法：/json get <jq路径> <json>
例：/json get .name {\"name\":\"x\"}"; return 0; }
      if command -v jq >/dev/null 2>&1; then
        local out; out=$(printf '%s' "$data" | jq -r "$path" 2>&1) || true
        reply_text "$to" "📋 ${out}"
      else
        reply_text "$to" "❌ 需要 jq"
      fi
      ;;
    "")
      reply_text "$to" "用法：/json fmt|min|get <内容>"
      ;;
    *)
      reply_text "$to" "未知子命令：${sub}"
      ;;
  esac
}
register_command "/json" plugin_json "JSON 工具：/json fmt|min|get"
