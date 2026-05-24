---
name: orbita-release
description: Use when preparing, troubleshooting, or publishing Orbita macOS releases, including GitHub Releases, signed DMG packaging, Apple Developer ID signing, notarization, Sparkle appcast generation, release secrets, tag handling, and release verification. This skill emphasizes preflight checks and strict secret redaction.
---

# Orbita Release

## Quick Start

Use this skill for Orbita official releases and release failures. Before making any release action, inspect the repo-local workflow and scripts because they are the source of truth:

```bash
git status --short --branch
sed -n '1,260p' .github/workflows/release.yml
sed -n '1,260p' script/release_github.sh
sed -n '1,220p' docs/release.md
```

Do not print secrets, certificates, private keys, app-specific passwords, OAuth tokens, or full credential files in chat or logs.

## Privacy Rules

- Never ask the user to paste secrets into chat. Use hidden local input, Keychain, GitHub Secrets UI, `gh secret set`, or encrypted GitHub API calls.
- If the user sends a secret in chat, do not repeat it. Tell them it should be rotated if it was sensitive.
- Do not include actual Apple IDs, Team IDs, certificate hashes, private keys, token values, app-specific passwords, or base64 certificate blobs in the skill, docs, commits, PR text, final answers, or logs.
- Keep temporary secret files outside the repo, under a chmod `700` directory such as `~/Library/Application Support/OrbitaReleaseSecrets`, and remove it before final response.
- Prefer `security`, `xcrun notarytool`, `gh secret set`, or encrypted GitHub API calls over shell commands that echo secret values.
- When showing command output, summarize secret-related results as present/missing/validated/written, never as raw values.

## Preflight Checklist

1. Confirm the working tree and target branch:

```bash
git status --short --branch
git log --oneline -3
```

2. Confirm the app version and bundle identity:

```bash
plutil -p Support/OrbitaApp/Info.plist | rg 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|SUFeedURL|SUPublicEDKey'
```

3. Confirm release scripts and workflow include signed Release build, DMG signing, notarization, Sparkle appcast, and GitHub release publishing.

4. Confirm a Developer ID Application identity exists locally when doing local signing diagnostics:

```bash
security find-identity -v -p codesigning | rg 'Developer ID Application|valid identities'
```

5. Confirm notarization credentials without revealing the password:

```bash
xcrun notarytool history --keychain-profile orbita-release
```

If no profile exists, use `xcrun notarytool store-credentials ... --validate`. Collect app-specific passwords through a hidden prompt or direct terminal input, not chat.

6. Confirm GitHub release secrets exist. Required repository secrets are:

```text
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
DEVELOPER_ID_APPLICATION
APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
SPARKLE_PRIVATE_ED_KEY
SPARKLE_PUBLIC_ED_KEY
```

Report only missing names.

## Secret Setup Pattern

Use local temporary files only when unavoidable. Keep them outside the repo:

```bash
SECRET_DIR="$HOME/Library/Application Support/OrbitaReleaseSecrets"
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
```

Recommended inputs:

- Apple app-specific password: hidden `osascript` prompt or `read -s`.
- Developer ID `.p12`: export from Keychain with a random local password, then base64 encode for GitHub Secrets.
- Sparkle private key: export with Sparkle tooling, write only to a temporary file, then GitHub Secret.
- GitHub token: use `gh`, `git credential fill`, or existing credential helpers; never display it.

After writing secrets and verifying the release, delete temporary files:

```bash
rm -rf "$SECRET_DIR"
```

## Release Flow

Use the repo script for normal releases:

```bash
script/release_github.sh vX.Y.Z
```

Expected behavior:

- Runs tests.
- Builds Release app.
- Creates a local DMG for validation.
- Creates and pushes `vX.Y.Z`.
- GitHub Actions signs, notarizes, staples, generates `appcast.xml`, and publishes assets.

Only force-move a tag when all are true:

- The previous run failed before publishing usable release assets.
- The user wants to keep the same version.
- The fix has been committed and pushed.

Never force-move a tag that already has a successful public release unless the user explicitly accepts the release management consequences.

## Verification

Local validation commands:

```bash
swift test
./script/xcode_build.sh build
git diff --check
```

For signed local DMG validation:

```bash
script/sign_release_app.sh "$APP" "$DEVELOPER_ID_APPLICATION"
script/package_dmg.sh "$APP" "$VERSION" "$DMG"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile orbita-release --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
```

Success should include `Accepted`, staple success, and `source=Notarized Developer ID`.

GitHub release verification:

- Confirm the latest release workflow run is `completed success`.
- Confirm the release exists for the tag.
- Confirm both assets exist: `Orbita-vX.Y.Z.dmg` and `appcast.xml`.
- Confirm `appcast.xml` contains a Sparkle signature, but do not print private keys.

## Failure Triage

If GitHub Actions fails at secret validation:

- Report the missing secret names only.
- Help write or update secrets through secure local mechanisms.

If notarization returns `Invalid`:

1. Fetch the notary log.
2. Summarize issue paths and messages.
3. Do not print secrets from environment dumps.

Common fixes:

- `get-task-allow`: Release build is carrying debug entitlements; clear release entitlements or re-sign without them.
- Sparkle nested helpers not Developer ID signed or no timestamp: re-sign `Downloader.xpc`, `Installer.xpc`, `Updater.app`, `Autoupdate`, and `Sparkle.framework` before signing the app.
- `spctl` rejects DMG after notarization: sign the DMG itself before submitting to notarization.

## Final Response Rules

Include:

- Version/tag.
- Commit pushed, if any.
- Workflow run URL.
- Release URL and asset names.
- Validation summary.
- Whether temporary local secret files were cleaned.

Exclude:

- Apple ID or user email.
- Team ID.
- Certificate fingerprint.
- Any token, password, private key, or base64 certificate.
