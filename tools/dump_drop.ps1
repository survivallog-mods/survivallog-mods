$ErrorActionPreference = 'Stop'
Start-Sleep 1
Add-Type -Path 'E:\Game\Mod\survivallog-mods\suite\tools\Cecil\Mono.Cecil.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly('E:\SteamLibrary\steamapps\common\Survival Log\BepInEx\interop\HotUpdate.dll')
$t = $asm.MainModule.GetType('GameCore.HotUpdate.DropItemSaveData')
if ($t) {
    foreach ($m in $t.Methods) {
        if ($m.Name -match '^get_') { "$($m.Name) -> $($m.ReturnType.Name)" }
    }
} else { 'no type' }
