// ============================================================
// Don't remove my junk! v1.8.3 —— 关箱时记录/更新挂起表
// 注入点：o_container_parent / Other 23，紧跟 "is_close = true" 之后
// 作者：ErenSanchez · TargetVersion 0.9.4.25-vm
// 版本史与全量核对结论见：说明.md、Cases and Experiences\Case-Container Eject.md
//
// 挂起表结构（挂在 global.saveDataMap 下随存档序列化；读档时 saveDataMap
// 被整体替换，故每次现查、绝不缓存到独立全局变量）：
//   cePending[locationTag]["roomTag|x,y"] = { roomTag, items }
//   · 桶键 locationTag = scr_locationGenerateTag()（世界坐标格式化）。
//     游戏自身持久化（门锁/犯罪/preset flags）同款键，跨读档与剧情重建
//     稳定；GM 房间编号（room）会漂移，不可作键。
//   · 条目键并入 roomTag：同地点不同房间各自本地坐标系，纯 "x,y" 会跨房间覆盖。
//
// 快照时机：Other 23 时 is_close 已置真、界面即将销毁，但 Alarm_0（写回世界
// 容器 + instance_destroy）尚未执行 → o_inv_slot 上仍是玩家离开前的最终状态，
// 世界容器 loot_list 还是旧的，快照必须从界面取。
// scr_save_item(表, id, false, false) = 无副作用读取（不回背包、不销毁物品）。
//
// 存档序列化硬规则：json_encode 只输出被标记过的嵌套 ds；ds_list_add 后必须
// ds_list_mark_as_list（ds_map_add_map/add_list 自带标记；本作无
// ds_map_mark_as_map，游戏本体零处使用）。
//
// 提前退出用 exit（UTM 的 GML 解析器不接受 return 紧跟 }）。
// ============================================================

// 只记录有主容器（hasOwner==true，即可盗窃容器）。无主容器的原生战利品
// HasOwner 也是 0，与玩家物品无法区分；有主容器首开会打 HasOwner=1
// （c_container_Other_13）。判据：HasOwner 0/无键=玩家物品→记；
// 1=原生战利品、2=失物→不记。
var _ce_w = parent

if (instance_exists(_ce_w) && instance_is(_ce_w, c_container)
    && variable_instance_exists(_ce_w, "hasOwner") && _ce_w.hasOwner)
{
    if (!variable_global_exists("ceScratch"))
        global.ceScratch = ds_list_create()
    ds_list_clear(global.ceScratch)
    scr_save_item(global.ceScratch, id, false, false)

    var _ce_n = ds_list_size(global.ceScratch)
    var _ce_keep = ds_list_create()
    var _ce_names = ""
    var _ce_fresh = ""
    var _ce_stamped = 0
    for (var _ce_i = 0; _ce_i < _ce_n; _ce_i++)
    {
        var _ce_item = ds_list_find_value(global.ceScratch, _ce_i)
        if (!ds_exists(_ce_item, ds_type_list) || ds_list_size(_ce_item) < 2)
            continue
        var _ce_data = ds_list_find_value(_ce_item, 1)
        // 槽1 非有效 map 的坏 item 跳过：过不了抛出侧结构校验，且下面读 Fresh
        // 会对无效句柄崩（ds_map_find_value 无防护）。
        if (ds_exists(_ce_data, ds_type_map) && ds_map_find_value_ext(_ce_data, "HasOwner", 0) == 0)
        {
            ds_list_add(_ce_keep, _ce_item)
            ds_list_mark_as_list(_ce_keep, ds_list_size(_ce_keep) - 1)
            var _ce_idn = ds_list_find_value(_ce_item, 0)
            if (string_length(_ce_names) < 120)
                _ce_names += string(_ce_idn) + "/"
            // 食物新鲜度/基准戳采样。有 Fresh 无 Timestamp 的食物（箱内新生成、
            // 从没当过地面掉落物）在关箱这一刻补基准戳，否则挂起期间永不腐败。
            // 改的是快照 data map（scr_save_item 的 clone 副本），不动容器 loot_list。
            var _ce_fr = ds_map_find_value_ext(_ce_data, "Fresh", -4)
            var _ce_ts = ds_map_find_value_ext(_ce_data, "Timestamp", -4)
            if (is_real(_ce_fr) && _ce_fr > 0 && (!is_real(_ce_ts) || _ce_ts <= 0))
            {
                _ce_ts = scr_timeGetTimestamp()
                ds_map_replace(_ce_data, "Timestamp", _ce_ts)
                _ce_stamped++
            }
            if (string_length(_ce_fresh) < 120)
                _ce_fresh += string(_ce_fr) + ":" + string(_ce_ts) + "/"
        }
    }

    var _ce_lk = scr_locationGenerateTag()
    var _ce_rt = scr_locationRoomGenerateTag()
    var _ce_key = _ce_rt + "|" + string(_ce_w.x) + "," + string(_ce_w.y)
    var _ce_kept = ds_list_size(_ce_keep)

    // ---- 调试日志（%LOCALAPPDATA%\StoneShard\ce_debug.csv，排查用可整段删）----
    // 行数=0 视为新文件写表头（不能用 file_exists：open_append 先建文件恒真）；
    // 超 1000 行截断轮转。
    var _ce_lines = 0
    var _ce_rd = file_text_open_read("ce_debug.csv")
    if (_ce_rd != -1)
    {
        while (!file_text_eof(_ce_rd))
        {
            file_text_readln(_ce_rd)
            _ce_lines++
        }
        file_text_close(_ce_rd)
    }
    if (_ce_lines > 1000)
    {
        var _ce_trunc = file_text_open_write("ce_debug.csv")
        if (_ce_trunc != -1)
            file_text_close(_ce_trunc)
        _ce_lines = 0
    }

    var _ce_f = file_text_open_append("ce_debug.csv")
    if (_ce_f != -1)
    {
        if (_ce_lines == 0)
            file_text_write_string(_ce_f, "time,stage,loc,roomtag,container,snapshot,kept,ids,now,fresh:stamp,why\n")
        file_text_write_string(_ce_f, string(current_time) + ",record," + _ce_lk + "," + _ce_rt + "," + _ce_key + "," + string(_ce_n) + "," + string(_ce_kept) + "," + _ce_names + "," + string(scr_timeGetTimestamp()) + "," + _ce_fresh + ":st" + string(_ce_stamped) + ",\n")
        file_text_close(_ce_f)
    }
    // ---- 调试结束 ----

    if (!variable_global_exists("saveDataMap") || !ds_exists(global.saveDataMap, ds_type_map))
        exit

    var _ce_pending = ds_map_find_value_ext(global.saveDataMap, "cePending", -1)
    if (!is_string(_ce_pending) && !is_array(_ce_pending) && ds_exists(_ce_pending, ds_type_map))
    {
        // 已有挂起表，直接用
    }
    else
    {
        // 缺失或坏类型残留：先删再建（ds_map_add_map 对已存在键无效）
        ds_map_delete(global.saveDataMap, "cePending")
        _ce_pending = ds_map_create()
        ds_map_add_map(global.saveDataMap, "cePending", _ce_pending)
    }

    var _ce_loc = ds_map_find_value_ext(_ce_pending, _ce_lk, -1)
    if (!is_string(_ce_loc) && !is_array(_ce_loc) && ds_exists(_ce_loc, ds_type_map))
    {
        // 已有本地点桶，直接用
    }
    else
    {
        ds_map_delete(_ce_pending, _ce_lk)
        _ce_loc = ds_map_create()
        ds_map_add_map(_ce_pending, _ce_lk, _ce_loc)
    }

    ds_map_delete(_ce_loc, _ce_key)
    if (_ce_kept > 0)
    {
        // 条目结构 { roomTag, items }：roomTag 仅辅助兜底定位，
        // 抛出决策在坐标 + is_execute（见 ce_eject.gml）。
        var _ce_entry = ds_map_create()
        ds_map_add(_ce_entry, "roomTag", _ce_rt)
        // clone 深拷贝入树，与 ceScratch 持有的原件彻底分离（双重所有权是
        // 悬垂 id 病灶）。本作 ds_list_clone = JSON 往返深拷贝，游戏容器
        // loot_list 持久化同款用法。
        // 注意：_ce_keep 与 ceScratch 共享同一批 item 原件，绝不可 destroy——
        // 下次 ds_list_clear(ceScratch) 若级联销毁即双重销毁。_ce_keep 本体
        // 不销毁，泄漏量小且有界（v1.7.1 及以前同款模式多版本实测安全）。
        ds_map_add_list(_ce_entry, "items", ds_list_clone(_ce_keep))
        ds_map_add_map(_ce_loc, _ce_key, _ce_entry)
    }

    if (ds_map_size(_ce_loc) == 0)
        ds_map_delete(_ce_pending, _ce_lk)
}
