# Releasing

The initial distribution targets Apple Silicon and macOS 14+. Run the tests and
review the release's hardware and performance notes before packaging.

## Build

Use committed source. Signing keys stay in the local Keychain.
Set `CODE_SIGN_IDENTITY` to your Developer ID identity and `CODE_SIGN_KEYCHAIN`
to your signing Keychain path, then run `bash scripts/build-app.sh`.

Inspect the executable with `file` and `vtool -show-build`. Verify the architecture,
macOS deployment target and `codesign --verify --strict` result.

## Notarize and package

Store a notarization profile in Keychain with `notarytool store-credentials`.
Never put credentials or account details in this repository.

Set `NOTARY_PROFILE` to that profile, keep the signing variables set, then run:

```sh
bash scripts/package-release.sh 0.1.0-beta.2
```

The script submits the app, staples its ticket, creates a signed DMG, notarizes
and staples the DMG, verifies Gatekeeper acceptance and writes a SHA-256 checksum.
All submissions must be Accepted before publishing.

## Sparkle feed

Create an app-specific EdDSA key once with Sparkle's `generate_keys --account
com.gitlares.desktop-leds` and store its public key as `SUPublicEDKey` in the app.
Keep the private key in Keychain and back it up securely outside this repository.

After stapling, put the updater ZIP alone in a staging directory and run Sparkle's
`generate_appcast --account com.gitlares.desktop-leds --download-url-prefix
https://github.com/gitlares/fs-desktop-leds/releases/download/vVERSION/
--maximum-deltas 0 -o docs/appcast.xml STAGING_DIRECTORY`.
The embedded `SURequireSignedFeed` setting also signs the feed. Never edit a
signed feed manually. Publish the ZIP and the signed feed together.

## Publish

1. Tag the built source commit as `vVERSION`.
2. Create a GitHub prerelease with the DMG, updater ZIP, checksum and release notes.
3. Enable GitHub Pages from `main` and `/docs`.
4. Verify the public site, download, checksum and donation link.
5. Download the published artifact and compare its checksum with the local package.

Use versioned URLs for betas; GitHub's `latest` route may exclude prereleases.
Never replace an asset with a different build under the same version.
