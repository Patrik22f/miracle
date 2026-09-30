#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path macos --build-system native -c debug
BIN_DIR="$(swift build --package-path macos --build-system native -c debug --show-bin-path)"
APP="build/Preflight.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Preflight" "$APP/Contents/MacOS/Preflight"
cp macos/Resources/Info.plist "$APP/Contents/Info.plist"
for resource in "$BIN_DIR"/*.bundle; do
    [ -d "$resource" ] && cp -R "$resource" "$APP/Contents/Resources/"
done
# Finder/iCloud metadata on generated bundles can otherwise block ad-hoc signing.
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP — open with: open build/Preflight.app"
