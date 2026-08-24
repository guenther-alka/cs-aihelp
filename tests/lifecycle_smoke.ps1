# lifecycle_smoke.ps1 -- start / status / stop smoke for cs-aihelp
$ErrorActionPreference = 'Continue'
$exe = 'C:\opt\testbase\cs-aihelp.exe'
$cfg = 'C:\opt\testbase\cs-aihelp-test.cfg'
$pidf = 'C:\opt\testbase\cs-aihelp.pid'
Remove-Item $pidf -ErrorAction SilentlyContinue

# free the port if a previous run left a daemon behind
Get-NetTCPConnection -LocalPort 45555 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

"--- start ---"
& $exe start --config $cfg
Start-Sleep -Seconds 3
"--- start (idempotent) ---"
& $exe start --config $cfg
"--- status ---"
& $exe status --config $cfg
"--- pid file ---"
$pidc = Get-Content $pidf -ErrorAction SilentlyContinue
"pid=$pidc  file_exists=$(Test-Path $pidf)"
"--- stop ---"
& $exe stop --config $cfg
Start-Sleep -Seconds 2
"--- stop again (expected: no pid file) ---"
& $exe stop --config $cfg 2>&1
"--- port after stop (expected: False) ---"
(Get-NetTCPConnection -LocalPort 45555 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0