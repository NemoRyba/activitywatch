param(
    [switch]$CentralMode
)

$scriptPath = Join-Path $PSScriptRoot "stack.ps1"

if ($CentralMode) {
    & $scriptPath restart -CentralMode
} else {
    & $scriptPath restart
}
