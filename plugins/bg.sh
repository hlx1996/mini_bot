#!/usr/bin/env bash
# plugins/bg.sh — 后台思考：把一个长问题甩进后台跑，立刻返回，结果好了再推。
#
# 用法：
#   /bg <问题>              立即回 "🤔" + 后台跑 qoder，结果好了用同会话的 session 推回去
#   /bg list                看正在跑的任务
#   /bg cancel <id>         杀掉
#
# 实现：fork 一个 nohup 子进程跑 run_qoder_agent。子进程结束时 reply_text
# 推结果。元数据写 state/sessions/<key>.bg.tsv：id\tpid\tstarted_ts\tprompt[:60]

_BG_TSV() { echo "$SESS_DIR/$1.bg.tsv"; }

_bg_cleanup() {
  # Drop rows whose PID is dead.
  local key="$1" f; f=$(_BG_TSV "$key")
  [[ -f "$f" ]] || return 0
  local tmp; tmp=$(mktemp)
  while IFS=$'\t' read -r id pid started prompt; do
    [[ -z "$pid" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      printf '%s\t%s\t%s\t%s\n' "$id" "$pid" "$started" "$prompt" >>"$tmp"
    fi
  done <"$f"
  mv "$tmp" "$f"
}

_bg_runner() {
  # _bg_runner <to> <key> <workspace> <model> <id> <platform> <account> <prompt>
  local to="$1" key="$2" workspace="$3" model="$4" id="$5" plat="$6" acct="$7" prompt="$8"
  # Use an ISOLATED qoder session (no --resume / --session-id) so the bg task
  # doesn't race with the user's main session if they keep chatting.
  local sys out rc
  sys=$(build_system_prompt "$key" 2>/dev/null) || sys=""
  out=$("$QODER_BIN" -p "$prompt" -m "$model" --cwd "$workspace" \
        --reasoning-effort high --permission-mode bypass_permissions \
        --append-system-prompt "$sys" --max-output-tokens 4000 \
        2>>"$LOG_DIR/qoder.err")
  rc=$?
  [[ -z "$out" ]] && out="(后台任务 #$id 没有产出，rc=$rc)"
  G_PLATFORM="$plat" G_ACCOUNT_NAME="$acct" \
    reply_text "$to" "💡 后台任务 #${id} 结果：

$out" || true
  # Self-prune from the tsv.
  local f; f=$(_BG_TSV "$key")
  if [[ -f "$f" ]]; then
    local tmp; tmp=$(mktemp)
    grep -v "^${id}	" "$f" >"$tmp" 2>/dev/null || true
    mv "$tmp" "$f"
  fi
}

plugin_bg() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" args=""
  [[ "$rest" != "$sub" ]] && args="${rest#* }"

  case "$sub" in
    ""|list|ls)
      _bg_cleanup "$key"
      local f; f=$(_BG_TSV "$key")
      if [[ ! -s "$f" ]]; then
        reply_text "$to" "🧘 没有在思考的任务。
用法：/bg <问题> 把一个慢问题甩进后台；/bg cancel <id>"
        return 0
      fi
      local now; now=$(date +%s)
      local out
      out=$(awk -F'\t' -v now="$now" '
        { age=now-$3; printf "  [%s] pid=%s  跑了 %ds  「%s」\n", $1,$2,age,$4 }
      ' "$f")
      reply_text "$to" "🤔 正在思考：
$out

/bg cancel <id> 撤销"
      return 0 ;;

    cancel|kill|rm)
      [[ -z "$args" ]] && { reply_text "$to" "用法：/bg cancel <id>"; return 0; }
      local f; f=$(_BG_TSV "$key")
      [[ -f "$f" ]] || { reply_text "$to" "（这个会话没有后台任务）"; return 0; }
      local pid; pid=$(awk -F'\t' -v id="$args" '$1==id {print $2; exit}' "$f")
      if [[ -z "$pid" ]]; then
        reply_text "$to" "❌ 没找到 id=$args"; return 0
      fi
      if kill "$pid" 2>/dev/null; then
        local tmp; tmp=$(mktemp); grep -v "^${args}	" "$f" >"$tmp" || true; mv "$tmp" "$f"
        reply_text "$to" "🛑 已撤销 #$args (pid=$pid)"
      else
        reply_text "$to" "（pid=$pid 进程已经不在了，清理元数据）"
        local tmp; tmp=$(mktemp); grep -v "^${args}	" "$f" >"$tmp" || true; mv "$tmp" "$f"
      fi
      return 0 ;;

    *)
      # /bg <prompt>  → 整个 rest 都是 prompt
      local prompt="$rest"
      if [[ -z "$prompt" ]]; then
        reply_text "$to" "用法：/bg <问题>   慢问题甩进后台，立即回 🤔 ，好了再推。"
        return 0
      fi
      local workspace model id plat acct
      workspace=$(cwd_resolve_workspace "$key" "$WORK_ROOT/$key"); mkdir -p "$workspace"
      model=$(model_for_key "$key")
      id="$(date +%s)$RANDOM"
      plat="${G_PLATFORM:-wechat}"
      acct="${G_ACCOUNT_NAME:-default}"

      reply_text "$to" "🤔 收到，我去想想…（任务 #${id}）"

      # Fork: subshell inherits all functions (_bg_runner, run_qoder_agent, ...)
      # and env. Detach SIGHUP/INT/TERM so it survives the handle_event parent.
      (
        trap '' HUP INT TERM
        _bg_runner "$to" "$key" "$workspace" "$model" "$id" "$plat" "$acct" "$prompt"
      ) </dev/null >>"$LOG_DIR/bg.log" 2>&1 &
      local rpid=$!
      disown "$rpid" 2>/dev/null || true

      local f; f=$(_BG_TSV "$key"); mkdir -p "$(dirname "$f")"
      printf '%s\t%s\t%s\t%s\n' "$id" "$rpid" "$(date +%s)" "${prompt:0:60}" >>"$f"
      return 0 ;;
  esac
}

register_command "/bg"   plugin_bg "后台思考：/bg <问题> 立即回 🤔，跑完再推；/bg list|cancel"
register_command "/思考" plugin_bg "后台思考：/思考 <问题>"
