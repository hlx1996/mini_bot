# plugins/translate_image.sh — /translate-image [target=zh] [图路径]
# OCR 最近一张图（或指定路径），再让 qoder 翻译到目标语言。
# 复用 ocr.sh 里的 _ocr_last_image_for + _ocr_tesseract。

plugin_translate_image() {
  local to="$1" key="$2" rest="$3"
  local target="zh"
  if [[ "$rest" =~ (^|[[:space:]])target=([a-zA-Z_-]+) ]]; then
    target="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])target=${target}([[:space:]]|\$)/ /g; s/^ +//; s/ +\$//")
  fi
  local img="$rest"
  if [[ -z "$img" ]] && command -v _ocr_last_image_for >/dev/null 2>&1; then
    img=$(_ocr_last_image_for "$key" 2>/dev/null) || img=""
  fi
  if [[ -z "$img" || ! -f "$img" ]]; then
    reply_text "$to" "用法：/translate-image [target=zh|en|ja|...] [图片路径]
也可先发一张图，再发 /translate-image，会取本会话最近的图。"
    return 0
  fi

  reply_text "$to" "🔎 OCR + 翻译（→ ${target}）…"

  local raw=""
  if command -v _ocr_tesseract >/dev/null 2>&1; then
    raw=$(_ocr_tesseract "$img" 2>/dev/null)
  fi
  local workspace; workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")

  if [[ -z "$raw" ]]; then
    # 直接让 qoder 看图并翻译（多模态 + 翻译一步到位）
    local prompt="请把图里所有文字识别出来，然后翻译成 ${target}。
输出格式：

【原文】
<原文逐行>

【译文 ${target}】
<译文逐行>"
    local ans; ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" "$img" 2>/dev/null)
    [[ -z "$ans" ]] && ans="❌ 翻译失败（qoder 无返回）"
    reply_text "$to" "$ans"
    return 0
  fi

  # 已有 OCR 原文 → 让 qoder 翻译
  local prompt="把下面文字翻译成 ${target}，保持分行。只输出译文：

${raw}"
  local trans; trans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null)
  [[ -z "$trans" ]] && trans="❌ qoder 翻译失败"
  # 截断
  local out="【原文】
${raw}

【译文 → ${target}】
${trans}"
  if (( ${#out} > 3500 )); then out="${out:0:3500}
…(截断)"; fi
  reply_text "$to" "$out"
}

register_command "/translate-image" plugin_translate_image "图片 OCR 后翻译：/translate-image [target=zh|en|...]"
