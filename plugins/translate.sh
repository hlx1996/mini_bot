# plugins/translate.sh — /translate [target=zh|en|...] <文本>
# 让 qoder 翻译（多语言、保留 markdown）。/translate-doc 走的是 URL 抓取，
# 本插件只翻译给定文本。

plugin_translate() {
  local to="$1" key="$2" rest="$3"
  local target="zh"
  if [[ "$rest" =~ (^|[[:space:]])target=([a-zA-Z_-]+) ]]; then
    target="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])target=${target}([[:space:]]|\$)/ /g; s/^ +//; s/ +\$//")
  fi
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/translate [target=zh|en|ja|...] <要翻译的文本>
例：/translate target=en 我今天去了北京"
    return 0
  fi
  reply_text "$to" "📖 翻译中（→ ${target}）…"
  local workspace; workspace="${WORK_ROOT}/${key}"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="把下面这段翻译成 ${target}。只输出译文，不要解释，保持原段落与格式：

${rest}"
  local ans; ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null)
  [[ -z "$ans" ]] && ans="❌ qoder 没返回内容"
  if (( ${#ans} > 3500 )); then ans="${ans:0:3500}
…(截断)"; fi
  reply_text "$to" "$ans"
}

register_command "/translate" plugin_translate "翻译文本：/translate [target=zh|en|...] <文本>"
