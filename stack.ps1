param(
    [ValidateSet("start", "stop", "restart", "status")]
    [string]$Action = "status",
    [switch]$CentralMode
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $RepoRoot ".aw-stack"
$LogsDir = Join-Path $RuntimeDir "logs"
$PidsDir = Join-Path $RuntimeDir "pids"

$VenvPath = Join-Path $RepoRoot ".venv"
$ScriptsPath = Join-Path $VenvPath "Scripts"
$PythonExe = Join-Path $ScriptsPath "python.exe"
$ServerExe = Join-Path $ScriptsPath "aw-server.exe"
$AfkExe = Join-Path $ScriptsPath "aw-watcher-afk.exe"
$WindowExe = Join-Path $ScriptsPath "aw-watcher-window.exe"
$SessionDir = Join-Path $RepoRoot "aw-watcher-session"

$StaticDir = Join-Path $RepoRoot "aw-server\aw_server\static"
$DistDir = Join-Path $RepoRoot "aw-server\aw-webui\dist"

New-Item -ItemType Directory -Force $RuntimeDir, $LogsDir, $PidsDir | Out-Null

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Get-PidFile {
    param([string]$Key)
    return (Join-Path $PidsDir "$Key.json")
}

function Save-PidInfo {
    param(
        [hashtable]$Component,
        [System.Diagnostics.Process]$Process
    )

    $payload = @{
        key = $Component.Key
        name = $Component.Display
        pid = $Process.Id
        started_at = (Get-Date).ToString("o")
        file_path = $Component.FilePath
        working_directory = $Component.WorkingDirectory
    } | ConvertTo-Json

    Set-Content -Path (Get-PidFile $Component.Key) -Value $payload
}

function Read-PidInfo {
    param([string]$Key)

    $path = Get-PidFile $Key
    if (-not (Test-Path $path)) {
        return $null
    }

    try {
        return Get-Content $path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Remove-PidInfo {
    param([string]$Key)
    $path = Get-PidFile $Key
    if (Test-Path $path) {
        Remove-Item $path -Force
    }
}

function Get-AliveProcess {
    param([int]$ProcessId)
    return Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
}

function Ensure-Environment {
    if (-not (Test-Path $VenvPath)) {
        throw "Virtual environment not found at $VenvPath"
    }

    foreach ($path in @($PythonExe, $ServerExe, $AfkExe, $WindowExe)) {
        if (-not (Test-Path $path)) {
            throw "Required executable not found: $path"
        }
    }

    if (-not (Test-Path $SessionDir)) {
        throw "Session watcher directory not found: $SessionDir"
    }
}

function Sync-WebUi {
    if (Test-Path (Join-Path $DistDir "index.html")) {
        New-Item -ItemType Directory -Force $StaticDir | Out-Null
        Copy-Item -Path (Join-Path $DistDir "*") -Destination $StaticDir -Recurse -Force
        Write-Host "[OK] Synced aw-webui build into aw-server\aw_server\static" -ForegroundColor Green
        return
    }

    if (-not (Test-Path (Join-Path $StaticDir "index.html"))) {
        throw "No built web UI found in $DistDir or $StaticDir"
    }
}

function Build-Components {
    $watcherArgs = @()
    if ($CentralMode) {
        $watcherArgs += "--central-mode"
    }

    return @(
        @{
            Key = "server"
            Display = "aw-server"
            FilePath = $PythonExe
            ArgumentList = @("-m", "aw_server", "--host", "127.0.0.1", "--port", "5600")
            WorkingDirectory = $RepoRoot
            StdOut = Join-Path $LogsDir "server.out.log"
            StdErr = Join-Path $LogsDir "server.err.log"
            ProcessMatcher = {
                param($p)
                return (
                    ($p.Name -ieq "aw-server.exe" -and $p.ExecutablePath -and ([string]::Equals($p.ExecutablePath, $ServerExe, [System.StringComparison]::OrdinalIgnoreCase))) -or
                    ($p.Name -match "^python" -and $p.CommandLine -and $p.CommandLine -match "(^|\\s)-m\\s+aw_server(\\s|$)")
                )
            }
            ShellMatcher = {
                param($p)
                return $p.CommandLine -and ($p.CommandLine -match [regex]::Escape("aw-server.exe") -or $p.CommandLine -match "(^|\\s)-m\\s+aw_server(\\s|$)")
            }
        },
        @{
            Key = "afk"
            Display = "aw-watcher-afk"
            FilePath = $PythonExe
            ArgumentList = @("-m", "aw_watcher_afk") + $watcherArgs
            WorkingDirectory = $RepoRoot
            StdOut = Join-Path $LogsDir "afk.out.log"
            StdErr = Join-Path $LogsDir "afk.err.log"
            ProcessMatcher = {
                param($p)
                return (
                    ($p.Name -ieq "aw-watcher-afk.exe" -and $p.ExecutablePath -and ([string]::Equals($p.ExecutablePath, $AfkExe, [System.StringComparison]::OrdinalIgnoreCase))) -or
                    ($p.Name -match "^python" -and $p.CommandLine -and $p.CommandLine -match "(^|\\s)-m\\s+aw_watcher_afk(\\s|$)")
                )
            }
            ShellMatcher = {
                param($p)
                return $p.CommandLine -and ($p.CommandLine -match [regex]::Escape("aw-watcher-afk.exe") -or $p.CommandLine -match "(^|\\s)-m\\s+aw_watcher_afk(\\s|$)")
            }
        },
        @{
            Key = "window"
            Display = "aw-watcher-window"
            FilePath = $PythonExe
            ArgumentList = @("-m", "aw_watcher_window") + $watcherArgs
            WorkingDirectory = $RepoRoot
            StdOut = Join-Path $LogsDir "window.out.log"
            StdErr = Join-Path $LogsDir "window.err.log"
            ProcessMatcher = {
                param($p)
                return (
                    ($p.Name -ieq "aw-watcher-window.exe" -and $p.ExecutablePath -and ([string]::Equals($p.ExecutablePath, $WindowExe, [System.StringComparison]::OrdinalIgnoreCase))) -or
                    ($p.Name -match "^python" -and $p.CommandLine -and $p.CommandLine -match "(^|\\s)-m\\s+aw_watcher_window(\\s|$)")
                )
            }
            ShellMatcher = {
                param($p)
                return $p.CommandLine -and ($p.CommandLine -match [regex]::Escape("aw-watcher-window.exe") -or $p.CommandLine -match "(^|\\s)-m\\s+aw_watcher_window(\\s|$)")
            }
        },
        @{
            Key = "session"
            Display = "aw-watcher-session"
            FilePath = $PythonExe
            ArgumentList = @("-m", "aw_watcher_session") + $watcherArgs
            WorkingDirectory = $SessionDir
            StdOut = Join-Path $LogsDir "session.out.log"
            StdErr = Join-Path $LogsDir "session.err.log"
            ProcessMatcher = {
                param($p)
                return $p.Name -match "^python" -and $p.CommandLine -and $p.CommandLine -match "aw_watcher_session"
            }
            ShellMatcher = {
                param($p)
                return $p.CommandLine -and $p.CommandLine -match "aw_watcher_session"
            }
        }
    )
}

function Stop-Component {
    param([hashtable]$Component)

    $pidInfo = Read-PidInfo $Component.Key
    if ($pidInfo -and $pidInfo.pid) {
        $proc = Get-AliveProcess -ProcessId ([int]$pidInfo.pid)
        if ($proc) {
            Write-Host "Stopping $($Component.Display) (PID $($proc.Id))" -ForegroundColor Yellow
            Stop-Process -Id $proc.Id -Force
            Start-Sleep -Milliseconds 300
        }
    }
    Remove-PidInfo $Component.Key
}

function Stop-StrayProcesses {
    param([hashtable[]]$Components)

    $processes = Get-CimInstance Win32_Process

    foreach ($component in $Components) {
        $matches = $processes | Where-Object { & $component.ProcessMatcher $_ }
        foreach ($match in $matches) {
            try {
                Write-Host "Stopping stray $($component.Display) (PID $($match.ProcessId))" -ForegroundColor Yellow
                Stop-Process -Id $match.ProcessId -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }

    $shells = $processes | Where-Object {
        $_.Name -in @("powershell.exe", "pwsh.exe", "cmd.exe")
    }
    foreach ($shell in $shells) {
        $shouldStop = $false
        foreach ($component in $Components) {
            if (& $component.ShellMatcher $shell) {
                $shouldStop = $true
                break
            }
        }
        if ($shouldStop) {
            try {
                Write-Host "Closing stale shell wrapper (PID $($shell.ProcessId))" -ForegroundColor DarkYellow
                Stop-Process -Id $shell.ProcessId -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }
}

function Find-ComponentProcesses {
    param([hashtable]$Component)
    $processes = Get-CimInstance Win32_Process
    return $processes | Where-Object { & $Component.ProcessMatcher $_ }
}

function Start-Component {
    param([hashtable]$Component)

    foreach ($log in @($Component.StdOut, $Component.StdErr)) {
        if (Test-Path $log) {
            Remove-Item $log -Force
        }
    }

    $process = Start-Process `
        -FilePath $Component.FilePath `
        -ArgumentList $Component.ArgumentList `
        -WorkingDirectory $Component.WorkingDirectory `
        -RedirectStandardOutput $Component.StdOut `
        -RedirectStandardError $Component.StdErr `
        -WindowStyle Hidden `
        -PassThru

    Save-PidInfo -Component $Component -Process $process
    Write-Host "Started $($Component.Display) (PID $($process.Id))" -ForegroundColor Green
}

function Wait-ForHttp {
    param(
        [string]$Uri,
        [int]$TimeoutSec = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 3
            return $response
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    return $null
}

function Invoke-StopStack {
    param([hashtable[]]$Components)

    Write-Section "Stopping ActivityWatch Stack"
    foreach ($component in $Components) {
        Stop-Component -Component $component
    }
    Stop-StrayProcesses -Components $Components
    Write-Host "Stack stopped." -ForegroundColor Green
}

function Invoke-StartStack {
    param([hashtable[]]$Components)

    Ensure-Environment
    Sync-WebUi

    Write-Section "Starting ActivityWatch Stack"
    Start-Component -Component $Components[0]

    $api = Wait-ForHttp -Uri "http://127.0.0.1:5600/api/0/info" -TimeoutSec 30
    if (-not $api) {
        throw "aw-server did not become ready on http://127.0.0.1:5600/api/0/info"
    }
    Write-Host "[OK] Server is responding" -ForegroundColor Green

    foreach ($component in $Components[1..($Components.Count - 1)]) {
        Start-Component -Component $component
    }

    Start-Sleep -Seconds 2
    $web = Wait-ForHttp -Uri "http://127.0.0.1:5600/" -TimeoutSec 10
    if ($web) {
        Write-Host "[OK] Web UI is responding at http://127.0.0.1:5600/" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Web UI did not answer yet. Check $LogsDir" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Logs:" -ForegroundColor Cyan
    Write-Host "  $LogsDir" -ForegroundColor Gray
    Show-Status -Components $Components
}

function Show-Status {
    param([hashtable[]]$Components)

    Write-Section "ActivityWatch Stack Status"
    foreach ($component in $Components) {
        $pidInfo = Read-PidInfo $component.Key
        if ($pidInfo -and $pidInfo.pid) {
            $proc = Get-AliveProcess -ProcessId ([int]$pidInfo.pid)
            if ($proc) {
                Write-Host ("[RUNNING] {0,-18} PID {1}" -f $component.Display, $proc.Id) -ForegroundColor Green
                continue
            }
        }

        $matches = Find-ComponentProcesses -Component $component
        if ($matches) {
            $first = @($matches)[0]
            Write-Host ("[RUNNING] {0,-18} PID {1} (untracked)" -f $component.Display, $first.ProcessId) -ForegroundColor DarkGreen
        } else {
            Write-Host ("[STOPPED] {0}" -f $component.Display) -ForegroundColor Yellow
        }
    }

    $info = Wait-ForHttp -Uri "http://127.0.0.1:5600/api/0/info" -TimeoutSec 2
    if ($info) {
        Write-Host ""
        Write-Host "API:     http://127.0.0.1:5600/api/0/info" -ForegroundColor Green
        Write-Host "Web UI:  http://127.0.0.1:5600/" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "API/Web UI are not responding on http://127.0.0.1:5600" -ForegroundColor Yellow
    }
}

$Components = Build-Components

switch ($Action) {
    "stop" {
        Invoke-StopStack -Components $Components
    }
    "start" {
        Invoke-StartStack -Components $Components
    }
    "restart" {
        Invoke-StopStack -Components $Components
        Invoke-StartStack -Components $Components
    }
    "status" {
        Show-Status -Components $Components
    }
}
