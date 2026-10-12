# SketchGlide · Windows 0.2 Test

Made by **Karim Eldamaty**. A personal whiteboard project for sketching, ideas, maths and diagrams. The Windows version uses native C# / WPF and ships with its .NET 10 runtime.

This is an **unsigned test release for Windows 11 Intel/AMD x64**. It is not a final stable release. Download from the project's GitHub release, compare its SHA-256 checksum, and keep your native drawings backed up. Windows may show an unknown-publisher or SmartScreen warning. Do not disable Windows security to run it.

## Start

1. Right-click the ZIP and choose **Extract All**.
2. Open **SketchGlide.exe** in the extracted folder. Keep the entire folder together: its DLLs and `Resources` are required.
3. If Windows reports a missing native DLL, use the [official Microsoft Visual C++ x64 runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). Its installer is not bundled and the app does not install it automatically.
4. Optionally run `Install.cmd` to copy the app into `%LOCALAPPDATA%\Programs\KarimEldamaty` and create a shortcut. The historical install/data paths and `karimboard://` scheme are preserved for file compatibility. Registering native drawing links requires selecting the installer's separate option; existing default file openers are unchanged.

`Uninstall.cmd` removes only unchanged installed files and its unchanged shortcuts/handlers, restores backed-up previous handlers, and keeps drawings, credentials, settings and previous app backups. If you use only the portable folder, keep your drawings and delete that extracted folder when finished.

## Features in this test

- Ten adjustable pen styles: technical fineliner, fountain, pencil, chalk, marker, calligraphy, airbrush, liquid ink, highlighter and dry erase.
- Ten canvas backgrounds; pan/zoom, editable text, line/shape tools, hold-to-correct geometry, millimetre dimensions, rulers and a protractor.
- Select/lasso, stroke/partial erasing, undo/redo, keyboard shortcuts and native Windows copy/paste of editable fragments, text and a rendered image.
- 380 maths/engineering diagram stencils, with a virtualised searchable library and short symbol animations.
- System, light and dark themes, translucent panels and native Windows DWM styling where supported; Reduce transparency is available.
- Local native `.engboard` storage with atomic writes, conflict detection and archive-on-delete. No account is required to draw and save locally.
- Local Tesseract English OCR, editable transcription review and Windows spelling suggestions. Replacement is explicit and undoable. Recognition may miss handwriting, symbols, numbers, decimals and units: review every result.
- Offline DeTeXt-derived **single-symbol** recognition with 1,098 model classes; an editable formula workbench. Full handwritten-equation recognition is not included.
- Simple 3D sketches with primitives, freehand strokes, view controls and `.karim3d` scene files. This is a sketching tool, with no full CAD assemblies or manufacturing validation.
- Calculator, unit conversion and graph plotting tools. Check units and assumptions before relying on results.
- An optional OpenAI API assistant using your own API key, plus an optional separately installed local Ollama model. No API key is bundled. A ChatGPT subscription is separate from OpenAI API access/billing. Requests show their route; drawings are attached only when you select that option. A failed local request does not trigger a hidden cloud fallback.
- Craft connection tools and an Excalidraw export; Notion HTML export. Live service access depends on your account/scoped credentials and is separate from local drawing.
- PNG/JPEG/PDF export. Windows PDF export embeds a raster drawing; the Mac version's PDF path is vector. Keep `.engboard` for editing.

The Windows tablet path uses the pressure/tilt/hover/eraser data exposed by the installed Windows driver. It is not restricted to one tablet brand. Install your manufacturer's official driver, then test your own pen and buttons. Driver shortcut remotes use your driver mappings; this app does not guarantee a proprietary tablet SDK or OLED labels for every device.

Keyboard shortcuts include Ctrl+N/O/S, Ctrl+Z/Y, B (draw), E (erase), V (select), L (lasso), and 1–9 / 0 for the ten pens when the canvas is active. Text fields keep ordinary typing.

## Files and privacy

Drawings remain under `%LOCALAPPDATA%\Karim Eldamaty\Boards`. Preferences, device pen profiles and Windows-user-encrypted credentials remain under `%LOCALAPPDATA%\KarimEldamaty`. These historical paths preserve existing files; they do not change the display name. Credentials are not saved into `.engboard` files or exports. Back up your editable drawing files and exports.

The Notion HTML export is an offline copy: existing artwork is a background image, while new browser ink can be downloaded separately. It does not automatically synchronise native drawing changes or embed a live native app in Notion/Craft. Hosted HTML requires separate hosting.

[Website](https://karim-ink.stonyvale1.chatgpt.site/) · [Feedback](https://github.com/12kareem2323-png/karim-ink/issues/new/choose) · [Support Karim Eldamaty with PayPal](https://paypal.me/KEldamaty)

## Verification

The release is built for Windows x64 on macOS. Portable checks exercise production document/storage, arithmetic/formula/3D logic and service HTTP validation with documented WPF/rendering substitutes and mocked remote responses. Native Windows checks use an isolated temporary library and settings folder, synthetic drawings and no cloud request. Exact release results are in `Verification/release-report.json`.

To repeat native checks on your PC, close the normal app yourself and run `RUN-CHECKS.cmd`. Test windows open and close and receipts/screenshots are saved into `Documents\Karim Windows checks`. Review the screenshots. Tests on Windows ARM under x64 emulation are not a physical Intel/AMD PC test.

Physical tablet pressure, tilt, eraser ends and buttons, live paid AI/Craft requests, and sustained high-refresh performance remain separate tests. No locked 120 FPS, zero latency, complete feature parity, or universal handwriting accuracy is claimed.

## Edit and build

Original project source is licensed under **MIT**; dependencies retain their separate licences in `Resources` and `THIRD-PARTY-NOTICES.md`. You may inspect, modify and contribute improvements. See `CONTRIBUTING.md`.

Install the .NET 10 SDK, then run from this source folder:

```powershell
dotnet publish KarimEldamatyWindows.csproj -c Release -r win-x64 --self-contained true -o publish
```

The first build restores NuGet packages over the internet. `BuildSupport/Publish-Windows.ps1` performs the same build. The output is `SketchGlide.exe`; internal namespaces and native file formats retain their existing names for compatibility.

Portable verification commands:

```powershell
dotnet run --project Verification/Core/CoreVerification.csproj -c Release
dotnet run --project Verification/Services/Services.Tests.csproj -c Release
dotnet run --project Workbenches/Verification/Logic/WorkbenchLogic.csproj -c Release
```

Portable tests do not execute WPF rendering or physical pen input. Use the native self-test and a real tablet for those checks.
