# Liberación de MerkaERP 1.2.1+7

## Build verificable

Desde PowerShell en la raíz:

```powershell
.\scripts\build_release.ps1 -Target windows
```

La puerta de liberación ejecuta, en ese orden:

1. `flutter clean`
2. `flutter pub get`
3. `flutter analyze --no-fatal-warnings --no-fatal-infos`
4. `flutter test`
5. `flutter build windows --release`

Si el analyzer reporta errores de compilación/análisis o si `test` falla, no se genera una liberación considerada válida. Warnings e infos se muestran para saneamiento progresivo, pero no bloquean un build de prueba.

## Instalador Windows

Instale Inno Setup 6 y ejecute:

```powershell
.\scripts\package_windows.ps1
```

o `package_windows.bat`.

El empaquetador vuelve a pasar el release gate, crea el instalador, calcula SHA-256 y genera evidencia en `build/release/`.

### Firma opcional

La firma nunca se simula. Puede usar un certificado del almacén de Windows:

```powershell
.\scripts\package_windows.ps1 -SigningThumbprint "HUELLA_SHA1"
```

O un PFX. La contraseña debe ir en la variable de entorno `MERKA_SIGNING_PASSWORD`, nunca en el repositorio:

```powershell
$env:MERKA_SIGNING_PASSWORD = "..."
.\scripts\package_windows.ps1 -PfxPath "C:\ruta\certificado.pfx"
```

Use `-PrivacyReviewed` únicamente cuando la revisión de privacidad de esa liberación haya sido realizada.

## Datos del cliente

El desinstalador **no elimina** bases, documentos, respaldos ni AppData. Una eliminación de datos debe ser una acción separada, explícita y precedida por respaldo.
