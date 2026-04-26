@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0stack.ps1" start %*
