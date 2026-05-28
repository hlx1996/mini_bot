#!/usr/bin/env bash
# install.sh — install mini_bot as a systemd service (linux) or launchd agent (macOS),
# plus a daily log-rotation rule. Idempotent: safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-auto}"   # auto | systemd | launchd | none
USER_NAME="${USER:-$(id -un)}"

usage() {
  cat <<EOF
Usage: $0 [systemd|launchd|none]

  systemd       (linux)  install a user systemd service that runs bot.sh
  launchd       (macOS)  install a LaunchAgent
  none                   only install logrotate / log-rotate-cron script
  (no arg = auto-detect)
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $# -ge 1 ]] && TARGET="$1"

if [[ "$TARGET" == "auto" ]]; then
  case "$(uname -s)" in
    Linux)  TARGET="systemd" ;;
    Darwin) TARGET="launchd" ;;
    *)      TARGET="none" ;;
  esac
fi

mkdir -p "$SCRIPT_DIR/state/logs"

install_logrotate() {
  # Drop a sister rotator script + cron entry that compresses + truncates daily.
  cat > "$SCRIPT_DIR/rotate-logs.sh" <<'ROT'
#!/usr/bin/env bash
# Rotate mini_bot logs:  keep 7 days, gzip older than 1 day, drop >7d.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state/logs"
[[ -d "$DIR" ]] || exit 0
find "$DIR" -type f -name '*.log' -size +5M -exec sh -c '
  for f; do mv "$f" "$f.$(date +%Y%m%d-%H%M%S)" && : > "$f"; done
' sh {} +
find "$DIR" -type f -name '*.log.*' ! -name '*.gz' -mtime +0 -exec gzip -9 {} \;
find "$DIR" -type f -name '*.gz' -mtime +7 -delete
find "$DIR" -type f -name 'events.jsonl' -size +20M -exec sh -c '
  for f; do tail -c 10485760 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
' sh {} +
ROT
  chmod +x "$SCRIPT_DIR/rotate-logs.sh"
  echo "[install] rotate-logs.sh written"
  # add a cron entry if cron is available and not already present
  if command -v crontab >/dev/null 2>&1; then
    local tag="# mini_bot:rotate"
    local line="0 3 * * * $SCRIPT_DIR/rotate-logs.sh >/dev/null 2>&1  $tag"
    local cur; cur=$(crontab -l 2>/dev/null || true)
    if ! grep -qF "$tag" <<<"$cur"; then
      { [[ -n "$cur" ]] && echo "$cur"; echo "$line"; } | crontab -
      echo "[install] cron entry added (daily 03:00)"
    else
      echo "[install] cron entry already present"
    fi
  fi
}

install_systemd() {
  local unit="$HOME/.config/systemd/user/mini_bot.service"
  mkdir -p "$(dirname "$unit")"
  cat > "$unit" <<EOF
[Unit]
Description=mini_bot (WeChat + Lark / qoder bridge)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/env bash $SCRIPT_DIR/bot.sh
Restart=on-failure
RestartSec=5s
StandardOutput=append:$SCRIPT_DIR/state/logs/service.log
StandardError=append:$SCRIPT_DIR/state/logs/service.err
Environment=BOT_HOME=$SCRIPT_DIR/state

[Install]
WantedBy=default.target
EOF
  echo "[install] systemd unit -> $unit"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable --now mini_bot.service || true
    echo "[install] systemd: enable+start attempted. Status:"
    systemctl --user status mini_bot.service --no-pager || true
  else
    echo "[install] systemctl not available; copy unit manually."
  fi
}

install_launchd() {
  local plist="$HOME/Library/LaunchAgents/com.minibot.bot.plist"
  mkdir -p "$(dirname "$plist")"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.minibot.bot</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>bash</string>
    <string>$SCRIPT_DIR/bot.sh</string>
  </array>
  <key>WorkingDirectory</key><string>$SCRIPT_DIR</string>
  <key>EnvironmentVariables</key><dict>
    <key>BOT_HOME</key><string>$SCRIPT_DIR/state</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$SCRIPT_DIR/state/logs/service.log</string>
  <key>StandardErrorPath</key><string>$SCRIPT_DIR/state/logs/service.err</string>
</dict></plist>
EOF
  echo "[install] launchd plist -> $plist"
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load -w "$plist" && echo "[install] launchd loaded" || {
    echo "[install] launchctl load failed (you can load manually)" >&2
  }
}

case "$TARGET" in
  systemd)  install_systemd; install_logrotate ;;
  launchd)  install_launchd; install_logrotate ;;
  none)     install_logrotate ;;
  *)        usage; exit 1 ;;
esac

echo
echo "[install] DONE. Useful commands:"
case "$TARGET" in
  systemd)
    echo "  systemctl --user status  mini_bot"
    echo "  systemctl --user restart mini_bot"
    echo "  journalctl --user -u mini_bot -f"
    ;;
  launchd)
    echo "  launchctl list | grep minibot"
    echo "  launchctl kickstart -k gui/\$(id -u)/com.minibot.bot"
    echo "  tail -f $SCRIPT_DIR/state/logs/service.log"
    ;;
esac
echo "  bash $SCRIPT_DIR/rotate-logs.sh    # rotate now"
