# plugins/whois.sh — /whois <domain>  优先用本机 whois，否则用 rdap.org
plugin_whois() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/whois <domain>"; return 0; }
  local domain="$rest"
  if command -v whois >/dev/null 2>&1; then
    local body; body=$(whois "$domain" 2>&1 | head -60)
    [[ -z "$body" ]] && body="(空)"
    reply_text "$to" "🔍 whois ${domain}:
${body}"
    return 0
  fi
  # rdap fallback
  local j; j=$(pu_http_get "https://rdap.org/domain/${domain}" 10) || {
    reply_text "$to" "❌ rdap.org 不可达"; return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit()
if d.get('errorCode'):
  print('❌', d.get('title','-'), d.get('description','-')); sys.exit()
print(f\"📛 {d.get('ldhName','-')}\")
print(f\"  handle: {d.get('handle','-')}\")
ev = d.get('events') or []
for e in ev[:5]:
  print(f\"  {e.get('eventAction','-')}: {e.get('eventDate','-')}\")
ns = [e.get('ldhName','') for e in (d.get('nameservers') or [])]
if ns: print('  ns: ' + ', '.join(ns[:6]))
ent = d.get('entities') or []
for e in ent[:3]:
  r = e.get('roles') or []
  v = (((e.get('vcardArray') or [])+[[]])[1] or [])
  fn = next((x[3] for x in v if x and x[0]=='fn'), '-')
  print(f\"  {','.join(r)}: {fn}\")" 2>/dev/null)
  reply_text "$to" "$out"
}
register_command "/whois" plugin_whois "域名 whois：/whois <domain>"
