# plugins/cidr.sh — /cidr <CIDR>  网段计算
plugin_cidr() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/cidr <CIDR>
例：/cidr 192.168.1.0/24
    /cidr 10.0.0.0/8
    /cidr 2001:db8::/64"; return 0; }
  local out; out=$(python3 -c "
import sys, ipaddress
try:
  net = ipaddress.ip_network(sys.argv[1], strict=False)
except Exception as e:
  print('❌', e); sys.exit()
print(f'🌐 {net}')
print(f'  version : IPv{net.version}')
print(f'  network : {net.network_address}')
print(f'  broadcast: {net.broadcast_address}')
print(f'  netmask : {net.netmask}')
print(f'  prefix  : /{net.prefixlen}')
print(f'  hosts   : {net.num_addresses}')
if net.num_addresses <= 8:
  print('  list    : ' + ', '.join(str(h) for h in net.hosts()))
" "$rest" 2>&1)
  reply_text "$to" "$out"
}
register_command "/cidr" plugin_cidr "网段计算：/cidr <CIDR>"
