param(
    [string]$InstallDir = (Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers"),
    [string[]]$Watchers,
    [switch]$SkipWatcherSelection,
    [switch]$SkipStartup,
    [switch]$SkipSystemTask,
    [switch]$NoStart,
    [switch]$AllowNonAdmin
)

$ErrorActionPreference = "Stop"

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

function Stop-ExistingWatcherProcesses {
    param([string]$InstallDir)

    $watcherExePaths = @(
        Join-Path $InstallDir "aw-watcher-afk\aw-watcher-afk.exe"
        Join-Path $InstallDir "aw-watcher-window\aw-watcher-window.exe"
        Join-Path $InstallDir "aw-watcher-session\aw-watcher-session.exe"
        Join-Path $InstallDir "aw-watcher-audio\aw-watcher-audio.exe"
        Join-Path $InstallDir "aw-watcher-system\aw-watcher-system.exe"
    )

    foreach ($watcherExe in $watcherExePaths) {
        if (-not (Test-Path $watcherExe)) {
            continue
        }

        $watcherExePath = [IO.Path]::GetFullPath($watcherExe)
        $processes = Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and [string]::Equals(
                $_.ExecutablePath,
                $watcherExePath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }

        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Could not gracefully stop ActivityWatch Fleet Watcher PID $($process.ProcessId): $($_.Exception.Message)"
            }

            if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            }

            Write-Host "Stopped existing ActivityWatch Fleet Watcher PID $($process.ProcessId)."
        }
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files and creates a machine-level watcher supervisor scheduled task."
    exit 1
}

$selectedWatchers = if ($PSBoundParameters.ContainsKey("Watchers")) {
    Resolve-WatcherSelection -SelectedWatchers $Watchers
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
} else {
    Write-Host "Skipping watcher task start because -NoStart was used."
}

Write-Host "ActivityWatch Fleet Watchers installed to $InstallDir"
Write-Host "Installed watcher components: $($selectedWatchers -join ', ')"
Write-Host "Watchers will send to http://192.168.0.144:5600/"
