# ============================================================================
#  uninstall.ps1 - Hapus agen client warnet (balikkan install-silent.ps1).
#  Dipanggil oleh uninstall.bat. HARUS Administrator.
#
#  Verifikasi OTP (pilihan): sebelum menghapus, minta kode OTP yang dikirim
#  server ke Telegram admin. Bila Telegram server belum dikonfigurasi, atau
#  server tidak terjangkau, uninstall tetap bisa dilanjutkan (mode dev).
# ============================================================================
$ErrorActionPreference = "Continue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Jalankan sebagai Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  WARNET BILLING CLIENT - UNINSTALL" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- [OTP] ambil ServerUrl & PCName dari config terinstal -------------------
$appDir  = Join-Path $env:ProgramFiles "WarnetBillingClient"
$cfgPath = Join-Path $appDir "client-net.dll.config"
$serverUrl = $null
$pcName    = $env:COMPUTERNAME

if (Test-Path $cfgPath) {
    try {
        [xml]$cfg = Get-Content $cfgPath
        foreach ($add in $cfg.configuration.appSettings.add) {
            if ($add.key -eq 'ServerUrl') { $serverUrl = $add.value }
            if ($add.key -eq 'PcId')      { $pcName    = $add.value }
        }
    } catch {
        Write-Host "[OTP] config tidak terbaca: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- [OTP] verifikasi ke server --------------------------------------------
if ($serverUrl) {
    $api = $serverUrl -replace '^wss?://([^/]+)/.*$', 'http://$1'
    Write-Host "[OTP] Server: $api" -ForegroundColor DarkGray
    try {
        $st = Invoke-RestMethod -Uri ($api + '/api/otp/status') -Method Get -TimeoutSec 10
        if ($st.enabled) {
            $null = Invoke-RestMethod -Uri ($api + '/api/otp/request') -Method Post `
                -ContentType 'application/json' `
                -Body (@{ pc_name = $pcName; purpose = 'uninstall' } | ConvertTo-Json) `
                -TimeoutSec 15
            Write-Host ""
            Write-Host "[OTP] Kode OTP telah dikirim ke Telegram admin/operator." -ForegroundColor Yellow
            $otp = Read-Host "Masukkan kode OTP (6 digit) dari Telegram"
            try {
                $v = Invoke-RestMethod -Uri ($api + '/api/otp/verify') -Method Post `
                    -ContentType 'application/json' `
                    -Body (@{ pc_name = $pcName; purpose = 'uninstall'; code = $otp } | ConvertTo-Json) `
                    -TimeoutSec 15
            } catch {
                $v = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message | ConvertFrom-Json } else { @{ ok = $false } }
            }
            if (-not $v.ok) {
                Write-Host "[OTP] GAGAL: $($v.message) — uninstall dibatalkan." -ForegroundColor Red
                exit 1
            }
            Write-Host "[OTP] OTP valid. Melanjutkan uninstall..." -ForegroundColor Green
        } else {
            Write-Host "[OTP] Telegram belum dikonfigurasi server — lanjut tanpa OTP (dev)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host ""
        Write-Host "[OTP] Server tidak terjangkau ($api)." -ForegroundColor Yellow
        $yes = Read-Host "Lanjut uninstall tanpa OTP? (y/N)"
        if ($yes -notmatch '^y') { Write-Host "Dibatalkan." -ForegroundColor Yellow; exit 1 }
    }
} else {
    Write-Host "[WARN] ServerUrl tidak terbaca dari config — lanjut tanpa OTP." -ForegroundColor Yellow
}

# 1. Hentikan proses agen
Write-Host "[1/4] Menghentikan proses client-net ..." -ForegroundColor Yellow
Get-Process -Name "client-net" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 2. Hapus Scheduled Task
Write-Host "[2/4] Menghapus Scheduled Task 'WarnetBillingClient' ..." -ForegroundColor Yellow
& schtasks /Delete /F /TN "WarnetBillingClient" | Out-Null

# 3. Pulihkan registry hardening (set ke 0 / hapus nilai)
Write-Host "[3/4] Memulihkan registry hardening ..." -ForegroundColor Yellow
$base = "Software\Microsoft\Windows\CurrentVersion\Policies"
$names = @{
    "$base\System" = @("DisableTaskMgr", "DisableRegistryTools", "DisableCMD")
    "$base"        = @("NoRun")
}
foreach ($subKey in $names.Keys) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey, $true)
    if ($k) {
        foreach ($n in $names[$subKey]) {
            $k.DeleteValue($n, $false) | Out-Null
            Write-Host ("       dihapus HKCU:\" + $subKey + "\" + $n)
        }
        $k.Close()
    }
}

# 4. Hapus folder instalasi
Write-Host "[4/4] Menghapus folder instalasi ..." -ForegroundColor Yellow
$appDir = Join-Path $env:ProgramFiles "WarnetBillingClient"
if (Test-Path $appDir) {
    Remove-Item $appDir -Recurse -Force
    Write-Host ("       dihapus " + $appDir)
}

Write-Host ""
Write-Host "[DONE] Uninstall selesai. Registry hardening sudah dipulihkan." -ForegroundColor Green