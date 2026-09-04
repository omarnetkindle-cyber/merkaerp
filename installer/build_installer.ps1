# Compatibilidad: la ruta canónica de empaquetado está en scripts/package_windows.ps1.
$Root = Split-Path -Parent $PSScriptRoot
& "$Root\scripts\package_windows.ps1" @args
exit $LASTEXITCODE
