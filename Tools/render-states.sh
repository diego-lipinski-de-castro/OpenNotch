#!/bin/bash
# Renders every notch state to PNGs without showing it on screen.
#   Tools/render-states.sh [output-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/render}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Everything but main.swift, which brings its own entry point.
SRC=$(ls Sources/OpenNotch/*.swift | grep -v '/main.swift$')
# main.swift also owns StatePaths, which the harness does not need.
swiftc -O -parse-as-library $SRC Tools/render-states.swift \
  -o "$TMP/render" -framework AppKit 2>&1 | grep -v '^$' || true
[ -x "$TMP/render" ] || { echo "render: build failed" >&2; exit 1; }
"$TMP/render" "$OUT"
