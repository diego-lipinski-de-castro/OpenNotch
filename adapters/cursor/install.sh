#!/bin/sh
# OpenNotch adapter for Cursor.
# Registers hooks in ~/.cursor/hooks.json. Existing hooks are preserved.
set -eu

SOURCE=cursor
HOOKS="${CURSOR_HOOKS:-$HOME/.cursor/hooks.json}"
ON_DIR="${OPENNOTCH_DIR:-$HOME/.opennotch}"
ADAPTER="$ON_DIR/bin/hook-adapter.sh"
MERGE="$(cd "$(dirname "$0")/../_lib" && pwd)/merge-hooks.sh"

[ -x "$ADAPTER" ] || { echo "run ./install.sh at the repo root first"; exit 1; }

if [ -s "$HOOKS" ]; then
  backup="$HOOKS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$HOOKS" "$backup"
  echo "==> backed up $HOOKS -> $backup"
fi

if [ "${1:-}" = "--uninstall" ]; then
  "$MERGE" --file "$HOOKS" --style flat --remove "hook-adapter.sh' --source $SOURCE"
  echo "==> removed Cursor hooks"
  exit 0
fi

map() {
  "$MERGE" --file "$HOOKS" --style flat --event "$1" \
    --command "sh '$ADAPTER' --source $SOURCE $2"
  echo "    $1 -> $2"
}

# Cursor's vocabulary is lowerCamelCase and its own shape: the turn begins when
# the prompt is submitted rather than at a separate "user prompt" event, and
# `stop` reports how the turn ended instead of splitting into several events.
map sessionStart       "--state idle --owner Cursor"
map beforeSubmitPrompt "--state running --owner Cursor"
map stop               "--state done --state-map status:completed=done,aborted=idle,error=error"
map sessionEnd         "--clear"

# Deliberately not mapped: `waiting`.
#
# Cursor has no event that means "blocked on a human". beforeShellExecution
# looked like one and is not — it fires before Cursor decides whether to ask,
# so on an auto-approving setup it would flash amber on every command the agent
# ran. Amber is the loudest thing this product does and the only one that asks
# for a human; spending it on a false positive costs more than the missing
# state does. Cursor sessions show running, done and error.

"$ON_DIR/bin/opennotch" source --id "$SOURCE" \
  --name "Cursor" --symbol "cube" --accent "#E4E4E4"

echo "==> Cursor adapter installed (picked up by running sessions; restart one if it is not)"
