# plugins/npm.sh — /npm <pkg>
# registry.npmjs.org（免 key）。

plugin_npm() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/npm <package>   例：/npm express"
    return 0
  fi
  local p; p=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='@/'))" "$rest")
  local j; j=$(curl -fsSL --max-time 8 "https://registry.npmjs.org/${p}") || {
    reply_text "$to" "❌ 没找到 npm 包 '${rest}'"
    return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
latest=(d.get('dist-tags',{}) or {}).get('latest','-')
print(f\"📦 {d.get('name')}  v{latest}\")
print(f\"📝 {d.get('description','-')}\")
au=d.get('author') or {}
if isinstance(au, dict): au=au.get('name','-')
print(f\"👤 {au}\")
lic=d.get('license') or '-'
print(f\"🏷️ {lic}\")
print(f\"🔗 https://www.npmjs.com/package/{d.get('name')}\")
print(f\"📥 npm i {d.get('name')}\")
")
  reply_text "$to" "$out"
}

register_command "/npm" plugin_npm "npm 包信息：/npm <package>"
