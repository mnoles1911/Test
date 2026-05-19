# tools/headless/run.ps1 — headless Tier-A test invoker.
#
# Usage:
#   powershell -File tools\headless\run.ps1 gate0
#   powershell -File tools\headless\run.ps1 codec
#   powershell -File tools\headless\run.ps1 spike
#
# Godot binary resolution order:
#   1. -GodotBin argument
#   2. $env:GODOT_BIN
#   3. the known local 4.6.2 console build (auto-detected 2026-05-18)
# Use the *_console.exe* build — the plain win64.exe is GUI-subsystem
# and does NOT pipe stdout/stderr to the terminal.
#
# Exit code is propagated from the runner (0 = pass, non-zero = fail).

param(
	[Parameter(Mandatory = $true)]
	[ValidateSet("gate0", "codec", "spike")]
	[string]$Selector,

	[string]$GodotBin = ""
)

$ErrorActionPreference = "Stop"

$projectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$candidates = @()
if ($GodotBin -ne "") { $candidates += $GodotBin }
if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
$candidates += "C:\Users\Matt Noles\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"

$godot = $null
foreach ($c in $candidates) {
	if ($c -and (Test-Path $c)) { $godot = $c; break }
}
if (-not $godot) {
	Write-Error "Godot console exe not found. Pass -GodotBin <path> or set GODOT_BIN. Tried: $($candidates -join '; ')"
	exit 3
}

Write-Output "[run.ps1] godot   = $godot"
Write-Output "[run.ps1] project = $projectDir"
Write-Output "[run.ps1] selector= $Selector"
Write-Output "[run.ps1] ----------------------------------------"

& $godot --headless --path $projectDir --script "res://tools/headless/runner.gd" -- $Selector
$code = $LASTEXITCODE

Write-Output "[run.ps1] ----------------------------------------"
Write-Output "[run.ps1] exit=$code"
exit $code
