# sync.ps1 -- copy the csweb-gui AI module files + testbase tests into this repo.
# Run after editing files under c:\opt\csweb-gui or c:\opt\testbase.
$ErrorActionPreference = 'Continue'
$src = 'C:\opt\csweb-gui\data'
$dst = 'C:\opt\cs-aihelp-src\data'

$module = @(
  'menues/_lib/windows/aihelplib.pl',
  'menues/_lib/windows/cstoolslib.pl',
  'menues/05_Help/00_AI_Helpdesk/action.pl',
  'menues/10_System/05_Services/12_AI_Helpdesk/action.pl',
  'menues/_lib/tools/CS_Tools_Download/action.pl',
  'wwwroot/cgi-bin/cs-aihelp.pl',
  'wwwroot/cgi-bin/cs-aihelp-exec.pl',
  'howto.ai/ai-helpdesk.info'
)
foreach ($f in $module) {
  $d = Join-Path $dst (Split-Path $f -Parent)
  if (!(Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  Copy-Item -Force (Join-Path $src $f) (Join-Path $dst $f)
  Write-Output "  + data/$f"
}

$tests = @('ai_helpdesk_test.pl','ai_mock_server.pl','ai_compile_check.pl','cs-aihelp-test.cfg','serve_smoke.ps1','exec_e2e.ps1','lifecycle_smoke.ps1')
foreach ($f in $tests) {
  if (Test-Path "C:\opt\testbase\$f") {
    Copy-Item -Force "C:\opt\testbase\$f" "C:\opt\cs-aihelp-src\tests\$f"
    Write-Output "  + tests/$f"
  }
}
Write-Output 'sync done'
