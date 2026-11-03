$ErrorActionPreference = 'Stop'
$projRoot = 'E:\Game\Mod\survivallog-mods\suite'
# 版本号唯一来源：suite 根 version.json（仅作者定义，脚本只读）。
# {V} = 套件号（安装器/Base 文件名）；{V_<Mod>} = 该 mod 本轮发版版本
#（钉版 mod 的 zip 版本与套件号不同步，见 get_mod_versions.ps1 的 pins 解析）
$ver = (Get-Content (Join-Path $projRoot 'version.json') -Raw | ConvertFrom-Json).suite
if (-not $ver) { throw 'version.json 缺少 suite 字段' }

$tpl = [System.IO.File]::ReadAllText((Join-Path $projRoot 'tools\install_notes.tpl.txt'))
if ($tpl -notmatch '\{V\}') { throw '模板里没有 {V} 占位符，检查 tools\install_notes.tpl.txt' }
$out = $tpl.Replace('{V}', $ver)

# 逐 mod 版本占位符 {V_<Mod>}：pins 钉版优先，否则该仓 csproj 版本
$root = Split-Path $projRoot -Parent
. (Join-Path $projRoot 'tools\get_mod_versions.ps1')
$pins = Get-SuitePins $projRoot
foreach ($m in (Get-SuiteModList)) {
    $out = $out.Replace(('{V_' + $m + '}'), (Get-ModShipVersion $root $m $pins))
}
if ($out -match '\{V_[A-Za-z]+\}') { throw ('模板里存在未识别的 {V_<Mod>} 占位符: ' + $Matches[0]) }

$dst = Join-Path $projRoot 'release\【必读】安装说明.txt'
# UTF-8 带 BOM：记事本/不同编码环境打开中文不乱码
[System.IO.File]::WriteAllText($dst, $out, (New-Object System.Text.UTF8Encoding($true)))
Write-Host ('OK: ' + $dst + '  （版本引用已统一为 v' + $ver + '）')
