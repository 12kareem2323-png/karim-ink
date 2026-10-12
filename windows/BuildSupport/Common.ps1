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
# Setup-only preflight: reads the extracted payload, never drawing libraries or credentials.
function Assert-KarimPayload([string]$source) {
    $required = @('SketchGlide.exe','SketchGlide.dll','SketchGlide.deps.json','SketchGlide.runtimeconfig.json',
        'coreclr.dll','hostfxr.dll','hostpolicy.dll','PresentationCore.dll','wpfgfx_cor3.dll',
        'onnxruntime.dll','x64\tesseract50.dll','x64\leptonica-1.82.0.dll',
        'Resources\SymbolCatalog.json','Resources\MathSymbols\deTeX.onnx','Resources\MathSymbols\classes.json',
        'Resources\OCR\eng.traineddata')
    foreach ($relative in $required) {
        $path = Join-Path $source $relative
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw ('The extracted app is incomplete: ' + $relative + '. Use Extract All on the complete Windows ZIP. The previous installation is untouched.')
        }
    }
    try {
        $deps = Get-Content -LiteralPath (Join-Path $source 'SketchGlide.deps.json') -Raw | ConvertFrom-Json
        $targetName = [string]$deps.runtimeTarget.name
        if (!$targetName.EndsWith('/win-x64')) { throw 'This is not a Windows x64 runtime payload.' }
        $target = $deps.targets.PSObject.Properties[$targetName]
        if (!$target) { throw 'The runtime target is missing.' }
        foreach ($library in $target.Value.PSObject.Properties) {
            foreach ($kind in @('runtime','native')) {
                $section = $library.Value.PSObject.Properties[$kind]
                if (!$section) { continue }
                foreach ($asset in $section.Value.PSObject.Properties) {
                    $name = [IO.Path]::GetFileName($asset.Name.Replace('/', '\'))
                    # Import libraries are build inputs, not runtime dependencies.
                    if ([IO.Path]::GetExtension($name) -notin @('.dll','.exe')) { continue }
                    $path = Join-Path $source $name
                    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw ('A runtime file is missing: ' + $name) }
                }
            }
        }
        $catalogue = Get-Content -LiteralPath (Join-Path $source 'Resources\SymbolCatalog.json') -Raw | ConvertFrom-Json
        if (!$catalogue -or @($catalogue).Count -eq 0) { throw 'The symbol catalogue is empty.' }
        foreach ($symbol in $catalogue) {
            $id = [string]$symbol.id
            if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]*$') { throw 'The symbol catalogue has an invalid asset identifier.' }
            $path = Join-Path $source ('Resources\Symbols\' + $id + '.png')
            if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw ('A symbol picture is missing: ' + $id) }
        }
    } catch { throw ('The extracted app could not be validated: ' + $_.Exception.Message + ' Use Extract All on the complete Windows ZIP. The previous installation is untouched.') }
}
function Copy-KarimPayload([string]$source,[string]$stage,[string]$packageRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $source -File) {
        if ($file.Name -ne 'install-state.json' -and ($file.Name -eq 'LICENSE' -or $file.Extension -in @('.exe','.dll','.json','.pdb','.md','.txt','.config','.cmd'))) {
            Copy-Item -LiteralPath $file.FullName -Destination $stage -Force
        }
    }
    foreach ($directory in @('Resources','Examples','BuildSupport','Prerequisites','x64','runtimes','Verification')) {
        $path = Join-Path $source $directory
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $stage -Recurse -Force }
    }
    # Nested App/Runtime layouts may keep their setup files and receipts at the outer root.
    foreach ($directory in @('BuildSupport','Prerequisites','Verification')) {
        $path = Join-Path $packageRoot $directory
        if ((Test-Path -LiteralPath $path) -and !(Test-Path -LiteralPath (Join-Path $stage $directory))) { Copy-Item -LiteralPath $path -Destination $stage -Recurse -Force }
    }
    foreach ($name in @('LICENSE','README.md','THIRD-PARTY-NOTICES.md','Install.cmd','Uninstall.cmd','RUN-CHECKS.cmd')) {
        $path = Join-Path $packageRoot $name
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and !(Test-Path -LiteralPath (Join-Path $stage $name))) { Copy-Item -LiteralPath $path -Destination $stage -Force }
    }
}
function New-KarimInstallStage([string]$source,[string]$destination,[string]$packageRoot) {
    Assert-KarimPayload $source
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $stage = Join-Path $parent ('KarimEldamaty.stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try { Copy-KarimPayload $source $stage $packageRoot; Assert-KarimPayload $stage }
    catch { Remove-Item -LiteralPath $stage -Recurse -Force; throw }
    return $stage
}
function Move-KarimInstallStage([string]$stage,[string]$destination) {
    Assert-KarimPayload $stage
    $previous = $null
    if (Test-Path -LiteralPath $destination) {
        $previous = $destination + '.previous-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
        [IO.Directory]::Move($destination,$previous)
    }
    # Stage and destination share a parent/volume. Directory.Move renames the whole
    # directory instead of partially moving its children like PowerShell Move-Item.
    try { [IO.Directory]::Move($stage,$destination) }
    catch { if ($previous) { [IO.Directory]::Move($previous,$destination) }; throw }
    return $previous
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
