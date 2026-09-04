# Step 2: clean + pub get
$PROJECT = "c:\Users\PC\Desktop\MERA ARREGLADO POR GPT\MerkaERP_TEST_READY_1.2.1_7"
$FLUTTER = "C:\src\flutter\bin\flutter.bat"
$OUT = "$PROJECT\step2_output.txt"

Set-Location $PROJECT

"=== flutter clean ===" | Out-File $OUT -Encoding UTF8
& $FLUTTER clean 2>&1 | Out-File $OUT -Encoding UTF8 -Append
$cleanCode = $LASTEXITCODE
"EXIT CODE: $cleanCode" | Out-File $OUT -Encoding UTF8 -Append

"" | Out-File $OUT -Encoding UTF8 -Append
"=== flutter pub get ===" | Out-File $OUT -Encoding UTF8 -Append
& $FLUTTER pub get 2>&1 | Out-File $OUT -Encoding UTF8 -Append
$pubCode = $LASTEXITCODE
"EXIT CODE: $pubCode" | Out-File $OUT -Encoding UTF8 -Append

Write-Host "Done step2. clean=$cleanCode pubget=$pubCode"
