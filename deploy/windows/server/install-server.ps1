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

$registryPath = "HKLM:\Software\ActivityWatchFleet"
$dataRootFileName = "data-root.txt"

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

function Select-RuntimeRootWithDialog {
    param([string]$CurrentRuntimeRoot)

    if (-not [Environment]::UserInteractive) {
        Write-Host "Non-interactive setup detected; keeping data root $CurrentRuntimeRoot"
        return $CurrentRuntimeRoot
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch {
        Write-Warning "Could not load Windows Forms for data location prompt; keeping $CurrentRuntimeRoot"
        return $CurrentRuntimeRoot
    }

    $timeoutSeconds = 30
    $state = @{ Remaining = $timeoutSeconds }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ActivityWatch Fleet Server data location"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(620, 230)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Location = New-Object System.Drawing.Point(16, 16)
    $messageLabel.Size = New-Object System.Drawing.Size(588, 108)
    $messageLabel.Text = "ActivityWatch Fleet Server already has an existing data location:`r`n`r`n$CurrentRuntimeRoot`r`n`r`nLeave the box unchecked to keep the current database and continue the update."
    $form.Controls.Add($messageLabel)

    $moveCheckbox = New-Object System.Windows.Forms.CheckBox
    $moveCheckbox.Location = New-Object System.Drawing.Point(20, 128)
    $moveCheckbox.Size = New-Object System.Drawing.Size(560, 24)
    $moveCheckbox.Text = "Move database and runtime data to a different empty folder"
    $moveCheckbox.Checked = $false
    $form.Controls.Add($moveCheckbox)

    $countdownLabel = New-Object System.Windows.Forms.Label
    $countdownLabel.Location = New-Object System.Drawing.Point(20, 160)
    $countdownLabel.Size = New-Object System.Drawing.Size(360, 22)
    $countdownLabel.Text = "Continuing without moving data in $timeoutSeconds seconds."
    $form.Controls.Add($countdownLabel)

    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Location = New-Object System.Drawing.Point(404, 158)
    $continueButton.Size = New-Object System.Drawing.Size(95, 28)
    $continueButton.Text = "Continue"
    $continueButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($continueButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(509, 158)
    $cancelButton.Size = New-Object System.Drawing.Size(95, 28)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $continueButton
    $form.CancelButton = $cancelButton

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $state.Remaining = [int]$state.Remaining - 1
        if ($state.Remaining -le 0) {
            $timer.Stop()
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
            return
        }

        $countdownLabel.Text = "Continuing without moving data in $($state.Remaining) seconds."
    })

    $moveCheckbox.Add_CheckedChanged({
        if ($moveCheckbox.Checked) {
            $timer.Stop()
            $countdownLabel.Text = "Click Continue to choose an empty folder for the moved data."
            return
        }

        $state.Remaining = $timeoutSeconds
        $countdownLabel.Text = "Continuing without moving data in $timeoutSeconds seconds."
        $timer.Start()
    })

    $timer.Start()
    $choice = $form.ShowDialog()
    $moveRequested = $moveCheckbox.Checked
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()

    if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
        throw "Setup cancelled by user."
    }

    if (-not $moveRequested) {
        return $CurrentRuntimeRoot
    }

    while ($true) {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Choose an empty folder for ActivityWatch Fleet Server data. The existing data will be moved there."
        $dialog.ShowNewFolderButton = $true
        if (Test-Path $CurrentRuntimeRoot) {
            $dialog.SelectedPath = $CurrentRuntimeRoot
        }

        $result = $dialog.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host "No new data folder selected; keeping $CurrentRuntimeRoot"
            return $CurrentRuntimeRoot
        }

        $selected = Normalize-DataRoot $dialog.SelectedPath
        if (Test-IsSamePath -Left $CurrentRuntimeRoot -Right $selected) {
            return $CurrentRuntimeRoot
        }

        if (Test-DirectoryHasEntries -Path $selected) {
            [System.Windows.Forms.MessageBox]::Show(
                "The selected folder is not empty. Choose an empty folder so setup cannot overwrite unrelated files.",
                "ActivityWatch Fleet Server data location",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            continue
        }

        return $selected
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
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
            Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not gracefully stop ActivityWatch Fleet Server PID $($process.ProcessId): $($_.Exception.Message)"
        }

        if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
        }

        Write-Host "Stopped existing ActivityWatch Fleet Server PID $($process.ProcessId)."
    }
}

if (-not $AllowNonAdmin -and -not (Test-IsAdmin)) {
    Write-Error "Run this setup as Administrator. It installs to Program Files, creates a startup task, and opens firewall port 5600."
    exit 1
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
