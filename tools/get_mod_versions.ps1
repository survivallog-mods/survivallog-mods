# ============ Shared suite mod-version resolver (dot-source me) ============
# Used by publish.ps1 / build_installer.ps1 / make_install_notes.ps1.
# Single source of truth for: the suite mod list, version.json pins, per-mod csproj versions.
# Version authority (author-defined, rule 1): mod version = repo csproj <Version>;
#   version.json "pins" overrides a mod to ship an ALREADY-RELEASED historical zip
#   (no pull / no gate / no rebuild - byte-identical to the original GitHub Release asset).

# The 13 suite mods bundled by the installer (order = installer component order).
function Get-SuiteModList() {
    return @('BackpackExpand','CabinetSize','FridgeChill','QuickAction','CabinetEverywhere','CabinetBurden','UnlockHub','RobotSpeed','ModCenter','EndlessGuard','PlanPick','PreDisasterSpeed','SaveMgr')
}

# Author pin table from suite version.json (empty table when absent).
function Get-SuitePins() {
    param([Parameter(Mandatory=$true)][string]$suiteDir)
    $j = Get-Content (Join-Path $suiteDir 'version.json') -Raw | ConvertFrom-Json
    if ($j.pins) { return $j.pins } else { return @{} }
}

function Get-ModCsprojVersion() {
    param([Parameter(Mandatory=$true)][string]$root, [Parameter(Mandatory=$true)][string]$mod)
    $csproj = Join-Path $root ($mod + '\SurvivalLog.' + $mod + '\SurvivalLog.' + $mod + '.csproj')
    if (-not (Test-Path $csproj)) { throw ('csproj missing: ' + $csproj) }
    $t = [System.IO.File]::ReadAllText($csproj)
    $mv = [regex]::Match($t, '<Version>([\d.]+)</Version>').Groups[1].Value
    if (-not $mv) { throw ('cannot read <Version>: ' + $csproj) }
    return $mv
}

# Version a mod ships at in this suite release: pins[mod] if pinned, else its csproj version.
function Get-ModShipVersion() {
    param([Parameter(Mandatory=$true)][string]$root, [Parameter(Mandatory=$true)][string]$mod, $pins)
    $p = $pins.$mod
    if ($p) { return $p }
    return Get-ModCsprojVersion $root $mod
}
