# SketchGlide for macOS — 0.2 Test

A personal project made by Karim Eldamaty. A native SwiftUI/AppKit whiteboard for drawing, maths, diagrams and ideas. This is editable source for the Mac app, not a browser wrapper.

## Build

On an Apple Silicon Mac with Apple Command Line Tools installed:

```sh
./build.sh
```

The default output is `dist/SketchGlide.app`. Override `KARIM_APP_PATH`, `KARIM_BUILD_DIR`, `KARIM_ARCH` or `KARIM_SDK` if needed. The checked-in project also opens in Xcode; regenerate it with `python3 BuildSupport/create_xcode_project.py` after adding source files. No external Swift packages or private account credentials are required.

The build script uses an installed compatible 26.5 SDK when available because this development Mac's newer default SDK does not match its Swift compiler. A local Clang VFS overlay guards an observed missing Carbon header without editing the installed SDK. You can select a complete SDK with `KARIM_SDK`.

## Included

- Ten brush profiles and ten paper backgrounds; per-brush colour, width, opacity and pressure controls.
- Native tablet pressure/tilt/proximity input, driver shortcut mapping and an optional community Quick Keys bridge. Physical hardware compatibility must be tested on each setup.
- Separate drawing and selection tools, pan/zoom, undo/redo, stroke/pixel erasing, shapes, guides and millimetre dimensions.
- Local editable drawing library with atomic saves, archive/recovery and import/export. PDF, PNG, JPEG and editable `.engboard` export.
- 380 engineering/mathematics symbols and a local Core ML recognizer with 1,098 symbol commands. The recognizer handles single symbols; candidates need review.
- Local handwriting smoothing and OCR review, optional cloud AI with the user's own OpenAI API key, text/formula tools, calculator and graph plotting.
- 3D sketch planes and primitive sketches, editable `.karim3d` files, Craft exchange and Notion-friendly HTML export.
- Light, dark and system appearance, native glass controls, feedback tools and an optional external PayPal support link.

## Compatibility and privacy

The distributed Mac Test targets Apple Silicon and macOS 14 or later. Runtime QA is on an Apple Silicon development Mac; older macOS and Intel have not been validated. This Test app is ad hoc signed and unnotarized, so Gatekeeper may block first launch. Keep system protections enabled and use Apple's Privacy & Security → Open Anyway only if you trust the official download.

Drawings stay local. The ordinary app preserves the earlier Karim Ink storage location, internal bundle identifier and file formats so upgrades remain compatible. The `--release-smoke-test` option creates its own fresh temporary drawing library; it never opens existing drawings.

Optional cloud requests send only the content selected for that request; paid AI requires separate user configuration. Feedback is reviewed before opening GitHub. The app does not collect card details: PayPal support opens the public provider website. No private boards, account tokens, installed proprietary apps or training database are in this source tree.

## Improve it

Read [CONTRIBUTING.md](CONTRIBUTING.md). Own code is MIT licensed; third-party resources retain separate terms described in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Public repository and feedback: https://github.com/12kareem2323-png/karim-ink
Project website: https://karim-ink.stonyvale1.chatgpt.site
Optional support: https://paypal.me/KEldamaty

This is an early Test release. It does not claim a guaranteed 120 FPS, zero latency, standards certification, physical testing of every tablet, live multiplayer or complete handwriting-to-LaTeX recognition.
