param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers"),
    [switch]$SkipStartup,
    [switch]$SkipSystemTask,
    [switch]$NoStart,
    [switch]$AllowNonAdmin
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Register-WatcherSupervisorTask {
    param([string]$InstallDir)

    $taskName = "ActivityWatch Fleet Watchers Supervisor"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $supervisorScript = Join-Path $InstallDir "supervise-watchers.ps1"

    if (-not (Test-Path $supervisorScript)) {
        throw "Watcher supervisor script not found at $supervisorScript"
    }

    $action = New-ScheduledTaskAction `
        -Execute $powershell `
        -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $supervisorScript) `
        -WorkingDirectory $InstallDir

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $repeatingTrigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger @($startupTrigger, $logonTrigger, $repeatingTrigger) `
        -Principal $principal `
        -Settings $settings `
        -Description "Starts ActivityWatch Fleet watchers in every active interactive user session." `
        -Force | Out-Null

    Start-ScheduledTask -TaskName $taskName
    Write-Host "Registered and started scheduled task '$taskName'."
}

function Stop-ExistingWatcherProcesses {
    param([string]$InstallDir)

    $watcherExePaths = @(
        Join-Path $InstallDir "aw-watcher-afk\aw-watcher-afk.exe"
        Join-Path $InstallDir "aw-watcher-window\aw-watcher-window.exe"
        Join-Path $InstallDir "aw-watcher-session\aw-watcher-session.exe"
        Join-Path $InstallDir "aw-watcher-system\aw-watcher-system.exe"
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
    Write-Error "Run this setup as Administrator. It installs to Program Files and creates a machine-level watcher supervisor scheduled task."
    exit 1
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-watchers.ps1"
}

Stop-ExistingWatcherProcesses -InstallDir $InstallDir
Unregister-ScheduledTask -TaskName "ActivityWatch Fleet System Watcher" -Confirm:$false -ErrorAction SilentlyContinue

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

if (-not $SkipSystemTask) {
    $taskName = "ActivityWatch Fleet System Watcher"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startScript = Join-Path $InstallDir "start-system-watcher.ps1"
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript

    $action = New-ScheduledTaskAction -Execute $powershell -Argument $taskArgs -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Start ActivityWatch Fleet system metrics watcher on boot." `
        -Force | Out-Null
}

if (-not $NoStart) {
    Register-WatcherSupervisorTask -InstallDir $InstallDir
    if (-not $SkipSystemTask) {
        Start-ScheduledTask -TaskName "ActivityWatch Fleet System Watcher"
    }
} else {
    Write-Host "Skipping watcher supervisor registration because -NoStart was used."
}

Write-Host "ActivityWatch Fleet Watchers installed to $InstallDir"
Write-Host "Watchers will send to http://192.168.0.144:5600/"
