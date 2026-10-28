# ============ Push ModShared from suite to the 12 mod repos ============
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\push_modshared.ps1
# Authority: <suite>\ModShared (the central copy). For each of the 12 mod repos that
# live as sibling folders of the suite clone, mirror ModShared into the repo with
# robocopy /MIR (excluding .git), and only when contents actually changed:
#   git add ModShared && git commit -m "sync ModShared from suite" && git push
# No differences -> prints "up to date" and moves on. Idempotent: safe to re-run.
# ASCII-only on purpose (PS 5.1 reads BOM-less UTF-8 scripts as ANSI).
$ErrorActionPreference = 'Stop'
$suite = Split-Path $PSScriptRoot -Parent          # ...\survivallog-mods\suite
$root  = Split-Path $suite -Parent                 # ...\survivallog-mods (12 repo clones)
$src   = Join-Path $suite 'ModShared'
$mods  = @('BackpackExpand','CabinetSize','FridgeChill','QuickAction','CabinetEverywhere',
           'CabinetBurden','RoleUnlock','RobotSpeed','ModCenter','EndlessGuard','PlanPick',
           'PreDisasterSpeed')

if (-not (Test-Path $src)) { throw ('ModShared source missing: ' + $src) }

$report = @()
foreach ($m in $mods) {
    $repo = Join-Path $root $m
    $dst  = Join-Path $repo 'ModShared'
    if (-not (Test-Path (Join-Path $repo '.git'))) { $report += ('MISSING REPO: ' + $m); continue }

    if (-not (Test-Path $dst)) { New-Item $dst -ItemType Directory -Force | Out-Null }
    # /MIR mirrors (also deletes stray files), /XD .git is defensive; exit codes: 0=in sync,
    # 1..7 = copies happened (ok), >=8 = failure. Bare call: robocopy writes its own console output.
    robocopy $src $dst /MIR /XD .git /NJH /NJS /NDL /NP /NS /NC | Out-Null
    if ($LASTEXITCODE -ge 8) { $report += ('ROBOCOPY FAIL (' + $LASTEXITCODE + '): ' + $m); continue }

    # commit + push only when the mirror actually changed tracked content
    $dirty = @(git -C $repo status --porcelain -- ModShared)
    if ($dirty.Count -eq 0) { $report += ('up to date: ' + $m); continue }

    git -C $repo add ModShared
    if ($LASTEXITCODE -ne 0) { $report += ('GIT ADD FAIL: ' + $m); continue }
    git -C $repo commit -m 'sync ModShared from suite'
    if ($LASTEXITCODE -ne 0) { $report += ('GIT COMMIT FAIL: ' + $m); continue }
    git -C $repo push
    if ($LASTEXITCODE -ne 0) { $report += ('GIT PUSH FAIL: ' + $m); continue }
    $report += ('pushed: ' + $m + ' (' + $dirty.Count + ' path(s))')
}

Write-Host ''
Write-Host '=== push_modshared summary ==='
$report | ForEach-Object { Write-Host ('  ' + $_) }
$pushed = @($report | Where-Object { $_ -like 'pushed:*' }).Count
$uptodate = @($report | Where-Object { $_ -like 'up to date:*' }).Count
$failed = @($report | Where-Object { $_ -match '(FAIL|MISSING REPO):' })
Write-Host ('repos: ' + $mods.Count + '  pushed: ' + $pushed + '  up to date: ' + $uptodate + '  failed: ' + $failed.Count)
if ($failed.Count -gt 0) { throw ('push_modshared failed for ' + $failed.Count + ' repo(s)') }
Write-Host '=== push_modshared done ==='
