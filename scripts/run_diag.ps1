# MerkaERP Diagnostics Script
$PROJECT = "c:\Users\PC\Desktop\MERA ARREGLADO POR GPT\MerkaERP_TEST_READY_1.2.1_7"
$FLUTTER = "C:\src\flutter\bin\flutter.bat"
$OUT = "$PROJECT\diag_output.txt"

Set-Location $PROJECT

"=== FLUTTER VERSION ===" | Out-File $OUT
& $FLUTTER --version 2>&1 | Out-File $OUT -Append

"=== FLUTTER DOCTOR ===" | Out-File $OUT -Append
& $FLUTTER doctor -v 2>&1 | Out-File $OUT -Append

Write-Host "Done: flutter version + doctor"
