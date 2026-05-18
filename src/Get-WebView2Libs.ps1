#Requires -Version 5.1
# Einmalig ausfuehren: laedt WebView2 NuGet-Paket und kopiert DLLs nach src/lib/

$LibDir   = Join-Path $PSScriptRoot "lib"
$TmpPkg   = Join-Path $env:TEMP "WebView2.nupkg"
$TmpExtr  = Join-Path $env:TEMP "WebView2Extract"

if (-not (Test-Path $LibDir)) { New-Item -ItemType Directory -Path $LibDir | Out-Null }

Write-Host "Lade WebView2 NuGet-Paket herunter..."
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2" `
                  -OutFile $TmpPkg -UseBasicParsing

Write-Host "Entpacke..."
if (Test-Path $TmpExtr) { Remove-Item $TmpExtr -Recurse -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($TmpPkg, $TmpExtr)

$SrcLib  = Join-Path $TmpExtr "lib\net45"
$Arch    = if ([System.Environment]::Is64BitOperatingSystem) { "win-x64" } else { "win-x86" }
$SrcNat  = Join-Path $TmpExtr "runtimes\$Arch\native"

Copy-Item (Join-Path $SrcLib "Microsoft.Web.WebView2.Core.dll") $LibDir -Force
Copy-Item (Join-Path $SrcLib "Microsoft.Web.WebView2.Wpf.dll")  $LibDir -Force
Copy-Item (Join-Path $SrcNat "WebView2Loader.dll")              $LibDir -Force

Remove-Item $TmpPkg  -Force
Remove-Item $TmpExtr -Recurse -Force

Write-Host "Fertig! DLLs liegen in: $LibDir" -ForegroundColor Green
