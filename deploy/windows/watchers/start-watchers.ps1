param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600
)

$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $installDir "watchers.config.psd1"
$runtimeRoot = Join-Path ${env:LOCALAPPDATA} "ActivityWatchFleet"
$logsDir = Join-Path $runtimeRoot "logs\watchers"
$pidsDir = Join-Path $runtimeRoot "pids"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsDir, $pidsDir | Out-Null

function Get-SelectedWatcherKeys {
    $defaultWatchers = @("afk", "window", "session", "audio", "system")
    if (-not (Test-Path $configPath)) {
        return $defaultWatchers
    }

    try {
        $config = Import-PowerShellDataFile -Path $configPath
        if ($config.SelectedWatchers -and $config.SelectedWatchers.Count -gt 0) {
            return @($config.SelectedWatchers)
        }
    } catch {
        Write-Warning "Could not read watcher selection config at $configPath`: $($_.Exception.Message)"
    }

    return $defaultWatchers
}

function Start-Watcher {
    param(
        [string]$Key,
        [string]$ExeRelativePath,
        [string[]]$Arguments
    )

    $exe = Join-Path $installDir $ExeRelativePath
    if (-not (Test-Path $exe)) {
        throw "$Key executable not found at $exe"
    }

    $currentSessionId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").SessionId
    $existingInSession = Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and
        [string]::Equals($_.ExecutablePath, $exe, [System.StringComparison]::OrdinalIgnoreCase) -and
        $_.SessionId -eq $currentSessionId
    } | Select-Object -First 1

    if ($existingInSession) {
        Set-Content -Path (Join-Path $pidsDir "$Key.pid") -Value $existingInSession.ProcessId
        Write-Host "$Key already running in session $currentSessionId as PID $($existingInSession.ProcessId)"
        return
    }

    $pidFile = Join-Path $pidsDir "$Key.pid"
    if (Test-Path $pidFile) {
        $existingPid = [int](Get-Content $pidFile -Raw)
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
        if (
            $existing -and
            [string]::Equals($existing.ExecutablePath, $exe, [System.StringComparison]::OrdinalIgnoreCase) -and
            $existing.SessionId -eq $currentSessionId
        ) {
            Write-Host "$Key already running as PID $existingPid"
            return
        }
    }

    $process = Start-Process `
        -FilePath $exe `
        -ArgumentList $Arguments `
        -WorkingDirectory (Split-Path -Parent $exe) `
        -RedirectStandardOutput (Join-Path $logsDir "$Key.out.log") `
        -RedirectStandardError (Join-Path $logsDir "$Key.err.log") `
        -WindowStyle Hidden `
        -PassThru

    Set-Content -Path $pidFile -Value $process.Id
    Write-Host "Started $Key PID $($process.Id)"
}

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

$commonArgs = @("--host", $ServerHost, "--port", [string]$ServerPort, "--central-mode")
$selectedWatchers = Get-SelectedWatcherKeys
$userWatchers = @(
    [pscustomobject]@{
        Key = "afk"
        ProcessKey = "aw-watcher-afk"
        ExeRelativePath = "aw-watcher-afk\aw-watcher-afk.exe"
    },
    [pscustomobject]@{
        Key = "window"
        ProcessKey = "aw-watcher-window"
        ExeRelativePath = "aw-watcher-window\aw-watcher-window.exe"
    },
    [pscustomobject]@{
        Key = "session"
        ProcessKey = "aw-watcher-session"
        ExeRelativePath = "aw-watcher-session\aw-watcher-session.exe"
    },
    [pscustomobject]@{
        Key = "audio"
        ProcessKey = "aw-watcher-audio"
        ExeRelativePath = "aw-watcher-audio\aw-watcher-audio.exe"
    }
)

$startedAny = $false
foreach ($watcher in $userWatchers) {
    if ($selectedWatchers -notcontains $watcher.Key) {
        continue
    }

    Start-Watcher `
        -Key $watcher.ProcessKey `
        -ExeRelativePath $watcher.ExeRelativePath `
        -Arguments $commonArgs
    $startedAny = $true
}

if (-not $startedAny) {
    Write-Host "No per-user watchers selected; nothing to start."
}
