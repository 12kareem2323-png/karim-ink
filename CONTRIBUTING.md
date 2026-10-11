# Contribute to SketchGlide

You can edit, build and share the original code under the MIT License. Keep third-party copyright and licence notices.

1. Fork this repository and create a focused branch.
2. Change the Mac code in `macos/`, Windows code in `windows/`, or static website in `docs/`.
3. Build and check the affected drawing/file/export behaviour with made-up documents. Add meaningful tests for changed behaviour.
4. Open a pull request explaining the problem, resulting behaviour and checks you actually ran. Include safe screenshots where useful.

Keep native file compatibility, atomic saves/recovery, deliberate stroke selection and accessibility controls. Network features must be deliberate and show their route. Avoid running continuous rendering for an idle canvas. Do not include private drawings, account keys, device serial numbers or copied proprietary apps.

See [BUILDING.md](BUILDING.md), platform READMEs and [VERIFICATION.md](VERIFICATION.md). Report reproducible bugs with app version, OS, processor and steps. Physical hardware results should identify the tablet/driver and state what was actually tested. Report security issues privately through GitHub's security reporting when available.
