#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_DIR="$PROJECT_DIR/Distribution/PolyPals.app"
DMG_PATH="$PROJECT_DIR/Distribution/PolyPals-0.4.0-local.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  "$PROJECT_DIR/Scripts/build-app.sh"
fi

rm -f "$DMG_PATH"
hdiutil create \
  -volname "PolyPals Local" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "Built local, ad-hoc-signed test image: $DMG_PATH"
