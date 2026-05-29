#!/usr/bin/env bash
# scripts/plugin-smoketest.sh — 静态 + 联网 smoke test for plugins/*.sh
#
# 用法: bash scripts/plugin-smoketest.sh [--no-net]
#
# 默认：
#   1. 对每个 plugins/*.sh 跑 bash -n 语法检查
#   2. 检查文件至少注册了一个命令
#   3. 检查处理函数签名注释（local to="$1" key="$2" rest="$3"）
#   4. 检查是否有 ${var}<CJK> 的潜在 bug 模式
#   5. 加 --net 时，对带 _smoke_test 的插件跑联网 ping（暂无插件实现）
#
# 退出码：0 全过；非 0 个数 = 失败数。

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS_DIR="${REPO_DIR}/plugins"
PLUGINS_EXTRA_DIR="${REPO_DIR}/plugins-extra"
FAIL=0
PASS=0
WARN=0

color() {
  case "$1" in
    g) printf "\033[32m%s\033[0m" "$2" ;;
    r) printf "\033[31m%s\033[0m" "$2" ;;
    y) printf "\033[33m%s\033[0m" "$2" ;;
    *) printf "%s" "$2" ;;
  esac
}

check_one() {
  local f="$1"
  local base; base=$(basename "$f" .sh)
  local errs=()

  # 1) 语法
  if ! bash -n "$f" 2>/tmp/smoke.err; then
    errs+=("SYNTAX: $(cat /tmp/smoke.err)")
  fi

  # 2) 注册命令
  if ! grep -q "register_command" "$f"; then
    errs+=("NO register_command")
  fi

  # 3) handler 签名
  if grep -E '^[[:space:]]*plugin_[a-z_]+\(\)' "$f" >/dev/null; then
    if ! grep -E 'local[[:space:]]+to="\$1"' "$f" >/dev/null; then
      errs+=("handler 未用 local to=\"\$1\"（可能签名不对）")
    fi
  fi

  # 4) CJK 紧跟 $var （bash 3.2 兼容性 + LANG 解析坑）
  if LC_ALL=C grep -nE '\$[a-zA-Z_][a-zA-Z0-9_]*[^[:space:][:print:]_${}/.,:;"#=)|\\-]' "$f" 2>/dev/null | LC_ALL=C grep -v 'register_command' >/dev/null; then
    WARN=$((WARN+1))
    color y "  ⚠️  CJK-after-\$var 模式，应用 \${var}写法" >&2; echo >&2
  fi

  if (( ${#errs[@]} > 0 )); then
    color r "✗ $base" ; echo
    for e in "${errs[@]}"; do echo "    $e"; done
    FAIL=$((FAIL+1))
  else
    color g "✓ $base"; echo
    PASS=$((PASS+1))
  fi
}

echo "=== mini_bot plugin smoke test ==="
echo "PLUGINS_DIR=$PLUGINS_DIR"
echo "PLUGINS_EXTRA_DIR=$PLUGINS_EXTRA_DIR"
echo
for f in "$PLUGINS_DIR"/*.sh; do
  [[ -f "$f" ]] || continue
  check_one "$f"
done
echo
echo "-- plugins-extra/ (opt-in) --"
for f in "$PLUGINS_EXTRA_DIR"/*.sh; do
  [[ -f "$f" ]] || continue
  check_one "$f"
done
echo
echo "Total: PASS=$PASS  FAIL=$FAIL  WARN=$WARN"

# 联网 ping（可选）
if [[ "${1:-}" != "--no-net" ]]; then
  echo
  echo "=== net reachability (5s timeout each) ==="
  for kv in \
    "api.github.com:https://api.github.com/zen" \
    "open.er-api.com:https://open.er-api.com/v6/latest/USD" \
    "wttr.in:https://wttr.in/?format=3" \
    "nominatim.openstreetmap.org:https://nominatim.openstreetmap.org/search?q=test&format=json&limit=1" \
    "api.openalex.org:https://api.openalex.org/works?per_page=1" \
    "en.wikipedia.org:https://en.wikipedia.org/api/rest_v1/page/summary/Earth" \
    "registry.npmjs.org:https://registry.npmjs.org/express" \
    "pypi.org:https://pypi.org/pypi/requests/json" \
    "hub.docker.com:https://hub.docker.com/v2/repositories/library/nginx/" \
    "api.dictionaryapi.dev:https://api.dictionaryapi.dev/api/v2/entries/en/hello" \
    "tinyurl.com:https://tinyurl.com/api-create.php?url=https://github.com" \
    "api.qrserver.com:https://api.qrserver.com/v1/create-qr-code/?data=x&size=50x50" \
    "noembed.com:https://noembed.com/embed?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  ; do
    host="${kv%%:*}"; url="${kv#*:}"
    code=$(curl -fsS -A "mini_bot/1.0" -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "ERR")
    if [[ "$code" =~ ^2 ]]; then
      color g "✓"; printf " %-35s %s\n" "$host" "$code"
    else
      color y "?"; printf " %-35s %s\n" "$host" "$code"
    fi
  done
fi

exit $FAIL
