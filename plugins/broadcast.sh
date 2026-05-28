#!/usr/bin/env bash
# plugins/broadcast.sh — /broadcast <name1,name2,...> <text>

plugin_broadcast() {
  local to="$1" _key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/broadcast <名字1,名字2,...> <消息正文>
例：/broadcast 老王,老李,产品群 周会改到下午 3 点

（名字需先用 /nick add <名字> last 注册）"
    return 0
  fi

  local targets_csv="${rest%% *}"
  local msg="${rest#* }"
  if [[ "$msg" == "$rest" || -z "$msg" ]]; then
    reply_text "$to" "❌ 缺少消息正文。用法：/broadcast <名字1,名字2> <消息>"
    return 0
  fi

  local IFS=','
  read -r -a names <<<"$targets_csv"
  unset IFS

  local ok=0 fail=0 not_found=()
  local nm trip plat acct pid
  for nm in "${names[@]}"; do
    nm="${nm// /}"
    [[ -z "$nm" ]] && continue
    if ! trip=$(contact_get "$nm" 2>/dev/null); then
      not_found+=( "$nm" ); continue
    fi
    plat=$(echo "$trip" | cut -f1)
    acct=$(echo "$trip" | cut -f2)
    pid=$(echo "$trip"  | cut -f3)
    if G_PLATFORM="$plat" G_ACCOUNT_NAME="$acct" reply_text "$pid" "$msg"; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
    fi
  done

  local report="📣 已群发：成功 $ok / 失败 $fail"
  ((${#not_found[@]})) && report+=$'\n'"❓ 未找到昵称：${not_found[*]}（/nick list 看看）"
  reply_text "$to" "$report"
  return 0
}

register_command "/broadcast" plugin_broadcast "群发：/broadcast <名字1,名字2,...> <消息>"
register_command "/群发"      plugin_broadcast "群发：/群发 <名字1,名字2,...> <消息>"
