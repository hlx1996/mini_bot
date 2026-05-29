# plugins/code_search.sh — /code <keyword>  (GitHub code search)
# 走 api.github.com /search/code，需要 GITHUB_TOKEN（GitHub 强制要求登录）。

plugin_code_search() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/code <关键词>   例：/code asyncio.gather language:python"
    return 0
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    reply_text "$to" "❌ /code 需要 GITHUB_TOKEN（GitHub 代码搜索接口强制要登录）
请：
  1) https://github.com/settings/tokens 生成 fine-grained PAT
  2) 在 mini_bot 的 .env 加: GITHUB_TOKEN=ghp_xxx
  3) 重启 bot"
    return 0
  fi
  local q; q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rest")
  local j; j=$(curl -fsSL \
       -A "mini_bot/1.0" \
       -H "Authorization: Bearer ${GITHUB_TOKEN}" \
       -H "Accept: application/vnd.github+json" \
       "https://api.github.com/search/code?q=${q}&per_page=5") || {
    reply_text "$to" "❌ GitHub 代码搜索失败（token 权限不够？需要 'Code search' read 权限）"
    return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
items=d.get('items',[]) or []
print(f\"🔎 GitHub code search: total {d.get('total_count',0)}\")
print()
for it in items[:5]:
    print(f\"📄 {(it.get('repository') or {}).get('full_name','-')} :: {it.get('path','-')}\")
    print(f\"  🔗 {it.get('html_url','')}\")
")
  reply_text "$to" "$out"
}

register_command "/code" plugin_code_search "GitHub 代码搜索：/code <q>（需 GITHUB_TOKEN）"
