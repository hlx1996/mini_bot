# plugins/pt.sh — /pt [hours]  BTSchool 最近 N 小时新种汇总（豆瓣增强）
# 输出：飞书卡片表格（table 组件），按类别分表：电影/电视剧/动漫/综艺/纪录片/其他
# 行序：做种数降序；全量列出（卡片内可翻页）；剧集类仅保留全集（脚本默认过滤）
# 豆瓣评分列：分数 / 暂无评分 / 未找到
# 依赖：state/skills/btschool-digest/（SKILL.md + scripts/btschool_digest.py + cookie.txt）
# Cookie 放 state/skills/btschool-digest/cookie.txt（chmod 600，state/ 已 gitignore，勿提交）

PT_SKILL_DIR="${PT_SKILL_DIR:-${BOT_HOME:-}/skills/btschool-digest}"

plugin_pt() {
  local to="$1"; local key="$2"; local rest="$3"
  local hours
  hours=$(printf '%s' "$rest" | awk '{print $1}')
  [[ "$hours" =~ ^[0-9]+$ ]] || hours=48

  local cookie=""
  if [[ -n "$PT_SKILL_DIR" && -f "$PT_SKILL_DIR/cookie.txt" ]]; then
    cookie="$(tr -d '\r\n' < "$PT_SKILL_DIR/cookie.txt")"
  fi
  if [[ -z "$cookie" ]]; then
    reply_text "$to" "❌ 未找到 BTSchool 登录 Cookie。
请把浏览器里复制的整串 cookie 写入：
$PT_SKILL_DIR/cookie.txt
（站内 F12 → Network → torrents.php → Request Headers → cookie 整串）"
    return 0
  fi

  reply_text "$to" "⏳ 正在抓取 BTSchool 最近 ${hours}h 新种并匹配豆瓣（约 1-3 分钟，站点慢时会自动重试）…"

  local tmp_json tmp_dir errf attempt=1 ok=0
  tmp_json="$(mktemp "${TMPDIR:-/tmp}/pt_digest.XXXXXX")"
  errf="$(mktemp "${TMPDIR:-/tmp}/pt_digest.err.XXXXXX")"
  # 站点在 12:00 前后有约 30-60s 的不稳定窗口且常态极慢：单次 15s 超时必挂，
  # 故整体最多 3 次尝试，间隔 60s/120s 错开窗口；登录态失效重试无意义，直接退出。
  while :; do
    if PT_COOKIE="$cookie" python3 "$PT_SKILL_DIR/scripts/btschool_digest.py" \
          --hours "$hours" --sort seeders --json "$tmp_json" >/dev/null 2>"$errf"; then
      ok=1
      break
    fi
    grep -q "登录态失效" "$errf" && break
    (( attempt >= 3 )) && break
    local wait_s=$(( attempt * 60 ))
    reply_text "$to" "⏳ BTSchool 站点响应慢/超时，${wait_s}s 后自动重试（第 $((attempt + 1))/3 次）…"
    sleep "$wait_s"
    attempt=$((attempt + 1))
  done
  if [[ "$ok" != 1 ]]; then
    local why
    why="$(grep -v '^[[:space:]]*$' "$errf" | tail -1)"
    rm -f "$tmp_json" "$errf"
    if [[ "$why" == *登录态失效* || "$why" == *需要\ Cookie* ]]; then
      reply_text "$to" "❌ $why
请更新 $PT_SKILL_DIR/cookie.txt 后再试 /pt"
    else
      reply_text "$to" "❌ 抓取失败：${why:-站点无响应}
（已自动重试 3 次仍未成功，站点当前不稳定，可稍后再试 /pt）"
    fi
    return 0
  fi
  rm -f "$errf"
  if [[ ! -s "$tmp_json" ]]; then
    rm -f "$tmp_json"
    reply_text "$to" "📭 最近 ${hours}h 没有符合条件的种子（免费/2X免费 且做种≥10）"
    return 0
  fi

  # 生成 1..N 张卡片（单张 >24KB 自动拆分），文件 card_1.json card_2.json …
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pt_cards.XXXXXX")"
  if PT_HOURS="$hours" PT_OUT_DIR="$tmp_dir" python3 - "$tmp_json" <<'PY'
import json, os, re, sys, datetime

data = json.load(open(sys.argv[1]))
rows = data['rows']
dropped = data.get('dropped_partial', 0) or 0
dropped_old = data.get('dropped_old_movies', 0) or 0
out_dir = os.environ['PT_OUT_DIR']
hours = os.environ.get('PT_HOURS', '48')

CATS = ['电影', '电视剧', '动漫', '综艺', '纪录片', '其他']
EMOJI = {'电影': '🎬', '电视剧': '📺', '动漫': '🌸', '综艺': '🎤', '纪录片': '🌍', '其他': '📦'}

def bucket_of(cat):
    return cat if cat in CATS[:5] else '其他'

def rate_md(r):
    st = r.get('status')
    if st == 'rated':
        return f"**{r.get('rate')}**"
    return '—'

def name_md(r):
    n = (r.get('name') or '?').replace('|', '/').strip()
    if len(n) > 42:
        n = n[:40] + '…'
    sid = r.get('sid')
    return f'[{n}](https://movie.douban.com/subject/{sid}/)' if sid else n

def spec_md(r):
    links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', r.get('spec') or '')
    out = []
    for label, url in links[:2]:
        label = re.sub(r'\(S(\d+)\)', r' S\1', label).strip()
        out.append(f'[{label}]({url})')
    extra = len(links) - 2
    if extra > 0:
        out.append(f'+{extra}')
    return ' · '.join(out) if out else '—'

# 卡片 JSON 2.0 表格规范：width 必须是字符串("Npx"，最小 80px，或 "auto")；
# data_type 用 "markdown"；行值为纯字符串；header_style 用 background_style
COLS = [
    {"name": "name",   "display_name": "名称",      "data_type": "markdown", "width": "250px", "horizontal_align": "left"},
    {"name": "rate",   "display_name": "评分",      "data_type": "markdown", "width": "90px",  "horizontal_align": "center"},
    {"name": "seed",   "display_name": "做种",      "data_type": "markdown", "width": "90px",  "horizontal_align": "center"},
    {"name": "ry",     "display_name": "国家&年份", "data_type": "markdown", "width": "120px", "horizontal_align": "center"},
    {"name": "types",  "display_name": "类型",      "data_type": "markdown", "width": "180px", "horizontal_align": "left"},
    {"name": "spec",   "display_name": "版本规格",  "data_type": "markdown", "width": "260px", "horizontal_align": "left"},
]

def types_md(r):
    t = r.get('types')
    if isinstance(t, list):
        return '、'.join(t[:3]) if t else '—'
    return t or '—'

def region_short(reg):
    reg = (reg or '').strip()
    if reg == '中国大陆':
        return '中国'
    if reg.startswith('中国') and len(reg) > 2:
        return reg[2:]
    return reg

def ry_md(r):
    reg, year = region_short(r.get('region')), r.get('year')
    if reg and year:
        return f"{reg}({year})"
    return reg or (str(year) if year else '—')

def row_obj(r):
    return {
        "name":   name_md(r),
        "ry":     ry_md(r),
        "rate":   rate_md(r),
        "seed":   str(r.get('max_seeders', 0)),
        "types":  types_md(r),
        "spec":   spec_md(r),
    }

def table_el(rs):
    return {"tag": "table", "page_size": 10, "row_height": "low", "freeze_first_column": False,
            "header_style": {"background_style": "grey", "bold": True, "text_align": "left"},
            "columns": COLS, "rows": [row_obj(r) for r in rs]}

def new_card():
    return {"schema": "2.0",
            "config": {"width_mode": "fill"},
            "header": {"title": {"tag": "plain_text", "content": f"🎟 BTSchool 最近{hours}h 热门种子"},
                       "template": "turquoise"},
            "body": {"direction": "vertical", "elements": []}}

def chunk(rs, n):
    return [rs[i:i + n] for i in range(0, len(rs), n)] or [[]]

groups = {c: [] for c in CATS}
for r in rows:
    groups[bucket_of(r.get('cat', ''))].append(r)
# JSON 的 rows 是原始顺序（脚本只对 markdown 输出排序），这里必须显式按做种数降序
for c in groups:
    groups[c].sort(key=lambda x: -x.get('max_seeders', 0))

nseed = sum(r.get('nv', 1) for r in rows)
rated = sum(1 for r in rows if r.get('status') == 'rated')
unrated = sum(1 for r in rows if r.get('status') == 'unrated')
nf = len(rows) - rated - unrated
now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')

intro = (f"**范围**：最近 {hours}h 上传 · 促销=免费/2X免费 · 做种≥10 · 按做种数排序 · 剧集仅全集 · 电影仅五年内")

# 前 3 个分类（电影/电视剧/动漫）各占一表；纪录片/综艺并入"其他"，行名加 [分类] 前缀（≤4 表，单条消息发完）
order = [c for c in CATS if groups[c]]
folded = []
for c in order[3:]:
    if c == '其他':
        continue
    for r in groups[c]:
        r['name'] = f"[{c}] {r['name']}"
    folded.append(c)
    groups['其他'].extend(groups[c])
    groups[c] = []

blocks = []          # 每个元素 = [el, el, ...]（小标题 + 表）
for c in [c for c in CATS if groups[c]]:
    rs = groups[c]
    label = ' / '.join([c] + folded) if c == '其他' and folded else c
    block = [{"tag": "markdown", "content": f"**{EMOJI[c]} {label}（{len(rs)}）**"}]
    block.extend(table_el(part) for part in chunk(rs, 100))
    blocks.append(block)

cards, cur, cur_intro = [], None, False
BUDGET = 28500

def flush():
    global cur
    if cur is not None and cur['body']['elements']:
        cards.append(cur)
    cur = None

for b in blocks:
    if cur is None:
        cur = new_card()
        cur['body']['elements'].append({"tag": "markdown", "content": intro})
        cur_intro = True
    size = len(json.dumps(b, ensure_ascii=False))
    cur_size = len(json.dumps(cur, ensure_ascii=False))
    if cur_size + size > BUDGET and len(cur['body']['elements']) > 1:
        flush()
        cur = new_card()
        cur['body']['elements'].append({"tag": "markdown", "content": intro})
        cur_intro = True
    cur['body']['elements'].extend(b)
    cur_intro = False

if cur is not None:
    cur['body']['elements'].append({"tag": "hr"})
    cur['body']['elements'].append({"tag": "markdown",
        "content": f'生成于 {now}'})
    cards.append(cur)

for i, card in enumerate(cards, 1):
    with open(os.path.join(out_dir, f'card_{i}.json'), 'w') as f:
        json.dump(card, f, ensure_ascii=False)
print(f"cards={len(cards)} rows={len(rows)}", file=sys.stderr)
PY
  then
    rm -f "$tmp_json"
    local ok=1 f
    for f in "$tmp_dir"/card_*.json; do
      [[ -f "$f" ]] || continue
      lark_send_card_json "$to" "$(cat "$f")" || ok=0
      sleep 0.3
    done
    rm -rf "$tmp_dir"
    if [[ "$ok" == 1 ]]; then
      return 0
    fi
    reply_text "$to" "❌ 部分卡片发送失败（飞书接口异常），请稍后再试 /pt"
    return 0
  else
    rm -rf "$tmp_dir" "$tmp_json"
    reply_text "$to" "❌ 卡片生成失败，请稍后再试 /pt"
    return 0
  fi
}

register_command "/pt" plugin_pt "BTSchool 新种汇总（飞书卡片表格，按类别分表、全量列出、按做种排序）：/pt [小时=48]"
