# plugins/randpw.sh — /pw [len] [no-symbols] 安全随机密码
plugin_randpw() {
  local to="$1" key="$2" rest="$3"
  local len=20 sym=1
  local tok
  for tok in $rest; do
    case "$tok" in
      [0-9]*) len="$tok" ;;
      ns|nosym|no-symbols) sym=0 ;;
    esac
  done
  (( len < 4 )) && len=4
  (( len > 128 )) && len=128
  local pw; pw=$(python3 -c "
import secrets, string, sys
n = int(sys.argv[1]); sym = int(sys.argv[2])
chars = string.ascii_letters + string.digits + ('!@#\$%^&*-_=+?' if sym else '')
print(''.join(secrets.choice(chars) for _ in range(n)))
" "$len" "$sym")
  reply_text "$to" "🔐 ${pw}"
}
register_command "/pw" plugin_randpw "随机密码：/pw [len] [ns]（ns = 不含符号）"
