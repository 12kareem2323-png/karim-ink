param(
 [Parameter(Mandatory=$true)][string]$PayloadDirectory,
 [string]$HelpersDirectory=(Join-Path $PSScriptRoot '..\..\BuildSupport'),
 [string]$ReportPath=(Join-Path $PSScriptRoot 'installer-smoke-results.json')
)
$ErrorActionPreference='Stop'
$updated=[IO.Path]::GetFullPath($HelpersDirectory)
. (Join-Path $updated 'Common.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('SketchGlide-Setup-Smoke-'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'payload'
$destination=Join-Path $temp 'isolated-install'
$checks=New-Object Collections.Generic.List[object]
function Check([string]$name,[scriptblock]$action){try{& $action;$checks.Add([pscustomobject]@{name=$name;passed=$true})}catch{$checks.Add([pscustomobject]@{name=$name;passed=$false;error=$_.Exception.Message})}}
function Assert([bool]$condition,[string]$message){if(!$condition){throw $message}}
function Reject([scriptblock]$action){$rejected=$false;try{& $action | Out-Null}catch{$rejected=$true};Assert $rejected 'The incomplete payload was accepted.'}
function WithRemoved([string]$relative,[scriptblock]$action){$path=Join-Path $source $relative;$saved=$path+'.smoke-backup';Move-Item -LiteralPath $path -Destination $saved;try{& $action}finally{Move-Item -LiteralPath $saved -Destination $path}}
try {
 New-Item -ItemType Directory -Path $source -Force | Out-Null
 Copy-Item (Join-Path $PayloadDirectory '*') -Destination $source -Recurse
 foreach($name in @('Common.ps1','Install.ps1','Uninstall.ps1')){Copy-Item (Join-Path $updated $name) (Join-Path $source ('BuildSupport\'+$name)) -Force}
 Check 'three setup scripts parse in native Windows PowerShell' {
  foreach($name in @('Common.ps1','Install.ps1','Uninstall.ps1')){
   $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $updated $name),[ref]$tokens,[ref]$errors)|Out-Null
   Assert ($errors.Count -eq 0) ('PowerShell parse error in '+$name)
  }
 }
 Check 'complete v0.2.0 self-contained x64 payload passes preflight' {Assert-KarimPayload $source}
 Check 'missing core runtime is rejected' {WithRemoved 'coreclr.dll' {Reject {Assert-KarimPayload $source}}}
 Check 'missing OCR native DLL is rejected' {WithRemoved 'x64\tesseract50.dll' {Reject {Assert-KarimPayload $source}}}
 Check 'missing offline maths model is rejected' {WithRemoved 'Resources\MathSymbols\deTeX.onnx' {Reject {Assert-KarimPayload $source}}}
 Check 'missing runtime dependency listed in deps is rejected' {WithRemoved 'System.Linq.dll' {Reject {Assert-KarimPayload $source}}}
 Check 'empty main assembly is rejected' {WithRemoved 'SketchGlide.dll' {New-Item -ItemType File -Path (Join-Path $source 'SketchGlide.dll') | Out-Null;try{Reject {Assert-KarimPayload $source}}finally{Remove-Item (Join-Path $source 'SketchGlide.dll')}}}
 Check 'missing catalogue stencil is rejected' {WithRemoved 'Resources\Symbols\Algebra-plus.png' {Reject {Assert-KarimPayload $source}}}
 Check 'malformed dependency JSON is rejected' {WithRemoved 'SketchGlide.deps.json' {Set-Content (Join-Path $source 'SketchGlide.deps.json') '{not json';try{Reject {Assert-KarimPayload $source}}finally{Remove-Item (Join-Path $source 'SketchGlide.deps.json')}}}
 Check 'wrong runtime architecture is rejected' {
  $path=Join-Path $source 'SketchGlide.deps.json';$content=Get-Content $path -Raw
  try{Set-Content $path ($content.Replace('win-x64','win-arm64'));Reject {Assert-KarimPayload $source}}finally{[IO.File]::WriteAllText($path,$content)}
 }
 Check 'catalogue path traversal identifier is rejected' {
  WithRemoved 'Resources\SymbolCatalog.json' {Set-Content (Join-Path $source 'Resources\SymbolCatalog.json') '[{"id":"../../outside"}]';try{Reject {Assert-KarimPayload $source}}finally{Remove-Item (Join-Path $source 'Resources\SymbolCatalog.json')}}
 }
 Check 'invalid payload creates no install parent' {
  $untouched=Join-Path $temp 'not-created\isolated-install'
  WithRemoved 'coreclr.dll' {Reject {New-KarimInstallStage $source $untouched $source}}
  Assert (!(Test-Path (Split-Path $untouched -Parent))) 'Invalid preflight created an install parent.'
 }
 Check 'staging preserves MIT licence and verification receipts' {
  $stage=New-KarimInstallStage $source $destination $source
  try{
   foreach($relative in @('LICENSE','Verification\release-report.json','Verification\windows-runtime-results.json')){
    Assert (Test-Path (Join-Path $stage $relative)) ('Staging omitted '+$relative)
    Assert ((Get-FileDigest (Join-Path $source $relative)) -eq (Get-FileDigest (Join-Path $stage $relative))) ('Staging changed '+$relative)
   }
  }finally{Remove-Item $stage -Recurse -Force}
 }
 Check 'nested runtime layout keeps outer licence setup and receipts' {
  $outer=Join-Path $temp 'outer-package';New-Item -ItemType Directory -Path $outer|Out-Null
  Copy-Item (Join-Path $source 'LICENSE') $outer;Copy-Item (Join-Path $source 'Verification') $outer -Recurse;Copy-Item (Join-Path $source 'BuildSupport') $outer -Recurse
  $stage=Join-Path $temp 'nested-stage';New-Item -ItemType Directory -Path $stage|Out-Null
  $smokeHeldVerificationPath=Join-Path $temp 'held-verification';Move-Item (Join-Path $source 'Verification') $smokeHeldVerificationPath
  WithRemoved 'LICENSE' {
   try{Copy-KarimPayload $source $stage $outer;Assert-KarimPayload $stage;Assert (Test-Path (Join-Path $stage 'LICENSE')) 'Outer LICENSE missing.';Assert (Test-Path (Join-Path $stage 'Verification\release-report.json')) 'Outer receipt missing.'}
   finally{Move-Item $smokeHeldVerificationPath (Join-Path $source 'Verification')}
  }
  Remove-Item $stage -Recurse -Force
 }
 Check 'replacement retains previous synthetic install backup' {
  New-Item -ItemType Directory -Path $destination | Out-Null;Set-Content (Join-Path $destination 'previous-sentinel.txt') 'synthetic previous app'
  $stage=New-KarimInstallStage $source $destination $source
  $backup=Move-KarimInstallStage $stage $destination
  Assert (Test-Path (Join-Path $backup 'previous-sentinel.txt')) 'Previous synthetic install was lost.'
  Assert (Test-Path (Join-Path $destination 'LICENSE')) 'Installed licence missing.'
  Assert (!(Test-Path $stage)) 'Stage was not committed.'
  Remove-Item $destination -Recurse -Force;Move-Item $backup $destination
 }
 Check 'locked replacement rolls back previous synthetic install' {
  $stage=New-KarimInstallStage $source $destination $source
  $lock=[IO.File]::Open((Join-Path $stage 'SketchGlide.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{Reject {Move-KarimInstallStage $stage $destination};Assert (Test-Path (Join-Path $destination 'previous-sentinel.txt')) 'Rollback lost previous app.'}
  finally{$lock.Dispose();if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}
 }
 Check 'copy failure removes only its own temporary stage' {
  $lock=[IO.File]::Open((Join-Path $source 'SketchGlide.dll'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{Reject {New-KarimInstallStage $source $destination $source};Assert (Test-Path (Join-Path $destination 'previous-sentinel.txt')) 'Copy failure changed previous app.';Assert (@(Get-ChildItem $temp -Directory -Filter 'KarimEldamaty.stage-*').Count -eq 0) 'Failed copy left a stage directory.'}
  finally{$lock.Dispose()}
 }
 $passed=@($checks | Where-Object {$_.passed}).Count;$failed=$checks.Count-$passed
 $report=[ordered]@{passed=$passed;failed=$failed;checks=$checks.ToArray();utc=[DateTimeOffset]::UtcNow.ToString('o');os=[Environment]::OSVersion.ToString();scope='Production setup validation/copy/stage-commit functions on Windows, using only an isolated synthetic temporary installation. No existing installed app, real drawings, settings, credentials, shortcuts or registry handlers were read or changed.';interactiveInstallDialogueTested=$false;physicalIntelAMDTested=$false;nativeAppBinaryChanged=$false;shippingZIPChanged=$false}
 $output=$ReportPath
 $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding UTF8
 Write-Output ('PASSED='+$passed+' FAILED='+$failed)
 if($failed -gt 0){exit 1}
} finally {if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
