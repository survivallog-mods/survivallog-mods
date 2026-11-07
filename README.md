# 生存日志 MOD 套件（Survival Log Mods）

《生存日志》(Survival Log, Steam AppID 4164790) 的 BepInEx 6 (IL2CPP) 插件套件——10 个独立 mod，单 DLL 部署、不改存档、不改游戏文件，卸载即还原原版。

## MOD 一览（各仓独立发版）

| MOD | 功能 | 仓库 |
|---|---|---|
| 冰箱保鲜 FridgeChill | 保鲜 5 倍 → 10 倍 | [FridgeChill](https://github.com/survivallog-mods/FridgeChill) |
| 动作提速 QuickAction | 77 项动作逐项可调，默认 0.5 秒 | [QuickAction](https://github.com/survivallog-mods/QuickAction) |
| 更好的储物系统 CabinetEverywhere（原储藏柜直达） | 储物柜进工作台/交易/烹饪等界面页签 + 高度修改（宽恒 12）+ 背包负重调整（kg）/柜子负重解放（2026-11-07 起并入原背包扩容/柜子容量/柜子负重解放三 mod，三仓退役） | [CabinetEverywhere](https://github.com/survivallog-mods/CabinetEverywhere) |
| 解锁中心 UnlockHub | 各类官方限制逐项放开：角色专属（藤蔓/花种子/规划/花瓶/防御配方）+ 交易解锁 | [UnlockHub](https://github.com/survivallog-mods/UnlockHub) |
| 机器人提速 RobotSpeed | 动作对齐手速，移速/充电/续航翻倍 | [RobotSpeed](https://github.com/survivallog-mods/RobotSpeed) |
| MOD 管理中心 ModCenter | 游戏内面板集中开关/调参全套件 mod | [ModCenter](https://github.com/survivallog-mods/ModCenter) |
| 无尽守卫 EndlessGuard（囤鼠桃园） | 无尽模式永不沦陷 + 11 条后期拾遗规划 | [EndlessGuard](https://github.com/survivallog-mods/EndlessGuard) |
| 自选规划 PlanPick | 全部 465+ 项规划可搜可买 | [PlanPick](https://github.com/survivallog-mods/PlanPick) |
| 灾前加速 PreDisasterSpeed | 官方五键倍速条搬到灾前 | [PreDisasterSpeed](https://github.com/survivallog-mods/PreDisasterSpeed) |
| 存档管理 SaveMgr | 存档点与官方存档同列同名，自动/立即存档 + 一键回档（原档不动） | [SaveMgr](https://github.com/survivallog-mods/SaveMgr) |

每个仓库的 Release 页提供该 mod 最新版安装包（`SurvivalLog.<Mod>_v<版本>.zip`），并附带 `update.json` 版本契约（游戏内「MOD 管理中心」支持一键在线更新）。

> 源码仅供阅读学习；自行编译需本机安装《生存日志》并按各仓 csproj 中的 HintPath 配置游戏路径。

## 安装

- **新玩家完整安装**（含 BepInEx 基座，推荐）：使用作者的百度网盘安装器（链接见作者发布渠道）。
- **已装基座的玩家**：到对应 mod 仓库的 Release 页下载 zip，解压到游戏根目录（`Steam\steamapps\common\Survival Log`）。

## 反馈与支持

- 建议/bug：各仓库 Issues，或抖音联系作者（Night，166660371）。
- 免费分享，仅供个人使用；禁止二次分发（各仓 LICENSE）。
