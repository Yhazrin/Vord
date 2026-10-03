#!/bin/bash
set -euo pipefail
VORD_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VORD_APP="$VORD_ROOT/build/Build/Products/Release.noindex/Vord.app"
if [[ ! -d "$VORD_APP" ]]; then
  echo 'Build the Release app first.' >&2
  exit 1
fi
codesign --verify --deep --strict "$VORD_APP"
VORD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$VORD_APP/Contents/Info.plist")
VORD_DEST="$VORD_ROOT/build/releases/Vord-macOS-$VORD_VERSION.zip"
mkdir -p "$(dirname "$VORD_DEST")"
ditto -c -k --sequesterRsrc --keepParent "$VORD_APP" "$VORD_DEST"
(cd "$(dirname "$VORD_DEST")" && shasum -a 256 "$(basename "$VORD_DEST")" > "$(basename "$VORD_DEST").sha256")
echo "$VORD_DEST"
