. (Join-Path $PSScriptRoot 'Common.ps1')
try {
    Assert-WindowsX64; Assert-KarimClosed
    $destination = Get-KarimInstallDirectory; $manifest = Join-Path $destination 'install-state.json'
    if (!(Test-Path -LiteralPath $manifest)) { throw 'No installation made by Install.cmd was found. Remove an extracted portable folder manually; keep your .engboard files.' }
    $state = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($state.Format -ne 1 -or [IO.Path]::GetFullPath($state.InstallDirectory).TrimEnd('\') -ne [IO.Path]::GetFullPath($destination).TrimEnd('\')) { throw 'Installation manifest is invalid. Nothing was removed.' }
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show("Remove this installed app and its shortcuts?`r`n`r`nYour drawing library, profiles, API/Craft credentials, exported files and previous app backups are kept.", 'Uninstall SketchGlide', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Host 'Uninstall cancelled.'; exit 0 }
    $expectedCommand = '"' + (Join-Path $destination 'SketchGlide.exe') + '" "%1"'
    foreach ($record in @($state.Registry)) {
        $allowed = ($record.Path -eq 'HKEY_CURRENT_USER\Software\Classes\karimboard' -and $record.Kind -eq 'uri' -and $record.BackupFile -eq 'RegistryBackup\karimboard.reg') -or ($record.Path -eq 'HKEY_CURRENT_USER\Software\Classes\.engboard\shell\KarimEldamaty' -and $record.Kind -eq 'context' -and $record.BackupFile -eq 'RegistryBackup\engboard-context.reg')
        if (!$allowed -or $record.ExpectedCommand -ne $expectedCommand) { throw 'Invalid registered-handler record. Removal stopped.' }
        Restore-KarimRegistry $record $destination
    }
    foreach ($shortcut in @($state.Shortcuts)) {
        if (!(Test-Path -LiteralPath $shortcut)) { continue }
        $shell = New-Object -ComObject WScript.Shell; $item = $shell.CreateShortcut($shortcut)
        if ($item.TargetPath -eq (Join-Path $destination 'SketchGlide.exe')) { Remove-Item -LiteralPath $shortcut -Force }
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
    }
    Set-Location -LiteralPath ([IO.Path]::GetTempPath())
    foreach ($file in @($state.Files)) {
        $path = [IO.Path]::GetFullPath((Join-Path $destination $file.Path))
        if (!$path.StartsWith($destination.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid installed-file path. Removal stopped.' }
        if (!(Test-Path -LiteralPath $path)) { continue }
        if ((Get-FileDigest $path) -eq $file.SHA256) { Remove-Item -LiteralPath $path -Force } else { Write-Host ('Preserved changed file: ' + $file.Path) }
    }
    Remove-Item -LiteralPath $manifest -Force
    foreach ($directory in Get-ChildItem -LiteralPath $destination -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending) { if (@(Get-ChildItem -LiteralPath $directory.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $directory.FullName -Force } }
    if (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 0) { Remove-Item -LiteralPath $destination -Force }
    Write-Host 'App removed. Drawing libraries, settings and previous app backups were kept.'
} catch { Write-Error $_; exit 1 }
