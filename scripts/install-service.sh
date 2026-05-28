#!/usr/bin/env bash
# install-service.sh — install mini_bot as an auto-start service.
#
# Usage:
#   ./scripts/install-service.sh install     # install + start + enable on boot
#   ./scripts/install-service.sh uninstall   # stop + remove
#   ./scripts/install-service.sh status      # show status
#   ./scripts/install-service.sh restart     # restart the service
#
# Detects OS: macOS  -> launchd user agent  (~/Library/LaunchAgents/com.mini-bot.plist)
#             Linux  -> systemd user unit   (~/.config/systemd/user/mini_bot.service)
#
# bot.sh must be runnable as `bash bot.sh` from this repo.
# Logs go to state/logs/ (same place as a manual run).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOT_SH="$REPO_DIR/bot.sh"
STATE_DIR="${BOT_HOME:-$REPO_DIR/state}"
LOG_DIR="$STATE_DIR/logs"
SVC_NAME="mini_bot"

[[ -x "$BOT_SH" || -f "$BOT_SH" ]] || { echo "❌ bot.sh not found at $BOT_SH" >&2; exit 1; }
mkdir -p "$LOG_DIR"

OS="$(uname -s)"
ACTION="${1:-install}"

bash_bin="$(command -v bash)"

# Try to capture user's interactive PATH so the service can find qodercli / lark-cli /
# python3 / jq the same way the shell does. Fallback to /usr/local/bin:/usr/bin:/bin.
get_user_path() {
  local p
  p=$("$bash_bin" -lc 'echo -n "$PATH"' 2>/dev/null || true)
  [[ -z "$p" ]] && p="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
  echo "$p"
}

##############################################################################
# macOS — launchd
##############################################################################

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_LABEL="com.mini-bot"
PLIST_FILE="$PLIST_DIR/$PLIST_LABEL.plist"

mac_install() {
  if [[ ! -w "$PLIST_DIR" ]] && [[ ! -e "$PLIST_FILE" ]]; then
    mkdir -p "$PLIST_DIR" 2>/dev/null || true
  fi
  if [[ ! -w "$PLIST_DIR" ]]; then
    echo "⚠️  $PLIST_DIR is not writable (corporate-managed Mac)."
    echo "   Falling back to a user-level watchdog (no admin needed)."
    fallback_install
    return
  fi
  local user_path; user_path=$(get_user_path)
  cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bash_bin</string>
    <string>$BOT_SH</string>
  </array>
  <key>WorkingDirectory</key><string>$REPO_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$HOME</string>
    <key>PATH</key><string>$user_path</string>
    <key>BOT_HOME</key><string>$STATE_DIR</string>
    <key>LANG</key><string>en_US.UTF-8</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$LOG_DIR/launchd.out</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/launchd.err</string>
  <key>ThrottleInterval</key><integer>10</integer>
</dict>
</plist>
PLIST
  # bootout if previously loaded
  launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE"
  launchctl enable    "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
  launchctl kickstart "gui/$(id -u)/$PLIST_LABEL"
  echo "✅ launchd agent installed: $PLIST_FILE"
  echo "   logs: $LOG_DIR/launchd.{out,err}"
  echo "   status: launchctl print gui/$(id -u)/$PLIST_LABEL | head"
}

mac_uninstall() {
  if [[ -f "$PLIST_FILE" ]]; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
    rm -f "$PLIST_FILE" 2>/dev/null || true
    echo "🗑  launchd agent removed."
  fi
  if [[ -f "$WATCHDOG" ]] || [[ -f "$WATCHDOG_PIDFILE" ]] || grep -q "mini_bot autostart" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile" 2>/dev/null; then
    fallback_uninstall
  fi
}

mac_status() {
  if [[ -f "$PLIST_FILE" ]]; then
    echo "plist: $PLIST_FILE"
    launchctl print "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null | grep -E "state|pid|last exit code" | head -5 || \
      echo "(not loaded)"
  elif [[ -f "$WATCHDOG_PIDFILE" ]]; then
    echo "mode: fallback watchdog"
    fallback_status
  else
    echo "(not installed)"
  fi
}

mac_restart() {
  if [[ -f "$PLIST_FILE" ]]; then
    launchctl kickstart -k "gui/$(id -u)/$PLIST_LABEL"
    echo "🔄 restarted."
  else
    fallback_restart
  fi
}

##############################################################################
# Fallback — pure user-mode watchdog (no LaunchAgents / systemd permissions)
##############################################################################
# Drops a watchdog script at $REPO_DIR/scripts/watchdog.sh that nohups bot.sh
# and respawns it on crash, plus a one-line hook in your shell rc that calls
# the watchdog at login. Works on any locked-down macOS / Linux laptop.

WATCHDOG="$REPO_DIR/scripts/watchdog.sh"
WATCHDOG_PIDFILE="$STATE_DIR/watchdog.pid"
SHELL_RC=""
detect_shell_rc() {
  case "${SHELL##*/}" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
  esac
  [[ -e "$SHELL_RC" ]] || touch "$SHELL_RC"
}

write_watchdog() {
  cat > "$WATCHDOG" <<WD
#!/usr/bin/env bash
# mini_bot watchdog — respawns bot.sh on crash, idempotent on repeated runs.
REPO_DIR="$REPO_DIR"
STATE_DIR="$STATE_DIR"
LOG_DIR="$LOG_DIR"
PID_FILE="$WATCHDOG_PIDFILE"
mkdir -p "\$LOG_DIR"
# already running?
if [[ -f "\$PID_FILE" ]] && kill -0 "\$(cat "\$PID_FILE")" 2>/dev/null; then
  exit 0
fi
echo \$\$ > "\$PID_FILE"
cd "\$REPO_DIR"
export BOT_HOME="\$STATE_DIR"
while true; do
  bash "\$REPO_DIR/bot.sh" >> "\$LOG_DIR/watchdog.out" 2>> "\$LOG_DIR/watchdog.err"
  echo "[watchdog \$(date +%FT%T)] bot.sh exited rc=\$?, restarting in 5s" >> "\$LOG_DIR/watchdog.err"
  sleep 5
done
WD
  chmod +x "$WATCHDOG"
}

fallback_install() {
  detect_shell_rc
  write_watchdog
  # add login-time hook
  local hook="# >>> mini_bot autostart >>>"
  local hook_end="# <<< mini_bot autostart <<<"
  if ! grep -q "$hook" "$SHELL_RC"; then
    cat >> "$SHELL_RC" <<RC

$hook
( nohup "$WATCHDOG" >/dev/null 2>&1 & ) 2>/dev/null
$hook_end
RC
    echo "✅ added autostart hook to $SHELL_RC"
  else
    echo "↺ autostart hook already present in $SHELL_RC"
  fi
  # also start it right now
  ( nohup "$WATCHDOG" >/dev/null 2>&1 & ) 2>/dev/null
  sleep 2
  echo "✅ watchdog launched. PID file: $WATCHDOG_PIDFILE"
  echo "   logs: $LOG_DIR/watchdog.{out,err}"
  echo
  echo "ℹ️  This fallback restarts the bot whenever you open a terminal / log in."
  echo "   For true on-boot (without login), need admin rights to install in"
  echo "   /Library/LaunchDaemons — ask your IT or use the systemd path on Linux."
}

fallback_uninstall() {
  detect_shell_rc
  if grep -q "# >>> mini_bot autostart >>>" "$SHELL_RC"; then
    # sed -i differs on mac vs gnu; use python for portability
    "${PYTHON_BIN:-python3}" - "$SHELL_RC" <<'PY'
import sys, re
p = sys.argv[1]
txt = open(p).read()
txt = re.sub(r"\n?# >>> mini_bot autostart >>>.*?# <<< mini_bot autostart <<<\n?",
             "\n", txt, flags=re.S)
open(p, "w").write(txt)
PY
    echo "🗑  removed autostart hook from $SHELL_RC"
  fi
  if [[ -f "$WATCHDOG_PIDFILE" ]]; then
    local wpid; wpid=$(cat "$WATCHDOG_PIDFILE")
    [[ -n "$wpid" ]] && kill "$wpid" 2>/dev/null || true
    rm -f "$WATCHDOG_PIDFILE"
  fi
  # also stop bot.sh chain
  for pat in "bot.sh" "wxlink subscribe" "lark-cli event"; do
    pgrep -f "$pat" 2>/dev/null | while read pp; do [ -n "$pp" ] && kill "$pp" 2>/dev/null; done
  done
  echo "🗑  fallback watchdog stopped."
}

fallback_status() {
  if [[ -f "$WATCHDOG_PIDFILE" ]] && kill -0 "$(cat "$WATCHDOG_PIDFILE")" 2>/dev/null; then
    echo "watchdog: ALIVE (pid $(cat "$WATCHDOG_PIDFILE"))"
    pgrep -af "bot.sh" | head -3
  else
    echo "watchdog: (not running)"
  fi
}

fallback_restart() {
  if [[ -f "$WATCHDOG_PIDFILE" ]]; then
    local wpid; wpid=$(cat "$WATCHDOG_PIDFILE")
    [[ -n "$wpid" ]] && kill "$wpid" 2>/dev/null || true
  fi
  for pat in "bot.sh" "wxlink subscribe" "lark-cli event"; do
    pgrep -f "$pat" 2>/dev/null | while read pp; do [ -n "$pp" ] && kill "$pp" 2>/dev/null; done
  done
  rm -f "$WATCHDOG_PIDFILE"
  sleep 2
  ( nohup "$WATCHDOG" >/dev/null 2>&1 & ) 2>/dev/null
  echo "🔄 watchdog restarted."
}

##############################################################################
# Linux — systemd user unit
##############################################################################

SYSTEMD_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$SYSTEMD_DIR/$SVC_NAME.service"

linux_install() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "⚠️  systemctl not found — falling back to user-mode watchdog."
    fallback_install
    return
  fi
  mkdir -p "$SYSTEMD_DIR"
  if [[ ! -w "$SYSTEMD_DIR" ]]; then
    echo "⚠️  $SYSTEMD_DIR not writable — falling back to user-mode watchdog."
    fallback_install
    return
  fi
  local user_path; user_path=$(get_user_path)
  cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=mini_bot — WeChat + Lark bot powered by qodercli
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$REPO_DIR
Environment=HOME=$HOME
Environment=PATH=$user_path
Environment=BOT_HOME=$STATE_DIR
Environment=LANG=en_US.UTF-8
ExecStart=$bash_bin $BOT_SH
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/systemd.out
StandardError=append:$LOG_DIR/systemd.err

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now "$SVC_NAME.service"
  # enable linger so service starts even before login
  loginctl enable-linger "$(id -un)" 2>/dev/null || true
  echo "✅ systemd user unit installed: $UNIT_FILE"
  echo "   status: systemctl --user status $SVC_NAME"
  echo "   logs:   journalctl --user -u $SVC_NAME -f"
}

linux_uninstall() {
  systemctl --user disable --now "$SVC_NAME.service" 2>/dev/null || true
  rm -f "$UNIT_FILE"
  systemctl --user daemon-reload || true
  echo "🗑  systemd user unit removed."
}

linux_status() {
  if [[ -f "$UNIT_FILE" ]]; then
    systemctl --user status "$SVC_NAME.service" --no-pager || true
  else
    echo "(not installed)"
  fi
}

linux_restart() {
  systemctl --user restart "$SVC_NAME.service"
  echo "🔄 restarted."
}

##############################################################################
# Dispatch
##############################################################################

case "$OS" in
  Darwin)  fn="mac" ;;
  Linux)   fn="linux" ;;
  *)       echo "❌ Unsupported OS: $OS"; exit 1 ;;
esac

case "$ACTION" in
  install)   ${fn}_install ;;
  uninstall) ${fn}_uninstall ;;
  status)    ${fn}_status ;;
  restart)   ${fn}_restart ;;
  *)         echo "Usage: $0 [install|uninstall|status|restart]"; exit 1 ;;
esac
