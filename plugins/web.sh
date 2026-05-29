#!/usr/bin/env bash
# plugins/web.sh — /web <url> [问题]  抓网页 → 去 HTML → 让 qoder 总结/回答。

_web_strip_html() {
  # 把 HTML 压成可读文本：去 script/style/标签/连续空白。
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import sys, re, html
s = sys.stdin.read()
s = re.sub(r"(?is)<(script|style|noscript)\b.*?</\1>", " ", s)
s = re.sub(r"(?is)<!--.*?-->", " ", s)
s = re.sub(r"(?s)<[^>]+>", " ", s)
s = html.unescape(s)
s = re.sub(r"[ \t]+", " ", s)
s = re.sub(r"\n{3,}", "\n\n", s).strip()
print(s[:20000])
'
  else
    sed -E 's/<script[^>]*>.*<\/script>//gI; s/<style[^>]*>.*<\/style>//gI; s/<[^>]+>/ /g; s/[[:space:]]+/ /g' | head -c 20000
  fi
}

plugin_web() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/web <url> [问题]
示例：
  /web https://example.com
  /web https://news.ycombinator.com 给我列出今天 top 5 的话题
抓取后会用 qoder 总结/回答（受 20KB 文本上限）。"
    return
  fi
  local url="${rest%% *}" question=""
  [[ "$rest" != "$url" ]] && question="${rest#* }"
  if [[ ! "$url" =~ ^https?:// ]]; then
    reply_text "$to" "❌ 第一个参数必须是 http(s):// 开头的 URL"
    return
  fi
  reply_text "$to" "🌐 抓取 $url …"
  local body
  body=$(curl -sSL --max-time 25 \
    -A 'Mozilla/5.0 (mini_bot/web)' \
    "$url" 2>/dev/null | _web_strip_html)
  if [[ -z "$body" ]]; then
    reply_text "$to" "❌ 抓取失败或页面为空"
    return
  fi
  local workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt
  if [[ -n "$question" ]]; then
    prompt="阅读下面网页内容并回答用户问题。
用户问题：$question

网页正文（已去 HTML）：
$body"
  else
    prompt="请用中文给出这篇网页的结构化摘要：
1. 一句话主旨；2. 5 条以内要点；3. 相关链接/数据（如有）。
网页正文（已去 HTML）：
$body"
  fi
  local ans
  ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || ans=""
  [[ -z "$ans" ]] && ans="（qoder 没有返回内容）"
  reply_text "$to" "$ans"
}

register_command "/web"  plugin_web "抓网页 → qoder 总结：/web <url> [问题]"
