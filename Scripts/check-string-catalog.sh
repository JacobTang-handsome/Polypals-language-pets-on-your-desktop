#!/bin/sh
set -eu
before=$(shasum -a 256 Sources/PolyPals/Resources/Localizable.xcstrings | awk '{print $1}')
Scripts/sync-string-catalog.rb >/dev/null
after=$(shasum -a 256 Sources/PolyPals/Resources/Localizable.xcstrings | awk '{print $1}')
if [ "$before" != "$after" ]; then
  echo "Localizable.xcstrings is missing static Simplified Chinese keys. Run Scripts/sync-string-catalog.rb."
  exit 1
fi
