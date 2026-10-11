Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-WindowsX64 {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'These scripts run on Windows only.' }
    $processor = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    if (!$processor -or $processor.Architecture -ne 9) { throw 'Use this x64 package on an Intel/AMD Windows 11 PC.' }
}
function Get-KarimPayload {
    $package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    foreach ($candidate in @($package, (Join-Path $package 'App'), (Join-Path $package 'Runtime'))) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'SketchGlide.exe')) { return $candidate }
    }
    throw 'SketchGlide.exe is missing. Use Extract All on the complete ZIP before running this script.'
}
function Get-KarimInstallDirectory { return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\KarimEldamaty') }
function Assert-KarimClosed {
    if (Get-Process -Name SketchGlide -ErrorAction SilentlyContinue) { throw 'Close SketchGlide yourself, then run this script again. Your running app has not been closed.' }
}
function Get-FileDigest([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-RegistryCommand([string]$path) {
    if (!(Test-Path -LiteralPath ($path + '\shell\open\command'))) { return $null }
    return (Get-Item -LiteralPath ($path + '\shell\open\command')).GetValue('')
}
function Set-RegistryDefault([string]$path,[string]$value) {
    New-Item -Path $path -Force | Out-Null
    Set-Item -LiteralPath $path -Value $value
}
function Invoke-RegistryExport([string]$nativePath,[string]$outputFile) {
    & "$env:SystemRoot\System32\reg.exe" export $nativePath $outputFile /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The existing per-user file handler could not be backed up. Registration stopped.' }
}
function Restore-KarimRegistry($record,[string]$installDirectory) {
    $psPath = 'HKCU:\' + $record.Path.Substring('HKEY_CURRENT_USER\'.Length)
    $commandPath = Join-Path $psPath 'shell\open\command'
    if ($record.Kind -eq 'context') { $commandPath = Join-Path $psPath 'command' }
    if (!(Test-Path -LiteralPath $commandPath)) { return }
    if ((Get-Item -LiteralPath $commandPath).GetValue('') -ne $record.ExpectedCommand) { Write-Host ('Preserved changed handler: ' + $record.Path); return }
    $backup = $null
    if ($record.Existed) {
        $backup = Join-Path $installDirectory $record.BackupFile
        if (!(Test-Path -LiteralPath $backup)) { throw ('Registry backup is missing. The current handler was kept: ' + $record.BackupFile) }
        if (!$record.PSObject.Properties['BackupSHA256'] -or !(Get-FileDigest $backup).Equals($record.BackupSHA256,[StringComparison]::OrdinalIgnoreCase)) { throw 'Registry backup hash does not match. The current handler was kept.' }
        $text = Get-Content -LiteralPath $backup -Raw
        if (!$text.TrimStart([char]0xfeff).StartsWith('Windows Registry Editor Version 5.00')) { throw 'Registry backup header is invalid. The current handler was kept.' }
        $sections = @($text -split '\r?\n' | Where-Object { $_.Trim().StartsWith('[') })
        if ($sections.Count -eq 0) { throw 'Registry backup has no handler section. The current handler was kept.' }
        foreach ($line in $sections) {
            $trimmed = $line.Trim()
            if (!$trimmed.EndsWith(']')) { throw 'Registry backup section is invalid. The current handler was kept.' }
            $key = $trimmed.Substring(1,$trimmed.Length-2)
            if ($key -ne $record.Path -and !$key.StartsWith($record.Path + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Registry backup contains an unrelated key. The current handler was kept.' }
        }
    }
    Remove-Item -LiteralPath $psPath -Recurse -Force
    if ($record.Existed) {
        & "$env:SystemRoot\System32\reg.exe" import $backup | Out-Null
        if ($LASTEXITCODE -ne 0) {
            if ($record.Kind -eq 'uri') {
                Set-RegistryDefault $psPath 'URL:SketchGlide drawing'
                New-ItemProperty -Path $psPath -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
            } else { Set-RegistryDefault $psPath 'Open with SketchGlide' }
            Set-RegistryDefault $commandPath $record.ExpectedCommand
            throw ('Previous handler could not be restored. The installed app handler was reinstated and removal stopped. Backup: ' + $backup)
        }
    }
}
function New-KarimShortcut([string]$path,[string]$executable) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path); $shortcut.TargetPath = $executable
    $shortcut.WorkingDirectory = Split-Path -Parent $executable; $shortcut.Description = 'SketchGlide Windows drawing workspace'
    $shortcut.IconLocation = $executable + ',0'; $shortcut.Save()
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
}
