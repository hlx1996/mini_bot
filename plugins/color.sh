# plugins/color.sh — /color <hex|rgb|name>  颜色转换 + 互补色
plugin_color() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  [[ -z "$rest" ]] && { reply_text "$to" "用法：/color <#RRGGBB|rgb(r,g,b)|颜色名>
例：/color #336699
    /color rgb(255,128,0)
    /color tomato"; return 0; }
  local out; out=$(python3 -c "
import sys, re
s = sys.argv[1].strip().lower()
# 简单命名表
named = {'red':(255,0,0),'green':(0,128,0),'blue':(0,0,255),'black':(0,0,0),
  'white':(255,255,255),'gray':(128,128,128),'tomato':(255,99,71),'orange':(255,165,0),
  'yellow':(255,255,0),'purple':(128,0,128),'pink':(255,192,203),'cyan':(0,255,255),
  'magenta':(255,0,255),'gold':(255,215,0),'silver':(192,192,192)}
r=g=b=None
if s in named: r,g,b = named[s]
elif s.startswith('#'):
  h = s[1:]
  if len(h)==3: h = ''.join(c*2 for c in h)
  if len(h)==6: r,g,b = int(h[0:2],16),int(h[2:4],16),int(h[4:6],16)
elif s.startswith('rgb'):
  m = re.findall(r'\d+', s)
  if len(m)>=3: r,g,b = [int(x) for x in m[:3]]
if r is None:
  print('❌ 解析失败'); sys.exit()
r,g,b = max(0,min(255,r)), max(0,min(255,g)), max(0,min(255,b))
hex_ = f'#{r:02x}{g:02x}{b:02x}'
def rgb2hsl(r,g,b):
  r,g,b = r/255,g/255,b/255
  mx,mn = max(r,g,b), min(r,g,b)
  l = (mx+mn)/2
  if mx==mn: h=s=0
  else:
    d = mx-mn
    s = d/(2-mx-mn) if l>0.5 else d/(mx+mn)
    if mx==r: h = (g-b)/d + (6 if g<b else 0)
    elif mx==g: h = (b-r)/d + 2
    else: h = (r-g)/d + 4
    h /= 6
  return int(h*360), int(s*100), int(l*100)
H,S,L = rgb2hsl(r,g,b)
comp = f'#{255-r:02x}{255-g:02x}{255-b:02x}'
print(f'🎨 {hex_}')
print(f'  RGB : ({r},{g},{b})')
print(f'  HSL : ({H},{S}%,{L}%)')
print(f'  互补: {comp}')
" "$rest" 2>&1)
  reply_text "$to" "$out"
}
register_command "/color" plugin_color "颜色转换：/color <hex|rgb|name>"
