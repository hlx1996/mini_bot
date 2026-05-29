# plugins/dns.sh — /dns <host> [type]
# 用 dns.google (Google DoH JSON, 免 key)
plugin_dns() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/dns <host> [A|AAAA|MX|TXT|CNAME|NS]"; return 0; }
  local host="${rest%% *}" tp=""
  [[ "$rest" != "$host" ]] && tp="${rest#* }"
  [[ -z "$tp" ]] && tp="A"
  tp=$(printf '%s' "$tp" | tr 'a-z' 'A-Z')
  local j; j=$(pu_http_get "https://dns.google/resolve?name=${host}&type=${tp}" 8) || {
    reply_text "$to" "❌ dns.google 不可达"; return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
if d.get('Status') != 0:
  print('❌ DNS error, status=', d.get('Status'))
ans = d.get('Answer') or []
if not ans:
  print('（无应答）')
else:
  for a in ans:
    print(f\"  {a.get('name','-')}  {a.get('type','-')}  TTL={a.get('TTL','-')}  -> {a.get('data','-')}\")" 2>/dev/null)
  reply_text "$to" "🔍 DNS ${host} (${tp}):
${out}"
}
register_command "/dns" plugin_dns "DNS 查询：/dns <host> [type]"
