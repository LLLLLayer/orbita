# Orbita release workflow

Orbita distributes macOS releases as a signed and notarized DMG. Unsigned local
DMGs are still useful for internal smoke tests, but public release automation must
go through Apple Developer ID signing and notarization before publishing.

## Public release requirements

- Apple Developer Program membership.
- A `Developer ID Application` certificate exported as a password-protected
  `.p12` file.
- Hardened Runtime enabled for the app target.
- GitHub repository secrets:
  - `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`
  - `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
  - `DEVELOPER_ID_APPLICATION`
  - `APPLE_ID`
  - `APPLE_TEAM_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`
  - `SPARKLE_PRIVATE_ED_KEY`
  - `SPARKLE_PUBLIC_ED_KEY`

The GitHub workflow validates these secrets before it builds. A missing secret is
a failed release, not a fallback to an unsigned public artifact.

## CI release flow

1. Trigger the workflow by pushing a `vX.Y.Z` tag or running the Release workflow
   manually.
2. Import the Developer ID certificate into a temporary keychain.
3. Build the Release app with `CODE_SIGNING_ALLOWED=YES`,
   `CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM`, and
   `CODE_SIGN_IDENTITY`.
4. Verify the signed app with `codesign --deep --strict --verify`.
5. Package `Orbita.app` into `Orbita-vX.Y.Z.dmg` with an `/Applications`
   shortcut.
6. Submit the DMG with `xcrun notarytool submit --wait`.
7. Staple the notarization ticket with `xcrun stapler staple`.
8. Validate the final DMG with `spctl`.
9. Generate `appcast.xml` with Sparkle `generate_appcast`, using the private
   EdDSA key from standard input.
10. Publish the notarized DMG and `appcast.xml` to the GitHub Release.

## Local release flow

`script/release_github.sh vX.Y.Z` runs tests, builds the app, creates a local DMG,
tags the commit, and pushes the tag.

By default this produces a local validation DMG. To mirror public signing locally:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)" \
APPLE_TEAM_ID="TEAMID" \
SPARKLE_PRIVATE_ED_KEY="base64-private-ed-key" \
SPARKLE_PUBLIC_ED_KEY="base64-public-ed-key" \
SPARKLE_GENERATE_APPCAST="/path/to/Sparkle/bin/generate_appcast" \
NOTARIZE=1 \
APPLE_ID="developer@example.com" \
APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
script/release_github.sh v0.1.0
```

## Automatic updates

Orbita integrates Sparkle for automatic update checks. The updater starts only
when the app bundle has both a valid HTTPS `SUFeedURL` and a real
`SUPublicEDKey`; the repository placeholder keeps local builds from showing a
misconfiguration alert before release keys exist.

Sparkle's release model has three distinct pieces:

- App integration: link and embed Sparkle, create an updater controller, and add
  the `Check for Updates...` app menu action.
- Feed configuration: add `SUFeedURL` to the app bundle, pointing at an HTTPS
  appcast.
- Update signing: generate a Sparkle EdDSA key pair, add `SUPublicEDKey` to the
  app bundle, and sign every release archive/appcast with Sparkle tooling.

The DMG produced by this release workflow can be reused as the Sparkle update
archive. The CI workflow publishes `appcast.xml` next to the DMG so the
production `SUFeedURL` can use GitHub Releases as the feed host.

## References

- Apple Developer ID: https://developer.apple.com/developer-id/
- Apple notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Sparkle documentation: https://sparkle-project.org/documentation/
