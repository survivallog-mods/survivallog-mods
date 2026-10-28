# ============ Base 基座包打包（自 make_mods_release.ps1 Base 段拆出，2026-10-28 多仓化）============
# 源 = 游戏目录（注入链 + unity-libs + BepInEx.cfg），输出 = suite\release\SurvivalLog.Base_v<version.json suite>.zip
# mod zip 不在本脚本：12 mod 由各仓仓内 release.ps1 -PackageOnly 产出，publish.ps1 编排拷入 suite\release\。
# 版本号唯一来源：suite 根 version.json 的 suite 字段（仅作者定义，脚本只读）
$ErrorActionPreference = 'Stop'
$game     = 'E:\SteamLibrary\steamapps\common\Survival Log'
$projRoot = 'E:\Game\Mod\survivallog-mods\suite'
$relRoot  = Join-Path $projRoot 'release'
$ver = (Get-Content (Join-Path $projRoot 'version.json') -Raw | ConvertFrom-Json).suite
if (-not $ver) { throw 'version.json 缺少 suite 字段' }

# ---------- BASE package ----------
$base = Join-Path $relRoot ('SurvivalLog.Base_v' + $ver)

New-Item (Join-Path $base 'BepInEx\core') -ItemType Directory -Force | Out-Null
New-Item (Join-Path $base 'BepInEx\plugins') -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $game 'BepInEx\core\*') (Join-Path $base 'BepInEx\core') -Force
Copy-Item (Join-Path $game 'dotnet') $base -Recurse -Force
Copy-Item (Join-Path $game 'winhttp.dll') $base -Force
Copy-Item (Join-Path $game 'doorstop_config.ini') $base -Force
Copy-Item (Join-Path $game '.doorstop_version') $base -Force
# unity-libs 预置（2026-10-17）：BepInEx 首启生成 interop 需要未裁剪 Unity 基础库，官方默认
# 从 unity.bepinex.dev 下载 {VERSION}.zip——境外源境内常失败 → mod 静默不生效（玩家实测反馈）。
# 预置整目录（zip+已解压 dll）命中 BepInEx.cfg UnityBaseLibrariesSource 的"同名 zip 本地
# 优先"逻辑，首启全程离线。zip 名 6000.2.7 = 游戏 Unity 版本，游戏大版本升级后需重新取新版
New-Item (Join-Path $base 'BepInEx\unity-libs') -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $game 'BepInEx\unity-libs\*') (Join-Path $base 'BepInEx\unity-libs') -Recurse -Force
# 预置 BepInEx.cfg（安装器里 onlyifdoesntexist，不会覆盖玩家已有配置）：
# [Logging.Disk] Enabled 强制 true——保证玩家机器生成 LogOutput.log，安装说明的排障 FAQ 依赖它
New-Item (Join-Path $base 'BepInEx\config') -ItemType Directory -Force | Out-Null
$cfgDst = Join-Path $base 'BepInEx\config\BepInEx.cfg'
Copy-Item (Join-Path $game 'BepInEx\config\BepInEx.cfg') $cfgDst -Force
$txt = [System.IO.File]::ReadAllText($cfgDst)
$m = [regex]::Match($txt, '(?sm)(\[Logging\.Disk\].*?^Enabled\s*=\s*)false')
if ($m.Success) {
    $txt = $txt.Substring(0, $m.Index) + $m.Groups[1].Value + 'true' + $txt.Substring($m.Index + $m.Length)
    [System.IO.File]::WriteAllText($cfgDst, $txt, (New-Object System.Text.UTF8Encoding($false)))
}
Copy-Item (Join-Path $projRoot 'tools\readme_base.md') (Join-Path $base 'README.md') -Force
$baseZip = Join-Path $relRoot ('SurvivalLog.Base_v' + $ver + '.zip')
if (Test-Path $baseZip) { Remove-Item $baseZip -Force }
Compress-Archive -Path (Join-Path $base '*') -DestinationPath $baseZip -CompressionLevel Optimal

Write-Host ('=== Base 包完成: ' + $baseZip + '  ' + [math]::Round((Get-Item $baseZip).Length/1MB, 2) + ' MB ===')
