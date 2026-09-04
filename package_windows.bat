@echo off
setlocal
cd /d "%~dp0"
echo MerkaERP 1.2.1+7 - Build + instalador Windows
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\package_windows.ps1"
if errorlevel 1 (
  echo.
  echo EMPAQUETADO FALLIDO. Revise el detalle arriba.
  exit /b 1
)
echo.
echo INSTALADOR COMPLETADO.
endlocal
