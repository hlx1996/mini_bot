#!/usr/bin/env bash
# Rotate mini_bot logs without logrotate (not installed on macOS by default).
# Policy mirrors scripts/logrotate.d/mini_bot.template: size 50M, keep 14 days.
#
# Snapshots use copytruncate semantics — gzip a copy, then truncate the live file
# in place. `mv` + recreate would be wrong here: the bot and its subscribers hold
# these files open in append mode, so they would keep writing to the renamed inode
# while the fresh file stayed empty. Same reason events.jsonl is truncated in
# place rather than replaced — an mv would orphan the bot's fd and silently drop
# every event written afterwards.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state/logs"
[[ -d "$DIR" ]] || exit 0

find "$DIR" -type f \( -name '*.log' -o -name '*.err' -o -name '*.out' \) \
     -size +50M -exec sh -c '
  for f; do
    snap="$f.$(date +%Y%m%d-%H%M%S).gz"
    gzip -9 -c "$f" > "$snap" && : > "$f"
  done
' sh {} +

find "$DIR" -type f -name '*.gz' -mtime +14 -delete

# events.jsonl is append-only state the bot replays on dedup, not a log: keep the
# trailing 10M instead of archiving the whole thing.
find "$DIR" -type f -name 'events.jsonl' -size +20M -exec sh -c '
  for f; do
    tail -c 10485760 "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
  done
' sh {} +
