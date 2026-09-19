# ============================================================================
#  install-silent.ps1 - Instalasi senyap (tanpa GUI) agen client warnet
#  Dipanggil oleh install-silent.bat. HARUS dijalankan sebagai Administrator.
#
#  Proses:
#    1. Baca konfigurasi dari install.config
#    2. Salin hasil build (folder Release) ke Program Files\WarnetBillingClient
#    3. Tulis client-net.dll.config (ServerUrl + Token + PcId)
#    4. Daftarkan Scheduled Task saat login + registry hardening
#    5. Jalankan agen langsung
# ============================================================================
$ErrorActionPreference = "Stop"

# --- cek admin --------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Jalankan sebagai Administrator." -ForegroundColor Red
    exit 1
}

$here     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$cfgPath  = Join-Path $here "install.config"
$release  = Join-Path $here "Release"
$appDir   = Join-Path $env:ProgramFiles "WarnetBillingClient"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  WARNET BILLING CLIENT - SILENT INSTALL" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- baca install.config ----------------------------------------------------
if (-not (Test-Path $cfgPath)) {
    Write-Host "[ERROR] install.config tidak ditemukan." -ForegroundColor Red
    Write-Host "        Salin install.config.example -> install.config lalu isi." -ForegroundColor Yellow
    exit 1
}
$cfg = @{}
Get-Content $cfgPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $k, $v = $line -split "=", 2
        $cfg[($k.Trim())] = $v.Trim()
    }
}

$serverUrl = $cfg["ServerUrl"]
$token     = $cfg["Token"]
$pcName    = if ($cfg["PCName"]) { $cfg["PCName"] } else { $env:COMPUTERNAME }

if (-not $serverUrl) {
    Write-Host "[ERROR] ServerUrl kosong di install.config." -ForegroundColor Red
    exit 1
}
if (-not $token -or $token -match "GANTI") {
    Write-Host "[ERROR] Token belum diisi. Ambil dari dashboard kasir." -ForegroundColor Red
    exit 1
}

# --- cek hasil build --------------------------------------------------------
if (-not (Test-Path (Join-Path $release "client-net.exe"))) {
    Write-Host "[ERROR] Folder Release kosong. Jalankan build-windows.ps1 dulu." -ForegroundColor Red
    exit 1
}

# --- salin ke Program Files -------------------------------------------------
Write-Host "[1/5] Menyalin ke $appDir ..." -ForegroundColor Yellow
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
New-Item -ItemType Directory -Path $appDir | Out-Null
Copy-Item (Join-Path $release "*") $appDir -Recurse -Force
Copy-Item (Join-Path $here "run-hidden.vbs") $appDir -Force

# --- tulis client-net.dll.config --------------------------------------------
Write-Host "[2/5] Menulis client-net.dll.config ..." -ForegroundColor Yellow
$configPath = Join-Path $appDir "client-net.dll.config"
$xml = @"
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <startup>
    <supportedRuntime version="v8.0" sku=".NETFramework,Version=v8.0" />
  </startup>
  <appSettings>
    <add key="ServerUrl" value="$serverUrl" />
    <add key="PcId" value="$pcName" />
    <add key="Token" value="$token" />
    <add key="HeartbeatInterval" value="20" />
    <add key="IdleTimeoutMinutes" value="5" />
  </appSettings>
</configuration>
"@
[System.IO.File]::WriteAllText($configPath, $xml, (New-Object System.Text.UTF8Encoding($false)))

# --- Scheduled Task saat login ----------------------------------------------
Write-Host "[3/5] Mendaftarkan Scheduled Task 'WarnetBillingClient' ..." -ForegroundColor Yellow
$vbsPath = Join-Path $appDir "run-hidden.vbs"
& schtasks /Create /F /TN "WarnetBillingClient" /SC ONLOGON /RL LIMITED /TR ('"' + $vbsPath + '"') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] Gagal membuat Scheduled Task. Cek error di atas." -ForegroundColor Yellow
}

# --- registry hardening user sekarang ----------------------------------------
Write-Host "[4/5] Menerapkan registry hardening ..." -ForegroundColor Yellow
$base = "Software\Microsoft\Windows\CurrentVersion\Policies"
$values = @{
    "$base\System\DisableTaskMgr"       = 1
    "$base\NoRun"                       = 1
    "$base\System\DisableRegistryTools" = 1
    "$base\System\DisableCMD"           = 1
}
foreach ($entry in $values.GetEnumerator()) {
    try {
        $parts  = $entry.Key -split "\\"
        $name   = $parts[-1]
        $subKey = $parts[0..($parts.Length - 2)] -join "\"
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
        try { $k.SetValue($name, $entry.Value, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() }
        Write-Host ("       HKCU:\" + $entry.Key + " = " + $entry.Value)
    } catch {
        Write-Host ("[WARN] gagal set " + $entry.Key + " : " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# --- jalankan agen sekarang --------------------------------------------------
Write-Host "[5/5] Menjalankan agen ..." -ForegroundColor Yellow
$exePath = Join-Path $appDir "client-net.exe"
Start-Process -FilePath $exePath -WindowStyle Hidden

Write-Host ""
Write-Host "[DONE] Instalasi selesai. Agen berjalan tersembunyi & aktif setiap login." -ForegroundColor Green
Write-Host "Cek dashboard kasir: PC ini harus tampil ONLINE (hijau)." -ForegroundColor Yellow
Write-Host ("Lokasi: " + $appDir)