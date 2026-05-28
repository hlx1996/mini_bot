#!/usr/bin/env bash
# plugins/diagram.sh — /diagram <prompt> 让 qoder 生成 mermaid，渲染成 PNG 发回。
# 无依赖：用 mermaid.ink 公网渲染服务（GET 一个 URL 拿 PNG，等同于本地 mmdc）。

_diagram_render_url() {
  # 把 mermaid 源码 URL-safe base64 编码后塞进 mermaid.ink URL
  local mmd="$1"
  local b64
  b64=$(printf '%s' "$mmd" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
  printf 'https://mermaid.ink/img/%s?type=png' "$b64"
}

plugin_diagram() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/diagram <想画的图>
示例：
  /diagram 用户从前端发请求到后端 + redis 缓存的时序图
  /diagram 自动驾驶感知→规划→控制的模块依赖关系
  /diagram mermaid: 直接给 mermaid 源码也行
工具：默认调 qoder 把自然语言变 mermaid，再 GET mermaid.ink 拿 PNG。"
    return
  fi

  local mmd
  if [[ "$rest" == mermaid:* ]]; then
    mmd="${rest#mermaid:}"; mmd="${mmd# }"
  else
    # 用 qoder 生成 mermaid（要求纯代码，不带 fence）
    reply_text "$to" "📐 生成 diagram 中…"
    local workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
    local model; model=$(model_for_key "$key")
    local prompt
    prompt="把下面的需求转成 mermaid 图（flowchart/sequenceDiagram/classDiagram/erDiagram 任选）。
只输出 mermaid 源码本体，不要 \`\`\` fence、不要解释、不要 'mermaid' 前缀。
需求：$rest"
    mmd=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null) || mmd=""
    # 清理：去掉 ``` fence、首尾空行
    mmd=$(printf '%s' "$mmd" | sed -E '/^[[:space:]]*```/d; /^[[:space:]]*mermaid[[:space:]]*$/d')
  fi
  if [[ -z "$mmd" ]]; then
    reply_text "$to" "❌ 没拿到 mermaid 源码"; return
  fi

  local png_tmp; png_tmp=$(mktemp)
  local png="${png_tmp}.png"; mv "$png_tmp" "$png" 2>/dev/null || png="$png_tmp"
  local url; url=$(_diagram_render_url "$mmd")
  local code
  code=$(curl -sSL --max-time 30 -o "$png" -w '%{http_code}' "$url" 2>/dev/null)
  if [[ "$code" != "200" || ! -s "$png" ]]; then
    reply_text "$to" "❌ mermaid.ink 渲染失败（HTTP $code）。源码：
$mmd"
    rm -f "$png"
    return
  fi
  # 尝试发图；失败（如 lark 用户身份缺 im:resource:upload）就回退到 URL
  local sent=0
  if command -v reply_media >/dev/null 2>&1; then
    reply_media "$to" "$png" 2>/dev/null && sent=1
  fi
  if (( sent == 0 )); then
    reply_text "$to" "🖼 已渲染（点击查看大图）：
$url

mermaid 源码：
$mmd"
  fi
  rm -f "$png"
}

register_command "/diagram" plugin_diagram "画图：/diagram <需求>（自然语言转 mermaid + 渲染 PNG）"
register_command "/画图"     plugin_diagram "画图：/画图 <需求>"
