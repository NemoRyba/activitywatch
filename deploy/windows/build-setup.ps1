param(
    [string]$ServerHost = "192.168.0.144",
    [int]$ServerPort = 5600,
    [ValidateSet("All", "Server", "Watchers")]
    [string]$Target = "All",
    # Stage the watcher payload, manifest and Update.zip but skip the setup
    # EXE. Useful when the previous EXE is held open (e.g. a device has it
    # open over the network share) - the GUI rollout and the server embed
    # need only the zip and the watchers-iexpress staging, not the EXE.
    [switch]$SkipWatchersSetupExe
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$distRoot = Join-Path $repoRoot "dist\deployment"
$serverPayload = Join-Path $distRoot "server-payload"
$watchersPayload = Join-Path $distRoot "watchers-payload"
$serverIexpress = Join-Path $distRoot "server-iexpress"
$watchersIexpress = Join-Path $distRoot "watchers-iexpress"
$serverSetup = Join-Path $distRoot "ActivityWatch-Fleet-Server-Setup.exe"
$watchersSetup = Join-Path $distRoot "ActivityWatch-Fleet-Watchers-Setup.exe"
$buildServer = $Target -in @("All", "Server")
$buildWatchers = $Target -in @("All", "Watchers")

function Assert-UnderRepo {
    param([string]$Path)
    $resolved = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { [IO.Path]::GetFullPath($Path) }
    if (-not $resolved.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside repo: $resolved"
    }
}

Assert-UnderRepo $distRoot
if ($Target -eq "All" -and (Test-Path $distRoot)) {
    Remove-Item -LiteralPath $distRoot -Recurse -Force
} elseif (Test-Path $distRoot) {
    $pathsToRemove = @()
    if ($buildServer) {
        $pathsToRemove += @(
            $serverPayload,
            $serverIexpress,
            $serverSetup,
            (Join-Path $distRoot "server-setup.sed")
        )
    }
    if ($buildWatchers) {
        $pathsToRemove += @(
            $watchersPayload,
            $watchersIexpress,
            (Join-Path $distRoot "watchers-setup.sed"),
            (Join-Path $distRoot "ActivityWatch-Fleet-Watchers-Update.zip")
        )
        if (-not $SkipWatchersSetupExe) {
            $pathsToRemove += $watchersSetup
        }
    }
    foreach ($path in $pathsToRemove) {
        Assert-UnderRepo $path
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
$dirsToCreate = @()
if ($buildServer) {
    $dirsToCreate += @($serverPayload, $serverIexpress)
}
if ($buildWatchers) {
    $dirsToCreate += @($watchersPayload, $watchersIexpress)
}
New-Item -ItemType Directory -Force -Path $dirsToCreate | Out-Null

$requiredDirs = @()
if ($buildServer) {
    $requiredDirs += "aw-server\dist\aw-server"
}
if ($buildWatchers) {
    $requiredDirs += @(
        "aw-watcher-afk\dist\aw-watcher-afk",
        "aw-watcher-window\dist\aw-watcher-window",
        "aw-watcher-session\dist\aw-watcher-session",
        "aw-watcher-audio\dist\aw-watcher-audio",
        "aw-watcher-system\dist\aw-watcher-system"
    )
}
foreach ($dir in $requiredDirs) {
    $path = Join-Path $repoRoot $dir
    if (-not (Test-Path $path)) {
        throw "Missing built distribution: $path"
    }
}

if ($buildServer) {
    Copy-Item -Path (Join-Path $repoRoot "aw-server\dist\aw-server") -Destination (Join-Path $serverPayload "aw-server") -Recurse -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "server\start-server.ps1") -Destination $serverPayload -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "server\stop-server.ps1") -Destination $serverPayload -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "server\uninstall-server.ps1") -Destination $serverPayload -Force
}

if ($buildWatchers) {
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
    Copy-Item -Path (Join-Path $PSScriptRoot "watchers\set-fleet-token.ps1") -Destination $watchersPayload -Force
}

function Update-DeploymentScriptDefaults {
    param([string]$Path)

    (Get-Content $Path -Raw).
        Replace("192.168.0.144", $ServerHost).
        Replace("5600", [string]$ServerPort) |
        Set-Content -Path $Path
}

if ($buildServer) {
    foreach ($scriptName in @("start-server.ps1", "uninstall-server.ps1")) {
        $scriptPath = Join-Path $serverPayload $scriptName
        Update-DeploymentScriptDefaults -Path $scriptPath
    }
}

if ($buildWatchers) {
    Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "start-watchers.ps1")
    Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "start-system-watcher.ps1")
    Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "supervise-watchers.ps1")
    Update-DeploymentScriptDefaults -Path (Join-Path $watchersPayload "set-fleet-token.ps1")
}

if ($buildServer) {
    Compress-Archive -Path (Join-Path $serverPayload "*") -DestinationPath (Join-Path $serverIexpress "payload.zip") -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "server\install-server.ps1") -Destination $serverIexpress -Force
    Update-DeploymentScriptDefaults -Path (Join-Path $serverIexpress "install-server.ps1")
}

if ($buildWatchers) {
    Compress-Archive -Path (Join-Path $watchersPayload "*") -DestinationPath (Join-Path $watchersIexpress "payload.zip") -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "watchers\install-watchers.ps1") -Destination $watchersIexpress -Force
    Update-DeploymentScriptDefaults -Path (Join-Path $watchersIexpress "install-watchers.ps1")

    # Auto-update manifest: the package version IS the SHA256 of payload.zip.
    # rebuild-server-setup.ps1 embeds payload.zip + install-watchers.ps1 +
    # manifest.json into the server, which then serves them to the supervisors.
    $watchersPayloadZip = Join-Path $watchersIexpress "payload.zip"
    $watchersPackageVersion = (Get-FileHash -Algorithm SHA256 -LiteralPath $watchersPayloadZip).Hash.ToLowerInvariant()
    $watchersManifest = @{
        version = $watchersPackageVersion
        sha256 = $watchersPackageVersion
        created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    } | ConvertTo-Json
    Set-Content -Path (Join-Path $watchersIexpress "manifest.json") -Value $watchersManifest -Encoding ASCII
    Write-Host "Watcher package version: $watchersPackageVersion"

    # Single-file update package for the admin GUI: upload this under
    # Administration -> Watcher-Updates to distribute the new watchers
    # WITHOUT rebuilding or reinstalling the server.
    $watchersUpdateZip = Join-Path $distRoot "ActivityWatch-Fleet-Watchers-Update.zip"
    Compress-Archive -Path @(
        (Join-Path $watchersIexpress "payload.zip"),
        (Join-Path $watchersIexpress "install-watchers.ps1"),
        (Join-Path $watchersIexpress "manifest.json")
    ) -DestinationPath $watchersUpdateZip -Force
    Write-Host "Created $watchersUpdateZip (upload this in the admin GUI under Watcher-Updates)"
}

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
FinishMessage=
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
        # iexpress.exe is launched with /N /Q and returns immediately, so the
        # only way to know it finished is to poll for the output. Compressing
        # the ~65 MB server payload regularly needs well over two minutes on a
        # loaded build machine (Defender scanning the fresh PyInstaller dist
        # makes it worse), and a timeout here is destructive: the previous
        # setup exe has already been cleared by then.
        [int]$TimeoutSeconds = 900
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
        # The exe appears before it is fully written; wait for the size to stop
        # growing. Same reasoning as Wait-ForFile for the generous timeout.
        [int]$TimeoutSeconds = 300
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

$iexpress = (Get-Command iexpress.exe -ErrorAction Stop).Source

function Invoke-IExpress {
    # iexpress.exe is a GUI-subsystem binary, so `& $iexpress` returns as soon
    # as it is launched instead of when it is done. The build then raced the
    # packager by polling for the output file, which is unreliable: on a loaded
    # machine the ~65 MB server payload finished the CAB but not the exe, and
    # the poll gave up - after the previous setup exe had already been cleared,
    # leaving no artefact at all. Start-Process -Wait actually waits.
    param([string]$SedPath)

    $process = Start-Process -FilePath $iexpress -ArgumentList @("/N", "/Q", $SedPath) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "iexpress failed with exit code $($process.ExitCode) for $SedPath"
    }
}

if ($buildServer) {
    New-IExpressSed `
        -SourceDir $serverIexpress `
        -TargetName $serverSetup `
        -FriendlyName "ActivityWatch Fleet Server" `
        -InstallScript "install-server.ps1" `
        -SedPath (Join-Path $distRoot "server-setup.sed")

    Invoke-IExpress -SedPath (Join-Path $distRoot "server-setup.sed")
    Complete-IExpressOutput -Path $serverSetup
    Write-Host "Created $serverSetup"
}

if ($buildWatchers) {
    if ($SkipWatchersSetupExe) {
        Write-Host "Skipping watcher setup EXE (-SkipWatchersSetupExe); payload, manifest and Update.zip are staged."
    } else {
        New-IExpressSed `
            -SourceDir $watchersIexpress `
            -TargetName $watchersSetup `
            -FriendlyName "ActivityWatch Fleet Watchers" `
            -InstallScript "install-watchers.ps1" `
            -SedPath (Join-Path $distRoot "watchers-setup.sed")

        Invoke-IExpress -SedPath (Join-Path $distRoot "watchers-setup.sed")
        Complete-IExpressOutput -Path $watchersSetup
        Write-Host "Created $watchersSetup"
    }
    Write-Host "Watchers are preconfigured for http://$($ServerHost):$ServerPort/"
}
