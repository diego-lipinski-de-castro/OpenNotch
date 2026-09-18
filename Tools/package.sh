#!/bin/bash
# Builds a zip you can hand to someone who does not have a Swift toolchain:
# the app built for both architectures, the CLI, the adapters, and the
# installer that wires them together.
#
#   Tools/package.sh
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="OpenNotch"
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' build.sh)"
STAGE="build/dist/${NAME}"
ZIP="build/${NAME}-${VERSION}.zip"

./build.sh --universal

echo "==> Staging ${STAGE}"
rm -rf "build/dist" "$ZIP"
mkdir -p "$STAGE"
cp -R "build/${NAME}.app" "$STAGE/"
cp -R bin adapters install.sh README.md "$STAGE/"

# Nothing here was downloaded, but the zip will be, and the flag rides along on
# whatever is inside it.
xattr -cr "$STAGE" 2>/dev/null || true

echo "==> Zipping ${ZIP}"
# ditto rather than zip: it is the only one that preserves the app bundle's
# symlinks and resource forks intact, and a bundle that arrives subtly mangled
# fails its signature check rather than failing to copy.
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

echo
echo "Built $(du -h "$ZIP" | cut -f1) — $ZIP"
echo "Architectures: $(lipo -archs "build/${NAME}.app/Contents/MacOS/${NAME}")"
echo
echo "Tell them: unzip it, then in Terminal run ./install.sh from inside the folder."
