#!/usr/bin/env bash
# lib/lark.sh — Lark/Feishu transport: reply (text/card/media) + event subscription
# Sourced by bot.sh. Depends on globals: LOG_DIR, DL_ROOT, PYTHON_BIN.
#
# Note about --as:
#   lark-cli identifies *its own* auth profile via --as. After `lark-cli auth login`
#   the bot identity is named `bot` (and `event +subscribe` only accepts `bot`).
#   This is unrelated to our accounts.list label. Override per-account via
#   LARK_AS_<NAME> (uppercase) env var if you actually have multiple lark-cli
#   profiles; otherwise we default to `bot`.

lark_as_for() {
  local acct="$1"
  local up; up=$(printf '%s' "$acct" | tr '[:lower:].-' '[:upper:]__')
  local var="LARK_AS_${up}"
  printf '%s' "${!var:-${LARK_AS:-bot}}"
}

lark_reply_text() {
  local message_id="$1" text="$2"
  local as; as=$(lark_as_for "${G_ACCOUNT_NAME:-default}")
  local data resp
  if [[ -n "${G_MENTION_USER:-}" ]]; then
    local at_tag
    at_tag=$(printf '<at user_id="%s"></at> ' "$G_MENTION_USER")
    text="${at_tag}${text}"
  fi
  data=$(jq -nc --arg t "$text" '{msg_type:"text", content:({text:$t}|tojson)}')
  resp=$(lark-cli api POST "/open-apis/im/v1/messages/$message_id/reply" \
    --data "$data" --as "$as" 2>>"$LOG_DIR/reply.err") || return 1
  [[ -n "$resp" ]]
}

lark_reply_card() {
  local message_id="$1" title="$2" content="$3"
  local as; as=$(lark_as_for "${G_ACCOUNT_NAME:-default}")
  local card data
  card=$(jq -nc --arg title "$title" --arg content "$content" '
    {
      config: {wide_screen_mode: true},
      header: {title: {tag: "plain_text", content: $title}, template: "blue"},
      elements: [
        {tag: "markdown", content: $content}
      ]
    }')
  data=$(jq -nc --argjson c "$card" '{msg_type:"interactive", content:($c|tojson)}')
  lark-cli api POST "/open-apis/im/v1/messages/$message_id/reply" \
    --data "$data" --as "$as" 2>>"$LOG_DIR/reply.err" >/dev/null
}

lark_reply_media() {
  local message_id="$1" file="$2"
  local as; as=$(lark_as_for "${G_ACCOUNT_NAME:-default}")
  local upload_resp image_key data
  case "$file" in
    *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp)
      upload_resp=$(lark-cli api POST /open-apis/im/v1/images \
        --form "image_type=message" --form "image=@$file" \
        --as "$as" 2>>"$LOG_DIR/reply.err") || return 1
      image_key=$(jq -r '.data.image_key // empty' <<<"$upload_resp")
      [[ -z "$image_key" ]] && return 1
      data=$(jq -nc --arg k "$image_key" '{msg_type:"image", content:({image_key:$k}|tojson)}')
      ;;
    *)
      upload_resp=$(lark-cli api POST /open-apis/im/v1/files \
        --form "file_type=stream" --form "file_name=$(basename "$file")" \
        --form "file=@$file" --as "$as" 2>>"$LOG_DIR/reply.err") || return 1
      local file_key; file_key=$(jq -r '.data.file_key // empty' <<<"$upload_resp")
      [[ -z "$file_key" ]] && return 1
      data=$(jq -nc --arg k "$file_key" '{msg_type:"file", content:({file_key:$k}|tojson)}')
      ;;
  esac
  lark-cli api POST "/open-apis/im/v1/messages/$message_id/reply" \
    --data "$data" --as "$as" 2>>"$LOG_DIR/reply.err" >/dev/null
}

###############################################################################
# Reply helpers
###############################################################################
lark_subscribe_loop() {
  local acct="$1"
  local as; as=$(lark_as_for "$acct")
  local lark_dl="$DL_ROOT/lark-$acct"
  mkdir -p "$lark_dl"
  command -v lark-cli >/dev/null 2>&1 || {
    log "lark-cli not found in PATH — lark[$acct] disabled"
    sleep 60
    return 0
  }
  # Clean stale single-instance lock left by previous lark-cli (no process holds it but file present blocks subscribe)
  local _lock_dir="$HOME/.lark-cli/locks"
  if [[ -d "$_lock_dir" ]]; then
    for _lf in "$_lock_dir"/subscribe_*.lock; do
      [[ -e "$_lf" ]] || continue
      if ! lsof "$_lf" >/dev/null 2>&1; then
        rm -f "$_lf"
      fi
    done
  fi
  local parser="${BASH_SOURCE[0]%/*}/lark_event_parser.py"
  lark-cli event +subscribe \
    --as "$as" \
    --event-types im.message.receive_v1 \
  | "$PYTHON_BIN" "$parser" "$acct" "$lark_dl" "$as"
}
