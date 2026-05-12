# Modding Infrastructure — Design Spec

**Status:** planning. No code changes have landed yet. This document captures the agreed direction so future refactors target a known shape rather than drifting.

**Goal at 1.0:** ship a data-mod-capable game — modders add new voxel materials, items, recipes, schematics, weather profiles, texture packs, dialogue timelines, and NPC definitions without recompiling or editing base-game scripts. **No script mods at 1.0** — that lands post-launch once we know what people actually want to extend.

This file documents the foundational refactor required *before* mod support can ship, and the broader infrastructure that will sit on top of it.

---

## The Foundational Refactor: String IDs Are Canonical

### What changes

Today, `VoxelMaterial.material_id` is a designer-authored integer (1–254) packed directly into `VoxelBuffer.CHANNEL_TYPE` on disk. `InventoryManager.ITEM_REGISTRY` uses string keys but those keys are scattered across `.tres` files, hardcoded constants, and save data without a single registry of record.

The refactor flips both systems to **string-id-first**:

- **`VoxelMaterial.id_string`** ("stone", "iron_ore", "copper_isles.obsidian") becomes the canonical identifier. The `material_id` int is **assigned at registry load** by sorting all loaded materials by `id_string` and allocating sequential IDs starting at 1. Designers / modders never type an int ID again.
- **`InventoryManager` item keys** stay strings (no behavioral change at the call-site level), but the registry becomes the single source of truth — items live in their own `.tres` files under `assets/items/` rather than a hardcoded dictionary, and the registry scans the directory the same way `VoxelMaterialRegistry` does today.

### Why string-id-first

1. **Mod ID collisions disappear.** Two mods can each ship `"obsidian"` material entries; we resolve via mod namespacing (`mod_a.obsidian` vs `mod_b.obsidian`) and the int IDs assigned at load are deterministic-per-installation. Two mods cannot accidentally claim the same int slot — there are no int slots to claim.
2. **Save format becomes mod-portable.** Saves write a `string_id ↔ int_id` table once at the top of the chunk DB; voxel bytes still pack 8-bit ints (no perf cost), but on load the table is rebuilt and any new ints are reassigned. A save made with `[mod_a.obsidian, vanilla.stone]` loads correctly even if vanilla added six new materials between sessions, shuffling the int order.
3. **Designers stop tracking "which IDs are free."** Today every new material requires reading the registry's startup print line to find an unused int. After the refactor, designers only pick a unique `id_string`, which the system already validates.
4. **Item registry parity.** Items already use strings; voxel materials catch up. Cross-system code (`yield_item_id`, `tool_target_materials`) becomes consistent — everything is a string, looked up through a registry.

### What stays the same

- **Voxel storage on disk remains 8-bit `CHANNEL_TYPE`.** Performance budget for mesher / generator / save size is unchanged. The change is purely about how `1..254` is *assigned*, not how it's stored.
- **The `VoxelMaterialRegistry` autoload's public API** (`get_by_id`, `get_by_string`, `pack_voxel`, `material_id_from_packed`, `type_value_for_material`) keeps its current shape. The flyweight pattern (one Resource per material, every voxel shares the reference) is unaffected.
- **Item registry call sites** (`add_item("iron_pommel", 1)`, `has_item("spear")`) don't change — every call site already uses strings.

---

## Implementation Plan (when this lands)

Ordered for minimum disruption. Each step is independently shippable:

### Step 1 — Add string-id translation tables to the registry (no behavioral change)

In `VoxelMaterialRegistry.gd`:
- Add `_int_to_string: Dictionary` and `_string_to_int: Dictionary` (built at load alongside the existing `_by_id` / `_by_string`).
- Sort all loaded materials by `id_string` alphabetically, allocate int IDs `1..N` in sort order.
- Keep the `@export var material_id` field on `VoxelMaterial.gd` working — but **prefer the auto-assigned ID** if both are present and they conflict. Log a warning naming the override.
- Existing `.tres` files keep their hand-authored int IDs as a hint; new ones can leave `material_id = 0` (signal: "auto-assign").

At this point everything works exactly as today. No saves break, no generators change.

### Step 2 — Bump save format with a string-id table

In `VoxelStreamSQLite` save flow (touch `WORLD_GENERATOR_VERSION`, currently 14):
- New `material_id_table` row in the meta table: JSON dictionary `{ "stone": 1, "dirt": 2, ... }`.
- On save: write the current registry's `_string_to_int` snapshot to that row.
- On load: read the row, build a remap table (`old_int → new_int` based on string match), and rewrite voxel bytes only if the int IDs don't match the current registry's assignment.

If a save references a string ID that isn't in the current registry (mod uninstalled), the chunk loads as **air** with a one-time warning naming the missing IDs. This is the modding-friendly behavior: missing-content failures degrade gracefully rather than crashing.

### Step 3 — Stop authoring `material_id` in `.tres` files

- Remove the `@export_range(1, 254) var material_id` field from `VoxelMaterial.gd` (or demote to `@export_storage` so it's persisted but not editor-facing).
- Update every `.tres` in `assets/voxels/materials/` to drop the field (or leave it; the registry ignores it).
- Update `design/3D_VOXEL_MIGRATION.md`, `CLAUDE.md`, and the comments inside `VoxelMaterial.gd` to remove "pick an unused int" from the designer flow.

### Step 4 — Migrate `InventoryManager.ITEM_REGISTRY` to `.tres` files

- New `Item.gd` Resource class mirroring `VoxelMaterial.gd`'s pattern (one Resource per item).
- New `InventoryItemRegistry.gd` autoload (or fold into `InventoryManager` itself) scans `assets/items/`.
- Migrate the existing `ITEM_REGISTRY` const dictionary to a one-off generator script that emits one `.tres` per entry, then delete the const.
- All call sites continue to use `InventoryManager.add_item("iron_pommel")` etc. — the lookup goes through the registry instead of the const.

This step is the largest of the four because it touches every item, but each individual change is mechanical.

---

## Mod Namespacing Rules (when mods land)

Once the foundation is in place, mods declare a namespace prefix in their manifest:

```json
{
    "mod_id": "ashlands_expansion",
    "version": "1.2.0",
    "namespace": "ashlands",
    "depends_on": ["vanilla>=1.0"]
}
```

All content the mod ships uses that prefix:
- `assets/voxels/materials/obsidian.tres` with `id_string = "ashlands.obsidian"`
- `assets/items/ash_dagger.tres` with `id_string = "ashlands.ash_dagger"`

Base-game content uses `vanilla.` (or no prefix; treated as `vanilla.` internally). Mods that omit the namespace prefix on their content get a load-time warning — name collisions with vanilla or other mods are caller error, not engine error.

---

## What Else Modding Will Eventually Need

(Out of scope for this doc; recorded so we don't paint ourselves into a corner.)

1. **A mod loader autoload** — scans `user://mods/*/`, reads `mod.json`, mounts `.pck` files via `ProjectSettings.load_resource_pack()`, and extends the registry scans to include mounted paths.
2. **Load order + dependency resolution** — manifest `depends_on` field, topological sort, missing-dep error reporting.
3. **Save mod-manifest header** — saves record which mods were active when they were written. Loading a save without the same mods raises a confirmation dialog ("This save was made with X. Load anyway? Y/N — missing content becomes air / inaccessible.").
4. **Event hooks (post-launch)** — signal-based extension points on each manager (`enemy_killed`, `voxel_mined`, `dialogue_choice_made`, `weather_changed`). Mods *listen*; they don't monkey-patch. Survives refactors.
5. **Texture pack stacking** — the existing texture-pack pipeline (`tools/build_texture_atlas.py`) gets a `mod_overrides/` layer that composites on top of the base atlas at load.
6. **Multiplayer mod-hash check** — co-op hosts publish their active mod set; clients must match before terrain syncs. Authoritative-host alternative recorded but not designed.

---

## Cross-References

- `CLAUDE.md` — top-level project bible; the "Critical GDScript patterns" section will gain a "voxel material ID lookup" rule pointing here once Step 1 lands.
- `design/3D_VOXEL_MIGRATION.md` → "Voxel Material System" — designer flow needs the "pick an unused int" step removed once Step 3 lands.
- `design/ITEM_LIBRARY.md` — once items are migrated to `.tres` (Step 4), the canonical recipe reference will point to the registry rather than the inline `ITEM_REGISTRY` dictionary.
- `design/SAVE_SYSTEM.md` — gets a new "string-id table" subsection once Step 2 lands.
- `DESIGNER_TODO.md` → Section 9 (parking lot) — task tracking the refactor itself.

---

## Open Questions (decide before Step 1)

1. **What happens to the existing `material_id` integers in shipping `.tres` files?** Two options:
   - **A.** Hard reset — registry auto-assigns from scratch, hand-authored values ignored. Simplest. Forces a `WORLD_GENERATOR_VERSION` bump and breaks all existing saves.
   - **B.** Soft migration — registry respects hand-authored IDs where they don't collide, auto-assigns the rest. Preserves saves through the transition. More code.
   - **Lean:** B for the bridge, then A once we've shipped one version with the migration code in place.
2. **Should mods be allowed to *replace* a vanilla material (e.g. retexture stone)?** Or only *add* new materials?
   - Replace = more flexible, more breaking. Skyrim model.
   - Add only = safer, less flexible. Stardew Valley vanilla model.
   - **Lean:** add-only at first; revisit when a real use case demands replacement.
3. **Do we need a separate `Item.gd` Resource class, or can we extend `VoxelMaterial.gd` (since items and materials share a lot of fields)?**
   - They share `id_string`, `display_name`, icon… but diverge on everything material-specific (mining, gravity, allowed_tools). One class with optional fields would be confusing.
   - **Lean:** separate `Item.gd`, keep them parallel but distinct.

Resolve these before Step 1 lands.
