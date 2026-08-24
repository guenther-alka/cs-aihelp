# serve_smoke.ps1 -- smoke test for cs-aihelp serve (auth + /ask)
$ErrorActionPreference = 'Continue'
$mock = Start-Process perl -ArgumentList 'C:\opt\testbase\ai_mock_server.pl','19091' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 1
$env:OLLAMA_BASE = 'http://127.0.0.1:19091'
$dmn = Start-Process 'C:\opt\testbase\cs-aihelp.exe' -ArgumentList 'serve','--config','C:\opt\testbase\cs-aihelp-test.cfg' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2

function Try-Get($u, $hdr) {
    try {
        if ($hdr) { $r = Invoke-WebRequest -Uri $u -Headers $hdr -TimeoutSec 8 -UseBasicParsing }
        else      { $r = Invoke-WebRequest -Uri $u -TimeoutSec 8 -UseBasicParsing }
        return "HTTP $($r.StatusCode): $($r.Content)"
    } catch {
        return "HTTP $([int]$_.Exception.Response.StatusCode): $($_.Exception.Response.StatusDescription)"
    }
}

"--- /health ohne Token (erwartet 401) ---"
Try-Get 'http://127.0.0.1:45555/health' $null
"--- /health mit Token (erwartet 200 ok) ---"
Try-Get 'http://127.0.0.1:45555/health' @{ Authorization = 'Bearer testtoken' }
"--- /status mit Token ---"
Try-Get 'http://127.0.0.1:45555/status' @{ Authorization = 'Bearer testtoken' }
"--- /ask mit Token (JSON) ---"
try {
    $body = @{ question = 'hallo daemon'; stream = $false } | ConvertTo-Json
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:45555/ask' -Method Post -Headers @{ Authorization = 'Bearer testtoken'; 'Content-Type' = 'application/json' } -Body $body -TimeoutSec 20 -UseBasicParsing
    "HTTP $($r.StatusCode): $($r.Content)"
} catch { "ask FAIL: $($_.Exception.Message)" }

Stop-Process -Id $dmn.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $mock.Id -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\opt\testbase\cs-aihelp.pid' -ErrorAction SilentlyContinue

