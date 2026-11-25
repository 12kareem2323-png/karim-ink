# Velin for Windows

A native Windows whiteboard by **Karim Eldamaty**. This is the portable **Windows 11 x64 test build** for Intel and AMD processors. The ZIP includes the .NET Desktop Runtime. WPF uses Windows graphics acceleration where the driver supports it, with software rendering available on lower-tier graphics.

## Open Velin

1. Download the Windows x64 ZIP and SHA-256 checksum from the release page.
2. Choose **Extract All**, then open **Velin.exe** from the extracted folder. Keep the whole folder together.
3. Keep your editable drawings backed up. This Test build is unsigned, so Windows can show an unknown-publisher or SmartScreen prompt. Download from the official GitHub release.

If an offline recognition tool reports a missing native runtime DLL, use Microsoft's [Visual C++ x64 Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

## Draw and annotate

- Ten pen types with colour and pressure settings, Windows Ink tablet input, undo/redo, editable copy and paste, sixteen paper patterns, and drawing tools for shapes and millimetre dimensions.
- Light, dark and system appearance, floating glass toolbars, and a solid fallback for Windows high contrast, disabled transparency and software rendering.
- The Mac build 116 ink model runs locally. Use **Ink assist** to pick **Hold to snap**, **Snap on release**, or **Shape snapping off**. Ctrl+Z after a snap restores the freehand ink. Lines stay unselected after drawing.
- Open a PDF using **PDF** or Ctrl+O. Use **PDF** for page thumbnails, page navigation, source text search and current/range/all export. Ctrl+F opens PDF text search. Search and copy need selectable source text. PDF export preserves the original page contents and adds a high-resolution raster annotation layer. Keep the editable page in Velin to revise your notes.
- Browse maths and engineering symbols, open the formula and 3D sketch workbenches, and use the local handwriting and single-symbol recognition tools. The optional local assistant uses Ollama. The optional cloud assistant uses your OpenAI API key.
- Windows Ink uses the pressure, tilt and buttons exposed by tablet drivers. Wacom, Xencelabs and other brands use that same input route. Pen-specific behaviour depends on the installed driver.

## Files and updates

Drawings and imported PDF originals live under **%LOCALAPPDATA%\Karim Eldamaty\Boards**. Preferences and protected credentials live under **%LOCALAPPDATA%\KarimEldamaty**. These folders are shared with the earlier Windows project to preserve drawings and settings. Keep both the drawing files and their **PDF Originals** subfolder when moving annotated PDFs to another PC.

On the Library screen, select **Check for updates…**. The editor has the same link under **More**. Velin checks GitHub for a newer Windows x64 release and opens its download page. Extract each new version into its own folder. The new executable opens the same drawing library.

[GitHub releases](https://github.com/12kareem2323-png/karim-ink/releases) · [Editable Windows source](https://github.com/12kareem2323-png/karim-ink/tree/velin/windows-x64) · [Feedback](https://github.com/12kareem2323-png/karim-ink/issues/new/choose)

## Build from source

Use the .NET 10 SDK and Python 3.11 or later. To build the Windows x64 app, run these commands from the repository root.

```powershell
dotnet restore windows/KarimEldamatyWindows.csproj --runtime win-x64 --locked-mode
dotnet publish windows/KarimEldamatyWindows.csproj -c Release -r win-x64 --no-restore --self-contained true -o out/velin-windows
python windows/BuildSupport/package_windows.py out/velin-windows out/velin-release
```

The original code is MIT-licensed. See [dependency notices](THIRD-PARTY-NOTICES.md). Maintainer release steps are in [Releasing Velin](RELEASING.md) in the source branch.
