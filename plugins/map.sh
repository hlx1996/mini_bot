# plugins/map.sh — /map <地名>
# Nominatim 地名 → 经纬度，再用 osm static map 给一张图。无 key 免费。

plugin_map() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/map <地名|地址>   例：/map 北京天安门"
    return 0
  fi

  local q; q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rest")
  local j; j=$(curl -fsSL -A "mini_bot/1.0 (https://github.com/hlx1996/mini_bot)" \
    "https://nominatim.openstreetmap.org/search?q=${q}&format=json&limit=1&accept-language=zh-CN") || {
    reply_text "$to" "❌ Nominatim 查询失败"
    return 0
  }
  local parsed; parsed=$(printf '%s' "$j" | python3 -c "
import sys, json
arr=json.load(sys.stdin)
if not arr: print('NONE'); sys.exit()
d=arr[0]
print(d['lat'])
print(d['lon'])
print(d.get('display_name','-'))
")
  if [[ "$parsed" == "NONE" ]]; then
    reply_text "$to" "🔍 没找到：${rest}"
    return 0
  fi
  local lat lon name
  lat=$(printf '%s\n' "$parsed" | sed -n 1p)
  lon=$(printf '%s\n' "$parsed" | sed -n 2p)
  name=$(printf '%s\n' "$parsed" | sed -n 3p)

  local txt="📍 ${name}
🌐 经纬度: ${lat}, ${lon}
🗺️ OSM: https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=15/${lat}/${lon}
🧭 高德: https://uri.amap.com/marker?position=${lon},${lat}&name=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$rest")"

  # 下载一张 staticmap.openstreetmap.de 图
  local img_dir; img_dir="${IMAGE_DIR:-/tmp}/map"; mkdir -p "$img_dir"
  local img="${img_dir}/$(date +%s)_${RANDOM}.png"
  if curl -fsSL --max-time 12 -o "$img" \
       "https://staticmap.openstreetmap.de/staticmap.php?center=${lat},${lon}&zoom=14&size=600x400&markers=${lat},${lon},red-pushpin" 2>/dev/null \
     && [[ -s "$img" ]]; then
    reply_media "$to" "$img" "$txt"
  else
    reply_text "$to" "$txt"
  fi
}

register_command "/map" plugin_map "地图/经纬度：/map <地名>"
