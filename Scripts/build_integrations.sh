#!/bin/bash
set -euo pipefail
VORD_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
VORD_OUT="${DERIVED_FILE_DIR:-$VORD_ROOT/build/integrations}"
mkdir -p "$VORD_OUT" "$VORD_ROOT/Vord/Resources"
VORD_SDK="$(xcrun --sdk macosx --show-sdk-path)"
for VORD_ARCH in arm64 x86_64; do
  xcrun swiftc -O -sdk "$VORD_SDK" -target "$VORD_ARCH-apple-macosx15.0" \
    "$VORD_ROOT/Integrations/NativeHost/main.swift" \
    "$VORD_ROOT/Vord/Core/Capture/ExternalCaptureRequest.swift" \
    "$VORD_ROOT/Vord/Core/Capture/BrowserIntegrationIdentity.swift" \
    -o "$VORD_OUT/VordSelectionBridge-$VORD_ARCH"
done
xcrun lipo -create "$VORD_OUT/VordSelectionBridge-arm64" "$VORD_OUT/VordSelectionBridge-x86_64" \
  -output "$VORD_ROOT/Vord/Resources/VordSelectionBridge"
codesign --force --sign - "$VORD_ROOT/Vord/Resources/VordSelectionBridge"
mkdir -p "$VORD_ROOT/Vord/Resources/BrowserExtension"
cp "$VORD_ROOT/Integrations/BrowserExtension/"* "$VORD_ROOT/Vord/Resources/BrowserExtension/"
