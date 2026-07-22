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

function Stop-ExistingWatcherProcesses {
    param([string]$InstallDir)

    $watcherExePaths = @(
        Join-Path $InstallDir "aw-watcher-afk\aw-watcher-afk.exe"
        Join-Path $InstallDir "aw-watcher-window\aw-watcher-window.exe"
        Join-Path $InstallDir "aw-watcher-session\aw-watcher-session.exe"
    )

    foreach ($watcherExe in $watcherExePaths) {
        if (-not (Test-Path $watcherExe)) {
            continue
        }

        $watcherExePath = [IO.Path]::GetFullPath($watcherExe)
        $processes = Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and [string]::Equals(
                $_.ExecutablePath,
                $watcherExePath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }

        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Could not gracefully stop ActivityWatch Fleet Watcher PID $($process.ProcessId): $($_.Exception.Message)"
            }

            if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            }

            Write-Host "Stopped existing ActivityWatch Fleet Watcher PID $($process.ProcessId)."
        }
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files and creates an all-users startup shortcut."
    exit 1
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-watchers.ps1"
}

Stop-ExistingWatcherProcesses -InstallDir $InstallDir

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Expand-Archive -Path $payload -DestinationPath $InstallDir -Force

if (-not $SkipStartup) {
    $startupDir = [Environment]::GetFolderPath("CommonStartup")
    $shortcutPath = Join-Path $startupDir "ActivityWatch Fleet Watchers.lnk"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
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
