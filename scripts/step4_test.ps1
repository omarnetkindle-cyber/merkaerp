# Step 4: flutter test
$PROJECT = "c:\Users\PC\Desktop\MERA ARREGLADO POR GPT\MerkaERP_TEST_READY_1.2.1_7"
$FLUTTER = "C:\src\flutter\bin\flutter.bat"
$OUT = "$PROJECT\step4_test.txt"

Set-Location $PROJECT

$start = Get-Date
"=== flutter test ===" | Out-File $OUT -Encoding UTF8
"Started: $start" | Out-File $OUT -Encoding UTF8 -Append
& $FLUTTER test 2>&1 | Out-File $OUT -Encoding UTF8 -Append
$code = $LASTEXITCODE
$end = Get-Date
$duration = $end - $start
"EXIT CODE: $code" | Out-File $OUT -Encoding UTF8 -Append
"Duration: $($duration.TotalSeconds) seconds" | Out-File $OUT -Encoding UTF8 -Append

Write-Host "Done step4. test=$code duration=$($duration.TotalSeconds)s"
