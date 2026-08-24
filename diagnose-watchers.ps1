$ErrorActionPreference = "Continue"
$installDir = Join-Path ${env:ProgramFiles} "ActivityWatch Fleet Watchers"
$runtimeRoot = Join-Path ${env:LOCALAPPDATA} "ActivityWatchFleet"
$report = Join-Path $PSScriptRoot "watcher-diagnostics.txt"
$lines = New-Object System.Collections.Generic.List[string]
function A([string]$t) { $script:lines.Add($t) }

A "ActivityWatch Fleet watcher diagnostics"
A ("generated : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
A ("computer  : $env:COMPUTERNAME    user: $env:USERDOMAIN\$env:USERNAME")
A ("elevated  : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
A ("session   : " + (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").SessionId)
A ""

A "== 1. running watcher processes =="
$procs = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like "$installDir*" })
if ($procs.Count -eq 0) { A "  NONE RUNNING" }
foreach ($p in $procs) {
    $owner = try { (Invoke-CimMethod -InputObject $p -MethodName GetOwner).User } catch { "?" }
    A ("  PID {0,-7} sess {1,-3} user {2,-16} {3}" -f $p.ProcessId, $p.SessionId, $owner, $p.ExecutablePath)
    A ("      started {0}" -f $p.CreationDate)
}
A ""

A "== 2. scheduled tasks =="
foreach ($n in @("ActivityWatch Fleet Watchers Supervisor","ActivityWatch Fleet System Watcher")) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if (-not $t) { A "  '$n' : NOT REGISTERED"; continue }
    $i = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
    A ("  '$n'")
    A ("      state={0} principal={1} runlevel={2}" -f $t.State, $t.Principal.UserId, $t.Principal.RunLevel)
    A ("      lastRun={0} lastResult={1} nextRun={2}" -f $i.LastRunTime, $i.LastTaskResult, $i.NextRunTime)
    A ("      action={0} {1}" -f $t.Actions[0].Execute, $t.Actions[0].Arguments)
}
A ""

A "== 3. startup shortcut =="
$lnk = Join-Path ([Environment]::GetFolderPath("CommonStartup")) "ActivityWatch Fleet Watchers.lnk"
A ("  $lnk : " + (Test-Path $lnk))
A ""

A "== 4. install dir =="
A ("  $installDir exists: " + (Test-Path $installDir))
foreach ($f in @("start-watchers.ps1","supervise-watchers.ps1","start-system-watcher.ps1","watchers.config.psd1")) {
    $p = Join-Path $installDir $f
    A ("  {0,-26} {1}" -f $f, $(if (Test-Path $p) { (Get-Item $p).LastWriteTime } else { "MISSING" }))
}
$cfg = Join-Path $installDir "watchers.config.psd1"
if (Test-Path $cfg) { A "  --- config ---"; Get-Content $cfg | ForEach-Object { A "  $_" } }
A ""

A "== 5. pid files =="
$pidsDir = Join-Path $runtimeRoot "pids"
if (Test-Path $pidsDir) {
    foreach ($f in Get-ChildItem $pidsDir -File) {
        $val = (Get-Content $f.FullName -Raw).Trim()
        $alive = [bool](Get-Process -Id ([int]$val) -ErrorAction SilentlyContinue)
        A ("  {0,-28} pid={1,-7} alive={2}  written={3}" -f $f.Name, $val, $alive, $f.LastWriteTime)
    }
} else { A "  no pids dir" }
A ""

A "== 6. supervisor dry run =="
$sup = Join-Path $installDir "supervise-watchers.ps1"
if (Test-Path $sup) {
    try { & $sup -DryRun 2>&1 | ForEach-Object { A "  $_" } } catch { A "  ERROR: $($_.Exception.Message)" }
} else { A "  supervise-watchers.ps1 MISSING" }
A ""

A "== 7. server reachability =="
$serverHost = "192.168.0.144"; $serverPort = 5600
try {
    $r = Invoke-WebRequest -Uri "http://${serverHost}:${serverPort}/api/0/info" -UseBasicParsing -TimeoutSec 10
    A ("  HTTP {0}" -f $r.StatusCode)
    A ("  {0}" -f $r.Content)
} catch { A ("  FAILED: " + $_.Exception.Message) }
A ""

A "== 8. last 25 log lines per watcher =="
$logsDir = Join-Path $runtimeRoot "logs\watchers"
if (Test-Path $logsDir) {
    foreach ($f in Get-ChildItem $logsDir -File | Sort-Object Name) {
        A ("  --- {0}  ({1} bytes, {2}) ---" -f $f.Name, $f.Length, $f.LastWriteTime)
        if ($f.Length -gt 0) { Get-Content $f.FullName -Tail 25 | ForEach-Object { A "    $_" } }
    }
} else { A "  no logs dir" }

$lines | Set-Content -Path $report -Encoding UTF8
Write-Host ""
Write-Host "Report written to: $report"
Write-Host ""
