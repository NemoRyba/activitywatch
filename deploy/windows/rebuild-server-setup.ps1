param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600,
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$webuiDir = Join-Path $repoRoot "aw-server\aw-webui"
$webuiDist = Join-Path $webuiDir "dist"
$serverDir = Join-Path $repoRoot "aw-server"
$serverStatic = Join-Path $serverDir "aw_server\static"
$serverSetup = Join-Path $repoRoot "dist\deployment\ActivityWatch-Fleet-Server-Setup.exe"
$buildHome = Join-Path $repoRoot ".pyinstaller-home"

function Assert-UnderRepo {
    param([string]$Path)

    $resolved = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { [IO.Path]::GetFullPath($Path) }
    if (-not $resolved.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside repo: $resolved"
    }
}

function Clear-SetupOutput {
    param([string]$Path)

    Assert-UnderRepo $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "No previous server setup exe present."
        return
    }

    $holders = Get-Process | Where-Object { $_.Path -and $_.Path -ieq $Path }
    if ($holders) {
        $names = ($holders | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ", "
        Write-Host "Stopping process using the setup exe: $names"
        $holders | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    & attrib.exe -R -S -H $Path 2>$null | Out-Null
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Removed previous server setup exe."
        return
    }

    Write-Host "Still locked - taking ownership..."
    & takeown.exe /F $Path | Out-Null
    & icacls.exe $Path /grant "*S-1-5-32-544:F" | Out-Null
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Removed previous server setup exe after takeown."
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $parked = "$Path.old-$stamp"
    Write-Host "Delete still refused - renaming to $(Split-Path -Leaf $parked)"
    Move-Item -LiteralPath $Path -Destination $parked -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        throw "Could not remove or rename the old server setup exe. It may be held by antivirus, Explorer preview, or a sync client."
    }
}

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "=== $Title ==="
    & $Action
}

function Assert-NativeSuccess {
    param([string]$What)

    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE"
    }
}

function Resolve-PythonExe {
    if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
        return [IO.Path]::GetFullPath($PythonExe)
    }

    $venvPython = Join-Path $repoRoot ".venv-build\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
        return $venvPython
    }

    return (Get-Command python.exe -ErrorAction Stop).Source
}

Assert-UnderRepo $webuiDir
Assert-UnderRepo $serverDir
Assert-UnderRepo $serverStatic
Assert-UnderRepo $serverSetup

Invoke-Step "1/6 Clear previous server setup" {
    Clear-SetupOutput -Path $serverSetup
}

Invoke-Step "2/6 Build web UI" {
    $npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
    if (-not $npm) {
        $npm = (Get-Command npm -ErrorAction Stop).Source
    }

    $previousGitConfigCount = $env:GIT_CONFIG_COUNT
    $previousGitConfigKey0 = $env:GIT_CONFIG_KEY_0
    $previousGitConfigValue0 = $env:GIT_CONFIG_VALUE_0
    $env:GIT_CONFIG_COUNT = "1"
    $env:GIT_CONFIG_KEY_0 = "safe.directory"
    $env:GIT_CONFIG_VALUE_0 = $webuiDir

    Push-Location $webuiDir
    try {
        & $npm run build
        Assert-NativeSuccess "Web UI build"
    } finally {
        Pop-Location
        $env:GIT_CONFIG_COUNT = $previousGitConfigCount
        $env:GIT_CONFIG_KEY_0 = $previousGitConfigKey0
        $env:GIT_CONFIG_VALUE_0 = $previousGitConfigValue0
    }
}

Invoke-Step "3/6 Copy web UI into server static assets" {
    if (-not (Test-Path -LiteralPath $webuiDist)) {
        throw "Missing web UI build output: $webuiDist"
    }

    Assert-UnderRepo $serverStatic
    if (Test-Path -LiteralPath $serverStatic) {
        Remove-Item -LiteralPath $serverStatic -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $serverStatic | Out-Null
    Copy-Item -Path (Join-Path $webuiDist "*") -Destination $serverStatic -Recurse -Force
}

Invoke-Step "4/6 Stage watcher package for auto-update" {
    # Embed the most recently built watcher setup contents into the server so
    # admins can roll them out fleet-wide from the web GUI (watcher auto-update).
    $watchersIexpress = Join-Path $repoRoot "dist\deployment\watchers-iexpress"
    $packageDir = Join-Path $serverDir "aw_server\watcher_package"
    Assert-UnderRepo $packageDir

    $sourceFiles = @("payload.zip", "install-watchers.ps1", "manifest.json") |
        ForEach-Object { Join-Path $watchersIexpress $_ }
    $missing = @($sourceFiles | Where-Object { -not (Test-Path -LiteralPath $_) })

    if ($missing.Count -eq 0) {
        if (Test-Path -LiteralPath $packageDir) {
            Remove-Item -LiteralPath $packageDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
        foreach ($file in $sourceFiles) {
            Copy-Item -LiteralPath $file -Destination $packageDir -Force
        }
        $stagedManifest = Get-Content -LiteralPath (Join-Path $packageDir "manifest.json") -Raw | ConvertFrom-Json
        Write-Host "Embedded watcher package version: $($stagedManifest.version)"
    } elseif (Test-Path -LiteralPath (Join-Path $packageDir "manifest.json")) {
        $stagedManifest = Get-Content -LiteralPath (Join-Path $packageDir "manifest.json") -Raw | ConvertFrom-Json
        Write-Host "WARNING: dist\deployment\watchers-iexpress is missing or incomplete." -ForegroundColor Yellow
        Write-Host "         Re-using the previously staged watcher package (version $($stagedManifest.version))." -ForegroundColor Yellow
        Write-Host "         Run rebuild-watchers-setup.cmd first to embed the latest watcher build." -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: no watcher package available (run rebuild-watchers-setup.cmd first)." -ForegroundColor Yellow
        Write-Host "         The server is built WITHOUT an embedded watcher package;" -ForegroundColor Yellow
        Write-Host "         the watcher auto-update page will show 'no package'." -ForegroundColor Yellow
    }
}

Invoke-Step "5/6 Build PyInstaller server payload" {
    $python = Resolve-PythonExe
    Write-Host "Using Python: $python"

    New-Item -ItemType Directory -Force -Path `
        $buildHome,
        (Join-Path $buildHome "AppData\Roaming"),
        (Join-Path $buildHome "AppData\Local"),
        (Join-Path $buildHome "Temp"),
        (Join-Path $buildHome "PyInstaller") | Out-Null

    $env:USERPROFILE = $buildHome
    $env:HOME = $buildHome
    $env:APPDATA = Join-Path $buildHome "AppData\Roaming"
    $env:LOCALAPPDATA = Join-Path $buildHome "AppData\Local"
    $env:TEMP = Join-Path $buildHome "Temp"
    $env:TMP = $env:TEMP
    $env:PYTHONNOUSERSITE = "1"
    $env:PYINSTALLER_CONFIG_DIR = Join-Path $buildHome "PyInstaller"

    Push-Location $serverDir
    try {
        & $python -m PyInstaller aw-server.spec --clean --noconfirm
        Assert-NativeSuccess "PyInstaller server build"
    } finally {
        Pop-Location
    }
}

Invoke-Step "6/6 Build server setup exe" {
    & (Join-Path $PSScriptRoot "build-setup.ps1") `
        -ServerHost $ServerHost `
        -ServerPort $ServerPort `
        -Target Server
    Assert-NativeSuccess "Server setup build"
}

if (-not (Test-Path -LiteralPath $serverSetup)) {
    throw "Build finished but the expected server setup is missing: $serverSetup"
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $serverSetup
$file = Get-Item -LiteralPath $serverSetup
Write-Host ""
Write-Host "BUILD OK"
Write-Host "  $($file.FullName)"
Write-Host "  $($file.Length) bytes"
Write-Host "  SHA256 $($hash.Hash)"
