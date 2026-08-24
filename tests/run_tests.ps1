# Run the AI Helpdesk test suite against a local mock HTTP server (Windows).
$p = Start-Process perl -ArgumentList "$PSScriptRoot\ai_mock_server.pl",'19091' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 1
try {
    perl "$PSScriptRoot\ai_helpdesk_test.pl"
    exit $LASTEXITCODE
} finally {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
