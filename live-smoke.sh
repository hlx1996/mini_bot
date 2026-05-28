#!/usr/bin/env bash
# live-smoke.sh — end-to-end smoke test for mini_bot using stubs for qoder/wxlink/lark.
# Verifies: multi-platform dispatch, /cwd, URL-fetch, /cron addto, /agent, /team, /automem.
# Idempotent; uses a temp BOT_HOME so it does not touch real state.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_SH="$SCRIPT_DIR/bot.sh"
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# ---- stubs ----
mkdir -p "$TMP/bin" "$TMP/state"

cat > "$TMP/bin/qoder-stub.sh" <<'EOF'
#!/usr/bin/env bash
prompt=""
for ((i=0;i<$#;i++)); do j=$((i+1)); arg=${!i:-}; nxt=${!j:-}; [[ "$arg" == "-p" ]] && prompt="$nxt"; done
# also scan all args
for ((i=1;i<=$#;i++)); do
  a="${!i}"
  if [[ "$a" == "-p" ]]; then
    j=$((i+1)); prompt="${!j}"; break
  fi
done
if [[ "$prompt" == *intent* && "$prompt" == *JSON* ]]; then
  echo '{"intent":"chat","args":""}'
elif [[ "$prompt" == *crontab*  || "$prompt" == *cron-expression*generator* ]]; then
  echo '{"cron":"0 9 * * *","task":"喝水"}'
elif [[ "$prompt" == *memory\ extractor* ]]; then
  echo "user likes hot pot
user is working on mini_bot project"
elif [[ "$prompt" == *"You are role:"* ]]; then
  role=$(echo "$prompt" | sed -n 's/.*You are role: \([a-z_-]*\).*/\1/p')
  echo "[stub:$role] reply for: ${prompt:0:60}"
else
  echo "STUB-REPLY: ${prompt:0:60}"
fi
EOF
chmod +x "$TMP/bin/qoder-stub.sh"

cat > "$TMP/bin/wxlink-stub.py" <<'EOF'
#!/usr/bin/env python3
import sys, json, time, argparse, os
ap = argparse.ArgumentParser()
ap.add_argument("--account", default="default")
sub = ap.add_subparsers(dest="cmd")
st = sub.add_parser("send-text"); st.add_argument("--to"); st.add_argument("--text")
sm = sub.add_parser("send-media"); sm.add_argument("--to"); sm.add_argument("--file"); sm.add_argument("--caption", default="")
sb = sub.add_parser("subscribe");  sb.add_argument("--download-dir", default="")
args = ap.parse_args()
log_path = os.environ.get("SMOKE_SENTLOG", "/tmp/minibot-smoke-sent.log")
if args.cmd == "send-text":
    with open(log_path, "a") as f:
        f.write(f"{time.strftime('%H:%M:%S')} [{args.account}] text {args.to} :: {args.text}\n")
    print(json.dumps({"ok": True}))
elif args.cmd == "send-media":
    with open(log_path, "a") as f:
        f.write(f"{time.strftime('%H:%M:%S')} [{args.account}] media {args.to} :: {args.file}\n")
    print(json.dumps({"ok": True}))
elif args.cmd == "subscribe":
    # do nothing (we feed events via --simulate)
    time.sleep(1)
EOF
chmod +x "$TMP/bin/wxlink-stub.py"

cat > "$TMP/bin/lark-cli" <<'EOF'
#!/usr/bin/env bash
echo "lark-cli: $*" >> /tmp/minibot-smoke-lark.log
echo '{"code":0,"data":{"message_id":"om_x"}}'
EOF
chmod +x "$TMP/bin/lark-cli"

cat > "$TMP/bin/crontab" <<'EOF'
#!/usr/bin/env bash
F="$BOT_HOME/.crontab"
case "$1" in
  -l) cat "$F" 2>/dev/null ;;
  -)  cat > "$F" ;;
  *)  echo "stub" ;;
esac
EOF
chmod +x "$TMP/bin/crontab"

# accounts.list
cat > "$TMP/state/accounts.list" <<EOF
wechat:acct1
lark:bot   cat   lite
EOF

export PATH="$TMP/bin:$PATH"
export BOT_HOME="$TMP/state"
export QODER_BIN="$TMP/bin/qoder-stub.sh"
export WXLINK_BIN="$TMP/bin/wxlink-stub.py"
export SMOKE_SENTLOG="$TMP/sent.log"

PASS=0; FAIL=0
expect() {
  local desc="$1" pattern="$2" file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ $desc"; PASS=$((PASS+1))
  else
    echo "  ❌ $desc  (expected /$pattern/ in $file)"
    [[ -f "$file" ]] && sed 's/^/      | /' "$file" | tail -5
    FAIL=$((FAIL+1))
  fi
}

simulate() {
  bash "$BOT_SH" --simulate "$1" >/dev/null 2>"$TMP/run.err" || true
  # accumulate stderr across invocations for log-grep tests
  cat "$TMP/run.err" >> "$TMP/all.err"
}

echo "== Test 1: WeChat text =="
simulate '{"type":"message","platform":"wechat","id":"t1","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"hello","media":[]}'
expect "wechat reply sent" "STUB-REPLY: hello" "$SMOKE_SENTLOG"

echo "== Test 2: Lark text → lark-cli reply =="
> /tmp/minibot-smoke-lark.log
simulate '{"type":"message","platform":"lark","id":"om_2","from":"oc_2","from_name":"b","chat_type":"direct","account_id":"bot","account_name":"bot","text":"hi lark","media":[],"reply_to":"om_2"}'
expect "lark reply via lark-cli" "lark-cli: api POST /open-apis/im/v1/messages/om_2/reply" /tmp/minibot-smoke-lark.log

echo "== Test 3: URL-fetch shortcut =="
simulate '{"type":"message","platform":"wechat","id":"t3","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"summarize https://example.com please","media":[]}'
expect "URL-fetch injected" "URL-FETCH injected" "$TMP/all.err"

echo "== Test 4: /cwd command =="
mkdir -p "$TMP/myproj" && echo "hello" > "$TMP/myproj/README.md"
simulate "$(jq -nc --arg p "$TMP/myproj" '{type:"message",platform:"wechat",id:"t4",from:"wxid_a",from_name:"a",chat_type:"direct",account_id:"acct1",account_name:"acct1",text:"/cwd \($p)",media:[]}')"
expect "/cwd reply" "工作目录已切换到：$TMP/myproj" "$SMOKE_SENTLOG"
# next turn → qoder should run with cwd=that dir
simulate '{"type":"message","platform":"wechat","id":"t4b","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"what is here","media":[]}'
expect "qoder NEW used /cwd" "qoder (NEW|RESUME) .*cwd=$TMP/myproj" "$TMP/all.err"

echo "== Test 5: /cron addto cross-chat =="
simulate '{"type":"message","platform":"wechat","id":"t5","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/cron addto lark:bot:oc_z \"0 9 * * *\" daily standup","media":[]}'
expect "/cron addto registered" "已添加跨会话定时" "$SMOKE_SENTLOG"
expect "cron line written to stub crontab" "wxcron:" "$BOT_HOME/.crontab"

echo "== Test 6: /agent sub-agent =="
simulate '{"type":"message","platform":"wechat","id":"t6","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/agent researcher 给我一份LLM最新进展","media":[]}'
expect "agent reply contains [researcher]" "researcher" "$SMOKE_SENTLOG"

echo "== Test 7: /team set + run =="
simulate '{"type":"message","platform":"wechat","id":"t7a","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/team set researcher critic editor","media":[]}'
simulate '{"type":"message","platform":"wechat","id":"t7b","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/team run 写一段关于猫的诗","media":[]}'
expect "team pipeline runs researcher" "researcher" "$SMOKE_SENTLOG"
expect "team pipeline runs editor" "editor" "$SMOKE_SENTLOG"

echo "== Test 8: /automem extracts facts =="
simulate '{"type":"message","platform":"wechat","id":"t8a","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/automem on","media":[]}'
simulate '{"type":"message","platform":"wechat","id":"t8b","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"I love hot pot and I am building mini_bot","media":[]}'
sleep 3   # automem runs in background
# Scan all memory files for an extracted fact
found_mem=0
for f in "$BOT_HOME"/memory/*.txt; do
  [[ -e "$f" ]] || continue
  if grep -qE "(hot pot|mini_bot)" "$f"; then found_mem=1; fi
done
if [[ $found_mem -eq 1 ]]; then echo "  ✅ memory has automem fact"; PASS=$((PASS+1)); else echo "  ❌ no automem fact found"; FAIL=$((FAIL+1)); fi

echo "== Test 9: /backup create + list =="
# bootstrap admin (first /admin add) — must use the same wxid_a who is the sender
simulate '{"type":"message","platform":"wechat","id":"t9adm","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/admin add wxid_a","media":[]}'
simulate '{"type":"message","platform":"wechat","id":"t9","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/backup create","media":[]}'
expect "backup file produced" "mini_bot-all-.*\\.tar\\.gz" "$SMOKE_SENTLOG"
backup_count=$(ls "$BOT_HOME/../backups" 2>/dev/null | grep -c '\.tar\.gz' || true)
if [[ ${backup_count:-0} -ge 1 ]]; then echo "  ✅ backup archive exists on disk"; PASS=$((PASS+1)); else
  # fallback: backup.sh writes to $BOT_HOME/backups by default (which is $TMP/state/backups)
  bc2=$(ls "$BOT_HOME/backups" 2>/dev/null | grep -c '\.tar\.gz' || true)
  if [[ ${bc2:-0} -ge 1 ]]; then echo "  ✅ backup archive exists on disk"; PASS=$((PASS+1)); else echo "  ❌ no archive in backups/"; FAIL=$((FAIL+1)); fi
fi

echo "== Test 10: /card lark card =="
> /tmp/minibot-smoke-lark.log
simulate '{"type":"message","platform":"lark","id":"om_10","from":"oc_g","from_name":"u","chat_type":"group","account_id":"bot","account_name":"bot","text":"/card 标题|内容 *粗体*","media":[],"reply_to":"om_10"}'
expect "lark card msg_type=interactive" "msg_type.*interactive" /tmp/minibot-smoke-lark.log

echo "== Test 11: Lark group @ mention back =="
> /tmp/minibot-smoke-lark.log
simulate '{"type":"message","platform":"lark","id":"om_11","from":"oc_grp","from_open_id":"ou_user11","from_name":"u","chat_type":"group","account_id":"bot","account_name":"bot","text":"hi","mentioned":true,"media":[],"reply_to":"om_11"}'
expect "lark reply contains @mention" "at user_id" /tmp/minibot-smoke-lark.log

echo "== Test 12: backup.sh export/import roundtrip =="
exp=$(BOT_HOME="$BOT_HOME/.." STATE_DIR="$BOT_HOME" BAK_DIR="$TMP/bk2" bash "$SCRIPT_DIR/backup.sh" export 2>&1 | tail -1)
if [[ -f "$exp" ]]; then echo "  ✅ backup.sh export produced $exp"; PASS=$((PASS+1)); else echo "  ❌ no archive: $exp"; FAIL=$((FAIL+1)); fi
# extract elsewhere
mkdir -p "$TMP/restore_target"
( cd "$TMP/restore_target" && tar tzf "$exp" >/dev/null )
if [[ $? -eq 0 ]]; then echo "  ✅ archive is a valid tar.gz"; PASS=$((PASS+1)); else echo "  ❌ tar listing failed"; FAIL=$((FAIL+1)); fi

echo "== Test 13: web auth (MINIBOT_USER set) =="
WEB_PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
MINIBOT_USER=admin MINIBOT_PASS=secret BOT_HOME="$BOT_HOME" \
  python3 "$SCRIPT_DIR/web.py" --port "$WEB_PORT" --host 127.0.0.1 >/dev/null 2>&1 &
WPID=$!
sleep 1
code_noauth=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEB_PORT/api/status" || echo 0)
code_auth=$(curl -s -o /dev/null -w '%{http_code}' -u admin:secret "http://127.0.0.1:$WEB_PORT/api/status" || echo 0)
kill $WPID 2>/dev/null || true
if [[ "$code_noauth" == "401" ]]; then echo "  ✅ web rejects no-auth (401)"; PASS=$((PASS+1)); else echo "  ❌ expected 401, got $code_noauth"; FAIL=$((FAIL+1)); fi
if [[ "$code_auth" == "200" ]]; then echo "  ✅ web accepts valid creds (200)"; PASS=$((PASS+1)); else echo "  ❌ expected 200, got $code_auth"; FAIL=$((FAIL+1)); fi

echo "== Test 14: /usage command =="
simulate '{"type":"message","platform":"wechat","id":"t14","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/usage day","media":[]}'
expect "/usage produces report" "(总计|按账号)" "$SMOKE_SENTLOG"

echo "== Test 15: /lang en switch =="
simulate '{"type":"message","platform":"wechat","id":"t15a","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/lang en","media":[]}'
expect "/lang en confirms" "(English|Language set)" "$SMOKE_SENTLOG"
simulate '{"type":"message","platform":"wechat","id":"t15b","from":"wxid_a","from_name":"a","chat_type":"direct","account_id":"acct1","account_name":"acct1","text":"/help","media":[]}'
expect "/help in English" "mini_bot — commands" "$SMOKE_SENTLOG"

echo "== Test 16: OAuth mock login =="
WEB_PORT2=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
MINIBOT_GH_CLIENT_ID=mock MINIBOT_GH_CLIENT_SECRET=mock MINIBOT_OAUTH_MOCK=1 \
  MINIBOT_OAUTH_MOCK_USER=hlx1996 MINIBOT_GH_ALLOWED_USERS=hlx1996 BOT_HOME="$BOT_HOME" \
  python3 "$SCRIPT_DIR/web.py" --port "$WEB_PORT2" --host 127.0.0.1 >/dev/null 2>&1 &
WPID2=$!
sleep 1
# unauth -> 302 to /login
c1=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEB_PORT2/api/status" || echo 0)
# /oauth/callback returns 302 with Set-Cookie
hdrs=$(curl -s -i "http://127.0.0.1:$WEB_PORT2/oauth/callback?code=fake" 2>&1)
cookie=$(echo "$hdrs" | awk -F': ' '/^[Ss]et-[Cc]ookie:/{print $2}' | head -1 | cut -d';' -f1)
c2=$(curl -s -o /dev/null -w '%{http_code}' --cookie "$cookie" "http://127.0.0.1:$WEB_PORT2/api/status" || echo 0)
kill $WPID2 2>/dev/null || true
if [[ "$c1" == "302" ]]; then echo "  ✅ unauth redirected (302)"; PASS=$((PASS+1)); else echo "  ❌ expected 302, got $c1"; FAIL=$((FAIL+1)); fi
if [[ -n "$cookie" && "$c2" == "200" ]]; then echo "  ✅ mock-OAuth cookie grants access (200)"; PASS=$((PASS+1)); else echo "  ❌ oauth-cookie failed: cookie='$cookie' code=$c2"; FAIL=$((FAIL+1)); fi

echo
echo "============================================"
echo " PASS: $PASS    FAIL: $FAIL"
echo "============================================"
exit $(( FAIL > 0 ? 1 : 0 ))
