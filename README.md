# Don't remove my junk!

[![Stoneshard](https://img.shields.io/badge/Stoneshard-0.9.4.25--vm-6f42c1)](https://store.steampowered.com/app/625960/Stoneshard/)
[![ModShardLauncher-Enhanced](https://img.shields.io/badge/loader-MSL--Enhanced-blue)](https://github.com/ModShardTeam/ModShardLauncher)

**Don't remove my junk!** keeps the items you store in stealable containers from vanishing when Stoneshard refreshes those containers every in-game week.

当紫色晶石按周刷新容器时，你存放在可盗窃容器里的自有物品会随之消失。这个模组把它们记下来，并在你下次进入该区域、确认容器确实已刷新后，将物品抛回容器脚下。

---

## Features / 功能

- **Records on close** — when you close a stealable container, the items you placed inside are snapshotted into a pending table stored inside the save data.
- **Ejects after refresh** — on the next visit, if a container has been refreshed (`is_execute == false`), the recorded items are dropped beside it.
- **Persists across saves** — the pending table lives under `global.saveDataMap`, so it is serialized and restored with the save. No lifecycle hooks required.
- **No gameplay rewrites** — no `instance_destroy()`, no injected player-facing text, no change to the game's own container logic.
- **Food spoilage carried over** — ejected food has its `Fresh` value aged by elapsed in-game hours, and turns into its `_rot` variant when expired.
- **Weapon durability preserved** — the game's 15% "smashed container" penalty is compensated before ejection.

> **迁移说明**：v1.8.3 只是更名（原名 *Container Eject*），内部存档键 `cePending` / `ceScratch` 未变，旧存档继续有效。

## Requirements / 环境要求

- **Stoneshard** `0.9.4.25-vm` (Steam → Properties → Betas → `modbranch`)
- **ModShardLauncher-Enhanced (MSL-E)**
- .NET 6 SDK — only needed to build from source / 仅自行编译时需要

## Installation / 安装

1. Download `DontRemoveMyJunk-v1.8.3.zip` from the [Releases](../../releases) page.
2. Extract `DontRemoveMyJunk.sml` into MSL-E's `Mods` folder.
3. Launch MSL-E, load the **vanilla** `data.win` of the `modbranch` build.
4. Enable **Don't remove my junk!**, then click Save and output a patched `.win`.
5. Start Stoneshard and select the patched `.win`.

1. 从 [Releases](../../releases) 下载 `DontRemoveMyJunk-v1.8.3.zip`。
2. 将压缩包内的 `DontRemoveMyJunk.sml` 解压到 MSL-E 的 `Mods` 目录。
3. 打开 MSL-E，加载 `modbranch` 分支的**原版** `data.win`。
4. 勾选 **Don't remove my junk!**，点击保存并输出打过补丁的 `.win`。
5. 启动游戏，选择该 `.win` 文件。

## How it works / 实现原理

Two hooks, both text-matched against vanilla code:

| Hook | Target | Purpose |
|---|---|---|
| Record | `o_container_parent` / Other 23, after `is_close = true` | Snapshot the final container UI state before it is written back to the world container |
| Eject | `o_roomEntityLoader` / Other 11, at the end | After all room entities (including containers) are loaded, eject pending items for refreshed containers |

The pending table is keyed by the game's own stable identifiers:

```gml
global.saveDataMap["cePending"]["<locationTag>"]["<roomTag>|<x>,<y>"] = {
    "roomTag": "<roomTag>",
    "items": [ ... ]
}
```

- `locationTag` — `scr_locationGenerateTag()` (world coordinates), stable across saves and map rebuilds.
- `x,y` — normalized container cell; the primary locator.
- `roomTag` — secondary locator / fallback filter, because each room has its own local coordinate system.

Ejection uses `scr_loot_drop_saved(false, items)` wrapped in `with (o_player)`, so loot is created on the player's layer (the ground-loot layer). Without this, items would be created on the entity layer and become invisible and unpickable.

Full design notes, failure modes and verification history: [docs/技术说明.md](docs/技术说明.md).

## Compatibility & known limits / 兼容性与已知限制

- Built and verified against `0.9.4.25-vm` only. Other versions may move the anchors.
- Only `c_container`-family containers are handled; consumer containers (`o_inv_consum`) are out of scope.
- Items marked `HasOwner == 1/2` (original loot / lost property) are intentionally not recorded.
- Scenario handling depends on `o_roomEntityLoader` running before the player can open a container; this window has been verified absent in testing.
- Existing pending records are kept if ejection cannot be completed, and retried on the next visit.

## Build from source / 从源码编译

```powershell
# Optional: point to your MSL-E installation if it is not in the default Steam path
$env:MSLE_DIR = "D:\steam\steamapps\common\Stoneshard\tools\ModShardLauncher-Enhanced"

dotnet build src/DontRemoveMyJunk.csproj -c Release
```

Packing into an `.sml` requires MSL-E (or a compatible packer); the `.sml` itself is not stored in this repository.

## Repository layout / 仓库结构

```
.
├── src/
│   ├── DontRemoveMyJunk.cs          # Mod entry point (record + eject hooks)
│   ├── DontRemoveMyJunk.csproj      # .NET 6 class library project
│   ├── Codes/
│   │   ├── ce_record.gml            # Container-close snapshot hook
│   │   └── ce_eject.gml             # Room-load ejection hook
│   └── icon.png                     # Mod icon (lowercase file name is required by MSL)
├── docs/
│   └── 技术说明.md                   # Full design notes, pitfalls and verification log
├── .gitignore
└── README.md
```

## Version history / 版本记录

| Version | Date | Changes |
|---|---|---|
| v1.8.3 | 2026-10-23 | Renamed from *Container Eject* to *Don't remove my junk!*; no functional change; save keys unchanged |
| v1.8.2 | 2026-10 | Reproduced the game's frame-index rules when renaming spoiled food to its `_rot` variant |
| v1.8.1 | 2026-10 | Weapon durability restoration, per-room key collision fix, snapshot ownership isolation, bad-item filtering |
| v1.8.0 | 2026-10 | Pending table keyed by `locationTag` instead of unstable room index |
| v1.7.1 | 2026-10 | Debug log rotation at 1000 lines |
| v1.6.x | 2026-10 | Food spoilage aging, `_rot` renaming, baseline `Timestamp` backfill |
| v1.4.0 | 2026-10 | `ds_list_mark_as_list` for save serialization, type guards |
| v1.3.0 | 2026-10 | Eject on the player layer via `with (o_player)` |

## Author / 作者

**ErenSanchez** — original mod, design and implementation.

This project is not affiliated with Ink Stains Games. Stoneshard is a trademark of its respective owner.
