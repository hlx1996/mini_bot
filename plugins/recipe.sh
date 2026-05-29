# plugins/recipe.sh — /recipe <食材或菜名> [n=3]
# 走 TheMealDB 免费 API（无 key、中英菜系，但主要英文）。
# 中文输入会自动用 qoder 翻译成英文菜名搜索。

plugin_recipe() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/recipe <食材或菜名> [n=3]
例：
  /recipe chicken curry
  /recipe 番茄炒蛋
  /recipe pasta n=5"
    return 0
  fi
  local n=3
  if [[ "$rest" =~ (^|[[:space:]])n=([0-9]+) ]]; then
    n="${BASH_REMATCH[2]}"
    rest=$(printf '%s' "$rest" | sed -E "s/(^|[[:space:]])n=${n}([[:space:]]|\$)/ /g")
  fi
  rest=$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

  # 中文 → 让 qoder 翻成英文菜名 (TheMealDB 只认英文)
  local q="$rest"
  if [[ "$rest" =~ [^\ -~] ]]; then
    reply_text "$to" "🍳 翻译菜名以便搜索 …"
    local workspace; workspace="$WORK_ROOT/$key"; mkdir -p "$workspace"
    local model; model=$(model_for_key "$key")
    local prompt="把下面中文菜名翻译成 1 个最常见的英文菜名（只输出菜名，不要任何其它解释）：
${rest}"
    q=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null | head -1 | sed -E 's/[[:space:]]+$//')
    [[ -z "$q" ]] && q="$rest"
  fi

  reply_text "$to" "🍳 查菜谱：${q} …"
  local enc; enc=$(jq -rn --arg s "$q" '$s|@uri')
  local raw
  raw=$(curl -sSL --max-time 15 "https://www.themealdb.com/api/json/v1/1/search.php?s=${enc}" 2>/dev/null)
  if [[ -z "$raw" ]] || ! printf '%s' "$raw" | jq -e '.meals' >/dev/null 2>&1; then
    reply_text "$to" "❌ TheMealDB 没找到 '${q}'"; return 1
  fi
  local out
  out=$(printf '%s' "$raw" | jq -r --argjson n "$n" '
    (.meals[0:$n] // []) | map(
      "🍽️ \(.strMeal)\n📍 \(.strArea) | \(.strCategory)\n🔗 \(.strSource // .strYoutube // "—")\n\n" +
      "📝 食材:\n" +
      ([range(1;21) as $i |
        (.["strIngredient"+($i|tostring)] // "") as $ing |
        (.["strMeasure"+($i|tostring)] // "") as $m |
        if $ing != "" and $ing != null then "  - \($m) \($ing)" else empty end
      ] | join("\n")) +
      "\n\n📖 做法:\n" + ((.strInstructions // "") | .[0:600]) + "…"
    ) | join("\n\n———\n\n")')
  reply_text "$to" "$out"
}

register_command "/recipe" plugin_recipe "查菜谱：/recipe <食材或菜名> [n=N]"
