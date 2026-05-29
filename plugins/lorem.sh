# plugins/lorem.sh — /lorem [p|s|w] [n]  生成 Lorem Ipsum
plugin_lorem() {
  local to="$1" key="$2" rest="$3"
  local unit="${rest%% *}" n=""
  [[ "$rest" != "$unit" ]] && n="${rest#* }"
  [[ -z "$unit" ]] && unit="p"
  [[ -z "$n" || ! "$n" =~ ^[0-9]+$ ]] && n=3
  (( n < 1 )) && n=1
  (( n > 20 )) && n=20
  local out; out=$(python3 -c "
import random, sys
WORDS=('lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure in reprehenderit voluptate velit esse cillum eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim id est laborum').split()
unit, n = sys.argv[1], int(sys.argv[2])
def sent(): 
  k = random.randint(8,18); s = ' '.join(random.choice(WORDS) for _ in range(k))
  return s[0].upper()+s[1:]+'.'
def para():
  k = random.randint(3,6); return ' '.join(sent() for _ in range(k))
if unit=='w': print(' '.join(random.choice(WORDS) for _ in range(n)))
elif unit=='s': print(' '.join(sent() for _ in range(n)))
else:
  for _ in range(n): print(para()); print()
" "$unit" "$n")
  reply_text "$to" "📝
${out}"
}
register_command "/lorem" plugin_lorem "Lorem Ipsum：/lorem [p|s|w] [n]"
