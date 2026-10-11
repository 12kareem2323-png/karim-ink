. (Join-Path $PSScriptRoot 'Common.ps1')
$testDirectory = $null
try {
    Assert-WindowsX64; Assert-KarimClosed
    $source = Get-KarimPayload; $exe = Join-Path $source 'SketchGlide.exe'
    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Karim-Windows-Check-Receipts-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testDirectory | Out-Null
    $receiptParent = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Karim Windows checks'
    $receiptDirectory = Join-Path $receiptParent ([DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6))
    Write-Host 'Running native Windows checks in an isolated temporary drawing library and settings folder.'
    Write-Host 'Test windows will open and close. No real drawings, profiles or credentials are read or changed; no cloud request is made.'
    $process = Start-Process -FilePath $exe -ArgumentList '--self-test',('"' + $testDirectory + '"') -PassThru -WorkingDirectory $source
    $timedOut = !$process.WaitForExit(180000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit(); Write-Host 'The isolated test process timed out and was stopped.' }
    $process.Refresh()
    New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $testDirectory -File) { Copy-Item -LiteralPath $file.FullName -Destination $receiptDirectory -Force }
    $reportPath = Join-Path $receiptDirectory 'windows-runtime-results.json'
    $passed = $false
    if (Test-Path -LiteralPath $reportPath) { $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json; $passed = $report.passed -eq $true -and $process.ExitCode -eq 0 -and !$timedOut }
    [ordered]@{ passed=$passed; runAt=[DateTimeOffset]::Now.ToString('o'); exitCode=$process.ExitCode; timedOut=$timedOut; executableSHA256=(Get-FileDigest $exe); receiptFolder=$receiptDirectory; physicalTabletTested=$false; liveOpenAIOrCraftTested=$false; visualInspectionRequired=$true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptDirectory 'run-checks-summary.json') -Encoding UTF8
    Write-Host ('Receipts and screenshots: ' + $receiptDirectory)
    Write-Host 'Inspect every screenshot. These checks do not prove physical pen pressure/tilt/eraser behaviour or live AI/Craft access.'
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"' + $receiptDirectory + '"')
    if (!$passed) { throw 'Some Windows checks failed or produced no complete report. Keep the receipt folder for investigation.' }
    Write-Host 'Automated Windows checks passed on this PC. Screenshot review and physical tablet testing remain separate.'
} catch { Write-Error $_; exit 1 }
finally { if ($testDirectory -and (Test-Path -LiteralPath $testDirectory)) { Remove-Item -LiteralPath $testDirectory -Recurse -Force } }
