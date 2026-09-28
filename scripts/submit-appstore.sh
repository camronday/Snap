#!/usr/bin/env bash
# Build, archive, and upload Snap to App Store Connect.
#
# Prerequisites:
#   1. Xcode installed
#   2. brew install xcodegen
#   3. Apple Distribution certificate in your keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Apple Distribution)
#   4. App record created in App Store Connect (bundle ID: com.cameronro.Snap)
#   5. Config/Local.xcconfig present with your DEVELOPMENT_TEAM
#
# Upload credentials (one of):
#   a) Transporter app (from Mac App Store) - drag the .pkg from build/AppStoreExport/
#   b) App Store Connect API key - set APPSTORE_KEY_ID, APPSTORE_ISSUER_ID,
#      and APPSTORE_KEY_PATH (path to the .p8 file) in your environment or below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARCHIVE_PATH="$REPO_DIR/build/Snap.xcarchive"
EXPORT_PATH="$REPO_DIR/build/AppStoreExport"

cd "$REPO_DIR"

# ── Checks ───────────────────────────────────────────────────────────────────

if [[ "$(sw_vers -productVersion)" < "26" ]]; then
    echo "error: macOS 26 or later required." >&2; exit 1
fi

if ! command -v xcodebuild &>/dev/null || [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    echo "error: Full Xcode required (not just Command Line Tools)." >&2
    echo "       Download from the Mac App Store or developer.apple.com/download" >&2
    exit 1
fi

if ! command -v xcodegen &>/dev/null; then
    echo "error: xcodegen not found - install with: brew install xcodegen" >&2; exit 1
fi

if [[ ! -f "Config/Local.xcconfig" ]]; then
    echo "error: Config/Local.xcconfig missing." >&2
    echo "       Copy Config/Local.xcconfig.example, fill in your DEVELOPMENT_TEAM." >&2
    exit 1
fi

TEAM=$(grep "DEVELOPMENT_TEAM" Config/Local.xcconfig | awk -F= '{gsub(/ /,"",$2); print $2}' | head -1)
if [[ -z "$TEAM" ]]; then
    echo "error: DEVELOPMENT_TEAM not set in Config/Local.xcconfig." >&2; exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "error: No 'Apple Distribution' certificate found in keychain." >&2
    echo "       Xcode > Settings > Accounts > Manage Certificates > + > Apple Distribution" >&2
    exit 1
fi

# ── Generate project ─────────────────────────────────────────────────────────

echo "==> Generating Xcode project..."
xcodegen generate --quiet

# ── Archive ──────────────────────────────────────────────────────────────────

echo "==> Archiving (this takes a minute)..."
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -scheme Snap \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    -quiet

# ── Export ───────────────────────────────────────────────────────────────────

echo "==> Exporting for App Store..."
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist ExportOptions-AppStore.plist \
    -allowProvisioningUpdates \
    -quiet

PKG=$(find "$EXPORT_PATH" -name "*.pkg" | head -1)
if [[ -z "$PKG" ]]; then
    echo "error: No .pkg found in $EXPORT_PATH" >&2; exit 1
fi
echo "==> Package: $PKG"

# ── Upload ───────────────────────────────────────────────────────────────────

if [[ -n "${APPSTORE_KEY_ID:-}" && -n "${APPSTORE_ISSUER_ID:-}" && -n "${APPSTORE_KEY_PATH:-}" ]]; then
    echo "==> Uploading to App Store Connect..."
    xcrun altool --upload-package "$PKG" \
        --type macos \
        --apiKey "$APPSTORE_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" \
        --apiKeyPath "$APPSTORE_KEY_PATH"
    echo "==> Done. Visit App Store Connect to complete submission."
else
    echo ""
    echo "==> Package ready. To upload:"
    echo "    • Open Transporter (free, from Mac App Store) and drag in:"
    echo "      $PKG"
    echo "    • Or set APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_KEY_PATH"
    echo "      and re-run this script to upload automatically."
    open "$EXPORT_PATH"
fi
