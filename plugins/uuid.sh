# plugins/uuid.sh — /uuid [n] 生成 n 个 UUIDv4（默认 1，上限 20）
plugin_uuid() {
  local to="$1" key="$2" rest="$3"
  local n="${rest%% *}"
  [[ -z "$n" || ! "$n" =~ ^[0-9]+$ ]] && n=1
  (( n < 1 )) && n=1
  (( n > 20 )) && n=20
  local out="🆔 UUIDv4:" i u
  for ((i=0; i<n; i++)); do
    if command -v uuidgen >/dev/null 2>&1; then
      u=$(uuidgen | tr 'A-Z' 'a-z')
    else
      u=$(python3 -c 'import uuid;print(uuid.uuid4())')
    fi
    out+="
  ${u}"
  done
  reply_text "$to" "$out"
}
register_command "/uuid" plugin_uuid "生成 UUIDv4：/uuid [n]"
