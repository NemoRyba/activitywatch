param(
    [string]$TaskName = "ActivityWatch Stack"
)

$ErrorActionPreference = "Stop"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host ("Removed scheduled task '{0}'." -f $TaskName) -ForegroundColor Green
} else {
    Write-Host ("Scheduled task '{0}' was not present." -f $TaskName) -ForegroundColor Yellow
}
