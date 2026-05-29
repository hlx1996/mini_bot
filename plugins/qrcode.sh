# plugins/qrcode.sh — /qrcode <text|url>
# 优先本地 qrencode（离线），否则用 api.qrserver.com（在线、免 key）。

plugin_qrcode() {
  local to="$1"; local key="$2"; local rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/qrcode <文本|URL>
例：
  /qrcode https://example.com
  /qrcode wifi:WeixinPay"
    return 0
  fi
  local out; out=$(mktemp -t qr.XXXXXX)
  mv "$out" "${out}.png"
  out="${out}.png"
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -o "$out" -s 8 -m 2 -- "$rest" 2>/dev/null
  else
    local enc; enc=$(jq -rn --arg s "$rest" '$s|@uri')
    curl -sSL --max-time 20 -o "$out" \
      "https://api.qrserver.com/v1/create-qr-code/?size=400x400&margin=10&data=${enc}" \
      2>/dev/null
  fi
  if [[ ! -s "$out" ]]; then
    rm -f "$out"
    reply_text "$to" "❌ 二维码生成失败"
    return 1
  fi
  reply_media "$to" "$out" "qrcode" || reply_text "$to" "❌ 二维码已生成但上传失败"
  rm -f "$out"
}

register_command "/qrcode" plugin_qrcode "生成二维码：/qrcode <文本|URL>"
register_command "/二维码"  plugin_qrcode "生成二维码：/二维码 <文本|URL>"
