class_name VoxelMaterial
extends Resource
# VoxelMaterial — one entry in the material registry.
#
# What this is in plain English:
#
# Every voxel in the world is one of these — stone, dirt, grass, sand.
# This Resource holds everything a voxel of that material needs to know:
# what it looks like, how long it takes to mine, what tool can mine it,
# what the player gets when they break it, and how it falls under
# gravity.
#
# How designers add a new material (the whole point of this system):
#
#   1. In Godot, navigate to assets/voxels/materials/ in the FileSystem dock.
#   2. Right-click → New Resource → "VoxelMaterial" → save as <name>.tres
#      (e.g. snow.tres, marble.tres, mud.tres).
#   3. Click the new .tres file. The Inspector now shows every field below.
#      Fill them in.
#   4. Pick a material_id between 1 and 254 that no other material uses.
#      The registry prints "loaded N materials: stone(1), dirt(2), …"
#      to the Output panel at startup so you can see which IDs are free.
#   5. Save. Restart the project. The material is live.
#
# That's it. No GDScript editing required for new materials.
#
# Why a Resource subclass: this mirrors the existing EnemyData /
# NPCData / NPCScheduleEntry pattern in the project. Designers
# already know how to author those, and the inspector already gives
# them a clean UI for filling fields.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Voxel Material System"


# =============================================================
# IDENTITY
# =============================================================

@export var id_string: String = ""
# Stable identifier — "stone", "grass", "iron_ore". Used by code that
# needs to refer to a material by name (e.g. the heightmap generator
# saying "the surface layer is grass"). This MUST stay the same once
# saves exist with this material — renaming the .tres file is fine,
# but changing id_string after release breaks any code that names this
# material by string.

@export_range(1, 254) var material_id: int = 0
# 1–254. This integer is what gets packed into the alpha byte of every
# voxel of this material. The mesher uses alpha for solid-vs-air
# (alpha == 0 means air); we repurpose the non-zero range as a
# material lookup key.
#
# IMPORTANT: every material in the game must have a UNIQUE
# material_id. The registry validates this on startup and refuses
# to load colliding materials with a loud error message naming
# both .tres files. You'll see the conflict in the Output panel.
#
# Reserved values:
#   0   = air (do not assign — the mesher and the generator both
#         treat 0 as "no voxel here")
#   255 = reserved for future use; don't assign
#
# In practice we have ~12 raw materials planned for Game One
# (design/ITEM_LIBRARY.md lines 46-64), so 254 is plenty of headroom.

@export var display_name: String = ""
# UI string — "Stone", "Grass", "Iron Ore". Shown in the journal,
# inventory tooltips, etc. Localizable later (Game Two onward).


# =============================================================
# VISUALS — color and per-voxel jitter
# =============================================================

@export var color_low: Color = Color.WHITE
# The base color at the BOTTOM of this material's vertical band in the
# world. For a stone band running Y=0 to Y=50, this is the colour at
# Y=0. The generator linearly interpolates between color_low and
# color_high based on each voxel's position within the band.

@export var color_high: Color = Color.WHITE
# The base color at the TOP of this material's vertical band.
# Lighter or differently-tinted than color_low typically — sun-
# bleached stone vs. shadowed valley stone, for example.

@export_range(0.0, 1.0, 0.01) var color_jitter: float = 0.05
# Per-voxel brightness jitter applied on top of the lerped color.
# Values are randomized deterministically from voxel coordinates so
# the same voxel always looks the same colour across save/load.
#
# 0.0 = every voxel of this material is the same colour (looks
#       like a solid wall — visually boring).
# 0.05 = subtle variation, individual cubes still readable but the
#        wall looks like one material — the recommended default.
# 0.2 = strong variation, each cube very visible (good for stone/
#       gravel; might look noisy for grass).


# =============================================================
# MINING — how the player breaks this material
# =============================================================

@export_range(0.0, 30.0, 0.1) var mining_time_seconds: float = 0.4
# Baseline swing time for the 2×2×2 (8-voxel) mining volume. The
# actual swing time scales with the volume the player has selected
# via the scroll wheel:
#   1×1×1 (1 voxel)  → 1/8 of this value  (fast precision dig)
#   2×2×2 (8 voxels) → exactly this value (baseline)
#   3×3×3 (27 voxels) → 27/8 of this value (slow bulk dig)
#
# Suggested baseline values (for the 2×2×2 carve):
#   0.2  - sand, snow, leaves (super fast)
#   0.3  - dirt, grass, clay
#   0.6  - soft wood, soft stone
#   0.8  - hard stone (default for stone)
#   1.5  - hard wood, iron ore
#   3.0  - steel ore
#   5.0  - adamant ore (lore says it's the hardest material)
#
# Tool animation pacing is separate (see swing_cooldown_seconds in
# EditToolHandler — runs after each successful swing regardless of
# carve volume).

@export var allowed_tools: Array[String] = []
# InventoryManager item_ids of the PREFERRED tools for this material.
# Tools in the list mine at 1.0× the per-material baseline; tools NOT
# in the list mine at `EditToolHandler.WRONG_TOOL_SPEED_MULTIPLIER`
# (currently 3×). The list is no longer a hard gate — any manual tool
# can mine any material, but mismatched tool/material pairs are slow.
#
# Empty array means "no tool can mine this." Bedrock uses this to
# stay unbreakable. Don't use empty for soft / any-tool-works materials
# any more — list the preferred tools explicitly so the speed
# multiplier behaves predictably.
#
# Examples:
#   ["iron_pickaxe", "stone_pickaxe"]  - stone / ore — pick is best
#   ["iron_shovel", "stone_shovel"]    - dirt / sand / clay — shovel
#   ["iron_axe", "stone_axe"]          - wood / log — axe
#   []                                  - unbreakable (bedrock)
#
# Tool tier gating (Common/Quality/Masterwork) is documented in
# design/3D_VOXEL_MIGRATION.md lines 148-156. Adamant ore would
# require ["masterwork_pickaxe"], etc.

@export var yield_item_id: String = ""
# What the player gets when they break a voxel of this material.
# References InventoryManager.ITEM_REGISTRY by id (e.g. "raw_stone",
# "raw_dirt", "raw_log").
#
# Empty string means "no yield" — useful for materials that aren't
# meant to be harvested (e.g. impassable lore-monument stone, or a
# placeholder material in early development).
#
# The registry validates this against ITEM_REGISTRY at startup and
# warns if the item doesn't exist. Add new items to InventoryManager
# before pointing a material at them.

@export var yield_quantity: int = 1
# How many of yield_item_id to add to the inventory per voxel broken.
# Almost always 1 for v1. Keep this for future tuning (e.g. an "ore
# chunk" voxel might yield 3 ore lumps).


# =============================================================
# GRAVITY — how this material falls when unsupported
# =============================================================

enum FallBehavior {
	NEVER,
	# Anchored geometry that never participates in gravity collapse
	# even when unsupported. Use only for materials that should look
	# load-bearing on their own (e.g. magic stone that stays put). v1
	# pilot materials don't use this — terrain materials use
	# PICKUP_DROP instead.

	SOLID,
	# Falls as a rigid-body cluster via VoxelGravityManager + spawns a
	# FallingVoxelCluster. The cluster physically tumbles, possibly
	# damages bodies on impact, and re-deposits as terrain when it
	# settles. Use this for materials that should fall over and stay
	# visible as a chunk — chopped tree trunks (so a felled limb lies
	# on the ground for the player to chop into pieces), heavy ore
	# boulders, etc. material.gravity_scale and damage_multiplier
	# scale the cluster physics.

	LOOSE,
	# Sand model. The voxel falls instantly, column-by-column, into any
	# air gap directly below it. No rigid body, no tumbling — the voxel
	# just appears one Y lower (or however many Y values it takes to
	# land on something solid). This is what makes sand "pour" when you
	# dig under it.

	LIQUID,
	# Water model. The voxel does NOT live in CHANNEL_TYPE — it lives
	# in WaterFlowManager's dictionary as a flow cell. The water slot
	# (material_id 5) in VoxelBlockyLibrary is intentionally empty so
	# writing TYPE=5 renders nothing; WaterChunkMesher emits the
	# transparent surface mesh separately by walking the flow dict.
	# Flow rules: source cells (designer/player-placed) are permanent;
	# flowing cells spread cellular-automata-style downward and
	# laterally with monotone-decay, capped at 8 levels of distance
	# from a source. See scripts/WaterFlowManager.gd.

	PICKUP_DROP,
	# Default for terrain/earth materials (stone, dirt, grass). When an
	# unsupported voxel of this material is detected, instead of
	# spawning a rigid-body cluster, we carve the voxel from terrain
	# and spawn a single VoxelDrop at its world position. The drop
	# falls under gravity, settles, hovers, and auto-collects when the
	# player walks within its pickup radius. Net effect: digging out a
	# cliff face produces a cluster of pickup blocks instead of a
	# physics-tumbling chunk that re-deposits — easier UX, no need to
	# re-mine fallen rubble. material.yield_item_id and yield_quantity
	# drive what the player gets per drop.
}

@export var fall_behavior: FallBehavior = FallBehavior.NEVER

@export_range(0.1, 5.0, 0.05) var gravity_scale: float = 1.0
# Multiplier on cluster fall speed. Only meaningful for NEVER and
# SOLID materials (LOOSE materials don't use rigid-body physics).
#
# 1.0 = standard fall (matches Player3D.GRAVITY = 20 m/s²)
# 1.5 = heavier-feeling — iron ore, steel
# 0.7 = lighter-feeling — pumice, soft wood
#
# Mixed clusters (multiple materials) use the AVERAGE gravity_scale
# across constituent voxels.

@export_range(0.0, 5.0, 0.1) var damage_multiplier: float = 1.0
# Multiplier on crush damage when a falling cluster of this material
# lands on something. The base damage is voxel_count × fall_height ×
# 0.05 (set in FallingVoxelCluster.gd). This multiplier scales it.
#
# 1.0 = default
# 0.3 = soft / cushioned — sand (LOOSE so this rarely matters), snow
# 1.5 = sharp — flint, broken glass
# 2.0 = heavy / sharp — iron ore, adamant
#
# Mixed clusters take the MAXIMUM damage_multiplier across constituent
# voxels (the deadliest material in the chunk wins).


# =============================================================
# SOUND — hooks for audio (not wired in v1)
# =============================================================

@export var step_sound: AudioStream = null
# Audio played when the player walks on a voxel of this material.
# Not wired in v1; lands when AudioManager arrives.

@export var break_sound: AudioStream = null
# Audio played when a voxel of this material is broken by mining.
# Not wired in v1; lands when AudioManager arrives.
