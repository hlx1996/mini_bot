# plugins/ip.sh — /ip [addr]  无 addr 显示 bot 公网 IP; 有 addr 查地理位置
# 用 ip-api.com (免 key, 45 req/min/IP)
plugin_ip() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  local url="http://ip-api.com/json/${rest}?fields=status,message,country,regionName,city,isp,org,as,query,timezone,reverse"
  local j; j=$(pu_http_get "$url" 8) || { reply_text "$to" "❌ ip-api.com 不可达"; return 0; }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
if d.get('status') != 'success':
  print('❌', d.get('message','unknown')); sys.exit()
print(f\"🌍 {d.get('query','-')}\")
print(f\"  📍 {d.get('country','-')} / {d.get('regionName','-')} / {d.get('city','-')}\")
print(f\"  🏢 {d.get('isp','-')}\")
print(f\"  📡 {d.get('as','-')}\")
print(f\"  🕐 {d.get('timezone','-')}\")
if d.get('reverse'): print(f\"  ↩️  {d.get('reverse')}\")" 2>/dev/null)
  reply_text "$to" "$out"
}
register_command "/ip" plugin_ip "IP 地理：/ip [地址]（空 = 公网出口）"
