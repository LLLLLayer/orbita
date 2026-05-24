#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
SIGNING_IDENTITY="${2:-${DEVELOPER_ID_APPLICATION:-}}"

if [[ -z "$APP_PATH" || -z "$SIGNING_IDENTITY" ]]; then
  echo "usage: $0 /path/to/Orbita.app 'Developer ID Application: Name (TEAMID)'" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 1
fi

sign_item() {
  local item="$1"
  if [[ ! -e "$item" ]]; then
    return 0
  fi

  codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "$item"
}

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
  sign_item "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
  sign_item "$SPARKLE_VERSION/XPCServices/Installer.xpc"
  sign_item "$SPARKLE_VERSION/Updater.app"
  sign_item "$SPARKLE_VERSION/Autoupdate"
  sign_item "$SPARKLE_VERSION"
fi

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --timestamp \
  --options runtime \
  "$APP_PATH"

codesign --deep --strict --verify --verbose=2 "$APP_PATH"

if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.get-task-allow"; then
  echo "release app must not request com.apple.security.get-task-allow" >&2
  exit 1
fi
