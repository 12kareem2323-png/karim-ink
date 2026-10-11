param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\publish'))
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '..\KarimEldamatyWindows.csproj'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Install the .NET 10 SDK to build the editable project. The prepared portable app does not need the SDK.' }
& dotnet publish $project -c Release -r win-x64 --self-contained true -o $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }
Write-Host "Windows x64 app published to $OutputDirectory"
