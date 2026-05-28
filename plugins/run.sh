#!/usr/bin/env bash
# plugins/run.sh — /run <lang> <code>  受限的代码执行（python/bash/node）
# 安全策略：
#   - 超时 15s
#   - 内存/CPU 限制（ulimit）
#   - 临时工作目录（不污染 cwd）
#   - 输出截断到 4KB

_run_lang() {
  local lang="$1"
  case "$lang" in
    py|python|python3) echo "python3" ;;
    sh|bash)           echo "bash"    ;;
    js|node)           echo "node"    ;;
    *) return 1 ;;
  esac
}

plugin_run() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/run <lang> <code>
  支持 lang：python(py) | bash(sh) | node(js)
示例：
  /run py print(sum(range(100)))
  /run bash for i in 1 2 3; do echo \$i; done
  /run js console.log([1,2,3].map(x=>x*x))
限制：15s 超时、stdout/stderr 各截 4KB、隔离临时目录。"
    return
  fi
  local lang_tok="${rest%% *}" code=""
  [[ "$rest" != "$lang_tok" ]] && code="${rest#* }"
  local bin
  if ! bin=$(_run_lang "$lang_tok"); then
    reply_text "$to" "未知语言：$lang_tok（支持 py/bash/js）"; return
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    reply_text "$to" "本机没装 $bin"; return
  fi
  if [[ -z "$code" ]]; then
    reply_text "$to" "代码不能空"; return
  fi
  local tmpdir; tmpdir=$(mktemp -d -t mbrun.XXXX)
  local src
  case "$bin" in
    python3) src="$tmpdir/run.py";  printf '%s' "$code" > "$src" ;;
    bash)    src="$tmpdir/run.sh";  printf '%s\n' "$code" > "$src" ;;
    node)    src="$tmpdir/run.js";  printf '%s' "$code" > "$src" ;;
  esac
  local out err
  out=$(mktemp); err=$(mktemp)
  local rc=0
  (
    cd "$tmpdir" || exit 1
    ulimit -t 15 2>/dev/null || true   # CPU sec
    ulimit -v 524288 2>/dev/null || true   # 512 MB virt
    ulimit -f 10240 2>/dev/null || true   # 10 MB file
    # Cross-platform timeout: GNU timeout / gtimeout / perl fallback
    local _to
    if command -v timeout >/dev/null 2>&1; then _to=(timeout 15)
    elif command -v gtimeout >/dev/null 2>&1; then _to=(gtimeout 15)
    else _to=(perl -e 'alarm 15; exec @ARGV' --)
    fi
    case "$bin" in
      bash) "${_to[@]}" bash "$src" ;;
      *)    "${_to[@]}" "$bin" "$src" ;;
    esac
  ) >"$out" 2>"$err"
  rc=$?
  local out_s err_s
  out_s=$(head -c 4096 "$out"); err_s=$(head -c 4096 "$err")
  rm -rf "$tmpdir" "$out" "$err"
  local msg="🧪 /run $lang_tok (exit=$rc)"
  [[ -n "$out_s" ]] && msg+=$'\n--- stdout ---\n'"$out_s"
  [[ -n "$err_s" ]] && msg+=$'\n--- stderr ---\n'"$err_s"
  [[ -z "$out_s" && -z "$err_s" ]] && msg+=$'\n(无输出)'
  reply_text "$to" "$msg"
}

register_command "/run"  plugin_run "代码沙箱：/run <py|bash|js> <code>"
register_command "/exec" plugin_run "代码沙箱：/exec <py|bash|js> <code>"
