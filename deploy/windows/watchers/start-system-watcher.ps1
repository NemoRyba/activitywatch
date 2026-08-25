param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600
)

$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $installDir "watchers.config.psd1"
$runtimeRoot = Join-Path ${env:ProgramData} "ActivityWatchFleet"
$logsDir = Join-Path $runtimeRoot "logs\watchers"
$pidsDir = Join-Path $runtimeRoot "pids"
$exe = Join-Path $installDir "aw-watcher-system\aw-watcher-system.exe"
$pidFile = Join-Path $pidsDir "aw-watcher-system.pid"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsDir, $pidsDir | Out-Null

function Test-SystemWatcherSelected {
    if (-not (Test-Path $configPath)) {
        return $true
    }

    try {
        $config = Import-PowerShellDataFile -Path $configPath
        return @($config.SelectedWatchers) -contains "system"
    } catch {
        Write-Warning "Could not read watcher selection config at $configPath`: $($_.Exception.Message)"
        return $true
    }
}

if (-not (Test-SystemWatcherSelected)) {
    Write-Host "CPU/RAM system watcher was not selected; nothing to start."
    exit 0
}

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
function Resolve-FleetServer {
    <#
      Honour a server move announced through the admin GUI.

      $ServerHost/$ServerPort are baked in at build time, but an admin can move
      the server to another machine and announce the new address; the
      supervisor verifies it and stores it here. This file lives outside the
      install directory, so a watcher update cannot lose it.
    #>
    param([string]$FallbackHost, [int]$FallbackPort)

    $endpointFile = Join-Path $env:ProgramData "ActivityWatchFleet\server-endpoint.txt"
    if (Test-Path $endpointFile) {
        try {
            $stored = (Get-Content -Path $endpointFile -Raw).Trim()
            if ($stored -match '^https?://') {
                $uri = [uri]$stored
                $port = if ($uri.IsDefaultPort -and $stored -notmatch ':\d+/?$') { $FallbackPort } else { $uri.Port }
                return [pscustomobject]@{ Host = $uri.Host; Port = [int]$port }
            }
        } catch { }
    }
    return [pscustomobject]@{ Host = $FallbackHost; Port = [int]$FallbackPort }
}

$fleetServer = Resolve-FleetServer -FallbackHost $ServerHost -FallbackPort $ServerPort
$ServerHost = $fleetServer.Host
$ServerPort = $fleetServer.Port

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
