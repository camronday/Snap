#!/usr/bin/env bash
# Removes Snap and its local state. No sudo required.
set -euo pipefail

APP_NAME="Snap"
BUNDLE_ID="com.cameronro.Snap"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo "==> Quitting ${APP_NAME}"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1

echo "==> Removing ${INSTALL_PATH}"
rm -rf "${INSTALL_PATH}"

echo "==> Removing preferences"
defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true

echo "==> Resetting Screen Recording permission"
tccutil reset ScreenCapture "${BUNDLE_ID}" >/dev/null 2>&1 || true

cat <<'EOF'
==> Note: if you had "Launch at Login" enabled, remove the leftover entry
    from System Settings > General > Login Items, since it can't be
    unregistered once the app is gone.

Snap has been uninstalled.
EOF
