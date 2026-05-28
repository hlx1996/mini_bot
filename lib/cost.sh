# lib/cost.sh — coarse token + cost tracker.
#
# We don't have an exact token count from qoder; use chars/3.5 as a rough
# estimate (close enough for Chinese+English mix). Log appended to
# $BOT_HOME/cost.jsonl. `cost_report` aggregates from there.
#
# Pricing is configurable via $BOT_HOME/pricing.json (USD per 1k tokens):
#   {"lite": {"in": 0.0003, "out": 0.0006}, "pro": {"in": 0.001, "out": 0.002}}
# Missing models fall back to "lite".

cost_log() {
  # cost_log <key> <model> <in_chars> <out_chars>
  local key="$1" model="$2" inc="$3" outc="$4"
  local f="$BOT_HOME/cost.jsonl"
  local ts; ts=$(date +%s)
  printf '{"ts":%d,"key":"%s","model":"%s","in_chars":%d,"out_chars":%d}\n' \
    "$ts" "$key" "$model" "$inc" "$outc" >> "$f"
}

cost_report() {
  # cost_report [day|week|all]   → echoes a human-readable summary
  local scope="${1:-day}"
  local f="$BOT_HOME/pricing.json"
  local cf="$BOT_HOME/cost.jsonl"
  [[ -f "$cf" ]] || { echo "(尚无 cost.jsonl，等首次回复后会自动累计)"; return; }
  "$PYTHON_BIN" - "$scope" "$cf" "$f" <<'PY'
import sys, json, time, os
scope, cf, pf = sys.argv[1], sys.argv[2], sys.argv[3]
now = int(time.time())
horizon = {"day": now-86400, "week": now-7*86400, "all": 0}.get(scope, now-86400)
pricing = {"lite":{"in":0.0003,"out":0.0006}, "pro":{"in":0.001,"out":0.002}}
if os.path.exists(pf):
    try: pricing.update(json.load(open(pf)))
    except Exception: pass
fallback = pricing.get("lite", {"in":0.0003,"out":0.0006})

agg = {}  # model -> {turns, in_tok, out_tok, cost}
total = {"turns":0, "in_tok":0, "out_tok":0, "cost":0.0}
for ln in open(cf, errors="ignore"):
    try: e = json.loads(ln)
    except Exception: continue
    if e.get("ts",0) < horizon: continue
    m = e.get("model","?")
    in_tok  = round(e.get("in_chars",0)/3.5)
    out_tok = round(e.get("out_chars",0)/3.5)
    rate = pricing.get(m, fallback)
    cost = in_tok*rate.get("in",0)/1000 + out_tok*rate.get("out",0)/1000
    a = agg.setdefault(m, {"turns":0,"in_tok":0,"out_tok":0,"cost":0.0})
    a["turns"] += 1
    a["in_tok"] += in_tok
    a["out_tok"] += out_tok
    a["cost"] += cost
    total["turns"] += 1
    total["in_tok"] += in_tok
    total["out_tok"] += out_tok
    total["cost"] += cost

print(f"📊 用量 / 成本（{scope}，token 用 chars/3.5 估算，价格来自 pricing.json）")
print(f"总计: {total['turns']} 轮 · 入 {total['in_tok']} tok · 出 {total['out_tok']} tok · ≈ ${total['cost']:.4f}")
if not agg:
    print("(本时段内无回复)")
else:
    print("按模型:")
    for m, a in sorted(agg.items(), key=lambda x: -x[1]['cost']):
        print(f"  {m:<10} {a['turns']:>4} 轮 · 入 {a['in_tok']:>6} · 出 {a['out_tok']:>6} · ≈ ${a['cost']:.4f}")
PY
}
