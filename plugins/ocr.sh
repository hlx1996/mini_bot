#!/usr/bin/env bash
# plugins/ocr.sh — /ocr  对最近收到的图片做 OCR
# 引擎自动探测：
#   1. tesseract (跨平台，支持中英日韩等)
#   2. macOS 'shortcuts' + 系统 Vision（如果用户配了 OCR shortcut）
#   3. 默认 fallback：直接把图发给 qoder 让它看图描述（多模态）

_ocr_last_image_for() {
  # 找最近这个 chat 收到的最新图片（看 events.jsonl 的 media[].path）
  local key="$1"
  local f="$LOG_DIR/events.jsonl"
  [[ -s "$f" ]] || return 1
  tail -n 500 "$f" | python3 -c '
import sys, json
key = sys.argv[1]
last = None
for line in sys.stdin:
    try: e = json.loads(line)
    except: continue
    if e.get("kind") != "event": continue
    if e.get("chat_key") != key: continue
    for m in e.get("media", []) or []:
        if (m.get("type") in ("image","picture")) and m.get("path"):
            last = m["path"]
if last: print(last)
' "$key"
}

_ocr_tesseract() {
  local img="$1"
  # zh + en 两个 lang，需要装 tesseract-data-chi-sim
  local langs="eng"
  tesseract --list-langs 2>/dev/null | grep -qx "chi_sim" && langs="chi_sim+eng"
  tesseract "$img" - -l "$langs" 2>/dev/null
}

plugin_ocr() {
  local to="$1" key="$2" rest="$3"
  local img="$rest"
  if [[ -z "$img" ]]; then
    img=$(_ocr_last_image_for "$key" 2>/dev/null) || img=""
  fi
  if [[ -z "$img" || ! -f "$img" ]]; then
    reply_text "$to" "用法：/ocr [图片路径]   或先发一张图，再发 /ocr
（自动用本会话最近一张图）"
    return
  fi
  local txt=""
  if command -v tesseract >/dev/null 2>&1; then
    txt=$(_ocr_tesseract "$img")
  fi
  if [[ -z "$txt" ]]; then
    # Fallback: 让 qoder 看图（attach 给 run_with_heartbeat）
    reply_text "$to" "🔎 没装 tesseract，让 qoder 看图…"
    local workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
    local model; model=$(model_for_key "$key")
    txt=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "请把这张图里的所有文字精确逐字读出来，按原版式分行。" "$img")
  fi
  [[ -z "$txt" ]] && txt="(没读出文字)"
  # 截断防止 IM 限长
  if (( ${#txt} > 3500 )); then
    txt="${txt:0:3500}
…(已截断 ${#txt} 字符)"
  fi
  reply_text "$to" "📝 OCR 结果：
$txt"
}

register_command "/ocr"   plugin_ocr "图转文字：/ocr [图路径]（默认取最近一张图）"
