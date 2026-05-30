# Combat / Physics / Enemy Systems — Next Phases

> Companion to `design/COMBAT_DESIGN_3D.md` (combat spec — what we want), `design/ENEMY_AI.md` (enemy roster + AI patterns), and the v1 milestone entry in `CLAUDE.md` (what shipped). This doc is the single source of truth for **what's NEXT** in those three systems. Update when a phase ships or priorities shift.

## What's already shipped (May 2026)

### Voxel Combat v1 (PRs #167, #171, #172, #173, #174)

- `Enemy3D` base class + `Goblin` v1 placeholder enemy
- `ThrowableSpear` projectile (sticks, pivots with corpse, retrievable)
- `BloodVFX` autoload (burst / drip / pool / dust)
- `CombatTest.tscn` dev arena with F1 debug menu
- Corpse persistence (5 min) + E-press loot infrastructure
- Spear-on-self collision filter
- Particle materials with `vertex_color_use_as_albedo`
- Pool renderer compatibility (PlaneMesh instead of Decal for gl_compatibility)

The slice is testable end-to-end: throw spear → goblin bleeds → goblin dies → corpse falls + spear pivots → walk up → E loot → spear back in inventory.

### Directional Melee v1 (PR #239, branch `claude/game-combat-design-Z5oLa`, May 2026)

Phases 0-6 of the Bannerlord-style directional combat redesign. Currently in designer playtest. Replaces the older "Melee combat foundation" + "Lock-on auto-switch" phases that lived in this doc — both are subsumed (and lock-on was removed entirely 2026-05-25 in favour of pure free-aim).

**Loadout + item slots:**
- `iron_sword` (type `melee_weapon`) and `iron_shield` (type `shield`) registered in `InventoryManager.ITEM_REGISTRY`.
- New `offhand` equipment slot for shields. Sword + shield is the v1 baseline.
- `EditToolHandler` short-circuits on `melee_weapon` or `throwable` equipped so LMB routes cleanly.

**Mouse-direction sampler (`scripts/combat/MouseDirectionSampler.gd`):**
- 4 quadrants (overhead / left / right / thrust) with ±50° tolerance + 10° overlap zones.
- Returns `DIR_NONE` (-1) when no flick detected so the caller can apply its own fallback.
- Designer mapping: mouse flick UP → DIR_THRUST (forward stab), flick DOWN → DIR_OVERHEAD (downward chop). Inverts the Bannerlord/KCD convention but matches "the sword goes where I flick."

**Attack system (`scripts/MeleeHandler.gd`, owns LMB when sword equipped):**
- Bannerlord hold-flick-release: press LMB to start the windup, flick at any point during the hold to LOCK a direction (survives long holds even after the sampler window forgets), release to fire.
- Direction lock + auto-alternating LRLR fallback when no flick happens (silent press-releases still vary the swing).
- Light vs charged: release < `charge_threshold_seconds` (0.4 s) = base damage (15); release ≥ threshold = 2× charged damage (30). FOV pinch via `CameraRig.set_charge_pinch(t)` during the charge ramp.
- Feint cancel: flick to a different direction during the hold + release within `feint_window_seconds` (0.1 s) = no swing, no damage, no EP.
- Hyperarmor flag set during charge windup so the player can commit a big swing through a small hit (`Player3D._melee_hyperarmor`).
- Endurance: 8 EP per light swing, 18 EP on charged release. Drains on release, not while held.

**Swing geometry:**
- Wide-arc cone for overhead + side swings: 110° forward, up to 3 targets. Thrust stays narrow: 90°, single target. Range = `swing_cone_meters` (2.0).
- 3-stage sword animation per direction: WINDUP pose (sword raised/cocked/drawn back) → STRIKE pose (sword chopped down / swept across / thrust forward) → home. EASE_OUT on windup, EASE_IN on strike so the strike accelerates through contact.

**Block / parry (`scripts/MeleeHandler.gd`, RMB):**
- RMB tap (≤ 140 ms) = parry attempt against any pending committed_attack within 300 ms. Matched direction = stagger enemy 1.5 s, refund 5 EP, auto-fire riposte sweep (90° cone, 2 m, base damage).
- RMB hold = directional block. Shield raises in the matched direction. Block direction tracks the mouse continuously while held (active blocking).
- **Damage reduction is real** (the bug that the previous "block raised but did nothing" hid): `EnemyAttackPool._perform_strike` now consults `MeleeHandler.is_blocking_against(direction)`. Matched = 0 dmg, mismatched = 60% chip damage taken (40% blocked), auto-block ON = 0 dmg regardless of direction.
- Auto-block (`@export var auto_block: bool = false`): Bannerlord's "Auto Block" difficulty option. Toggleable in CombatTest via B; Settings menu UI is v1.1.

**Parry chain (`scripts/combat/ParryChainTracker.gd`):**
- Successive parries within decaying windows (1.0 → 0.7 → 0.5 s). Chain ≥ 2 refunds the full block-equivalent EP (net-zero cost on chained parries).
- DebugOverlay logs `PARRY dir=N chain=xN` so dev-arena testing can verify without the on-screen label.

**Enemy attack pool (`scripts/enemies/EnemyAttackPool.gd`):**
- Composed (not inherited) into `Goblin`. Independent state machine: READY → WINDUP → STRIKE → RECOVERY → STAGGERED. Only ticks when host's `current_state == COMBAT`.
- Goblin pool: 50% jab (DIR_THRUST), 18% left swing, 17% right swing, 15% unblockable leap (DIR_OVERHEAD, red flash).
- Yellow/red telegraph via `material_override.albedo_color` on the goblin visual during WINDUP. `committed_attack(direction, time_to_impact, is_unblockable)` signal emitted at WINDUP start.
- `_contact_damage_suppressed` flag set during WINDUP/STRIKE/RECOVERY so the goblin doesn't double-dip (touch damage + sword swing).

**Enemy3D additions:**
- `state_changed(old, new)` signal for HUD/system subscribers.
- `committed_attack(direction, time_to_impact, is_unblockable)` signal forwarded from the AttackPool.
- `stagger(duration)` method — locks the AttackPool into STAGGERED, suppresses contact damage. Used by successful player parry.
- `_stagger_remaining: float` ticks down each physics frame.

**Free-aim camera (lock-on REMOVED 2026-05-25):**
- LockOnManager autoload + file deleted. CameraRig lock-on API (`set_lock_on_target` / `cycle_lock_target` / `clear_lock_target` / `_update_lock_on_rotation` / `_lock_on_target`) stripped. `lock_on_cycle` input action (MMB) removed.
- The player has uninterrupted mouse-driven facing in 1-vs-many. Strafing + positioning is the depth axis, Bannerlord-style.

**HUD (Phase 6):**
- `HUDDirectionArrows` (Control, child of HUDOverlay): yellow/red arrows above each committed enemy's head, sized by time-to-impact. Off-screen attackers get screen-edge triangle pulses. Subscribes to every Enemy3D's `committed_attack` directly via the "enemy" group + `SceneTree.node_added`.
- `HUDCombatRadar` (Control, child of HUDOverlay): 80 px bottom-center radar. One dot per enemy in the "enemy" group within 24 m, coloured by alert state (grey IDLE / yellow ALERT / red COMBAT / bright-red unblockable windup). Bearing arc on the perimeter at the closest currently-committed attacker (replaces the old locked-target arc since lock-on is gone).
- Parry-chain count label on `HUDOverlay` status row (`Colors.MANA`, hidden in dev_scene since `_hide_all_chrome` blanks `_root` — DebugOverlay logs the chain count for dev-arena verification).

**Player3D.tscn scene additions:**
- `MeleeWeaponPivot: Node3D` at the right hand offset + `SwordVisual` (long thin box) + `MeleeWeaponHitbox: Area3D`.
- `ShieldPivot: Node3D` at the left hand offset + `ShieldVisual` (flat square).
- `MeleeHandler: Node3D` runs `scripts/MeleeHandler.gd`.
- All placeholder geometry — swap to Mixamo rig in the next phase.

**Dev arena (`scenes/_dev/CombatTest.tscn` + `CombatTestBootstrap.gd`):**
- Tight goblin triangle: front-left (-1.2, 0, -2), front-right (1.2, 0, -2), back-center (0, 0, -2.5). All three within 2 m sword reach for sweep testing.
- Goblin stop distance bumped to 1.7 m (was 0.8 m) so contact physics doesn't shove the player.
- Debug keys: F1 menu, F8 kill nearest (60 dmg), F9 wound (30 dmg), R reset triangle, K print loadout, M print MeleeHandler state, N toggle passive goblins, B toggle auto-block, Q quit.

**MP-2 awareness:** all Input.* reads in MeleeHandler gate via `Player3D._can_take_input()`. Combat is offline-only for v1; MP routing is a deferred epic.

---

## Priority order (as of 2026-05-25)

The directional melee foundation (Phases 0-6 of the v1 plan) is shipped. Remaining work, in rough priority:

1. **v1.1 polish bundle** — finishers + gib clusters + time-slow on lethal, combat audio cues, Spin-Parry perk, Settings UI for auto-block + accessibility (currently grouped because none has architectural risk on its own)
2. **Spear charge mechanic + HUD ring + spear arm tilt** — finishes the throwable side of the charge work; melee charge already ships in v1
3. **Mixamo .glb integration** — replace sword/shield + Roland body + Goblin placeholders with rigged models
4. **Second enemy type — Ashfallen** — validates `EnemyAttackPool` composition on a non-Goblin
5. **Group AI** — attack tokens, fleeing, swarm override
6. **Non-humanoid enemies — Wolf, Bear**
7. **Companion AI — Orion, Dagna** (Bow.gd + ranged combat depth lands here)
8. **v1.2+ Bannerlord depth** — per-weapon reach/speed, weapon-type restrictions, stagger from heavy hits, damage simulation depth (weight + momentum + skill + movement + hit zone), enemy AI dodge/block intelligence + attack obviousness. See dedicated section below.

Each phase below has:
- **What** the work is
- **Files** to create / modify
- **Dependency** (what has to be true before starting)
- **Defer signal** (what would push this back)

---

## v1.1 polish bundle — finishers, audio, perk, Settings UI

Low-risk additions that flesh out the v1 directional combat without changing its core loop. Grouped because none requires architectural work; ship in any order.

### Finishers + gib clusters + time-slow on lethal

The user-visible jump from "corpse falls flat" to "body explodes into chunks on charged kills" is the single biggest combat win still unshipped.

**Scope:**
- `Goblin._on_died` reads `damage_at_kill`. If ≥ 80 dmg (overkill threshold) OR caller was a charged sword swing OR 25% random on light kills, spawn a `FallingVoxelCluster` of ~80 chunky cubes (mix of green outer-skin + red core voxels) with outward radial impulse from `hit_point` along `hit_dir` instead of laying the corpse flat.
- 0.15 s time-slow via `Engine.time_scale = 0.05` + one-shot `Timer` (`process_mode = PHYSICS`).
- Camera orbit (~1.2 s, distinct from the existing FOV pinch) + player i-frames during the cinematic so a swarm kill doesn't punish the player for landing the finisher.
- Add `CameraRig.kick(magnitude, duration)` for the impact shake.
- Embedded spear (if any) reparents to the largest gib chunk so it travels with the explosion.
- Max 1 finisher per 6 s real-time (otherwise a swarm-cleanout is a slideshow).

**Files:** `scripts/enemies/Goblin.gd`, `scripts/Enemy3D.gd`, `scripts/CameraRig.gd`, `scripts/MeleeHandler.gd` (charged-kill trigger), `scripts/throwables/ThrowableSpear.gd` (spear-rides-gib).

**Dependency:** `FallingVoxelCluster.gd` + `VoxelClusterBuilder.gd` already exist. Use `embed_on_settle = false` on the cluster so gibs don't merge back into terrain.

### Combat audio cues

Wire `cmb_*` SFX through `AudioManager.play()` at every combat moment. AudioManager is no-op-safe until the `.ogg` files curate in.

**Scope:**
- 16 directional windup SFX prompts in `design/SFX_PROMPTS.md` — 4 directions × 4 enemy types (Goblin, Ashfallen, Wolf, Bear). Names like `cmb_swing_overhead_goblin_01`. Routed via `cmb_*` prefix → Combat bus.
- Call sites: MeleeHandler swing-fire, MeleeHandler hit-impact, MeleeHandler parry success, MeleeHandler block hit (matched + chip), EnemyAttackPool windup-start.

**Files:** `design/SFX_PROMPTS.md` (prompt table), `scripts/MeleeHandler.gd`, `scripts/enemies/EnemyAttackPool.gd`.

**Dependency:** none — assets land later via `tools/render_sfx.py` per `design/SFX_LIBRARY.md`.

### Spin-Parry perk

The sword skill tree's signature mid-tier perk (per the May 2026 design conversation).

**Scope:**
- `assets/skills/perks/sword/spin_parry.tres` (PerkData schema) + `scripts/skills/perks/sword/spin_parry.gd` (extends `Perk`, overrides `on_parry`).
- Effect: on successful parry, fire a 360° arc parry that staggers every enemy in `swing_cone_meters` radius. 25 EP cost.
- Hooks `SkillManager.dispatch("on_parry", ctx)` which MeleeHandler already calls on successful parry.

**Files:** the two new perk files above. PerkRegistry auto-discovers them on autoload.

**Dependency:** Sword skill in `SkillManager.SKILLS` (already there).

### Settings UI: Auto-Block + Direction Input Mode + Smooth Camera Transitions

Currently `auto_block` is a runtime flag on `MeleeHandler` toggled by the `B` debug key. Production needs a player-facing option.

**Scope:**
- Add to `scripts/Settings.gd`: `auto_block: bool` (off), `direction_input_mode: int` (0=mouse, 1=WASD modifier), `smooth_camera_transitions: bool` (on by default — affects future camera transitions; lock-on transitions are gone).
- Persist to `user://settings.json` via existing save/load path.
- Settings menu UI gets three new rows. Manual `_input` dispatch per CLAUDE.md.
- WASD modifier mode (deferred from v1): WASD held + LMB tap = direction-modified attack instead of mouse-flick. Wire into `MouseDirectionSampler` as an alternate input path.

**Files:** `scripts/Settings.gd` (state + persistence), `scenes/ui/Settings.tscn` (UI), `scripts/MeleeHandler.gd` (read setting at swing time).

---

## Spear charge mechanic + HUD ring + spear arm tilt (throwables side)

Melee charge is shipped in directional-melee v1 (FOV pinch + 2× damage on hold release). The spear / throwables side still needs its own charge work — different input handler (`ThrowableHandler`), different damage formula (velocity scales too).

### Scope
- `ThrowableHandler.gd`: replace `is_action_just_pressed("attack")` with hold tracking. Track `_charge_start_msec` on press; on release compute `hold_ms`; lerp damage 30→60 and velocity 9→16 across the 150–700 ms window.
- HUD charge ring on `HUDOverlay.gd` Layer-5 CanvasLayer. Centered radial fill, grey at 0 → `#E8873A` warm orange at full charge. Distinct from the melee FOV-pinch tell. **Manual `_input` dispatch only** per CLAUDE.md hard rule.
- Spear arm tilt: add `set_arm_charge(t)` on `Player3D.gd`. Rotates a `SpearArm` `Node3D` (placeholder; aligns to Roland's rigged `.glb` arm when Mixamo lands) up to 90° on local X.
- `CameraRig.set_charge_pinch(t)` already wired and used by melee — `ThrowableHandler` can feed the same API.

### Files
- `scripts/ThrowableHandler.gd` — input model
- `scripts/HUDOverlay.gd` — ring node + draw
- `scripts/Player3D.gd` — `set_arm_charge(t)` proxy

### Dependency
- None — independent of the melee work.

### Defer signal
- If real Game One playtests show the spear is rarely used (sword + shield is the primary loadout), defer the spear-side polish.

---

## Replace placeholder green boxes with rigged Mixamo characters

Mixamo pipeline already validated on Goblin (`design/ASSET_PIPELINE_AI.md` Path A). Wire the rigged `.glb`s into the gameplay scenes and replace the v1 placeholder boxes (player capsule, sword box, shield square, goblin box).

### Scope
- Swap `scenes/enemies/Goblin.tscn` Visual `MeshInstance3D` to instance the `.glb` import scene.
- Wire `AnimationPlayer` in `Goblin.gd` to the AttackPool state machine: idle in IDLE, walk in COMBAT, windup/strike/recovery animations match `EnemyAttackPool` phases per direction (overhead chop, side swing, thrust, leap), react on damage, death on `_on_died`.
- Repeat for `Player3D.tscn` once Roland's rig lands: swap Visual box, attach `MeleeWeaponPivot` + `ShieldPivot` to the right/left hand bones, replace the placeholder sword + shield meshes with proper geometry.
- Drive `MeleeHandler`'s 3-stage sword tween from `AnimationPlayer.play()` calls instead of `Tween` on the pivot transform. The state machine in MeleeHandler is animation-agnostic — see the migration TODO comment at the tween site.
- Update `Goblin.tscn` ChestSocket position to the rigged model's actual chest height (not the green-box 1.2 m).
- Update EyeGlow to attach to the head bone of the rigged skeleton, or bake emissive eye voxels into the model.

### Files
- `scenes/enemies/Goblin.tscn`, `scenes/Player3D.tscn`
- `scripts/enemies/Goblin.gd` — animation state dispatch
- `scripts/MeleeHandler.gd` — swap pose tweens for AnimationPlayer calls
- `assets/models/goblin.glb`, `assets/models/roland.glb` (Mixamo path)

### Dependency
- Goblin `.glb` exists and animates correctly in Godot preview (✓ validated).
- Roland `.glb` not yet authored — follow `design/ASSET_PIPELINE_AI.md` Path A as for Goblin.

### Defer signal
- Animation transition glitches / foot sliding can land in a polish pass after rigs are in.

---

## Second enemy type — Ashfallen v1

Validates that `Enemy3D` + the shipped `EnemyAttackPool` composition pattern extends cleanly to a different enemy archetype.

### Scope
- New `scripts/enemies/Ashfallen.gd` extending `Enemy3D`. Slower (`walk_speed_meters_per_second = 1.8`), tougher (`max_health = 120`), longer detection (`alert_range_meters = 18`), fewer attacks but heavier contact damage (`contact_damage = 18`).
- Compose a new `EnemyAttackPool` with patient, telegraphed swings per `design/ENEMY_AI.md`: 40% measured swing (green/parryable), 25% heavy blow (yellow), 20% unblockable thrust (red), 15% shield bash. Longer windups than Goblin to reward parry reads.
- New `scenes/enemies/Ashfallen.tscn` with placeholder grey-iron box (same approach as Goblin — swap to Mixamo .glb after asset pipeline run).
- No glow eyes (Ashfallen helmet is faceless per `lore/CHARACTERS_NPCS.md`); replace with a slow rust-orange emissive ring on the helmet.
- Override `_loot_corpse` to return any embedded throwables + 1× rusted blade to inventory.
- Add to CombatTest arena as a fourth enemy (or a separate `AshfallenTest.tscn`).

### Files
- `scripts/enemies/Ashfallen.gd`, `scenes/enemies/Ashfallen.tscn`
- `scenes/_dev/CombatTest.tscn` — optional second enemy slot
- `scripts/InventoryManager.gd` — register `rusted_blade` item

### Dependency
- Finishers shipped first — Ashfallen's heavier corpse benefits more from the gib treatment than the goblin does.
- Mixamo .glb optional; placeholder works for AI/balance testing.

### Defer signal
- If group AI lands first, Ashfallen integrates with attack-token system out of the gate; otherwise it ships as another solo combatant.

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

## v1.2+ — Bannerlord-style combat depth (deferred)

The directional melee v1 (PR #239, in playtest) covers the foundational Bannerlord-style loop. Designer feedback 2026-05-25 surfaced additional simulation depth Bannerlord has that v1 doesn't — collected here so it doesn't get lost while v1 settles.

### Per-weapon reach + speed
- Each weapon type (sword, axe, mace, dagger, spear) gets a `reach_meters` and `swing_speed_multiplier` in `InventoryManager.ITEM_REGISTRY`. Longer reach = catches enemies at greater distance but slower windup; faster swing = less time to read + react but less damage.
- Within a type, individual weapons vary (e.g. "iron arming sword" vs "longsword"). Bannerlord has different lengths within sword variants — same pattern here.
- Wire `MeleeHandler.swing_cone_meters` to read the equipped weapon's `reach_meters` per swing (instead of the current global `@export var swing_cone_meters`).

### Weapon-type restrictions
- Spears can only thrust (DIR_THRUST) — side swings and overheads are no-ops or play a "wrong technique" feedback. Match Bannerlord: polearms have limited swing directions.
- Daggers can't be used to block effectively (block damage reduction is poor) — encourages a parry-or-dodge playstyle on small weapons.
- Two-handed weapons disable the shield slot entirely (no offhand). Single-handed weapons + shield is the v1 baseline.
- Per-weapon `allowed_directions: Array[int]` in ITEM_REGISTRY (e.g. spear = `[DIR_THRUST]`).

### Stagger from heavy hits
- Player gets staggered (movement lockout ~0.5 s, can't attack/parry) when hit by a high-damage attack from a heavy enemy (Bear charge, Ashfallen power swing). Enemy3D's existing `stagger(duration)` already works for the inverse direction — extend the same concept to the player.
- Trigger conditions: incoming damage above a threshold (e.g. ≥ 25 dmg), or hit while at low endurance, or hit while in WINDUP without hyperarmor.
- Bannerlord's "knockback" momentum should also push the player a half-meter on big hits — physics impulse on Player3D.velocity.

### Damage simulation depth (Bannerlord parity)
Currently damage is a flat `combat_damage` or 2× charged. Bannerlord simulates several factors:
- **Weapon type + weight**: heavy weapons swing slower but deal more damage. Add `weapon_weight_kg` + `damage_curve` to ITEM_REGISTRY; final damage = base × weight_modifier × ...
- **Charge / hold duration**: longer holds increase swing momentum and damage. v1 has a binary light-vs-charged (2×); Bannerlord-style would be a continuous curve from light → fully-charged, with the curve plateauing after a full wind-up (no benefit to over-holding past the charge_full_seconds threshold).
- **Hit location**: per-hit-zone multipliers (head 2.0×, torso 1.0×, limb 0.6×). Spec lives in "Physics polish → Per-hit zones" below. MeleeHandler's `_perform_strike_check` would route through the authored hitboxes instead of its current single distance + arc test.
- **Player movement speed at swing moment**: in Bannerlord, swinging while running deals MORE damage (momentum carries through). Capture `Player3D.velocity.length()` at the strike frame and multiply damage by a small speed bonus (e.g. +20% at full sprint).
- **Character skill level**: `SkillManager.sword` level should feed back into damage — high sword skill = more damage per swing. Currently SkillManager tracks XP but doesn't influence MeleeHandler. Wire `SkillManager.get_level("sword")` into `_resolve_weapon_data` as a damage multiplier (e.g. +1% per level, capped).

Final damage formula sketch:
```
final = base × weight_mod × charge_curve × hit_zone × movement_mod × (1 + skill_level × 0.01)
```

### Enemy AI: dodge + block based on intelligence + attack obviousness
- Add `ai_intelligence: float` (0.0 dumb → 1.0 brilliant) to `EnemyAttackPool` or `Enemy3D`. Goblins ≈ 0.3, Ashfallen ≈ 0.7, Bear ≈ 0.2 (raw aggression), Wolf ≈ 0.5 (reactive).
- Track "attack obviousness": how long the player has held LMB charging from a stable direction. Longer hold + no direction-changes = more telegraphed = higher score (e.g. `obviousness = clamp(hold_seconds / 1.0, 0.0, 1.0)`).
- When the player commits a swing, every nearby enemy rolls `randf() < ai_intelligence × obviousness` to:
  - Block in the matched direction (the enemy raises a defensive pose for that windup), OR
  - Dodge sideways (short backward/strafe impulse out of the cone).
- Hyperarmor exception: if the enemy is mid-WINDUP itself, it can't react (mirroring the player's hyperarmor flag).
- Reward subtle play: rapid direction-flicks, short hold-releases, and feinting all KEEP the obviousness score low.

### Ranged combat depth (when Bow.gd lands for Orion)

Roland is melee-only per `design/COMBAT_DESIGN_3D.md:54`, but **companions use bows** (Orion). When `Bow.gd` lands, build the simulation depth in from the start instead of retro-fitting: accuracy degraded by movement (running shots wobble), firing arc + bullet drop on long shots, high-ground advantage (arrows fly further from elevation), long-distance XP bonus for hits past N meters.

### Training Field practice area

Bannerlord has a dedicated practice arena with dummies + various weapon types. `CombatTest.tscn` already serves this purpose for developers; defer the in-game tutorial / sandbox version until an Act I slot needs it.

### Charged attacks — kept for v1, reconceptualise later

v1 keeps a binary "tap = 15 dmg, hold = 30 dmg charged" model. When the "Damage simulation depth" work lands, this should become a continuous curve (more hold = more momentum, plateaus at full wind-up). The player thinks "waiting for max impact," not "charging up." Designer call 2026-05-25 — keep the binary for v1 because it's a learnable gameplay layer.

---

## Tracking / housekeeping

- This doc replaces ad-hoc "Phase X" mentions scattered in commit messages and the asset pipeline doc. When a phase ships, move it to the "What's already shipped" section at top with a date and PR reference, then drop the old detailed section.
- Major refactors to `design/COMBAT_DESIGN_3D.md` or `design/ENEMY_AI.md` should reference this doc as the implementation-truth companion.
- If the priority order shifts (e.g. Game One narrative pushes Bear forward), reorder the section anchors and update CLAUDE.md's pointer paragraph.
