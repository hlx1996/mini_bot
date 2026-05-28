#!/usr/bin/env bash
# plugins/rag.sh — 真正的 RAG：把 Feishu doc 切块入索引（不存原文），
# 提问时按 BM25-ish 关键词检索 top-K，临时 fetch 抽对应段落注入 context。
#
# 用法：
#   /rag add <feishu-url>     拉一次文档，建索引（每块 ~300 字）；原文不落地
#   /rag list                  本会话 + 全局已加入的文档
#   /rag rm <doc_token>        删掉
#   /rag on | off              开关（默认 on）
#   /rag test <query>          预览这次会拼什么进 context
#
# 索引文件：state/rag/<chat_key>.idx.tsv  和  state/rag/_global.idx.tsv
#   每行：doc_token \t chunk_idx \t start \t end \t title \t tokens
# tokens 是这块内容的【关键词集合】（小写英数 + 中文 bigram），
# 不是原文。检索靠它，原文回 Feishu 实时拉。

_RAG_STATE_DIR="$BOT_HOME/rag_idx"
mkdir -p "$_RAG_STATE_DIR"

_rag_idx_for() {
  # _rag_idx_for <key>  → file path
  local key="$1"
  echo "$_RAG_STATE_DIR/$key.idx.tsv"
}

_rag_on_flag()   { echo "$_RAG_STATE_DIR/$1.off"; }
rag_is_on()      { [[ ! -f "$(_rag_on_flag "$1")" ]]; }
_rag_enable()    { rm -f "$(_rag_on_flag "$1")"; }
_rag_disable()   { : > "$(_rag_on_flag "$1")"; }

_rag_extract_token() {
  # _rag_extract_token <url-or-token>
  local s="$1"
  "$PYTHON_BIN" - "$s" <<'PY'
import sys, re
s = sys.argv[1]
m = re.search(r'/(?:docx|wiki|doc|sheet|base|file)/([A-Za-z0-9]+)', s)
print(m.group(1) if m else s.strip())
PY
}

# Fetch a Feishu doc body (DocxXML or wiki node text). Echoes plain text only.
_rag_fetch_text() {
  local tok="$1" out
  out=$(lark-cli docs +fetch --as user --api-version v2 --doc "$tok" --format json 2>/dev/null) || return 1
  "$PYTHON_BIN" - "$out" <<'PY'
import sys, json, re
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
if not d.get("ok"):
    sys.exit(1)
content = (d.get("data", {}).get("document", {}) or {}).get("content", "")
# Strip XML tags; collapse whitespace.
text = re.sub(r"<[^>]+>", "\n", content)
text = re.sub(r"\n+", "\n", text).strip()
print(text)
PY
}

# _rag_fetch_title <token> → echoes title (best-effort).
_rag_fetch_title() {
  local tok="$1" out
  out=$(lark-cli docs +fetch --as user --api-version v2 --doc "$tok" --format json 2>/dev/null) || { echo "$tok"; return; }
  "$PYTHON_BIN" - "$out" <<'PY' 2>/dev/null || echo "$1"
import sys, json, re
try:
    d = json.loads(sys.argv[1])
    c = (d.get("data", {}).get("document", {}) or {}).get("content", "")
    m = re.search(r"<title>(.*?)</title>", c)
    print(m.group(1) if m else d.get("data", {}).get("document", {}).get("document_id", ""))
except Exception:
    print("")
PY
}

# Build index rows for one doc and append to idx file.
# _rag_index_doc <idx_file> <token> <title> <text>
_rag_index_doc() {
  local idx="$1" tok="$2" title="$3" text="$4"
  local tf; tf=$(mktemp); printf '%s' "$text" > "$tf"
  "$PYTHON_BIN" - "$idx" "$tok" "$title" "$tf" <<'PY'
import sys, re, os
idx_path, tok, title, txt_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(txt_path, encoding='utf-8') as f:
    text = f.read()
def keytoks(s):
    s = s.lower()
    parts = re.findall(r'[a-z0-9]{2,}', s)
    cj = [c for c in s if '\u4e00' <= c <= '\u9fff']
    bigrams = [''.join(cj[i:i+2]) for i in range(len(cj)-1)]
    return sorted(set(parts) | set(bigrams))
SIZE, STEP = 350, 300
keep = []
if os.path.exists(idx_path):
    with open(idx_path, encoding='utf-8') as f:
        for line in f:
            if not line.strip(): continue
            if line.split('\t', 1)[0] != tok:
                keep.append(line.rstrip('\n'))
rows = list(keep)
n = 0
for i in range(0, max(len(text), 1), STEP):
    chunk = text[i:i+SIZE].strip()
    if len(chunk) < 20: continue
    toks = keytoks(chunk)
    if not toks: continue
    row = '\t'.join([tok, str(n), str(i), str(i+len(chunk)), title.replace('\t',' '), ' '.join(toks)])
    rows.append(row)
    n += 1
os.makedirs(os.path.dirname(idx_path) or '.', exist_ok=True)
with open(idx_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(rows))
    if rows: f.write('\n')
print(n)
PY
  local rc=$?
  rm -f "$tf"
  return $rc
}

# rag_retrieve <chat_key> <query>  →  echo "[Knowledge from RAG]:\n..."  or exit 1.
# This is the function bot.sh checks for with command -v.
rag_retrieve() {
  local key="$1" query="$2"
  rag_is_on "$key" || return 1
  local idx1; idx1=$(_rag_idx_for "$key")
  local idx2; idx2=$(_rag_idx_for "_global")
  [[ -s "$idx1" || -s "$idx2" ]] || return 1

  # Step 1: BM25-ish keyword overlap → pick top-K (token, chunk_idx, start, end, title, score)
  local pick
  pick=$("$PYTHON_BIN" - "$query" "$idx1" "$idx2" <<'PY' 2>/dev/null
import sys, os, re
q = sys.argv[1]
files = [p for p in sys.argv[2:] if p and os.path.exists(p)]
def keytoks(s):
    s = s.lower()
    parts = re.findall(r'[a-z0-9]{2,}', s)
    cj = [c for c in s if '\u4e00' <= c <= '\u9fff']
    bigrams = [''.join(cj[i:i+2]) for i in range(len(cj)-1)]
    return set(parts) | set(bigrams)
qt = keytoks(q)
if not qt: sys.exit(0)
cands = []  # (score, tok, chunk_idx, start, end, title)
for fp in files:
    for line in open(fp, encoding='utf-8'):
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 6: continue
        tok, ci, s, e, title, toks = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
        ct = set(toks.split(' '))
        score = len(qt & ct)
        if score > 0:
            cands.append((score, tok, ci, s, e, title))
cands.sort(reverse=True)
for sc, tok, ci, s, e, title in cands[:3]:
    print('\t'.join([str(sc), tok, ci, s, e, title]))
PY
)
  [[ -z "$pick" ]] && return 1

  # Step 2: refetch each picked doc once and slice the chunks.
  local out="[Knowledge from RAG]:" sc tok ci s e title text last_tok="" last_text=""
  while IFS=$'\t' read -r sc tok ci s e title; do
    [[ -z "$tok" ]] && continue
    if [[ "$tok" != "$last_tok" ]]; then
      last_text=$(_rag_fetch_text "$tok" 2>/dev/null) || last_text=""
      last_tok="$tok"
    fi
    [[ -z "$last_text" ]] && continue
    local slice
    slice=$("$PYTHON_BIN" - "$last_text" "$s" "$e" <<'PY' 2>/dev/null
import sys
text, s, e = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
print(text[s:e].strip())
PY
)
    [[ -z "$slice" ]] && continue
    out+=$'\n--- '"$title (score=$sc)"$' ---\n'"$slice"
  done <<<"$pick"

  [[ "$out" == "[Knowledge from RAG]:" ]] && return 1
  printf '%s' "$out"
}

plugin_rag() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" args=""
  [[ "$rest" != "$sub" ]] && args="${rest#* }"

  case "$sub" in
    add)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/rag add <feishu-url-or-token>"; return 0; }
      local tok title text idx n
      tok=$(_rag_extract_token "$args")
      [[ -z "$tok" ]] && { reply_text "$to" "❌ 解析不出 doc token：$args"; return 0; }
      reply_text "$to" "📚 正在拉取并索引文档 $tok …"
      text=$(_rag_fetch_text "$tok") || { reply_text "$to" "❌ 拉取失败（doc=$tok），可能没有权限或链接错"; return 0; }
      [[ -z "$text" ]] && { reply_text "$to" "❌ 文档内容为空"; return 0; }
      title=$(_rag_fetch_title "$tok")
      idx=$(_rag_idx_for "$key")
      n=$(_rag_index_doc "$idx" "$tok" "${title:-$tok}" "$text" | tail -1)
      _rag_enable "$key"
      reply_text "$to" "✅ 已索引《${title:-$tok}》（$n 块；原文未落地，每次提问会实时拉取）
doc_token: $tok"
      return 0 ;;

    list|ls|"")
      local idx1 idx2
      idx1=$(_rag_idx_for "$key"); idx2=$(_rag_idx_for "_global")
      local on_flag="ON"; rag_is_on "$key" || on_flag="OFF"
      local body="== /rag ($on_flag) — 本会话 =="
      if [[ -s "$idx1" ]]; then
        body+=$'\n'"$(awk -F'\t' '{print $1"\t"$5}' "$idx1" | sort -u | awk -F'\t' '{print "  "$1"  "$2}')"
      else
        body+=$'\n  (空)'
      fi
      body+=$'\n\n== 全局 =='
      if [[ -s "$idx2" ]]; then
        body+=$'\n'"$(awk -F'\t' '{print $1"\t"$5}' "$idx2" | sort -u | awk -F'\t' '{print "  "$1"  "$2}')"
      else
        body+=$'\n  (空)'
      fi
      reply_text "$to" "$body"
      return 0 ;;

    rm|del)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/rag rm <doc_token>"; return 0; }
      local tok=$(_rag_extract_token "$args") idx=$(_rag_idx_for "$key") tmp
      tmp=$(mktemp)
      grep -v "^${tok}	" "$idx" > "$tmp" 2>/dev/null || true
      mv "$tmp" "$idx"
      reply_text "$to" "✅ 已移除 $tok"
      return 0 ;;

    on)  _rag_enable  "$key"; reply_text "$to" "📚 /rag 已开启"; return 0 ;;
    off) _rag_disable "$key"; reply_text "$to" "已关闭 /rag"; return 0 ;;

    test)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/rag test <query>"; return 0; }
      local ctx
      ctx=$(rag_retrieve "$key" "$args") || { reply_text "$to" "（没有命中任何块）"; return 0; }
      reply_text "$to" "$ctx"
      return 0 ;;

    *)
      reply_text "$to" "用法：/rag add <feishu-url> | list | rm <doc_token> | on | off | test <q>"
      return 0 ;;
  esac
}

register_command "/rag" plugin_rag "RAG: /rag add <feishu-url> | list | rm <doc_token> | on|off | test <q>"
