#!/usr/bin/env bash
#
# install.sh — one-time setup for the Atobi Content Engine skill sync.
# Links the skills into ~/.claude/skills and schedules an automatic pull so
# new/changed skills appear without any manual step.
#
# Usage (after cloning the repo anywhere you like):
#   ./install.sh                 # link + schedule every 30 min (default)
#   SYNC_INTERVAL=3600 ./install.sh   # custom interval, in seconds
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${SYNC_INTERVAL:-1800}"   # seconds between pulls (default 30 min)
LABEL="io.atobi.content-engine-sync"

chmod +x "$REPO_DIR/sync.sh"

echo "==> Initial sync"
"$REPO_DIR/sync.sh"

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  # --- macOS: launchd user agent ---
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO_DIR/sync.sh</string>
  </array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$REPO_DIR/.sync.log</string>
  <key>StandardErrorPath</key><string>$REPO_DIR/.sync.log</string>
</dict>
</plist>
PLIST_EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "==> Scheduled via launchd every ${INTERVAL}s ($PLIST)"
  echo "    Stop with:  launchctl unload \"$PLIST\""
else
  # --- Linux/other: cron ---
  MINUTES=$(( INTERVAL / 60 )); [ "$MINUTES" -lt 1 ] && MINUTES=1
  CRON_LINE="*/$MINUTES * * * * /bin/bash $REPO_DIR/sync.sh >> $REPO_DIR/.sync.log 2>&1 # $LABEL"
  ( crontab -l 2>/dev/null | grep -v "# $LABEL" ; echo "$CRON_LINE" ) | crontab -
  echo "==> Scheduled via cron every ${MINUTES} min"
  echo "    Remove with: crontab -e  (delete the line tagged # $LABEL)"
fi

echo "==> Done. Skills are linked into ~/.claude/skills and will stay in sync."
