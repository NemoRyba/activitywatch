param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Server"),
    [switch]$SkipTask,
    [switch]$SkipFirewall,
    [switch]$NoStart,
    [switch]$AllowNonAdmin
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledServerProcesses {
    param(
        [string]$ServerExe,
        [string]$PidFile
    )

    $processes = @()
    $serverExePath = [IO.Path]::GetFullPath($ServerExe)

    if (Test-Path $PidFile) {
        try {
            $existingPid = [int](Get-Content $PidFile -Raw)
            $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
            if ($existing) {
                $processes += $existing
            }
        } catch {
            Write-Warning "Ignoring stale ActivityWatch Fleet Server PID file: $($_.Exception.Message)"
        }
    }

    if (Test-Path $ServerExe) {
        $processes += Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and [string]::Equals(
                $_.ExecutablePath,
                $serverExePath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    }

    return $processes | Sort-Object ProcessId -Unique
}

function Stop-ExistingServer {
    param([string]$InstallDir)

    $taskName = "ActivityWatch Fleet Server"
    $serverExe = Join-Path $InstallDir "aw-server\aw-server.exe"
    $runtimeRoot = Join-Path ${env:ProgramData} "ActivityWatchFleet"
    $pidFile = Join-Path $runtimeRoot "pids\server.pid"

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Write-Host "Stopped existing ActivityWatch Fleet Server scheduled task."
        } catch {
            Write-Warning "Could not stop existing scheduled task '$taskName': $($_.Exception.Message)"
        }
    }

    $processes = @(Get-InstalledServerProcesses -ServerExe $serverExe -PidFile $pidFile)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
            Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not gracefully stop ActivityWatch Fleet Server PID $($process.ProcessId): $($_.Exception.Message)"
        }

        if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
        }

        Write-Host "Stopped existing ActivityWatch Fleet Server PID $($process.ProcessId)."
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files, creates a startup task, and opens firewall port 5600."
    exit 1
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-server.ps1"
}

Stop-ExistingServer -InstallDir $InstallDir

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Expand-Archive -Path $payload -DestinationPath $InstallDir -Force

$runtimeRoot = Join-Path ${env:ProgramData} "ActivityWatchFleet"
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (-not $SkipFirewall) {
    try {
        $ruleName = "ActivityWatch Fleet Server 5600"
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule `
                -DisplayName $ruleName `
                -Direction Inbound `
                -Action Allow `
                -Protocol TCP `
                -LocalPort 5600 | Out-Null
        }
    } catch {
        Write-Warning "Could not create firewall rule for TCP 5600: $($_.Exception.Message)"
    }
}

if (-not $SkipTask) {
    $taskName = "ActivityWatch Fleet Server"
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startScript = Join-Path $InstallDir "start-server.ps1"
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

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
        -Description "Start ActivityWatch Fleet Server on boot." `
        -Force | Out-Null

    if (-not $NoStart) {
        Start-ScheduledTask -TaskName $taskName
    }
}

Write-Host "ActivityWatch Fleet Server installed to $InstallDir"
Write-Host "Runtime data root: $runtimeRoot"
Write-Host "Web UI: http://192.168.0.144:5600/"
