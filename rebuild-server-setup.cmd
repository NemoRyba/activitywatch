@echo off
setlocal
rem Rebuilds ActivityWatch-Fleet-Server-Setup.exe from the current sources.
rem Self-elevates, rebuilds the web UI, rebuilds the PyInstaller server payload,
rem then packages the server setup only.

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs" || (
        echo.
        echo Elevation was cancelled or failed.
        pause
        exit /b 1
    )
    exit /b 0
)

pushd "%REPO%"
set "OUT=%REPO%\dist\deployment\ActivityWatch-Fleet-Server-Setup.exe"

echo === Rebuilding ActivityWatch Fleet Server setup ===
echo This builds web UI assets, the PyInstaller server payload, and the setup exe.
echo It can take several minutes.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\deploy\windows\rebuild-server-setup.ps1" -ServerHost 192.168.0.144 -ServerPort 5600
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo BUILD FAILED with exit code %RC%.
    popd
    pause
    exit /b %RC%
)

if exist "%OUT%" (
    echo BUILD OK.
    for %%F in ("%OUT%") do echo   %%~fF  ^(%%~zF bytes, %%~tF^)
) else (
    echo Build reported success but the expected output is missing:
    echo   %OUT%
    set "RC=1"
)

popd
echo.
pause
exit /b %RC%
