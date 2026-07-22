param(
    [string]$InstallDir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [switch]$DryRun
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

                string userName = QuerySessionString(nativeSession.SessionID, WTS_INFO_CLASS.WTSUserName);
                if (String.IsNullOrWhiteSpace(userName))
                {
                    continue;
                }

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
$sessions = [AwFleetSessionLauncher]::GetSessions() | Where-Object {
    $launchableStates -contains [int]$_.State
}

foreach ($session in $sessions) {
    $stateName = $stateNames[[int]$session.State]
    $userLabel = if ($session.DomainName) {
        "$($session.DomainName)\$($session.UserName)"
    } else {
        $session.UserName
    }

    if ($DryRun) {
        Write-Host "Would start watchers for session $($session.SessionId) ($stateName) user $userLabel"
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
        Write-Host "Started watcher launcher PID $processId for session $($session.SessionId) ($stateName) user $userLabel"
    } else {
        Write-Warning "Could not start watchers for session $($session.SessionId) ($stateName) user $userLabel`: $errorMessage"
    }
}
