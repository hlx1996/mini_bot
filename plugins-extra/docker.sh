# plugins/docker.sh — /docker <image>
# Docker Hub registry-1.docker.io public API（免 key）。

plugin_docker() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/docker <image>   例：/docker nginx 或 /docker library/python"
    return 0
  fi
  local img="$rest"
  [[ "$img" != */* ]] && img="library/${img}"
  local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$img")
  local j; j=$(curl -fsSL --max-time 8 "https://hub.docker.com/v2/repositories/${enc}/") || {
    reply_text "$to" "❌ 没找到镜像 '${rest}'"
    return 0
  }
  # 拿前 5 个 tag
  local tags; tags=$(curl -fsSL --max-time 8 "https://hub.docker.com/v2/repositories/${enc}/tags/?page_size=5" 2>/dev/null)
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print(f\"🐳 {d.get('namespace')}/{d.get('name')}\")
print(f\"⭐ {d.get('star_count',0)}  📥 pulls: {d.get('pull_count',0):,}\")
desc=(d.get('description') or '').strip() or '-'
print(f\"📝 {desc[:200]}\")
print(f\"🔗 https://hub.docker.com/r/{d.get('namespace')}/{d.get('name')}\")
print(f\"📥 docker pull {d.get('namespace') if d.get('namespace')!='library' else ''}{'/' if d.get('namespace')!='library' else ''}{d.get('name')}\")
")
  local tag_lines=""
  if [[ -n "$tags" ]]; then
    tag_lines=$(printf '%s' "$tags" | python3 -c "
import sys, json
try:
  d=json.load(sys.stdin)
  rs=d.get('results',[]) or []
  if rs:
    print('🏷️ 最近 tags:')
    for t in rs[:5]:
      print(f\"  - {t.get('name')}  ({(t.get('last_updated') or '')[:10]})\")
except: pass
")
  fi
  reply_text "$to" "$out
$tag_lines"
}

register_command "/docker" plugin_docker "Docker Hub 镜像信息：/docker <image>"
