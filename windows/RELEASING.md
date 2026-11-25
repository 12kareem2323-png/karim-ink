# Releasing a Windows update

Velin uses the `velin/windows-x64` branch in Karim Eldamaty's GitHub project. Windows releases use the `velin-windows-v` tag prefix.

1. Update `<Version>` in `windows/KarimEldamatyWindows.csproj`. For the next preview, use `1.0.0-test.2`.
2. Commit and push that change to `velin/windows-x64`. Check the **Velin Windows x64** workflow. It runs the drawing, services and workbench suites, compiles a self-contained x64 app and builds the ZIP and SHA-256 manifest.
3. Tag the tested commit with the matching version.

```bash
git tag -a velin-windows-v1.0.0-test.2 -m "Velin Windows 1.0.0 Test 2"
git push origin velin-windows-v1.0.0-test.2
```

4. The tag workflow puts the ZIP and checksum on a draft GitHub release. Download that ZIP, match its SHA-256, extract it, and check drawing, save/reopen, PDFs and your tablet on Windows 11. Measure high-refresh behaviour on the target PC when it matters.
5. Review the release notes and publish the draft. The Windows app finds it under **Check for updates…**. A stable version uses a tag such as `velin-windows-v1.0.0` and a matching project version.

To run the app's synthetic Windows checks against that extracted package, use PowerShell from the package folder. This uses a temporary test library.

```powershell
$receipt = Join-Path $env:TEMP ('VelinCheck-' + [guid]::NewGuid())
$p = Start-Process .\Velin.exe -ArgumentList '--self-test', ('"' + $receipt + '"') -PassThru -Wait
Get-Content (Join-Path $receipt 'windows-runtime-results.json')
$p.ExitCode
```
