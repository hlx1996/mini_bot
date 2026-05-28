# lib/bridge.sh — cross-platform contact book + send + 2-way bridge.
#
# Storage:
#   $BOT_HOME/contacts.tsv         named contacts:   name\tplatform\taccount\tpeer_id
#   $BOT_HOME/contacts_seen.tsv    auto-cache of last-seen senders (rolling 200)
#   $BOT_HOME/bridges.tsv          active 2-way bridges: keyA\tkeyB
#                                  (key = "<platform>:<account>:<peer_id>")
#
# A bridge entry binds two chat_keys. When handle_event sees a message from a
# bridged key, it relays the text to the other side instead of running qoder.

_CONTACTS_FILE() { echo "$BOT_HOME/contacts.tsv"; }
_SEEN_FILE()     { echo "$BOT_HOME/contacts_seen.tsv"; }
_BRIDGES_FILE()  { echo "$BOT_HOME/bridges.tsv"; }

contact_remember() {
  # contact_remember <platform> <account> <peer_id> <display_name>
  local plat="$1" acct="$2" pid="$3" name="${4:-}"
  local f; f=$(_SEEN_FILE)
  mkdir -p "$(dirname "$f")"
  # dedup by (plat,acct,pid); keep last 200
  "$PYTHON_BIN" - "$f" "$plat" "$acct" "$pid" "$name" <<'PY'
import sys, os, time
f, plat, acct, pid, name = sys.argv[1:6]
key = f"{plat}\t{acct}\t{pid}"
rows = []
if os.path.exists(f):
    for ln in open(f, encoding="utf-8", errors="ignore"):
        ln = ln.rstrip("\n")
        if not ln: continue
        parts = ln.split("\t")
        if len(parts) < 4: continue
        rk = "\t".join(parts[:3])
        if rk == key: continue
        rows.append(parts)
rows.append([plat, acct, pid, name, str(int(time.time()))])
rows = rows[-200:]
with open(f, "w", encoding="utf-8") as w:
    for r in rows:
        w.write("\t".join(r) + "\n")
PY
}

contact_recent() {
  # Print last N seen contacts (default 10), newest first
  local n="${1:-10}" f; f=$(_SEEN_FILE)
  [[ -f "$f" ]] || { echo "(暂无 recent)"; return; }
  # `tac` is GNU-only; macOS has `tail -r`. Fall back to awk for portability.
  if command -v tac >/dev/null 2>&1; then
    tail -n "$n" "$f" | tac | awk -F'\t' '{printf "  %s:%s:%s  (%s)\n", $1,$2,$3,$4}'
  else
    tail -n "$n" "$f" | awk -F'\t' '
      {a[NR]=$0}
      END {for(i=NR;i>=1;i--){split(a[i],p,"\t"); printf "  %s:%s:%s  (%s)\n", p[1],p[2],p[3],p[4]}}'
  fi
}

contact_last_seen() {
  # Echo the most recent peer triple "platform\taccount\tpeer_id"
  local f; f=$(_SEEN_FILE)
  [[ -f "$f" ]] || return 1
  tail -n 1 "$f" | awk -F'\t' '{printf "%s\t%s\t%s\n", $1,$2,$3}'
}

contact_add() {
  # contact_add <name> <platform> <account> <peer_id>
  local name="$1" plat="$2" acct="$3" pid="$4"
  [[ -z "$name" || -z "$plat" || -z "$pid" ]] && return 1
  acct="${acct:-default}"
  local f; f=$(_CONTACTS_FILE); mkdir -p "$(dirname "$f")"
  "$PYTHON_BIN" - "$f" "$name" "$plat" "$acct" "$pid" <<'PY'
import sys, os
f, name, plat, acct, pid = sys.argv[1:6]
rows = []
if os.path.exists(f):
    for ln in open(f, encoding="utf-8", errors="ignore"):
        ln = ln.rstrip("\n")
        if not ln: continue
        parts = ln.split("\t")
        if parts and parts[0] == name: continue
        rows.append(ln)
rows.append("\t".join([name, plat, acct, pid]))
open(f, "w", encoding="utf-8").write("\n".join(rows) + "\n")
PY
}

contact_get() {
  # Echo "platform\taccount\tpeer_id" for <name>, empty if missing.
  local name="$1" f; f=$(_CONTACTS_FILE)
  [[ -f "$f" ]] || return 1
  awk -F'\t' -v n="$name" '$1==n {printf "%s\t%s\t%s\n",$2,$3,$4; found=1; exit} END{exit !found}' "$f"
}

contact_rm() {
  local name="$1" f; f=$(_CONTACTS_FILE)
  [[ -f "$f" ]] || return 0
  "$PYTHON_BIN" - "$f" "$name" <<'PY'
import sys, os
f, name = sys.argv[1], sys.argv[2]
rows = [ln.rstrip("\n") for ln in open(f, encoding="utf-8", errors="ignore") if ln.strip()]
rows = [r for r in rows if r.split("\t")[0] != name]
open(f, "w", encoding="utf-8").write(("\n".join(rows) + "\n") if rows else "")
PY
}

contact_list() {
  local f; f=$(_CONTACTS_FILE)
  [[ -f "$f" ]] || { echo "(暂无昵称)"; return; }
  awk -F'\t' '{printf "  %-16s → %s:%s:%s\n", $1,$2,$3,$4}' "$f"
}

contact_lookup_name() {
  # contact_lookup_name <platform> <account> <peer_id>  → echo name (or empty)
  local plat="$1" acct="$2" pid="$3" f; f=$(_CONTACTS_FILE)
  [[ -f "$f" ]] || return 1
  awk -F'\t' -v p="$plat" -v a="$acct" -v i="$pid" \
    '$2==p && $3==a && $4==i {print $1; found=1; exit} END{exit !found}' "$f"
}

# bridge_send <name> <text>  — direct message to a contact via the right platform.
bridge_send() {
  local name="$1" text="$2"
  local trip; trip=$(contact_get "$name") || return 1
  local plat acct pid
  plat=$(echo "$trip" | cut -f1); acct=$(echo "$trip" | cut -f2); pid=$(echo "$trip" | cut -f3)
  G_PLATFORM="$plat" G_ACCOUNT_NAME="$acct" reply_text "$pid" "$text"
}

# ---------------- 2-way bridges ----------------

bridge_pair() {
  # bridge_pair <keyA> <keyB>  — keys are full "<platform>:<account>:<peer_id>"
  local a="$1" b="$2" f; f=$(_BRIDGES_FILE); mkdir -p "$(dirname "$f")"
  "$PYTHON_BIN" - "$f" "$a" "$b" <<'PY'
import sys, os
f, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
rows = set()
if os.path.exists(f):
    for ln in open(f, encoding="utf-8", errors="ignore"):
        ln = ln.strip()
        if not ln: continue
        x, y = (ln.split("\t") + [""])[:2]
        if {x, y} == {a, b}: continue  # remove pre-existing same pair
        rows.add((x, y))
rows.add((a, b))
open(f, "w", encoding="utf-8").write("\n".join(f"{x}\t{y}" for x, y in rows) + "\n")
PY
}

bridge_unpair() {
  # bridge_unpair <key>  — remove ALL bridges touching <key>
  local k="$1" f; f=$(_BRIDGES_FILE)
  [[ -f "$f" ]] || return 0
  "$PYTHON_BIN" - "$f" "$k" <<'PY'
import sys, os
f, k = sys.argv[1], sys.argv[2]
rows = []
for ln in open(f, encoding="utf-8", errors="ignore"):
    ln = ln.strip()
    if not ln: continue
    parts = ln.split("\t")
    if k in parts: continue
    rows.append(ln)
open(f, "w", encoding="utf-8").write(("\n".join(rows) + "\n") if rows else "")
PY
}

bridge_peer_of() {
  # bridge_peer_of <key>  → echo the OTHER key bridged to <key>, empty if none.
  local k="$1" f; f=$(_BRIDGES_FILE)
  [[ -f "$f" ]] || return 1
  awk -F'\t' -v k="$k" '
    $1==k {print $2; f=1; exit}
    $2==k {print $1; f=1; exit}
    END {exit !f}
  ' "$f"
}

bridge_list() {
  local f; f=$(_BRIDGES_FILE)
  [[ -f "$f" ]] || { echo "(暂无桥接)"; return; }
  awk -F'\t' '{printf "  %s  ⇄  %s\n", $1, $2}' "$f"
}

# Helper used by bot.sh: given platform/account/peer_id, build the chat key string.
bridge_key() {
  printf '%s:%s:%s' "$1" "$2" "$3"
}
