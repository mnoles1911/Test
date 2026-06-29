@echo off
REM ============================================================================
REM  Rebake-Terrain.bat  -  one-line whole-map terrain bake (parallel by default).
REM
REM  USAGE:  Rebake-Terrain.bat  <cubeCm>  [saveName]  [jobs]
REM     cubeCm    cube edge in cm: 40, 80, 160, 640 ...        (default 80)
REM     saveName  /Game/VoxelBake/<saveName>      (default MiraStreamTest_<cubeCm>cm)
REM     jobs      parallel processes; blank/omitted = auto (cores-2); 1 = single
REM
REM  EXAMPLES:
REM     Rebake-Terrain.bat 80                  (80cm, auto-parallel)
REM     Rebake-Terrain.bat 40 MyFine 12        (40cm across 12 processes)
REM     Rebake-Terrain.bat 10 Mira10cm         (10cm global, auto-parallel - hours)
REM
REM  CLOSE the GUI editor first. This is a thin wrapper over Rebake-Terrain.ps1,
REM  which shards the bake across processes and merges the result.
REM ============================================================================
setlocal
set "CUBE=%~1"
if "%CUBE%"=="" set "CUBE=80"
set "PSARGS=-CubeCm %CUBE%"
if not "%~2"=="" set "PSARGS=%PSARGS% -Name %~2"
if not "%~3"=="" set "PSARGS=%PSARGS% -Jobs %~3"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Rebake-Terrain.ps1" %PSARGS%
endlocal
exit /b %ERRORLEVEL%
