$ErrorActionPreference = 'Stop'
$suite = Split-Path $PSScriptRoot -Parent          # <root>\suite（中枢仓 clone）
$root  = Split-Path $suite -Parent                 # <root>\（12 mod 仓 clone 所在父夹）
# 版本号来源（2026-10-28 多仓化）：SuiteVer = suite 根 version.json（作者定义）；
# 各 mod 版本 = 该仓 csproj <Version>（publish.ps1 已 pull 后读取，不再用 version.json.mods 字段——已瘦身移除）
$ver = (Get-Content (Join-Path $suite 'version.json') -Raw | ConvertFrom-Json).suite
if (-not $ver) { throw 'version.json 缺少 suite 字段' }
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'
if (-not (Test-Path $iscc)) { throw ('ISCC 不存在: ' + $iscc) }

Write-Host ('编译安装器 v' + $ver + ' ...')
# per-mod 版本 define（mod 包目录名 = mod 自身版本；Base 用 SuiteVer）
$defines = @('/DSuiteVer=' + $ver)
$mods = @('BackpackExpand','CabinetSize','FridgeChill','QuickAction','CabinetEverywhere','CabinetBurden','RoleUnlock','RobotSpeed','ModCenter','EndlessGuard','PlanPick','PreDisasterSpeed')
foreach ($m in $mods) {
    $csproj = Join-Path $root ($m + '\SurvivalLog.' + $m + '\SurvivalLog.' + $m + '.csproj')
    if (-not (Test-Path $csproj)) { throw ('csproj 缺失: ' + $csproj) }
    $t = [System.IO.File]::ReadAllText($csproj)
    $mv = [regex]::Match($t, '<Version>([\d.]+)</Version>').Groups[1].Value
    if (-not $mv) { throw ('无法读取 csproj <Version>: ' + $csproj) }
    $defines += ('/DVer' + $m + '=' + $mv)
}
& $iscc @defines (Join-Path $suite 'installer\installer.iss')
if ($LASTEXITCODE -ne 0) { throw ('ISCC 编译失败，退出码 ' + $LASTEXITCODE) }

$exe = Join-Path $suite ('release\生存日志MOD安装器_v' + $ver + '.exe')
if (-not (Test-Path $exe)) { throw ('安装器编译产物缺失: ' + $exe) }
Write-Host ('OK: ' + $exe + '  ' + [math]::Round((Get-Item $exe).Length / 1MB, 2) + ' MB')
