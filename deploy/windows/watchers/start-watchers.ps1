param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600
)

$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path ${env:LOCALAPPDATA} "ActivityWatchFleet"
$logsDir = Join-Path $runtimeRoot "logs\watchers"
$pidsDir = Join-Path $runtimeRoot "pids"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsDir, $pidsDir | Out-Null

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

$commonArgs = @("--host", $ServerHost, "--port", [string]$ServerPort, "--central-mode")
Start-Watcher -Key "aw-watcher-afk" -ExeRelativePath "aw-watcher-afk\aw-watcher-afk.exe" -Arguments $commonArgs
Start-Watcher -Key "aw-watcher-window" -ExeRelativePath "aw-watcher-window\aw-watcher-window.exe" -Arguments $commonArgs
Start-Watcher -Key "aw-watcher-session" -ExeRelativePath "aw-watcher-session\aw-watcher-session.exe" -Arguments $commonArgs
Start-Watcher -Key "aw-watcher-audio" -ExeRelativePath "aw-watcher-audio\aw-watcher-audio.exe" -Arguments $commonArgs
