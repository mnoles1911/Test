# Combat / Physics / Enemy Systems — Next Phases

> Companion to `design/COMBAT_DESIGN_3D.md` (combat spec — what we want), `design/ENEMY_AI.md` (enemy roster + AI patterns), and the v1 milestone entry in `CLAUDE.md` (what shipped). This doc is the single source of truth for **what's NEXT** in those three systems. Update when a phase ships or priorities shift.

## What's already shipped (May 2026)

Voxel Combat v1 (PRs #167, #171, #172, #173, #174):

- `Enemy3D` base class + `Goblin` v1 placeholder enemy
- `ThrowableSpear` projectile (sticks, pivots with corpse, retrievable)
- `BloodVFX` autoload (burst / drip / pool / dust)
- `CombatTest.tscn` dev arena with F1 debug menu
- Corpse persistence (5 min) + E-press loot infrastructure
- Spear-on-self collision filter
- Particle materials with `vertex_color_use_as_albedo`
- Pool renderer compatibility (PlaneMesh instead of Decal for gl_compatibility)

The slice is testable end-to-end: throw spear → goblin bleeds → goblin dies → corpse falls + spear pivots → walk up → E loot → spear back in inventory.

---

## Priority order (as of May 2026)

1. **Phase 5 finish — gib clusters + time-slow on lethal hits** (most visible payoff)
2. **Phase 3 finish — charge mechanic + HUD ring + spear arm tilt**
3. **Real Roland + Goblin .glb integration via Mixamo** (replace placeholder boxes)
4. **Second enemy type — Ashfallen** (validates Enemy3D extensibility)
5. **Melee combat foundation** (tap/hold LMB, parry, block, lock-on)
6. **Group AI** (attack tokens, fleeing, swarm override per `design/ENEMY_AI.md`)
7. **Non-humanoid enemies — Wolf, Bear**
8. **Companion AI** (Orion, Dagna)

Each phase below has:
- **What** the work is
- **Files** to create / modify
- **Dependency** (what has to be true before starting)
- **Defer signal** (what would push this back)

---

## Phase 5 finish — Gib clusters + time-slow on lethal

The user-visible jump from "corpse falls flat" to "body explodes into chunks on charged kills" is the single biggest combat win still unshipped.

### Scope
- `Goblin._on_died` reads `damage_at_kill`. If ≥ 80 dmg (overkill threshold from the v1 plan), spawn a `FallingVoxelCluster` of ~80 chunky cubes (mix of green outer-skin + red core voxels) with outward radial impulse from `hit_point` along `hit_dir` instead of laying the corpse flat.
- 0.15 s time-slow on lethal hit via `Engine.time_scale = 0.05` + a one-shot `Timer` with `process_mode = PHYSICS` so the restore fires reliably.
- Camera kick on lethal — add `CameraRig.kick(magnitude: float, duration: float)`. Tween `Camera3D.position` along a random unit vector and back.
- Spear that was embedded in the goblin reparents to the largest gib chunk so it visibly travels with the explosion.

### Files
- `scripts/enemies/Goblin.gd` — branch `_on_died` on damage_at_kill
- `scripts/Enemy3D.gd` — small helper for gib-cluster spawn (could move to base class)
- `scripts/CameraRig.gd` — add `kick(magnitude, duration)` method
- `scripts/throwables/ThrowableSpear.gd` — listen to `enemy.died` signal, find nearest gib chunk, reparent

### Dependency
- `FallingVoxelCluster.gd` and `VoxelClusterBuilder.gd` already exist (used by `VoxelGravityManager`). Reuse those.
- Use `embed_on_settle = false` on the cluster so gibs don't merge back into terrain.

### Defer signal
- If `FallingVoxelCluster` proves wrong-shaped for character gibs (it's tuned for terrain falls), consider building a `CharacterGibCluster` variant.

---

## Phase 3 finish — Charge mechanic + HUD ring + spear arm tilt

Started in commit 248b773 (`CameraRig.set_charge_pinch` hook only). Finish the rest.

### Scope
- `ThrowableHandler.gd`: replace `is_action_just_pressed("attack")` with hold tracking. Track `_charge_start_msec` on press; on release compute `hold_ms`; lerp damage 30→60 and velocity 9→16 across the 150–700 ms window.
- HUD charge ring on `HUDOverlay.gd` Layer-5 CanvasLayer. Centered radial fill, grey at 0 → `#E8873A` warm orange at full charge. **Manual `_input` dispatch only** per CLAUDE.md hard rule (no `Button.pressed` signals).
- Spear arm tilt: add `set_arm_charge(t)` on `Player3D.gd`. Rotates a `SpearArm` `Node3D` (placeholder; lands properly when Roland's rigged `.glb` arrives via Mixamo) up to 90° on local X.
- `CameraRig.set_charge_pinch(t)` already wired — caller (ThrowableHandler) feeds it the same `t` value.

### Files
- `scripts/ThrowableHandler.gd` — input model
- `scripts/HUDOverlay.gd` — ring node + draw + manual click dispatch
- `scripts/Player3D.gd` — `set_arm_charge(t)` proxy

### Dependency
- None — all three feedback channels can land independently.

### Defer signal
- If user testing finds the FOV pinch + charge ring already sells the charge feel, the spear arm tilt can ship later (cosmetic only).

---

## Replace placeholder green boxes with rigged Mixamo characters

User's first end-to-end Mixamo run already validated the asset pipeline (goblin animates in Godot preview). Now wire the `.glb` into the gameplay scenes.

### Scope
- Swap `scenes/enemies/Goblin.tscn` Visual `MeshInstance3D` to instance `assets/models/goblin.fbx` import scene.
- Add `AnimationPlayer` wiring in `Goblin.gd`: idle in IDLE state, walk in COMBAT, attack on contact damage, react on damage, death on `_on_died`.
- Repeat for `Player3D.tscn` once Roland's Mixamo rig lands.
- Update `Goblin.tscn` ChestSocket position to match the new model's actual chest height (not the green-box 1.2m).
- Update EyeGlow to attach to the head bone of the rigged skeleton (so it tracks head turns), or replace with emissive eye voxels baked into the model.

### Files
- `scenes/enemies/Goblin.tscn`
- `scripts/enemies/Goblin.gd` — animation state dispatch
- `scenes/Player3D.tscn` (when Roland lands)

### Dependency
- `assets/models/goblin.fbx` exists and animates correctly (✓ validated).
- Roland `.glb` not yet authored — follow `design/ASSET_PIPELINE_AI.md` Path A (Meshy → Blender voxelize → Mixamo) as for Goblin.

### Defer signal
- Animation state machine quirks (transition glitches, foot sliding) can land in a polish pass after the rest of v1 ships.

---

## Second enemy type — Ashfallen v1

Validates that `Enemy3D` actually extends cleanly to a different enemy archetype (one of the design goals for the base class).

### Scope
- New `scripts/enemies/Ashfallen.gd` extending `Enemy3D`. Slower (`walk_speed_meters_per_second = 1.8`), tougher (`max_health = 120`), longer detection (`alert_range_meters = 18`), fewer attacks but heavier contact damage (`contact_damage = 18`).
- New `scenes/enemies/Ashfallen.tscn` with placeholder grey-iron box (same approach as Goblin — swap to Mixamo .glb after asset pipeline run).
- No glow eyes (Ashfallen helmet is faceless per `lore/CHARACTERS_NPCS.md`); replace with a slow rust-orange emissive ring on the helmet.
- Override `_loot_corpse` to return any embedded throwables + 1× rusted blade to inventory.
- Add to CombatTest arena as a fourth enemy (or a separate `AshfallenTest.tscn`).

### Files
- `scripts/enemies/Ashfallen.gd`, `scenes/enemies/Ashfallen.tscn`
- `scenes/_dev/CombatTest.tscn` — optional second enemy slot
- `scripts/InventoryManager.gd` — register `rusted_blade` item

### Dependency
- Phase 5 finish (gib clusters) is recommended first — Ashfallen's heavier corpse benefits more from the gib treatment than the goblin does.
- Real Mixamo .glb is optional — placeholder works for AI/balance testing.

### Defer signal
- If group AI lands first, Ashfallen integrates with attack-token system out of the gate; if not, it ships as another solo walk-toward-player like Goblin.

---

## Melee combat foundation

Per `design/COMBAT_DESIGN_3D.md` lines 24–48 (tap/hold LMB power system, parry, block, lock-on). Currently NOT scoped in v1 — spear-only ships first.

### Scope (high-level)
- LMB dispatcher on `ThrowableHandler.gd`: if equipped weapon `type == "throwable"` → existing throw flow; if `type == "weapon"` → new `MeleeHandler.gd`. The handler split is the cleanest insertion point (ThrowableHandler currently short-circuits on non-throwable).
- `MeleeHandler.gd` reads tap vs hold for light vs power swing. Spawns hitbox `Area3D` along the swing arc, deals damage to overlapping enemies.
- `RMB`-based block + parry with green/yellow/red attack flash colors per `COMBAT_DESIGN_3D.md` line 47.
- Endurance integration: light swing 8 EP, power swing 18 EP, block 12 EP/hit absorbed, parry 5 EP per `COMBAT_DESIGN_3D.md` lines 60–77.
- Lock-on: extend `CameraRig` lock-on API (already stubbed). Tab to cycle targets among visible enemies in forward arc.

### Files
- `scripts/MeleeHandler.gd` (new), `scripts/ThrowableHandler.gd` (route by weapon type)
- `scripts/CameraRig.gd` — wire lock-on cycle
- `scripts/Enemy3D.gd` — hitbox `Area3D` children for limb-zone hit detection

### Dependency
- Roland `.glb` with attack animations from Mixamo. Without animations, the swing has no visible follow-through.
- Lock-on UI cue (target reticle on locked enemy) — small `HUDOverlay` addition.

### Defer signal
- If real Game One playtests show ranged spear combat is enough for Act I encounters, melee can defer to a later milestone.

---

## Group AI — attack tokens, fleeing, swarms

Per `design/ENEMY_AI.md` lines 79–90.

### Scope
- New `EnemyAIManager.gd` autoload. Tracks the global "active attacker" token: only one enemy at a time may commit to an attack swing; others orbit at mid-range. Token transfers on attacker recovery, stagger, death, or 2-second timeout.
- Goblin override: 4+ goblins ignore the token system (swarm mechanic from `ENEMY_AI.md` line 100). Each `Goblin._enemy_physics_step` checks `EnemyAIManager.get_active_count()`.
- Fleeing: when last goblin in a group remains, 60% chance to flee per `ENEMY_AI.md` line 116. Adds a FLEE state to `Enemy3D.State` enum.
- Group alert broadcast: `Enemy3D.died` signal triggers nearby enemies (within `group_alert_radius`) to immediately enter ALERT.

### Files
- `scripts/EnemyAIManager.gd` (new autoload), register in `project.godot`
- `scripts/Enemy3D.gd` — add FLEE state + `group_alert_radius` export
- `scripts/enemies/Goblin.gd` — swarm override
- Update `CLAUDE.md` autoload list

### Dependency
- Multiple enemy types alive at once (CombatTest arena scaling up). Currently 3 goblins; bump to 6+ for swarm validation.
- Phase 5 finish — group alert is more readable when corpses persist.

### Defer signal
- Single-enemy encounters work fine without this. Defer if Act I roadmap shifts to fewer encounters.

---

## Non-humanoid enemies — Wolf, Bear

Mixamo doesn't auto-rig quadrupeds; these need manual rigging in Blender + the optional Voxel Heat Diffuse Skinning add-on (per `design/ASSET_PIPELINE_AI.md` troubleshooting section).

### Scope
- `scripts/enemies/Wolf.gd`: pack hunter (3–5 per encounter), no token system per `ENEMY_AI.md` lines 145–167. Lunge attack as primary, narrow parry window. Faster than Goblin (`walk_speed = 4.5`).
- `scripts/enemies/Bear.gd`: solo mini-boss per `ENEMY_AI.md` lines 169–190. Charge attack (unblockable), claw swipe, rear-up phase under 30% HP.
- Both need manual Blender rigging — Mixamo doesn't auto-rig quadrupeds. Use Voxel Heat Diffuse Skinning to compute skin weights on the chunky voxelized models.
- Add WolfTest and BearTest dev arenas under `scenes/_dev/`.

### Files
- `scripts/enemies/Wolf.gd`, `scripts/enemies/Bear.gd`
- `scenes/enemies/Wolf.tscn`, `scenes/enemies/Bear.tscn`
- `scenes/_dev/WolfTest.tscn`, `scenes/_dev/BearTest.tscn`
- `assets/models/wolf.glb`, `assets/models/bear.glb` (manual Blender pipeline)

### Dependency
- Manual Blender quadruped rig — significantly more authoring time than humanoid.
- Group AI for Wolf packs (or skip for solo Wolf v1).

### Defer signal
- Heavy authoring cost for two enemies. Defer until Act I narrative requires them.

---

## Companion AI — Orion, Dagna

Per `design/COMPANION_SYSTEM.md` and `design/ENEMY_AI.md` companion AI section (lines 209–228 pseudocode).

### Scope (deferred — full design exists; not breaking it down further until v1 combat is content-locked)
- `CompanionManager.gd` autoload (already specified in CLAUDE.md "not yet implemented").
- Orion: ranged combat (bow), maintains distance. New `Bow.gd` weapon analogous to spear.
- Dagna: melee tank, taunts enemies. Reuses melee combat foundation.
- Combat orders UI (`Hold Position` / `Engage` / `Defend Roland`).
- Downed/revive system per `design/COMPANION_SYSTEM.md`.

### Dependency
- Companion `.glb` assets (Mixamo path).
- Melee combat foundation for Dagna.
- Group AI for clean enemy/companion interaction.

### Defer signal
- Companions are an Act I content gate, not a tech gate. Build when Act I encounter design needs them.

---

## Physics polish (across all phases)

Items that don't fit neatly into a single phase but need to land somewhere.

- **Spear surface normal on terrain hit**: currently `_impact_terrain` uses `-travel_dir` as the "best guess outward" axis since `body_entered` doesn't carry contact details. Glancing wall skims look wrong. Fix: switch to `body_shape_entered` and read the contact normal from the terrain's collision shape, OR add a forward `RayCast3D` on the spear that captures the surface normal one frame before impact.
- **Spear-into-NoEditZone**: currently spears in NoEditZones still embed normally. Decision: should they bounce? Stick? Pass through? Match the no-edit voxel rule semantically.
- **Knockback impulses on hit**: `take_damage` should apply a small forward velocity to the enemy along `hit_dir`. Visible push-back sells the impact and creates positioning openings. Cap so a wounded enemy isn't punted off the map.
- **Per-hit zones**: `Goblin.tscn` has `HeadHitbox`, `TorsoHitbox`, `LimbHitbox` `Area3D` children mentioned in `Enemy3D.gd` doc but not actually authored. Add them and route hit detection through them for damage-multiplier zones (head 2.0×, torso 1.0×, limb 0.6×).
- **Friendly fire toggle**: in case of multiplayer or pet companions, decide whether spears can damage allies.

---

## Tracking / housekeeping

- This doc replaces ad-hoc "Phase X" mentions scattered in commit messages and the asset pipeline doc. When a phase ships, move it to the "What's already shipped" section at top with a date and PR reference, then drop the old detailed section.
- Major refactors to `design/COMBAT_DESIGN_3D.md` or `design/ENEMY_AI.md` should reference this doc as the implementation-truth companion.
- If the priority order shifts (e.g. Game One narrative pushes Bear forward), reorder the section anchors and update CLAUDE.md's pointer paragraph.
