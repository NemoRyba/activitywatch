param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Server"),
    [switch]$RemoveData
)

$ErrorActionPreference = "Stop"

Unregister-ScheduledTask -TaskName "ActivityWatch Fleet Server" -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "ActivityWatch Fleet Server 5600" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

$stopScript = Join-Path $InstallDir "stop-server.ps1"
if (Test-Path $stopScript) {
    & $stopScript
}

if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}

if ($RemoveData) {
    $runtimeRoot = Join-Path ${env:ProgramData} "ActivityWatchFleet"
    if (Test-Path $runtimeRoot) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
    }
}

Write-Host "ActivityWatch Fleet Server uninstalled."
