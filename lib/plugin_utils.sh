# lib/plugin_utils.sh — 给 plugins/*.sh 用的共享小工具
# 命名约定：所有公开函数以 pu_ 前缀。
#
# 用法（插件文件里）：
#   command -v pu_url_encode >/dev/null 2>&1 || source "$SCRIPT_DIR/lib/plugin_utils.sh"
# 但 bot.sh 启动时已 source 本文件，所以插件直接调用即可。

# ----- URL & JSON 小工具 -----

pu_url_encode() {
  # pu_url_encode <text>  → 输出 percent-encoded 字符串
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

pu_url_encode_path() {
  # 保留 / 与 @
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe="/@"))' "$1"
}

pu_json_get() {
  # pu_json_get <json-string> <key1.key2.key3>  支持 a.b.0.c
  python3 -c '
import sys, json
d = json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    if isinstance(d, list):
        try: d = d[int(k)]
        except: d = None; break
    elif isinstance(d, dict):
        d = d.get(k)
    else:
        d = None; break
    if d is None: break
print("" if d is None else (d if isinstance(d, str) else json.dumps(d, ensure_ascii=False)))
' "$1" "$2"
}

# ----- HTTP -----

pu_http_get() {
  # pu_http_get <url> [timeout=8]  → stdout 是 body，rc != 0 表示失败
  local url="$1" t="${2:-8}"
  curl -fsSL --max-time "$t" -A "mini_bot/1.0 (+https://github.com/hlx1996/mini_bot)" "$url"
}

pu_http_get_retry() {
  # pu_http_get_retry <url> [max=3] [timeout=8]
  local url="$1" max="${2:-3}" t="${3:-8}" i=0 out=""
  while (( i < max )); do
    out=$(pu_http_get "$url" "$t") && { printf '%s' "$out"; return 0; }
    i=$((i+1))
    sleep 1
  done
  return 1
}

# ----- 文本工具 -----

pu_truncate() {
  # pu_truncate <text> [maxbytes=3500] [marker]
  local s="$1" max="${2:-3500}" marker="${3:-…(截断)}"
  if (( ${#s} > max )); then
    printf '%s\n%s' "${s:0:max}" "$marker"
  else
    printf '%s' "$s"
  fi
}

pu_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ----- 参数解析 (key=value 形式) -----

pu_extract_kv() {
  # pu_extract_kv <rest-string> <key>  → echo value, 并打印 stripped rest 到 stderr 是不实际的
  # 实际用法：将 rest 改成 stripped 需要 caller eval。这里直接给标准用法 wrapper：
  #   parsed=$(pu_strip_kv "$rest" lang)
  #   rest="${parsed%%	*}"; val="${parsed##*	}"
  :
}

pu_strip_kv() {
  # pu_strip_kv <rest> <key>
  # 输出格式: "<stripped-rest>\t<value>"  （tab 分隔）
  local rest="$1" key="$2"
  local val=""
  if [[ "$rest" =~ (^|[[:space:]])${key}=([^[:space:]]+) ]]; then
    val="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])${key}=[^[:space:]]+([[:space:]]|\$)/ /g")
  fi
  rest=$(pu_trim "$rest")
  printf '%s\t%s' "$rest" "$val"
}

# ----- qoder 调用 wrapper -----

pu_ask_qoder() {
  # pu_ask_qoder <to> <key> <prompt> [attached-file]
  # 自动 workspace + model_for_key + run_with_heartbeat 包装。
  local to="$1" key="$2" prompt="$3" file="${4:-}"
  local workspace; workspace="${WORK_ROOT}/${key}"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  if [[ -n "$file" ]]; then
    run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" "$file"
  else
    run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt"
  fi
}
