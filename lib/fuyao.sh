#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao AI Gateway direct chat (bypasses qodercli).
# Env: FUYAO_API_KEY (required), FUYAO_BASE_URL (optional override).

FUYAO_BASE_URL="${FUYAO_BASE_URL:-https://fuyao-ai-gateway.xiaopeng.link/v1}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

# run_fuyao_chat <prompt> <sys_prompt> <model>
# Calls Fuyao OpenAI-compatible /chat/completions and prints assistant content.
run_fuyao_chat() {
  local prompt="$1" sys_prompt="$2" model="$3"

  if [[ -z "${FUYAO_API_KEY:-}" ]]; then
    echo "(Fuyao API key 未配置。请在 .env 中设置 FUYAO_API_KEY)"
    return 1
  fi

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
      echo "(Fuyao 没有返回内容)"
    fi
    return 1
  fi

  printf '%s' "$content"
}
