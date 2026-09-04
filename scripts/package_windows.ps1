param(
  [string]$Publisher = 'MerkaERP',
  [string]$SigningThumbprint = '',
  [string]$PfxPath = '',
  [string]$TimestampUrl = 'http://timestamp.digicert.com',
  [switch]$PrivacyReviewed,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Version = '1.3.0'
$Build = 8
$DisplayVersion = "$Version+$Build"
$ReleaseDir = Join-Path $Root 'build\release'
$WindowsDir = Join-Path $Root 'build\windows\x64\runner\Release'
$Exe = Join-Path $WindowsDir 'MerkaERP.exe'
$Installer = Join-Path $Root "build\installer\MerkaERP-Setup-$Version.exe"

function Resolve-Tool([string[]]$Candidates, [string]$CommandName) {
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Sign-File([string]$Path, [string]$SignTool) {
  if (-not (Test-Path $Path)) { throw "No existe el archivo a firmar: $Path" }
  if ($SigningThumbprint) {
    & $SignTool sign /sha1 $SigningThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $Path
  } elseif ($PfxPath) {
    if (-not (Test-Path $PfxPath)) { throw "No existe el PFX indicado." }
    $password = $env:MERKA_SIGNING_PASSWORD
    if (-not $password) { throw 'Para PFX configure MERKA_SIGNING_PASSWORD en el entorno. No escriba la contraseña dentro del repositorio.' }
    & $SignTool sign /f $PfxPath /p $password /fd SHA256 /tr $TimestampUrl /td SHA256 $Path
  } else {
    return
  }
  if ($LASTEXITCODE -ne 0) { throw "Falló la firma de $Path" }
  & $SignTool verify /pa /v $Path
  if ($LASTEXITCODE -ne 0) { throw "La firma no pudo verificarse: $Path" }
}

function Copy-NativeRuntimeAssets {
  $SqliteDll = Join-Path $Root 'build\native_assets\windows\sqlite3.dll'
  if (Test-Path $SqliteDll) {
    Copy-Item -LiteralPath $SqliteDll -Destination (Join-Path $WindowsDir 'sqlite3.dll') -Force
  }
}

Push-Location $Root
try {
  $SigningRequested = [bool]($SigningThumbprint -or $PfxPath)
  if (-not $SkipBuild) {
    & "$Root\scripts\build_release.ps1" -Target windows -ProductionSignature:$SigningRequested -PrivacyReviewed:$PrivacyReviewed
    if ($LASTEXITCODE -ne 0) { throw 'El release gate de Flutter falló.' }
  }
  if (-not (Test-Path $Exe)) { throw 'No existe build Windows release. Ejecute sin -SkipBuild.' }
  Copy-NativeRuntimeAssets

  $SignTool = $null
  if ($SigningRequested) {
    $kits = @(
      "$env:ProgramFiles(x86)\Windows Kits\10\bin\x64\signtool.exe",
      "$env:ProgramFiles\Windows Kits\10\bin\x64\signtool.exe"
    )
    $SignTool = Resolve-Tool $kits 'signtool.exe'
    if (-not $SignTool) { throw 'Se solicitó firma, pero signtool.exe no está disponible.' }
    Sign-File $Exe $SignTool
  }

  $Iscc = Resolve-Tool @(
    "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  ) 'ISCC.exe'
  if (-not $Iscc) { throw 'Inno Setup 6 no está instalado o ISCC.exe no está en PATH.' }

  New-Item -ItemType Directory -Force -Path (Join-Path $Root 'build\installer') | Out-Null
  & $Iscc "/DMyAppVersion=$Version" "/DMyAppPublisher=$Publisher" "$Root\installer\merkaerp.iss"
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup no pudo generar el instalador.' }
  if (-not (Test-Path $Installer)) { throw "No se encontró el instalador esperado: $Installer" }

  if ($SigningRequested) { Sign-File $Installer $SignTool }

  New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
  $installerHash = (Get-FileHash $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $exeHash = (Get-FileHash $Exe -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest = [ordered]@{
    format = 'MERKAERP_LOCAL_RELEASE_1'
    version = $Version
    build = $Build
    display_version = $DisplayVersion
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    target = 'windows-x64'
    publisher = $Publisher
    analyzer_passed = (-not $SkipBuild)
    tests_passed = (-not $SkipBuild)
    privacy_reviewed = $PrivacyReviewed.IsPresent
    signature_requested = $SigningRequested
    signature_verified = $SigningRequested
    executable = [ordered]@{ path = $Exe; sha256 = $exeHash }
    installer = [ordered]@{ path = $Installer; sha256 = $installerHash }
  }
  $ManifestPath = Join-Path $ReleaseDir "MerkaERP-$Version-$Build-release.json"
  $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding UTF8
  "$installerHash  $(Split-Path -Leaf $Installer)" | Set-Content -Path "$Installer.sha256" -Encoding ASCII

  Write-Host "`nInstalador generado y verificado:" -ForegroundColor Green
  Write-Host $Installer
  Write-Host "SHA-256: $installerHash"
  Write-Host "Evidencia local: $ManifestPath"
  if (-not $SigningRequested) {
    Write-Warning 'El instalador NO está firmado digitalmente. No se ha marcado como firmado.'
  }
} finally {
  Pop-Location
}
