param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $Root 'windows/PocketPaws.Windows/PocketPaws.Windows.csproj'
$Output = Join-Path $Root "dist/windows/$Runtime"
$Archive = Join-Path $Root "dist/Pocket-Paws-Windows-$Runtime.zip"

dotnet publish $Project -c Release -r $Runtime --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false -o $Output
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }

Copy-Item (Join-Path $Root 'LICENSE') (Join-Path $Output 'LICENSE.txt') -Force
Copy-Item (Join-Path $Root 'docs/WINDOWS.md') (Join-Path $Output 'README.txt') -Force
$Files = @('PocketPaws.exe', 'LICENSE.txt', 'README.txt') | ForEach-Object { Join-Path $Output $_ }
Compress-Archive -Path $Files -DestinationPath $Archive -Force
$Hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  $(Split-Path $Archive -Leaf)" | Set-Content "$Archive.sha256" -Encoding ascii
Write-Host "Built: $Archive"
