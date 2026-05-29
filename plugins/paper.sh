# plugins/paper.sh — /paper <arxiv-id|doi|url|关键词>
# 优先 OpenAlex（免 key，全球学术索引），arXiv 备用，Semantic Scholar 第三档。

# OpenAlex 把 abstract 存成 inverted_index：{word: [positions]} → 还原成原文
_paper_openalex_invert() {
  python3 -c '
import sys, json
try:
  d = json.load(sys.stdin)
except Exception:
  print(""); sys.exit(0)
# search result 用 results[0]；按 ID 直查直接是 work 对象
w = d["results"][0] if isinstance(d, dict) and d.get("results") else d
if not isinstance(w, dict):
  print(""); sys.exit(0)
title = (w.get("title") or "").strip()
year  = w.get("publication_year") or ""
doi   = (w.get("doi") or "").replace("https://doi.org/","") if w.get("doi") else ""
oa    = ((w.get("open_access") or {}).get("oa_url") or "")
authors = [a.get("author",{}).get("display_name","") for a in (w.get("authorships") or [])][:6]
inv = w.get("abstract_inverted_index") or {}
positions = []
for word, pos in inv.items():
  for p in pos: positions.append((p, word))
positions.sort()
abstract = " ".join(w for _,w in positions)
out = {"title":title,"authors":", ".join(a for a in authors if a),"year":year,
       "doi":doi,"oa":oa,"abstract":abstract}
print(json.dumps(out, ensure_ascii=False))
'
}

plugin_paper() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/paper <arxiv-id|doi|url|关键词>
例：
  /paper 2310.06825
  /paper https://arxiv.org/abs/2310.06825
  /paper attention is all you need"
    return 0
  fi
  # 提取 arxiv id / doi
  local arxiv_id="" doi=""
  if [[ "$rest" =~ ([0-9]{4}\.[0-9]{4,5}) ]]; then
    arxiv_id="${BASH_REMATCH[1]}"
  fi
  if [[ "$rest" =~ (10\.[0-9]{4,9}/[^[:space:]]+) ]]; then
    doi="${BASH_REMATCH[1]}"
  fi

  reply_text "$to" "📄 查询论文 …"

  local meta_json=""
  # === Step 1: OpenAlex ===
  local oa_url=""
  if [[ -n "$arxiv_id" ]]; then
    oa_url="https://api.openalex.org/works/doi:10.48550/arXiv.${arxiv_id}"
  elif [[ -n "$doi" ]]; then
    oa_url="https://api.openalex.org/works/doi:${doi}"
  else
    local enc; enc=$(jq -rn --arg s "$rest" '$s|@uri')
    oa_url="https://api.openalex.org/works?search=${enc}&per-page=1"
  fi
  local oa_raw; oa_raw=$(curl -sSL --max-time 20 --user-agent 'mini-bot/1.0 (mailto:bot@example.com)' "$oa_url" 2>/dev/null)
  if [[ -n "$oa_raw" ]] && printf '%s' "$oa_raw" | jq -e . >/dev/null 2>&1; then
    meta_json=$(printf '%s' "$oa_raw" | _paper_openalex_invert 2>/dev/null)
  fi

  # === Step 2: arXiv 兜底（仅对 arxiv_id / 关键词） ===
  if [[ -z "$meta_json" || "$meta_json" == "null" ]] || [[ -z "$(printf '%s' "$meta_json" | jq -r '.abstract // ""' 2>/dev/null)" ]]; then
    local url=""
    if [[ -n "$arxiv_id" ]]; then
      url="https://export.arxiv.org/api/query?id_list=${arxiv_id}"
    elif [[ -z "$doi" ]]; then
      local enc2; enc2=$(jq -rn --arg s "$rest" '$s|@uri')
      url="https://export.arxiv.org/api/query?search_query=all:${enc2}&max_results=1"
    fi
    if [[ -n "$url" ]]; then
      local xml="" a
      for a in 1 2; do
        xml=$(curl -sSL --max-time 20 --user-agent 'mini-bot/1.0' "$url" 2>/dev/null)
        [[ -n "$xml" && ! "$xml" =~ "Rate exceeded" ]] && break
        sleep 2
      done
      if [[ -n "$xml" && ! "$xml" =~ "Rate exceeded" ]]; then
        meta_json=$(printf '%s' "$xml" | python3 -c '
import sys, re, html, json
x = sys.stdin.read()
ms = re.findall(r"<entry>.*?</entry>", x, re.S)
if not ms: print(""); sys.exit(0)
e = ms[0]
def g(t):
  m = re.search(r"<"+t+r"[^>]*>(.*?)</"+t+r">", e, re.S)
  return html.unescape(re.sub(r"\s+"," ", m.group(1).strip())) if m else ""
authors = re.findall(r"<name>(.*?)</name>", e)
link = re.search(r"<id>(.*?)</id>", e); link = link.group(1) if link else ""
print(json.dumps({"title":g("title"),"authors":", ".join(authors[:6]),
  "year":g("published")[:4],"doi":"","oa":link,"abstract":g("summary")}, ensure_ascii=False))
' 2>/dev/null)
      fi
    fi
  fi

  # === Step 3: Semantic Scholar (需 key) ===
  if [[ -z "$meta_json" || -z "$(printf '%s' "$meta_json" | jq -r '.abstract // ""' 2>/dev/null)" ]]; then
    local ss_url
    if [[ -n "$arxiv_id" ]]; then
      ss_url="https://api.semanticscholar.org/graph/v1/paper/arXiv:${arxiv_id}?fields=title,abstract,authors.name,year,externalIds,openAccessPdf"
    else
      local enc3; enc3=$(jq -rn --arg s "$rest" '$s|@uri')
      ss_url="https://api.semanticscholar.org/graph/v1/paper/search?query=${enc3}&limit=1&fields=title,abstract,authors.name,year,externalIds,openAccessPdf"
    fi
    local ss_json
    ss_json=$(curl -sSL --max-time 20 --user-agent 'mini-bot/1.0' \
      ${SEMANTIC_SCHOLAR_KEY:+-H "x-api-key: ${SEMANTIC_SCHOLAR_KEY}"} \
      "$ss_url" 2>/dev/null)
    if [[ -n "$ss_json" ]] && printf '%s' "$ss_json" | jq -e '.code=="429"' >/dev/null 2>&1; then
      :
    elif [[ -n "$ss_json" ]] && printf '%s' "$ss_json" | jq -e . >/dev/null 2>&1; then
      meta_json=$(printf '%s' "$ss_json" | jq -c '
        (.data[0]//.) as $w |
        {title: ($w.title // ""),
         authors: (($w.authors // []) | map(.name) | .[0:6] | join(", ")),
         year: (($w.year // "") | tostring),
         doi: "",
         oa: (($w.openAccessPdf.url // (if ($w.externalIds.ArXiv // "")!="" then "https://arxiv.org/abs/"+$w.externalIds.ArXiv else "" end))),
         abstract: ($w.abstract // "")}')
    fi
  fi

  if [[ -z "$meta_json" ]] || [[ -z "$(printf '%s' "$meta_json" | jq -r '.abstract // ""' 2>/dev/null)" ]] || [[ "$(printf '%s' "$meta_json" | jq -r '.abstract' 2>/dev/null)" == "null" ]]; then
    reply_text "$to" "❌ 三档源（OpenAlex / arXiv / Semantic Scholar）都没能取到论文。
可设置 SEMANTIC_SCHOLAR_KEY 提高成功率：
https://www.semanticscholar.org/product/api#api-key-form"
    return 1
  fi

  local title authors year link abs
  title=$(printf '%s' "$meta_json"   | jq -r '.title // ""')
  authors=$(printf '%s' "$meta_json" | jq -r '.authors // ""')
  year=$(printf '%s' "$meta_json"    | jq -r '.year // ""')
  link=$(printf '%s' "$meta_json"    | jq -r '.oa // (if .doi!="" then "https://doi.org/"+.doi else "" end) // ""')
  abs=$(printf '%s' "$meta_json"     | jq -r '.abstract // ""')

  # qoder 中文总结
  local workspace; workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="把下面论文摘要翻译成中文，并用 5 个要点（# 编号）总结核心贡献、方法、实验、结论：

标题：${title}
作者：${authors}
${abs}"
  local ans
  ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || ans=""
  [[ -z "$ans" ]] && ans="（总结失败，仅返回原文）

${abs}"

  reply_text "$to" "📄 ${title}
👤 ${authors}
📅 ${year}
🔗 ${link}

${ans}"
}

register_command "/paper" plugin_paper "查论文：/paper <arxiv-id|doi|关键词>（OpenAlex+arXiv+S2 三档）"
