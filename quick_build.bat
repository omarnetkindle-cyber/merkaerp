@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo  MerkaERP 1.3.0+8 - Quick Build (no tests)
echo ============================================
echo.

echo [1/3] flutter pub get...
call flutter pub get
if errorlevel 1 (
  echo FALLO en pub get.
  exit /b 1
)
echo OK - pub get completado.
echo.

echo [2/3] flutter analyze (no fatal warnings/infos)...
call flutter analyze --no-fatal-warnings --no-fatal-infos
if errorlevel 1 (
  echo FALLO en analyze - hay errores reales de compilacion.
  exit /b 1
)
echo OK - analyze sin errores fatales.
echo.

echo [3/3] flutter build windows --release...
call flutter build windows --release
if errorlevel 1 (
  echo FALLO en build.
  exit /b 1
)
echo.
echo ============================================
echo  BUILD COMPLETADO EXITOSAMENTE
echo ============================================
echo  Ejecutable: build\windows\x64\runner\Release\MerkaERP.exe
echo ============================================

endlocal
