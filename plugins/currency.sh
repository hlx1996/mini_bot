# plugins/currency.sh — /currency <amount> <FROM> <TO>
# 用 open.er-api.com（免 key）。

plugin_currency() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/currency <金额> <FROM> <TO>
例：/currency 100 USD CNY
也支持：/currency USD CNY  （查 1 单位汇率）"
    return 0
  fi

  local amount from tgt
  set -- $rest
  if [[ $# -ge 3 ]]; then
    amount="$1"
    from=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
    tgt=$(printf '%s' "$3" | tr '[:lower:]' '[:upper:]')
  elif [[ $# -eq 2 ]]; then
    amount="1"
    from=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    tgt=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
  else
    reply_text "$to" "参数不够。例：/currency 100 USD CNY"
    return 0
  fi

  if ! [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    reply_text "$to" "金额格式不对：${amount}"
    return 0
  fi

  local j; j=$(curl -fsSL --max-time 8 "https://open.er-api.com/v6/latest/${from}") || {
    reply_text "$to" "❌ 汇率源不可达"
    return 0
  }
  local rate; rate=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
if d.get('result') != 'success':
    print('ERR:' + (d.get('error-type') or 'unknown')); sys.exit()
r=(d.get('rates') or {}).get(sys.argv[1])
if r is None: print('NO_TARGET'); sys.exit()
print(r)
" "$tgt")

  case "$rate" in
    ERR:*)  reply_text "$to" "❌ ${rate#ERR:}  (FROM=${from})" ;;
    NO_TARGET) reply_text "$to" "❌ 不支持的目标币种：${tgt}" ;;
    *)
      local res; res=$(python3 -c "print(round(${amount}*${rate}, 4))")
      reply_text "$to" "💱 ${amount} ${from} = ${res} ${tgt}
（汇率 1 ${from} = ${rate} ${tgt}，open.er-api.com）"
      ;;
  esac
}

register_command "/currency" plugin_currency "汇率换算：/currency <金额> <FROM> <TO>"
