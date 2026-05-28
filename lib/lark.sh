#!/usr/bin/env bash
# lib/lark.sh — Lark/Feishu transport: reply (text/card/media) + event subscription
# Sourced by bot.sh. Depends on globals: LOG_DIR, DL_ROOT, PYTHON_BIN.

lark_reply_text() {
  local message_id="$1" text="$2" acct="${G_ACCOUNT_NAME:-bot}"
  local data resp
  # If G_MENTION_USER is set (group @ reply), prepend <at user_id="..."/>
  if [[ -n "${G_MENTION_USER:-}" ]]; then
    local at_tag
    at_tag=$(printf '<at user_id="%s"></at> ' "$G_MENTION_USER")
    text="${at_tag}${text}"
  fi
  data=$(jq -nc --arg t "$text" '{msg_type:"text", content:({text:$t}|tojson)}')
  resp=$(lark-cli api POST "/open-apis/im/v1/messages/$message_id/reply" \
    --data "$data" --as "$acct" 2>>"$LOG_DIR/reply.err") || return 1
  [[ -n "$resp" ]]
}

lark_reply_card() {
  # $1 message_id  $2 title  $3 content (markdown supported)
  local message_id="$1" title="$2" content="$3" acct="${G_ACCOUNT_NAME:-bot}"
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
    --data "$data" --as "$acct" 2>>"$LOG_DIR/reply.err" >/dev/null
}

lark_reply_media() {
  local message_id="$1" file="$2" acct="${G_ACCOUNT_NAME:-bot}"
  # Upload image first, then reply with image message
  local upload_resp image_key data
  case "$file" in
    *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp)
      upload_resp=$(lark-cli api POST /open-apis/im/v1/images \
        --form "image_type=message" --form "image=@$file" \
        --as "$acct" 2>>"$LOG_DIR/reply.err") || return 1
      image_key=$(jq -r '.data.image_key // empty' <<<"$upload_resp")
      [[ -z "$image_key" ]] && return 1
      data=$(jq -nc --arg k "$image_key" '{msg_type:"image", content:({image_key:$k}|tojson)}')
      ;;
    *)
      # Generic file upload
      upload_resp=$(lark-cli api POST /open-apis/im/v1/files \
        --form "file_type=stream" --form "file_name=$(basename "$file")" \
        --form "file=@$file" --as "$acct" 2>>"$LOG_DIR/reply.err") || return 1
      local file_key; file_key=$(jq -r '.data.file_key // empty' <<<"$upload_resp")
      [[ -z "$file_key" ]] && return 1
      data=$(jq -nc --arg k "$file_key" '{msg_type:"file", content:({file_key:$k}|tojson)}')
      ;;
  esac
  lark-cli api POST "/open-apis/im/v1/messages/$message_id/reply" \
    --data "$data" --as "$acct" 2>>"$LOG_DIR/reply.err" >/dev/null
}

###############################################################################
# Reply helpers
###############################################################################
lark_subscribe_loop() {
  local acct="$1"
  local lark_dl="$DL_ROOT/lark-$acct"
  mkdir -p "$lark_dl"
  command -v lark-cli >/dev/null 2>&1 || {
    log "lark-cli not found in PATH — lark[$acct] disabled"
    sleep 60
    return 0
  }
  lark-cli event +subscribe \
    --as "$acct" \
    --event-types im.message.receive_v1 \
    --quiet \
  | "$PYTHON_BIN" <(cat <<'PY'
import sys, json, os, subprocess
acct = sys.argv[1]
dl_dir = sys.argv[2]
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("header", {}).get("event_type") != "im.message.receive_v1":
        continue
    msg = ev.get("event", {}).get("message", {})
    sender = ev.get("event", {}).get("sender", {}).get("sender_id", {})
    mtype = msg.get("message_type")
    raw = msg.get("content") or "{}"
    try: content = json.loads(raw)
    except Exception: content = {}
    text = ""
    media = []
    if mtype == "text":
        text = content.get("text", "")
    elif mtype == "image":
        ikey = content.get("image_key")
        if ikey:
            fpath = os.path.join(dl_dir, f"{ikey}.jpg")
            try:
                subprocess.run(["lark-cli","im","+messages-resources-download",
                    "--message-id", msg.get("message_id",""),
                    "--file-key", ikey, "--type", "image",
                    "--output", os.path.basename(fpath), "--as", acct],
                    cwd=dl_dir, check=False,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=30)
                if os.path.exists(fpath):
                    media.append({"kind":"image","path":fpath})
            except Exception: pass
    elif mtype == "post":
        title = content.get("title","")
        texts = []
        for row in content.get("content",[]):
            for el in row:
                if el.get("tag") == "text":
                    texts.append(el.get("text",""))
        text = "\n".join([t for t in [title]+texts if t])
    elif mtype == "file" or mtype == "audio" or mtype == "media":
        fkey = content.get("file_key")
        if fkey:
            fpath = os.path.join(dl_dir, f"{fkey}")
            try:
                subprocess.run(["lark-cli","im","+messages-resources-download",
                    "--message-id", msg.get("message_id",""),
                    "--file-key", fkey, "--type", "file",
                    "--output", os.path.basename(fpath), "--as", acct],
                    cwd=dl_dir, check=False,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=60)
                if os.path.exists(fpath):
                    kind = "audio" if mtype=="audio" else ("video" if mtype=="media" else "file")
                    media.append({"kind":kind,"path":fpath})
            except Exception: pass
    else:
        continue
    mentions = msg.get("mentions") or ev.get("event",{}).get("mentions") or []
    out = {
        "type":"message",
        "platform":"lark",
        "id": msg.get("message_id",""),
        "from": msg.get("chat_id",""),
        "from_name": sender.get("user_id") or sender.get("open_id",""),
        "from_open_id": sender.get("open_id",""),
        "chat_type": "group" if msg.get("chat_type")=="group" else "direct",
        "account_id": acct,
        "account_name": acct,
        "text": text,
        "mentioned": bool(mentions),
        "media": media,
        "reply_to": msg.get("message_id",""),
    }
    print(json.dumps(out, ensure_ascii=False), flush=True)
PY
) "$acct" "$lark_dl"
}
