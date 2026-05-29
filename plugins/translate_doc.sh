#!/usr/bin/env bash
# plugins/translate_doc.sh — /translate-doc <url|text> [target=zh|en|ja|...]
# 抓 URL（或就用给的文本），让 qoder 翻译成目标语言。

plugin_translate_doc() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/translate-doc <url|text> [target=zh|en|ja|ko|fr|...]
示例：
  /translate-doc https://en.wikipedia.org/wiki/Mermaid_(software) target=zh
  /translate-doc Hello, how are you? target=zh
不指定 target 默认 zh。"
    return
  fi
  # 提取 target=xx
  local target="zh"
  if [[ "$rest" =~ (^|[[:space:]])target=([a-zA-Z_-]+) ]]; then
    target="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])target=${target}([[:space:]]|$)/ /g; s/[[:space:]]+/ /g; s/^ +//; s/ +$//")
  fi
  local body=""
  if [[ "$rest" =~ ^https?:// ]]; then
    local url="${rest%% *}"
    reply_text "$to" "📖 抓取 $url → 翻译为 $target …"
    if command -v _web_strip_html >/dev/null 2>&1; then
      body=$(curl -sSL --max-time 25 -A 'Mozilla/5.0 (mini_bot/translate)' "$url" 2>/dev/null | _web_strip_html)
    else
      body=$(curl -sSL --max-time 25 -A 'Mozilla/5.0 (mini_bot/translate)' "$url" 2>/dev/null \
        | sed -E 's/<script[^>]*>.*<\/script>//gI; s/<style[^>]*>.*<\/style>//gI; s/<[^>]+>/ /g; s/[[:space:]]+/ /g' \
        | head -c 20000)
    fi
    if [[ -z "$body" ]]; then reply_text "$to" "❌ 抓取失败"; return; fi
  else
    body="$rest"
    reply_text "$to" "📖 翻译中（→ ${target}）…"
  fi
  local workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="把下面内容翻译成 ${target}，要求：
- 保留段落结构、列表、代码块
- 专业术语首次出现给出原文括注
- 不要添加任何额外解释
原文：
$body"
  local ans
  ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || ans=""
  [[ -z "$ans" ]] && ans="（qoder 没有返回内容）"
  reply_text "$to" "$ans"
}

register_command "/translate-doc" plugin_translate_doc "翻译网页/文本：/translate-doc <url|text> [target=zh|en|...]"
