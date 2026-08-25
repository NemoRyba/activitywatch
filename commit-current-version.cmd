@echo off
setlocal
rem Commits the current state of all fork-owned repos (submodules first, root
rem last). Optional argument = commit message. Nothing is pushed.

pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0commit-current-version.ps1" %*
set "RC=%ERRORLEVEL%"
popd
echo.
pause
exit /b %RC%
