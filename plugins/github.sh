# plugins/github.sh — /github <owner/repo|user|search keywords>
# 走 api.github.com（无 key 限速 60/hr，配 GITHUB_TOKEN 提升到 5000/hr）。

_gh_curl() {
  local url="$1"
  local ua="mini_bot/1.0 (+https://github.com/hlx1996/mini_bot)"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -A "$ua" -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -fsSL -A "$ua" -H "Accept: application/vnd.github+json" "$url"
  fi
}

plugin_github() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：
  /github owner/repo        仓库信息
  /github @user             用户信息
  /github <关键词>          搜索仓库（取 top 5）"
    return 0
  fi

  local out=""
  if [[ "$rest" == @* ]]; then
    local u="${rest#@}"
    local j; j=$(_gh_curl "https://api.github.com/users/${u}") || { reply_text "$to" "❌ 取不到用户 ${u}"; return 0; }
    out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print(f\"👤 {d.get('login')}  ({d.get('name') or '-'})\")
print(f\"🏢 {d.get('company') or '-'}  📍 {d.get('location') or '-'}\")
print(f\"📦 repos:{d.get('public_repos')}  👥 followers:{d.get('followers')}  following:{d.get('following')}\")
if d.get('bio'): print(f'📝 {d[\"bio\"]}')
print(f\"🔗 {d.get('html_url')}\")
")
  elif [[ "$rest" == */* && "$rest" != *' '* ]]; then
    local j; j=$(_gh_curl "https://api.github.com/repos/${rest}") || { reply_text "$to" "❌ 取不到仓库 ${rest}"; return 0; }
    out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print(f\"📦 {d.get('full_name')}\")
print(f\"⭐ {d.get('stargazers_count')}  🍴 {d.get('forks_count')}  🐛 {d.get('open_issues_count')}\")
print(f\"📝 {d.get('description') or '-'}\")
print(f\"🏷️  lang: {d.get('language') or '-'}  license: {(d.get('license') or {}).get('spdx_id') or '-'}\")
print(f\"📅 updated: {d.get('updated_at','')[:10]}\")
print(f\"🔗 {d.get('html_url')}\")
")
  else
    local q; q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rest")
    local j; j=$(_gh_curl "https://api.github.com/search/repositories?q=${q}&per_page=5") || { reply_text "$to" "❌ 搜索失败"; return 0; }
    out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
items=d.get('items',[])
if not items: print('（无结果）'); sys.exit()
for it in items[:5]:
    print(f\"📦 {it['full_name']}  ⭐{it['stargazers_count']}  {it.get('language') or ''}\")
    desc=(it.get('description') or '')[:120]
    if desc: print(f'  {desc}')
    print(f\"  🔗 {it['html_url']}\")
")
  fi
  [[ -z "$out" ]] && out="(空)"
  reply_text "$to" "$out"
}

register_command "/github" plugin_github "GitHub 查询：/github owner/repo | @user | <关键词>"
