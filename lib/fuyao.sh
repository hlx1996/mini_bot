#!/usr/bin/env bash
# lib/fuyao.sh — Fuyao AI Gateway direct chat (bypasses qodercli).
# Maintains per-chat conversation history so Fuyao models have multi-turn context.
# Env: FUYAO_API_KEY (required), FUYAO_BASE_URL (optional), FUYAO_MAX_TURNS (default 20).

FUYAO_BASE_URL="${FUYAO_BASE_URL:-https://fuyao-ai-gateway.xiaopeng.link/v1}"
FUYAO_MAX_TURNS="${FUYAO_MAX_TURNS:-20}"

_is_fuyao_model() {
  [[ "$1" == fuyao-* ]]
}

_fuyao_history_file() { echo "$SESS_DIR/$1.fuyao_history"; }

_fuyao_system_prompt() {
  local key="$1"
  local mem="" gmem=""
  mem=$(memory_show "$key" 2>/dev/null);   [[ "$mem" == "(本会话暂无记忆)" ]] && mem=""
  gmem=$(memory_show_global 2>/dev/null);  [[ "$gmem" == "(全局记忆暂为空)" ]] && gmem=""
  local base="你是一个聊天助手（Fuyao 推理网关）。用用户使用的语言回复（默认中文）。简洁但有帮助。
注意：你是纯聊天模式，没有联网搜索、执行代码、读写文件、调用 API 等工具能力。如果用户的请求需要联网或使用工具，请明确告知并建议用户发送 /model select 切换到带工具能力的模型（如 Lite / Auto / Performance）。"
  printf '%s' "$base"
  [[ -n "$gmem" ]] && printf '\n\n[全局记忆]:\n%s' "$gmem"
  [[ -n "$mem" ]]  && printf '\n\n[本会话记忆]:\n%s' "$mem"
}

fuyao_reset() {
  local key="$1"
  local hf; hf=$(_fuyao_history_file "$key")
  : > "$hf" 2>/dev/null
}

# run_fuyao_chat <prompt> <key> <model>
run_fuyao_chat() {
  local prompt="$1" key="$2" model="$3"

  if [[ -z "${FUYAO_API_KEY:-}" ]]; then
    echo "(Fuyao API key 未配置。请在 .env 中设置 FUYAO_API_KEY)"
    return 1
  fi

  local sys_prompt
  sys_prompt=$(_fuyao_system_prompt "$key")

  local hf; hf=$(_fuyao_history_file "$key")
  touch "$hf"

  # Build messages array: system + last N turns from history + new user message
  local messages
  messages=$(jq -nc --arg sys "$sys_prompt" --arg user "$prompt" \
    --argjson history "$(tail -n "$((FUYAO_MAX_TURNS * 2))" "$hf" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')" \
    '[{role:"system",content:$sys}] + $history + [{role:"user",content:$user}]')

  local payload
  payload=$(jq -nc --arg model "$model" --argjson msgs "$messages" \
    '{model:$model, messages:$msgs, stream:false}')

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

  # Append this turn to history
  jq -nc --arg c "$prompt" '{role:"user",content:$c}' >> "$hf"
  jq -nc --arg c "$content" '{role:"assistant",content:$c}' >> "$hf"

  # Trim history file to max turns
  local total; total=$(wc -l < "$hf")
  local max_lines=$((FUYAO_MAX_TURNS * 2))
  if (( total > max_lines )); then
    local tmp; tmp=$(tail -n "$max_lines" "$hf")
    printf '%s\n' "$tmp" > "$hf"
  fi

  log "FUYAO OK model=$model chars=${#content}"
  printf '%s' "$content"
}

