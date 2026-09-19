@echo off
rem ============================================================================
rem  uninstall.bat - Hapus agen client warnet (double-click, minta izin admin).
rem ============================================================================
title Warnet Billing Client - Uninstall

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Membuka UAC untuk izin Administrator...
  powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0uninstall.ps1\"' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause