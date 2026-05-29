# plugins/paper.sh — /paper <arxiv-id|url|关键词>
# 取 arXiv 摘要 + qoder 总结成中文要点。

plugin_paper() {
  local to="$1"; local key="$2"; local rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/paper <arxiv-id|arxiv-url|关键词>
例：
  /paper 2310.06825
  /paper https://arxiv.org/abs/2310.06825
  /paper attention is all you need"
    return 0
  fi
  # 提取 arxiv id
  local id=""
  if [[ "$rest" =~ ([0-9]{4}\.[0-9]{4,5}) ]]; then
    id="${BASH_REMATCH[1]}"
  fi

  local xml=""
  _paper_fetch() {
    curl -sSL --max-time 25 --user-agent 'mini-bot/1.0 (paper plugin)' "$1" 2>/dev/null
  }
  local url
  if [[ -n "$id" ]]; then
    reply_text "$to" "📄 取 arXiv:${id} …"
    url="https://export.arxiv.org/api/query?id_list=${id}"
  else
    local enc; enc=$(jq -rn --arg s "$rest" '$s|@uri')
    reply_text "$to" "🔎 arXiv 搜索：${rest} …"
    url="https://export.arxiv.org/api/query?search_query=all:${enc}&max_results=1"
  fi
  local attempt
  for attempt in 1 2 3; do
    xml=$(_paper_fetch "$url")
    if [[ -n "$xml" && ! "$xml" =~ "Rate exceeded" ]]; then break; fi
    sleep 3
  done
  if [[ -z "$xml" ]] || [[ "$xml" =~ "Rate exceeded" ]]; then
    reply_text "$to" "❌ arXiv 暂时不可用（${xml:-no response}）"
    return 1
  fi
  local meta
  meta=$(printf '%s' "$xml" | python3 -c '
import sys, re, html
x = sys.stdin.read()
def grab(tag):
  m = re.search(r"<"+tag+r"[^>]*>(.*?)</"+tag+r">", x, re.S)
  return html.unescape(re.sub(r"\s+"," ", m.group(1).strip())) if m else ""
title = grab("title")
# first <title> is feed title; grab the second entry-level
ms = re.findall(r"<entry>.*?</entry>", x, re.S)
if ms:
  e = ms[0]
  def g2(t):
    m = re.search(r"<"+t+r"[^>]*>(.*?)</"+t+r">", e, re.S)
    return html.unescape(re.sub(r"\s+"," ", m.group(1).strip())) if m else ""
  t = g2("title"); s = g2("summary")
  a = re.findall(r"<name>(.*?)</name>", e)
  pub = g2("published")[:10]
  link = re.search(r"<id>(.*?)</id>", e)
  link = link.group(1) if link else ""
  print(f"TITLE::{t}")
  print(f"AUTHORS::{', '.join(a[:6])}")
  print(f"PUB::{pub}")
  print(f"LINK::{link}")
  print(f"ABS::{s}")
' 2>/dev/null)
  if [[ -z "$meta" ]]; then
    reply_text "$to" "❌ 无法解析 arXiv 响应"
    return 1
  fi
  local title authors pub link abs
  title=$(printf '%s' "$meta" | sed -n 's/^TITLE:://p')
  authors=$(printf '%s' "$meta" | sed -n 's/^AUTHORS:://p')
  pub=$(printf '%s' "$meta" | sed -n 's/^PUB:://p')
  link=$(printf '%s' "$meta" | sed -n 's/^LINK:://p')
  abs=$(printf '%s' "$meta" | sed -n 's/^ABS:://p')

  if [[ -z "$abs" ]]; then
    reply_text "$to" "❌ 没找到论文"
    return 1
  fi
  # 让 qoder 总结
  local key; key=$(_chat_key "$to")
  local workspace; workspace="$WORKSPACE_DIR/$key"
  mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="把下面 arXiv 论文摘要翻译成中文，并用 5 个要点（# 编号）总结核心贡献、方法、实验、结论：

标题：${title}
作者：${authors}
${abs}"
  local ans
  ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || ans=""
  if [[ -z "$ans" ]]; then ans="（总结失败，仅返回原文）

${abs}"; fi
  reply_text "$to" "📄 ${title}
👤 ${authors}
📅 ${pub}
🔗 ${link}

${ans}"
}

register_command "/paper" plugin_paper "查 arXiv 论文：/paper <id|url|关键词>"
register_command "/论文"   plugin_paper "查 arXiv 论文：/论文 <id|url|关键词>"
