#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_DIR="$PROJECT_DIR/Distribution/PolyPals.app"
DMG_PATH="$PROJECT_DIR/Distribution/PolyPals-0.4.0.dmg"
: ${POLYPALS_SIGNING_IDENTITY:?Set POLYPALS_SIGNING_IDENTITY to a Developer ID Application identity}
: ${POLYPALS_NOTARY_PROFILE:?Set POLYPALS_NOTARY_PROFILE to an xcrun notarytool Keychain profile}

if [[ ! -d "$APP_DIR" ]]; then
  "$PROJECT_DIR/Scripts/build-app.sh"
fi

codesign --force --deep --options runtime --timestamp \
  --entitlements "$PROJECT_DIR/Distribution/PolyPals.entitlements" \
  --sign "$POLYPALS_SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname PolyPals -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$POLYPALS_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
print "Signed and notarized $DMG_PATH"
