#!/usr/bin/env bash
# lib/telegram.sh — Telegram Bot API transport (long-polling).
# Token comes from env: TELEGRAM_BOT_TOKEN_<acct>  (uppercase, dots→_).
#   TELEGRAM_BOT_TOKEN_DEFAULT=123:ABC...
# Or a shared TELEGRAM_BOT_TOKEN for the "default" account.
# Depends on: LOG_DIR, DL_ROOT, log.

tg_token_for() {
  local acct="$1"
  local up; up=$(printf '%s' "$acct" | tr '[:lower:].' '[:upper:]_')
  local var="TELEGRAM_BOT_TOKEN_${up}"
  printf '%s' "${!var:-${TELEGRAM_BOT_TOKEN:-}}"
}

# Safe fallback for log() when this module is sourced standalone (tests).
type -t log >/dev/null 2>&1 || log() { printf '[telegram] %s\n' "$*" >&2; }

tg_api() {
  # tg_api <acct> <method> <json-body>
  local acct="$1" method="$2" body="${3:-{}}"
  local token; token=$(tg_token_for "$acct")
  [[ -z "$token" ]] && { log "telegram[$acct] no token"; return 1; }
  curl -sS --max-time 60 -H 'Content-Type: application/json' \
    -d "$body" "https://api.telegram.org/bot${token}/${method}"
}

tg_api_form() {
  # tg_api_form <acct> <method> <curl -F args...>
  local acct="$1" method="$2"; shift 2
  local token; token=$(tg_token_for "$acct")
  [[ -z "$token" ]] && { log "telegram[$acct] no token"; return 1; }
  curl -sS --max-time 120 "$@" "https://api.telegram.org/bot${token}/${method}"
}

tg_reply_text() {
  local chat_id="$1" text="$2" acct="${G_ACCOUNT_NAME:-default}"
  local body; body=$(jq -nc --arg c "$chat_id" --arg t "$text" \
    '{chat_id: ($c | tonumber? // $c), text: $t, parse_mode: "Markdown"}')
  tg_api "$acct" "sendMessage" "$body" >>"$LOG_DIR/reply.err" 2>&1
}

tg_reply_media() {
  local chat_id="$1" file="$2" acct="${G_ACCOUNT_NAME:-default}"
  local method="sendDocument" field="document"
  case "$file" in
    *.jpg|*.jpeg|*.png|*.webp|*.gif) method="sendPhoto"; field="photo" ;;
    *.mp3|*.m4a|*.wav|*.ogg|*.opus)  method="sendVoice"; field="voice" ;;
    *.mp4|*.mov|*.webm)              method="sendVideo"; field="video" ;;
  esac
  tg_api_form "$acct" "$method" \
    -F "chat_id=$chat_id" -F "${field}=@${file}" >>"$LOG_DIR/reply.err" 2>&1
}

# Long-polling subscriber. Emits NDJSON events compatible with parse_event.
tg_subscribe_loop() {
  local acct="$1"
  local token; token=$(tg_token_for "$acct")
  if [[ -z "$token" ]]; then
    log "telegram[$acct] disabled (no token). Set TELEGRAM_BOT_TOKEN or TELEGRAM_BOT_TOKEN_${acct^^}"
    sleep 60; return 0
  fi
  local tg_dl="$DL_ROOT/telegram-$acct"
  mkdir -p "$tg_dl"
  local offset_file="$BOT_HOME/.tg-offset-$acct"
  local offset=0
  [[ -s "$offset_file" ]] && offset=$(cat "$offset_file")

  while true; do
    local resp
    resp=$(curl -sS --max-time 60 \
      "https://api.telegram.org/bot${token}/getUpdates?timeout=30&offset=${offset}" \
      2>>"$LOG_DIR/telegram.err") || { sleep 5; continue; }
    local n; n=$(jq '.result | length' <<<"$resp" 2>/dev/null || echo 0)
    [[ -z "$n" || "$n" == "null" ]] && n=0
    if (( n == 0 )); then continue; fi

    local i=0
    while (( i < n )); do
      local upd; upd=$(jq -c ".result[$i]" <<<"$resp")
      local update_id; update_id=$(jq -r '.update_id' <<<"$upd")
      offset=$(( update_id + 1 ))
      local msg; msg=$(jq -c '.message // empty' <<<"$upd")
      i=$((i+1))
      [[ -z "$msg" || "$msg" == "null" ]] && continue

      local chat_id chat_type from_id from_name text media_json
      chat_id=$(jq -r '.chat.id' <<<"$msg")
      chat_type=$(jq -r '.chat.type' <<<"$msg")
      from_id=$(jq -r '.from.id // ""' <<<"$msg")
      from_name=$(jq -r '.from.username // .from.first_name // ""' <<<"$msg")
      text=$(jq -r '.text // .caption // ""' <<<"$msg")

      # Detect file (single best variant: photo[-1] / document / voice / video / audio)
      media_json="[]"
      local file_id="" suffix=""
      if jq -e '.photo' <<<"$msg" >/dev/null 2>&1; then
        file_id=$(jq -r '.photo[-1].file_id' <<<"$msg"); suffix="jpg"
      elif jq -e '.document' <<<"$msg" >/dev/null 2>&1; then
        file_id=$(jq -r '.document.file_id' <<<"$msg")
        suffix=$(jq -r '.document.file_name // ""' <<<"$msg" | awk -F. 'NF>1 {print $NF}')
      elif jq -e '.voice' <<<"$msg" >/dev/null 2>&1; then
        file_id=$(jq -r '.voice.file_id' <<<"$msg"); suffix="ogg"
      elif jq -e '.audio' <<<"$msg" >/dev/null 2>&1; then
        file_id=$(jq -r '.audio.file_id' <<<"$msg"); suffix="mp3"
      elif jq -e '.video' <<<"$msg" >/dev/null 2>&1; then
        file_id=$(jq -r '.video.file_id' <<<"$msg"); suffix="mp4"
      fi
      if [[ -n "$file_id" ]]; then
        # 1. getFile to obtain file_path
        local file_info path url out kind
        file_info=$(curl -sS --max-time 15 \
          "https://api.telegram.org/bot${token}/getFile?file_id=${file_id}" \
          2>>"$LOG_DIR/telegram.err")
        path=$(jq -r '.result.file_path // empty' <<<"$file_info")
        if [[ -n "$path" ]]; then
          out="$tg_dl/${file_id}.${suffix:-bin}"
          url="https://api.telegram.org/file/bot${token}/${path}"
          curl -sS --max-time 60 -o "$out" "$url" 2>>"$LOG_DIR/telegram.err" || true
          if [[ -s "$out" ]]; then
            case "$suffix" in
              jpg|png|gif|webp) kind="image" ;;
              mp3|m4a|wav|ogg|opus) kind="audio" ;;
              mp4|mov|webm) kind="video" ;;
              *) kind="file" ;;
            esac
            media_json=$(jq -nc --arg k "$kind" --arg p "$out" '[{kind:$k, path:$p}]')
          fi
        fi
      fi

      # Emit NDJSON event line on stdout (consumed by handle_event).
      jq -nc \
        --arg id    "${update_id}" \
        --arg from  "${chat_id}" \
        --arg fname "${from_name}" \
        --arg fopen "${from_id}" \
        --arg ctype "$([[ $chat_type == private ]] && echo direct || echo group)" \
        --arg acct  "$acct" \
        --arg text  "$text" \
        --argjson media "$media_json" \
        '{type:"message", platform:"telegram", id:$id, from:$from, from_name:$fname,
          from_open_id:$fopen, chat_type:$ctype, account_id:$acct, account_name:$acct,
          text:$text, media:$media, reply_to:$from}'
    done

    printf '%s' "$offset" > "$offset_file"
  done
}
