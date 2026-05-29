# plugins/reddit.sh — /reddit <subreddit> [n=10]
# Reddit JSON 公开接口（免 key，UA 必填）。

plugin_reddit() {
  local to="$1" key="$2" rest="$3"
  local n=10
  if [[ "$rest" =~ (^|[[:space:]])n=([0-9]+) ]]; then
    n="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])n=[0-9]+([[:space:]]|\$)/ /g; s/^ +//; s/ +\$//")
  fi
  (( n > 25 )) && n=25
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/reddit <subreddit> [n=10]
例：/reddit MachineLearning n=8"
    return 0
  fi
  local sub="${rest#r/}"; sub="${sub#/r/}"
  local j; j=$(curl -fsSL --max-time 8 -A "mini_bot/1.0" "https://www.reddit.com/r/${sub}/hot.json?limit=${n}") || {
    reply_text "$to" "❌ Reddit 不可达 / 子版不存在 (${sub})"; return 0
  }
  local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
posts=(d.get('data',{}) or {}).get('children',[]) or []
if not posts: print('（空）'); sys.exit()
sub=sys.argv[1]
n=int(sys.argv[2])
print(f'👽 r/{sub}  hot top {n}')
print()
for i, p in enumerate(posts[:n], 1):
    pd=p.get('data',{}) or {}
    title=pd.get('title','-')
    score=pd.get('score',0)
    nc=pd.get('num_comments',0)
    url='https://reddit.com'+pd.get('permalink','')
    print(f'{i:>2}. [{score:>5}] {title[:140]}')
    print(f'     💬 {nc}  🔗 {url}')
" "$sub" "$n")
  reply_text "$to" "$out"
}

register_command "/reddit" plugin_reddit "Reddit 热帖：/reddit <sub> [n=10]"
