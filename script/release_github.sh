#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 v0.1.0" >&2
  exit 2
fi

# Plain vX.Y.Z only: the version gate below compares this against MARKETING_VERSION, which carries no
# pre-release suffix, so accepting a suffixed tag here would only get rejected there. Reject it up front.
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release version must look like v0.1.0 (no pre-release suffix)" >&2
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

# Fail fast on a tag <-> project version mismatch. Without this guard a wrong
# tag silently ships a DMG named for $VERSION while the app bundle + Sparkle
# appcast report the stale MARKETING_VERSION baked into project.pbxproj.
PBXPROJ="Orbita.xcodeproj/project.pbxproj"
VERSION_NUMBER="${VERSION#v}"
# Anchored to line start so a hypothetical custom *_MARKETING_VERSION key can't be picked up.
marketing_versions="$(grep -E '^[[:space:]]*MARKETING_VERSION = ' "$PBXPROJ" \
  | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d '[:blank:]' | sort -u)"
if [[ "$marketing_versions" != "$VERSION_NUMBER" ]]; then
  echo "version mismatch: tag $VERSION implies MARKETING_VERSION=$VERSION_NUMBER," >&2
  echo "but project.pbxproj has: $(echo "$marketing_versions" | tr '\n' ' ')" >&2
  echo "run 'script/bump_version.sh $VERSION' and commit before releasing." >&2
  exit 1
fi
build_numbers="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBXPROJ" \
  | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);.*/\1/' | tr -d '[:blank:]' | sort -u)"
if [[ -z "$build_numbers" ]]; then
  echo "no CURRENT_PROJECT_VERSION found in $PBXPROJ" >&2
  exit 1
fi
if [[ "$(printf '%s\n' "$build_numbers" | grep -c .)" -ne 1 ]]; then
  echo "CURRENT_PROJECT_VERSION entries disagree in $PBXPROJ: $(echo "$build_numbers" | tr '\n' ' ')" >&2
  echo "run 'script/bump_version.sh $VERSION' to make them consistent." >&2
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
    CODE_SIGN_ENTITLEMENTS=""
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
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
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  script/sign_release_app.sh "$APP" "$DEVELOPER_ID_APPLICATION"
fi
script/package_dmg.sh "$APP" "$VERSION" "$DMG"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
fi

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  : "${APPLE_ID:?APPLE_ID is required when NOTARIZE=1}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when NOTARIZE=1}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required when NOTARIZE=1}"

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
    --download-url-prefix "https://github.com/LLLLLayer/orbita/releases/download/${VERSION}/" \
    "$UPDATES_DIR"
  cp "$UPDATES_DIR/appcast.xml" "dist/appcast.xml"
fi

git tag -a "$VERSION" -m "Orbita $VERSION"
git push origin "$VERSION"

echo "Created $DMG locally and pushed $VERSION. GitHub Actions will publish the signed DMG release."
