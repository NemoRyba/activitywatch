$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$watchers = @(
    Join-Path $installDir "aw-watcher-afk\aw-watcher-afk.exe",
    Join-Path $installDir "aw-watcher-window\aw-watcher-window.exe",
    Join-Path $installDir "aw-watcher-session\aw-watcher-session.exe",
    Join-Path $installDir "aw-watcher-audio\aw-watcher-audio.exe",
    Join-Path $installDir "aw-watcher-system\aw-watcher-system.exe"
)

$processes = Get-CimInstance Win32_Process | Where-Object {
    $path = $_.ExecutablePath
    $watchers | Where-Object { [string]::Equals($_, $path, [System.StringComparison]::OrdinalIgnoreCase) }
}

foreach ($process in $processes) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped watcher PID $($process.ProcessId)"
}
