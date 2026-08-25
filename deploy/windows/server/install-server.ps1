param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Server"),
    [string]$DataDir = "",
    [switch]$SkipTask,
    [switch]$SkipFirewall,
    [switch]$SkipDataLocationPrompt,
    [switch]$NoStart,
    [switch]$AllowNonAdmin
)

$ErrorActionPreference = "Stop"

trap {
    Write-Host ""
    Write-Host "INSTALLATION FAILED: $_" -ForegroundColor Red
    Read-Host "Press Enter to close this window" | Out-Null
    exit 1
}

$registryPath = "HKLM:\Software\ActivityWatchFleet"
$dataRootFileName = "data-root.txt"

function Invoke-SelfElevation {
    # Relaunch this script elevated (UAC prompt), forwarding all bound parameters,
    # then exit the non-elevated process with the elevated run's exit code.
    param([hashtable]$BoundParameters)

    $argList = @()
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        if ($entry.Value -is [switch] -or $entry.Value -is [bool]) {
            if ($entry.Value) { $argList += "-$($entry.Key)" }
        } elseif ($entry.Value -is [array]) {
            $joined = ($entry.Value | ForEach-Object { "'$_'" }) -join ","
            $argList += "-$($entry.Key)"; $argList += $joined
        } else {
            $argList += "-$($entry.Key)"; $argList += "'$($entry.Value)'"
        }
    }

    $scriptPath = $PSCommandPath

    $inner = "& '$scriptPath' $($argList -join ' '); `$code = `$LASTEXITCODE; if (`$null -eq `$code) { `$code = 0 }; exit `$code"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    Write-Host "Administrator rights are required. Requesting elevation..."
    try {
        $process = Start-Process `
            -FilePath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
            -Verb RunAs `
            -PassThru `
            -Wait
        exit $process.ExitCode
    } catch {
        Write-Error "Elevation was declined or failed: $($_.Exception.Message)"
        exit 1
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Get-DataRootConfigFile {
    param([string]$InstallDir)
    return (Join-Path $InstallDir $dataRootFileName)
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

    $configFile = Get-DataRootConfigFile -InstallDir $InstallDir
    if (Test-Path $configFile) {
        $fileValue = Get-Content -Path $configFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
            return (Normalize-DataRoot $fileValue)
        }
    }

    return (Get-DefaultRuntimeRoot)
}

function Set-ConfiguredRuntimeRoot {
    param(
        [string]$InstallDir,
        [string]$RuntimeRoot,
        [switch]$AllowRegistryFailure
    )

    $normalized = Normalize-DataRoot $RuntimeRoot
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Set-Content -Path (Get-DataRootConfigFile -InstallDir $InstallDir) -Value $normalized -Encoding ASCII

    try {
        New-Item -Path $registryPath -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name DataRoot -Value $normalized -PropertyType String -Force | Out-Null
    } catch {
        if ($AllowRegistryFailure) {
            Write-Warning "Could not write HKLM data-root setting; start script will use install-folder fallback: $($_.Exception.Message)"
        } else {
            throw
        }
    }
}

function Test-DirectoryHasEntries {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    return [bool](Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-IsSamePath {
    param(
        [string]$Left,
        [string]$Right
    )

    return [string]::Equals(
        (Normalize-DataRoot $Left).TrimEnd('\'),
        (Normalize-DataRoot $Right).TrimEnd('\'),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-IsUpdateInstall {
    param(
        [string]$InstallDir,
        [string]$RuntimeRoot
    )

    if (Test-Path $InstallDir) {
        return $true
    }

    if (Test-DirectoryHasEntries -Path $RuntimeRoot) {
        return $true
    }

    try {
        return [bool](Get-ItemProperty -Path $registryPath -Name DataRoot -ErrorAction Stop)
    } catch {
        return $false
    }
}

function Read-MoveDecisionWithTimeout {
    param(
        [string]$CurrentRuntimeRoot,
        [int]$TimeoutSeconds = 13
    )

    # Console question with auto-continue: returns $true only if the user
    # explicitly answers yes within the timeout. Any problem (no interactive
    # console, redirected input) means "keep the current data" - the update
    # must never hang or move data on its own.
    Write-Host ""
    Write-Host "Existing server data found at: $CurrentRuntimeRoot" -ForegroundColor Cyan
    Write-Host "Move the database/runtime data to a different folder?" -ForegroundColor Cyan
    Write-Host "  [J/Y] yes, choose a new folder    [N/Enter] no    (auto-continue keeps current data)"

    try {
        # Flush pending keypresses so an earlier Enter cannot answer this question.
        while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }
    } catch {
        Write-Host "No interactive console input available; keeping the current data location."
        return $false
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastShown = -1

    while ((Get-Date) -lt $deadline) {
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($remaining -ne $lastShown) {
            Write-Host ("`rContinuing without moving in {0,2} s... " -f $remaining) -NoNewline
            $lastShown = $remaining
        }

        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::J -or $key.Key -eq [ConsoleKey]::Y) {
                    Write-Host ""
                    return $true
                }
                if ($key.Key -eq [ConsoleKey]::N -or $key.Key -eq [ConsoleKey]::Enter -or $key.Key -eq [ConsoleKey]::Escape) {
                    Write-Host ""
                    return $false
                }
                # other keys are ignored; countdown keeps running
            }
        } catch {
            Write-Host ""
            return $false
        }

        Start-Sleep -Milliseconds 100
    }

    Write-Host ""
    Write-Host "No answer within $TimeoutSeconds seconds - keeping the current data location."
    return $false
}

function Select-RuntimeRootWithDialog {
    param([string]$CurrentRuntimeRoot)

    if (-not [Environment]::UserInteractive) {
        Write-Host "Non-interactive setup detected; keeping data root $CurrentRuntimeRoot"
        return $CurrentRuntimeRoot
    }

    if (-not (Read-MoveDecisionWithTimeout -CurrentRuntimeRoot $CurrentRuntimeRoot -TimeoutSeconds 13)) {
        Write-Host "Keeping data location: $CurrentRuntimeRoot"
        return $CurrentRuntimeRoot
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch {
        Write-Warning "Could not load Windows Forms for the folder dialog; keeping $CurrentRuntimeRoot"
        return $CurrentRuntimeRoot
    }

    # Invisible TopMost owner window: without it, dialogs started from an
    # elevated installer console regularly open BEHIND the console without
    # focus - which made the old move dialog look like it did not exist.
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.ShowInTaskbar = $false
    $owner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $owner.StartPosition = "Manual"
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Location = New-Object System.Drawing.Point(-2000, -2000)

    try {
        $owner.Show()
        $owner.Activate()

        while ($true) {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = "Choose an EMPTY folder for ActivityWatch Fleet Server data. The existing data will be moved there."
            $dialog.ShowNewFolderButton = $true
            if (Test-Path $CurrentRuntimeRoot) {
                $dialog.SelectedPath = $CurrentRuntimeRoot
            }

            $result = $dialog.ShowDialog($owner)
            if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Host "No new data folder selected; keeping $CurrentRuntimeRoot"
                return $CurrentRuntimeRoot
            }

            $selected = Normalize-DataRoot $dialog.SelectedPath
            if (Test-IsSamePath -Left $CurrentRuntimeRoot -Right $selected) {
                Write-Host "Selected folder equals the current data location; nothing to move."
                return $CurrentRuntimeRoot
            }

            if (Test-DirectoryHasEntries -Path $selected) {
                [System.Windows.Forms.MessageBox]::Show(
                    $owner,
                    "The selected folder is not empty. Choose an empty folder so setup cannot overwrite unrelated files.",
                    "ActivityWatch Fleet Server data location",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                continue
            }

            Write-Host "New data location selected: $selected"
            return $selected
        }
    } finally {
        $owner.Dispose()
    }
}

function Resolve-TargetRuntimeRoot {
    param(
        [string]$InstallDir,
        [string]$CurrentRuntimeRoot,
        [string]$RequestedDataDir,
        [switch]$SkipPrompt
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedDataDir)) {
        return (Normalize-DataRoot $RequestedDataDir)
    }

    if ($SkipPrompt) {
        return $CurrentRuntimeRoot
    }

    if (Test-IsUpdateInstall -InstallDir $InstallDir -RuntimeRoot $CurrentRuntimeRoot) {
        return (Select-RuntimeRootWithDialog -CurrentRuntimeRoot $CurrentRuntimeRoot)
    }

    return $CurrentRuntimeRoot
}

function Move-RuntimeRootIfNeeded {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot
    )

    $source = Normalize-DataRoot $SourceRoot
    $target = Normalize-DataRoot $TargetRoot

    if (Test-IsSamePath -Left $source -Right $target) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        return
    }

    $sourceWithSlash = $source.TrimEnd('\') + '\'
    $targetWithSlash = $target.TrimEnd('\') + '\'
    if ($targetWithSlash.StartsWith($sourceWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The new data directory cannot be inside the current data directory."
    }

    if (Test-DirectoryHasEntries -Path $target) {
        throw "Target data directory is not empty: $target"
    }

    New-Item -ItemType Directory -Force -Path $target | Out-Null

    if (Test-Path $source) {
        Write-Host "Moving ActivityWatch Fleet Server data from $source to $target"
        $items = @(Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
        }

        Set-Content -Path (Join-Path $target ".activitywatch-fleet-data-root") -Value ("Moved from $source on {0:u}" -f (Get-Date)) -Encoding ASCII

        foreach ($item in $items) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }

        try {
            Remove-Item -LiteralPath $source -Force -ErrorAction Stop
        } catch {
            Write-Warning "Moved data, but could not remove old empty data directory ${source}: $($_.Exception.Message)"
        }
    }
}

function Get-InstalledServerProcesses {
    param(
        [string]$ServerExe,
        [string]$PidFile
    )

    $processes = @()
    $serverExePath = [IO.Path]::GetFullPath($ServerExe)

    if (Test-Path $PidFile) {
        try {
            $existingPid = [int](Get-Content $PidFile -Raw)
            $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
            if ($existing) {
                $processes += $existing
            }
        } catch {
            Write-Warning "Ignoring stale ActivityWatch Fleet Server PID file: $($_.Exception.Message)"
        }
    }

    if (Test-Path $ServerExe) {
        $processes += Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and [string]::Equals(
                $_.ExecutablePath,
                $serverExePath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    }

    return $processes | Sort-Object ProcessId -Unique
}

function Stop-ExistingServer {
    param([string]$InstallDir)

    $taskName = "ActivityWatch Fleet Server"
    $serverExe = Join-Path $InstallDir "aw-server\aw-server.exe"
    $runtimeRoot = Get-ConfiguredRuntimeRoot -InstallDir $InstallDir
    $pidFile = Join-Path $runtimeRoot "pids\server.pid"

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Write-Host "Stopped existing ActivityWatch Fleet Server scheduled task."
        } catch {
            Write-Warning "Could not stop existing scheduled task '$taskName': $($_.Exception.Message)"
        }
    }

    $processes = @(Get-InstalledServerProcesses -ServerExe $serverExe -PidFile $pidFile)
    if ($processes.Count -eq 0) {
        return
    }

    # One Stop-Process invocation for every PID: PowerShell scopes "Yes to All" to a
    # single cmdlet invocation, so a per-process loop would re-prompt for each PID.
    $processIds = @($processes | ForEach-Object { [int]$_.ProcessId })

    try {
        Stop-Process -Id $processIds -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not gracefully stop existing ActivityWatch Fleet Server processes: $($_.Exception.Message)"
    }

    Wait-Process -Id $processIds -Timeout 10 -ErrorAction SilentlyContinue

    $survivors = @(
        $processIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
    )

    if ($survivors.Count -gt 0) {
        Stop-Process -Id $survivors -Force -Confirm:$false -ErrorAction SilentlyContinue
        Wait-Process -Id $survivors -Timeout 10 -ErrorAction SilentlyContinue
    }

    foreach ($processId in $processIds) {
        if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
            Write-Warning "ActivityWatch Fleet Server PID $processId is still running."
        } else {
            Write-Host "Stopped existing ActivityWatch Fleet Server PID $processId."
        }
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Invoke-SelfElevation -BoundParameters $PSBoundParameters
}

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-server.ps1"
}

Stop-ExistingServer -InstallDir $InstallDir

$currentRuntimeRoot = Get-ConfiguredRuntimeRoot -InstallDir $InstallDir
$runtimeRoot = Resolve-TargetRuntimeRoot `
    -InstallDir $InstallDir `
    -CurrentRuntimeRoot $currentRuntimeRoot `
    -RequestedDataDir $DataDir `
    -SkipPrompt:$SkipDataLocationPrompt
Move-RuntimeRootIfNeeded -SourceRoot $currentRuntimeRoot -TargetRoot $runtimeRoot

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-ConfiguredRuntimeRoot -InstallDir $InstallDir -RuntimeRoot $runtimeRoot -AllowRegistryFailure:$AllowNonAdmin
Expand-Archive -Path $payload -DestinationPath $InstallDir -Force

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (-not $SkipFirewall) {
    try {
        $ruleName = "ActivityWatch Fleet Server 5600"
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule `
                -DisplayName $ruleName `
                -Direction Inbound `
                -Action Allow `
                -Protocol TCP `
                -LocalPort 5600 | Out-Null
        }
    } catch {
        Write-Warning "Could not create firewall rule for TCP 5600: $($_.Exception.Message)"
    }
}

if (-not $SkipTask) {
    $taskName = "ActivityWatch Fleet Server"
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startScript = Join-Path $InstallDir "start-server.ps1"
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute $powershell -Argument $taskArgs -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Start ActivityWatch Fleet Server on boot." `
        -Force | Out-Null

    if (-not $NoStart) {
        Start-ScheduledTask -TaskName $taskName
    }
}

Write-Host "ActivityWatch Fleet Server installed to $InstallDir"
Write-Host "Runtime data root: $runtimeRoot"
Write-Host "Web UI: http://192.168.0.144:5600/"

Write-Host ""
Write-Host "Installation completed successfully." -ForegroundColor Green
Read-Host "Press Enter to close this window" | Out-Null
