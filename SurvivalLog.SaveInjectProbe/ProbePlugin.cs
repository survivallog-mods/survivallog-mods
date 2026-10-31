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
            if (!Input.GetKeyDown(KeyCode.F11)) return;
            RunInject();
        }
        catch (Exception e) { ProbePlugin.Trace("ticker: " + e.Message); }
    }

    private static void RunInject()
    {
        ProbePlugin.Trace("== F11 注入开始 ==");
        var gsm = GameCore.HotUpdate.BaseSingleton<GameCore.HotUpdate.GameSaveManager>.Instance;
        if (gsm == null) { ProbePlugin.Trace("FAIL: GameSaveManager.Instance null"); return; }
        ProbePlugin.Trace("gsm ok, IsInBattle=" + gsm.IsInBattle);

        string last = gsm.GetLastPlayFileName();
        if (string.IsNullOrEmpty(last)) { ProbePlugin.Trace("FAIL: GetLastPlayFileName 空（先进过一次存档再回主菜单）"); return; }
        ProbePlugin.Trace("lastSave=" + last);

        string root = GameCore.HotUpdate.TemporaryFile.GetRootPath();
        ProbePlugin.Trace("savesRoot=" + root);
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) { ProbePlugin.Trace("FAIL: saves 目录不存在"); return; }

        var snaps = Directory.GetFiles(root, last + ".snap*.bytes");
        if (snaps.Length == 0) { ProbePlugin.Trace("FAIL: 无 snap 文件（先玩过至少一次结算）"); return; }
        var newest = snaps.OrderByDescending(f => File.GetLastWriteTime(f)).First();
        var fi = new FileInfo(newest);
        ProbePlugin.Trace($"newestSnap={Path.GetFileName(newest)} size={fi.Length} mtime={fi.LastWriteTime:HH:mm:ss}");

        string newName = gsm.GenerateNewSaveFileName();
        ProbePlugin.Trace("newName=" + newName);
        string dest = Path.Combine(root, newName + ".bytes");
        if (File.Exists(dest)) { ProbePlugin.Trace("FAIL: 目标已存在（同秒碰撞）：" + dest); return; }
        File.Copy(newest, dest);
        ProbePlugin.Trace("copied → " + dest + " size=" + new FileInfo(dest).Length);

        gsm.AddHistoryEntry(newName, "探针注入");
        ProbePlugin.Trace("AddHistoryEntry done");

        var hist = gsm.GetHistoryList();
        if (hist == null || hist.Count == 0) { ProbePlugin.Trace("FAIL: GetHistoryList 空"); return; }
        var tail = hist[hist.Count - 1];
        ProbePlugin.Trace($"historyTail: file={tail.FileName} day={tail.Day} maxDay={tail.MaxDay} player={tail.PlayerSelectId} metaV2={tail.HasProgressMetaV2}");
        ProbePlugin.Trace(tail.FileName == newName
            ? "== 成功：打开「读档案」应见顶部「探针注入」条目；点进游戏即验 snap 可读性 =="
            : "== 异常：尾部条目文件名不匹配 ==");
    }
}
