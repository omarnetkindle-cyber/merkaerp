param(
  [ValidateSet('windows','apk','appbundle')]
  [string]$Target = 'windows',
  [switch]$ProductionSignature,
  [switch]$PrivacyReviewed
)

$ErrorActionPreference = 'Stop'

function Run-Flutter {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
  Write-Host "`n> flutter $($Arguments -join ' ')" -ForegroundColor Cyan
  & flutter @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter terminó con código $LASTEXITCODE"
  }
}

function Import-AndroidSigningProperties {
  $propertiesPath = Join-Path $PSScriptRoot '..\android\key.properties'
  if (-not (Test-Path $propertiesPath)) {
    return
  }

  Write-Host "Cargando firma Android local desde android\key.properties" -ForegroundColor Cyan
  Get-Content $propertiesPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      return
    }

    $parts = $line -split '=', 2
    if ($parts.Length -ne 2) {
      return
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ($key -and $value -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key, 'Process'))) {
      [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
  }
}

Write-Host 'MerkaERP 1.3.0+8 - Release gate' -ForegroundColor Green
Run-Flutter clean
Run-Flutter pub get
Run-Flutter analyze
Run-Flutter test

$defines = @(
  '--dart-define=MERKA_ANALYZER_CLEAN=true',
  '--dart-define=MERKA_TESTS_PASSING=true',
  '--dart-define=MERKA_VERSION_INCREMENTED=true',
  "--dart-define=MERKA_PRODUCTION_SIGNATURE=$($ProductionSignature.IsPresent.ToString().ToLower())",
  "--dart-define=MERKA_PRIVACY_REVIEWED=$($PrivacyReviewed.IsPresent.ToString().ToLower())"
)

if ($Target -in @('apk', 'appbundle')) {
  Import-AndroidSigningProperties
}

switch ($Target) {
  'windows'   { Run-Flutter build windows --release @defines }
  'apk'       { Run-Flutter build apk --release @defines }
  'appbundle' { Run-Flutter build appbundle --release @defines }
}

Write-Host "`nRelease build completado. Analyzer sin errores fatales y pruebas pasaron en esta ejecución." -ForegroundColor Green
if (-not $ProductionSignature) {
  Write-Host 'Advertencia: MERKA_PRODUCTION_SIGNATURE quedó false. Use -ProductionSignature solo cuando el artefacto/instalador esté realmente firmado.' -ForegroundColor Yellow
}
if (-not $PrivacyReviewed) {
  Write-Host 'Advertencia: MERKA_PRIVACY_REVIEWED quedó false. Use -PrivacyReviewed únicamente después de la revisión correspondiente.' -ForegroundColor Yellow
}
