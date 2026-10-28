# ============ 一键发版流水线（多仓编排版，2026-10-28 拆分迁移后）============
# 用法：tools\publish.ps1 [-Yes] [-SkipTest] [-SkipGithub]
#   -Yes        跳过交互确认
#   -SkipTest   跳过安装器回归测试（不建议）
#   -SkipGithub 跳过 git 提交/tag/GitHub Release
# 版本号来源：suite 根 version.json 的 suite 字段（安装器/中枢仓 tag 线，作者定义）；
#   各 mod 版本以各仓 csproj <Version> 为权威（pull 后读取）。
# 布局：本脚本在 <root>\suite\tools\；12 个 mod 仓 clone 在 <root>\<Mod>\（各仓自带 release.ps1）。
# CHANGELOG.md 必须已有该版说明。
param(
    [switch]$Yes,
    [switch]$SkipTest,
    [switch]$SkipGithub
)
$ErrorActionPreference = 'Stop'
$suite   = Split-Path $PSScriptRoot -Parent          # <root>\suite（中枢仓 clone）
$root    = Split-Path $suite -Parent                 # <root>\（12 mod 仓 clone 所在父夹）
$tools   = $PSScriptRoot
$relRoot = Join-Path $suite 'release'
$ghExe   = Join-Path $tools 'gh\bin\gh.exe'
$orgRepo = 'survivallog-mods/survivallog-mods'       # 中枢仓（套件 Release 仅说明，零资产）
$suiteMods = @('BackpackExpand','CabinetSize','FridgeChill','QuickAction','CabinetEverywhere','CabinetBurden','RoleUnlock','RobotSpeed','ModCenter','EndlessGuard','PlanPick','PreDisasterSpeed')

# ---------- 1. 版本与更新说明一致性 + 确认 ----------
$ver = (Get-Content (Join-Path $suite 'version.json') -Raw | ConvertFrom-Json).suite
if (-not $ver) { throw 'version.json 缺少 suite 字段' }
Write-Host ('=== 发版 v' + $ver + '（多仓编排：12 mod 仓 + Base + 安装器）===')
$logPath = Join-Path $suite 'CHANGELOG.md'
$logTxt  = [System.IO.File]::ReadAllText($logPath)
if ($logTxt -notmatch (('##\s*v' + [regex]::Escape($ver)) + '\b')) {
    throw ('CHANGELOG.md 没有 v' + $ver + ' 的小节：先补该版更新说明再发版。')
}
if (-not $Yes) {
    $a = Read-Host ('确认发版 v' + $ver + '？（拉取 12 仓、重建 zip/安装器，覆盖同名产物）[Y/N]')
    if ($a -notmatch '^[Yy]') { throw '已取消' }
}

# ---------- 2. 12 mod 仓：pull → 读 csproj 版本 → 各仓 release.ps1 -PackageOnly → 收 zip ----------
# 各仓 release.ps1 自含构建与 csproj/Plugin.cs 版本一致性闸门；-PackageOnly 只打包不 tag。
# 注意：必须以子进程 powershell -File 调用（各仓脚本 PackageOnly 路径 exit 0，dot-source 会终止本流水线）。
# release\ 必须先以目录存在——Copy-Item 到不存在的目录路径会把 zip 落成名为 release 的文件（实测踩坑）
if (Test-Path $relRoot -PathType Leaf) { throw ($relRoot + ' 是文件而非目录（历史事故残留），先手工删除再发版') }
New-Item $relRoot -ItemType Directory -Force | Out-Null
$mvers = @{}
foreach ($m in $suiteMods) {
    Write-Host ('--- ' + $m + ' ---')
    $repo = Join-Path $root $m
    if (-not (Test-Path (Join-Path $repo '.git'))) { throw ('mod 仓 clone 不存在: ' + $repo) }
    git -C $repo pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw ('git pull --ff-only 失败: ' + $m + '（先处理本地/远端分叉再发版）') }

    $csproj = Join-Path $repo ('SurvivalLog.' + $m + '\SurvivalLog.' + $m + '.csproj')
    if (-not (Test-Path $csproj)) { throw ('csproj 缺失: ' + $csproj) }
    $t = [System.IO.File]::ReadAllText($csproj)
    $mv = [regex]::Match($t, '<Version>([\d.]+)</Version>').Groups[1].Value
    if (-not $mv) { throw ('无法读取 csproj <Version>: ' + $csproj) }
    $mvers[$m] = $mv

    # 防盗署名气泡接线校验（套件规范，见 docs\00 与 ModShared\README.md；源在各仓 clone 内）
    if ($t -notmatch 'ModShared[\\/]WelcomeTip\.cs') {
        throw ($m + ' 的 csproj 未链入 ModShared\WelcomeTip.cs（防盗署名气泡为套件规范）')
    }
    $plug = Get-ChildItem (Join-Path $repo ('SurvivalLog.' + $m)) -Filter '*Plugin.cs' | Select-Object -First 1
    if ($plug -and (([System.IO.File]::ReadAllText($plug.FullName)) -notmatch 'WelcomeTip\.Install')) {
        throw ($plug.Name + ' 缺少 WelcomeTip.Install(Log) 调用（防盗署名气泡为套件规范）')
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'release.ps1') -PackageOnly
    if ($LASTEXITCODE -ne 0) { throw ($m + ' release.ps1 -PackageOnly 失败（退出码 ' + $LASTEXITCODE + '）') }

    $zip = Join-Path $repo ('release\SurvivalLog.' + $m + '_v' + $mv + '.zip')
    if (-not (Test-Path $zip)) { throw ('打包产物缺失: ' + $zip) }
    Copy-Item $zip $relRoot -Force
    # installer.iss 的 [Files] 直接引用 release\SurvivalLog.<Mod>_v<ver>\ 目录（非 zip），
    # 故将各仓 zip 解包成同名目录供 ISCC 使用
    $dir = Join-Path $relRoot ('SurvivalLog.' + $m + '_v' + $mv)
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Write-Host ('OK  ' + $m + '  v' + $mv + '  -> zip + 安装器源目录')
}
Write-Host ('12 mod 仓 PackageOnly 全部完成（版本: ' + (($suiteMods | ForEach-Object { $_ + '=' + $mvers[$_] }) -join ', ') + '）')

# ---------- 3. Base 基座包（源=游戏目录，含 unity-libs 预置与 BepInEx.cfg Logging.Disk=true）----------
& (Join-Path $tools 'make_base_release.ps1')

# ---------- 4. 编译安装器（/D 版本：SuiteVer=version.json；各 mod=该仓 csproj 版本）----------
& (Join-Path $tools 'build_installer.ps1')

# ---------- 5. 生成安装说明（版本引用统一）----------
& (Join-Path $tools 'make_install_notes.ps1')

# ---------- 6. 安装器回归测试（失败即中止，禁止发版）----------
if (-not $SkipTest) {
    & (Join-Path $tools 'test_installer.ps1')
} else {
    Write-Host '!! 已跳过安装器回归测试（-SkipTest）' -ForegroundColor Yellow
}

# ---------- 7. 组装网盘上传目录 ----------
$cfgPath = Join-Path $tools 'publish.config.json'
$syncDir = ''
if (Test-Path $cfgPath) {
    $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
    if ($j.baiduSyncDir) { $syncDir = $j.baiduSyncDir }
}
$syncHint = ''
if (-not $syncDir) {
    foreach ($c in @((Join-Path $env:USERPROFILE 'BaiduNetdiskSync'), (Join-Path $env:USERPROFILE 'Documents\BaiduNetdiskSync'))) {
        if (Test-Path $c) { $syncDir = Join-Path $c '生存日志MOD'; $syncHint = '（自动探测到同步空间；建议把路径回填 tools\publish.config.json）'; break }
    }
}
$stage = if ($syncDir) { $syncDir } else { Join-Path $relRoot 'baidu_upload' }
New-Item $stage -ItemType Directory -Force | Out-Null
$artifacts = @(
    (Join-Path $relRoot ('生存日志MOD安装器_v' + $ver + '.exe')),
    (Join-Path $relRoot '【必读】安装说明.txt'),
    (Join-Path $relRoot ('SurvivalLog.Base_v' + $ver + '.zip'))
)
foreach ($m in $suiteMods) {
    $artifacts += (Join-Path $relRoot ('SurvivalLog.' + $m + '_v' + $mvers[$m] + '.zip'))
}
foreach ($f in $artifacts) {
    if (-not (Test-Path $f)) { throw ('产物缺失: ' + $f) }
    Copy-Item $f $stage -Force
}
Write-Host ('网盘上传目录: ' + $stage + $syncHint + '（' + $artifacts.Count + ' 件：安装器+说明+Base zip+12 mod zip）')

# 说明：GitHub 只做源码管理，中枢仓 Release 仅 tag + 更新说明，不上传任何安装包（安装包只进网盘目录）

# ---------- 8. git 提交 / tag / GitHub Release（中枢仓）----------
if (-not $SkipGithub -and (Test-Path (Join-Path $suite '.git'))) {
    git -C $suite add -A
    if (git -C $suite status --porcelain) {
        git -C $suite commit -m ('release: v' + $ver) | Out-Host
    } else { Write-Host 'git 无变更可提交' }

    $tag = 'v' + $ver
    if (git -C $suite tag -l $tag) {
        Write-Host ('tag ' + $tag + ' 已存在，跳过')
    } else {
        # 必须用附注标签：--follow-tags 只推附注标签，轻量标签推不上去
        git -C $suite tag -a $tag -m ('release ' + $tag)
    }

    # 注意：PS5.1 下 EAP=Stop 时给原生命令加重定向（2>&1/2>$null）可能触发
    # NativeCommandError 终止，所以这里全部裸调用、只看退出码
    $remote = git -C $suite remote | Where-Object { $_ -eq 'origin' }
    if ($remote) {
        git -C $suite push origin --follow-tags HEAD
        if ($LASTEXITCODE -ne 0) { Write-Host '!! git push 失败（看上面输出；tag 已在本地）' -ForegroundColor Yellow }
    } else {
        Write-Host '无 origin 远程，跳过 push'
    }

    if ((Test-Path $ghExe) -and $remote) {
        & $ghExe auth status
        if ($LASTEXITCODE -eq 0) {
            $notes = [regex]::Match($logTxt, ('(?s)##\s*v' + [regex]::Escape($ver) + '\b.*?(?=\r?\n(---|#{1,2}\s)|\z)')).Value.Trim()
            $notesFile = Join-Path $env:TEMP ('release_notes_v' + $ver + '.md')
            [System.IO.File]::WriteAllText($notesFile, $notes, (New-Object System.Text.UTF8Encoding($false)))
            & $ghExe release create $tag --repo $orgRepo --title ('v' + $ver) --notes-file $notesFile
            if ($LASTEXITCODE -ne 0) { Write-Host '!! GitHub Release 创建失败（tag 已打好，可手动重试 gh release create）' -ForegroundColor Yellow }
            else { Write-Host ('GitHub Release ' + $tag + ' 已创建于 ' + $orgRepo + '（仅更新说明，无安装包）') }
        } else {
            Write-Host 'gh 未登录，跳过 GitHub Release（tools\gh\bin\gh.exe auth login）'
        }
    } elseif (-not (Test-Path $ghExe)) {
        Write-Host '未找到 tools\gh\bin\gh.exe，跳过 GitHub Release'
    }
}

# ---------- 9. 清理旧版本产物（不堆积：release 与 baidu_upload 只保留当前版本集）----------
# 锚定版本命名格式（SurvivalLog.X_vN.N(.zip) / 生存日志MOD安装器_vN.N.exe），
# 绝不误删 测试版/预览版（文件名带后缀不匹配锚定模式）、promo、安装说明等。
# 多仓化调整：版本不再全线齐步——保留集 = suite 号（Base/安装器）+ 本轮各 mod csproj 版本
# （旧版逻辑只认套件号，mod 独立升版后会把刚产出的 mod zip/目录误删）。
$keepVers = @($ver) + @($suiteMods | ForEach-Object { $mvers[$_] })
function Remove-OldArtifacts($rootDir) {
    if (-not (Test-Path $rootDir)) { return }
    Get-ChildItem $rootDir | Where-Object {
        $n = $_.Name
        (($_ -is [System.IO.FileInfo]) -and (
            ($n -match '^SurvivalLog\..+_v(?<v>[\d.]+)\.zip$' -and ($Matches['v'] -notin $keepVers)) -or
            ($n -match '^生存日志MOD安装器_v[\d.]+\.exe$' -and $n -ne ('生存日志MOD安装器_v' + $ver + '.exe'))
        )) -or
        (($_ -is [System.IO.DirectoryInfo]) -and $n -match '^SurvivalLog\..+_v(?<v>[\d.]+)$' -and ($Matches['v'] -notin $keepVers))
    } | ForEach-Object {
        Write-Host ('清理旧产物: ' + $_.Name)
        Remove-Item $_.FullName -Recurse -Force
    }
}
Remove-OldArtifacts $relRoot
Remove-OldArtifacts (Join-Path $relRoot 'baidu_upload')

Write-Host ''
Write-Host ('=== v' + $ver + ' 发版完成 ===')
