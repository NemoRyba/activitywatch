param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers"),
    [switch]$SkipStartup,
    [switch]$NoStart,
    [switch]$AllowNonAdmin
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files and creates an all-users startup shortcut."
    exit 1
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-watchers.ps1"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Expand-Archive -Path $payload -DestinationPath $InstallDir -Force

if (-not $SkipStartup) {
    $startupDir = [Environment]::GetFolderPath("CommonStartup")
    $shortcutPath = Join-Path $startupDir "ActivityWatch Fleet Watchers.lnk"
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startScript = Join-Path $InstallDir "start-watchers.ps1"
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = "Start ActivityWatch Fleet Watchers for the logged-in user."
    $shortcut.Save()
}

if (-not $NoStart) {
    & (Join-Path $InstallDir "start-watchers.ps1")
}

Write-Host "ActivityWatch Fleet Watchers installed to $InstallDir"
Write-Host "Watchers will send to http://192.168.0.144:5600/"
