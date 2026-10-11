. (Join-Path $PSScriptRoot 'Common.ps1')
try {
    Assert-WindowsX64; Assert-KarimClosed
    $source = Get-KarimPayload; $destination = Get-KarimInstallDirectory
    if ([IO.Path]::GetFullPath($source).TrimEnd('\') -eq [IO.Path]::GetFullPath($destination).TrimEnd('\')) { throw 'Run Install.cmd from the newly extracted ZIP, not from the installed folder.' }
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Install SketchGlide for this Windows user'; $form.Width = 660; $form.Height = 340
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $description = New-Object Windows.Forms.Label
    $description.Text = "Copy the app into:`r`n$destination`r`n`r`nYour drawing library, pen profiles and AI/Craft settings stay outside this app folder. An older installed app folder is kept as a backup."
    $description.SetBounds(20,18,605,100); $form.Controls.Add($description)
    $startMenu = New-Object Windows.Forms.CheckBox; $startMenu.Text = 'Create a Start menu shortcut'; $startMenu.Checked = $true; $startMenu.SetBounds(20,128,580,25); $form.Controls.Add($startMenu)
    $desktop = New-Object Windows.Forms.CheckBox; $desktop.Text = 'Create a desktop shortcut'; $desktop.SetBounds(20,158,580,25); $form.Controls.Add($desktop)
    $links = New-Object Windows.Forms.CheckBox; $links.Text = 'Enable karimboard links and an .engboard Open with context menu'; $links.SetBounds(20,188,610,25); $form.Controls.Add($links)
    $note = New-Object Windows.Forms.Label; $note.Text = 'File defaults are unchanged. Previous karimboard handlers are backed up for Uninstall.'; $note.SetBounds(20,222,610,24); $form.Controls.Add($note)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Install'; $ok.SetBounds(428,258,92,30); $ok.DialogResult = [Windows.Forms.DialogResult]::OK; $form.AcceptButton = $ok; $form.Controls.Add($ok)
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.SetBounds(532,258,92,30); $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel; $form.CancelButton = $cancel; $form.Controls.Add($cancel)
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { Write-Host 'Install cancelled. Nothing changed.'; exit 0 }
    $parent = Split-Path -Parent $destination; New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $stage = Join-Path $parent ('KarimEldamaty.stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $source -File) {
        if ($file.Name -ne 'install-state.json' -and $file.Extension -in @('.exe','.dll','.json','.pdb','.md','.txt','.config','.cmd')) { Copy-Item -LiteralPath $file.FullName -Destination $stage -Force }
    }
    foreach ($directory in @('Resources','Examples','BuildSupport','Prerequisites','x64','runtimes')) {
        $path = Join-Path $source $directory
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $stage -Recurse -Force }
    }
    # A package with its runtime in App/ or Runtime/ may keep docs/scripts at the outer root.
    $packageRoot = Split-Path -Parent $PSScriptRoot
    foreach ($directory in @('BuildSupport','Prerequisites')) {
        $path = Join-Path $packageRoot $directory
        if ((Test-Path -LiteralPath $path) -and !(Test-Path -LiteralPath (Join-Path $stage $directory))) { Copy-Item -LiteralPath $path -Destination $stage -Recurse -Force }
    }
    if (!(Test-Path -LiteralPath (Join-Path $stage 'SketchGlide.exe'))) { throw 'The staged app is incomplete. The previous installation is untouched.' }
    $oldState = $null; $oldStatePath = Join-Path $destination 'install-state.json'
    if (Test-Path -LiteralPath $oldStatePath) { $oldState = Get-Content -LiteralPath $oldStatePath -Raw | ConvertFrom-Json }
    $registry = @(); $command = '"' + (Join-Path $destination 'SketchGlide.exe') + '" "%1"'
    $backupDirectory = Join-Path $stage 'RegistryBackup'; New-Item -ItemType Directory -Path $backupDirectory | Out-Null
    if ($links.Checked) {
        $records = @(
            @{ Path='HKEY_CURRENT_USER\Software\Classes\karimboard'; Kind='uri'; BackupFile='RegistryBackup\karimboard.reg' },
            @{ Path='HKEY_CURRENT_USER\Software\Classes\.engboard\shell\KarimEldamaty'; Kind='context'; BackupFile='RegistryBackup\engboard-context.reg' }
        )
        foreach ($record in $records) {
            $record.ExpectedCommand = $command; $record.BackupSHA256 = $null; $psPath = 'HKCU:\' + $record.Path.Substring('HKEY_CURRENT_USER\'.Length)
            $existingCommandPath = if ($record.Kind -eq 'uri') { Join-Path $psPath 'shell\open\command' } else { Join-Path $psPath 'command' }
            $ours = (Test-Path -LiteralPath $existingCommandPath) -and ((Get-Item -LiteralPath $existingCommandPath).GetValue('') -eq $command)
            $previousRecord = if ($oldState -and $ours) { @($oldState.Registry | Where-Object { $_.Path -eq $record.Path }) | Select-Object -First 1 } else { $null }
            if ($previousRecord) {
                $record.Existed = $previousRecord.Existed
                if ($record.Existed) { Copy-Item -LiteralPath (Join-Path $destination $previousRecord.BackupFile) -Destination (Join-Path $stage $record.BackupFile) -Force }
            } else {
                $record.Existed = Test-Path -LiteralPath $psPath
                if ($record.Existed) { Invoke-RegistryExport $record.Path (Join-Path $stage $record.BackupFile) }
            }
            if ($record.Existed) { $record.BackupSHA256 = Get-FileDigest (Join-Path $stage $record.BackupFile) }
            $registry += [PSCustomObject]$record
        }
    } elseif ($oldState -and $oldState.Registry.Count -gt 0) {
        # Keep an earlier explicit registration choice when updating; don't silently remove it.
        $registry = @($oldState.Registry)
        $oldBackups = Join-Path $destination 'RegistryBackup'
        if (Test-Path -LiteralPath $oldBackups) { Copy-Item -Path (Join-Path $oldBackups '*') -Destination $backupDirectory -Force }
    }
    $shortcuts = @(); $exe = Join-Path $destination 'SketchGlide.exe'
    if ($oldState) {
        foreach ($path in @($oldState.Shortcuts)) {
            if (Test-Path -LiteralPath $path) {
                $shell = New-Object -ComObject WScript.Shell; $existing = $shell.CreateShortcut($path)
                if ($existing.TargetPath -eq $exe) { $shortcuts += $path }
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
            }
        }
    }
    $state = [ordered]@{ Format=1; InstallDirectory=$destination; InstalledAt=[DateTimeOffset]::Now.ToString('o'); Registry=$registry; Shortcuts=@($shortcuts | Select-Object -Unique); Files=@(); PreviousInstall=$null }
    $state.Files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { [PSCustomObject]@{ Path=$_.FullName.Substring($stage.Length+1); SHA256=(Get-FileDigest $_.FullName) } })
    $previous = $null
    if (Test-Path -LiteralPath $destination) { $previous = $destination + '.previous-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6); Move-Item -LiteralPath $destination -Destination $previous; $state.PreviousInstall = $previous }
    try { Move-Item -LiteralPath $stage -Destination $destination } catch { if ($previous) { Move-Item -LiteralPath $previous -Destination $destination }; throw }
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'install-state.json') -Encoding UTF8
    if ($links.Checked) {
        Set-RegistryDefault 'HKCU:\Software\Classes\karimboard' 'URL:SketchGlide drawing'
        New-ItemProperty -Path 'HKCU:\Software\Classes\karimboard' -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
        Set-RegistryDefault 'HKCU:\Software\Classes\karimboard\shell\open\command' $command
        Set-RegistryDefault 'HKCU:\Software\Classes\.engboard\shell\KarimEldamaty' 'Open with SketchGlide'
        Set-RegistryDefault 'HKCU:\Software\Classes\.engboard\shell\KarimEldamaty\command' $command
    }
    if ($startMenu.Checked) { $path = Join-Path ([Environment]::GetFolderPath('Programs')) 'SketchGlide.lnk'; New-KarimShortcut $path $exe; $shortcuts += $path; $state.Shortcuts = @($shortcuts | Select-Object -Unique); $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'install-state.json') -Encoding UTF8 }
    if ($desktop.Checked) { $path = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'SketchGlide.lnk'; New-KarimShortcut $path $exe; $shortcuts += $path }
    $state.Shortcuts = @($shortcuts | Select-Object -Unique); $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'install-state.json') -Encoding UTF8
    Write-Host "Installed for this user: $destination"
    Write-Host 'Run SketchGlide.exe or use your shortcut. Visual C++ installation is a separate optional step.'
    if ($previous) { Write-Host "Previous app folder retained: $previous" }
} catch { Write-Error $_; exit 1 }
