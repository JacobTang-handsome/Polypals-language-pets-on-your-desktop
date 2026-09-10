#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
BUILD_DIR="$PROJECT_DIR/.build-release"
APP_DIR="$PROJECT_DIR/Distribution/PolyPals.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCE_DIR="$APP_DIR/Contents/Resources"

if [[ $(uname -m) != arm64 ]]; then
  print -u2 "PolyPals MVP is locked to Apple Silicon (arm64)."
  exit 1
fi

swift build -c release --arch arm64 --disable-sandbox --scratch-path "$BUILD_DIR"
rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RESOURCE_DIR"
cp "$PROJECT_DIR/Distribution/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/arm64-apple-macosx/release/PolyPals" "$BIN_DIR/PolyPals"
cp "$PROJECT_DIR/Distribution/AppIcon.icns" "$RESOURCE_DIR/AppIcon.icns"

RESOURCE_BUNDLE="$BUILD_DIR/arm64-apple-macosx/release/PolyPals_PolyPals.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCE_DIR/"
fi

chmod 755 "$BIN_DIR/PolyPals"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
print "Built $APP_DIR"
