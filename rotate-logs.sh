#!/usr/bin/env bash
# Rotate mini_bot logs:  keep 7 days, gzip older than 1 day, drop >7d.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state/logs"
[[ -d "$DIR" ]] || exit 0
find "$DIR" -type f -name '*.log' -size +5M -exec sh -c '
  for f; do mv "$f" "$f.$(date +%Y%m%d-%H%M%S)" && : > "$f"; done
' sh {} +
find "$DIR" -type f -name '*.log.*' ! -name '*.gz' -mtime +0 -exec gzip -9 {} \;
find "$DIR" -type f -name '*.gz' -mtime +7 -delete
find "$DIR" -type f -name 'events.jsonl' -size +20M -exec sh -c '
  for f; do tail -c 10485760 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
' sh {} +
