#!/bin/sh
# OpenNotch adapter for Gemini CLI.
# Registers hooks in ~/.gemini/settings.json. Existing hooks are preserved.
set -eu

SOURCE=gemini
SETTINGS="${GEMINI_SETTINGS:-$HOME/.gemini/settings.json}"
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
  echo "==> removed Gemini hooks"
  exit 0
fi

# Gemini counts its hook timeouts in milliseconds, where the other three count
# seconds. The default of 5 would be five thousandths of a second here, and a
# hook killed that fast looks exactly like a client that never fired at all.
map() {
  "$MERGE" --file "$SETTINGS" --timeout 5000 --event "$1" \
    --command "sh '$ADAPTER' --source $SOURCE $2"
  echo "    $1 -> $2"
}

# Gemini's payload is already the shape hook-adapter.sh speaks — session_id,
# cwd and transcript_path — so this is only an event mapping. Its vocabulary
# splits the turn around the agent rather than the prompt: BeforeAgent fires
# after submission and AfterAgent after the final response.
map SessionStart "--state idle --owner gemini"
map BeforeAgent  "--state running --owner gemini"
# Tool permission prompts arrive as notifications, the same signal Claude Code
# gives. Guarded, so a notification outside a turn cannot turn the notch amber.
map Notification "--state waiting --if-state running"
# Nothing says the human answered. A tool cannot run until the prompt is
# resolved, so its completion is the resume signal — a no-op on every tool call
# but the first one after a prompt.
map AfterTool    "--state running --if-state waiting"
map AfterAgent   "--state done"
map SessionEnd   "--clear"

"$ON_DIR/bin/opennotch" source --id "$SOURCE" \
  --name "Gemini" --symbol "sparkles" --accent "#8E9BFF"

echo "==> Gemini adapter installed (picked up by running sessions; restart one if it is not)"
