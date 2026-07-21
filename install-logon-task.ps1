param(
    [switch]$CentralMode,
    [string]$TaskName = "ActivityWatch Stack",
    [switch]$StartNow
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot "restart-stack.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "restart-stack.ps1 not found at $scriptPath"
}

$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) {
    $pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$userId = if ($env:USERDOMAIN) {
    "$($env:USERDOMAIN)\$($env:USERNAME)"
} else {
    $env:USERNAME
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-WindowStyle", "Hidden",
    "-File", ('"{0}"' -f $scriptPath)
)
if ($CentralMode) {
    $args += "-CentralMode"
}

$action = New-ScheduledTaskAction -Execute $pwsh -Argument ($args -join " ")
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Restart the repo-managed ActivityWatch stack at user logon." `
    -Force | Out-Null

Write-Host ("Installed scheduled task '{0}' for {1}" -f $TaskName, $userId) -ForegroundColor Green
Write-Host ("Command: {0} {1}" -f $pwsh, ($args -join " ")) -ForegroundColor Gray

if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Started scheduled task immediately." -ForegroundColor Green
}
