#!/usr/bin/env bash
# plugins/browse.sh — /browse <url> [问题]  浏览器抓取（截图 + 文本）
#
# 默认 fresh-profile (无 cookie)；环境变量 USE_LOCAL_CHROME=1 改为附着到本机 Chrome：
#   1. 先用  /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
#         --remote-debugging-port=9222 --user-data-dir=$HOME/.chrome-debug   启动 Chrome
#      （也可以用普通 Chrome，但需要带 --remote-debugging-port=9222 启动）
#   2. export USE_LOCAL_CHROME=1
# 后台运行，不抢前台焦点。

plugin_browse() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/browse <url> [问题]
默认引擎：fresh-profile playwright（headless，无 cookie，不抢焦点）
本机 Chrome 模式（带 cookie）：export USE_LOCAL_CHROME=1，并提前用
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \\
      --remote-debugging-port=9222 --user-data-dir=~/.chrome-debug
启动 Chrome。
示例：
  /browse https://news.ycombinator.com
  /browse https://twitter.com/home 这页上 trending 是什么 (需 USE_LOCAL_CHROME)"
    return
  fi
  local url="${rest%% *}" question=""
  [[ "$rest" != "$url" ]] && question="${rest#* }"
  if [[ ! "$url" =~ ^https?:// ]]; then
    reply_text "$to" "❌ 第一个参数必须是 http(s):// 开头的 URL"; return
  fi
  command -v node >/dev/null 2>&1 || { reply_text "$to" "❌ 没装 node"; return; }
  [[ -d "$SCRIPT_DIR/node_modules/playwright" ]] || {
    reply_text "$to" "❌ playwright 未安装。请在 $SCRIPT_DIR 跑：
  npm install playwright && npx playwright install chromium"; return
  }
  local mode="fetch"
  [[ "${USE_LOCAL_CHROME:-}" == "1" ]] && mode="cdp"
  reply_text "$to" "🌐 浏览（mode=${mode}）：$url …"
  local shot txt
  shot=$(mktemp); shot="${shot}.png"
  txt=$(mktemp)
  ( cd "$SCRIPT_DIR" && node lib/browse.js \
      --mode "$mode" --url "$url" --screenshot "$shot" --text "$txt" \
      2>>"$LOG_DIR/browse.err" )
  local rc=$?
  if (( rc != 0 )); then
    local hint=""
    [[ "$mode" == "cdp" ]] && hint="
提示：检查 Chrome 是否带 --remote-debugging-port=9222 启动。"
    reply_text "$to" "❌ 浏览失败（rc=${rc}）$hint
$(tail -3 "$LOG_DIR/browse.err" 2>/dev/null)"
    rm -f "$shot" "$txt"; return
  fi
  # 发截图（失败也继续）
  if [[ -s "$shot" ]] && command -v reply_media >/dev/null 2>&1; then
    reply_media "$to" "$shot" 2>/dev/null || true
  fi
  # 让 qoder 总结/回答
  local body; body=$(head -c 20000 "$txt" 2>/dev/null)
  if [[ -n "$body" ]]; then
    local workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
    local model; model=$(model_for_key "$key")
    local prompt
    if [[ -n "$question" ]]; then
      prompt="阅读下面网页内容并回答：$question

网页正文：
$body"
    else
      prompt="给出这页的结构化摘要：一句话主旨 + 5 条要点。
网页正文：
$body"
    fi
    local ans
    ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || ans=""
    [[ -n "$ans" ]] && reply_text "$to" "$ans"
  fi
  rm -f "$shot" "$txt"
}

register_command "/browse" plugin_browse "浏览器抓取：/browse <url> [问题]"
