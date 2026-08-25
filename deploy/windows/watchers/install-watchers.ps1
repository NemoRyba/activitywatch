param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers"),
    [string[]]$Watchers,
    [switch]$SkipWatcherSelection,
    [switch]$KeepExistingSelection,
    [switch]$SkipStartup,
    [switch]$SkipSystemTask,
    [switch]$NoStart,
    [int]$StartupTimeoutSeconds = 120,
    [switch]$AllowNonAdmin,
    [switch]$Headless,
    # Shared secret this device uses to authenticate against the fleet server
    # (Administration -> Watcher-Updates -> Fleet-Token). Written once per
    # machine; every watcher and the supervisor read it from there. Omit it on
    # an upgrade to keep whatever token is already provisioned.
    [string]$FleetToken = ""
)

$ErrorActionPreference = "Stop"

# Headless mode: used by the watcher auto-update (supervisor spawns this script
# as SYSTEM with no interactive console). Never prompt, never show dialogs, and
# log everything to a transcript instead of pausing.
$IsHeadless = [bool]$Headless -or (-not [Environment]::UserInteractive)
if ($IsHeadless) {
    $ProgressPreference = "SilentlyContinue"
    $ConfirmPreference = "None"
    $headlessLogDir = Join-Path $env:ProgramData "ActivityWatchFleet\logs"
    try {
        New-Item -ItemType Directory -Force -Path $headlessLogDir | Out-Null
        Start-Transcript -Path (Join-Path $headlessLogDir "install-watchers.log") -Append | Out-Null
    } catch { }
    Write-Host ""
    Write-Host ("=== Headless watcher install started {0} ===" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
}

trap {
    Write-Host ""
    Write-Host "INSTALLATION FAILED: $_" -ForegroundColor Red
    if ($IsHeadless) {
        try { Stop-Transcript | Out-Null } catch { }
    } else {
        Read-Host "Press Enter to close this window" | Out-Null
    }
    exit 1
}

$WatcherConfigFileName = "watchers.config.psd1"
$WatcherDefinitions = @(
    [pscustomobject]@{
        Key = "afk"
        DisplayName = "AFK watcher"
        Folder = "aw-watcher-afk"
        Description = "Detects idle and away state for each logged-in user."
        Scope = "User"
    },
    [pscustomobject]@{
        Key = "window"
        DisplayName = "Window activity watcher"
        Folder = "aw-watcher-window"
        Description = "Tracks the active app and window title for each logged-in user."
        Scope = "User"
    },
    [pscustomobject]@{
        Key = "session"
        DisplayName = "Session watcher"
        Folder = "aw-watcher-session"
        Description = "Tracks lock, unlock, logon, and session state."
        Scope = "User"
    },
    [pscustomobject]@{
        Key = "audio"
        DisplayName = "Audio watcher"
        Folder = "aw-watcher-audio"
        Description = "Tracks audible media/browser activity for each logged-in user."
        Scope = "User"
    },
    [pscustomobject]@{
        Key = "system"
        DisplayName = "CPU/RAM system watcher"
        Folder = "aw-watcher-system"
        Description = "Tracks machine-level CPU and memory load."
        Scope = "System"
    }
)
$WatcherAliases = @{
    "afkt" = "afk"
    "idle" = "afk"
    "activity" = "window"
    "user" = "window"
    "window-activity" = "window"
    "cpu" = "system"
    "ram" = "system"
    "metrics" = "system"
}

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

function Get-AllWatcherKeys {
    return @($WatcherDefinitions | ForEach-Object { $_.Key })
}

function Resolve-WatcherSelection {
    param([string[]]$SelectedWatchers)

    $allWatcherKeys = Get-AllWatcherKeys
    if (-not $SelectedWatchers -or $SelectedWatchers.Count -eq 0) {
        return $allWatcherKeys
    }

    $normalized = @()
    foreach ($selected in $SelectedWatchers) {
        if ([string]::IsNullOrWhiteSpace($selected)) {
            continue
        }

        $key = $selected.Trim().ToLowerInvariant()
        if ($WatcherAliases.ContainsKey($key)) {
            $key = $WatcherAliases[$key]
        }

        if ($allWatcherKeys -notcontains $key) {
            throw "Unknown watcher '$selected'. Valid values: $($allWatcherKeys -join ', ')"
        }

        if ($normalized -notcontains $key) {
            $normalized += $key
        }
    }

    if ($normalized.Count -eq 0) {
        throw "Select at least one watcher."
    }

    return @($WatcherDefinitions | Where-Object { $normalized -contains $_.Key } | ForEach-Object { $_.Key })
}

function Get-ExistingWatcherSelection {
    param([string]$InstallDir)

    $configPath = Join-Path $InstallDir $WatcherConfigFileName
    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $config = Import-PowerShellDataFile -Path $configPath
        $selected = @($config.SelectedWatchers | Where-Object { $_ })
        if ($selected.Count -eq 0) {
            return $null
        }
        return Resolve-WatcherSelection -SelectedWatchers $selected
    } catch {
        Write-Warning "Could not read existing watcher selection: $($_.Exception.Message)"
        return $null
    }
}

function Select-WatchersWithDialog {
    if (-not [Environment]::UserInteractive) {
        Write-Warning "Watcher selection dialog is unavailable in this session; installing all watchers."
        return Get-AllWatcherKeys
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch {
        Write-Warning "Could not load Windows Forms for watcher selection; installing all watchers."
        return Get-AllWatcherKeys
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ActivityWatch Fleet watcher selection"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(660, 330)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Location = New-Object System.Drawing.Point(16, 16)
    $messageLabel.Size = New-Object System.Drawing.Size(628, 48)
    $messageLabel.Text = "Choose which watcher components to install. All watchers are selected by default."
    $form.Controls.Add($messageLabel)

    $checkedList = New-Object System.Windows.Forms.CheckedListBox
    $checkedList.CheckOnClick = $true
    $checkedList.Location = New-Object System.Drawing.Point(20, 72)
    $checkedList.Size = New-Object System.Drawing.Size(620, 180)
    foreach ($definition in $WatcherDefinitions) {
        $label = "{0} - {1}" -f $definition.DisplayName, $definition.Description
        [void]$checkedList.Items.Add($label, $true)
    }
    $form.Controls.Add($checkedList)

    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Location = New-Object System.Drawing.Point(432, 276)
    $installButton.Size = New-Object System.Drawing.Size(95, 28)
    $installButton.Text = "Install"
    $installButton.Add_Click({
        if ($checkedList.CheckedItems.Count -le 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Select at least one watcher.",
                "ActivityWatch Fleet watcher selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($installButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(542, 276)
    $cancelButton.Size = New-Object System.Drawing.Size(95, 28)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $installButton
    $form.CancelButton = $cancelButton

    $choice = $form.ShowDialog()
    if ($choice -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        throw "Setup cancelled by user."
    }

    $selected = @()
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        if ($checkedList.GetItemChecked($i)) {
            $selected += $WatcherDefinitions[$i].Key
        }
    }

    $form.Dispose()
    return Resolve-WatcherSelection -SelectedWatchers $selected
}

function Test-SelectionHasScope {
    param(
        [string[]]$SelectedWatchers,
        [string]$Scope
    )

    foreach ($definition in $WatcherDefinitions) {
        if ($definition.Scope -eq $Scope -and $SelectedWatchers -contains $definition.Key) {
            return $true
        }
    }

    return $false
}

function Write-WatcherSelectionConfig {
    param(
        [string]$InstallDir,
        [string[]]$SelectedWatchers
    )

    $configPath = Join-Path $InstallDir $WatcherConfigFileName
    $lines = @(
        "@{",
        "    SelectedWatchers = @("
    )
    for ($i = 0; $i -lt $SelectedWatchers.Count; $i++) {
        $suffix = if ($i -lt ($SelectedWatchers.Count - 1)) { "," } else { "" }
        $lines += "        '$($SelectedWatchers[$i])'$suffix"
    }
    $lines += @(
        "    )",
        "}"
    )

    Set-Content -Path $configPath -Encoding ASCII -Value $lines
}

function Remove-UnselectedWatcherFolders {
    param(
        [string]$InstallDir,
        [string[]]$SelectedWatchers
    )

    foreach ($definition in $WatcherDefinitions) {
        if ($SelectedWatchers -contains $definition.Key) {
            continue
        }

        $watcherDir = Join-Path $InstallDir $definition.Folder
        if (Test-Path $watcherDir) {
            Remove-Item -LiteralPath $watcherDir -Recurse -Force
            Write-Host "Skipped $($definition.DisplayName)."
        }
    }
}

function Remove-WatcherStartupShortcut {
    $startupDir = [Environment]::GetFolderPath("CommonStartup")
    $shortcutPath = Join-Path $startupDir "ActivityWatch Fleet Watchers.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
    }
}

function Write-FleetToken {
    <#
      Provision the machine-wide fleet token. It lives outside the install dir
      so an update (which wipes and re-extracts the install dir) cannot lose
      it, and so every per-user watcher plus the SYSTEM supervisor read the
      same value. Omitting -FleetToken on an upgrade keeps the existing token.
    #>
    param([string]$Token)

    $tokenDir = Join-Path $env:ProgramData "ActivityWatchFleet"
    $tokenFile = Join-Path $tokenDir "fleet-token.txt"

    if ([string]::IsNullOrWhiteSpace($Token)) {
        if (Test-Path $tokenFile) {
            Write-Host "Fleet token: keeping the token already provisioned on this device."
        } else {
            Write-Host "Fleet token: none provisioned. Fine while the server has token enforcement off; re-run with -FleetToken before switching it on."
        }
        return
    }

    New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
    Set-Content -Path $tokenFile -Encoding ASCII -Value $Token.Trim() -NoNewline

    # Readable by every logged-in user's watchers, writable only by admins.
    try {
        & icacls.exe $tokenFile /inheritance:r /grant:r "*S-1-5-32-544:(F)" "*S-1-5-18:(F)" "*S-1-5-32-545:(R)" | Out-Null
    } catch {
        Write-Warning "Could not tighten permissions on $tokenFile : $_"
    }
    Write-Host "Fleet token written to $tokenFile"
}

function Register-WatcherSupervisorTask {
    param([string]$InstallDir)

    $taskName = "ActivityWatch Fleet Watchers Supervisor"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $supervisorScript = Join-Path $InstallDir "supervise-watchers.ps1"

    if (-not (Test-Path $supervisorScript)) {
        throw "Watcher supervisor script not found at $supervisorScript"
    }

    $action = New-ScheduledTaskAction `
        -Execute $powershell `
        -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $supervisorScript) `
        -WorkingDirectory $InstallDir

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $repeatingTrigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger @($startupTrigger, $logonTrigger, $repeatingTrigger) `
        -Principal $principal `
        -Settings $settings `
        -Description "Starts ActivityWatch Fleet watchers in every active interactive user session." `
        -Force | Out-Null

    Start-ScheduledTask -TaskName $taskName
    Write-Host "Registered and started scheduled task '$taskName'."
}

function Get-WatcherExePath {
    param([string]$InstallDir, [string]$Key)

    $definition = $WatcherDefinitions | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $definition) {
        return $null
    }

    return Join-Path $InstallDir ("{0}\{0}.exe" -f $definition.Folder)
}

function Get-RunningWatcherProcesses {
    param([string[]]$ExePaths)

    if (-not $ExePaths -or $ExePaths.Count -eq 0) {
        return @()
    }

    return @(
        Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and ($ExePaths -contains $_.ExecutablePath)
        }
    )
}

function Start-SelectedWatchers {
    param(
        [string]$InstallDir,
        [string[]]$SelectedWatchers,
        [bool]$SkipSystem,
        [int]$TimeoutSeconds = 60
    )

    $supervisorTask = "ActivityWatch Fleet Watchers Supervisor"
    $systemTask = "ActivityWatch Fleet System Watcher"
    $hasUserScope = Test-SelectionHasScope -SelectedWatchers $SelectedWatchers -Scope "User"
    $hasSystemScope = ($SelectedWatchers -contains "system") -and -not $SkipSystem

    $expected = @()
    foreach ($key in $SelectedWatchers) {
        if ($key -eq "system" -and $SkipSystem) {
            continue
        }

        $exe = Get-WatcherExePath -InstallDir $InstallDir -Key $key
        if ($exe -and (Test-Path $exe)) {
            $expected += [pscustomobject]@{
                Key = $key
                Exe = [IO.Path]::GetFullPath($exe)
            }
        }
    }

    if ($expected.Count -eq 0) {
        Write-Host "No installed watcher executables to start."
        return
    }

    # The installer runs inside an interactive session, so start the per-user
    # watchers directly FIRST - deterministic and instant. The SYSTEM
    # supervisor task remains responsible for boot time and self-healing.
    $installerSessionId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").SessionId
    if ($installerSessionId -ne 0) {
        $startScript = Join-Path $InstallDir "start-watchers.ps1"
        if (Test-Path $startScript) {
            Write-Host "Starting watchers directly in session $installerSessionId..."
            $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            try {
                & $powershell -NoProfile -ExecutionPolicy Bypass -File $startScript 2>&1 |
                    ForEach-Object { Write-Host "  $_" }
            } catch {
                Write-Warning "Direct watcher start failed: $($_.Exception.Message)"
            }
        }
    }

    Write-Host "Verifying watchers (timeout $TimeoutSeconds s)..."
    Write-Host "(If this console appears frozen, a click selected text - QuickEdit. Press Enter to release.)"

    $expectedPaths = @($expected | ForEach-Object { $_.Exe })
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastKick = Get-Date
    $lastTick = Get-Date
    $waitStart = Get-Date

    while ($true) {
        $running = Get-RunningWatcherProcesses -ExePaths $expectedPaths
        $missing = @(
            $expected | Where-Object {
                $exePath = $_.Exe
                -not ($running | Where-Object { $_.ExecutablePath -eq $exePath })
            }
        )

        if ($missing.Count -eq 0) {
            break
        }

        if ((Get-Date) -ge $deadline) {
            break
        }

        # The supervisor task runs as SYSTEM and launches watchers into every
        # interactive session. Re-trigger it periodically in case the first start
        # raced with task registration or a session was not ready yet.
        if (((Get-Date) - $lastKick).TotalSeconds -ge 15) {
            if ($hasUserScope) {
                Start-ScheduledTask -TaskName $supervisorTask -ErrorAction SilentlyContinue
            }
            if ($hasSystemScope) {
                Start-ScheduledTask -TaskName $systemTask -ErrorAction SilentlyContinue
            }
            $lastKick = Get-Date
        }

        if (((Get-Date) - $lastTick).TotalSeconds -ge 10) {
            $elapsed = [int]((Get-Date) - $waitStart).TotalSeconds
            Write-Host "  still waiting... ($elapsed s)"
            $lastTick = Get-Date
        }

        Start-Sleep -Seconds 2
    }

    $running = Get-RunningWatcherProcesses -ExePaths $expectedPaths
    foreach ($watcher in $expected) {
        $exePath = $watcher.Exe
        $processes = @($running | Where-Object { $_.ExecutablePath -eq $exePath })
        if ($processes.Count -gt 0) {
            $pidList = ($processes | ForEach-Object { $_.ProcessId }) -join ", "
            Write-Host "Watcher '$($watcher.Key)' running (PID $pidList)."
        } else {
            Write-Warning "Watcher '$($watcher.Key)' did not start. Check %LOCALAPPDATA%\ActivityWatchFleet\logs\watchers and the '$supervisorTask' task history."
        }
    }
}

function Stop-ExistingWatcherProcesses {
    param([string]$InstallDir)

    $watcherExePaths = @(
        Join-Path $InstallDir "aw-watcher-afk\aw-watcher-afk.exe"
        Join-Path $InstallDir "aw-watcher-window\aw-watcher-window.exe"
        Join-Path $InstallDir "aw-watcher-session\aw-watcher-session.exe"
        Join-Path $InstallDir "aw-watcher-audio\aw-watcher-audio.exe"
        Join-Path $InstallDir "aw-watcher-system\aw-watcher-system.exe"
    )

    $targetPaths = @(
        $watcherExePaths |
            Where-Object { Test-Path $_ } |
            ForEach-Object { [IO.Path]::GetFullPath($_) }
    )

    if ($targetPaths.Count -eq 0) {
        return
    }

    # Collect every running watcher process up front so that the stop below is a
    # SINGLE Stop-Process invocation. PowerShell scopes "Yes to All" to one cmdlet
    # invocation, so stopping one process per call would re-prompt for each PID no
    # matter what the user answered.
    $processes = @(
        Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and ($targetPaths -contains $_.ExecutablePath)
        } | Sort-Object ProcessId -Unique
    )

    if ($processes.Count -eq 0) {
        return
    }

    $processIds = @($processes | ForEach-Object { [int]$_.ProcessId })

    try {
        Stop-Process -Id $processIds -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not gracefully stop existing ActivityWatch Fleet Watcher processes: $($_.Exception.Message)"
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
            Write-Warning "ActivityWatch Fleet Watcher PID $processId is still running."
        } else {
            Write-Host "Stopped existing ActivityWatch Fleet Watcher PID $processId."
        }
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    if ($IsHeadless) {
        throw "Administrator rights are required for a headless installation."
    }
    Invoke-SelfElevation -BoundParameters $PSBoundParameters
}

$selectedWatchers = if ($PSBoundParameters.ContainsKey("Watchers")) {
    Resolve-WatcherSelection -SelectedWatchers $Watchers
} elseif ($KeepExistingSelection -or ($IsHeadless -and -not $SkipWatcherSelection)) {
    # Auto-update path: keep whatever this machine already has installed;
    # fall back to all watchers on a fresh machine.
    $existingSelection = Get-ExistingWatcherSelection -InstallDir $InstallDir
    if ($existingSelection) {
        Write-Host "Keeping existing watcher selection."
        $existingSelection
    } else {
        Get-AllWatcherKeys
    }
} elseif ($SkipWatcherSelection) {
    Get-AllWatcherKeys
} else {
    Select-WatchersWithDialog
}
$hasUserWatchers = Test-SelectionHasScope -SelectedWatchers $selectedWatchers -Scope "User"
$hasSystemWatcher = $selectedWatchers -contains "system"
Write-Host "Selected watcher components: $($selectedWatchers -join ', ')"

$payload = Join-Path $PSScriptRoot "payload.zip"
if (-not (Test-Path $payload)) {
    throw "Missing payload.zip next to install-watchers.ps1"
}

Stop-ExistingWatcherProcesses -InstallDir $InstallDir
Unregister-ScheduledTask -TaskName "ActivityWatch Fleet Watchers Supervisor" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "ActivityWatch Fleet System Watcher" -Confirm:$false -ErrorAction SilentlyContinue
Remove-WatcherStartupShortcut

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Expand-Archive -Path $payload -DestinationPath $InstallDir -Force

# Record which watcher package build is now installed. The supervisor reports
# this version to the fleet server and uses it to decide when to self-update.
$packageVersion = (Get-FileHash -Algorithm SHA256 -LiteralPath $payload).Hash.ToLowerInvariant()
Set-Content -Path (Join-Path $InstallDir "package-version.txt") -Encoding ASCII -Value $packageVersion
Write-Host "Installed watcher package version: $packageVersion"

Write-FleetToken -Token $FleetToken

Write-WatcherSelectionConfig -InstallDir $InstallDir -SelectedWatchers $selectedWatchers
Remove-UnselectedWatcherFolders -InstallDir $InstallDir -SelectedWatchers $selectedWatchers

if ($hasUserWatchers -and -not $SkipStartup) {
    $startupDir = [Environment]::GetFolderPath("CommonStartup")
    $shortcutPath = Join-Path $startupDir "ActivityWatch Fleet Watchers.lnk"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startScript = Join-Path $InstallDir "start-watchers.ps1"
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = "Start ActivityWatch Fleet Watchers for the logged-in user."
    $shortcut.Save()
} elseif (-not $hasUserWatchers) {
    Write-Host "No per-user watchers selected; startup shortcut skipped."
}

if ($hasSystemWatcher -and -not $SkipSystemTask) {
    $taskName = "ActivityWatch Fleet System Watcher"
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startScript = Join-Path $InstallDir "start-system-watcher.ps1"
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript

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
        -Description "Start ActivityWatch Fleet system metrics watcher on boot." `
        -Force | Out-Null
} elseif (-not $hasSystemWatcher) {
    Write-Host "CPU/RAM system watcher not selected; system task skipped."
}

if (-not $NoStart) {
    if ($hasUserWatchers) {
        Register-WatcherSupervisorTask -InstallDir $InstallDir
    } else {
        Write-Host "No per-user watchers selected; watcher supervisor task skipped."
    }
    if ($hasSystemWatcher -and -not $SkipSystemTask) {
        Start-ScheduledTask -TaskName "ActivityWatch Fleet System Watcher"
    }

    # Do not just fire the tasks and exit: confirm the watchers are actually
    # running, re-triggering the supervisor while any are still stopped.
    Start-SelectedWatchers `
        -InstallDir $InstallDir `
        -SelectedWatchers $selectedWatchers `
        -SkipSystem ([bool]$SkipSystemTask) `
        -TimeoutSeconds $StartupTimeoutSeconds
} else {
    Write-Host "Skipping watcher task start because -NoStart was used."
}

Write-Host "ActivityWatch Fleet Watchers installed to $InstallDir"
Write-Host "Installed watcher components: $($selectedWatchers -join ', ')"
Write-Host "Watchers will send to http://192.168.0.144:5600/"

Write-Host ""
Write-Host "Installation completed successfully." -ForegroundColor Green
if ($IsHeadless) {
    try { Stop-Transcript | Out-Null } catch { }
} else {
    Read-Host "Press Enter to close this window" | Out-Null
}
