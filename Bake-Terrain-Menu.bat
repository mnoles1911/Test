@echo off
setlocal
REM ============================================================================
REM  Bake-Terrain-Menu.bat  -  pick a terrain resolution and bake the whole map.
REM
REM  Interactive front-end for Rebake-Terrain.bat. Re-run it any time you want a
REM  different global crust resolution. CLOSE the GUI editor before baking
REM  (the bake launches its own headless instance).
REM ============================================================================

:menu
cls
echo ==================== MIRA-THAL  TERRAIN  BAKE ====================
echo   Whole 5km x 5km map, baked to Nanite crust tiles.
echo   The baker auto-clips to the coastline (no ocean tiles).
echo.
echo    #   CUBE     ~TILES     ~DISK      ~TIME      NOTES
echo   ---  ------   --------   --------   --------   -----------------------------
echo   [1]  10 cm    ~275,000   ~4-6 GB    8-15 hrs   OVER the file wall *
echo   [2]  20 cm     ~70,000   ~1.3 GB    3-4 hrs    PAST the wall (borderline) *
echo   [3]  40 cm     ~17,000   ~300 MB    ~1 hr      heavy but OK
echo   [4]  80 cm      ~5,000   ~150 MB    ~20 min    sweet spot  (RECOMMENDED)
echo   [5]  1.6 m      ~2,000    ~40 MB    ~12 min    coarse / cheap
echo   [6]  custom    (enter your own cube size in cm)
echo   [0]  quit
echo   -----------------------------------------------------------------
echo    * 10/20cm produce a huge file count with one-file-per-tile. They WORK
echo      but strain the project; "region-packing" (a future upgrade) is the
echo      clean way to ship 10-20cm. You will be warned again before proceeding.
echo =================================================================
echo.

set "CUBE="
set /p CHOICE=Select [0-6]:
if "%CHOICE%"=="1" set "CUBE=10"
if "%CHOICE%"=="2" set "CUBE=20"
if "%CHOICE%"=="3" set "CUBE=40"
if "%CHOICE%"=="4" set "CUBE=80"
if "%CHOICE%"=="5" set "CUBE=160"
if "%CHOICE%"=="6" goto custom
if "%CHOICE%"=="0" goto end
if not defined CUBE ( echo. & echo Invalid choice "%CHOICE%". & pause & goto menu )
goto confirm

:custom
echo.
set /p CUBE=Enter cube size in cm (10 voxels/metre, e.g. 30):
if not defined CUBE goto menu

:confirm
echo.
set /p NAME=Save name [default MiraStreamTest_%CUBE%cm]:
if not defined NAME set "NAME=MiraStreamTest_%CUBE%cm"
echo.
echo   Parallel processes speed up the bake on multi-core machines.
set /p JOBS=Parallel jobs [blank = auto (cores-2), or 1 = single process]:
echo.
echo   Baking %CUBE%cm cubes  ->  /Game/VoxelBake/%NAME%    (jobs: %JOBS%)
echo   Make sure the GUI editor is CLOSED.
echo.
pause

if "%JOBS%"=="" (
  powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Rebake-Terrain.ps1" -CubeCm %CUBE% -Name "%NAME%"
) else (
  powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Rebake-Terrain.ps1" -CubeCm %CUBE% -Name "%NAME%" -Jobs %JOBS%
)

echo.
echo   (Point a VoxelNaniteCrust actor's Manifest at /Game/VoxelBake/%NAME%
echo    and set its Inner/Outer chunk band to stream this layer.)
echo.
pause
goto menu

:end
endlocal
exit /b 0
