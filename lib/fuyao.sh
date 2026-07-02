#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao AI Gateway direct chat (bypasses qodercli).
# Env: FUYAO_API_KEY (required), FUYAO_BASE_URL (optional override).

FUYAO_BASE_URL="${FUYAO_BASE_URL:-https://fuyao-ai-gateway.xiaopeng.link/v1}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

_fuyao_system_prompt() {
  local key="$1"
  local mem="" gmem=""
  mem=$(memory_show "$key" 2>/dev/null);   [[ "$mem" == "(本会话暂无记忆)" ]] && mem=""
  gmem=$(memory_show_global 2>/dev/null);  [[ "$gmem" == "(全局记忆暂为空)" ]] && gmem=""
  local base="你是一个聊天助手。用用户使用的语言回复（默认中文）。简洁但有帮助。"
  printf '%s' "$base"
  [[ -n "$gmem" ]] && printf '\n\n[全局记忆]:\n%s' "$gmem"
  [[ -n "$mem" ]]  && printf '\n\n[本会话记忆]:\n%s' "$mem"
}

# run_fuyao_chat <prompt> <key> <model>
# Calls Fuyao OpenAI-compatible /chat/completions and prints assistant content.
run_fuyao_chat() {
  local prompt="$1" key="$2" model="$3"

  if [[ -z "${FUYAO_API_KEY:-}" ]]; then
    echo "(Fuyao API key 未配置。请在 .env 中设置 FUYAO_API_KEY)"
    return 1
  fi

  local sys_prompt
  sys_prompt=$(_fuyao_system_prompt "$key")

  local payload
  payload=$(jq -nc \
    --arg model "$model" \
    --arg sys "$sys_prompt" \
    --arg user "$prompt" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $sys},
        {role: "user", content: $user}
      ],
      stream: false
    }')

  local resp
  resp=$(curl -sS --max-time 180 -X POST "${FUYAO_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${FUYAO_API_KEY}" \
    -d "$payload" 2>>"$LOG_DIR/fuyao.err")

  local content
  content=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

  if [[ -z "$content" ]]; then
    local err_msg
    err_msg=$(printf '%s' "$resp" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$err_msg" ]]; then
      log "FUYAO ERROR model=$model: $err_msg"
      echo "(Fuyao 调用失败: $err_msg)"
    else
      log "FUYAO ERROR model=$model: empty response"
      log "FUYAO raw resp: ${resp:0:500}"
      echo "(Fuyao 没有返回内容)"
    fi
    return 1
  fi

  log "FUYAO OK model=$model chars=${#content}"
  printf '%s' "$content"
}
