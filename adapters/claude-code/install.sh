#!/bin/sh
# OpenNotch adapter for Claude Code.
# Registers hooks in ~/.claude/settings.json. Existing hooks are preserved.
set -eu

SOURCE=claude-code
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
ON_DIR="${OPENNOTCH_DIR:-$HOME/.opennotch}"
ADAPTER="$ON_DIR/bin/hook-adapter.sh"
MERGE="$(cd "$(dirname "$0")/../_lib" && pwd)/merge-hooks.sh"

[ -x "$ADAPTER" ] || { echo "run ./install.sh at the repo root first"; exit 1; }

if [ -s "$SETTINGS" ]; then
  backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$backup"
  echo "==> backed up $SETTINGS -> $backup"
fi

if [ "${1:-}" = "--uninstall" ]; then
  "$MERGE" --file "$SETTINGS" --remove "hook-adapter.sh' --source $SOURCE"
  echo "==> removed Claude Code hooks"
  exit 0
fi

map() {
  "$MERGE" --file "$SETTINGS" --event "$1" \
    --command "sh '$ADAPTER' --source $SOURCE $2"
  echo "    $1 -> $2"
}

# Claude Code's event vocabulary, mapped onto OpenNotch states.
map SessionStart     "--state idle --owner claude"
map UserPromptSubmit "--state running --owner claude"
map Notification     "--state waiting --if-state running"
# Nothing in Claude Code's vocabulary says "the human answered", so a granted
# permission used to leave the session amber for the rest of the turn. A tool
# cannot run until the prompt is resolved, so its completion is the resume
# signal. Guarded, so it is a no-op on every tool call but the first one after
# a prompt.
map PostToolUse      "--state running --if-state waiting"
map Stop             "--state done"
map SessionEnd       "--clear"

"$ON_DIR/bin/opennotch" source --id "$SOURCE" \
  --name "Claude Code" --symbol "sparkle" --accent "#D97757"

echo "==> Claude Code adapter installed (picked up by running sessions; restart one if it is not)"
