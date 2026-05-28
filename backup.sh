#!/usr/bin/env bash
# backup.sh — export / import mini_bot session+memory+souls+skills
# Usage:
#   backup.sh export [--account NAME] [--out FILE]
#   backup.sh import FILE [--force]
#   backup.sh list
set -euo pipefail

BOT_HOME="${BOT_HOME:-$HOME/mini_bot}"
STATE_DIR="${STATE_DIR:-$BOT_HOME/state}"
BAK_DIR="${BAK_DIR:-$BOT_HOME/backups}"
mkdir -p "$BAK_DIR"

cmd="${1:-}"; shift || true

case "$cmd" in
  export)
    acct="" out=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --account) acct="$2"; shift 2 ;;
        --out)     out="$2";  shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
      esac
    done
    ts=$(date +%Y%m%d-%H%M%S)
    tag="${acct:-all}"
    out="${out:-$BAK_DIR/mini_bot-${tag}-${ts}.tar.gz}"
    cd "$STATE_DIR"
    if [[ -n "$acct" ]]; then
      # Backup only files for that account (sessions/<acct>* etc) — best effort
      find sessions memory -maxdepth 2 -type f -name "${acct}*" -o -name "*${acct}*" 2>/dev/null \
        | sort -u > /tmp/.minibot-bak-files.$$
      [[ -s /tmp/.minibot-bak-files.$$ ]] || { echo "no files for account=$acct" >&2; exit 1; }
      tar czf "$out" -T /tmp/.minibot-bak-files.$$ souls skills 2>/dev/null
      rm -f /tmp/.minibot-bak-files.$$
    else
      tar czf "$out" \
        --exclude='logs/*.log' --exclude='logs/*.err' --exclude='downloads' --exclude='workspaces' \
        sessions memory souls skills hooks tts rag accounts.list admins.list whitelist.list mute.list 2>/dev/null || true
    fi
    echo "$out"
    ;;

  import)
    file="${1:-}"; shift || true
    [[ -f "$file" ]] || { echo "file not found: $file" >&2; exit 2; }
    force=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --force) force=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
      esac
    done
    cd "$STATE_DIR"
    if [[ $force -eq 0 ]]; then
      conflicts=$(tar tzf "$file" | head -5 | xargs -I {} sh -c '[ -e "{}" ] && echo {}' 2>/dev/null | head -3 || true)
      if [[ -n "$conflicts" ]]; then
        echo "would overwrite (use --force):" >&2
        echo "$conflicts" >&2
        exit 3
      fi
    fi
    tar xzf "$file"
    echo "restored from $file"
    ;;

  list)
    ls -lhrt "$BAK_DIR" 2>/dev/null | tail -n +2 || echo "(empty)"
    ;;

  *)
    cat <<EOF
Usage:
  $0 export [--account NAME] [--out FILE]
  $0 import FILE [--force]
  $0 list
EOF
    exit 2 ;;
esac
