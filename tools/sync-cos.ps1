# ============ COS asset uploader (v2.1.0 热更新迁移：GitHub Release → 腾讯云 COS 主源) ============
# Usage:
#   sync-cos.ps1 -Mod <modName> -Zip <zipPath> -UpdateJson <updateJsonPath>   # 单 mod 资产 → mods/<mod>/ + 桶根 suite.json upsert 本行
#   sync-cos.ps1 -Index <suiteJsonPath>                                       # 聚合索引 → 桶根 suite.json
# 上传通道 + 单 mod 发版顺手维护桶根 suite.json（v2.3.0；全量聚合/重建仍由套件根 publish-index.ps1
# 负责）。调用方：各仓 release.ps1（gh release create 之后）、publish-index.ps1（index 双发）。
# 桶：survival-log-1302318873 / ap-shanghai，公有读私有写；coscli.exe + coscli.yaml（含密钥，
# 仓外目录不入 git）都在本目录下。客户端消费契约见 RepoClient.CosBase 头注。
param(
    [string]$Mod,         # 单 mod 上传：mod 名（= 桶内 mods/ 子目录名 = 仓键）
    [string]$Zip,         # 单 mod 上传：zip 绝对路径
    [string]$UpdateJson,  # 单 mod 上传：update.json 绝对路径（契约文件，v2.2.0 起含 notes 字段）
    [string]$Versions,    # 单 mod 上传（可选）：versions.json 版本台账绝对路径（v2.2.0 新增；上传前按桶内实际文件过滤）
    [string]$Index        # 聚合上传：suite.json 绝对路径
)
# Continue 而非 Stop（PS5.1 同款坑，见 publish-index.ps1 头注）：coscli 的 logrus 日志走 stderr，
# Stop 下会被包成 NativeCommandError 炸脚本——失败语义由 $LASTEXITCODE 显式判定。
$ErrorActionPreference = 'Continue'
# v2.3.0：套件共享助手（Read-CosJson/Get-ModIdentity/New-SuiteRow/Upsert-SuiteRow/
# Filter-VersionsByBucket；其内部重设 $ErrorActionPreference/$coscli/$cfg 均与本处同值）
. (Join-Path $PSScriptRoot 'suite-common.ps1')
$coscli = Join-Path $PSScriptRoot 'coscli\coscli.exe'
$cfg    = Join-Path $PSScriptRoot 'secrets\coscli.yaml'
$dst    = 'cos://sl/'

if ($Index) {
    & $coscli -c $cfg cp $Index ($dst + 'suite.json')
    if ($LASTEXITCODE -ne 0) { throw 'coscli upload suite.json failed' }
    Write-Host ('=== cos suite.json uploaded ===')
    exit 0
}
if ($Mod) {
    if (-not $Zip -or -not $UpdateJson) { throw 'sync-cos: -Mod requires -Zip and -UpdateJson' }
    # cp 目标写完整对象路径（cos://sl/mods/<mod>/<文件名>）——coscli cp 到"目录"会沿用
    # 源文件名，临时文件名不固定时会传错对象名（实测坑：vj_test.json → mods/<mod>/vj_test.json）
    & $coscli -c $cfg cp $Zip ($dst + 'mods/' + $Mod + '/' + (Split-Path $Zip -Leaf))
    if ($LASTEXITCODE -ne 0) { throw ('coscli upload zip failed: ' + $Mod) }
    # v2.3.0：台账先按桶过滤再传，且必须在 zip 之后——过滤只留桶内实际存在的 asset，
    # 新 zip 未入桶就被当僵尸版本丢行；防本地台账与桶脱节（手删对象/迁移残留）产出 404 版本
    $filtered = $null
    if ($Versions) { $filtered = Filter-VersionsByBucket $Mod $Versions }
    & $coscli -c $cfg cp $UpdateJson ($dst + 'mods/' + $Mod + '/update.json')
    if ($LASTEXITCODE -ne 0) { throw ('coscli upload update.json failed: ' + $Mod) }
    # v2.2.0：版本台账第三件（可选——migrate/老调用方不传时跳过）
    if ($Versions) {
        & $coscli -c $cfg cp $filtered ($dst + 'mods/' + $Mod + '/versions.json')
        if ($LASTEXITCODE -ne 0) { throw ('coscli upload versions.json failed: ' + $Mod) }
    }
    # v2.3.0：本 mod 行自动 upsert 桶根 suite.json（本地 update.json 须按字节读 UTF-8——
    # PS5.1 Get-Content 对无 BOM 文件按 ANSI 解会 mojibake 中文 notes）。整段只警告不炸发版：
    # Continue 下坏 JSON 不抛错只给 $null，不拦会把该 mod 的好行覆盖成全 null 坏行；三件
    # 已入桶且版本一致，重跑本脚本或 publish-index.ps1 全量重建即可补救
    try {
        $upd = [IO.File]::ReadAllText($UpdateJson, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not $upd) { throw 'update.json 解析失败' }
        Upsert-SuiteRow (New-SuiteRow $Mod $upd (Get-ModIdentity $Mod))
    } catch {
        Write-Warning ('suite.json upsert 失败：' + $_.Exception.Message + '；zip/update.json/versions 已上传，重跑本脚本或 publish-index 全量重建补救')
    }
    Write-Host ('=== cos ' + $Mod + ' uploaded → mods/' + $Mod + '/ ===')
    exit 0
}
throw 'sync-cos: nothing to do (-Mod/-Zip/-UpdateJson or -Index required)'
