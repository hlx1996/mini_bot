# lib/router.sh — trigger-keyword based model routing.
#
# Per-chat rules live in $SESS_DIR/$key.routes (TSV: pattern\tmodel).
# A global ruleset lives in $BOT_HOME/routes.default (same format, fallback).
#
# Pattern is an extended regex (matched with `grep -E -i` against the user text).
# Special pattern `*` matches anything (rarely useful, but supported).
#
# Used by bot.sh handle_event after `model_for_key` to optionally override the
# model based on the message content (e.g. coding tasks → claude, chit-chat →
# lite, image generation → already handled by /image command).

_route_file_chat()   { echo "$SESS_DIR/$1.routes"; }
_route_file_global() { echo "$BOT_HOME/routes.default"; }

# route_for_text <key> <text>  → echoes routed model name (empty if no match).
route_for_text() {
  local key="$1" text="$2" f line pat model
  [[ -z "$text" ]] && return 1
  for f in "$(_route_file_chat "$key")" "$(_route_file_global)"; do
    [[ -f "$f" ]] || continue
    while IFS=$'\t' read -r pat model; do
      [[ -z "$pat" || "$pat" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$model" ]] && continue
      if [[ "$pat" == "*" ]] || printf '%s' "$text" | grep -E -i -q -- "$pat"; then
        printf '%s' "$model"
        return 0
      fi
    done < "$f"
  done
  return 1
}

route_list() {
  local key="$1" f label
  for f in "$(_route_file_chat "$key")" "$(_route_file_global)"; do
    label="$([[ "$f" == */routes.default ]] && echo global || echo chat)"
    [[ -f "$f" ]] || { echo "($label: 无规则)"; continue; }
    echo "== $label ($f) =="
    nl -ba "$f"
  done
}

# route_add <key> <pattern> <model> [--global]
route_add() {
  local key="$1" pat="$2" model="$3" scope="${4:-chat}"
  local f
  if [[ "$scope" == "--global" || "$scope" == "global" ]]; then
    f=$(_route_file_global)
  else
    f=$(_route_file_chat "$key")
  fi
  mkdir -p "$(dirname "$f")"
  printf '%s\t%s\n' "$pat" "$model" >> "$f"
}

# route_rm <key> <line-number> [--global]
route_rm() {
  local key="$1" idx="$2" scope="${3:-chat}"
  local f
  [[ "$scope" == "--global" || "$scope" == "global" ]] && f=$(_route_file_global) || f=$(_route_file_chat "$key")
  [[ -f "$f" ]] || return 0
  "$PYTHON_BIN" - "$f" "$idx" <<'PY'
import sys
p, i = sys.argv[1], int(sys.argv[2])
ls = open(p).read().splitlines()
if 1 <= i <= len(ls):
    del ls[i-1]
    open(p, "w").write("\n".join(ls) + ("\n" if ls else ""))
PY
}

route_clear() {
  local key="$1" scope="${2:-chat}"
  local f
  [[ "$scope" == "--global" || "$scope" == "global" ]] && f=$(_route_file_global) || f=$(_route_file_chat "$key")
  rm -f "$f"
}
