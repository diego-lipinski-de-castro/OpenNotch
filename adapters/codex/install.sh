#!/bin/sh
# OpenNotch adapter for Codex.
# Registers hooks in ~/.codex/hooks.json. Existing hooks are preserved.
set -eu

SOURCE=codex
HOOKS="${CODEX_HOOKS:-$HOME/.codex/hooks.json}"
CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
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
  "$MERGE" --file "$HOOKS" --remove "hook-adapter.sh' --source $SOURCE"
  echo "==> removed Codex hooks"
  exit 0
fi

map() {
  "$MERGE" --file "$HOOKS" --event "$1" \
    --command "sh '$ADAPTER' --source $SOURCE $2"
  echo "    $1 -> $2"
}

# Codex has a richer vocabulary than Claude Code: PermissionRequest is an
# exact "blocked on you" signal, and Interrupt closes the turn that Stop
# would otherwise leave spinning.
map SessionStart      "--state idle --owner codex"
map UserPromptSubmit  "--state running --owner codex"
map PermissionRequest "--state waiting --if-state running"
# PermissionRequest says the turn stopped; nothing says it started again. A
# tool cannot run until the request is resolved, so its completion is the
# resume signal. Guarded, so it no-ops on every other tool call.
map PostToolUse       "--state running --if-state waiting"
map Stop              "--state done"
map Interrupt         "--state idle"
map SessionEnd        "--clear"

"$ON_DIR/bin/opennotch" source --id "$SOURCE" \
  --name "Codex" --symbol "chevron.left.forwardslash.chevron.right" --accent "#10A37F"

if ! grep -qE '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true' "$CONFIG" 2>/dev/null; then
  echo
  echo "!!  Codex hooks are not enabled. Add this to $CONFIG:"
  echo "        [features]"
  echo "        hooks = true"
fi

echo "==> Codex adapter installed (picked up by running sessions; restart one if it is not)"
