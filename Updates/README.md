# Sparkle release configuration

The app target links Sparkle 2.9.6 from the exact Swift Package Manager
revision recorded in `LexCleaner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

The repository intentionally does not contain a feed hostname, Ed25519 private
key, signed archive, Developer ID identity, or notarization ticket. Distribution
builds must inject these values without committing secrets:

```sh
xcodebuild \
  SPARKLE_FEED_URL=https://updates.example.invalid/lexcleaner/appcast.xml \
  SPARKLE_PUBLIC_ED_KEY='<base64 Ed25519 public key>' \
  ...
```

The example hostname above is documentation-only and must not be used for a
release. The app refuses to start Sparkle unless the feed is HTTPS and the key
decodes to a 32-byte Ed25519 public key. Debug builds therefore show an explicit
unavailable state until real distribution values are supplied.

## Publishing checklist

1. Build and archive a signed, notarized, stapled arm64/universal app with an
   incremented `CFBundleVersion`.
2. Put the signed archive in a release directory and run Sparkle's
   `generate_appcast` and `sign_update` tools from the pinned 2.9.6 distribution.
3. Publish the generated appcast and archive over HTTPS, retaining the
   `edSignature` and `length` attributes in the appcast enclosure.
4. Verify the appcast with a clean build configured with the matching public key
   before publishing. Do not place the private signing key in this repository or
   on the feed host.

Before publishing, run the repository checker against the exact archive or app
bundle:

```sh
python3 scripts/verify_macos_distribution.py --app /absolute/path/LexCleaner.app
```

The checker requires a complete Xcode toolchain, a `Developer ID Application`
identity, a strict `codesign` verification, Gatekeeper assessment, and a valid
stapled notarization ticket. It also checks the bundle's HTTPS feed, 32-byte
Ed25519 public key, signed-feed requirement, extraction verification, and
non-silent-install settings. It does not submit credentials, generate an
appcast, or claim that a release is valid without a real artifact.

Sparkle performs feed validation, archive signature validation, secure download,
extraction validation, and installation through its updater/installer. If any
step fails, the updater reports an error and does not replace the current app.
This repository does not claim a real release update until the signed feed,
archive, Developer ID signature, and notarization have been supplied and tested.
