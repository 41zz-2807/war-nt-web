# ============================================================================
#  uninstall.ps1 - Hapus agen client warnet (balikkan install-silent.ps1).
#  Dipanggil oleh uninstall.bat. HARUS Administrator.
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