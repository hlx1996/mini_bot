# plugins/movie.sh — /movie <片名|关键词> [year=YYYY]
# 走 Wikipedia OpenSearch + Page extract API（免 key、多语言）。

plugin_movie() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/movie <片名|关键词> [year=YYYY] [lang=zh|en]
例：
  /movie The Matrix
  /movie 流浪地球 year=2019
  /movie Inception lang=zh"
    return 0
  fi
  local lang="zh"
  if [[ "$rest" =~ (^|[[:space:]])lang=([a-z]{2}) ]]; then
    lang="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])lang=${lang}([[:space:]]|\$)/ /g")
  fi
  local year=""
  if [[ "$rest" =~ (^|[[:space:]])year=([0-9]{4}) ]]; then
    year="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])year=${year}([[:space:]]|\$)/ /g")
  fi
  rest=$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

  reply_text "$to" "🎬 查电影：${rest} …"
  local q="${rest}"; [[ -n "$year" ]] && q="${q} ${year} film"
  local enc; enc=$(jq -rn --arg s "$q" '$s|@uri')

  # 1. OpenSearch 找标题
  local titles
  titles=$(curl -sSL --max-time 15 \
    "https://${lang}.wikipedia.org/w/api.php?action=opensearch&search=${enc}&limit=3&namespace=0&format=json" \
    2>/dev/null)
  local title; title=$(printf '%s' "$titles" | jq -r '.[1][0] // empty' 2>/dev/null)
  if [[ -z "$title" ]]; then
    reply_text "$to" "❌ Wikipedia 没找到 '${rest}'（试 lang=en）"; return 1
  fi
  local tenc; tenc=$(jq -rn --arg s "$title" '$s|@uri')

  # 2. summary API
  local summary
  summary=$(curl -sSL --max-time 15 \
    "https://${lang}.wikipedia.org/api/rest_v1/page/summary/${tenc}" \
    2>/dev/null)
  if [[ -z "$summary" ]]; then
    reply_text "$to" "❌ 取摘要失败"; return 1
  fi
  local extract page_url
  extract=$(printf '%s' "$summary" | jq -r '.extract // ""')
  page_url=$(printf '%s' "$summary" | jq -r '.content_urls.desktop.page // ""')
  if [[ -z "$extract" ]]; then
    reply_text "$to" "❌ 没找到摘要：${title}"; return 1
  fi
  reply_text "$to" "🎬 ${title}
🔗 ${page_url}

${extract}"
}

register_command "/movie" plugin_movie "查电影：/movie <片名> [year=YYYY] [lang=zh|en]"
