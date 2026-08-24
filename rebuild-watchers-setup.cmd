@echo off
setlocal enabledelayedexpansion
rem Rebuilds ActivityWatch-Fleet-Watchers-Setup.exe from the current sources.
rem Self-elevates, clears locks/ACLs on the old exe, packages watchers only.

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
set "OUT=%REPO%\dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe"

echo === Step 1/2: clearing the previous setup exe ===
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Continue';" ^
  "$out='%OUT%';" ^
  "if (-not (Test-Path -LiteralPath $out)) { Write-Host 'No previous exe present.'; exit 0 };" ^
  "$holders = Get-Process | Where-Object { $_.Path -and $_.Path -ieq $out };" ^
  "if ($holders) { Write-Host ('Running from that exe: ' + (($holders | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ', ')); $holders | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 };" ^
  "& attrib.exe -R -S -H $out 2>$null | Out-Null;" ^
  "Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue;" ^
  "if (-not (Test-Path -LiteralPath $out)) { Write-Host 'Removed.'; exit 0 };" ^
  "Write-Host 'Still locked - taking ownership...';" ^
  "& takeown.exe /F $out | Out-Null;" ^
  "& icacls.exe $out /grant *S-1-5-32-544:F | Out-Null;" ^
  "Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue;" ^
  "if (-not (Test-Path -LiteralPath $out)) { Write-Host 'Removed after takeown.'; exit 0 };" ^
  "$stamp = Get-Date -Format 'yyyyMMdd-HHmmss';" ^
  "$parked = $out + '.old-' + $stamp;" ^
  "Write-Host ('Delete still refused - renaming to ' + (Split-Path -Leaf $parked));" ^
  "Move-Item -LiteralPath $out -Destination $parked -Force -ErrorAction SilentlyContinue;" ^
  "if (Test-Path -LiteralPath $out) { Write-Host 'FATAL: could not remove or rename the old exe.'; Write-Host 'It is held open by a process (antivirus scan, Explorer preview, sync client) - reboot and retry.'; exit 1 };" ^
  "Write-Host 'Renamed out of the way.'; exit 0"

if errorlevel 1 (
    echo.
    echo Could not clear the previous exe. Build not attempted.
    popd
    pause
    exit /b 1
)

echo.
echo === Step 2/2: building ===
echo This takes several minutes and prints nothing while zipping/packaging.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\deploy\windows\build-setup.ps1" -Target Watchers
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
