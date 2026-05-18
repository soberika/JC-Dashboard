#Requires -Version 5.1
# Einmalig ausfuehren: laedt WebView2 NuGet-Paket und kopiert DLLs nach src/lib/

$LibDir  = Join-Path $PSScriptRoot "lib"
$TmpPkg  = Join-Path $env:TEMP "WebView2.nupkg"
$TmpExtr = Join-Path $env:TEMP "WebView2Extract"

if (-not (Test-Path $LibDir)) { New-Item -ItemType Directory -Path $LibDir | Out-Null }

Write-Host "Lade WebView2 NuGet-Paket herunter..."
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2" `
                  -OutFile $TmpPkg -UseBasicParsing

Write-Host "Entpacke..."
if (Test-Path $TmpExtr) { Remove-Item $TmpExtr -Recurse -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($TmpPkg, $TmpExtr)

# DLL-Pfade dynamisch ermitteln (Framework-Ordner kann variieren: net45, netcoreapp3.0 usw.)
$CoreDll = Get-ChildItem -Path $TmpExtr -Recurse -Filter "Microsoft.Web.WebView2.Core.dll" |
           Where-Object { $_.FullName -notmatch "\\ref\\" } | Select-Object -First 1
$WpfDll  = Get-ChildItem -Path $TmpExtr -Recurse -Filter "Microsoft.Web.WebView2.Wpf.dll"  |
           Where-Object { $_.FullName -notmatch "\\ref\\" } | Select-Object -First 1

if (-not $CoreDll) { Write-Error "Microsoft.Web.WebView2.Core.dll nicht im Paket gefunden."; exit 1 }
if (-not $WpfDll)  { Write-Error "Microsoft.Web.WebView2.Wpf.dll nicht im Paket gefunden.";  exit 1 }

$Arch    = if ([System.Environment]::Is64BitOperatingSystem) { "win-x64" } else { "win-x86" }
$Loader  = Get-ChildItem -Path (Join-Path $TmpExtr "runtimes\$Arch") -Recurse -Filter "WebView2Loader.dll" |
           Select-Object -First 1

if (-not $Loader) { Write-Error "WebView2Loader.dll fuer $Arch nicht im Paket gefunden."; exit 1 }

Copy-Item $CoreDll.FullName $LibDir -Force
Copy-Item $WpfDll.FullName  $LibDir -Force
Copy-Item $Loader.FullName  $LibDir -Force

Remove-Item $TmpPkg  -Force
Remove-Item $TmpExtr -Recurse -Force

Write-Host "Fertig! DLLs liegen in: $LibDir" -ForegroundColor Green
