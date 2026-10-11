# Build SketchGlide

The complete native application source is published under `macos/` and `windows/`. A repository ZIP contains source; ready-to-run app packages are on [Releases](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test).

## Mac

Install Apple's Command Line Tools or a compatible full Xcode and Python 3. On an Apple Silicon Mac:

```sh
cd macos
./build.sh
```

Output: `dist/SketchGlide.app`. Optional `KARIM_SDK`, `KARIM_BUILD_DIR`, `KARIM_APP_PATH` and `KARIM_ARCH` select the SDK, scratch directory, output and architecture. The internal Swift package/executable remains `EngineeringBoard`. The checked-in Xcode project can be regenerated with `python3 BuildSupport/create_xcode_project.py` after adding files.

This release was built using the installed macOS 26.5 SDK, which matches this development Mac's compiler. The script includes a local overlay for an observed missing Carbon header; it does not modify installed SDKs. A source build creates an ad hoc signature, not Developer ID signing or notarization.

A full compatible Xcode installation may run `swift test`. The development Command Line Tools do not include the XCTest runtime, so this release used separate production-source native executable harnesses. See [verification](VERIFICATION.md) and `macos/VERIFICATION.md`.

## Windows

Install the .NET 10 SDK. The first restore needs internet. Run in PowerShell:

```powershell
cd windows
dotnet publish KarimEldamatyWindows.csproj -c Release -r win-x64 --self-contained true -o publish
```

Output: `publish/SketchGlide.exe` with its DLLs and Resources. Keep the whole output folder together. The prepared Test ZIP includes its .NET runtime, so ordinary users do not need the SDK. Optional native OCR dependencies may need Microsoft's official x64 Visual C++ runtime; the installer is not bundled or installed automatically.

Portable checks:

```powershell
dotnet run --project Verification/Core/CoreVerification.csproj -c Release
dotnet run --project Verification/Services/Services.Tests.csproj -c Release
dotnet run --project Workbenches/Verification/Logic/WorkbenchLogic.csproj -c Release
```

These checks use documented platform substitutes/mocked transport. They do not exercise WPF rendering or physical pen input. `RUN-CHECKS.cmd` exercises the real Windows app in a fresh isolated drawing library, saves receipts/screenshots and exits. Review the screenshots and test your real tablet separately.

## Release hygiene

Never commit drawings, API keys, tokens, signing credentials or private account screenshots. Own source is MIT; retain dependency notices. Confirm build, actual launch, exports, package content and SHA-256 hashes before sharing changed binaries. Neither compiling source nor synthetic input proves compatibility with every tablet or computer.
