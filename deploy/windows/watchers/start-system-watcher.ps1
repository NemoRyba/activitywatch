param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600
)

$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path ${env:ProgramData} "ActivityWatchFleet"
$logsDir = Join-Path $runtimeRoot "logs\watchers"
$pidsDir = Join-Path $runtimeRoot "pids"
$exe = Join-Path $installDir "aw-watcher-system\aw-watcher-system.exe"
$pidFile = Join-Path $pidsDir "aw-watcher-system.pid"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsDir, $pidsDir | Out-Null

if (-not (Test-Path $exe)) {
    throw "aw-watcher-system executable not found at $exe"
}

if (Test-Path $pidFile) {
    $existingPid = [int](Get-Content $pidFile -Raw)
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
    if ($existing -and [string]::Equals($existing.ExecutablePath, $exe, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "aw-watcher-system already running as PID $existingPid"
        exit 0
    }
}

$env:LOCALAPPDATA = $runtimeRoot
$arguments = @(
    "--host", $ServerHost,
    "--port", [string]$ServerPort,
    "--central-mode",
    "--username", "system",
    "--session-id", "machine",
    "--session-type", "machine"
)

$process = Start-Process `
    -FilePath $exe `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $exe) `
    -RedirectStandardOutput (Join-Path $logsDir "aw-watcher-system.out.log") `
    -RedirectStandardError (Join-Path $logsDir "aw-watcher-system.err.log") `
    -WindowStyle Hidden `
    -PassThru

Set-Content -Path $pidFile -Value $process.Id
Write-Host "Started aw-watcher-system PID $($process.Id)"
