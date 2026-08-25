param(
    [string]$InstallDir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [string]$ServerBase = "http://192.168.0.144:5600",
    [switch]$DryRun,
    [switch]$SkipUpdateCheck
)

$ErrorActionPreference = "Stop"

$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$startScript = Join-Path $InstallDir "start-watchers.ps1"

if (-not (Test-Path $startScript)) {
    throw "start-watchers.ps1 not found at $startScript"
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class AwFleetSessionLauncher
{
    private const int WTS_CURRENT_SERVER_HANDLE = 0;
    private const uint TOKEN_ALL_ACCESS = 0xF01FF;
    private const int SecurityImpersonation = 2;
    private const int TokenPrimary = 1;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO
    {
        public int SessionID;
        [MarshalAs(UnmanagedType.LPStr)]
        public string pWinStationName;
        public int State;
    }

    public struct SessionInfo
    {
        public int SessionId;
        public int State;
        public string UserName;
        public string DomainName;
        public string StationName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public uint cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public uint dwX;
        public uint dwY;
        public uint dwXSize;
        public uint dwYSize;
        public uint dwXCountChars;
        public uint dwYCountChars;
        public uint dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }

    private enum WTS_INFO_CLASS
    {
        WTSUserName = 5,
        WTSDomainName = 7
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSEnumerateSessions(
        IntPtr hServer,
        int Reserved,
        int Version,
        out IntPtr ppSessionInfo,
        out int pCount
    );

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool WTSQuerySessionInformation(
        IntPtr hServer,
        int SessionId,
        WTS_INFO_CLASS WTSInfoClass,
        out IntPtr ppBuffer,
        out int pBytesReturned
    );

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSQueryUserToken(uint SessionId, out IntPtr phToken);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool DuplicateTokenEx(
        IntPtr hExistingToken,
        uint dwDesiredAccess,
        IntPtr lpTokenAttributes,
        int ImpersonationLevel,
        int TokenType,
        out IntPtr phNewToken
    );

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool CreateEnvironmentBlock(
        out IntPtr lpEnvironment,
        IntPtr hToken,
        bool bInherit
    );

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessAsUser(
        IntPtr hToken,
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    public static SessionInfo[] GetSessions()
    {
        IntPtr sessionInfoPtr = IntPtr.Zero;
        int count = 0;
        var sessions = new List<SessionInfo>();

        if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out sessionInfoPtr, out count))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            int dataSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
            long current = sessionInfoPtr.ToInt64();
            for (int i = 0; i < count; i++)
            {
                var nativeSession = (WTS_SESSION_INFO)Marshal.PtrToStructure(
                    new IntPtr(current),
                    typeof(WTS_SESSION_INFO)
                );
                current += dataSize;

                // Do not drop sessions with an unreadable user name here: a failed
                // WTSQuerySessionInformation would otherwise be indistinguishable from
                // "no sessions exist". Filtering happens in PowerShell, where it is logged.
                string userName = QuerySessionString(nativeSession.SessionID, WTS_INFO_CLASS.WTSUserName);

                sessions.Add(new SessionInfo
                {
                    SessionId = nativeSession.SessionID,
                    State = nativeSession.State,
                    UserName = userName,
                    DomainName = QuerySessionString(nativeSession.SessionID, WTS_INFO_CLASS.WTSDomainName),
                    StationName = nativeSession.pWinStationName ?? ""
                });
            }
        }
        finally
        {
            WTSFreeMemory(sessionInfoPtr);
        }

        return sessions.ToArray();
    }

    public static bool LaunchInSession(
        int sessionId,
        string application,
        string arguments,
        string workingDirectory,
        out int processId,
        out string error
    )
    {
        processId = 0;
        error = "";
        IntPtr userToken = IntPtr.Zero;
        IntPtr primaryToken = IntPtr.Zero;
        IntPtr environment = IntPtr.Zero;

        try
        {
            if (!WTSQueryUserToken((uint)sessionId, out userToken))
            {
                error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return false;
            }

            if (!DuplicateTokenEx(
                userToken,
                TOKEN_ALL_ACCESS,
                IntPtr.Zero,
                SecurityImpersonation,
                TokenPrimary,
                out primaryToken
            ))
            {
                error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return false;
            }

            if (!CreateEnvironmentBlock(out environment, primaryToken, false))
            {
                error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return false;
            }

            var startupInfo = new STARTUPINFO();
            startupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
            startupInfo.lpDesktop = "winsta0\\default";

            PROCESS_INFORMATION processInfo;
            var commandLine = new StringBuilder("\"" + application + "\" " + arguments);
            if (!CreateProcessAsUser(
                primaryToken,
                application,
                commandLine,
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                CREATE_UNICODE_ENVIRONMENT,
                environment,
                workingDirectory,
                ref startupInfo,
                out processInfo
            ))
            {
                error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return false;
            }

            processId = (int)processInfo.dwProcessId;
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return true;
        }
        finally
        {
            if (environment != IntPtr.Zero)
            {
                DestroyEnvironmentBlock(environment);
            }
            if (primaryToken != IntPtr.Zero)
            {
                CloseHandle(primaryToken);
            }
            if (userToken != IntPtr.Zero)
            {
                CloseHandle(userToken);
            }
        }
    }

    private static string QuerySessionString(int sessionId, WTS_INFO_CLASS infoClass)
    {
        IntPtr buffer = IntPtr.Zero;
        int bytesReturned = 0;
        if (!WTSQuerySessionInformation(IntPtr.Zero, sessionId, infoClass, out buffer, out bytesReturned))
        {
            return "";
        }

        try
        {
            return Marshal.PtrToStringUni(buffer) ?? "";
        }
        finally
        {
            WTSFreeMemory(buffer);
        }
    }
}
"@

$stateNames = @{
    0 = "Active"
    1 = "Connected"
    2 = "ConnectQuery"
    3 = "Shadow"
    4 = "Disconnected"
    5 = "Idle"
    6 = "Listen"
    7 = "Reset"
    8 = "Down"
    9 = "Init"
}

$launchableStates = @(0, 1)
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startScript

$logDir = Join-Path $env:ProgramData "ActivityWatchFleet\logs"
$logFile = Join-Path $logDir "supervisor.log"
try {
    New-Item -ItemType Directory -Force -Path $logDir -ErrorAction SilentlyContinue | Out-Null
} catch { }

function Write-SupervisorLog {
    param([string]$Message, [switch]$IsWarning)

    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$stamp  $Message"

    if ($IsWarning) { Write-Warning $Message } else { Write-Host $Message }
    try { Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch { }
}

$script:FleetDataDir = Join-Path $env:ProgramData "ActivityWatchFleet"
$script:FleetTokenFile = Join-Path $script:FleetDataDir "fleet-token.txt"
$script:FleetEndpointFile = Join-Path $script:FleetDataDir "server-endpoint.txt"

function Get-FleetToken {
    if (Test-Path $script:FleetTokenFile) {
        try {
            $token = (Get-Content -Path $script:FleetTokenFile -Raw).Trim()
            if ($token) { return $token }
        } catch { }
    }
    return ""
}

function Get-FleetAuthHeaders {
    # The device's credential. Either the shared token provisioned by
    # install-watchers.ps1 -FleetToken, or the device's own key created during
    # enrollment - both live in the same file, and aw-client reads it too.
    # An empty hashtable is exactly what a server with enforcement off expects.
    $token = Get-FleetToken
    if ($token) { return @{ Authorization = "Bearer $token" } }
    return @{}
}

function Get-FleetServerBase {
    <#
      The address the fleet server is reachable at. The build bakes a default
      into $ServerBase, but an admin can move the server to another machine and
      announce the new address; that override is stored here, outside the
      install directory, so a watcher update cannot lose it.
    #>
    param([string]$Fallback)

    if (Test-Path $script:FleetEndpointFile) {
        try {
            $stored = (Get-Content -Path $script:FleetEndpointFile -Raw).Trim().TrimEnd('/')
            if ($stored -match '^https?://') { return $stored }
        } catch { }
    }
    return $Fallback.TrimEnd('/')
}

function Test-FleetEndpoint {
    # Never point the device at an address that is not actually serving an
    # aw-server: the device would go silent and the only way back is a visit.
    param([string]$Endpoint)

    try {
        $info = Invoke-RestMethod -Uri ("{0}/api/0/info" -f $Endpoint.TrimEnd('/')) -Method Get -TimeoutSec 10
        return [bool]($info -and $info.hostname)
    } catch {
        return $false
    }
}

function Set-FleetServerBase {
    param([string]$Endpoint)

    New-Item -ItemType Directory -Force -Path $script:FleetDataDir | Out-Null
    Set-Content -Path $script:FleetEndpointFile -Encoding ASCII -Value $Endpoint.TrimEnd('/') -NoNewline
}

function Invoke-FleetEndpointMigration {
    <#
      Follow a server move announced by the CURRENT server.

      Safety rules, in order of importance:
        1. Only switch to an endpoint this device has just verified is serving
           an aw-server. An announced typo must not strand the device.
        2. Restart the watchers afterwards, because they read --host/--port
           once at startup.
    #>
    param([string]$CurrentBase, [string]$Announced)

    $target = ([string]$Announced).Trim().TrimEnd('/')
    if (-not $target -or $target -notmatch '^https?://') { return $false }
    if ($target -eq $CurrentBase.TrimEnd('/')) { return $false }

    Write-SupervisorLog "Server move announced: '$CurrentBase' -> '$target'. Verifying the new address..."
    if (-not (Test-FleetEndpoint -Endpoint $target)) {
        Write-SupervisorLog "Server move IGNORED: nothing answered at $target. Staying on $CurrentBase." -IsWarning
        return $false
    }

    try {
        Set-FleetServerBase -Endpoint $target
        Write-SupervisorLog "Server move applied; watchers will be restarted to pick up $target"
    } catch {
        Write-SupervisorLog "Could not store the new server address: $($_.Exception.Message)" -IsWarning
        return $false
    }

    # Watchers cache the address from their command line, so they have to be
    # restarted. The supervisor relaunches them on its next pass.
    try {
        $stopScript = Join-Path $InstallDir "stop-watchers.ps1"
        if (Test-Path $stopScript) {
            & $powershell -NoProfile -ExecutionPolicy Bypass -File $stopScript | Out-Null
        } else {
            Get-Process -Name "aw-watcher-*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-SupervisorLog "Could not stop watchers after the server move: $($_.Exception.Message)" -IsWarning
    }
    return $true
}

function Invoke-FleetEnrollment {
    <#
      Give this device a credential without anyone carrying a secret to it.

      The device generates its own high-entropy key, stores it where the
      watchers already look for a token, and registers it with the server. It
      stays "pending" - and writes nothing - until an admin approves it in
      Administration -> Geraete. Events are not lost meanwhile: aw-client
      queues them on disk and flushes once approval lands.
    #>
    param([string]$ApiRoot, [hashtable]$AuthHeaders)

    $token = Get-FleetToken
    $isNew = $false
    if (-not $token) {
        $bytes = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $token = ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
        try {
            New-Item -ItemType Directory -Force -Path $script:FleetDataDir | Out-Null
            Set-Content -Path $script:FleetTokenFile -Encoding ASCII -Value $token -NoNewline
            & icacls.exe $script:FleetTokenFile /inheritance:r /grant:r "*S-1-5-32-544:(F)" "*S-1-5-18:(F)" "*S-1-5-32-545:(R)" | Out-Null
        } catch {
            Write-SupervisorLog "Could not store the device key: $($_.Exception.Message)" -IsWarning
            return
        }
        $isNew = $true
        Write-SupervisorLog "Generated this device's fleet key; requesting enrollment."
    }

    $installedVersion = ""
    $versionFile = Join-Path $InstallDir "package-version.txt"
    if (Test-Path $versionFile) {
        try { $installedVersion = (Get-Content -Path $versionFile -Raw).Trim() } catch { }
    }

    # Re-posting an existing key is idempotent server-side and never downgrades
    # an approved device, so this is safe to do on every start.
    try {
        $body = @{
            device_key = $token
            hostname = $env:COMPUTERNAME
            package_version = $installedVersion
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$ApiRoot/fleet/enroll" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
    } catch {
        if ($isNew) {
            Write-SupervisorLog "Enrollment request failed: $($_.Exception.Message)" -IsWarning
        }
        return
    }

    try {
        $status = Invoke-RestMethod -Uri "$ApiRoot/fleet/enroll/status" -Method Get -TimeoutSec 10 -Headers (Get-FleetAuthHeaders)
        if ($status.status -eq "pending") {
            Write-SupervisorLog "Waiting for an admin to approve this device (Administration -> Geraete)."
        } elseif ($status.status -eq "rejected") {
            Write-SupervisorLog "This device was REJECTED by an admin; it will not be able to send data." -IsWarning
        }
    } catch { }
}

$allSessions = @([AwFleetSessionLauncher]::GetSessions())
Write-SupervisorLog ("Enumerated {0} session(s); running as {1}" -f $allSessions.Count, [Security.Principal.WindowsIdentity]::GetCurrent().Name)

foreach ($candidate in $allSessions) {
    $candidateState = $stateNames[[int]$candidate.State]
    if (-not $candidateState) { $candidateState = "Unknown($([int]$candidate.State))" }
    $candidateUser = if ($candidate.UserName) {
        if ($candidate.DomainName) { "$($candidate.DomainName)\$($candidate.UserName)" } else { $candidate.UserName }
    } else {
        "<no user name>"
    }
    Write-SupervisorLog ("  session {0} state={1} station='{2}' user={3}" -f $candidate.SessionId, $candidateState, $candidate.StationName, $candidateUser)
}

$sessions = @(
    $allSessions | Where-Object {
        ($launchableStates -contains [int]$_.State) -and -not [string]::IsNullOrWhiteSpace($_.UserName)
    }
)

if ($sessions.Count -eq 0) {
    Write-SupervisorLog "No launchable interactive session found; no watchers were started." -IsWarning
}

foreach ($session in $sessions) {
    $stateName = $stateNames[[int]$session.State]
    $userLabel = if ($session.DomainName) {
        "$($session.DomainName)\$($session.UserName)"
    } else {
        $session.UserName
    }

    if ($DryRun) {
        Write-SupervisorLog "Would start watchers for session $($session.SessionId) ($stateName) user $userLabel"
        continue
    }

    $processId = 0
    $errorMessage = ""
    $started = [AwFleetSessionLauncher]::LaunchInSession(
        [int]$session.SessionId,
        $powershell,
        $arguments,
        $InstallDir,
        [ref]$processId,
        [ref]$errorMessage
    )

    if ($started) {
        Write-SupervisorLog "Started watcher launcher PID $processId for session $($session.SessionId) ($stateName) user $userLabel"
    } else {
        Write-SupervisorLog -IsWarning "Could not start watchers for session $($session.SessionId) ($stateName) user $userLabel`: $errorMessage"
    }
}

# --- Watcher auto-update ------------------------------------------------------
# Runs AFTER the watcher launching above so that update problems can never
# block the supervisor's primary job. Every run reports the installed package
# version to the fleet server; when the server offers a different package and
# auto-update is enabled in the admin GUI, the package is downloaded, verified
# by SHA256, and installed by a detached headless run of install-watchers.ps1.

function Invoke-WatcherUpdateCheck {
    param(
        [string]$InstallDir,
        [string]$ServerBase
    )

    $ProgressPreference = "SilentlyContinue"
    # An announced server move overrides the address baked in at build time.
    $effectiveBase = Get-FleetServerBase -Fallback $ServerBase
    $apiRoot = "{0}/api/0" -f $effectiveBase
    $apiBase = "{0}/fleet/watcher-update" -f $apiRoot

    # Make sure this device has a credential and is registered before anything
    # that needs one.
    Invoke-FleetEnrollment -ApiRoot $apiRoot -AuthHeaders (Get-FleetAuthHeaders)
    $authHeaders = Get-FleetAuthHeaders

    $installedVersion = ""
    $versionFile = Join-Path $InstallDir "package-version.txt"
    if (Test-Path $versionFile) {
        try {
            $installedVersion = (Get-Content -Path $versionFile -Raw).Trim().ToLowerInvariant()
        } catch { }
    }

    try {
        # The hostname lets the server answer with a manual "update now"
        # request filed for THIS device in the admin GUI. It rides along on the
        # poll that already happens once a minute - no extra request, and the
        # server never has to reach into the device.
        $manifestUri = "{0}/manifest?hostname={1}" -f $apiBase, [uri]::EscapeDataString($env:COMPUTERNAME)
        $manifest = Invoke-RestMethod -Uri $manifestUri -Method Get -TimeoutSec 10 -Headers $authHeaders
    } catch {
        Write-SupervisorLog "Update check: fleet server unreachable ($($_.Exception.Message))" -IsWarning
        return
    }
    if (-not $manifest) {
        return
    }

    # Follow a server move BEFORE acting on anything else: if the address
    # changed, this run's remaining work belongs to the new server, and the
    # next pass (<=60s away) will do it there.
    if ($manifest.server_endpoint) {
        if (Invoke-FleetEndpointMigration -CurrentBase $effectiveBase -Announced $manifest.server_endpoint) {
            return
        }
    }

    $serverVersion = ""
    if ($manifest.available) {
        $serverVersion = ([string]$manifest.version).Trim().ToLowerInvariant()
    }
    $autoUpdateEnabled = [bool]$manifest.auto_update_enabled
    $versionDiffers = [bool]($manifest.available -and $serverVersion -and ($serverVersion -ne $installedVersion))

    # An admin ticked this device in Administration -> Watcher-Updates. That
    # bypasses the auto-update switch AND installs even when the version
    # already matches, so the button doubles as a repair/reinstall.
    $manualRequested = [bool]$manifest.update_requested
    $requestId = ([string]$manifest.request_id).Trim()
    $updateNeeded = [bool]($manifest.available -and $serverVersion -and ($versionDiffers -or $manualRequested))

    # Cooldown: never re-attempt the same target version within 15 minutes, so a
    # failing update cannot loop once per supervisor run. A manual request skips
    # the cooldown exactly ONCE (tracked by request_id), so a permanently
    # failing install still falls back to the 15-minute rhythm instead of
    # re-downloading the package every minute.
    $updateRoot = Join-Path $env:ProgramData "ActivityWatchFleet\update"
    $stateFile = Join-Path $updateRoot "state.json"
    $cooldownMinutes = 15
    $inCooldown = $false
    $manualBypass = $manualRequested
    if ($updateNeeded -and (Test-Path $stateFile)) {
        try {
            $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
            if ($manualRequested -and $requestId -and ([string]$state.request_id -eq $requestId)) {
                # This exact request was already attempted once.
                $manualBypass = $false
            }
            if (([string]$state.version -eq $serverVersion) -and $state.attempted_ticks) {
                $minutesSince = ((Get-Date).Ticks - [long]$state.attempted_ticks) / 600000000.0
                if ($minutesSince -ge 0 -and $minutesSince -lt $cooldownMinutes) {
                    $inCooldown = $true
                }
            }
        } catch { }
    }

    $updateAllowed = [bool]($autoUpdateEnabled -or $manualRequested)
    $willUpdate = [bool]($updateNeeded -and $updateAllowed -and ((-not $inCooldown) -or $manualBypass))
    $statusMessage = if (-not $manifest.available) {
        "no_package_on_server"
    } elseif ($willUpdate -and $manualRequested) {
        "manual_update_starting"
    } elseif ($manualRequested -and $inCooldown) {
        "manual_update_recently_attempted_waiting"
    } elseif (-not $updateNeeded) {
        "up_to_date"
    } elseif (-not $autoUpdateEnabled) {
        "update_available_auto_update_disabled"
    } elseif ($inCooldown) {
        "update_recently_attempted_waiting"
    } else {
        "update_starting"
    }

    try {
        $statusBody = @{
            hostname = $env:COMPUTERNAME
            version = $installedVersion
            updating = $willUpdate
            message = $statusMessage
            request_id = $requestId
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$apiBase/status" -Method Post -Body $statusBody -ContentType "application/json" -TimeoutSec 10 -Headers $authHeaders | Out-Null
    } catch {
        Write-SupervisorLog "Update check: status report failed ($($_.Exception.Message))" -IsWarning
    }

    if (-not $willUpdate) {
        if ($updateNeeded -and -not $updateAllowed) {
            Write-SupervisorLog "Watcher update $serverVersion is available, but auto-update is disabled on the server."
        }
        return
    }

    if ($manualRequested) {
        Write-SupervisorLog "Watcher update requested from the admin GUI (request $requestId): installed '$installedVersion' -> server '$serverVersion'"
    } else {
        Write-SupervisorLog "Watcher auto-update: installed '$installedVersion' -> server '$serverVersion'"
    }
    $targetDir = Join-Path $updateRoot $serverVersion

    try {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        # Housekeeping: drop update folders for other versions once they are a day old.
        Get-ChildItem -Path $updateRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $serverVersion -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Recurse -Force } catch { }
            }

        # Record the attempt BEFORE doing anything slow, so a crash still cools
        # down. request_id is what makes a manual request bypass the cooldown
        # exactly once.
        $stateJson = @{
            version = $serverVersion
            request_id = $requestId
            attempted_ticks = (Get-Date).Ticks
            attempted_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        Set-Content -Path $stateFile -Encoding ASCII -Value $stateJson

        $payloadPath = Join-Path $targetDir "payload.zip"
        $installerPath = Join-Path $targetDir "install-watchers.ps1"
        Write-SupervisorLog "Downloading watcher package from $apiBase/payload ..."
        Invoke-WebRequest -UseBasicParsing -Uri "$apiBase/payload" -OutFile $payloadPath -TimeoutSec 900 -Headers $authHeaders
        Invoke-WebRequest -UseBasicParsing -Uri "$apiBase/installer" -OutFile $installerPath -TimeoutSec 60 -Headers $authHeaders

        $expectedHash = ([string]$manifest.sha256).Trim().ToLowerInvariant()
        if (-not $expectedHash) { $expectedHash = $serverVersion }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $payloadPath).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            Write-SupervisorLog "Update aborted: payload hash mismatch (expected $expectedHash, got $actualHash)" -IsWarning
            return
        }
        if (-not (Test-Path $installerPath) -or (Get-Item -LiteralPath $installerPath).Length -lt 1024) {
            Write-SupervisorLog "Update aborted: downloaded installer looks incomplete." -IsWarning
            return
        }

        # Detached spawn: the installer stops and replaces the watchers (and this
        # script's on-disk copy), so the supervisor must NOT wait on it.
        $installerArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Headless -KeepExistingSelection -InstallDir "{1}"' -f $installerPath, $InstallDir
        Start-Process -FilePath $powershell -ArgumentList $installerArgs -WindowStyle Hidden | Out-Null
        Write-SupervisorLog "Headless installer started from $installerPath (log: %ProgramData%\ActivityWatchFleet\logs\install-watchers.log)"
    } catch {
        Write-SupervisorLog "Watcher auto-update failed: $($_.Exception.Message)" -IsWarning
    }
}

if (-not $SkipUpdateCheck -and -not $DryRun) {
    try {
        Invoke-WatcherUpdateCheck -InstallDir $InstallDir -ServerBase $ServerBase
    } catch {
        Write-SupervisorLog "Watcher update check failed: $($_.Exception.Message)" -IsWarning
    }
}
