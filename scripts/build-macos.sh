#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${PREFLIGHT_APP_PATH:-$HOME/Applications/Preflight.app}"
case "$APP" in
    /*.app) ;;
    *) echo 'PREFLIGHT_APP_PATH must be an absolute .app path outside iCloud.' >&2; exit 1 ;;
esac
if [ -e "$APP" ]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
    if [ "$EXISTING_ID" != dev.preflight.hackathon ]; then
        echo "Refusing to replace another application at $APP." >&2
        exit 1
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
    if /usr/bin/awk -v executable="$APP/Contents/MacOS/Preflight" \
        -v legacy="$PWD/build/Preflight.app/Contents/MacOS/Preflight" \
        '$0 == executable || $0 == legacy { found = 1 } END { exit !found }' <<< "$processes"; then
        echo "Quit Preflight before rebuilding. The running app has been left untouched." >&2
        exit 1
    fi
}
ensure_app_stopped
mkdir -p "$(dirname "$APP")"

# Reuse the same certificate on later builds. Ad-hoc signing binds permission
# to one binary hash and therefore must be an explicit, disposable-build choice.
SIGNER_FILE="build/.signing-identity"
SIGNER="${PREFLIGHT_CODESIGN_IDENTITY:-}"
if [ -z "$SIGNER" ] && [ -f "$SIGNER_FILE" ]; then
    SIGNER="$(cat "$SIGNER_FILE")"
fi
if [ -z "$SIGNER" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2}')"
    COUNT="$(awk 'NF {count++} END {print count+0}' <<< "$IDENTITIES")"
    if [ "$COUNT" = 1 ]; then
        SIGNER="$IDENTITIES"
    else
        echo 'Set PREFLIGHT_CODESIGN_IDENTITY to a code-signing certificate name or SHA-1.' >&2
        echo 'For a disposable build only, set it to "-"; rebuilding then requires Accessibility approval again.' >&2
        exit 1
    fi
fi
if [ "$SIGNER" = - ]; then
    echo 'Warning: ad-hoc signing. Accessibility permission will not survive code changes.' >&2
fi

swift build --package-path macos --build-system native -c debug
BIN_DIR="$(swift build --package-path macos --build-system native -c debug --show-bin-path)"
ensure_app_stopped
# Sign outside iCloud-backed Documents. File Provider can immediately reattach
# FinderInfo to a bundle there, even after xattr -c, causing codesign to fail.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/preflight-build.XXXXXX")"
STAGED_APP="$STAGING/Preflight.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp -X "$BIN_DIR/Preflight" "$STAGED_APP/Contents/MacOS/Preflight"
cp -X macos/Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
for resource in "$BIN_DIR"/*.bundle; do
    if [ -d "$resource" ]; then
        ditto --noextattr --norsrc "$resource" "$STAGED_APP/Contents/Resources/$(basename "$resource")"
    fi
done
codesign --force --sign "$SIGNER" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
ensure_app_stopped
[ ! -d "$APP" ] || mv "$APP" "$STAGING/Previous.app"
if ! mv "$STAGED_APP" "$APP" || ! codesign --verify --strict "$APP"; then
    # Preserve the prior working bundle if installation fails.
    [ ! -d "$APP" ] || mv "$APP" "$STAGING/Failed.app"
    [ ! -d "$STAGING/Previous.app" ] || mv "$STAGING/Previous.app" "$APP"
    exit 1
fi
if [ "$SIGNER" != - ]; then
    printf '%s\n' "$SIGNER" > "$SIGNER_FILE"
fi
# Keep the documented development shortcut, but the executable itself must
# live outside File Provider storage. This path contains generated output only.
if [ "$APP" != "$PWD/build/Preflight.app" ]; then
    if [ -e build/Preflight.app ] || [ -L build/Preflight.app ]; then
        mv build/Preflight.app "$STAGING/Legacy.app"
    fi
    ln -s "$APP" build/Preflight.app
fi
echo "Built $APP"
echo 'Launch Preflight from your Applications folder.'
