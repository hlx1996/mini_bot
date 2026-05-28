#!/usr/bin/env bash
# /metrics — observability over state/logs/events.jsonl

_METRICS_LOG="${BOT_HOME:-$(dirname "${BASH_SOURCE[0]}")/../state}/logs/events.jsonl"

_metrics_window_seconds() {
  case "$1" in
    1h)  echo 3600 ;;
    24h|"") echo 86400 ;;
    7d)  echo 604800 ;;
    30d) echo 2592000 ;;
    all) echo 0 ;;
    *[0-9]h) echo $(( ${1%h} * 3600 )) ;;
    *[0-9]d) echo $(( ${1%d} * 86400 )) ;;
    *)   echo 86400 ;;
  esac
}

_metrics_py() {
  # Args: SUB WIN WINLABEL LOG  via env
  python3 <<'PYEOF'
import json, os, time
from collections import Counter, defaultdict
import statistics

log = os.environ["LOG"]
win = int(os.environ["WIN"])
wl  = os.environ.get("WINLABEL", "24h")
sub = os.environ.get("SUB", "")
now = int(time.time())
cutoff = now - win if win else 0

events = []
try:
    with open(log, encoding="utf-8", errors="replace") as f:
        for ln in f:
            try:
                o = json.loads(ln)
            except Exception:
                continue
            if o.get("ts", 0) < cutoff:
                continue
            events.append(o)
except FileNotFoundError:
    print("（无日志）"); raise SystemExit

if sub == "errors":
    errs = [o for o in events if o.get("kind") == "reply" and not o.get("ok", True)]
    errs = errs[-10:]
    print("❌ 最近失败回复（{} 条）".format(len(errs)))
    for e in errs:
        msg = (e.get("err") or e.get("text") or "")[:60]
        print("- [{}] {}: {}".format(e.get("platform","?"), str(e.get("to",""))[:24], msg))
    if not errs:
        print("（无）")
elif sub == "chat":
    c = Counter()
    for o in events:
        if o.get("kind") != "event":
            continue
        name = o.get("from_name") or o.get("from") or "?"
        key = "{}/{}".format(o.get("platform","?"), str(name)[:20])
        c[key] += 1
    print("💬 活跃会话 Top10")
    for k, n in c.most_common(10):
        print("  {:>4}  {}".format(n, k))
    if not c:
        print("（窗口内无消息）")
else:
    n_in = n_out = n_err = 0
    chars_in = chars_out = 0
    by_plat = defaultdict(lambda: [0, 0])
    pending = {}
    lat = []
    for o in events:
        k = o.get("kind")
        plat = o.get("platform", "?")
        if k == "event":
            n_in += 1
            chars_in += len(o.get("text", "") or "")
            by_plat[plat][0] += 1
            pending[o.get("from")] = o.get("ts", 0)
        elif k == "reply":
            n_out += 1
            chars_out += len(o.get("text", "") or "")
            by_plat[plat][1] += 1
            if not o.get("ok", True):
                n_err += 1
            ts0 = pending.pop(o.get("to"), None)
            if ts0 and o.get("ts", 0) >= ts0:
                lat.append(o["ts"] - ts0)
    if lat:
        p95 = sorted(lat)[max(0, int(len(lat) * 0.95) - 1)]
        lat_s = "avg {:.1f}s, p50 {:.1f}s, p95 {:.1f}s".format(
            statistics.mean(lat), statistics.median(lat), p95)
    else:
        lat_s = "无样本"
    tok_in = chars_in // 3
    tok_out = chars_out // 3
    label = wl or "24h"
    print("📊 /metrics  窗口 {}".format(label))
    print("  收消息：{:,}    回复：{:,}    失败：{}".format(n_in, n_out, n_err))
    print("  字符：in {:,} / out {:,}".format(chars_in, chars_out))
    print("  ≈token：in {:,} / out {:,}  (chars/3 估算)".format(tok_in, tok_out))
    print("  延迟：{}".format(lat_s))
    print("  按平台：")
    for p, (i, o) in sorted(by_plat.items()):
        print("    {}: in {} / out {}".format(p, i, o))
    print("  细分：/metrics chat  /metrics errors  /metrics 7d")
PYEOF
}

plugin_metrics() {
  local to="$1" key="$2" args="$3"
  [[ -f "$_METRICS_LOG" ]] || { reply_text "$to" "📊 暂无日志（events.jsonl 不存在）"; return; }

  local sub win
  local first="${args%% *}"
  case "$first" in
    chat|errors)  sub="$first"; win="${args#* }"; [[ "$win" == "$args" ]] && win="24h" ;;
    "")           sub=""; win="24h" ;;
    *)            sub=""; win="$first" ;;
  esac
  local win_s; win_s=$(_metrics_window_seconds "$win")
  local out
  out=$(SUB="$sub" WIN="$win_s" WINLABEL="$win" LOG="$_METRICS_LOG" _metrics_py 2>&1)
  reply_text "$to" "$out"
}

register_command "/metrics" plugin_metrics "可观测：/metrics [1h|24h|7d|all] | chat | errors"
