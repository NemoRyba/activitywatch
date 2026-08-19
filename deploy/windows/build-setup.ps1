param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$distRoot = Join-Path $repoRoot "dist\deployment"
$serverPayload = Join-Path $distRoot "server-payload"
$watchersPayload = Join-Path $distRoot "watchers-payload"
$serverIexpress = Join-Path $distRoot "server-iexpress"
$watchersIexpress = Join-Path $distRoot "watchers-iexpress"

function Assert-UnderRepo {
    param([string]$Path)
    $resolved = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { [IO.Path]::GetFullPath($Path) }
    if (-not $resolved.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside repo: $resolved"
    }
}

Assert-UnderRepo $distRoot
if (Test-Path $distRoot) {
    Remove-Item -LiteralPath $distRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $serverPayload, $watchersPayload, $serverIexpress, $watchersIexpress | Out-Null

$requiredDirs = @(
    "aw-server\dist\aw-server",
    "aw-watcher-afk\dist\aw-watcher-afk",
    "aw-watcher-window\dist\aw-watcher-window",
    "aw-watcher-session\dist\aw-watcher-session",
    "aw-watcher-audio\dist\aw-watcher-audio",
    "aw-watcher-system\dist\aw-watcher-system"
)
foreach ($dir in $requiredDirs) {
    $path = Join-Path $repoRoot $dir
    if (-not (Test-Path $path)) {
        throw "Missing built distribution: $path"
    }
}

Copy-Item -Path (Join-Path $repoRoot "aw-server\dist\aw-server") -Destination (Join-Path $serverPayload "aw-server") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "server\start-server.ps1") -Destination $serverPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "server\stop-server.ps1") -Destination $serverPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "server\uninstall-server.ps1") -Destination $serverPayload -Force

Copy-Item -Path (Join-Path $repoRoot "aw-watcher-afk\dist\aw-watcher-afk") -Destination (Join-Path $watchersPayload "aw-watcher-afk") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "aw-watcher-window\dist\aw-watcher-window") -Destination (Join-Path $watchersPayload "aw-watcher-window") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "aw-watcher-session\dist\aw-watcher-session") -Destination (Join-Path $watchersPayload "aw-watcher-session") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "aw-watcher-audio\dist\aw-watcher-audio") -Destination (Join-Path $watchersPayload "aw-watcher-audio") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "aw-watcher-system\dist\aw-watcher-system") -Destination (Join-Path $watchersPayload "aw-watcher-system") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\start-watchers.ps1") -Destination $watchersPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\supervise-watchers.ps1") -Destination $watchersPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\start-system-watcher.ps1") -Destination $watchersPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\stop-watchers.ps1") -Destination $watchersPayload -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\uninstall-watchers.ps1") -Destination $watchersPayload -Force

function Update-DeploymentScriptDefaults {
    param([string]$Path)

    (Get-Content $Path -Raw).
        Replace("192.168.0.144", $ServerHost).
        Replace("5600", [string]$ServerPort) |
        Set-Content -Path $Path
}

foreach ($scriptName in @("start-server.ps1", "uninstall-server.ps1")) {
    $scriptPath = Join-Path $serverPayload $scriptName
    Update-DeploymentScriptDefaults -Path $scriptPath
}

Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "start-watchers.ps1")
Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "start-system-watcher.ps1")

Compress-Archive -Path (Join-Path $serverPayload "*") -DestinationPath (Join-Path $serverIexpress "payload.zip") -Force
Compress-Archive -Path (Join-Path $watchersPayload "*") -DestinationPath (Join-Path $watchersIexpress "payload.zip") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "server\install-server.ps1") -Destination $serverIexpress -Force
Copy-Item -Path (Join-Path $PSScriptRoot "watchers\install-watchers.ps1") -Destination $watchersIexpress -Force
Update-DeploymentScriptDefaults -Path (Join-Path $serverIexpress "install-server.ps1")
Update-DeploymentScriptDefaults -Path (Join-Path $watchersIexpress "install-watchers.ps1")

function New-IExpressSed {
    param(
        [string]$SourceDir,
        [string]$TargetName,
        [string]$FriendlyName,
        [string]$InstallScript,
        [string]$SedPath
    )

    $installerPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    $content = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles

[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=Installed.
TargetName=$TargetName
FriendlyName=$FriendlyName
AppLaunched=$installerPowerShell -NoProfile -ExecutionPolicy Bypass -File $InstallScript
FILE0="$InstallScript"
FILE1="payload.zip"

[SourceFiles]
SourceFiles0=$SourceDir

[SourceFiles0]
%FILE0%=
%FILE1%=
"@

    Set-Content -Path $SedPath -Value $content -Encoding ASCII
}

function Wait-ForFile {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $Path) {
            return
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Timed out waiting for file: $Path"
}

function Wait-ForStableFile {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLength = -1
    $stableCount = 0
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-Path $Path)) {
            Start-Sleep -Milliseconds 500
            continue
        }

        $length = (Get-Item -LiteralPath $Path).Length
        if ($length -eq $lastLength) {
            $stableCount += 1
            if ($stableCount -ge 4) {
                return
            }
        } else {
            $lastLength = $length
            $stableCount = 0
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Timed out waiting for stable file: $Path"
}

function Complete-IExpressOutput {
    param(
        [string]$Path,
        [int64]$MinimumBytes = 1048576
    )

    Wait-ForFile -Path $Path
    Wait-ForStableFile -Path $Path

    $output = Get-Item -LiteralPath $Path
    if ($output.Length -lt $MinimumBytes) {
        $outputDir = Split-Path -Parent $Path
        $candidate = Get-ChildItem -LiteralPath $outputDir -Filter "RCX*.tmp" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($candidate -and $candidate.Length -ge $MinimumBytes) {
            Wait-ForStableFile -Path $candidate.FullName
            Move-Item -LiteralPath $candidate.FullName -Destination $Path -Force
            $output = Get-Item -LiteralPath $Path
        }
    }

    if ($output.Length -lt $MinimumBytes) {
        throw "IExpress output looks incomplete: $Path ($($output.Length) bytes)"
    }

    $baseName = [IO.Path]::GetFileNameWithoutExtension($Path)
    Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "~$baseName*.CAB" -File |
        Remove-Item -Force
}

$serverSetup = Join-Path $distRoot "ActivityWatch-Fleet-Server-Setup.exe"
$watchersSetup = Join-Path $distRoot "ActivityWatch-Fleet-Watchers-Setup.exe"
$iexpress = (Get-Command iexpress.exe -ErrorAction Stop).Source

New-IExpressSed `
    -SourceDir $serverIexpress `
    -TargetName $serverSetup `
    -FriendlyName "ActivityWatch Fleet Server" `
    -InstallScript "install-server.ps1" `
    -SedPath (Join-Path $distRoot "server-setup.sed")

New-IExpressSed `
    -SourceDir $watchersIexpress `
    -TargetName $watchersSetup `
    -FriendlyName "ActivityWatch Fleet Watchers" `
    -InstallScript "install-watchers.ps1" `
    -SedPath (Join-Path $distRoot "watchers-setup.sed")

& $iexpress /N /Q (Join-Path $distRoot "server-setup.sed")
Complete-IExpressOutput -Path $serverSetup
& $iexpress /N /Q (Join-Path $distRoot "watchers-setup.sed")
Complete-IExpressOutput -Path $watchersSetup

Write-Host "Created $serverSetup"
Write-Host "Created $watchersSetup"
Write-Host "Watchers are preconfigured for http://$($ServerHost):$ServerPort/"
