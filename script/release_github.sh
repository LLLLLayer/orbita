#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 v0.1.0" >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; then
  echo "release version must look like v0.1.0" >&2
  exit 2
fi

if [[ "${NOTARIZE:-0}" == "1" && -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "DEVELOPER_ID_APPLICATION is required when NOTARIZE=1" >&2
  exit 2
fi

if [[ "${NOTARIZE:-0}" == "1" && -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY is required when NOTARIZE=1" >&2
  exit 2
fi

if [[ "${NOTARIZE:-0}" == "1" && -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_ED_KEY is required when NOTARIZE=1" >&2
  exit 2
fi

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty; commit or stash changes before releasing" >&2
  exit 1
fi

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "tag already exists: $VERSION" >&2
  exit 1
fi

swift test

build_settings=(
  -project Orbita.xcodeproj
  -scheme Orbita
  -configuration Release
  -derivedDataPath .build/release-local
  -destination "platform=macOS"
)

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  build_settings+=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    build_settings+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
  fi
else
  build_settings+=(CODE_SIGNING_ALLOWED=NO)
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  build_settings+=(SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY")
fi

xcodebuild \
  "${build_settings[@]}" \
  build

APP=".build/release-local/Build/Products/Release/Orbita.app"
DMG="dist/Orbita-${VERSION}.dmg"
script/package_dmg.sh "$APP" "$VERSION" "$DMG"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  : "${APPLE_ID:?APPLE_ID is required when NOTARIZE=1}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when NOTARIZE=1}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required when NOTARIZE=1}"

  codesign --deep --strict --verify --verbose=2 "$APP"
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-.build/release-local/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast}"
  if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "Sparkle generate_appcast not found or not executable: $GENERATE_APPCAST" >&2
    exit 1
  fi
  UPDATES_DIR="dist/sparkle-updates"
  mkdir -p "$UPDATES_DIR"
  cp "$DMG" "$UPDATES_DIR/"
  printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/LLLLLayer/orbita/releases/download/${VERSION}" \
    "$UPDATES_DIR"
  cp "$UPDATES_DIR/appcast.xml" "dist/appcast.xml"
fi

git tag -a "$VERSION" -m "Orbita $VERSION"
git push origin "$VERSION"

echo "Created $DMG locally and pushed $VERSION. GitHub Actions will publish the signed DMG release."
