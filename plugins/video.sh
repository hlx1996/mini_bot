#!/usr/bin/env bash
# plugins/video.sh — /video <prompt>  调用海螺 AI (hailuoai.video) 的网页 UI 生成视频。
#
# 实验性！海螺没有真正的免费 API tier，此插件用 playwright 自动化网页：
#   1. 必须先用本机 Chrome 登录 hailuoai.video（cookie 要保留）
#   2. 启动 Chrome 时带 --remote-debugging-port=9222 --user-data-dir=~/.chrome-debug
#   3. export USE_LOCAL_CHROME=1
# 生成时间通常 1-5 分钟，期间不影响你前台办公（后台 tab）。

plugin_video() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/video <prompt>
⚠️ 海螺 AI 视频生成（实验性）
准备：
  1) 启动 Chrome：
     '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \\
         --remote-debugging-port=9222 --user-data-dir=~/.chrome-debug
  2) 在 Chrome 里登录 https://hailuoai.video
  3) export USE_LOCAL_CHROME=1（mini_bot 进程里）
示例：/video 一只柴犬在沙滩上奔跑，电影感
另：MiniMax 官方付费 API 已支持，配置 MINIMAX_API_KEY 可改走官方通道（TODO）。"
    return
  fi
  if [[ "${USE_LOCAL_CHROME:-}" != "1" ]]; then
    reply_text "$to" "❌ 海螺生成需要使用本机已登录的 Chrome。请先：
  export USE_LOCAL_CHROME=1
并按 /video（不带参数）的提示启动 Chrome。"
    return
  fi
  command -v node >/dev/null 2>&1 || { reply_text "$to" "❌ 没装 node"; return; }
  [[ -d "$SCRIPT_DIR/node_modules/playwright" ]] || {
    reply_text "$to" "❌ playwright 未安装。在 $SCRIPT_DIR 跑：
  npm install playwright && npx playwright install chromium"; return
  }
  reply_text "$to" "🎬 提交到海螺并等待生成（最长 10 分钟，期间会保持后台运行）…
prompt: $rest"
  local out
  out=$( cd "$SCRIPT_DIR" && \
    HAILUO_PROMPT="$rest" HAILUO_TIMEOUT_SEC=600 \
    node lib/browse.js --mode script --js lib/hailuo_video.js \
    2>>"$LOG_DIR/browse.err" )
  local rc=$?
  if (( rc != 0 )); then
    reply_text "$to" "❌ 海螺自动化执行失败（rc=${rc}）
$(tail -3 "$LOG_DIR/browse.err" 2>/dev/null)"
    return
  fi
  local ok video_url err
  ok=$(printf '%s' "$out"      | python3 -c 'import sys,json; print(json.load(sys.stdin).get("ok",""))' 2>/dev/null)
  video_url=$(printf '%s' "$out"| python3 -c 'import sys,json; print(json.load(sys.stdin).get("videoUrl",""))' 2>/dev/null)
  err=$(printf '%s' "$out"     | python3 -c 'import sys,json; print(json.load(sys.stdin).get("error",""))' 2>/dev/null)
  if [[ "$ok" != "True" ]]; then
    reply_text "$to" "❌ 海螺生成失败：${err:-unknown}"
    return
  fi
  reply_text "$to" "✅ 视频已生成：
$video_url
（链接通常在海螺账号下保留若干天，正在下载并发送原文件…）"
  # 下载并发到聊天（保存到 IMAGE_DIR/video，便于事后查）
  local vdir="${IMAGE_DIR:-/tmp}/video"; mkdir -p "$vdir"
  local mp4="${vdir}/hailuo_$(date +%Y%m%d_%H%M%S)_${RANDOM}.mp4"
  if curl -fsSL --max-time 180 -o "$mp4" "$video_url" && [[ -s "$mp4" ]]; then
    local size; size=$(wc -c <"$mp4" | tr -d ' ')
    if (( size > 100*1024*1024 )); then
      reply_text "$to" "⚠️ 视频 ${size} bytes 超过 100MB，未上传原文件（仅链接）"
    else
      reply_media "$to" "$mp4" "🎞️ 海螺生成（$(numfmt --to=iec ${size} 2>/dev/null || echo ${size}B)）"
    fi
  else
    reply_text "$to" "⚠️ 视频下载失败，请点上面链接查看"
  fi
}

register_command "/video"   plugin_video "海螺 AI 视频（实验，需本机 Chrome 登录）：/video <prompt>"
