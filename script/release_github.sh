#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 v0.1.0" >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\\.[0-9]+\\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; then
  echo "release version must look like v0.1.0" >&2
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
xcodebuild \
  -project Orbita.xcodeproj \
  -scheme Orbita \
  -configuration Release \
  -derivedDataPath .build/release-local \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

git tag -a "$VERSION" -m "Orbita $VERSION"
git push origin "$VERSION"

echo "Pushed $VERSION. GitHub Actions will build and publish the release."
