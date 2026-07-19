#!/usr/bin/env bash
#
# uninstall.sh — stop the scheduled sync and remove the ce-* symlinks this
# repo created in ~/.claude/skills. Does NOT delete the repo clone itself.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
LABEL="io.atobi.content-engine-sync"

if [ "$(uname -s)" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "==> Removed launchd job"
else
  ( crontab -l 2>/dev/null | grep -v "# $LABEL" ) | crontab - || true
  echo "==> Removed cron entry"
fi

for link in "$SKILLS_DIR"/ce-*; do
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in
    "$REPO_DIR"/*) rm "$link"; echo "==> Unlinked $(basename "$link")" ;;
  esac
done

echo "==> Uninstalled. Repo clone left in place at $REPO_DIR"
