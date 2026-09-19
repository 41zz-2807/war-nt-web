@echo off
rem ============================================================================
rem  install-silent.bat - Instalasi senyap agen client warnet (double-click).
rem  Otomatis meminta izin admin (UAC) lalu menjalankan install-silent.ps1.
rem ============================================================================
title Warnet Billing Client - Silent Installer

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Membuka UAC untuk izin Administrator...
  powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0install-silent.ps1\"' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-silent.ps1"
echo.
pause