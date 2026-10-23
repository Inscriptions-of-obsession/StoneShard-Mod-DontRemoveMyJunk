// Don't remove my junk! v1.8.3
// 原创模组，作者 ErenSanchez。适配 Stoneshard 0.9.4.25-vm + MSL-Enhanced。
// v1.8.3：模组更名为 Don't remove my junk!（原 Container Eject），功能无改动；
//         内部存档键（cePending / ceScratch）保持不变，旧存档继续有效。
//
// 作用：紫色晶石每七天按 presetTag 世代更替（剧情推进/地图重建也会刷新），
//       使可盗窃容器存档失效，玩家存放在其中的自有物品随之消失。
//       本模组在关箱时记录这些物品（挂起表 cePending，挂在 global.saveDataMap
//       下随存档序列化），玩家重进区域且确认容器已刷新（is_execute==false）时
//       按记录把它们抛回容器脚下。
//       不改动游戏任何原生逻辑，不注入任何游戏内文本，不做 instance_destroy。
//
// 完整版本史与全量反编译核对结论：
//   Mod Works\Don't remove my junk!\说明.md
//   Cases and Experiences\Case-Container Eject.md
// 关键实现约束（详见 GML 文件头）：
//   · 键：cePending[locationTag]["roomTag|x,y"]——GM 房间编号跨读档/重建会漂移，
//     不可作键；同地点不同房间各自本地坐标系，纯坐标会跨房间覆盖。
//   · 存档序列化必须 ds_list_mark_as_list；提前退出用 exit（UTM 解析器限制）。
//   · 抛出必须 with (o_player) 改 x/y（图层规则）；scr_loot_drop_saved 必须
//     显式传 (false, 列表)；武器耐久预放 x/0.15 抵消其惩罚折损。

using ModShardLauncher;
using ModShardLauncher.Mods;
using UndertaleModLib.Models;

namespace DontRemoveMyJunk;

public class DontRemoveMyJunk : Mod
{
    public override string Author => "ErenSanchez";

    public override string Name => "Don't remove my junk!";

    // 仅启动器模组列表显示，不进入游戏界面。
    public override string Description =>
        "Items you store in containers are ejected beside the container when you next visit the area after a weekly container refresh.";

    public override string Version => "1.8.3";

    public override string TargetVersion => "0.9.4.25-vm";

    public override void PatchMod()
    {
        // 记录钩：Other 23 是容器界面关闭的提交点，插在 is_close = true 之后——
        // 此时箱内物品已定型但 Alarm_0 尚未写回世界容器，可做无副作用快照。
        // 锚点注意：o_container_parent_Alarm_0 与 gml_GlobalScript_scr_save_item
        // 内含 self.xxx() 方法调用，UTM 解析器无法重编译，不可作注入点；
        // Other_23 / roomEntityLoader_Other_11 已实测可编译。
        Msl.LoadGML("gml_Object_o_container_parent_Other_23")
            .MatchFrom("is_close = true")
            .InsertBelow(ModFiles.GetCode("ce_record.gml"))
            .Save();

        // 抛出钩：Other 11 是实体加载总调度，循环完成全部类型（含容器）后才到
        // 末尾——此时容器实例齐备，且仍早于玩家可操作。
        Msl.LoadGML("gml_Object_o_roomEntityLoader_Other_11")
            .MatchFrom("__show_debug_message")
            .InsertBelow(ModFiles.GetCode("ce_eject.gml"))
            .Save();
    }
}
