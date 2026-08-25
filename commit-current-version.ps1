param(
    [string]$Message = ""
)

# Commits the current working state across ALL fork-owned git repositories in
# the right order: innermost submodules first, so each parent repo records the
# updated submodule pointers, root last. Nothing is pushed.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "Fleet checkpoint {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm")
}

$git = (Get-Command git.exe -ErrorAction Stop).Source
$committed = @()

function Invoke-RepoCommit {
    param(
        [string]$Path,
        [string]$Label,
        [string]$CommitMessage
    )

    if (-not (Test-Path (Join-Path $Path ".git"))) {
        Write-Host ("SKIP {0} - no git checkout" -f $Label) -ForegroundColor DarkGray
        return
    }

    & $git -C $Path add -A
    if ($LASTEXITCODE -ne 0) {
        throw "git add failed in $Label"
    }

    & $git -C $Path diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("OK   {0} - nothing to commit" -f $Label)
        return
    }

    & $git -C $Path commit -m $CommitMessage | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed in $Label"
    }

    $sha = (& $git -C $Path rev-parse --short HEAD).Trim()
    $branch = (& $git -C $Path rev-parse --abbrev-ref HEAD).Trim()

    if ($branch -eq "HEAD") {
        # Detached HEAD (common in submodules): park the commit on a rescue
        # branch so a later submodule checkout cannot orphan it.
        $rescue = "fleet-checkpoint-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        & $git -C $Path branch $rescue HEAD | Out-Null
        Write-Host ("WARN {0} was on a detached HEAD - commit {1} parked on branch '{2}'" -f $Label, $sha, $rescue) -ForegroundColor Yellow
        $branch = $rescue
    }

    Write-Host ("DONE {0} -> {1} on {2}" -f $Label, $sha, $branch) -ForegroundColor Green
    $script:committed += ("{0} {1} ({2})" -f $sha, $Label, $branch)
}

Write-Host "Committing with message: $Message"
Write-Host ""

# innermost first
Invoke-RepoCommit (Join-Path $repoRoot "aw-server\aw-webui") "aw-server/aw-webui" $Message
Invoke-RepoCommit (Join-Path $repoRoot "aw-server") "aw-server" $Message
foreach ($module in @("aw-core", "aw-client", "aw-watcher-afk", "aw-watcher-window")) {
    Invoke-RepoCommit (Join-Path $repoRoot $module) $module $Message
}
Invoke-RepoCommit $repoRoot "activitywatch (root)" $Message

Write-Host ""
if ($committed.Count -eq 0) {
    Write-Host "Everything was already committed - no new commits created."
} else {
    Write-Host "New commits:"
    $committed | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""
Write-Host "Nothing was pushed. To publish to GitHub, push each repo you changed, e.g.:"
Write-Host "  git -C `"$repoRoot\aw-server\aw-webui`" push"
Write-Host "  git -C `"$repoRoot\aw-server`" push"
Write-Host "  git -C `"$repoRoot\aw-watcher-window`" push"
Write-Host "  git -C `"$repoRoot`" push"
