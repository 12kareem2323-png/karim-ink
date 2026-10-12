# Draft preparation helper. It does not sign, install, submit, download or change policy.
# Run only after entering exact Store identity values in IDENTITY-INPUTS.json.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$IdentityFile,
    [string]$OutputName = 'SketchGlide-Store-Draft',
    [switch]$Pack,
    [string]$MakeAppxPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VerifiedIdentity {
    param([string]$File)
    $identity = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    foreach ($field in @('PackageIdentityName','PublisherDistinguishedName',
                        'PublisherDisplayName','ReservedDisplayName','StorePackageVersion')) {
        $property = $identity.PSObject.Properties[$field]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "Missing exact Partner Center input: $field. No staging was created."
        }
        $value = [string]$property.Value
        if ($value -match '__|<|>|REPLACE|PLACEHOLDER' -or $value -ne $value.Trim()) {
            throw "Placeholder or surrounding whitespace is not allowed in $field."
        }
    }
    if ([string]$identity.PackageIdentityName -notmatch '^[A-Za-z0-9.-]{3,50}$') {
        throw 'PackageIdentityName must match the Store-assigned manifest name.'
    }
    if ([string]$identity.PublisherDistinguishedName -notmatch '^CN=') {
        throw 'PublisherDistinguishedName must be the exact CN=... value from Product identity.'
    }
    $version = [string]$identity.StorePackageVersion
    if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)\.0$') {
        throw 'StorePackageVersion requires four integer parts; the fourth must be 0.'
    }
    $parts = $version.Split('.') | ForEach-Object { [long]$_ }
    if ($parts[0] -lt 1 -or @($parts | Where-Object { $_ -gt 65535 }).Count -gt 0) {
        throw 'Store version first component must be 1..65535; other components must be 0..65535.'
    }
    return $identity
}

function Get-SafeArchiveEntries {
    param([System.IO.Compression.ZipArchive]$Archive)
    $prefix = 'SketchGlide-0.2.0-Windows-x64-Test/'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Archive.Entries) {
        if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal)) {
            throw 'Archive entry is outside the expected release root.'
        }
        $relative = $entry.FullName.Substring($prefix.Length)
        if ([string]::IsNullOrEmpty($relative)) { continue }
        if ($relative.Contains('\') -or $relative.Contains(':') -or $relative.StartsWith('/')) {
            throw "Unsafe archive path: $relative"
        }
        $segments = $relative.TrimEnd('/').Split('/')
        if (@($segments | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count -gt 0) {
            throw "Unsafe archive path: $relative"
        }
        if (-not $seen.Add($relative.TrimEnd('/'))) { throw "Duplicate archive path: $relative" }
        [pscustomobject]@{ Entry=$entry; Relative=$relative; IsDirectory=$relative.EndsWith('/') }
    }
}

function New-ResolvedManifest {
    param([string]$Template, [psobject]$Identity)
    $replacements = @{
        '__PACKAGE_IDENTITY_NAME__'=[string]$Identity.PackageIdentityName
        '__PUBLISHER_DN__'=[string]$Identity.PublisherDistinguishedName
        '__PUBLISHER_DISPLAY_NAME__'=[string]$Identity.PublisherDisplayName
        '__RESERVED_DISPLAY_NAME__'=[string]$Identity.ReservedDisplayName
        '__STORE_PACKAGE_VERSION__'=[string]$Identity.StorePackageVersion
    }
    foreach ($token in $replacements.Keys) {
        $Template = $Template.Replace($token, [Security.SecurityElement]::Escape($replacements[$token]))
    }
    if ($Template -match '__[A-Z_]+__') { throw 'Unresolved manifest placeholder.' }
    $readerSettings = [Xml.XmlReaderSettings]::new()
    $readerSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($Template), $readerSettings)
    try { while($reader.Read()) {} } finally { $reader.Dispose() }
    return $Template
}

# All mutations are confined to a new child of this kit's Prepared folder.
$identity = Get-VerifiedIdentity -File $IdentityFile
if ($OutputName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,70}$' -or $OutputName -in @('.','..')) {
    throw 'OutputName must be a plain folder name, not a path.'
}
$kit = [IO.Path]::GetFullPath($PSScriptRoot)
$archivePath = Join-Path $kit 'Inputs\SketchGlide-0.2.0-Windows-x64-Test.zip'
$expectedSha = 'ed275d81fd370d5d3dcd873350e736f0438880d04bddf9c1fdf4fb50e9eda018'
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSha) {
    throw 'The existing release ZIP checksum does not match. No staging was created.'
}
$manifest = New-ResolvedManifest -Template (Get-Content -LiteralPath (Join-Path $kit 'AppxManifest.xml.template') -Raw) -Identity $identity
$makeAppx = $null
if ($Pack) {
    if ([string]::IsNullOrWhiteSpace($MakeAppxPath)) {
        throw 'For -Pack, pass an existing Windows SDK MakeAppx.exe path. This helper never installs an SDK.'
    }
    $makeAppx = (Get-Item -LiteralPath $MakeAppxPath).FullName
    if ([IO.Path]::GetFileName($makeAppx) -ine 'MakeAppx.exe') { throw 'Expected Windows SDK MakeAppx.exe.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $makeAppx
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'MakeAppx.exe must have a valid Microsoft Authenticode signature.'
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = @(Get-SafeArchiveEntries -Archive $zip)
    foreach ($required in @('SketchGlide.exe','SketchGlide.dll','SketchGlide.deps.json',
                           'SketchGlide.runtimeconfig.json','coreclr.dll','hostfxr.dll','hostpolicy.dll',
                           'LICENSE','THIRD-PARTY-NOTICES.md','Resources/Licenses/LICENSE-DotNet.txt',
                           'Resources/Licenses/NOTICE-DotNet.txt')) {
        if (@($entries | Where-Object { $_.Relative -ceq $required -and -not $_.IsDirectory }).Count -ne 1) {
            throw "Release missing required payload: $required"
        }
    }
    $prepared = Join-Path $kit 'Prepared'
    $output = Join-Path $prepared $OutputName
    if (Test-Path -LiteralPath $output) { throw 'Output already exists. Choose a new OutputName; no overwrite is performed.' }
    [IO.Directory]::CreateDirectory($prepared) | Out-Null
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $payload = Join-Path $output 'Payload'
    $app = Join-Path $payload 'App'
    [IO.Directory]::CreateDirectory($app) | Out-Null
    $appPrefix = [IO.Path]::GetFullPath($app) + [IO.Path]::DirectorySeparatorChar
    foreach ($item in $entries) {
        $target = [IO.Path]::GetFullPath((Join-Path $app ($item.Relative.Replace('/',[IO.Path]::DirectorySeparatorChar))))
        if (-not $target.StartsWith($appPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Extraction escaped draft App directory.' }
        if ($item.IsDirectory) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($item.Entry,$target,$false)
    }
    Copy-Item -LiteralPath (Join-Path $kit 'Assets') -Destination $payload -Recurse
    [IO.File]::WriteAllText((Join-Path $payload 'AppxManifest.xml'),$manifest,[Text.UTF8Encoding]::new($false))
    $receipt = [ordered]@{
        status='Prepared only - not installed, signed, certified or submitted'
        shippingArchiveSha256=$expectedSha
        nativeVersion='0.2 Test'
        storePackageVersion=[string]$identity.StorePackageVersion
        storeIdentityName=[string]$identity.PackageIdentityName
        filesExtracted=@($entries | Where-Object { -not $_.IsDirectory }).Count
        restrictedCapabilities=@('runFullTrust','unvirtualizedResources')
        sdkSemanticValidation=$false
        packagedRuntimeTest=$false
    }
    $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'preparation-receipt.json') -Encoding UTF8
    if ($Pack) {
        $packagePath = Join-Path $output 'SketchGlide-Store-Draft-x64.msix'
        # Default MakeAppx semantic checks are enabled; they do not replace install/WACK tests.
        & $makeAppx pack /d $payload /p $packagePath /h SHA256 /no
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath)) { throw 'MakeAppx validation/pack failed. Review the draft; do not submit.' }
        $receipt.status = 'MSIX created - not signed, installed, WACK-certified or submitted'
        $receipt.sdkSemanticValidation = $true
        $receipt.msixSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'preparation-receipt.json') -Encoding UTF8
    }
    Write-Output $output
} finally { $zip.Dispose() }
