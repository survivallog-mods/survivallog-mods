# ModCenter v2：游戏内更新/安装/卸载 + 冲突体检 + 手动排序 — 设计

> 2026-10-28 头脑风暴定稿方向，作者拍板 + A1 排序机制装机实证通过（§2）。
> 关联：`2026-10-28-repo-split-and-online-update-design.md` §6/§7（update.json 契约与客户端接口已冻结，本文档实现其客户端侧）；
> `2026-10-24-modcenter-design.md`（ModCenter v1 现状）；ModCenter 仓 `DllDisabler.cs`（v1 停用机制，本次部分退役）。
> 版本号：作者定（硬规则 1），本文档一律称 v2。

## 0. 背景与为什么

现状：玩家侧获取/更新套件全靠网盘 zip + 安装器，链路长；同类型第三方 mod（改包类）与套件
功能叠加冲突无任何提示；停用/卸载机制是"退出时分离进程改名"，强杀游戏有失效窗口，卸载留
`.disabled` 残骸。作者诉求（本轮对话原话要点）：

1. 游戏内完成更新、安装、卸载（**接受重启生效**，进程内热换已定案不可行）；
2. 卸载要**彻底**（真删除，不是改名），且**零概率不生效**（强杀也不能让已卸载的 mod 复活）；
3. 冲突体检：有冲突的 mod 行内挂警示标，点击看具体原因，玩家自行决定停/卸谁或调序规避，
   **调序不保证解决所有冲突，风险由玩家自担**；
4. 手动调整加载顺序，降低同类型 mod 冲突概率（对套件与第三方一视同仁）。

## 1. 决策记录（作者已拍板，2026-10-28）

| # | 决策点 | 结论 |
|---|---|---|
| D1 | 热更新口径 | 游戏内检测/下载/落盘 + 重启生效；不做进程内热换 |
| D2 | 卸载彻底度 | 真删除：dll + 该 mod cfg + ModCenter 自身记录全清；执行点在**下次启动、插件加载之前**（强杀零概率失效） |
| D3 | 排序机制 | **A1**：前置清理器 Harmony 改序（A2 Cecil 给第三方 dll 注依赖属性被否——改写玩家文件，对方发新版即失效） |
| D4 | 冲突体检 | 三层全上（已知冲突库 / 运行时补丁碰撞实测 / 功能类型标注），行内警示标 + 点击详情 + 玩家自决 |
| D5 | 安装范围 | 套件 12 组织仓（GitHub Release 拉取）；第三方仍=玩家手丢 dll 面板纳管；**不做第三方商店**（转载红线）；基座修复仍走网盘（拆仓 §11 边界） |
| D6 | 更新触发 | **面板打开时自动查一次**（15 分钟会话缓存 + 手动刷新 60 秒冷却；Ruling 22 定案，T16/D 加固）；**无后台轮询** |
| D7 | 版本比较策略（本地 ≥ 远端时） | **作者拍板（2026-10-28）：只告警不拦截。** 远端 ≠ 本地即给更新入口；本地高于远端时确认窗红字警示"版本回退风险"（如动作加速 2.1.2 → 1.7.0），是否降级由玩家决定；"重装当前版本"入口保留（修复损坏安装） |
| D8 | gamekb 兼容门范围与兜底 | **作者拍板（2026-10-28）：只告警不拦截。** gamekb 与本地游戏版本不符 → **主列表行内 ⊘ 橙色图标**（悬停显原因全文）+ 仓库页行内 ⚠ 原因 + 确认窗红字警示"可能不兼容/闪退"，更新/安装按钮**保持可用**；本地版本读不到 → 标注"未校验游戏版本"照常放行 |
| D9 | 面板交互形态（2026-10-28 看原型后拍板） | **融合式定稿**（仓库入口卡 + 排序模式融入侧栏，不加顶部页签）；列表徽标**全图标化**（⚠ 红=冲突 / ⇄ 橙=碰撞 / ◎ 灰=同域 / ↑ 蓝=可更新点击弹确认 / ⟳ 琥珀=待生效，悬停出完整提示、点击弹详情）；可更新标识**上列表行**，点击弹窗确认更新；排序**拖拽移动**（拖柄 ⋮⋮ + 插入指示线），键盘 ↑↓ 为无障碍替代（WCAG 2.2 AA），**不用按钮堆** |
| D10 | 列表密度（2026-10-28 第二轮微调） | 徽标 18px 圆片（初版 22px 压缩名称被否）；侧栏 280px；行内距/间距收紧（gap 6px）；mod 显示名**去掉"（第三方）"后缀**（分组标题已标明，省出的空间保名称与版本号零截断——三徽标行实测通过） |

## 2. 实证档案（2026-10-28 装机探针，两轮）

探针源码与证据：`suite/tools/_spike_orderpatcher/`（Patcher.cs + evidence_round2.txt；
**一次性探针，dll 已从游戏目录移除，不入发版**）。五项结论：

| # | 验证点 | 结果 |
|---|---|---|
| E1 | `BepInEx\patchers\` 纯前置执行器（无 Patch 方法的 BasePatcher）能否加载并跑 `Initialize()` | ✅（21:54:03 首轮即过） |
| E2 | 补丁器阶段 HarmonyLib 可用性 | ✅ 0Harmony 解析成功、`harmony.Patch` 成功（第二轮 21:58:39） |
| E3 | 挂 `BaseChainloader.ModifyLoadOrder` 在插件加载前生效 | ✅ postfix 在链式加载器排序时触发，拿到全部 20 插件最终序 |
| E4 | 补丁器阶段 plugins 目录文件无锁（真删除前提） | ✅ `File.Delete` dummy 成功 |
| E5 | 加载序实测 | ✅ = GUID 字母序（忽略大小写），与 BepInEx.Core 反汇编一致（`SortedDictionary` + `Utility.TopologicalSort`，无依赖声明的插件纯字母序，**文件名不影响顺序**） |

**关键教训（实现必读）**：Il2CppInterop 的 Harmony 后端（`HarmonySupportComponent.TryResolve`）
对**开放式泛型**抛 `ContainsGenericParameters` 异常——`AccessTools.Method(typeof(BaseChainloader<>), ...)`
不可用；必须挂**封闭泛型** `BaseChainloader<BasePlugin>`（引用类型封闭泛型共享方法体，等价挂到
IL2CPPChainloader 实际执行的方法）。

加载序实测样本（20 插件节选）：`com.dev.survivallog.* → com.ivmakk.survivallog.* → com.local.survivallog.*`
——组间组内均字母序。

## 3. 架构：双件套 + 待办清单契约

四个约束拼出的唯一形状：体检要活在运行态（插件侧）、UI/网络要活在游戏内（插件侧）、
文件操作要活在插件加载前（补丁器侧）、纯退出路径已被作者否决（D2）。

```
┌─ ModCenter 插件本体（BepInEx\plugins\SurvivalLog.ModCenter.dll）──────────┐
│ 面板 UI：仓库页/更新/卸载/体检/排序模式                                    │
│ 网络层：GitHub API + 资产下载 + 镜像回退                                   │
│ 体检三层 + 警示标渲染                                                      │
│ 决策层：比对版本/游戏版本门/写 pending 清单                                │
│ CleanupRunner（T16：补丁器阶段由壳反射唤起；禁碰 IL2CPP）                  │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │ 写/读（唯一介质）
   BepInEx\ModCenter\pending.json（+ staging\ 暂存目录）
               │ 启动时读取执行
┌─ MCShell（BepInEx\patchers\MCShell.dll，永久冻结，T16）──────────────────┐
│ ① 墓碑分支：uninstalled.flag → 删本体+cfg+目录 → 不加载 → 退出              │
│ ② 自更新分支：selfupdate.flag → 加载前替换本体（一次重启生效）              │
│ ③ 定位本体 → Assembly.LoadFrom → 反射调 CleanupRunner.Run()                │
└────────────────────────────────────────────────────────────────────────────┘
```

**单 dll 化（T16 / Ruling 21，方案 A）**：清理逻辑（marker 翻译 / pending 执行 / 顺序覆盖 /
目录 sweep）全部在 ModCenter.dll 内，**游戏内更新 ModCenter 即更新清理逻辑**；`patchers\` 只留
永久冻结的 `MCShell.dll`（1.0.0 仅属性占位，无独立版本线，只有壳接口签名变更才需安装器）。
物理约束（T16 实证）：本体被壳 `Assembly.LoadFrom` 后文件被 CLR 锁定、不可 `File.Delete`，
同程序集身份也不允许同靴重新 `LoadFrom`——自删除/自更新必须两阶段：boot N 写 flag，
boot N+1 壳在加载前执行；自更新由面板写 `selfupdate.flag`，壳加载前替换 → **一次重启生效**。

**pending.json 契约**（ModCenter 写、清理器读执行后重写）：

```jsonc
{
  "ops": [                                  // 幂等：目标不在场即视为成功
    { "op": "delete",  "target": "plugins/SurvivalLog.X.dll" },
    { "op": "delete",  "target": "config/SurvivalLog.X.cfg" },
    { "op": "install", "staged": "staging/x.zip@SurvivalLog.X.dll", "target": "plugins/SurvivalLog.X.dll", "md5": "…" },
    { "op": "disable", "target": "plugins/ThirdParty.dll" },   // → .disabled（可恢复停用）
    { "op": "enable",  "target": "plugins/ThirdParty.dll" }
  ],
  "order": ["guid.a", "guid.b", "…"]        // 可选：顺序覆盖（§4.5）
}
```

失败语义：单条 op 失败保留在清单（下次启动再试），清理器自证文件记录失败原因；
不阻断其余 op 与游戏启动。

## 4. 功能规格

### 4.1 更新

- 发现：`GET https://api.github.com/repos/survivallog-mods/{repo}/releases/latest` → 拉
  `update.json` 资产（拆仓设计 §7 冻结接口，逐字段照用：mod/version/asset/md5/gamekb）。
- 触发时机（Ruling 22 + T16/D）：**面板打开时**自动查一次（15 分钟会话缓存）+ 面板内手动
  "检查更新"（60 秒冷却）；打开面板即触发（12×4=48 < 60 匿名限额，由 15 分钟缓存与 60 秒冷却约束，
  无后台轮询）。fetch 命中 HTTP 403 时限流专门提示（"GitHub 限流，请稍后再试"），不显示成普通
  检查失败。
- 决策：本地 `PluginInfo.Metadata.Version` vs `update.json.version`；**gamekb 兼容提示（D8：只告警不拦截）**——
  update.json 的 gamekb 快照名与本地游戏版本不匹配时，行内显示原因、确认窗红字警示，按钮保持可用
  （本地游戏版本读取通道待实证，见 §6 开放点）。
- 校验：下载 zip 的 MD5 对 update.json。
- 网络：HttpClient；检查超时 5s、下载超时 60s，快速失败不卡面板；GitHub 直连失败自动回退
  **可配置镜像前缀**（cfg，默认值实施时定）；全失败仅提示"有新版，去网盘手动下"，不硬卡。
- 应用：zip 解包校验后暂存 `staging\` → 写 pending `install/replace` → 面板提示"重启生效"，
  附**立即重启**按钮（分离进程等本进程退出 → `steam://rungameid/4164790` 重拉）。
- ModCenter 自身更新走同一机制（自身也是组织仓）；**T16 单 dll 化后清理逻辑随本体更新**——
  面板另写 `selfupdate.flag`，下一靴壳在 LoadFrom 前替换本体（一次重启即加载新程序集与
  新清理逻辑）；引导壳 `MCShell.dll` 永不参与游戏内更新（只有壳接口签名变更才需安装器）。

### 4.2 安装（套件仓库页）

- 面板新页：列出 12 个组织仓；本机未装的显示"安装"，已装的显示版本 + "更新"。
- 安装 = 下载该仓 latest zip → md5 → 暂存 → pending install。重启生效。
- 第三方 mod 安装仍 = 玩家自己丢 dll 进 plugins（面板自动发现纳管，v1 已有）。

### 4.3 卸载

- 范围：目标 dll + `BepInEx\config\` 下该 mod 的 cfg + ModCenter 自身相关记录（marker/清单项）。
  确认框列出将删除的**完整明细**（D2"彻底"口径）。
- 流程：确认 → 写 pending delete（含 cfg）→ 重启时清理器在插件加载前 `File.Delete`（E4 已证无锁）。
- 停用（可恢复）与卸载（彻底）在面板上是两个明确分档动作，文案区分"下次启动不加载/可恢复"
  与"彻底删除所有文件"。
- **ModCenter 完全卸载**（边界，T16 两阶段墓碑）：pending 写删除自身 dll 与自身 cfg（真实
  存在才列）。物理约束：本体被壳 LoadFrom 后文件锁定，不能本靴自删——boot N：CleanupRunner
  不执行自身 dll 的 delete，写 `BepInEx\ModCenter\uninstalled.flag`（时间戳 + cfg 路径）并从
  清单移除（视为已接管）；boot N+1：壳见 flag → 删本体（含 `.disabled`）+ cfg + 整个
  `BepInEx\ModCenter\` 目录（含 flag）→ **不加载本体** → 退出（入口消失）。引导壳
  `MCShell.dll` 为**基座级组件保留**（可用安装器卸载或手动删除）。⇒ 面板自卸载需两次重启；
  弹窗/README 明示此口径。不再有"分离进程自删清理器运行槽"机制。

### 4.4 冲突体检（三层，D4）

- **L1 已知冲突库**：作者维护表（内置随包、随 ModCenter 发版刷新，**不做在线拉表**——网络层保持单链路）；
  字段：匹配键（dll 名或 GUID）×（冲突对象/类型标签/原因文案/建议动作）。首批收录（出处=2026-10-22
  反汇编鉴定档案，匹配键为确切值）：
  - `com.jangfullmoon.storagecapacityexpansion` / `StorageCapacityExpansion.dll` v1.3.0（红标）：
    改写 73 件柜族家具 BagId 至共享包并改包尺寸、强写 ColdRate/PowerCost——冲突对象：CabinetSize、
    BackpackExpand、CabinetEverywhere（间接失效路径=改包时序 × BagCache 镜像错位）；
  - `survivallog.expandedstorage` / `ExpandedStorage`（灰标，低相关）：仅玩家背包扩容/负重 ×10，
    与套件储物类重叠但机制正交——标注"同域共存，自行取舍"；
  - `com.jangfullmoon.karinasprite` / `KarinaSprite.dll`（不收录：纯立绘替换零游戏钩子——档案已排除，
    防止包名误导误报）。
- **L2 补丁碰撞实测**：面板打开时调 `Harmony.GetAllPatchedMethods()` 归组——同一方法被 ≥2 个
  owner（按 HarmonyInstanceId 归属）挂补丁即成一条碰撞记录（方法名 + owner 名单）。这是实测
  数据，能覆盖 L1 未收录的新 mod。注意：对 Il2CppInterop 挂的游戏方法补丁，owner 归属依赖
  HarmonyLib PatchInfo 记账（补丁管线经 PatchManager，理论可用，**实施首任务实机小验**）。
- **L3 功能类型标注**：套件 mod 按功能域打标签（储物/机器人/规划/速度/角色…，Meta 表扩展）；
  报告把"同域共存"列组，**只标注不判定**，避免误报。第三方 mod 仅在进入 L1 名录后带类型。
- **呈现与动作**：mod 列表行内警示标（分级色：L1 命中=红、L2 碰撞=橙、L3 同域=灰）→ 点击弹
  详情（冲突对象、原因、建议：停用一方/卸载一方/尝试调序）→ 调序建议旁固定文案
  **"调整加载顺序只能规避部分冲突（后写覆盖前写类），不能解决数值叠加类冲突，风险自负"**。
  全程不自动替玩家处置。

### 4.5 手动排序

- 面板"排序模式"：对全部已装 mod（套件+第三方）侧栏平铺，**拖拽调序**（拖柄 ⋮⋮ + 上下
  插入指示线）+ 键盘 ↑↓ 无障碍替代（WCAG 2.2 AA；已实现），保存写入 pending.order；
  冲突/碰撞详情弹窗提供**"去调序"入口**（关闭弹窗 → 进入排序模式；Ruling 20，已实现）。
- 生效：清理器在补丁器阶段 Harmony postfix `BaseChainloader<BasePlugin>.ModifyLoadOrder`
  （E2/E3 已证），对 `__result` 做**稳定重排**：出现在 order 中的按序提前，其余保持原相对序。
- **依赖保护**：重排前对 order 做拓扑校验，与 `[BepInDependency]` 硬依赖冲突时尊重依赖序。
  被保护项由清理器每靴写入 `BepInEx\ModCenter\order_protected.txt`（每行 `<guid>\t<被依赖guid>`），
  面板排序视图在工具条披露"被硬依赖保护 N 项：xxx"（无文件不显示；2026-10-29 修复波）。
- 语义边界（面板明示 + 设计红线）：调序只改变"加载即写表/挂补丁"的先后，不改变叠加运算
  本身。

### 4.6 停用机制迁移（v1 DllDisabler 退役）

- `[DisabledTp]` cfg marker 继续作为停用**意图源**（兼容既有存档状态）；执行点从
  "退出时分离进程改名"整体迁移到"清理器启动时改名"：marker=true 且 dll 在场 → 加载前改
  `.disabled`；`.disabled` 在场且 marker=false → 反向改名。
- 迁移动机：退出路径的强杀失效窗口结构性消失（意图在盘上，每次启动先于加载执行）；
  分离进程改名机械（SpawnDisableBatch/残留自愈/Residue 补拉）全部退役删除。
- Tier 2 软停回调（`OnEnabledChanged(false)` 本会话停行为）保留不变。

### 4.7 单 dll 化：清理逻辑并入本体 + 永久冻结引导壳（2026-10-29 T16 / Ruling 21）

~~双槽 A/B 自更新~~——T1 装机实证证伪（同程序集名两份 dll 被 CLR 按身份合并，
`Assembly.Location` 都报 A.dll）→ 中间方案"单槽 MCCleaner.dll 基座级"（Ruling 8）→
**T16 作者拍板方案 A 单 dll 化，Ruling 8 的清理器定位作废**：

- 清理逻辑（marker 翻译 / pending 执行 / 顺序覆盖 / 目录 sweep）全部并入
  `BepInEx\plugins\SurvivalLog.ModCenter.dll`（`CleanupRunner.Run()`，禁碰 IL2CPP 类型）；
  **游戏内更新 ModCenter 即更新清理逻辑**，版本线只有一条（csproj `<Version>`）。
- `BepInEx\patchers\MCShell.dll` 是**永久冻结**的引导壳（`[PatcherPluginInfo]` 版本固定
  1.0.0 仅属性占位，不构成版本线）：补丁器阶段 `Assembly.LoadFrom` 本体 → 反射调
  `CleanupRunner.Run()`；墓碑/自更新两分支见 §3/§4.3。只有壳接口签名（flag 格式 /
  Run 签名）变更才需要随安装器更新壳。
- 执行器守卫：install/replace 目标为 `MCShell.dll` / 旧 `MCCleaner.dll`（任意目录）或
  `patchers\` 下任何文件 → 拒绝执行并留证据（基座级组件不走游戏内通道）。
- 自更新（一次重启）：面板更新本体时另写 `BepInEx\ModCenter\selfupdate.flag`
  （staged 绝对路径 / staged md5 / target 绝对路径）；壳在下一靴 LoadFrom **之前**替换本体，
  当靴即加载新程序集。无壳预置时由 CleanupRunner 补写预置并接管，代价=多一次重启。
- 自卸载（两阶段）：boot N 写 `uninstalled.flag`；boot N+1 壳删本体+cfg+目录后不加载。
- 物理依据（T16 实证）：已加载程序集文件 `File.Delete` 失败（UnauthorizedAccess）；
  同程序集身份同靴重新 `LoadFrom` 抛 `FileLoadException: Assembly with same name is already
  loaded`。因此自操作一律"下一靴加载前执行"，不在本靴硬来。

## 5. 与现有系统的关系 / 改动面

| 对象 | 改动 |
|---|---|
| ModCenter 插件本体 | 新增：仓库页/更新/卸载/体检/排序的 UI 与逻辑、网络层、pending 写入；Meta 扩 L1/L3 表；**T16：CleanupRunner 迁入（清理执行体）** |
| 新组件 | **MCShell 引导壳**（T16）：`BepInEx\patchers\MCShell.dll`，永久冻结；只引用 BepInEx.Core / Preloader.Core，通过反射调本体 CleanupRunner；无独立版本线 |
| DllDisabler | 退出改名+分离进程+残留自愈退役；marker 解析与 Tier2 软停保留并入本体/CleanupRunner |
| 发版链 | ModCenter 仓 `release.ps1` 打包布局：zip 内含 `BepInEx\plugins\SurvivalLog.ModCenter.dll` + `BepInEx\patchers\MCShell.dll` + `README.md`；旧 `MCCleaner.dll` 由安装器 `[InstallDelete]` 清理；update.json 不变（仍一个 zip） |
| 文档 | ModCenter 仓 DESIGN.md 按 per-mod 文档规则同步；本设计进 specs |
| 面板契约 | panel.js 新页/新模式/警示标；MC_* 消息协议向后兼容扩展；**D6：MC_OPEN 触发仓库自动查（Ruling 22）** |

## 6. 非目标与开放点（实施时收口）

**非目标**：进程内热换；第三方 mod 商店/代下载；BepInEx 基座自动安装；自动处置冲突；
后台静默轮询更新。

**开放点**（按实施顺序）：
1. L2 的 `GetAllPatchedMethods()` 对 Il2CppInterop 补丁的 owner 归属——实机小验；
2. gamekb 兼容门的"本地游戏版本读取通道"——探针实证（拆仓设计 §7 已列为待实证项）；
3. 镜像前缀默认值与回退策略实测选型（境内可达性）；
4. 排序拓扑校验的具体算法（依赖图取自 PluginInfo.Dependencies，面板预览提示）；
5. pending.json 并发写保护（本体主线程唯一写者 + 清理器启动早期唯一写者，时序天然隔离，写前原子替换文件）。

## 7. 验收清单（装机，实施完成门）

1. 更新全链：装旧版 → 面板查到新版 → 下载 md5 过 → 重启 → 新版在役、旧文件无残留；
2. gamekb 告警：构造版本不符的 update.json → 行内原因 + 确认窗红字警示，按钮仍可用（D8 不拦截）；
3. 卸载彻底：卸载后 plugins/config/ModCenter 记录三处无残留；**强杀场景**（卸载意图写入后
   taskkill 游戏二次启动）依然完成删除，被卸载 mod 不复活；
4. 排序：order 改动后自证文件记录的实际加载序随之变化；依赖冲突项被保护并有提示；
5. 体检：L1 样例（Karina 改包名）触发红标；L2 报告非空（套件自身补丁互撞场景）；L3 同域成组；
6. 停用迁移：marker 停用/启用经清理器路径行为与 v1 等价（重启级不加载/可恢复）；
7. ModCenter 自更新（T16 口径）：游戏内更新本体 → 重启一次 → 新版在役，且清理证据行
   （`MCCleaner_loaded.txt` 的 `CleanupRunner.Run v<程序集版本>`）带**新程序集版本**，
   证明清理逻辑随 dll 更新；引导壳 `MCShell.dll` 不变（只有壳接口签名变更才需安装器）。
   自卸载两阶段：boot N 写墓碑、本体仍在；boot N+1 本体+cfg+目录删除、游戏正常启动（无面板）。

## 8. 原型

交互原型（2026-10-28 两轮：双变体 → 作者拍板融合式+图标化+拖拽后重做，浏览器实测全绿）：
同目录 `2026-10-28-modcenter-v2-prototype.html`——**融合式定稿**单设计，要点见 D9：
侧栏行内图标徽标（悬停 tooltip 全文 / 点击弹详情或更新确认；图标语言见下）、套件仓库入口卡
（含 D7"可降级更新"、D8"版本告警不拦截"两态演示）、排序模式=侧栏平铺加载序 + 拖拽（插入
指示线）+ 键盘 ↑↓ 替代、卸载确认（dll/cfg/记录明细）、底部待生效条（撤销 / 立即重启）。
图标语言：色随级（红/橙/灰/蓝/琥珀）、形随义（⚠ 冲突 / ⇄ 碰撞 / ◎ 同域 / ↑ 可更新 /
↓ 可降级 / ⊘ 版本兼容告警 / ⟳ 待生效），义不单靠颜色（WCAG 色义规则）。

## 9. 结论

方向（D1–D6）作者已拍板；排序生效机制 A1 已装机实证通过（§2 五项全绿，含唯一已知陷阱的
规避方案）；供给侧（12 组织仓 Release + update.json）已在线。本设计可直接进入任务拆解
（superpowers:writing-plans）。
