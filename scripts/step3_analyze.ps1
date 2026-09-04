# Step 3: flutter analyze
$PROJECT = "c:\Users\PC\Desktop\MERA ARREGLADO POR GPT\MerkaERP_TEST_READY_1.2.1_7"
$FLUTTER = "C:\src\flutter\bin\flutter.bat"
$OUT = "$PROJECT\step3_analyze.txt"

Set-Location $PROJECT

"=== flutter analyze --no-fatal-warnings --no-fatal-infos ===" | Out-File $OUT -Encoding UTF8
& $FLUTTER analyze --no-fatal-warnings --no-fatal-infos 2>&1 | Out-File $OUT -Encoding UTF8 -Append
$code = $LASTEXITCODE
"EXIT CODE: $code" | Out-File $OUT -Encoding UTF8 -Append

Write-Host "Done step3. analyze=$code"
