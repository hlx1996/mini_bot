# plugins/morse.sh — /morse enc|dec <text>
plugin_morse() {
  local to="$1" key="$2" rest="$3"
  local sub="${rest%% *}" arg=""
  [[ "$rest" != "$sub" ]] && arg="${rest#* }"
  case "$sub" in
    enc|encode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/morse enc <text>"; return 0; }
      local out; out=$(python3 -c "
import sys
M={'A':'.-','B':'-...','C':'-.-.','D':'-..','E':'.','F':'..-.','G':'--.','H':'....','I':'..','J':'.---','K':'-.-','L':'.-..','M':'--','N':'-.','O':'---','P':'.--.','Q':'--.-','R':'.-.','S':'...','T':'-','U':'..-','V':'...-','W':'.--','X':'-..-','Y':'-.--','Z':'--..','0':'-----','1':'.----','2':'..---','3':'...--','4':'....-','5':'.....','6':'-....','7':'--...','8':'---..','9':'----.'}
print(' '.join(M.get(c,'?') for c in sys.argv[1].upper() if c.strip()))
" "$arg")
      reply_text "$to" "📡 ${out}"
      ;;
    dec|decode)
      [[ -z "$arg" ]] && { reply_text "$to" "用法：/morse dec <code>"; return 0; }
      local out; out=$(python3 -c "
import sys
M={'.-':'A','-...':'B','-.-.':'C','-..':'D','.':'E','..-.':'F','--.':'G','....':'H','..':'I','.---':'J','-.-':'K','.-..':'L','--':'M','-.':'N','---':'O','.--.':'P','--.-':'Q','.-.':'R','...':'S','-':'T','..-':'U','...-':'V','.--':'W','-..-':'X','-.--':'Y','--..':'Z','-----':'0','.----':'1','..---':'2','...--':'3','....-':'4','.....':'5','-....':'6','--...':'7','---..':'8','----.':'9'}
print(''.join(M.get(t,'?') for t in sys.argv[1].split()))
" "$arg")
      reply_text "$to" "📨 ${out}"
      ;;
    *)
      reply_text "$to" "用法：/morse enc|dec <内容>"
      ;;
  esac
}
register_command "/morse" plugin_morse "摩斯密码：/morse enc|dec <内容>"
