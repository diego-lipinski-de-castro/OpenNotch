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

# /Applications needs an admin account. A standard user gets ~/Applications,
# which macOS treats as a real applications folder and which needs nobody's
# password.
APP_DIR="/Applications"
[ -w "$APP_DIR" ] || APP_DIR="$HOME/Applications"
APP="$APP_DIR/OpenNotch.app"

# macOS asks an app's permission before letting it read ~/Downloads, ~/Desktop
# or ~/Documents. When that was declined — or never asked, which happens when a
# terminal is launched in ways the prompt does not cover — every read fails with
# EPERM, printed as "Operation not permitted". It is the most common way this
# script dies, and it dies reading its own payload, which looks like anything
# but a privacy setting.
preflight() {
  for f in "$REPO/bin/opennotch" "$REPO/adapters/_lib/hook-adapter.sh"; do
    head -c 1 "$f" >/dev/null 2>&1 && continue
    cat >&2 <<MSG
install: cannot read $f
         ("Operation not permitted" means macOS is blocking the folder, not
          that the file is missing or that you need sudo.)

  Move this folder somewhere macOS does not guard, and run it from there:

      mv "$REPO" ~/OpenNotch && cd ~/OpenNotch && ./install.sh

  Or grant the access: System Settings > Privacy & Security >
  Files and Folders, and enable the folder for your terminal app.
  Full Disk Access works too, and covers every folder at once.
MSG
    exit 1
  done
}
preflight

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
      cursor)      [ -d "$HOME/.cursor" ] || continue ;;
      gemini)      [ -d "$HOME/.gemini" ] || continue ;;
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
  # Either location, since which one was used depended on the account.
  rm -rf "/Applications/OpenNotch.app" "$HOME/Applications/OpenNotch.app"
  rm -rf "$ON_DIR/bin"
  echo "==> removed OpenNotch.app and $ON_DIR/bin"
  echo "    session state left in $ON_DIR (delete it by hand if you want)"
  exit 0
fi

# Either a prebuilt bundle sitting next to this script — which is how a build
# handed to someone else arrives — or one built here from source.
install_app() {
  if [ -d "$REPO/OpenNotch.app" ]; then
    echo "==> installing $APP (prebuilt)"
    pkill -x OpenNotch 2>/dev/null || true
    mkdir -p "$APP_DIR"
    rm -rf "$APP"
    if ! cp -R "$REPO/OpenNotch.app" "$APP"; then
      echo "install: could not copy the app into $APP_DIR" >&2
      exit 1
    fi
    # An archive that arrived over the network is quarantined, and this app is
    # signed ad-hoc rather than notarised, so Gatekeeper refuses to open it at
    # all until the flag is cleared. Doing it here rather than telling people to
    # paste an xattr command they cannot evaluate.
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
    open "$APP"
  elif [ -x "$REPO/build.sh" ] && command -v swift >/dev/null 2>&1; then
    "$REPO/build.sh" --install
  else
    echo "install: no OpenNotch.app beside this script, and no Swift toolchain" >&2
    echo "         to build one. Install Xcode's command line tools, or use a" >&2
    echo "         package that includes the app." >&2
    exit 1
  fi
}

echo "==> installing CLI into $ON_DIR/bin"
mkdir -p "$ON_DIR/bin" "$ON_DIR/sessions"
install -m 0755 bin/opennotch "$ON_DIR/bin/opennotch"
install -m 0755 adapters/_lib/hook-adapter.sh "$ON_DIR/bin/hook-adapter.sh"

install_app

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
