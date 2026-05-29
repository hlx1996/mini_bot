# plugins/idiom.sh — /idiom <成语>
# 让 qoder 解释成语含义、出处、用法、近反义词（中文母语场景的硬刚需）。
# 没有合适的免 key API，统一让模型答。

plugin_idiom() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/idiom <成语>   例：/idiom 守株待兔"
    return 0
  fi
  reply_text "$to" "🀄 查成语：${rest} …"
  local workspace; workspace="${WORK_ROOT}/${key}"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="解释成语「${rest}」，严格按下面格式输出：

【拼音】
【释义】（一两句）
【出处】（典籍名 + 原文一两句）
【典故】（不超过 60 字）
【用法】（褒/贬/中性 + 一句例句）
【近义词】（3 个）
【反义词】（3 个）

不要别的话。"
  local ans; ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null)
  [[ -z "$ans" ]] && ans="❌ qoder 没返回"
  reply_text "$to" "$ans"
}

register_command "/idiom" plugin_idiom "中文成语：/idiom <成语>"
