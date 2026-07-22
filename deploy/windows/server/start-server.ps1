param(
    [string]$HostName = "0.0.0.0",
    [int]$Port = 5600
)

$ErrorActionPreference = "Stop"

$registryPath = "HKLM:\Software\ActivityWatchFleet"
$dataRootFileName = "data-root.txt"

function Get-DefaultRuntimeRoot {
    return (Join-Path ${env:ProgramData} "ActivityWatchFleet")
}

function Normalize-DataRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Get-DefaultRuntimeRoot)
    }

    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
}

function Get-ConfiguredRuntimeRoot {
    param([string]$InstallDir)

    try {
        $registryValue = (Get-ItemProperty -Path $registryPath -Name DataRoot -ErrorAction Stop).DataRoot
        if (-not [string]::IsNullOrWhiteSpace($registryValue)) {
            return (Normalize-DataRoot $registryValue)
        }
    } catch {
        # Fresh installs and older packages do not have the registry value yet.
    }

    $configFile = Join-Path $InstallDir $dataRootFileName
    if (Test-Path $configFile) {
        $fileValue = Get-Content -Path $configFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
            return (Normalize-DataRoot $fileValue)
        }
    }

    return (Get-DefaultRuntimeRoot)
}

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Get-ConfiguredRuntimeRoot -InstallDir $installDir
$logsDir = Join-Path $runtimeRoot "logs\server"
$pidsDir = Join-Path $runtimeRoot "pids"
$serverExe = Join-Path $installDir "aw-server\aw-server.exe"
$pidFile = Join-Path $pidsDir "server.pid"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsDir, $pidsDir | Out-Null

if (-not (Test-Path $serverExe)) {
    throw "aw-server.exe not found at $serverExe"
}

if (Test-Path $pidFile) {
    $existingPid = [int](Get-Content $pidFile -Raw)
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
    if ($existing -and [string]::Equals($existing.ExecutablePath, $serverExe, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "ActivityWatch Fleet Server is already running as PID $existingPid"
        exit 0
    }
}

$env:LOCALAPPDATA = $runtimeRoot
$arguments = @("--host", $HostName, "--port", [string]$Port)
$process = Start-Process `
    -FilePath $serverExe `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $serverExe) `
    -RedirectStandardOutput (Join-Path $logsDir "server.out.log") `
    -RedirectStandardError (Join-Path $logsDir "server.err.log") `
    -WindowStyle Hidden `
    -PassThru

Set-Content -Path $pidFile -Value $process.Id
Write-Host "Started ActivityWatch Fleet Server PID $($process.Id)"
Write-Host "Listening on http://192.168.0.144:5600/ via host bind $HostName"
