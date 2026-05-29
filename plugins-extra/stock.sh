# plugins/stock.sh — /stock <symbol|名称>
# 走 Yahoo Finance 公共 quote API（免 key、有时被墙）；
# A 股可走腾讯财经 q.qq.com（免 key），symbol 形如 sh600519 / sz000001。

plugin_stock() {
  local to="$1"; local key="$2"; local rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/stock <ticker>
例：
  /stock AAPL            # 美股
  /stock TSLA
  /stock sh600519        # A股贵州茅台（sh/sz 前缀）
  /stock hk00700         # 港股腾讯
  /stock BTC-USD         # 加密"
    return 0
  fi
  local s; s=$(printf '%s' "$rest" | awk '{print $1}')
  local lower; lower=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')

  # A股 / 港股走腾讯
  if [[ "$lower" =~ ^(sh|sz|hk)[0-9]+ ]]; then
    local raw
    raw=$(curl -sSL --max-time 12 \
      --user-agent 'Mozilla/5.0' \
      "https://qt.gtimg.cn/q=${lower}" 2>/dev/null)
    # 转 UTF-8（响应是 GBK）
    if command -v iconv >/dev/null 2>&1; then
      raw=$(printf '%s' "$raw" | iconv -f GBK -t UTF-8//IGNORE 2>/dev/null || printf '%s' "$raw")
    fi
    # v_sh600519="字段..."; (尾部可能没换行)
    local payload
    payload=$(printf '%s' "$raw" | python3 -c '
import sys, re
m = re.search(r"v_[^=]+=\"([^\"]*)\"", sys.stdin.read())
print(m.group(1) if m else "")
' 2>/dev/null)
    if [[ -z "$payload" ]]; then
      reply_text "$to" "❌ 未取到 ${s}（响应为空）"; return 1
    fi
    local name price chgpct vol date
    IFS='~' read -r -a F <<< "$payload"
    name="${F[1]}"; price="${F[3]}"; chgpct="${F[32]:-0}"; vol="${F[6]:-0}"; date="${F[30]:-}"
    reply_text "$to" "📈 ${name} (${s})
💰 现价: ${price}
📊 涨跌: ${chgpct}%
🔄 成交量: ${vol} 手
🕐 ${date}"
    return 0
  fi

  # 其它走 Yahoo
  local enc; enc=$(jq -rn --arg s "$s" '$s|@uri')
  local j
  j=$(curl -sSL --max-time 15 \
    --user-agent 'Mozilla/5.0' \
    "https://query1.finance.yahoo.com/v7/finance/quote?symbols=${enc}" 2>/dev/null)
  if [[ -z "$j" ]] || ! printf '%s' "$j" | jq -e '.quoteResponse.result|length>0' >/dev/null 2>&1; then
    reply_text "$to" "❌ 未找到 ${s}（Yahoo Finance 在大陆可能被墙）"
    return 1
  fi
  local txt
  txt=$(printf '%s' "$j" | jq -r '.quoteResponse.result[0] |
    "📈 \(.shortName // .longName // .symbol) (\(.symbol))\n💰 现价: \(.regularMarketPrice) \(.currency // "")\n📊 涨跌: \(.regularMarketChange) (\(.regularMarketChangePercent|tostring|.[0:6])%)\n🔄 成交量: \(.regularMarketVolume)\n📍 市场: \(.fullExchangeName // .exchange)"')
  reply_text "$to" "$txt"
}

register_command "/stock" plugin_stock "股票/加密报价：/stock <ticker>"
