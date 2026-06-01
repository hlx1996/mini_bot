# plugins/stats.sh — /export /stats /usage /quota
# 派发到 bot.sh 里已有的 handle_export / handle_stats / handle_usage / handle_quota。

plugin_export() {
  local to="$1" key="$2" rest="$3"
  handle_export "$to" "$key" "$rest"
}

plugin_stats() {
  local to="$1" key="$2" rest="$3"
  handle_stats "$to"
}

plugin_usage() {
  local to="$1" key="$2" rest="$3"
  handle_usage "$to" "$rest"
}

plugin_quota() {
  local to="$1" key="$2" rest="$3"
  handle_quota "$to" "$key" "$rest"
}

register_command "/export" plugin_export "导出本会话最近 N 条：/export [n]"
register_command "/stats"  plugin_stats  "全局统计"
register_command "/usage"  plugin_usage  "用量统计：/usage [day|week|all]"
register_command "/quota"  plugin_quota  "配额/用量：/quota [show|tokens [day|week|all]|set <n>|reset]"
