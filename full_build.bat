@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo  MerkaERP 1.3.0+8 - Full Build
echo ============================================

echo [1/4] flutter clean...
call flutter clean
if errorlevel 1 ( echo FALLO en flutter clean & exit /b 1 )
echo OK - clean completado

echo [2/4] flutter pub get...
call flutter pub get
if errorlevel 1 ( echo FALLO en pub get & exit /b 1 )
echo OK - pub get completado

echo [3/4] flutter analyze...
call flutter analyze --no-fatal-warnings --no-fatal-infos
if errorlevel 1 ( echo FALLO en analyze & exit /b 1 )
echo OK - analyze sin errores fatales

echo [4/4] flutter build windows --release...
call flutter build windows --release
if errorlevel 1 ( echo FALLO en build & exit /b 1 )

echo Copiando sqlite3.dll a Release...
if exist "build\native_assets\windows\sqlite3.dll" (
  copy /Y "build\native_assets\windows\sqlite3.dll" "build\windows\x64\runner\Release\sqlite3.dll"
  echo OK - sqlite3.dll copiada
) else (
  echo AVISO - sqlite3.dll no encontrada en native_assets, puede que no sea necesaria
)

echo ============================================
echo  BUILD COMPLETADO EXITOSAMENTE
echo ============================================
echo  Ejecutable: build\windows\x64\runner\Release\MerkaERP.exe
echo ============================================

endlocal
