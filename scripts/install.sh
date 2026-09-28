#!/usr/bin/env bash
# Builds Snap from source and installs it to /Applications.
#
# No sudo, no downloaded binaries, no quarantine-flag manipulation: this
# only compiles the checked-out source with your local Xcode and copies
# the result into /Applications.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP_NAME="Snap"
BUILD_DIR="build-release"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo "==> Checking macOS version"
os_version="$(sw_vers -productVersion)"
os_major="${os_version%%.*}"
if [[ "${os_major}" -lt 26 ]]; then
    echo "error: Snap requires macOS 26 or later (found ${os_version})." >&2
    exit 1
fi

echo "==> Checking for Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: a full Xcode installation is required (the Command Line Tools alone
aren't enough).

Install Xcode from the App Store, then run:
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
and re-run this script.
EOF
    exit 1
fi

echo "==> Checking for XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: XcodeGen is required. Install it with:" >&2
    echo "  brew install xcodegen" >&2
    exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building Release"
rm -rf "${BUILD_DIR}"
xcodebuild -quiet -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}" build

built_app="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${built_app}" ]]; then
    echo "error: build succeeded but ${built_app} is missing." >&2
    exit 1
fi

echo "==> Quitting any running ${APP_NAME}"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1

echo "==> Installing to ${INSTALL_PATH}"
rm -rf "${INSTALL_PATH}"
cp -R "${built_app}" "${INSTALL_PATH}"

echo "==> Launching ${APP_NAME}"
open "${INSTALL_PATH}"

echo "Done. On first launch, grant Screen Recording access when prompted, then relaunch Snap."
