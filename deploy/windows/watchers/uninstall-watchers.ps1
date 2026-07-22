param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers")
)

$ErrorActionPreference = "Stop"

$supervisorTaskName = "ActivityWatch Fleet Watchers Supervisor"
Unregister-ScheduledTask -TaskName $supervisorTaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "ActivityWatch Fleet System Watcher" -Confirm:$false -ErrorAction SilentlyContinue

$startupDir = [Environment]::GetFolderPath("CommonStartup")
$shortcutPath = Join-Path $startupDir "ActivityWatch Fleet Watchers.lnk"
if (Test-Path $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}

$stopScript = Join-Path $InstallDir "stop-watchers.ps1"
if (Test-Path $stopScript) {
    & $stopScript
}

if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}

Write-Host "ActivityWatch Fleet Watchers uninstalled. Per-user offline queues/logs under LOCALAPPDATA are left in place."
