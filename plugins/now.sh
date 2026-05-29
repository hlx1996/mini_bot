# plugins/now.sh — /now [tz]  时间换算
# /now            本机时间
# /now utc        UTC
# /now Asia/Tokyo IANA tz
# /now <epoch>    把 epoch 翻译成多时区
plugin_now() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"

  if [[ "$rest" =~ ^[0-9]{9,13}$ ]]; then
    # epoch
    local epoch="$rest"
    [[ ${#epoch} -ge 13 ]] && epoch=$((epoch/1000))
    local out
    out=$(python3 -c "
import datetime, sys
try: from zoneinfo import ZoneInfo
except: ZoneInfo=None
e = int(sys.argv[1])
print(f'⏱️ epoch {e}')
print('  Local : ' + datetime.datetime.fromtimestamp(e).strftime('%Y-%m-%d %H:%M:%S'))
print('  UTC   : ' + datetime.datetime.utcfromtimestamp(e).strftime('%Y-%m-%d %H:%M:%S Z'))
if ZoneInfo:
  for tz in ['Asia/Shanghai','Asia/Tokyo','Europe/London','America/New_York','America/Los_Angeles']:
    print(f'  {tz:<22}: '+datetime.datetime.fromtimestamp(e,ZoneInfo(tz)).strftime('%Y-%m-%d %H:%M:%S %Z'))
" "$epoch" 2>&1)
    reply_text "$to" "$out"; return 0
  fi

  if [[ -z "$rest" ]]; then
    reply_text "$to" "🕐 $(date '+%Y-%m-%d %H:%M:%S %Z')
epoch: $(date +%s)
用法：/now            本机时间
      /now utc       UTC
      /now Asia/Tokyo
      /now 1700000000  把 epoch 翻译成多时区"
    return 0
  fi

  local tz="$rest"
  [[ "$tz" == "utc" || "$tz" == "UTC" ]] && tz="UTC"
  local out
  out=$(TZ="$tz" date '+%Y-%m-%d %H:%M:%S %Z' 2>&1) || { reply_text "$to" "❌ 无效时区: ${tz}"; return 0; }
  reply_text "$to" "🕐 ${tz}: ${out}"
}
register_command "/now" plugin_now "时间/时区：/now [tz|epoch]"
