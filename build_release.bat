@echo off
setlocal
cd /d "%~dp0"
echo MerkaERP 1.3.0+8 - Release gate
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\build_release.ps1" -Target windows
if errorlevel 1 (
  echo.
  echo BUILD RELEASE FALLIDO. Revise analyzer/tests/build arriba.
  exit /b 1
)
echo.
echo BUILD RELEASE COMPLETADO.
endlocal
