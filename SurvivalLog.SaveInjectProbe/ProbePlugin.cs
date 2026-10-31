using System;
using System.IO;
using System.Linq;
using BepInEx;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using Il2CppInterop.Runtime.Injection;
using UnityEngine;
using Object = UnityEngine.Object;

namespace SurvivalLog.SaveInjectProbe;

/// <summary>一次性取证探针（硬规则 5：永不进发布名单/安装器）。主菜单按 F11：
/// 最新 snap → 复制成 GenerateNewSaveFileName 新档 → AddHistoryEntry 注册 → 全步 trace。
/// 验证目标：SaveMgr DESIGN §6-③ snap 独立可读 + 注入链路。结论回收后本 dll 即删。</summary>
[BepInPlugin("com.local.survivallog.saveinjectprobe", "SaveInjectProbe", "0.0.1")]
public sealed class ProbePlugin : BasePlugin
{
    internal static ManualLogSource Log;

    public override void Load()
    {
        Log = base.Log;
        if (!ClassInjector.IsTypeRegisteredInIl2Cpp<ProbeTicker>())
            ClassInjector.RegisterTypeInIl2Cpp<ProbeTicker>();
        var go = new GameObject("SaveInjectProbe.Ticker");
        Object.DontDestroyOnLoad(go);
        go.AddComponent<ProbeTicker>();
        Trace("loaded——主菜单按 F11 注入最新 snap 复制档；结论看本 trace");
        Log.LogInfo("[SaveInjectProbe] loaded（F11=注入，取证探针）");
    }

    internal static void Trace(string line)
    {
        try { File.AppendAllText(Path.Combine(Paths.BepInExRootPath, "SaveInjectProbe_trace.txt"), $"[{DateTime.Now:HH:mm:ss}] {line}\n"); }
        catch { }
    }
}

/// <summary>0.5s 轮询 F11（主线程，interop 调用安全窗口）。Update public + 双构造器（RoleUnlock 实证模式）。</summary>
internal sealed class ProbeTicker : MonoBehaviour
{
    private float _acc;
    public ProbeTicker(IntPtr p) : base(p) { }
    public ProbeTicker() { }
    public void Update()
    {
        try
        {
            _acc += Time.unscaledDeltaTime;
            if (_acc < 0.5f) return;
            _acc = 0;
            if (Input.GetKeyDown(KeyCode.F11)) RunInject();
            // 文件触发通道（键盘注入对游戏不可靠——2026-10-31 SendInput 实证；走文件系统）
            var cmd = Path.Combine(Paths.BepInExRootPath, "SaveInjectProbe_cmd.txt");
            if (File.Exists(cmd))
            {
                var line = (File.ReadAllText(cmd) ?? "").Trim().ToLowerInvariant();
                try { File.Delete(cmd); } catch { }
                if (line == "inject") RunInject();
                else if (line == "diag") RunDiag();
            }
        }
        catch (Exception e) { ProbePlugin.Trace("ticker: " + e.Message); }
    }

    private static void RunDiag()
    {
        try
        {
            var gsm = GameCore.HotUpdate.BaseSingleton<GameCore.HotUpdate.GameSaveManager>.Instance;
            if (gsm == null) { ProbePlugin.Trace("diag: gsm null"); return; }
            gsm.EnsureHistoryV2Migrated();
            var list = gsm.GetHistoryList();
            ProbePlugin.Trace("diag: count=" + (list?.Count ?? -1));
            var present = GameCore.HotUpdate.GameSaveManager.IsSaveFilePresent("Save_2026_10_31_21_15_55.bytes");
            ProbePlugin.Trace("diag: IsSaveFilePresent(注入档)=" + present);
            if (list == null) return;
            for (var i = 0; i < list.Count; i++)
            {
                var c = list[i];
                if (c == null) continue;
                var fn = c.FileName ?? "";
                if (!fn.Contains("09_30_35") && !fn.Contains("21_15_55") && !fn.Contains("21_11_25")) continue;
                ProbePlugin.Trace($"diag[{i}] file={fn} name={c.Name} day={c.Day} max={c.MaxDay} turn={c.Turn}" +
                    $" gt={c.GameTime} extra={c.ExtraCountDownTime} chap={c.InitChapterId} fin={c.IsFinished} res={c.FinishResult}" +
                    $" meta1={c.HasProgressMeta} meta2={c.HasProgressMetaV2} pureEnd={c.IsPureEndless} storyEnd={c.IsStoryEndless}" +
                    $" casualEnd={c.IsCasualEndless} endStart={c.EndlessStartDay} hasEndMeta={c.HasEndlessMeta}" +
                    $" storyEndOrigin={c.StoryEndlessOriginEnding} origin={c.SaveOrigin} diff={c.HasDifficultyMeta}/{c.DifficultyPresetId}" +
                    $" diffLv={(c.DifficultyLevels == null ? -1 : c.DifficultyLevels.Count)} chal={c.ChallengeTargetId}" +
                    $" legacy={GameCore.HotUpdate.GameKey.IsLegacySave(c.SaveOrigin)} endSnap={c.HasEndingSnapshot} endRule={c.HasEndingRuleMeta}" +
                    $" finDay={c.SnapshotDay}");
            }
        }
        catch (System.Exception e) { ProbePlugin.Trace("diag: " + e.Message); }
    }

    private static void RunInject()
    {
        ProbePlugin.Trace("== 注入开始 ==");
        var gsm = GameCore.HotUpdate.BaseSingleton<GameCore.HotUpdate.GameSaveManager>.Instance;
        if (gsm == null) { ProbePlugin.Trace("FAIL: GameSaveManager.Instance null"); return; }
        ProbePlugin.Trace("gsm ok, IsInBattle=" + gsm.IsInBattle);

        // 历史懒加载守卫（2026-10-31 实机：主菜单直调 GetLastPlayFileName NRE @游戏源:421；
        // 原生 RebuildSaveList 先调幂等的 EnsureHistoryV2Migrated——照抄）
        try { gsm.EnsureHistoryV2Migrated(); } catch (Exception e) { ProbePlugin.Trace("EnsureHistoryV2Migrated: " + e.Message); }

        string last = gsm.GetLastPlayFileName();
        if (string.IsNullOrEmpty(last)) { ProbePlugin.Trace("FAIL: GetLastPlayFileName 空（先进过一次存档再回主菜单）"); return; }
        ProbePlugin.Trace("lastSave=" + last);
        // 游戏约定 fileName 带 .bytes（2026-10-31 实机实证）；本地路径运算用基名
        string baseName = last.EndsWith(".bytes") ? last[..^".bytes".Length] : last;

        string root = GameCore.HotUpdate.TemporaryFile.GetRootPath();
        ProbePlugin.Trace("savesRoot=" + root);
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) { ProbePlugin.Trace("FAIL: saves 目录不存在"); return; }

        // 字节源 = 主档（GameSaveData）。snapN 是 RebirthDaySnapshot 元数据包装（dump.cs:87451：
        // {Version,Day,SaveFileName,Child:SaveChildData}），非完整档——2026-10-31 探针实锤
        // PeekGameSave 读 snap 得 null → metaV2=False。结算时 CaptureDaySnapshotCore 会直接
        // 调无参 SaveGameFileCore 写主档（反汇编 0x28D2367），主档即最新全量状态。
        var mainPath = Path.Combine(root, baseName + ".bytes");
        if (!File.Exists(mainPath)) { ProbePlugin.Trace("FAIL: 主档不存在 base=" + baseName); return; }
        var newest = mainPath;
        var fi = new FileInfo(newest);
        ProbePlugin.Trace($"source=main {Path.GetFileName(newest)} size={fi.Length} mtime={fi.LastWriteTime:HH:mm:ss}");

        string newName = gsm.GenerateNewSaveFileName();
        ProbePlugin.Trace("newName=" + newName);
        string newFile = newName.EndsWith(".bytes") ? newName : newName + ".bytes";
        string dest = Path.Combine(root, newFile);
        if (File.Exists(dest)) { ProbePlugin.Trace("FAIL: 目标已存在（同秒碰撞）：" + dest); return; }
        File.Copy(newest, dest);
        ProbePlugin.Trace("copied → " + dest + " size=" + new FileInfo(dest).Length);

        // Name 必须是可解析的时间戳串（diag 实证：原档 name=2026_09_19_09_30_35；列表行时间列
        // =ParseSaveTimeShort(child.Name)，非时间串 → 行被丢弃不显示）。
        string entryName = newFile;
        if (entryName.StartsWith("Save_")) entryName = entryName["Save_".Length..];
        if (entryName.EndsWith(".bytes")) entryName = entryName[..^".bytes".Length];
        gsm.AddHistoryEntry(newName, entryName);
        ProbePlugin.Trace("AddHistoryEntry(name=" + entryName + ") done");

        var hist = gsm.GetHistoryList();
        if (hist == null || hist.Count == 0) { ProbePlugin.Trace("FAIL: GetHistoryList 空"); return; }
        var tail = hist[hist.Count - 1];
        ProbePlugin.Trace($"historyTail: file={tail.FileName} day={tail.Day} maxDay={tail.MaxDay} player={tail.PlayerSelectId} metaV2={tail.HasProgressMetaV2}");
        ProbePlugin.Trace(tail.FileName == newName
            ? "== 成功：打开「读档案」应见顶部「探针注入」条目；点进游戏即验 snap 可读性 =="
            : "== 异常：尾部条目文件名不匹配 ==");
    }
}
