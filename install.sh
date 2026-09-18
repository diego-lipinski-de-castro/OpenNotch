#!/bin/sh
# Installs OpenNotch: the app, the reporter CLI, and an adapter for every
# supported client found on this machine.
#
#   ./install.sh                 app + CLI + auto-detected adapters
#   ./install.sh --app-only      skip the adapters
#   ./install.sh --uninstall     remove everything
set -eu

cd "$(dirname "$0")"
REPO="$(pwd)"
ON_DIR="${OPENNOTCH_DIR:-$HOME/.opennotch}"
APP="/Applications/OpenNotch.app"

# Every adapter directory that exists is offered; adding a client means adding
# a directory here, not editing this script.
adapters_for() {
  for dir in "$REPO"/adapters/*/; do
    name=$(basename "$dir")
    [ "$name" = "_lib" ] && continue
    [ -x "$dir/install.sh" ] || continue
    case "$name" in
      claude-code) [ -d "$HOME/.claude" ] || continue ;;
      codex)       [ -d "$HOME/.codex" ]  || continue ;;
    esac
    printf '%s\n' "$name"
  done
}

if [ "${1:-}" = "--uninstall" ]; then
  for name in $(adapters_for); do
    echo "==> uninstalling adapter: $name"
    "$REPO/adapters/$name/install.sh" --uninstall || true
  done
  pkill -x OpenNotch 2>/dev/null || true
  rm -rf "$APP"
  rm -rf "$ON_DIR/bin"
  echo "==> removed $APP and $ON_DIR/bin"
  echo "    session state left in $ON_DIR (delete it by hand if you want)"
  exit 0
fi

echo "==> installing CLI into $ON_DIR/bin"
mkdir -p "$ON_DIR/bin" "$ON_DIR/sessions"
install -m 0755 bin/opennotch "$ON_DIR/bin/opennotch"
install -m 0755 adapters/_lib/hook-adapter.sh "$ON_DIR/bin/hook-adapter.sh"

./build.sh --install

if [ "${1:-}" = "--app-only" ]; then
  echo "==> done (adapters skipped)"
  exit 0
fi

found=0
for name in $(adapters_for); do
  echo "==> installing adapter: $name"
  "$REPO/adapters/$name/install.sh"
  found=1
done
[ "$found" -eq 1 ] || echo "==> no supported clients detected"

echo
echo "Done. Add $ON_DIR/bin to your PATH to use 'opennotch' directly:"
echo "    export PATH=\"\$PATH:$ON_DIR/bin\""
