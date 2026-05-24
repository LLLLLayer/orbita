#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
VERSION="${2:-}"
OUTPUT_PATH="${3:-}"

if [[ -z "$APP_PATH" || -z "$VERSION" || -z "$OUTPUT_PATH" ]]; then
  echo "usage: $0 /path/to/Orbita.app v0.1.0 /path/to/Orbita-v0.1.0.dmg" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orbita-dmg.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUTPUT_PATH")"
cp -R "$APP_PATH" "$STAGING_DIR/Orbita.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Orbita ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
