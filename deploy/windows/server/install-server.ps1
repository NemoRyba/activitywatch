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

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files, creates a startup task, and opens firewall port 5600."
    exit 1
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-server.ps1"
}

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
