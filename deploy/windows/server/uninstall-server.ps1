param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Server"),
    [switch]$RemoveData
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

$runtimeRoot = Get-ConfiguredRuntimeRoot -InstallDir $InstallDir

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
    if (Test-Path $runtimeRoot) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
    }

    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force
    }
}

Write-Host "ActivityWatch Fleet Server uninstalled."
