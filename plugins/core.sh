# plugins/core.sh — /model /status /cancel /news /hooks /card
# 把 bot.sh 里小而独立的核心 case 分支抽出来。bot.sh 兜底分支仍在。

plugin_model() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "当前模型：$(model_for_key "$key")"
  else
    set_model_for_key "$key" "$rest"
    reply_text "$to" "✅ 已切换模型为：${rest}"
  fi
}

plugin_status() {
  local to="$1" key="$2" rest="$3"
  reply_text "$to" "🤖 mini_bot OK
host: $(uname -srm)
qoder: $(${QODER_BIN:-qoder} --version 2>/dev/null | head -1)
soul: $(current_soul_for_key "$key")
model: $(model_for_key "$key")
quota: $(quota_get_used "$key") / $(quota_limit_for_key "$key") (today)"
}

plugin_cancel() {
  local to="$1" key="$2" rest="$3"
  local lock="${SESS_DIR}/${key}.lock"
  if [[ -s "$lock" ]]; then
    kill "$(cat "$lock")" 2>/dev/null
    reply_text "$to" "🛑 已中止当前请求。"
  else
    reply_text "$to" "(没有正在处理的请求)"
  fi
}

plugin_news() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/news <关键词>"
    return 0
  fi
  local hits; hits=$(web_search "$rest" 8)
  [[ -z "$hits" ]] && hits="(没有搜到结果)"
  reply_text "$to" "📰 ${rest}

${hits}"
}

plugin_hooks() {
  local to="$1" key="$2" rest="$3"
  local out="🪝 hooks 目录：${HOOKS_DIR}
"
  local h
  for h in pre_turn post_turn on_command; do
    if [[ -x "${HOOKS_DIR}/${h}.sh" ]]; then
      out+="  ✅ ${h}.sh
"
    else
      out+="  ⬜ ${h}.sh   (未启用)
"
    fi
  done
  out+="
说明见 ${HOOKS_DIR}/README.txt"
  reply_text "$to" "$out"
}

plugin_card() {
  local to="$1" key="$2" rest="$3"
  if [[ "${G_PLATFORM:-wechat}" != "lark" && "${G_PLATFORM:-wechat}" != "feishu" ]]; then
    reply_text "$to" "/card 仅 Lark 平台支持"; return 0
  fi
  local title content
  title="${rest%%|*}"
  content="${rest#*|}"
  if [[ -z "$rest" || "$title" == "$content" ]]; then
    reply_text "$to" "用法：/card <title>|<content>"; return 0
  fi
  lark_reply_card "$to" "$title" "$content"
}

register_command "/model"  plugin_model  "查看/切换模型：/model [<name>]"
register_command "/status" plugin_status "bot 状态"
register_command "/cancel" plugin_cancel "中止当前正在处理的请求"
register_command "/news"   plugin_news   "新闻搜索：/news <关键词>"
register_command "/hooks"  plugin_hooks  "查看本机 hooks 启用状态"
register_command "/card"   plugin_card   "[Lark] 发卡片：/card <title>|<content>"
