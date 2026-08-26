# One-time helper: close the SMB handle another PC holds on the old
# Watchers-Setup.exe so the build can replace it. Self-elevates.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$open = Get-SmbOpenFile | Where-Object { $_.Path -like '*Watchers-Setup*' }
if ($open) {
    $open | Select-Object Path, ClientComputerName, ClientUserName | Format-List
    $open | Close-SmbFile -Force -Confirm:$false
    Write-Host "Closed. The build can now replace the file."
} else {
    Write-Host "No SMB open on the setup exe. Checking all deployment opens:"
    Get-SmbOpenFile | Where-Object { $_.Path -like '*deployment*' } | Select-Object Path, ClientComputerName | Format-List
}
pause
