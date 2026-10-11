# Contributing to SketchGlide

You can edit, build and share this app's source under the MIT License. Keep all copyright notices and third-party terms. Contributions should be your own work or clearly attributed compatible material.

1. Fork the public repository and create a focused branch.
2. Make changes under `macos/Sources/EngineeringBoard` and add tests when behaviour warrants them.
3. Build the Mac app, run available tests and check affected drawing/export behaviour using synthetic documents. Never upload private drawings or account keys.
4. Open a pull request explaining the problem, the change and the tests you actually ran. Screenshots should use a made-up drawing.

Command Line Tools on the development Mac do not contain the XCTest runtime. `swift test` may require a full compatible Xcode installation; see VERIFICATION.md for the native executable harnesses that were run for this release.

Report reproducible bugs using version, OS and processor type. Do not include serial numbers, paid API keys, device identifiers or personal work. Report security issues using GitHub's private vulnerability report when available.

Keep `.engboard` and `.karim3d` compatibility, atomic-save/recovery safeguards, deliberate selection and no automatic bounding boxes after drawing. Preserve the lightweight event-driven canvas and accessibility settings. A feature should not silently send content to a network service.
