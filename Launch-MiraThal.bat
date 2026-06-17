@echo off
REM Launch MiraThal in the CUSTOM source engine at D:å (bypasses the flaky
REM GUID registry mapping that the launcher keeps clearing). Double-click this.
start "" "D:å_5.7ngine\Binaries\Win64\UnrealEditor.exe" "%~dp0ue5\MiraThal\MiraThal.uproject"
