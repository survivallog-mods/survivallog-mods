# ModCenter v2（游戏内更新/安装/卸载 + 冲突体检 + 手动排序）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 [spec](../specs/2026-10-28-modcenter-lifecycle-v2-design.md)（D1–D10 全定稿）实现 ModCenter v2：游戏内更新/安装/卸载（重启级、启动清理器执行）、三层冲突体检、拖拽排序。

**Architecture:** 双件套——ModCenter 插件本体（UI/网络/体检/决策/写 pending.json）+ MC 启动清理器（`BepInEx\patchers\` 前置执行器：文件操作 + Harmony 改序 + 停用改名，双槽 A/B 自更新），以 `BepInEx\ModCenter\pending.json` 为唯一意图介质。

**Tech Stack:** BepInEx 6 BE（Unity IL2CPP）/.NET 6/手写 JSON（Payload.cs 同款，零外部依赖）/HttpClient/panel.js（内嵌资源）。

**Spec:** `E:\Game\Mod\survivallog-mods\suite\docs\superpowers\specs\2026-10-28-modcenter-lifecycle-v2-design.md`（执行者必读，含 §2 实证档案与 API 陷阱）

## Global Constraints

- 版本号一律作者定（硬规则 1）：计划中版本占位 `1.8.0`，实施时以 csproj 现值+作者指令为准，**不得自定自增**。
- 构建判退出码、禁管道（硬规则 8）：`dotnet build -c Release --nologo`；本机 SDK `E:\Game\Mod\survivallog-mods\sdk\dotnet\dotnet.exe`。
- 装机自证用独立文件（硬规则 9），不依赖 LogOutput.log；游戏根 `E:\SteamLibrary\steamapps\common\Survival Log`。
- 启动游戏必须 `steam://rungameid/4164790`；taskkill 后重启需隔 8~10 秒（Steam 对刚杀实例有延迟）。
- BepInEx BE API 陷阱（spec §2 + 记忆清单）：挂 Harmony 必须用**封闭泛型** `BaseChainloader<BasePlugin>`；无静态 `Chainloader.PluginInfos`；ps1 经 Write 工具须 ASCII/BOM 注意。
- 开发主场=ModCenter 仓（`E:\Game\Mod\survivallog-mods\ModCenter`）；每任务本地 commit（`feat/fix(ModCenter): ...`），push 与发版另走作者门。
- 清理器是**正式组件**（入发版）；`suite/tools/_spike_orderpatcher/` 是一次性探针源码，只作参考、**不入发版**（硬规则 5）。
- 回归夹具 `tools/mc_fixture.js`（DevTools 9222）改 ConfigBridge/Meta/panel.js 后必跑 `menu`+`toggle`；验收前查 ViewportProbe 9222 cfg 已关。
- 迭代改动必须同步 ModCenter 仓 `SurvivalLog.ModCenter/DESIGN.md`（per-mod 文档规则）。
- 面板文案红线：不替玩家做主（体检/降级/版本告警全为"告警+玩家自决"口径）；不用"发版"字眼吓作者。

## Review Focus

1. **强杀中断**（taskkill/断电后 pending 与停用意图必须下次启动仍执行、被卸载 mod 不复活）→ T2 Step6、T4 Step5 的强杀场景实测。
2. **pending.json 特殊字符**（mod 名含引号/反斜杠、路径含空格 "Survival Log"、中文名）→ T2 Step3 的转义用例 + 清理器全程 `-LiteralPath` 等价处理。
3. **清理器自更新死锁**（运行槽锁死自身、槽残留）→ T1 单槽定稿（Ruling 8：基座级组件不走游戏内通道）、T2 拒绝守卫、T15 验收"ModCenter 本体自更新 + 清理器拒绝自装有证据"。
4. **排序 vs 硬依赖冲突**（手动序覆盖 `[BepInDependency]` 硬依赖导致加载失败）→ T3 Step5 拓扑保护测试（构造依赖冲突的 order 断言被保护项保持依赖序）。
5. **网络/版本通道全失败降级**（GitHub 直连+镜像双挂、gamekb 读取通道失败）→ T5 Step5 快速失败不卡面板、T6 Step4 通道失败=「未校验」标注放行，不得整页变砖。

---

### Task 1: 清理器项目骨架 + 生命周期转正

**Files:**
- Create: `ModCenter/MCCleaner/MCCleaner.csproj`（net6.0；引用 BepInEx.Core / BepInEx.Preloader.Core / BepInEx.Unity.IL2CPP / 0Harmony，HintPath 指游戏 core，`Private=false`——抄 `suite/tools/_spike_orderpatcher/SpikeOrderPatcher.csproj`）
- Create: `ModCenter/MCCleaner/CleanerPatcher.cs`

**Interfaces:**
- Produces: `[PatcherPluginInfo("com.local.survivallog.mccleaner", "MC Cleaner", "1.0.0")] public class CleanerPatcher : BasePatcher`，`public override void Initialize()`；自证文件 `Paths.BepInExRootPath + "MCCleaner_loaded.txt"`；后续任务在其 Initialize 末尾追加各执行段。

- [ ] **Step 1: 写 CleanerPatcher 骨架**——Initialize 写自证行（时间戳 + dll Location + 当前槽名：按 `Path.GetFileName(Assembly.Location)` 是否含 "B" 判定 A/B）；无任何 Patch 方法（纯前置执行器形态，探针 E1 已证可行）。
- [ ] **Step 2: 构建**——`dotnet build ModCenter/MCCleaner -c Release`，退出码 0。
- [ ] **Step 3: 装机双槽部署**——产物 dll 复制两份到 `BepInEx\patchers\MCCleanerA.dll`、`MCCleanerB.dll`；启动游戏（steam://）→ 退出 → 查 `MCCleaner_loaded.txt` 出现**两行**（A、B 各一，双槽同装同载，幂等前提）。
- [ ] **Step 4: 清理游戏侧测试痕迹，commit** `feat(ModCenter): MCCleaner 骨架（双槽部署+生命周期自证）`

### Task 2: pending 契约 + 清理器执行器

**Files:**
- Create: `ModCenter/SurvivalLog.ModCenter/Contracts/McPending.cs`（两端 link 编译进 MCCleaner.csproj）
- Modify: `ModCenter/MCCleaner/CleanerPatcher.cs`

**Interfaces:**
- Produces: `McPending` 静态类：`Op { string Type; string Target; string Staged; string Md5; }`（Type ∈ `delete|install|replace|disable|enable`；Target/Staged 均为 BepInEx 根相对路径）；`List<Op> Load(string path)` / `void Save(string path, List<Op> ops, List<string> order)` / `List<string> LoadOrder(string path)`；手写 JSON（仅对象/数组/字符串/数字/布尔，转义 `\"` `\\` `\n`，UTF-8 无 BOM）。
- Produces: 常量 `McPending.File = BepInExRootPath\ModCenter\pending.json`、`McPending.StagingDir = BepInExRootPath\ModCenter\staging\`。
- Cleaner 执行语义（spec §3）：幂等（目标不在场=成功）；单条失败保留该条并记证据 `BepInEx\MCCleaner_ops.txt`（追加行：时间/操作/结果/原因）；install/replace 先 MD5 校验 staged 失败即该条失败；成功条目从清单移除后**原子重写** pending.json（写临时文件再 File.Replace）。
- **自身槽守卫（spec §4.7 修订后）**：install/replace 的 Target 为 `MCCleaner.dll` 时**拒绝执行**（清理器=基座级组件，不走游戏内通道），证据文件记录"请用安装器更新清理器"。

- [ ] **Step 1: 写 McPending 序列化 + 单元自证**——在 CleanerPatcher 加临时自证分支（cfg 键 `Debug.SelfTest` 默认关；开则对含 `"名\"称\\` 换行、中文、空格路径的 ops 做 Save→Load 往返对拍，结果写 ops 证据）。构建 0。
- [ ] **Step 2: 写执行器**——Initialize 里按序执行：`delete`→`File.Delete`；`install/replace`→校验 MD5→删 Target（在场时）→`File.Copy(staged,target)`；`disable`→`File.Move(target, target+".disabled")`；`enable`→反向。全程拼路径用 `Path.Combine(BepInExRootPath, ...)`，等同 `-LiteralPath` 语义（不吃通配/相对歧义）。
- [ ] **Step 3: 转义用例装机**——手写 pending.json：delete 一个预置假 dll（名字含空格+中文）、install 一个 staged 假 dll（带正确 MD5）、一个 MD5 故意错的 install → 启动 → 断言：假 dll 已删、staged 已就位、坏 MD5 条目保留且证据有失败原因、清单只剩坏条目。
- [ ] **Step 4: 幂等复跑**——不改动再启动一次 → 坏条目仍保留、无异常、无重复副作用。
- [ ] **Step 5: 清测试痕迹，commit** `feat(ModCenter): pending 契约与清理器执行器（幂等/MD5/原子重写）`

### Task 3: 顺序覆盖（Harmony 改序 + 依赖保护）

**Files:**
- Modify: `ModCenter/MCCleaner/CleanerPatcher.cs`

**Interfaces:**
- Consumes: `McPending.LoadOrder`（T2）。
- Produces: Cleaner 内 `Postfix(object __instance, IList<PluginInfo> __result)` 挂 `AccessTools.Method(typeof(BaseChainloader<BepInEx.Unity.IL2CPP.BasePlugin>), "ModifyLoadOrder")`（**封闭泛型**，spec §2 教训）；稳定重排算法：`order` 中出现的项按序前置，其余保持原相对序。

- [ ] **Step 1: 实装 postfix + 稳定重排**——重排前做依赖保护：对 `__result` 中每个有 `Dependencies`（`DependencyFlags.HardDependency`）的项，若其依赖项被 order 移到其后，则该项跟随依赖项位置（保持依赖在前）；被保护项名单写入 ops 证据。
- [ ] **Step 2: 构建 + 装机**——pending.order 写入把某两个无依赖 mod 对调 + 一组人为依赖冲突（对套件内不存在真实依赖，用「依赖项排后」的构造序即可验证保护分支）→ 启动 → ops 证据记录实际加载序与被保护项。
- [ ] **Step 3: 对拍断言**——证据中的加载序 = 预期（对调生效、依赖项仍在前）；`IL2CPPChainloader.Instance.Plugins` 无加载失败新增。
- [ ] **Step 4: 清痕迹，commit** `feat(ModCenter): 启动清理器加载序覆盖（封闭泛型+依赖保护）`

### Task 4: 停用机制迁移（DllDisabler 退出路径退役）

**Files:**
- Modify: `ModCenter/MCCleaner/CleanerPatcher.cs`（启动时读 `[DisabledTp]` marker → disable/enable 改名）
- Modify: `ModCenter/SurvivalLog.ModCenter/DllDisabler.cs`（删除 SpawnDisableBatch/SpawnReverse/OnQuit/残留补拉机械；保留 marker 解析、Enable/Disable 意图写入、Tier2 软停 `FireEnabledChanged` 重放、缺席行扫描）
- Modify: `ModCenter/SurvivalLog.ModCenter/ModCenterPlugin.cs`（摘除 OnApplicationQuit→OnQuit 调用链）

**Interfaces:**
- Consumes: marker cfg 节名 `DisabledTp`、后缀 `.disabled`（v1 语义不变）；清理器直接解析 ModCenter 自身 cfg 文件（`Paths.ConfigPath + "\SurvivalLog.ModCenter.cfg"`，解析逻辑抄 DllDisabler.ParseMarkerTrues 迁移）。
- Produces: 停用/启用语义不变（面板文案仍"重启级"）；执行点=启动清理器。

- [ ] **Step 1: 迁移实现 + 退役旧机械**（改三文件；构建 0）。
- [ ] **Step 2: 回归装机（正路径）**——面板停用一个第三方 dll → 重启 → `.disabled` 在场、插件不加载；启用 → 反向改名恢复。
- [ ] **Step 3: 回归夹具**——`mc_fixture.js` `menu`+`toggle` 两模式全绿（启停语义未变）。
- [ ] **Step 4: 强杀场景**——停用后不正常退出（taskkill）→ 再启动 → dll 仍被改名禁用（对比 v1 需再等一拍，结构性消失）；toast 文案若无残留概念则同步删。
- [ ] **Step 5: commit** `refactor(ModCenter): 停用执行点迁至启动清理器，退出分离进程机械退役`

### Task 5: 网络层 RepoClient

**Files:**
- Create: `ModCenter/SurvivalLog.ModCenter/RepoClient.cs`
- Modify: `ModCenter/SurvivalLog.ModCenter/ModCenterPlugin.cs`（cfg 绑定）

**Interfaces:**
- Produces: `static class RepoClient { Task<UpdateInfo> FetchLatest(string repoName); Task<string> DownloadAsset(UpdateInfo info, Action<long,long> progress); }`；`UpdateInfo { string Mod, Version, Asset, Md5, Gamekb, string AssetUrl }`（解析 release 的 `update.json` 资产，契约=拆仓设计 §6 五字段）。
- cfg 键：`Network.MirrorPrefix`（默认空=直连；非空时 `https://api.github.com/...` 与资产 URL 前缀替换）、`Network.CheckTimeoutMs`=5000、`Network.DownloadTimeoutMs`=60000。任何失败返回 null/抛出（调用方降级），**绝不定时重试、不阻塞主线程**（Task + Ticker 收割）。

- [ ] **Step 1: 实装 HttpClient 封装**（User-Agent 必带；Accept application/vnd.github+json；zip 下载到 StagingDir 临时名）。
- [ ] **Step 2: 构建装机实测（直连）**——探针路径：临时 cfg `Debug.NetSelfTest`（默认关）对 `survivallog-mods/RobotSpeed` fetch → 写证据文件（版本/md5/耗时）。
- [ ] **Step 3: 镜像选型实测（开放点 3 收口）**——本机分别测 2~3 个镜像前缀可达性（ghproxy 类），把默认值定为**空**（直连）+ README 记镜像示例，结论写任务报告。
- [ ] **Step 4: 失败降级实测**——MirrorPrefix 指向不可达地址 → fetch 秒级失败、游戏面板不卡（探针证据记录失败耗时 < 超时上限即可）。
- [ ] **Step 5: commit** `feat(ModCenter): GitHub 仓库客户端（直连+可配镜像+快速失败）`

### Task 6: 决策层 + gamekb 版本通道

**Files:**
- Create: `ModCenter/SurvivalLog.ModCenter/RepoDecision.cs`
- Create: `ModCenter/SurvivalLog.ModCenter/GameVersion.cs`

**Interfaces:**
- Consumes: `RepoClient.FetchLatest`（T5）、`IL2CPPChainloader.Instance.Plugins`（v1 §4.1①）。
- Produces: `enum RepoState { Ok, Update, Downgrade, Warn, Install }`；`RepoRow { string Name; RepoState State; string Local, Remote, Why; string RepoKey; string Guid; }`；`RepoDecision.Build(List<RepoRow> src)`——本地高于远端=Downgrade（D7 告警不拦）；远端 gamekb ≠ 本地基线=Warn（Why=原因，D8 告警不拦）；未装=Install；相等=Ok。
- Produces: `GameVersion.ReadLocal()`——本地游戏版本读取通道（候选：`Application.version`/il2cpp 侧 `UnityEngine.Application.version` interop、或游戏主程序版本文件；**先探针实证据再定**）。通道失败返回 null → 决策层**不判 Warn、标注"未校验游戏版本"**（D8）。
- Produces: `PendingWriter`（静态薄封装调 McPending，主线程唯一写者，Save 防抖复用 ConfigBridge.MarkDirty 模式）。

- [ ] **Step 1: gamekb 通道探针（开放点 2 收口）**——探针 dump `Application.version` 等 2~3 候选值进证据，选定通道写任务报告；失败路径（返 null）纳入 GameVersion 契约。
- [ ] **Step 2: 实装决策层**——12 仓 RepoRow 构造（仓清单常量=spec §4.2 的 12 名，含仓键与套件 GUID 映射）。
- [ ] **Step 3: 探针自证**——Debug 键跑一轮 12 仓 fetch+决策，证据文件断言五态各至少一行（构造：本地版本改写或 mock 不做——直接对真仓断言 Ok/Update 两态 + 代码走查 Downgrade/Warn 分支）。
- [ ] **Step 4: 通道失败降级实测**——探针强制 GameVersion 返回 null → 决策输出含"未校验"标注、State 不误报 Warn。
- [ ] **Step 5: commit** `feat(ModCenter): 仓库决策层（五态+gamekb 告警通道）`

### Task 7: 面板·图标徽标系统 + 待生效条

**Files:**
- Modify: `ModCenter/SurvivalLog.ModCenter/panel.js`（CSS 段 + 渲染）
- Modify: `ModCenter/SurvivalLog.ModCenter/Payload.cs`（快照 DTO 增徽标字段）与 `ConfigBridge.BuildSnapshot`

**Interfaces:**
- Consumes: 原型 `modcenter-v2-prototype.html`（specs 目录，视觉与交互的**唯一基准**，照抄 computed 样式勿自算）。
- Produces: 行内七形图标（⚠红冲突/⇄橙碰撞/◎灰同域/↑蓝可更新/↓橙可降级/⊘橙版本告警/⟳琥珀待生效），18px、悬停 title 全文、点击路由：conflict 类→详情弹窗、upd/down/kbw→更新确认弹窗；底部待生效条（清单摘要+撤销+立即重启，重启按钮 T13 前先置灰占位）。
- 快照协议扩展（向后兼容）：mod 行 DTO 增 `ics: [{k:"red|orange|gray|blue|amber", tip, click:"cf|upd"}]`；新消息 `MC_PENDING_SUMMARY`（Pump 推送）。

- [ ] **Step 1: 照原型移植 CSS+渲染**（七形 chips、tooltip、待生效条；样式值照抄原型）。
- [ ] **Step 2: 构建装机目检**——主菜单开面板：徽标渲染、悬停、点击弹窗（conflict 详情用 T11 前的空数据兜底文案）。
- [ ] **Step 3: 回归**——`mc_fixture.js` `menu`+`toggle` 全绿（快照协议向后兼容未破）。
- [ ] **Step 4: commit** `feat(ModCenter): 面板图标徽标系统与待生效条（原型移植）`

### Task 8: 面板·套件仓库页与更新确认

**Files:**
- Modify: `panel.js` / `Payload.cs` / `ConfigBridge.cs`

**Interfaces:**
- Consumes: `RepoDecision.Build`（T6）、`RepoClient`（T5）、`PendingWriter`（T6）。
- Produces: 侧栏"套件仓库"入口卡（计数徽标）→ 主区仓库视图（12 行五态、检查更新、全部更新、← 返回）；更新确认弹窗（版本对比 + 校验/生效说明 + D7 降级红字/D8 版本告警红字 + 橙色"降级到 X"/琥珀"更新"按钮）；确认→下载（进度）→MD5→暂存→写 pending install/replace→行内 ⟳。
- 新消息：`MC_REPO_GET`（面板拉取）→ `MC_REPO_DATA`（快照推送）；`MC_UPD {repoKey}` / `MC_INST {repoKey}` / `MC_UPDALL` / `MC_CHK`（outbox 命令）。

- [ ] **Step 1: 后端路由**——ConfigBridge Pump 处理四命令（fetch/决策在后台 Task，主线程收割写快照推送；下载进度节流推送）。
- [ ] **Step 2: 前端视图+弹窗**（照原型仓库页与 updHtml 红字口径）。
- [ ] **Step 3: 端到端装机实测**——对一个真实旧版本仓（如降装 RobotSpeed 旧 zip 后开面板）：查更→确认→下载→待生效；重启→版本已换新、旧文件被清理器原子替换；D8 伪造（等游戏更新后天然出现，或临时改 GameVersion 探针值）确认红字告警且按钮可用。
- [ ] **Step 4: 回归 + commit** `feat(ModCenter): 套件仓库页与更新确认链（下载/校验/暂存/待生效）`

### Task 9: 面板·排序模式（拖拽）

**Files:**
- Modify: `panel.js` / `ConfigBridge.cs`

**Interfaces:**
- Consumes: `McPending.LoadOrder`/`PendingWriter`。
- Produces: 侧栏底部"加载排序模式"切换 → 侧栏平铺 `S.order` 序（拖柄 ⋮⋮、琥珀插入线、键盘 ↑↓ 替代）、排序工具条（恢复默认/保存）；保存→`MC_ORDER_SAVE {guids[]}`→ 写 pending.order → 待生效条 + ⟳。

- [ ] **Step 1: 前端拖拽**（照原型：dragstart/dragover 上下半区/drop/键盘 focus+Arrow；**排序模式平铺全列表**不分分组——原型定稿行为）。
- [ ] **Step 2: 后端命令**——MC_ORDER_SAVE 校验 guid 白名单（当前 Plugins 键）后落盘。
- [ ] **Step 3: 装机实测**——拖两个 mod 对调→保存→重启→清理器 ops 证据的加载序对拍（复用 T3 Step3 断言法）。
- [ ] **Step 4: 回归 + commit** `feat(ModCenter): 加载排序模式（拖拽+键盘替代+依赖保护提示）`

### Task 10: 面板·卸载与停用动作

**Files:**
- Modify: `panel.js` / `ConfigBridge.cs`（`MC_UNINST {guid}` 命令）

**Interfaces:**
- Consumes: `PluginInfo.Instance as BasePlugin → Config.ConfigFilePath`（v1 §4.1③ 实证写法）定位该 mod cfg；`PendingWriter`。
- Produces: 卸载确认弹窗（将删除明细：dll 相对路径 + cfg 路径 + ModCenter 记录；不受影响说明）；确认→pending 写 delete×2（dll+cfg）+ marker 清理 → 行内 ⟳；ModCenter 自身卸载：弹窗特别文案（清理器运行槽由分离进程收尾自删——复用 v1 StartDetached 模式一次性脚本；此为全系统唯一保留的退出路径分离进程）。

- [ ] **Step 1: 实装命令与明细构造**（dll 相对名复用 DllDisabler.DllRelOf）。
- [ ] **Step 2: 装机实测（spec §7-3）**——卸载一个第三方样例 dll → 重启 → plugins/config/ModCenter 记录三处无残留；**强杀场景**：确认卸载后 taskkill → 二次启动仍完成删除。
- [ ] **Step 3: commit** `feat(ModCenter): 彻底卸载（dll+cfg+记录，强杀免疫）`

### Task 11: 体检 L1 已知冲突库 + L3 功能域标注

**Files:**
- Modify: `ModCenter/SurvivalLog.ModCenter/Meta.cs`（两张静态表）+ `Payload.cs` + `panel.js` + `ConfigBridge.cs`

**Interfaces:**
- Produces: L1 表条目 `{ MatchDll, MatchGuid, Level:"red", Title, Who[], Reason, Tips[] }` 首批三条（spec §4.4 确切值：storagecapacityexpansion 红标 / expandedstorage 灰 / karinasprite 排除）；L3 功能域表 `{ Guid → Domain }`（储物/机器人/规划/速度/角色/面板…，12 套件全覆盖）。
- Produces: 冲突详情弹窗（对象/原因/处置建议/风险文案——照原型 cfHtml）+ 行内红/灰徽标（喂 T7 的 `ics` 字段）。

- [ ] **Step 1: 表数据 + 快照接线**（BuildSnapshot 时按已装列表匹配 L1/L3 产 ics）。
- [ ] **Step 2: 弹窗与文案移植**（照原型）。
- [ ] **Step 3: 装机实测（spec §7-5 前半）**——放一个改名副本 `StorageCapacityExpansion.dll`（内容任意、文件名匹配）进 plugins → 面板红标 + 点击详情内容对拍 spec 首批文案；karinasprite 命名副本不触发（排除分支）。
- [ ] **Step 4: 回归 + commit** `feat(ModCenter): 冲突体检 L1 冲突库与 L3 功能域标注`

### Task 12: 体检 L2 补丁碰撞实测扫描

**Files:**
- Create: `ModCenter/SurvivalLog.ModCenter/PatchScan.cs`
- Modify: `Meta.cs`/`Payload.cs`/`panel.js`（橙标 + 碰撞组数据）

**Interfaces:**
- Produces: `PatchScan.Collisions() → List<{ Method, Owners[] }>`（Harmony.GetAllPatchedMethods → PatchInfo owners 归组，同方法 ≥2 owner 成一条）；扫描时机=面板打开（MC_OPEN）+ 手动刷新。
- **先实证后实装**（开放点 1）：owner 归属对 Il2CppInterop 挂的游戏方法是否可读——探针证据先落，不行则降级为「仅统计 HarmonyLib 记账内方法」并在报告注明。

- [ ] **Step 1: 探针实证**——dump 3~5 个套件已挂方法的 owners 归属进证据，收口结论。
- [ ] **Step 2: 实装扫描 + 橙标/弹窗**（碰撞详情=方法名+owner 名单+建议，文案含"调序仅缓解写序类冲突"）。
- [ ] **Step 3: 装机实测（spec §7-5 中段）**——扫描报告非空（套件自身即有同方法多补丁场景，如柜子系×快速系同挂表方法）；BetterTrade 在场时若实证命中则对拍。
- [ ] **Step 4: 回归 + commit** `feat(ModCenter): 体检 L2 运行时补丁碰撞扫描`

### Task 13: 立即重启助手

**Files:**
- Create: `ModCenter/SurvivalLog.ModCenter/RestartHelper.cs`

**Interfaces:**
- Produces: `RestartHelper.Request()`——拉分离 PowerShell（v1 StartDetached 同款 EncodedCommand 模式）：循环等本进程退出（ SurvivalLog.exe）→ **sleep 9 秒**（Steam 延迟坑）→ `Start-Process 'steam://rungameid/4164790'`；面板待生效条"立即重启"接通（T7 置灰占位换真）；确认弹窗文案提示未保存对局风险。

- [ ] **Step 1: 实装 + 面板接线。构建 0。**
- [ ] **Step 2: 实机实测**——主菜单态点立即重启 → 游戏退出 → ~10 秒内自动重拉进主菜单；确认待生效项已生效（对拍 ops 证据）。
- [ ] **Step 3: commit** `feat(ModCenter): 一键重启（steam 重拉+延迟补偿）`

### Task 14: 发版链与文档同步

**Files:**
- Modify: `ModCenter/release.ps1`（打包布局：zip 内 `BepInEx\plugins\SurvivalLog.ModCenter.dll` + `BepInEx\patchers\MCCleanerA.dll` + `MCCleanerB.dll`；版本一致性检查扩到 MCCleaner.csproj）
- Modify: `suite/installer/installer.iss`（文件表加两清理器槽；InstallDelete 名单核对无新增历史名）
- Modify: `ModCenter/SurvivalLog.ModCenter/DESIGN.md`（v2 章节重写：架构图/双件套/协议/退役记录）
- Modify: `ModCenter/SurvivalLog.ModCenter/CHANGELOG.md`（`## v<作者定号>` 占位节）
- Modify: `tools/gamekb/moddeps.json` + ModCenter `ANCHORS.md`（若挂钩点/依赖面变化）

- [ ] **Step 1: release.ps1 改造**——MCCleaner 构建并入、双槽复制、zip 布局断言；`-PackageOnly` 干跑 → 解包核对三文件在场。
- [ ] **Step 2: 安装器表同步**——编译 iss 干跑（或编译日志检查），文件表/组件对账。
- [ ] **Step 3: 文档三件**——DESIGN.md/CHANGELOG 占位/ANCHORS+moddeps 核对；探针源码 `_spike_orderpatcher` 保留 suite/tools（不入 ModCenter 仓发版面）。
- [ ] **Step 4: commit** `chore(ModCenter): v2 发版布局（双槽清理器）与文档同步`

### Task 15: 终验收（spec §7 全清单）

**Files:** 无新文件（验收任务，报告存 `.superpowers/sdd/<日期>-modcenter-v2/task-15-report.md`）

- [ ] **Step 1: §7 七项逐项装机过**——①更新全链（含旧文件清理）②gamekb 告警（不拦+红字+按钮可用）③卸载彻底+强杀免疫 ④排序生效+依赖保护 ⑤体检三层（红/橙/灰各有实锤）⑥停用迁移等价 ⑦ModCenter 本体自更新全链 + 清理器拒绝游戏内自装（证据留痕，Ruling 8）。
- [ ] **Step 2: 回归夹具六模式全绿 + ViewportProbe 9222 cfg 确认关闭。**
- [ ] **Step 3: 全套冒烟**——正常玩家动线走一遍（查更→更新→重启→体检→停用一个→排序→卸载一个）。
- [ ] **Step 4: 验收报告 + 终审呈作者**（含各步证据文件路径清单）。

---

## 执行顺序依赖

T1→T2→T3/T4（依赖执行器）→T5→T6→T7（可与 T5/T6 并行起步）→T8/T9/T10（依赖 T6/T7）→T11/T12（T12 探针可提前）→T13→T14→T15。T11 与 T8-T10 无耦合可穿插。

---

## 追加任务 T16（2026-10-29 作者拍板方案 A）

**目标**：单 dll 化——patchers\ 只留永久冻结引导壳，清理逻辑并入 ModCenter.dll，游戏内更新即更新清理逻辑。

**Files**：
- Create: `ModCenter/MCShell/MCShell.csproj` + `ShellPatcher.cs`（~40 行：定位 `plugins\SurvivalLog.ModCenter.dll` → `Assembly.LoadFrom` → 反射调 `SurvivalLog.ModCenter.CleanupRunner.Run()`；墓碑分支：见 `BepInEx\ModCenter\uninstalled.flag` 则删 ModCenter.dll+cfg+目录后退出，不加载；异常自吞写证据）
- Create: `ModCenter/SurvivalLog.ModCenter/CleanupRunner.cs`（把 `MCCleaner/CleanerPatcher.cs` 全部执行逻辑迁入：pending 执行/幂等/MD5/原子重写/marker 翻译/顺序覆盖 Harmony/目录 sweep/order_protected 披露/证据落盘；**禁止触碰 IL2CPP 游戏类型**，只用 BepInEx/Harmony/文件 API）
- Delete: `ModCenter/MCCleaner/`（项目与版本线）
- Modify: `release.ps1`（打包 plugins dll + patchers\MCShell.dll；版本一致性检查只对 ModCenter）、`installer/installer.iss`（patchers 文件名改 MCShell.dll；保留 MCCleaner.dll 的 InstallDelete 以便升级清理旧件）
- Modify: `panel.js`/`ConfigBridge.cs`（D6 改回面板打开即查：MC_OPEN 时若会话缓存 >10 分钟则触发 fetch(force=false)）
- Modify: `DESIGN.md`/spec（架构改单壳；Ruling 8 章节重写；自卸载两阶段墓碑；维护规则改为"壳接口签名变更才需安装器"）

**步骤**：
1. **探针先决**：壳在 patcher 阶段 `Assembly.LoadFrom(plugins\ModCenter.dll)` 并反射调用静态方法 → 验证 ①调用成功 ②随后 Chainloader 正常加载同一程序集（插件数 20、面板可开、无 IL2CPP 异常）。失败即 BLOCKED 上报（控制器改走方案 B）。
2. 迁逻辑 → 删 MCCleaner → 壳实现（含墓碑分支）。
3. 验证：pending 五类 op / marker 翻译（Ruling 9）/ 顺序覆盖 20/20 / 自卸载两阶段 / ModCenter 游戏内自更新（清理逻辑随新 dll 生效，证据行带程序集版本）/ D6 面板打开即查 / 夹具 menu+toggle。
4. 文档与发版链同步；commit。
