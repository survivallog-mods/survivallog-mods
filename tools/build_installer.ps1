$ErrorActionPreference = 'Stop'
$suite = Split-Path $PSScriptRoot -Parent          # <root>\suite（中枢仓 clone）
$root  = Split-Path $suite -Parent                 # <root>\（13 mod 仓 clone 所在父夹）
# 版本号来源（2026-10-28 多仓化）：SuiteVer = suite 根 version.json（作者定义）；
# 各 mod 版本 = 该仓 csproj <Version>；version.json pins 钉版的 mod 用钉版号（与 publish 收包口径一致）
$ver = (Get-Content (Join-Path $suite 'version.json') -Raw | ConvertFrom-Json).suite
if (-not $ver) { throw 'version.json 缺少 suite 字段' }
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'
if (-not (Test-Path $iscc)) { throw ('ISCC 不存在: ' + $iscc) }

Write-Host ('编译安装器 v' + $ver + ' ...')
# per-mod 版本 define（mod 包目录名 = mod 自身版本；Base 用 SuiteVer）
$defines = @('/DSuiteVer=' + $ver)                   # 数组初始化必须在 += 之前（漏掉会拼成单字符串，实锤 2026-11-03）
. (Join-Path $PSScriptRoot 'get_mod_versions.ps1')   # 共享：13 mod 清单 + 钉版/版本解析
$mods = Get-SuiteModList
$pins = Get-SuitePins $suite
foreach ($m in $mods) {
    $mv = Get-ModShipVersion $root $m $pins
    $defines += ('/DVer' + $m + '=' + $mv)
}
& $iscc @defines (Join-Path $suite 'installer\installer.iss')
if ($LASTEXITCODE -ne 0) { throw ('ISCC 编译失败，退出码 ' + $LASTEXITCODE) }

$exe = Join-Path $suite ('release\生存日志MOD安装器_v' + $ver + '.exe')
if (-not (Test-Path $exe)) { throw ('安装器编译产物缺失: ' + $exe) }
Write-Host ('OK: ' + $exe + '  ' + [math]::Round((Get-Item $exe).Length / 1MB, 2) + ' MB')
