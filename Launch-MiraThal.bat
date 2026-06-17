@echo off
REM Launch MiraThal in the CUSTOM source engine at D:\UE5 ? bypasses the flaky
REM GUID registry mapping (the launcher keeps clearing it). Just double-click this.
start "" "D:\UE5\UE_5.7\Engine\Binaries\Win64\UnrealEditor.exe" "%~dp0ue5\MiraThal\MiraThal.uproject"
