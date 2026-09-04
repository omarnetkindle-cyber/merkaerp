# Step 5: flutter build windows --release
$PROJECT = "c:\Users\PC\Desktop\MERA ARREGLADO POR GPT\MerkaERP_TEST_READY_1.2.1_7"
$FLUTTER = "C:\src\flutter\bin\flutter.bat"
$OUT = "$PROJECT\step5_build.txt"

Set-Location $PROJECT

$start = Get-Date
"=== flutter build windows --release ===" | Out-File $OUT -Encoding UTF8
"Started: $start" | Out-File $OUT -Encoding UTF8 -Append
& $FLUTTER build windows --release 2>&1 | Out-File $OUT -Encoding UTF8 -Append
$code = $LASTEXITCODE
$end = Get-Date
$duration = $end - $start
"EXIT CODE: $code" | Out-File $OUT -Encoding UTF8 -Append
"Duration: $($duration.TotalSeconds) seconds" | Out-File $OUT -Encoding UTF8 -Append

# Check if exe exists
$exePath = "$PROJECT\build\windows\x64\runner\Release\MerkaERP.exe"
if (Test-Path $exePath) {
    $info = Get-Item $exePath
    "" | Out-File $OUT -Encoding UTF8 -Append
    "=== MerkaERP.exe ===" | Out-File $OUT -Encoding UTF8 -Append
    "EXISTS: YES" | Out-File $OUT -Encoding UTF8 -Append
    "Size: $($info.Length) bytes ($([math]::Round($info.Length/1MB,2)) MB)" | Out-File $OUT -Encoding UTF8 -Append
    "LastWrite: $($info.LastWriteTime)" | Out-File $OUT -Encoding UTF8 -Append
    "" | Out-File $OUT -Encoding UTF8 -Append
    "=== Release folder contents ===" | Out-File $OUT -Encoding UTF8 -Append
    Get-ChildItem "$PROJECT\build\windows\x64\runner\Release" | Format-Table Name, Length, LastWriteTime | Out-File $OUT -Encoding UTF8 -Append
} else {
    "" | Out-File $OUT -Encoding UTF8 -Append
    "=== MerkaERP.exe ===" | Out-File $OUT -Encoding UTF8 -Append
    "EXISTS: NO" | Out-File $OUT -Encoding UTF8 -Append
}

Write-Host "Done step5. build=$code duration=$($duration.TotalSeconds)s exe=$(Test-Path $exePath)"
