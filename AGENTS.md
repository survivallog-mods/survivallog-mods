# AGENTS.md —— 代理操作手册

> 给在本仓库工作的 AI 代理（Codex/Cursor/Claude/ZCode 等）的操作须知。
> 人读入门请走 [README.md](README.md)；机制细节见 `docs/`；本文只放"动手前必须知道的"。

## 一、硬规则（违反即事故，先读这里）

1. **版本号只由作者本人定义**。助手不得自定/自增版本号，双轨单源：**套件号 = suite `version.json` 的 `suite` 字段**（安装器/中枢仓 tag 线）；**mod 版本 = 各 mod 仓 csproj `<Version>`**（各仓 `release.ps1` 与套件 publish 都以它为权威）；CHANGELOG 可代写。
2. **工作树常带作者未提交改动**。提交必须外科手术式：`git add <明确文件清单>`，**禁止 `git add -A` / `git add .`**；对作者已脏（有未提交改动）的文件只能改内容、不得擅自 stage 整文件。
3. **游戏单实例红线**：作者正在玩（SurvivalLog.exe 在跑且内存活跃）时，**绝不等待、绝不杀进程**，任务整体中止择时重试。杀游戏后必须回读 tasklist 确认死透再操作文件（`sleep 3`）。注意 `tasklist | grep` 在 GBK 中文控制台输出不可靠，判断进程看原始输出。
4. **游戏启动方式**：`powershell Start-Process 'steam://rungameid/4164790'`（直接 start exe 会被 Steamworks 转拉导致插件哑火）；表就绪约在主菜单后 15-25 秒。
5. **探针 ≠ 玩家 mod**：`SurvivalLog.ActionProbe` / `ViewportProbe` / `ConfigDumpProbe` 是取证探针，**绝不能进** publish.ps1 的 `$suiteMods` 白名单、安装器 [Files] 与 InstallDelete 名单。
6. **版权红线**：`gamekb/`（游戏 dump/表数据/素材镜像）整目录不入库（.gitignore 已锚定 `/gamekb/`）；他人 N 网 mod 禁止转载分发；`StackLimit999` 有未修复缺陷**禁止发布**。
7. **PowerShell 5.1 编码坑**：.ps1 一律 **ASCII-only**（无 BOM 的 ps1 含中文会乱码/替换不命中）；复杂 node 片段写 .js 文件执行，不 inline 进 bash（反斜杠/括号会被吃）。
8. **构建判退出码**：`"sdk\dotnet\dotnet.exe" build <目录> -c Release > log 2>&1; echo $?`——**禁止**用 `| tail` 管道（退出码被 tail 吃掉，构建失败照样部署旧 dll 的实坑）。
9. **BepInEx 日志强杀不落盘**：插件验证一律用自证文件（trace / `_DONE.txt`），别指望 LogOutput.log。
10. **UI 修复必须先实机/浏览器实测再报"修好"**；同题两轮不过换道，不 promises "最后一次"。
11. **改 mod 必须同步该 mod 的 `DESIGN.md`**（每份末尾有迭代维护清单）；**改挂钩点（Harmony 目标/表字段/字节签名）必须同步 `tools/gamekb/moddeps.json`**。
12. **实证优先**：不猜先查（反汇编/读源码/运行时探针），方案确认后再动手，最小侵入。
13. **外部工具装卸可能拆注入链**（2026-10-24 xmod 卸载实锤拆了 winhttp/dotnet/BepInEx core，见 docs/03 环境事故节）：任何 xmod/修改器/loader 安装或卸载后、以及"mod 全部失效"时，先验三件套——根目录 `winhttp.dll`+`doorstop_config.ini`、`dotnet\` 有货、`BepInEx\core` 有 dll；被拆即重跑套件安装器（勿 /SILENT）。
14. **N网通道确认门**：向 Nexus Mods 推送发版前必须经作者显式触发/确认（publish.ps1 出完 GitHub Release 后不得自动推 N网）；API key 本地单源 `tools/secrets/`（gitignore 已锚定）绝不入库。详见 `docs/08`。
15. **中枢+子项目模型（2026-10-28 v2 迁移后）**：父夹 `E:\Game\Mod\survivallog-mods\`（非 git 仓）下，**12 个 mod 仓 = 开发主场**（组织 `survivallog-mods` 各自独立仓，本地 clone 于父夹 `\<Mod>`，各仓自带 `release.ps1` 单发流水线）；**suite = 中枢**（安装器/Base/工具链/文档/ModShared/探针与存档 mod）。探针三件（ActionProbe/ConfigDumpProbe/ViewportProbe）、StackLimit999、CabinetExpand **只在 suite 存档，绝不发 Release、绝不进安装器**；`gamekb/`、`tools/secrets/`、`发版物料/` **永不入库**；**ModShared 唯一改动源 = suite\ModShared**（`tools\push_modshared.ps1` 单向下行推送 12 仓，镜像内副本是生成物勿手改）。N网推送永远另走确认门（规则 14）。

## 二、环境与路径（本机开发环境）

| 项 | 路径 |
|---|---|
| 父项目夹 | `E:\Game\Mod\survivallog-mods\`（非 git 仓；下含 suite、12 个 mod 仓 clone 与共享目录） |
| suite\（中枢仓） | `E:\Game\Mod\survivallog-mods\suite`（origin=survivallog-mods/survivallog-mods；工具链/安装器/文档/发版物料、ModShared 唯一权威、探针与存档 mod） |
| 12 个 mod 仓 | `E:\Game\Mod\survivallog-mods\<Mod>\`（各自 git 仓=组织仓=开发主场，仓内 `release.ps1` 单发流水线；`SurvivalLog.<Mod>\` 为工程目录） |
| 父夹级共享目录 | `gamekb\`（游戏资料库，本地 only 永不入库）、`sdk\dotnet\`（便携 .NET SDK，构建依赖）、`thirdparty\`（第三方 N 网 mod 本地参考，禁转载）、`发版物料\`（本地） |
| 游戏本体 | `E:\SteamLibrary\steamapps\common\Survival Log`（AppID 4164790，Unity 6000.2.7f2，IL2CPP，Steam 注册表 HKCU:\SOFTWARE\Valve\Steam → libraryfolders.vdf 定位） |
| 存档 | `C:\Users\<user>\AppData\LocalLow\LLS\SLGame\Saves\` |
| 注入链 | 游戏根目录 `winhttp.dll`(Doorstop) + `dotnet\` + `BepInEx\`（约 138MB）；Steam 重装/校验不会清除 |
| mod 部署 | 拷 dll 到 `<游戏>\BepInEx\plugins\`（interop 由 BepInEx 在游戏更新后自动重生，重生需一次启动） |
| 游戏资料库 | `E:\Game\Mod\survivallog-mods\gamekb\<日期>_<buildid>\`（本地留存：il2cpp dump 三件套 / binaries / webui 镜像 / tables 表数据 / meta.json / diff 报告） |

## 三、常用命令速查

```bash
# 构建（判退出码，见硬规则 8；sdk 为父夹级共享目录）
"E:/Game/Mod/survivallog-mods/sdk/dotnet/dotnet.exe" build "E:/Game/Mod/survivallog-mods/<Mod>/SurvivalLog.<Mod名>" -c Release > build.log 2>&1; echo $?

# 单 mod 发版（各仓仓内；版本号=该仓 csproj <Version>，作者定义）
powershell -File "E:\Game\Mod\survivallog-mods\<Mod>\release.ps1"

# ModShared 下行同步（唯一改动源=suite\ModShared → 12 仓；幂等，有差异才提交推送）
powershell -File "E:\Game\Mod\survivallog-mods\suite\tools\push_modshared.ps1"

# 套件发版（作者在 suite version.json 定套件号 + CHANGELOG 补节后；编排 12 仓 -PackageOnly）
powershell -File "E:\Game\Mod\survivallog-mods\suite\tools\publish.ps1"

# 游戏更新后一键同步（快照+diff+兼容核对+[-AutoProbe]启动采表；快照落父夹 gamekb\）
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\Game\Mod\survivallog-mods\suite\tools\gamekb\gamekb_sync.ps1" [-AutoProbe]

# 全套件依赖兼容核对（红=缺方法/字段/签名异常；全绿 exit 0）
node "E:/Game/Mod/survivallog-mods/suite/tools/gamekb/modcompat_check.js" "E:/Game/Mod/survivallog-mods/gamekb/<版本目录>"

# 两版 dump 结构对比（剥 RVA/TypeDefIndex 噪声；--moddeps 取依赖清单做关注列表）
node "E:/Game/Mod/survivallog-mods/suite/tools/gamekb/dumpdiff.js" gamekb/<旧>/il2cpp/dump.cs gamekb/<新>/il2cpp/dump.cs [--moddeps tools/gamekb/moddeps.json]

# 原生字节签名静态验证（如 FridgeChill 天赋上限补丁）
node "E:/Game/Mod/survivallog-mods/suite/tools/gamekb/sigscan.js" "E:/SteamLibrary/steamapps/common/Survival Log/GameAssembly.dll"

# 表数值查询：直接读 gamekb/<版本>/tables/Config_<表名>.json（125 表；5 张非 int 键表仅行数）
```

## 四、两条核心工作流

**游戏更新后**（docs/07 §5/§8）：
`gamekb_sync.ps1` → 过目 `diff_from_*.md`（类型增删/变更 + modcompat 结果）→ modcompat 全绿 → 实机启动一次看各 mod 自证"生效" → 有红灯才改代码（修复落在对应 mod 仓）→ **各仓发版走快车道：仓内 CHANGELOG 补节 + csproj 改号（作者）+ `.\release.ps1`**；动到安装器/Base 才需要套件线 publish。

**发版**（docs/05，两条线）：
- **单 mod 线**（常用）：改码→commit→该仓 `CHANGELOG.md` 补节→该仓 csproj `<Version>` 改号（作者）→ 仓内 `.\release.ps1`（闸门=本仓干净树仅放行 CHANGELOG 脏改动；构建→打包+cfg 归一→update.json→tag `v<版本>`+Release 双资产；`-PackageOnly` 供套件编排）。
- **套件线**：作者在 suite `version.json` 定套件号（各 mod 版本以各仓 csproj 为权威）→ CHANGELOG 补该版小节 → `tools\publish.ps1`（拉取 12 仓→逐仓 `release.ps1 -PackageOnly`→Base→安装器→回归→网盘组装→中枢仓 tag `v<套件号>`+GitHub Release 仅说明）。
N网通道在任一线发完之后另走 docs/08 确认门：**必须作者显式触发/确认才推送**。

## 五、文档地图

| 文档 | 内容 |
|---|---|
| `docs/00-目录说明.md` | 文档维护规则、mod 清单口径 |
| `docs/01/02` | 需求/技术设计 |
| `docs/03-教训与红线.md` | 历史事故清单（v1.3.2 等） |
| `docs/04/05` | 版本历史 / 版本管理与发版机制（渠道分工） |
| `docs/06-WebUI调试通道与源码地图.md` | DevTools 9222 白盒调试、WebUI 源码位置 |
| `docs/07-游戏资料库gamekb.md` | gamekb 设计与机制（同步流程/探针规格/依赖核对） |
| `docs/08-N网自动发版与更新.md` | N网 Upload API 发版通道（确认门/API key 红线/常表） |
| 各仓 `SurvivalLog.<Mod>\DESIGN.md` | 各 mod 设计文档（含迭代维护清单；位于父夹 `<Mod>\` 各 mod 仓内）；suite 内仅存档 mod（StackLimit999/CabinetExpand/探针）的 DESIGN |
| 各仓 `CHANGELOG.md` / `README.md` | 各 mod 仓内的更新说明（单发闸门）与玩家文档 |
| `ModShared\README.md` | 共享源码（防盗署名气泡接线规则；唯一改动源=suite\ModShared） |
| `tools/gamekb/README.md` | gamekb 工具集用法 |

## 六、gamekb 注意事项（2026-10-23 起）

- 游戏侧 `BepInEx\gamekb_tables\<资源版本>\` 是探针的 **_DONE 哨兵目录，勿删**（删了下次启动会重新全量 dump 一遍）；表采集靠 sync 移走整个目录。
- Il2CppDumper 的输出**落在 exe 所在目录**（`tools/il2cppdumper/`，非第三参）；sync 已做防覆盖（exe 目录有未认领产物即拒绝执行）。
- 逆向工具链（Iced 反汇编、E8 调用方扫描、字面量 xref、mdump 等）用法与坑见 docs/06 与工具源码头注释。
