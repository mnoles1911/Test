# Critical scene hierarchies

Load-bearing structures — scripts use hardcoded `$NodeName` references. Don't reorganise without updating the consuming script.

---

## Player3D / CameraRig

```
Player3D (CharacterBody3D + Player3D.gd)
├── CameraTarget (Node3D)
│   └── SpringArm3D (+ CameraRig.gd)
│       └── Camera3D
├── MeleeWeaponPivot (Node3D)            ← directional-melee v1 (sword pivot, right hand)
│   ├── SwordVisual (MeshInstance3D)
│   └── MeleeWeaponHitbox (Area3D)
├── ShieldPivot (Node3D)                 ← directional-melee v1 (shield, left hand)
│   └── ShieldVisual (MeshInstance3D)
├── MeleeHandler (Node3D + MeleeHandler.gd)
├── EditToolHandler (Node3D + EditToolHandler.gd)
├── ThrowableHandler (Node3D + ThrowableHandler.gd)
├── UnderwaterFilter (CanvasLayer)
└── ...
```

- `CameraRig` walks `get_parent().get_parent()` to reach the `CharacterBody3D`. Don't add wrapper nodes between them.
- Two camera modes: **Standard** (mouse rotates `Player3D` body — W always toward camera) and **Freelook** (hold `freelook_camera`, default F2 — orbits arm without rotating Roland; re-centers on release).
- Combat camera is free-aim — no lock-on. `MeleeWeaponPivot` and `ShieldPivot` are placeholder rigs; swap to bone-attachments when Mixamo Roland lands.

---

## NPC (NPC.gd)

```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D
├── CollisionShape3D
├── BarkArea (Area3D)          ← must be named exactly "BarkArea"
│   └── CollisionShape3D
└── InteractArea (Area3D)      ← must be named exactly "InteractArea"
    └── CollisionShape3D
```

Assign an `NPCData` resource from `/assets/npcs/` in the Inspector. Tier 0 background NPCs are plain `Node3D`, no `NPC.gd`.

---

## Enemy3D / Goblin (post directional-melee v1)

```
EnemyNode (CharacterBody3D + Enemy3D subclass)
├── Visual (MeshInstance3D)            ← albedo tinted yellow/red during WINDUP telegraph
├── CollisionShape3D
├── ChestSocket (Node3D)               ← spear embed point; rotates with corpse on death
├── EyeGlow (MeshInstance3D, optional)
└── EnemyAttackPool (Node + EnemyAttackPool.gd, composed in _ready)
```

`EnemyAttackPool` is composed (not inherited) — runs its own READY/WINDUP/STRIKE/RECOVERY/STAGGERED state machine independent of `Enemy3D`'s detection state. Emits `committed_attack(direction, time_to_impact, is_unblockable)` via the host's `Enemy3D.committed_attack` signal.

---

## VoxelLodTerrain (World3D.tscn)

```
World3D (Node3D)
├── VoxelLodTerrain
│   ├── generator: VoxelGeneratorScript (CubicHeightmapGeneratorAdapter.gd)
│   │   └── cpp_impl: CubicHeightmapGeneratorCpp
│   ├── stream: VoxelStreamSQLite
│   └── mesher: VoxelMesherBlocky
├── VoxelViewer (child of Player3D)
├── EntityStreamer
└── ...
```

---

## NoEditZone authoring (settlement / interior)

```
SettlementRoot (Node3D)
├── NoEditZone (Area3D, group: "no_edit_zone")
│   └── CollisionShape3D (Box/Convex, ~50–100m buffer)
├── BuildingProp (MeshInstance3D — MagicaVoxel .glb)
└── ...
```

Every settlement, dungeon entrance, and lore landmark sits under a `NoEditZone`. Writes inside are silently rejected and trigger Roland's bark *"This place doesn't yield to me."*
