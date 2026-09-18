#!/bin/bash
# Builds OpenNotch.app into ./build.
#
#   --install     also copy it to /Applications and launch it
#   --universal   build for Apple silicon and Intel, for a build you intend to
#                 hand to someone else
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="OpenNotch"
BUNDLE_ID="com.castro.opennotch"
VERSION="1.0"
OUT="build/${APP_NAME}.app"

DO_INSTALL=0
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    --install)   DO_INSTALL=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    *) echo "build: unknown option '$arg'" >&2; exit 2 ;;
  esac
done

echo "==> Building release binary${ARCHS:+ (universal)}"
swift build -c release "${ARCHS[@]+"${ARCHS[@]}"}"
BIN="$(swift build -c release "${ARCHS[@]+"${ARCHS[@]}"}" --show-bin-path)/${APP_NAME}"

echo "==> Assembling ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/${APP_NAME}"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>OpenNotch</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

echo "==> Generating icon"
ICONTMP="$(mktemp -d)"
if swiftc -O Tools/make-icon.swift -o "$ICONTMP/make-icon" 2>/dev/null && "$ICONTMP/make-icon" "$ICONTMP" >/dev/null 2>&1; then
  ICONSET="$ICONTMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  cp "$ICONTMP/icon_16.png"   "$ICONSET/icon_16x16.png"
  cp "$ICONTMP/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
  cp "$ICONTMP/icon_32.png"   "$ICONSET/icon_32x32.png"
  cp "$ICONTMP/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
  cp "$ICONTMP/icon_128.png"  "$ICONSET/icon_128x128.png"
  cp "$ICONTMP/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
  cp "$ICONTMP/icon_256.png"  "$ICONSET/icon_256x256.png"
  cp "$ICONTMP/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
  cp "$ICONTMP/icon_512.png"  "$ICONSET/icon_512x512.png"
  cp "$ICONTMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "    (icns step skipped)"
else
  echo "    (icon generation skipped)"
fi
rm -rf "$ICONTMP"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || echo "    (codesign skipped)"

if [[ "$DO_INSTALL" == 1 ]]; then
  echo "==> Installing to /Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$OUT" "/Applications/${APP_NAME}.app"
  echo "==> Launching"
  open "/Applications/${APP_NAME}.app"
fi

echo "Done: $OUT"
