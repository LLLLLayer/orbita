#!/usr/bin/env bash
set -euo pipefail

# Rewrites the single source of the app version (both MARKETING_VERSION build
# configs in Orbita.xcodeproj) and increments the build number
# (CURRENT_PROJECT_VERSION), so `script/release_github.sh vX.Y.Z` and the tag
# can never silently disagree. Run this, review the diff, commit, then release.

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT_DIR/Orbita.xcodeproj/project.pbxproj"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 vX.Y.Z" >&2
  exit 2
fi

# Plain vX.Y.Z only — matches the release gate, and keeps CFBundleShortVersionString valid.
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must look like v1.3.0 (no pre-release suffix)" >&2
  exit 2
fi

if [[ ! -f "$PBXPROJ" ]]; then
  echo "project file not found: $PBXPROJ" >&2
  exit 1
fi

VERSION_NUMBER="${VERSION#v}"

# Highest existing build number, +1. Monotonic CFBundleVersion is what Sparkle
# compares to decide an update is newer.
current="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBXPROJ" \
  | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/' | sort -rn | head -1)"
if [[ -z "$current" ]]; then
  echo "no CURRENT_PROJECT_VERSION found in $PBXPROJ" >&2
  exit 1
fi
next=$((current + 1))

# macOS sed in-place edit (this project is macOS-only). Anchored to line start so a hypothetical custom
# *_MARKETING_VERSION / *_CURRENT_PROJECT_VERSION key is never rewritten.
/usr/bin/sed -i '' -E "s/(^[[:space:]]*MARKETING_VERSION = )[^;]+;/\1${VERSION_NUMBER};/g" "$PBXPROJ"
/usr/bin/sed -i '' -E "s/(^[[:space:]]*CURRENT_PROJECT_VERSION = )[0-9]+;/\1${next};/g" "$PBXPROJ"

# Verify the rewrite landed consistently.
marketing="$(grep -E '^[[:space:]]*MARKETING_VERSION = ' "$PBXPROJ" \
  | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d '[:blank:]' | sort -u)"
if [[ "$marketing" != "$VERSION_NUMBER" ]]; then
  echo "post-bump verification failed: MARKETING_VERSION is now: $(echo "$marketing" | tr '\n' ' ')" >&2
  exit 1
fi

echo "Set MARKETING_VERSION=${VERSION_NUMBER}, CURRENT_PROJECT_VERSION=${next} in project.pbxproj"
echo "Review the diff, commit, then run: script/release_github.sh ${VERSION}"
