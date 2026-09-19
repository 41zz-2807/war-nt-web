# ============================================================================
#  build-windows.ps1 - Bangun agen client Windows (.NET 8) ke folder Release
#
#  Cara pakai:
#    powershell -ExecutionPolicy Bypass -File build-windows.ps1
#
#  Hasil:
#    installer\Release\client-net.exe
#    installer\Release\client-net.dll.config  (konfigurasi ServerUrl/Token)
# ============================================================================
param(
    [string]$Configuration = "Release",
    [string]$Runtime       = "win-x64",
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"

function Test-Dotnet {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "[ERROR] dotnet SDK tidak ditemukan di PATH." -ForegroundColor Red
        Write-Host "        Install .NET 8 SDK dulu: https://dotnet.microsoft.com/download" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    $ver = (dotnet --version).Trim()
    Write-Host ("[dotnet] SDK terdeteksi: " + $ver) -ForegroundColor Cyan
}

Test-Dotnet

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$proj = Join-Path $root "client-net.csproj"
$out  = Join-Path $PSScriptRoot "Release"

if (-not (Test-Path $proj)) {
    Write-Host "[ERROR] file proyek tidak ditemukan: $proj" -ForegroundColor Red
    exit 1
}

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

Write-Host ("[build] publish -> " + $out) -ForegroundColor Yellow

$argsPublish = @(
    "publish", $proj,
    "-c", $Configuration,
    "-r", $Runtime,
    "-o", $out,
    "-v", "minimal",
    "-p:PublishSingleFile=false",
    "-p:DebugType=none"
)
if ($SelfContained) { $argsPublish += "--self-contained"; $argsPublish += "true" }

& dotnet @argsPublish
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] dotnet publish gagal (kode $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

# Verifikasi hasil sesuai ekspektasi
$exe    = Join-Path $out "client-net.exe"
$config = Join-Path $out "client-net.dll.config"
$ok = $true
if (-not (Test-Path $exe))    { Write-Host "[ERROR] client-net.exe tidak ada." -ForegroundColor Red; $ok = $false }
if (-not (Test-Path $config)) { Write-Host "[ERROR] client-net.dll.config tidak ada." -ForegroundColor Red; $ok = $false }
if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "[DONE] Build berhasil." -ForegroundColor Green
Write-Host ("      exe    : " + $exe)
Write-Host ("      config : " + $config)
Write-Host ""
Write-Host "Langkah berikutnya:" -ForegroundColor Yellow
Write-Host "  1. Edit install.config (isi ServerUrl + Token PC dari dashboard kasir)."
Write-Host "  2. Jalankan install-silent.bat  ATAU  WarnetClientSetup.exe (Inno Setup)."