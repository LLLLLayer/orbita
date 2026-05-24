#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Orbita.xcodeproj"
APP_SCHEME="Orbita"
DESTINATION="platform=macOS"

cd "$ROOT_DIR"

case "$MODE" in
  open)
    /usr/bin/open "$PROJECT"
    ;;
  list)
    xcodebuild -project "$PROJECT" -list
    ;;
  build)
    xcodebuild -project "$PROJECT" -scheme "$APP_SCHEME" -destination "$DESTINATION" build
    ;;
  test)
    swift test
    ;;
  clean)
    xcodebuild -project "$PROJECT" -scheme "$APP_SCHEME" -destination "$DESTINATION" clean
    ;;
  *)
    echo "usage: $0 [open|list|build|test|clean]" >&2
    exit 2
    ;;
esac
