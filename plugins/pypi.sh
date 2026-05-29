# plugins/pypi.sh — /pypi <pkg>
# pypi.org JSON API（免 key）。

plugin_pypi() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/pypi <package>   例：/pypi requests"
    return 0
  fi
  local p; p=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rest")
  local j; j=$(curl -fsSL --max-time 8 "https://pypi.org/pypi/${p}/json") || {
    reply_text "$to" "❌ 没找到包 '${rest}'"
    return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
info=d.get('info',{}) or {}
print(f\"📦 {info.get('name')} {info.get('version','-')}\")
sum_=info.get('summary') or '-'
print(f\"📝 {sum_}\")
au=info.get('author') or info.get('author_email') or '-'
print(f\"👤 {au}\")
lic=info.get('license') or '-'
print(f\"🏷️ {lic}\")
hp=info.get('home_page') or info.get('project_url') or ''
print(f\"🔗 {hp}\")
print(f\"📥 pip install {info.get('name')}\")
")
  reply_text "$to" "$out"
}

register_command "/pypi" plugin_pypi "PyPI 包信息：/pypi <package>"
