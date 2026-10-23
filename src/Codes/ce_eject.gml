// ============================================================
// Don't remove my junk! v1.8.3 —— 进房时按挂起表抛出已刷新容器的玩家物品
// 注入点：o_roomEntityLoader / Other 11 末尾（全部实体加载完成后）
// 作者：ErenSanchez · TargetVersion 0.9.4.25-vm
// 版本史与全量核对结论见：说明.md、Cases and Experiences\Case-Container Eject.md
// 挂起表结构见 ce_record.gml 头。
//
// 流程：遍历 cePending[locationTag] 条目 →
//   归属过滤（roomTag==当前房间）→
//   主路径：按 "x,y" 找容器，is_execute==false（已刷新）才抛；
//   坐标失效（notfound/badkey）时兜底：抛给房内"已刷新的可盗窃容器"；
//   双失效不抛。只有真交出去（_ce_good>0）才删条目，否则保留重试。
// 关键判据：
//   · is_execute==true 时绝不抛也不兜底——物品还在箱里，抛了就是复制。
//   · 类型防御判据 "!is_string && !is_array && ds_exists"：存档 JSON 往返
//     可能把未标记槽写成标量字符串，ds_exists 收到 string 会崩；
//     ds 句柄本身是 real，不能用 is_real 排除。
// GML 硬约束：
//   · 提前退出用 exit（UTM 解析器不接受 return 紧跟 }）。
//   · 所有变量在 while 前显式初始化：循环体内 var + with 内赋值会被编译成
//     实例变量（"Variable not set before reading it"）。
//   · 键解析只用 string_pos/string_copy/real（string_split 返回类型不可靠、
//     string_find 本作运行时报错；real 对非法输入返回 0→找不到容器→走兜底）。
//   · roomTag 是房间资产名（r_global / r_dungeon_N / 房间名），不含 | 与 ,，
//     键 "roomTag|x,y" 可安全用 string_pos 定位；无 | 时兼容旧格式（整键即坐标）。
// 抛出用 scr_loot_drop_saved(开关, 列表)：
//   · 必须显式传 (false, _ce_valid)——列表参数缺省兜底成调用者 loot_list，
//     刚刷新的容器它是空的，表现为"执行了但没物品"。
//   · 必须包在 with (o_player) 并把 x/y 临时改到容器坐标：该函数走
//     instance_create_depth(x,y,0,obj)，实例建在调用者图层；从实体图层调用
//     会得到看不见捡不到的掉落物且全程不报错。玩家图层=地面掉落物图层。
//   · 武器分支会把 data["Duration"] 乘 0.15（砸碎散落惩罚），救援不继承：
//     抛出前对武器 item（list[0] 字符串且 asset_get_index 解析不出对象）
//     预放 x/0.15，乘回后精确还原（Duration 是 real；瞬态值无观察者）。
// 食物补扣与换名（对齐 scr_consum_food_change / o_inv_food_parent_Alarm_8）：
//   · Fresh 单位=游戏小时，扣 scr_timeGetPassed(Timestamp, 2) 的整小时数。
//   · 扣到 0 必须换 _rot 物品名（_raw/_fried/_cooked 先剥再拼；只归零会得到
//     "永远不变腐"的食物——can_change 门控在抛出实例上恒 false）。
//   · 帧号规则同链复刻：默认 1；原贴图帧数>2 沿用旧帧；剥 _raw 或存在
//     _fried 变体则归 0。写回 list[4]。
// ============================================================

if (!variable_global_exists("saveDataMap") || !ds_exists(global.saveDataMap, ds_type_map))
    exit

var _ce_lk = scr_locationGenerateTag()
var _ce_rt = scr_locationRoomGenerateTag()

var _ce_pending = ds_map_find_value_ext(global.saveDataMap, "cePending", -1)
if (!is_string(_ce_pending) && !is_array(_ce_pending) && !ds_exists(_ce_pending, ds_type_map))
    exit

var _ce_loc = ds_map_find_value_ext(_ce_pending, _ce_lk, -1)
if (!is_string(_ce_loc) && !is_array(_ce_loc) && !ds_exists(_ce_loc, ds_type_map))
    exit

var _ce_done = ds_list_create()

// ---- 调试日志（与记录侧同一套规则：行数=0 写表头、>1000 轮转）。
// 本侧句柄跨整个 while 保持打开，轮转判定必须在开句柄前做完。----
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
}

// ---- 全部声明提升到循环外并显式初始化（见文件头 GML 硬约束）----
var _ce_key = ds_map_find_first(_ce_loc)
var _ce_entry = noone
var _ce_items = noone
var _ce_ert = ""
var _ce_cnt = 0
var _ce_act = ""
var _ce_state = 0
var _ce_hit = noone
var _ce_fb = noone
var _ce_comma = 0
var _ce_tx = 0
var _ce_ty = 0
var _ce_bar = 0
var _ce_coord = ""
var _ce_dur = -4
var _ce_new_i = 0
var _ce_orig_obj = -1
var _ce_spr = -1
var _ce_ll = 0
var _ce_valid = noone
var _ce_it = noone
var _ce_dm = noone
var _ce_id = noone
var _ce_k = 0
var _ce_good = 0
var _ce_px = 0
var _ce_py = 0
var _ce_ids = ""
var _ce_fresh = ""
var _ce_fr = -4
var _ce_ts = -4
var _ce_fv = -4
var _ce_passed = 0
var _ce_base = ""
var _ce_rot = -1
var _ce_rotted = 0
var _ce_now = 0
var _ce_why = -1
var _ce_t0 = "?"
var _ce_t1 = "-"
var _ce_t2 = "-"
var _ce_len = -1
var _ce_why_s = ""

while (!is_undefined(_ce_key))
{
    _ce_entry = ds_map_find_value(_ce_loc, _ce_key)
    _ce_items = -1
    _ce_ert = ""
    _ce_cnt = 0
    _ce_ids = ""
    _ce_fresh = ""
    _ce_why_s = ""
    _ce_rotted = 0
    _ce_now = scr_timeGetTimestamp()

    // 条目 = { roomTag, items } 的 map；类型防御挡住旧结构/坏数据
    if (!is_string(_ce_entry) && !is_array(_ce_entry) && ds_exists(_ce_entry, ds_type_map))
    {
        _ce_items = ds_map_find_value_ext(_ce_entry, "items", -1)
        _ce_ert = ds_map_find_value_ext(_ce_entry, "roomTag", "")
        if (!is_string(_ce_items) && !is_array(_ce_items) && ds_exists(_ce_items, ds_type_list))
            _ce_cnt = ds_list_size(_ce_items)
    }

    _ce_act = "skip:notstring"
    _ce_state = 0
    _ce_hit = noone
    _ce_tx = 0
    _ce_ty = 0

    // 归属过滤：只处理当前房间的条目（同地点跨房间坐标会重复）。
    // continue 前必须推进 _ce_key（循环末尾的推进会被 continue 跳过）。
    if (_ce_ert != _ce_rt)
    {
        _ce_key = ds_map_find_next(_ce_loc, _ce_key)
        continue
    }

    if (is_string(_ce_key) && _ce_cnt > 0
        && !is_string(_ce_items) && !is_array(_ce_items) && ds_exists(_ce_items, ds_type_list))
    {
        // 键 "roomTag|x,y"；无 | 时兼容旧格式（整键即坐标）
        _ce_bar = string_pos("|", _ce_key)
        _ce_coord = _ce_key
        if (_ce_bar > 0)
            _ce_coord = string_copy(_ce_key, _ce_bar + 1, string_length(_ce_key) - _ce_bar)
        _ce_comma = string_pos(",", _ce_coord)
        if (_ce_comma > 1 && _ce_comma < string_length(_ce_coord))
        {
            _ce_tx = real(string_copy(_ce_coord, 1, _ce_comma - 1))
            _ce_ty = real(string_copy(_ce_coord, _ce_comma + 1, string_length(_ce_coord) - _ce_comma))

            with (o_stuff)
            {
                if (!persistent && instance_is(id, c_container) && x == _ce_tx && y == _ce_ty)
                    _ce_hit = id
            }

            if (!instance_exists(_ce_hit))
                _ce_act = "skip:notfound"
            else if (!variable_instance_exists(_ce_hit, "is_execute"))
                _ce_act = "skip:noexecflag"
            else if (_ce_hit.is_execute)
                _ce_act = "skip:is_execute"
            else
                _ce_state = 1
        }
        else
            _ce_act = "skip:badkey"
    }

    // ---- 兜底：坐标失效（notfound/badkey）时抛给房内"已刷新的可盗窃容器"。
    // 边界（已知）：无法验证目标容器的状态变更，房内存在从未开启的
    // 可盗窃容器时可能误配位置——罕见情形的尽力救援。
    // 坐标命中但未刷新（skip:is_execute）不走兜底：物品还在容器里。----
    if (_ce_state == 0 && (_ce_act == "skip:notfound" || _ce_act == "skip:badkey")
        && _ce_cnt > 0)
    {
        with (o_stuff)
        {
            if (!persistent && instance_is(id, c_container)
                && variable_instance_exists(id, "hasOwner") && hasOwner
                && variable_instance_exists(id, "is_execute") && !is_execute)
                _ce_fb = id
        }
        if (instance_exists(_ce_fb))
        {
            _ce_hit = _ce_fb
            _ce_tx = _ce_fb.x
            _ce_ty = _ce_fb.y
            _ce_state = 2
            _ce_act = ""
        }
        _ce_fb = noone
    }

    if (_ce_state > 0)
    {
        // 逐项结构校验：损坏条目直接丢给 scr_loot_drop_saved 会抛
        // "Data structure with index does not exist"，先筛一遍。
        // why 诊断格式：why<序号>=<失败项>|<槽0类型>|<长度>|<槽1类型>|<槽0值类型>/
        //   失败项 0=槽0非ds_list 1=长度<2 2=槽1非ds_map 3=槽0值类型非法
        //   类型   str/arr/list/map/num/?
        _ce_valid = ds_list_create()
        for (_ce_k = 0; _ce_k < _ce_cnt; _ce_k++)
        {
            _ce_it = ds_list_find_value(_ce_items, _ce_k)

            _ce_why = -1
            _ce_t0 = "?"
            _ce_t1 = "-"
            _ce_t2 = "-"
            _ce_len = -1

            if (is_string(_ce_it)) _ce_t0 = "str"
            else if (is_array(_ce_it)) _ce_t0 = "arr"
            else if (!is_array(_ce_it) && ds_exists(_ce_it, ds_type_list)) _ce_t0 = "list"
            else if (!is_array(_ce_it) && ds_exists(_ce_it, ds_type_map)) _ce_t0 = "map"
            else if (is_real(_ce_it)) _ce_t0 = "num"

            if (_ce_t0 == "str" || _ce_t0 == "arr" || _ce_t0 == "num" || _ce_t0 == "?")
                _ce_why = 0
            else
                _ce_len = ds_list_size(_ce_it)

            if (_ce_why < 0 && _ce_len < 2)
                _ce_why = 1

            if (_ce_why < 0)
            {
                _ce_dm = ds_list_find_value(_ce_it, 1)
                if (is_string(_ce_dm)) _ce_t1 = "str"
                else if (is_array(_ce_dm)) _ce_t1 = "arr"
                else if (!is_array(_ce_dm) && ds_exists(_ce_dm, ds_type_map)) _ce_t1 = "map"
                else if (!is_array(_ce_dm) && ds_exists(_ce_dm, ds_type_list)) _ce_t1 = "list"
                else if (is_real(_ce_dm)) _ce_t1 = "num"
                else _ce_t1 = "?"

                if (_ce_t1 != "map")
                    _ce_why = 2
            }

            if (_ce_why < 0)
            {
                _ce_id = ds_list_find_value(_ce_it, 0)
                if (is_string(_ce_id)) _ce_t2 = "str"
                else if (is_real(_ce_id)) _ce_t2 = "num"
                else _ce_t2 = "?"
                if (_ce_t2 == "?")
                    _ce_why = 3
            }

            if (_ce_why >= 0)
            {
                if (string_length(_ce_why_s) < 100)
                    _ce_why_s += string(_ce_k) + "=" + string(_ce_why) + "|" + _ce_t0 + "|"
                        + string(_ce_len) + "|" + _ce_t1 + "|" + _ce_t2 + "/"
                continue
            }

            _ce_dm = ds_list_find_value(_ce_it, 1)
            _ce_id = ds_list_find_value(_ce_it, 0)

            // 食物保质期补扣（挂起表无活实例，没人跑 alarm[8]）：
            // 按绝对游戏时间一次性扣，写法照抄 scr_item_crime_pass（单位换小时）。
            _ce_fr = ds_map_find_value_ext(_ce_dm, "Fresh", -4)
            _ce_ts = ds_map_find_value_ext(_ce_dm, "Timestamp", -4)
            if (is_real(_ce_fr) && is_real(_ce_ts) && _ce_ts > 0)
            {
                _ce_passed = scr_timeGetPassed(_ce_ts, 2)
                if (_ce_passed > 0)
                {
                    _ce_fv = max(0, _ce_fr - _ce_passed)
                    ds_map_replace(_ce_dm, "Fresh", _ce_fv)
                    ds_map_replace(_ce_dm, "Timestamp", _ce_now)

                    // 扣到 0 必须换 _rot 名 + 按帧号规则调帧（见文件头）。
                    if (_ce_fv <= 0)
                    {
                        _ce_base = ""
                        if (is_string(_ce_id))
                            _ce_base = string(_ce_id)
                        else {
                            // list[0] 经存档往返可能变成对象索引，用 idName 还原
                            // （与 scr_loadContainerContent 同一套拼法）
                            var _ce_idn = ds_map_find_value_ext(_ce_dm, "idName", "")
                            if (is_string(_ce_idn) && string_length(_ce_idn) > 0)
                                _ce_base = "o_inv_" + string_replace(string(_ce_idn), " notId", "")
                        }
                        _ce_rot = -1
                        if (string_length(_ce_base) > 0)
                        {
                            // 帧号在剥后缀前先按原物品计算
                            _ce_new_i = 1                                  // ① 默认第 1 帧
                            _ce_orig_obj = -1
                            if (is_real(_ce_id))
                                _ce_orig_obj = _ce_id
                            else
                                _ce_orig_obj = asset_get_index(_ce_id)
                            if (_ce_orig_obj > -1)
                            {
                                _ce_spr = object_get_sprite(_ce_orig_obj)
                                if (_ce_spr > -1 && sprite_get_number(_ce_spr) > 2)
                                    _ce_new_i = ds_list_find_value(_ce_it, 4)   // ② 原贴图帧数>2 沿用旧帧号
                            }
                            // 命名规则与帧号同链（对齐 scr_consum_food_change 原文结构）
                            if (string_ends_with(_ce_base, "_raw"))
                            {
                                _ce_base = string_replace(_ce_base, "_raw", "")
                                _ce_new_i = 0                              // ③ 生食帧布局不同，强制归 0
                            }
                            else if (string_ends_with(_ce_base, "_fried"))
                            {
                                _ce_base = string_replace(_ce_base, "_fried", "")
                            }
                            else if (string_ends_with(_ce_base, "_cooked"))
                            {
                                _ce_base = string_replace(_ce_base, "_cooked", "")
                            }
                            else if (asset_get_index(_ce_base + "_fried") > -1)
                            {
                                _ce_new_i = 0                              // ④ 存在 _fried 变体，强制归 0
                            }
                            _ce_rot = asset_get_index(_ce_base + "_rot")
                        }
                        if (_ce_rot != -1)
                        {
                            ds_list_set(_ce_it, 0, _ce_rot)
                            ds_list_set(_ce_it, 4, _ce_new_i)
                            _ce_rotted++
                            if (string_length(_ce_ids) < 120)
                                _ce_ids += "→" + string(_ce_rot) + "/"
                        }
                    }
                }
            }

            // 武器耐久补偿：判定与 scr_loot_drop_saved 武器分支一致
            // （list[0] 字符串且解析不出对象）。预放 x/0.15，游戏乘回后还原。
            if (is_string(_ce_id) && asset_get_index(_ce_id) == -1)
            {
                _ce_dur = ds_map_find_value_ext(_ce_dm, "Duration", -4)
                if (is_real(_ce_dur) && _ce_dur > 0)
                    ds_map_replace(_ce_dm, "Duration", _ce_dur / 0.15)
            }

            ds_list_add(_ce_valid, _ce_it)
            if (string_length(_ce_ids) < 120)
                _ce_ids += string(_ce_id) + "/"
            if (string_length(_ce_fresh) < 120)
                _ce_fresh += string(ds_map_find_value_ext(_ce_dm, "Fresh", -4)) + ":"
                    + string(ds_map_find_value_ext(_ce_dm, "Timestamp", -4)) + "/"
        }

        // 记录容器 loot_list 大小作对照：误用兜底列表时这里会是 0 且物品不掉。
        _ce_ll = 0
        _ce_good = ds_list_size(_ce_valid)
        if (_ce_good > 0)
        {
            with (_ce_hit)
            {
                if (ds_exists(loot_list, ds_type_list))
                    _ce_ll = ds_list_size(loot_list)
            }

            // 必须在玩家图层发起抛出（见文件头）；x/y 临时改到容器坐标再改回。
            if (instance_exists(o_player))
            {
                with (o_player)
                {
                    _ce_px = x
                    _ce_py = y
                    x = _ce_tx
                    y = _ce_ty
                    scr_loot_drop_saved(false, _ce_valid)
                    x = _ce_px
                    y = _ce_py
                }
            }
            else
            {
                // 极端兜底：房间里没有玩家实例时退回容器上下文
                with (_ce_hit)
                    scr_loot_drop_saved(false, _ce_valid)
            }
        }
        // eject: = 主路径（坐标命中）；ejectfb: = roomTag 兜底路径
        _ce_act = (_ce_state == 1 ? "eject:" : "ejectfb:") + "ll" + string(_ce_ll) + ":ok" + string(_ce_good) + "/" + string(_ce_cnt)
            + ":rot" + string(_ce_rotted)
        // 只有真交出去了才删记录；一件都没交成功就保留条目等下次重试
        if (_ce_good > 0)
            ds_list_add(_ce_done, _ce_key)
        // _ce_valid 是未标记的引用列表，destroy 不级联，安全
        ds_list_destroy(_ce_valid)
    }

    if (_ce_f != -1)
    {
        file_text_write_string(_ce_f, string(current_time) + ",eject," + _ce_lk + "," + _ce_rt + "," + _ce_key + ","
            + string(_ce_cnt) + "," + _ce_act + "," + _ce_ids + "," + string(scr_timeGetTimestamp()) + "," + _ce_fresh + "," + _ce_why_s + "\n")
    }

    _ce_key = ds_map_find_next(_ce_loc, _ce_key)
}

if (_ce_f != -1)
    file_text_close(_ce_f)

for (var _ce_i = 0; _ce_i < ds_list_size(_ce_done); _ce_i++)
    ds_map_delete(_ce_loc, ds_list_find_value(_ce_done, _ce_i))
ds_list_destroy(_ce_done)

if (ds_map_size(_ce_loc) == 0)
    ds_map_delete(_ce_pending, _ce_lk)
