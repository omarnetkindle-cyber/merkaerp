param(
  [string]$Alias = 'merka_release',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function New-Password {
  $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
  -join (1..40 | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$keystoreDir = Join-Path $projectRoot 'android\keystores'
$keystorePath = Join-Path $keystoreDir 'merka-release.jks'
$propertiesPath = Join-Path $projectRoot 'android\key.properties'

if ((Test-Path $keystorePath) -and -not $Force) {
  Write-Host "La keystore Android ya existe: $keystorePath" -ForegroundColor Yellow
  Write-Host 'Use -Force solo si realmente quiere reemplazarla; cambiar la firma rompe actualizaciones sobre instalaciones anteriores.' -ForegroundColor Yellow
  exit 0
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
$keytoolPath = if ($keytool) { $keytool.Source } else { $null }
if (-not $keytoolPath) {
  $androidStudioKeytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
  if (Test-Path $androidStudioKeytool) {
    $keytoolPath = $androidStudioKeytool
  }
}

if (-not $keytoolPath) {
  throw 'No se encontró keytool. Instale/active JDK 17 o Android Studio y vuelva a ejecutar este script.'
}

New-Item -ItemType Directory -Path $keystoreDir -Force | Out-Null

$storePassword = New-Password
$keyPassword = $storePassword

& $keytoolPath `
  -genkeypair `
  -v `
  -keystore $keystorePath `
  -alias $Alias `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -storepass $storePassword `
  -keypass $keyPassword `
  -dname 'CN=MerkaERP, OU=MerkaERP, O=MerkaERP, L=Bogota, ST=Bogota, C=CO'

if ($LASTEXITCODE -ne 0) {
  throw "keytool terminó con código $LASTEXITCODE"
}

$escapedStorePath = $keystorePath -replace '\\', '/'
@(
  '# Archivo local generado por scripts/init_android_signing.ps1.'
  '# No subir a Git: contiene credenciales de firma Android.'
  "MERKA_RELEASE_STORE_FILE=$escapedStorePath"
  "MERKA_RELEASE_KEY_ALIAS=$Alias"
  "MERKA_RELEASE_STORE_PASSWORD=$storePassword"
  "MERKA_RELEASE_KEY_PASSWORD=$keyPassword"
) | Set-Content -Path $propertiesPath -Encoding UTF8

Write-Host 'Keystore Android creada correctamente.' -ForegroundColor Green
Write-Host "Keystore: $keystorePath"
Write-Host "Propiedades locales: $propertiesPath"
Write-Host 'Guarde una copia segura de ambos archivos; sin ellos no podrá actualizar el APK firmado con esta identidad.' -ForegroundColor Yellow
