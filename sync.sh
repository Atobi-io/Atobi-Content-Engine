#!/usr/bin/env bash
#
# sync.sh — pull the latest Atobi Content Engine skills and (re)link them into
# the Claude skills folder. Safe to run repeatedly; used both by install.sh and
# by the scheduled job. Only touches ce-* symlinks that point into this repo.
#
set -euo pipefail

# The repo is wherever this script lives, so a teammate can clone it anywhere.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

mkdir -p "$SKILLS_DIR"

# 1. Pull latest (fast-forward only; never rewrites local state).
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO_DIR" fetch --quiet origin
  git -C "$REPO_DIR" pull --ff-only --quiet || {
    echo "$LOG_PREFIX WARN: git pull --ff-only failed (local changes?). Linking current checkout." >&2
  }
fi

# 2. Link every ce-* skill that has a SKILL.md into the skills folder.
linked=0
for skill in "$REPO_DIR"/ce-*/; do
  [ -f "${skill}SKILL.md" ] || continue
  name="$(basename "$skill")"
  target="${skill%/}"
  link="$SKILLS_DIR/$name"

  # Replace only if missing or already pointing at us; never clobber a real dir.
  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$target" ] || ln -sfn "$target" "$link"
  elif [ -e "$link" ]; then
    echo "$LOG_PREFIX SKIP: $link exists and is not a symlink — leaving it alone." >&2
    continue
  else
    ln -sfn "$target" "$link"
  fi
  linked=$((linked + 1))
done

# 3. Prune dead links: ce-* symlinks that point into this repo but whose
#    source folder no longer exists (a skill was removed upstream).
for link in "$SKILLS_DIR"/ce-*; do
  [ -L "$link" ] || continue
  dest="$(readlink "$link")"
  case "$dest" in
    "$REPO_DIR"/*)
      [ -e "$dest" ] || { rm "$link"; echo "$LOG_PREFIX PRUNED: $(basename "$link")"; } ;;
  esac
done

echo "$LOG_PREFIX synced $linked skill(s) from $REPO_DIR -> $SKILLS_DIR"
