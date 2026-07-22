$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverExe = Join-Path $installDir "aw-server\aw-server.exe"
$processes = Get-CimInstance Win32_Process | Where-Object {
    [string]::Equals($_.ExecutablePath, $serverExe, [System.StringComparison]::OrdinalIgnoreCase)
}

foreach ($process in $processes) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped ActivityWatch Fleet Server PID $($process.ProcessId)"
}
