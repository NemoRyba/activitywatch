@echo off
setlocal enabledelayedexpansion
rem Collects ActivityWatch Fleet watcher logs from fleet PCs into diagnostics\
rem so they can be analyzed from the repo. Add machine names below as needed.

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
set "OUTDIR=%REPO%\diagnostics"
set "MACHINES=tbfpc6 tbfpc4 tbfpc2"

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

for %%M in (%MACHINES%) do (
    echo === %%M ===
    set "SRC=\\%%M\C$\ProgramData\ActivityWatchFleet\logs"
    if exist "!SRC!\supervisor.log" (
        copy /Y "!SRC!\supervisor.log" "%OUTDIR%\supervisor-%%M.log" >nul && echo   supervisor.log copied
    ) else (
        echo   no supervisor.log at !SRC!
    )
    rem per-user watcher logs live under each user profile
    for /D %%U in (\\%%M\C$\Users\*) do (
        if exist "%%U\AppData\Local\ActivityWatchFleet\logs\watchers" (
            for %%F in ("%%U\AppData\Local\ActivityWatchFleet\logs\watchers\*.err.log") do (
                copy /Y "%%F" "%OUTDIR%\%%M-%%~nU-%%~nxF" >nul
            )
            echo   watcher logs copied for user %%~nU
        )
    )
)

echo.
echo Done. Files are in: %OUTDIR%
pause
