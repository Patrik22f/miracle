#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEFAULT_APP="$HOME/Applications/Miracle.app"
LEGACY_APP="$HOME/Applications/Preflight.app"
APP="${MIRACLE_APP_PATH:-${PREFLIGHT_APP_PATH:-$DEFAULT_APP}}"
PREVIOUS_APP="$APP"
case "$APP" in
    /*.app) ;;
    *) echo 'MIRACLE_APP_PATH must be an absolute .app path outside iCloud.' >&2; exit 1 ;;
esac
if [ -e "$APP" ]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
    if [ "$EXISTING_ID" != dev.preflight.hackathon ]; then
        echo "Refusing to replace another application at $APP." >&2
        exit 1
    fi
fi
if [ "$APP" = "$DEFAULT_APP" ] && [ ! -e "$APP" ] && [ -d "$LEGACY_APP" ]; then
    LEGACY_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP/Contents/Info.plist")"
    if [ "$LEGACY_ID" = dev.preflight.hackathon ]; then
        PREVIOUS_APP="$LEGACY_APP"
    fi
fi
mkdir -p build
LOCK="build/.app-build-lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another app build is in progress ($LOCK)." >&2
    exit 1
fi
STAGING=""
cleanup() {
    [ -z "$STAGING" ] || rm -rf "$STAGING"
    rmdir "$LOCK"
}
trap cleanup EXIT

# Never mutate an executable that another development session is testing.
# Replacing a running ad-hoc build was invalidating its Accessibility grant.
ensure_app_stopped() {
    local processes
    processes="$(/bin/ps -axo comm=)"
    if /usr/bin/awk \
        '/\.app\/Contents\/MacOS\/(Preflight|Miracle)$/ { found = 1 } END { exit !found }' <<< "$processes"; then
        echo "Quit Miracle (or the previous Preflight build) before rebuilding. The running app has been left untouched." >&2
        exit 1
    fi
}
ensure_app_stopped
mkdir -p "$(dirname "$APP")"

# Reuse the same certificate on later builds. Ad-hoc signing binds permission
# to one binary hash and therefore must be an explicit, disposable-build choice.
SIGNER_FILE="build/.signing-identity"
SIGNER="${MIRACLE_CODESIGN_IDENTITY:-${PREFLIGHT_CODESIGN_IDENTITY:-}}"
if [ -z "$SIGNER" ] && [ -f "$SIGNER_FILE" ]; then
    SIGNER="$(cat "$SIGNER_FILE")"
fi
if [ -z "$SIGNER" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2}')"
    COUNT="$(awk 'NF {count++} END {print count+0}' <<< "$IDENTITIES")"
    if [ "$COUNT" = 1 ]; then
        SIGNER="$IDENTITIES"
    else
        echo 'Set MIRACLE_CODESIGN_IDENTITY to a code-signing certificate name or SHA-1.' >&2
        echo 'For a disposable build only, set it to "-"; rebuilding then requires Accessibility approval again.' >&2
        exit 1
    fi
fi
if [ "$SIGNER" = - ]; then
    echo 'Warning: ad-hoc signing. Accessibility permission will not survive code changes.' >&2
fi

swift build --package-path macos --build-system native -c debug
BIN_DIR="$(swift build --package-path macos --build-system native -c debug --show-bin-path)"
swiftc -swift-version 6 macos/Sources/Preflight/MiracleArtwork.swift macos/Branding/main.swift -o build/render-miracle-icon
build/render-miracle-icon build/Miracle.iconset
iconutil -c icns build/Miracle.iconset -o build/Miracle.icns
ensure_app_stopped
# Sign outside iCloud-backed Documents. File Provider can immediately reattach
# FinderInfo to a bundle there, even after xattr -c, causing codesign to fail.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/preflight-build.XXXXXX")"
STAGED_APP="$STAGING/Miracle.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp -X "$BIN_DIR/Miracle" "$STAGED_APP/Contents/MacOS/Miracle"
cp -X macos/Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp -X build/Miracle.icns "$STAGED_APP/Contents/Resources/Miracle.icns"
for resource in "$BIN_DIR"/*.bundle; do
    if [ -d "$resource" ]; then
        ditto --noextattr --norsrc "$resource" "$STAGED_APP/Contents/Resources/$(basename "$resource")"
    fi
done
codesign --force --sign "$SIGNER" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
ensure_app_stopped
[ ! -d "$PREVIOUS_APP" ] || mv "$PREVIOUS_APP" "$STAGING/Previous.app"
if ! mv "$STAGED_APP" "$APP" || ! codesign --verify --strict "$APP"; then
    # Preserve the prior working bundle if installation fails.
    [ ! -d "$APP" ] || mv "$APP" "$STAGING/Failed.app"
    [ ! -d "$STAGING/Previous.app" ] || mv "$STAGING/Previous.app" "$PREVIOUS_APP"
    exit 1
fi
if [ "$SIGNER" != - ]; then
    printf '%s\n' "$SIGNER" > "$SIGNER_FILE"
fi
# Retain the old development shortcut while the installed app adopts its new name.
for NAME in Miracle Preflight; do
    SHORTCUT="$PWD/build/$NAME.app"
    if [ "$APP" != "$SHORTCUT" ]; then
        if [ -e "$SHORTCUT" ] || [ -L "$SHORTCUT" ]; then
            mv "$SHORTCUT" "$STAGING/Shortcut-$NAME.app"
        fi
        ln -s "$APP" "$SHORTCUT"
    fi
done
echo "Built $APP"
echo 'Launch Miracle from your Applications folder.'
