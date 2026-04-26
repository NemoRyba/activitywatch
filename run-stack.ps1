param(
    [switch]$CentralMode
)

$scriptPath = Join-Path $PSScriptRoot "stack.ps1"

if ($CentralMode) {
    & $scriptPath start -CentralMode
} else {
    & $scriptPath start
}
