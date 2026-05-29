# plugins/joke.sh — /joke  随机笑话（英文 + 中文）
# 英文：official-joke-api.appspot.com（免 key）
# 中文：让 qoder 现编一个段子

plugin_joke() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  local lang="zh"
  [[ "$rest" == "en" ]] && lang="en"

  if [[ "$lang" == "en" ]]; then
    local j; j=$(pu_http_get "https://official-joke-api.appspot.com/random_joke" 6) || {
      reply_text "$to" "❌ joke API 不可达"; return 0
    }
    local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print(f\"😂 {d.get('setup','-')}\")
print(f\"   — {d.get('punchline','-')}\")
print(f\"[{d.get('type','-')}]\")
")
    reply_text "$to" "$out"
  else
    reply_text "$to" "😂 想一个段子…"
    local prompt="讲一个简短的中文段子或冷笑话，不超过 60 字。直接输出段子，不要解释。"
    local ans; ans=$(pu_ask_qoder "$to" "$key" "$prompt")
    [[ -z "$ans" ]] && ans="(qoder 没返回)"
    reply_text "$to" "$ans"
  fi
}

register_command "/joke" plugin_joke "笑话：/joke [zh|en]"
