# plugins/poem.sh — /poem [random|<关键词>]
# 古诗词随机/搜索。今古词典 API：https://v1.jinrishici.com/all.json （免 key）
# 关键词搜索走 https://api.gushi.ci/?type=text （或 fallback 让 qoder 编一首）。

plugin_poem() {
  local to="$1" key="$2" rest="$3"
  rest="${rest## }"; rest="${rest%% }"
  if [[ -z "$rest" || "$rest" == "random" ]]; then
    local j; j=$(curl -fsSL --max-time 6 "https://v1.jinrishici.com/all.json") || {
      reply_text "$to" "❌ 今日诗词接口不可达"; return 0
    }
    local out; out=$(printf '%s' "$j" | python3 -c "
import sys, json
d=json.load(sys.stdin)
print('📜', d.get('content','-'))
print('—— 《' + d.get('origin','-') + '》  ' + d.get('author','-'))
cat=d.get('category') or ''
if cat: print('🏷️', cat)
")
    reply_text "$to" "$out"
    return 0
  fi
  # 关键词 → 让 qoder 选一首并解读（更可靠）
  reply_text "$to" "📜 查诗：${rest} …"
  local workspace; workspace="${WORK_ROOT}/${key}"; mkdir -p "$workspace"
  local model; model=$(model_for_key "$key")
  local prompt="围绕主题/关键词「${rest}」，选一首中国古典诗词（唐诗/宋词/元曲都可），按下面格式回答：

【标题】《...》 ‧ 作者(朝代)
【全文】
<逐行原文>

【白话直译】
<一两句话>

【为何切题】
<一两句>

只输出上面 4 个区块。"
  local ans; ans=$(run_with_heartbeat "$to" "$key" "$workspace" "$model" "$prompt" 2>/dev/null)
  [[ -z "$ans" ]] && ans="❌ qoder 没返回"
  reply_text "$to" "$ans"
}

register_command "/poem" plugin_poem "古诗词：/poem [random|<关键词>]"
