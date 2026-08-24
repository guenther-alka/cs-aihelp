# exec_e2e.ps1 -- Level 2 end-to-end: daemon parses [[ACTION]], accepts tool_results
$ErrorActionPreference = 'Continue'
$mock = Start-Process perl -ArgumentList 'C:\opt\testbase\ai_mock_server.pl','19091' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 1
$env:OLLAMA_BASE = 'http://127.0.0.1:19091'
# variant config: exec_access=exec with allow zfs (overwrite for the test)
$cfg = Get-Content 'C:\opt\testbase\cs-aihelp-test.cfg'
$cfg = $cfg -replace '^exec_access\s*=.*','exec_access  = exec'
$cfg = $cfg -replace '^exec_allow\s*=.*','exec_allow   = zfs,find'
$cfg | Set-Content 'C:\opt\testbase\cs-aihelp-exec-test.cfg' -Encoding Ascii
$dmn = Start-Process 'C:\opt\testbase\cs-aihelp.exe' -ArgumentList 'serve','--config','C:\opt\testbase\cs-aihelp-exec-test.cfg' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
$H = @{ Authorization = 'Bearer testtoken'; 'Content-Type' = 'application/json' }

"--- /ask mit ACTIONTEST (erwartet action + bereinigte Antwort) ---"
try {
    $body = @{ question = 'ACTIONTEST bitte Snapshot machen'; stream = $false } | ConvertTo-Json
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:45555/ask' -Method Post -Headers $H -Body $body -TimeoutSec 20 -UseBasicParsing
    "HTTP $($r.StatusCode): $($r.Content)"
} catch { "ask1 FAIL: $($_.Exception.Message)" }

"--- /ask Continuation mit tool_results (erwartet Antwort ohne Fehler) ---"
try {
    $body = @{ question = ''; stream = $false; tool_results = @('MOCK-EXEC-OUTPUT: snapshot created') } | ConvertTo-Json
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:45555/ask' -Method Post -Headers $H -Body $body -TimeoutSec 20 -UseBasicParsing
    "HTTP $($r.StatusCode): $($r.Content)"
} catch { "ask2 FAIL: $($_.Exception.Message)" }

Stop-Process -Id $dmn.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $mock.Id -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\opt\testbase\cs-aihelp-exec-test.cfg' -ErrorAction SilentlyContinue
Remove-Item 'C:\opt\testbase\cs-aihelp.pid' -ErrorAction SilentlyContinue
