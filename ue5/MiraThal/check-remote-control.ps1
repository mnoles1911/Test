# check-remote-control.ps1 — quick health check for the mcp-unreal bridge.
# Run this AFTER restarting the Unreal editor. It confirms the editor is up,
# the Remote Control HTTP server is listening on 30010, and the API answers.
# Usage (from a normal PowerShell prompt, or type `! powershell -File check-remote-control.ps1` in Claude Code):
#   powershell -ExecutionPolicy Bypass -File "C:\Users\Matt Noles\Test-ue5\ue5\MiraThal\check-remote-control.ps1"

Write-Host "== mcp-unreal bridge check ==" -ForegroundColor Cyan

$ue = Get-Process UnrealEditor -ErrorAction SilentlyContinue
if ($ue) { Write-Host "[ok]  UnrealEditor running (PID $($ue.Id))" -ForegroundColor Green }
else     { Write-Host "[!!]  UnrealEditor NOT running — open MiraThal.uproject first" -ForegroundColor Red; exit 1 }

$listen = Get-NetTCPConnection -LocalPort 30010 -State Listen -ErrorAction SilentlyContinue
if ($listen) { Write-Host "[ok]  Remote Control HTTP server LISTENING on 30010" -ForegroundColor Green }
else { Write-Host "[!!]  Port 30010 not listening — RC server didn't auto-start. In the editor console run: WebControl.StartServer" -ForegroundColor Red; exit 1 }

try {
    $body = '{"objectPath":"/Script/Engine.Default__KismetSystemLibrary","functionName":"GetEngineVersion","parameters":{}}'
    $resp = Invoke-RestMethod -Uri "http://localhost:30010/remote/object/call" -Method Put -Body $body -ContentType "application/json" -TimeoutSec 5
    Write-Host "[ok]  RC API answered — engine version: $($resp.ReturnValue)" -ForegroundColor Green
    Write-Host "All green. Restart Claude Code (claude -c) to load the mcp-unreal tools." -ForegroundColor Cyan
} catch {
    Write-Host "[!!]  Port open but RC API call failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
