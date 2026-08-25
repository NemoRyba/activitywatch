<#
.SYNOPSIS
    Provisions this machine's ActivityWatch Fleet token.

.DESCRIPTION
    The watcher setup EXE is an IExpress self-extractor with a fixed launch
    line, so it cannot forward -FleetToken to install-watchers.ps1. This script
    writes the same file the installer would, so a device installed from the
    EXE can still be given its token without re-running the whole installer.

    The token lives outside the install directory
    (%ProgramData%\ActivityWatchFleet\fleet-token.txt) on purpose: a watcher
    update wipes and re-extracts the install directory, and must not lose it.

    Get the token from the web UI: Administration -> Fleet-Zugriffstoken.

.EXAMPLE
    .\set-fleet-token.ps1 -FleetToken abc123...

.EXAMPLE
    # Verify what is currently provisioned, without changing it
    .\set-fleet-token.ps1 -Show

.EXAMPLE
    # Roll out across the fleet from an admin workstation
    'PC-01','PC-02' | ForEach-Object {
        Copy-Item .\set-fleet-token.ps1 "\\$_\C$\Windows\Temp\" -Force
        Invoke-Command -ComputerName $_ -ScriptBlock {
            & C:\Windows\Temp\set-fleet-token.ps1 -FleetToken $using:token
        }
    }
#>
[CmdletBinding(DefaultParameterSetName = 'Set')]
param(
    [Parameter(ParameterSetName = 'Set', Mandatory = $true, Position = 0)]
    [string]$FleetToken,

    [Parameter(ParameterSetName = 'Show')]
    [switch]$Show,

    [Parameter(ParameterSetName = 'Set')]
    [switch]$AllowNonAdmin,

    # Verify the token against the server before writing it, so a typo is
    # caught on the spot instead of silently stopping the device's recording
    # once enforcement is switched on.
    [Parameter(ParameterSetName = 'Set')]
    [string]$ServerBase = "http://192.168.0.144:5600",

    [Parameter(ParameterSetName = 'Set')]
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

$tokenDir = Join-Path $env:ProgramData "ActivityWatchFleet"
$tokenFile = Join-Path $tokenDir "fleet-token.txt"

function Get-CurrentToken {
    if (-not (Test-Path $tokenFile)) { return $null }
    try {
        $value = (Get-Content -Path $tokenFile -Raw -ErrorAction Stop).Trim()
        if ($value) { return $value }
    } catch { }
    return $null
}

if ($Show) {
    $current = Get-CurrentToken
    if ($current) {
        Write-Host "Fleet token provisioned on $env:COMPUTERNAME"
        Write-Host ("  file   : {0}" -f $tokenFile)
        Write-Host ("  value  : {0}... ({1} chars)" -f $current.Substring(0, [Math]::Min(6, $current.Length)), $current.Length)
    } else {
        Write-Host "No fleet token provisioned on $env:COMPUTERNAME."
        Write-Host "  expected at: $tokenFile"
    }
    return
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $AllowNonAdmin) {
    throw "Run this as Administrator (it writes under %ProgramData% and sets ACLs)."
}

$token = $FleetToken.Trim()
if (-not $token) {
    throw "-FleetToken was empty."
}

if (-not $SkipVerify) {
    # A wrong token is silent until enforcement is switched on, and then the
    # device just stops reaching the server - so check it now.
    $uri = "{0}/api/0/fleet/watcher-update/manifest" -f $ServerBase.TrimEnd('/')
    try {
        $null = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 10 -Headers @{ Authorization = "Bearer $token" }
        Write-Host "Token accepted by $ServerBase."
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 401) {
            throw "The server REJECTED this token (HTTP 401). Copy it again from Administration -> Fleet-Zugriffstoken. Nothing was written."
        }
        Write-Warning "Could not verify the token against $ServerBase ($($_.Exception.Message)). Writing it anyway; re-run with -Show to confirm."
    }
}

New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
Set-Content -Path $tokenFile -Encoding ASCII -Value $token -NoNewline

# Readable by every logged-in user's watchers, writable only by admins.
try {
    & icacls.exe $tokenFile /inheritance:r /grant:r "*S-1-5-32-544:(F)" "*S-1-5-18:(F)" "*S-1-5-32-545:(R)" | Out-Null
} catch {
    Write-Warning "Could not tighten permissions on $tokenFile : $_"
}

Write-Host "Fleet token written to $tokenFile"
Write-Host "The watchers pick it up on their next restart (the supervisor restarts them within a minute)."
