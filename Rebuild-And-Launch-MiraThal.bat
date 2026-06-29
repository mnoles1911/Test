@echo off
REM ============================================================================
REM Rebuild-And-Launch-MiraThal.bat
REM
REM The plain Launch-MiraThal.bat ONLY launches the editor - it never rebuilds,
REM so any C++ change you made since the last build silently does NOT take effect
REM (the editor loads the stale DLL on disk). USE THIS script after editing C++.
REM
REM It: (1) force-closes any running editor (so the DLL unlocks),
REM     (2) rebuilds MiraThalEditor (Development, Win64) in the D:\UE5 source engine,
REM     (3) only launches if the build SUCCEEDED.
REM Double-click it, or run from a terminal.
REM ============================================================================
setlocal
set ENGINE=D:\UE5\UE_5.7
set PROJECT=%~dp0ue5\MiraThal\MiraThal.uproject

echo [1/3] Closing any running Unreal editor...
taskkill /IM UnrealEditor.exe /F >nul 2>&1
REM give Windows a moment to release the loaded DLLs
ping -n 3 127.0.0.1 >nul

echo [2/3] Building MiraThalEditor (this can take ~15s for a small change)...
call "%ENGINE%\Engine\Build\BatchFiles\Build.bat" MiraThalEditor Win64 Development -Project="%PROJECT%" -WaitMutex
if errorlevel 1 (
  echo.
  echo *** BUILD FAILED - editor NOT launched. Scroll up for the error. ***
  pause
  exit /b 1
)

echo [3/3] Build OK. Launching editor...
start "" "%ENGINE%\Engine\Binaries\Win64\UnrealEditor.exe" "%PROJECT%"
echo Done. When the editor is up: press Play, then run your console command.
endlocal
