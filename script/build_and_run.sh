#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Orbita"
BUNDLE_ID="dev.orbita.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Orbita.xcodeproj"
DERIVED_DATA_PATH="${ORBITA_DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
xcodebuild -project "$PROJECT" -scheme "$APP_NAME" -configuration Debug -derivedDataPath "$DERIVED_DATA_PATH" -destination "platform=macOS" build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\" AND (subsystem == \"$BUNDLE_ID\" OR eventMessage CONTAINS \"scan.\" OR eventMessage CONTAINS \"project.\" OR eventMessage CONTAINS \"plan.\" OR eventMessage CONTAINS \"apply.\")"
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
