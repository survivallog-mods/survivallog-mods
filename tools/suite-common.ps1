# ============ Suite shared helpers（发布侧共享助手：COS 事实源读取 + suite.json upsert） ============
# Usage: . <本文件>（dot-source 进调用方脚本；只定义函数和路径变量，不自动执行任何动作）
# 供套件各仓 release.ps1 / publish 脚本共用：桶内 mods/ 目录 = 套件成员事实源；suite.json 行
# v2.3.0 起扩展 guid/display/summary/dll（身份取自各仓 SurvivalLog.<Mod>\modcenter.json）。
# 只走 COS，不碰 GitHub。coscli.exe + coscli.yaml（含密钥，不入 git）都在本目录（见 sync-cos.ps1 头注）。
# Continue 而非 Stop（PS5.1 同款坑，见 sync-cos.ps1 头注）：coscli 的 logrus 日志走 stderr，Stop 下会
# 被包成 NativeCommandError 炸脚本——失败语义由 $LASTEXITCODE 显式判定。
$ErrorActionPreference = 'Continue'
$coscli  = Join-Path $PSScriptRoot 'coscli\coscli.exe'
$cfg     = Join-Path $PSScriptRoot 'secrets\coscli.yaml'
$cosBase = 'https://survival-log-1302318873.cos.ap-shanghai.myqcloud.com'

# ---- 桶内 mods/ 一级目录名（= 套件成员事实源；按名称排序返回） ----
function Get-CosModNames {
    $out = & $coscli -c $cfg ls 'cos://sl/mods/'
    if ($LASTEXITCODE -ne 0) { throw 'coscli ls mods/ failed' }
    $names = foreach ($line in $out) {
        if ($line -match '^\s*mods/([^/]+)/\s+\|\s+DIR') { $Matches[1] }
    }
    return @($names | Sort-Object)
}

# ---- 公有读 URL → PSCustomObject（PS5.1 对无 charset 响应按 ISO-8859-1 解 .Content 会 mojibake，
# 一律 RawContentStream 字节读 + UTF-8 解码——沿用 publish-index.ps1 实证写法；-ErrorAction Stop
# 让 404/网络错以 WebException 进调用方 catch，可按状态码分流） ----
function Read-CosJson {
    param([string]$Url)
    $rw = Invoke-WebRequest -UseBasicParsing -Uri $Url -ErrorAction Stop
    $c = [Text.Encoding]::UTF8.GetString($rw.RawContentStream.ToArray())
    return ($c | ConvertFrom-Json)
}

# ---- mod 身份：读 <仓>/SurvivalLog.<Mod>/modcenter.json 的 id/display/summary；清单缺失回退命名约定 ----
function Get-ModIdentity {
    param([string]$Mod)
    if ($Mod -eq 'ModCenter') {
        # ModCenter 自身无清单（管理端不发 modcenter.json），身份硬编码
        return [ordered]@{ guid = 'com.local.survivallog.modcenter'; display = 'Mod 管理中心'; summary = '' }
    }
    $suiteRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # suite\tools -> suite -> 套件根
    $manifest  = Join-Path $suiteRoot ($Mod + '\SurvivalLog.' + $Mod + '\modcenter.json')
    if (Test-Path $manifest) {
        $m = [IO.File]::ReadAllText($manifest, [Text.Encoding]::UTF8) | ConvertFrom-Json
        return [ordered]@{ guid = $m.id; display = $m.display; summary = $m.summary }
    }
    return [ordered]@{
        guid    = 'com.local.survivallog.' + $Mod.ToLowerInvariant()
        display = $Mod
        summary = ''
    }
}

# ---- suite.json 行构造（字段顺序固定；dll = 套件包内安装路径） ----
function New-SuiteRow {
    param([string]$Mod, $Update, $Identity)
    return [ordered]@{
        mod      = $Mod
        guid     = $Identity.guid
        display  = $Identity.display
        summary  = $Identity.summary
        dll      = 'plugins/SurvivalLog.' + $Mod + '.dll'
        version  = $Update.version
        asset    = $Update.asset
        md5      = $Update.md5
        gamekb   = $Update.gamekb
        assetUrl = $cosBase + '/mods/' + $Mod + '/' + $Update.asset
        notes    = $Update.notes
    }
}

# ---- suite.json upsert：读桶根 -> 按 mod 原地替换/追加（保留其他行原字段与顺序）-> 写临时文件 -> coscli cp 回桶根 ----
function Upsert-SuiteRow {
    param($Row)
    $suite = $null
    try {
        $suite = Read-CosJson ($cosBase + '/suite.json')
    } catch {
        $ex = $_.Exception
        $is404 = ($ex -is [Net.WebException]) -and $ex.Response -and ($ex.Response.StatusCode -eq [Net.HttpStatusCode]::NotFound)
        # catch 只承接 IWR（-ErrorAction Stop）的 WebException：404（桶根尚无 suite.json）从空表开始，
        # 其余（网络/5xx）上抛——否则一次网络抖动会把共享索引覆盖成单行。坏 JSON 不进 catch
        # （Continue 下 ConvertFrom-Json 的错非终止，Read-CosJson 返回 $null），由下方检查兜住
        if ($ex -is [Net.WebException] -and -not $is404) { throw }
        $suite = $null
    }
    if (-not ($suite -is [pscustomobject])) { $suite = $null }   # 坏结构兜底（坏 JSON -> $null / 顶层非对象）从空表开始
    $mods = @()
    if ($suite.mods) { $mods = @($suite.mods) }
    $hit = $false
    for ($i = 0; $i -lt $mods.Count; $i++) {
        if ($mods[$i].mod -eq $Row.mod) { $mods[$i] = $Row; $hit = $true; break }
    }
    if (-not $hit) { $mods = @($mods + $Row) }
    if ($suite -and $suite.PSObject.Properties['mods']) { $suite.mods = $mods; $out = $suite }
    else { $out = [ordered]@{ mods = $mods } }   # 顶层缺 mods 时 PS5.1 对不存在属性赋值抛语句级错，从空表重建
    $temp = Join-Path $env:TEMP 'suite.json'
    [IO.File]::WriteAllText($temp, ($out | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    & $coscli -c $cfg cp $temp 'cos://sl/suite.json'
    if ($LASTEXITCODE -ne 0) { throw 'coscli upload suite.json failed' }
}

# ---- 版本台账过滤：只保留桶内 mods/<Mod>/ 实际存在的 asset 行（含刚上传的新 zip；防僵尸版本），
# 其余顶层字段与行内字段原样保留；返回过滤后临时文件路径 ----
function Filter-VersionsByBucket {
    param([string]$Mod, [string]$VersionsPath)
    # Continue 偏好下 .NET/解析错只终止单条语句不终止函数（实测会带着 $null 继续产出空台账），前置条件显式抛错
    if (-not (Test-Path $VersionsPath)) { throw ('versions file not found: ' + $VersionsPath) }
    $v = [IO.File]::ReadAllText($VersionsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $v.versions) { throw ('versions.json 缺 versions 数组: ' + $VersionsPath) }
    $out = & $coscli -c $cfg ls ('cos://sl/mods/' + $Mod + '/')
    if ($LASTEXITCODE -ne 0) { throw ('coscli ls mods/' + $Mod + '/ failed') }
    $bucketAssets = @{}
    foreach ($line in $out) {
        # 对象行 TYPE 列为存储类型（STANDARD 等），DIR 行排除；文件名 = key 最后一段
        if ($line -match '^\s*mods/[^/]+/(\S+)\s+\|\s+(?!DIR\b)') { $bucketAssets[$Matches[1]] = $true }
    }
    $kept = @($v.versions | Where-Object { $bucketAssets.ContainsKey([string]$_.asset) })
    $v.versions = $kept
    $temp = Join-Path $env:TEMP ('versions_' + $Mod + '_filtered.json')
    [IO.File]::WriteAllText($temp, ($v | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    return $temp
}

# ---- coscli cp 薄封装（失败抛错；目标须写完整对象路径，见 sync-cos.ps1 cp 注） ----
function Upload-File {
    param([string]$LocalPath, [string]$CosObjectPath)
    & $coscli -c $cfg cp $LocalPath $CosObjectPath
    if ($LASTEXITCODE -ne 0) { throw ('coscli upload failed: ' + $CosObjectPath) }
}
