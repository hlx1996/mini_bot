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
    # Semantic Scholar 兜底（免 key、500/5min/IP）
    reply_text "$to" "⚠️ arXiv 限速，切到 Semantic Scholar …"
    local ss_url ss_json
    if [[ -n "$id" ]]; then
      ss_url="https://api.semanticscholar.org/graph/v1/paper/arXiv:${id}?fields=title,abstract,authors.name,year,externalIds,openAccessPdf"
    else
      local enc2; enc2=$(jq -rn --arg s "$rest" '$s|@uri')
      ss_url="https://api.semanticscholar.org/graph/v1/paper/search?query=${enc2}&limit=1&fields=title,abstract,authors.name,year,externalIds,openAccessPdf"
    fi
    ss_json=$(curl -sSL --max-time 25 --user-agent 'mini-bot/1.0' \
      ${SEMANTIC_SCHOLAR_KEY:+-H "x-api-key: ${SEMANTIC_SCHOLAR_KEY}"} \
      "$ss_url" 2>/dev/null)
    if [[ -z "$ss_json" ]] || ! printf '%s' "$ss_json" | jq -e . >/dev/null 2>&1; then
      reply_text "$to" "❌ arXiv 限速且 Semantic Scholar 也无响应"
      return 1
    fi
    if printf '%s' "$ss_json" | jq -e '.code=="429"' >/dev/null 2>&1; then
      reply_text "$to" "❌ arXiv 和 Semantic Scholar 都在限速。可以申请 Semantic Scholar 免费 key 后设置 SEMANTIC_SCHOLAR_KEY 环境变量：
https://www.semanticscholar.org/product/api#api-key-form"
      return 1
    fi
    # 统一字段
    local title authors pub link abs
    title=$(printf '%s' "$ss_json"  | jq -r '(.data[0]//.) | .title // ""')
    authors=$(printf '%s' "$ss_json" | jq -r '(.data[0]//.) | (.authors // []) | map(.name) | .[0:6] | join(", ")')
    pub=$(printf '%s' "$ss_json"    | jq -r '(.data[0]//.) | (.year // "") | tostring')
    link=$(printf '%s' "$ss_json"   | jq -r '(.data[0]//.) | (.openAccessPdf.url // ("https://arxiv.org/abs/" + (.externalIds.ArXiv // "")))')
    abs=$(printf '%s' "$ss_json"    | jq -r '(.data[0]//.) | .abstract // ""')
    if [[ -z "$abs" || "$abs" == "null" ]]; then
      reply_text "$to" "❌ 没找到论文（或摘要为空）"; return 1
    fi
    local key2; key2=$(_chat_key "$to")
    local workspace2; workspace2="$WORKSPACE_DIR/$key2"; mkdir -p "$workspace2"
    local model2; model2=$(model_for_key "$key2")
    local prompt2="把下面论文摘要翻译成中文，并用 5 个要点（# 编号）总结核心贡献、方法、实验、结论：

标题：${title}
作者：${authors}
${abs}"
    local ans2
    ans2=$(run_with_heartbeat "$to" "$key2" "$workspace2" "$model2" "$prompt2" 2>/dev/null) || ans2=""
    [[ -z "$ans2" ]] && ans2="（总结失败，仅返回原文）

${abs}"
    reply_text "$to" "📄 ${title}
👤 ${authors}
📅 ${pub}
🔗 ${link}

${ans2}"
    return 0
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
