#!/usr/bin/env bash
# Refresh every RAG index in state/rag_idx — invoked by crontab via /rag watch.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDX_DIR="$ROOT/state/rag_idx"
[[ -d "$IDX_DIR" ]] || exit 0

# Source rag.sh to reuse _rag_ingest_one. But it needs bot helpers stubbed.
BOT_HOME="$ROOT/state"
LOG_DIR="$BOT_HOME/logs"; mkdir -p "$LOG_DIR"
LOGF="$LOG_DIR/rag-watch.log"

reply_text(){ :; }     # silent stub
register_command(){ :; } # plugin register no-op
log_info(){ echo "[$(date +%H:%M:%S)] $*" >>"$LOGF"; }

# shellcheck disable=SC1091
source "$ROOT/plugins/rag.sh"

ts=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$ts] rag-refresh-all start" >>"$LOGF"
total=0 ok=0 fail=0
for idx in "$IDX_DIR"/*.idx.tsv; do
  [[ -e "$idx" ]] || continue
  key=$(basename "$idx" .idx.tsv)
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    total=$((total+1))
    if _rag_ingest_one "" "$key" "$tok" 2>>"$LOGF" | grep -q '^OK'; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
    fi
  done < <(awk -F'\t' 'NF{print $1}' "$idx" | sort -u)
done
echo "[$ts] done: total=$total ok=$ok fail=$fail" >>"$LOGF"
