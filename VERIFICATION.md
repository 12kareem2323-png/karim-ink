# SketchGlide 0.2 Test verification

Build success, real app behaviour and physical hardware tests are separate results. The release uses only made-up documents for QA; private drawings are excluded.

## Mac

- Fresh Swift release build: succeeded; Apple Silicon arm64, version 0.2.0/build 2, macOS 14 deployment target.
- Real packaged shipping app: isolated home/canvas/feedback launch and clean exit, with a fresh empty library. Native screenshots reviewed.
- Offline Core ML inference and missing-model rejection checked in a real bundle.
- Native production-source harnesses: 122 storage/input assertions, 9 cache comparisons, 40 synthetic tablet checks, 47 URL-routing checks, 64 mocked AI/OCR assertions and 438 maths/symbol/export/3D checks.
- Built, extracted ZIP and mounted DMG app signatures validated. Source/model/resource/package content and hashes checked.
- Final neutral UI/prompt wording rebuilt and launch/package checks refreshed. Earlier behaviour tests remain applicable to unchanged logic.

Runtime was Apple Silicon macOS 27.2. Command Line Tools lack XCTest, so the supplied XCTest suite was not executed. Mac Test is ad hoc signed/unnotarized. Physical tablets/remotes, live paid cloud requests, Intel/older macOS, locked 120 FPS and battery/thermal performance remain unverified.

## Windows

The Test is self-contained Windows x64, not an Electron wrapper. Portable production logic checks and isolated native Windows checks are recorded in the Windows source README/release report. Real WPF rendering was checked in the logged-in desktop, using a fresh library and synthetic input; service-session rendering differs and is not a valid desktop visual test.

Windows runtime verification uses x64 emulation on Windows ARM in Parallels. It is not a physical Intel/AMD PC or real tablet test. The Test is unsigned. OCR can miss characters even on the synthetic printed fixture; reviewed transcription is required. Live paid services, every tablet brand and sustained high-refresh/battery performance remain unverified.

## Website and media

42 fresh local browser checks passed across 360, 390, 768 and 1440 pixel widths, including light/dark, looping/offscreen motion, Reduced Motion, scroll camera, no idle camera render loop, safe local feedback export, PayPal and H.264 video decoding. Public deployment/download checks are separate and performed after upload.

The supplied promo clips are edited programmatic animations with a real synthetic app screenshot. They are not generative-AI footage or an exhaustive feature demonstration. The Creator Kit provides five timed one-minute scripts, editable prompts/captions/subtitles and public posting links.
