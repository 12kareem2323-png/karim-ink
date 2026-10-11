# Development and release notes

This GitHub repository distributes the Karim Ink Mac preview, documentation and feedback channels. It does **not** contain the full native application's source. A ZIP of this repository is not an app or a buildable whiteboard project. Download the `.app` ZIP or DMG from [Releases](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.1.0).

## Native development project

Karim's local editable project uses Swift 5.10-compatible source, SwiftUI/AppKit for the workspace, Metal for accelerated ink, Core ML/Vision for local recognition and SceneKit for concept sketches. Its internal Swift package and executable retain the name `EngineeringBoard`; the display name is Karim Ink. The minimum deployment target is macOS 14.

For a developer who has that separate complete project, the top-level `build.sh` packages the binary, icon, Info.plist, recognition resources and third-party notices into `Karim Ink.app`. It accepts `KARIM_SDK`, `KARIM_BUILD_DIR`, `KARIM_APP_PATH` and `KARIM_ARCH`; ARM64 is the default. Build it on a Mac with a matching Swift compiler/macOS SDK and Python 3 installed. The public preview was built with the macOS 26.5 SDK because that installed SDK matches the available compiler.

The script creates an ad hoc signature for local integrity verification. That signature does not establish developer identity or supply Apple notarization.

## Public preview checks

The release process checks the built app's version, ARM64 architecture, signature integrity, bundled licences, package contents and SHA-256 checksums. Native harnesses exercise real production drawing, file handling, recognition and 3D logic on Apple Silicon with macOS 27.2. Synthetic pen inputs do not establish physical tablet compatibility. Mocked AI transport tests do not establish a live account integration. Full XCTest execution was unavailable in the installed command-line toolchain.

Public packages exclude personal drawings, API keys, connection tokens, signing keys, private browser profiles and local QA logs. GitHub publishes Mac assets only; Windows is coming soon.

## A future notarized release

Developer ID signing and Apple notarization require the appropriate Apple Developer Program access. The separate native project's `BuildSupport/distribute.sh` accepts an existing Developer ID Application identity and a Keychain-backed notarytool profile, signs with the hardened runtime, submits to Apple, requires Accepted status, staples tickets, checks the result and packages downloads. No passwords or signing keys belong in this repository.

The free 0.1.0 preview does not use that notarized distribution path. [Support](SUPPORT.md) explains its first-launch status.

## Licensing

Public availability of this distribution repository is not a grant of an open-source licence for Karim Ink's original application source. The original application's source-release/licensing decision remains separate. Bundled third-party MIT resources retain their complete copyright and licence notices; see [Third-party notices](THIRD_PARTY_NOTICES.md).
