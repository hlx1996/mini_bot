#!/usr/bin/env bash
BOT="ou_e3c30f75c519fbf6644816e577d15dfe"
EVT=~/Projects/mini_bot/state/logs/events.jsonl

send() {
  local txt="$1"
  lark-cli im +messages-send --as user --user-id "$BOT" --text "$txt" >/dev/null 2>&1
}

wait_for_n_replies() {
  local target="$1" timeout="${2:-30}" base="$3"
  local i=0 cur
  while (( i < timeout )); do
    cur=$(tail -n +$((base+1)) "$EVT" | grep -c '"kind":"reply"')
    (( cur >= target )) && return 0
    sleep 1; i=$((i+1))
  done
  return 1
}

run_test() {
  local name="$1" msg="$2" expect_replies="${3:-1}" timeout="${4:-30}"
  local base; base=$(wc -l < "$EVT")
  send "$msg"
  wait_for_n_replies "$expect_replies" "$timeout" "$base" || true
  local got
  got=$(tail -n +$((base+1)) "$EVT" | jq -c 'select(.kind=="reply") | {ok, text:(.text//"")[:140]}' | head -$expect_replies)
  echo "── $name ──"
  echo "  sent: $msg"
  echo "  replies ($expect_replies expected):"
  echo "$got" | sed 's/^/    /'
  if [[ -z "$got" ]]; then
    echo "    ❌ NO REPLY"
  fi
  echo
}

echo "=========================================="
echo " mini_bot — Feishu full sweep $(date +%H:%M:%S)"
echo "=========================================="
run_test "01 /reset"         "/reset"                       1  10
run_test "02 simple Q&A"     "用一个词形容今天的天气"       1  30
run_test "03 /soul list"     "/soul list"                   1  10
run_test "04 /memory add"    "/memory add 我喜欢喝拿铁"     1  10
run_test "05 /memory show"   "/memory"                      1  10
run_test "06 /skill list"    "/skill list"                  1  10
run_test "07 /status"        "/status"                      1  10
run_test "08 /lang en"       "/lang en"                     1  10
run_test "09 /help (en)"     "/help"                        1  10
run_test "10 /lang zh"       "/lang zh"                     1  10
run_test "11 /mcp list"      "/mcp"                         1  10
run_test "12 /cron list"     "/cron list"                   1  10
run_test "13 /rag list"      "/rag list"                    1  10
run_test "14 /usage day"     "/usage day"                   1  10
run_test "15 /quota show"    "/quota"                       1  10
run_test "16 /url status"    "/url"                         1  10
run_test "17 /stream status" "/stream"                      1  10
run_test "18 /automem"       "/automem"                     1  10
run_test "19 /agent"         "/agent default 一句话介绍量子计算"  1  60
run_test "20 URL fetch"      "用一句话总结：https://example.com" 1  35
run_test "21 /stream on"     "/stream on"                   1  10
run_test "22 streaming Q"    "用一句话告诉我 3+4 等于多少"  2  45
run_test "23 /stream off"    "/stream off"                  1  10
run_test "24 /tts on"        "/tts on"                      1  10
run_test "25 TTS reply"      "请说『你好』"                 2  40
run_test "26 /tts off"       "/tts off"                     1  10
