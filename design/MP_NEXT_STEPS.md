# Multiplayer — Next Steps

> Roadmap for MP-4..MP-8 on top of the MP-1 / MP-2 / MP-3 foundation in PR #180. See `design/MULTIPLAYER.md` for what's already live.

## Status snapshot (2026-05-12)

| Milestone | Status | PR | Acceptance |
|---|---|---|---|
| MP-0 | ✅ Merged | #179 | GodotSteam plugin scaffolding + HelloSteam scene |
| MP-1 | ✅ Draft | #180 | Two ENet instances connect on 127.0.0.1 |
| MP-2 | ✅ Draft | #180 | Two-peer walking demo (RemotePlayer + PlayerSpawner) |
| MP-3 | ✅ Draft | #180 | Voxel edit dispatch round-trip in MP2Test |
| MP-4 | Next | — | Combat replication (Enemy3D + ThrowableSpear + clusters) |
| MP-5 | Pending | — | Catch-up snapshot for late-join |
| MP-6 | Pending | — | Portable character (CharacterRecord per Steam ID) |
| MP-7 | Pending | — | Proximity cutscene system |
| MP-8 | Pending | — | Polish + dev menu (kick, ping, bandwidth) |

---

## MP-4 — Combat replication

**Goal:** two peers fight three goblins together. Hits register on both sides; kills, blood, corpse-lay, and spear-stick all visible to both peers.

**Files to create:**
- `scripts/net/EnemySpawner.gd` + scene — MultiplayerSpawner whitelisted to `scenes/enemies/Goblin.tscn` (and future enemy types). Host instantiates; guests receive via spawner.
- `scripts/net/ThrowableNet.gd` (autoload) — owns the predict/reconcile path for thrown items. Issues `throw_id` per local throw, awaits `throw_resolved` from host with the authoritative outcome (`terrain_stick` / `enemy_stick` / `miss`).
- `scripts/net/FallingClusterNet.gd` (autoload) — spawns FallingVoxelCluster on host, replicates pos/vel/ang_vel/is_sleeping at 15 Hz to guests.

**Files to modify:**
- `scripts/Enemy3D.gd` — gate the IDLE / ALERT / COMBAT state machine with `if MultiplayerManager.is_host()`. Add `MultiplayerSynchronizer` child @ 10 Hz replicating `health`, `state`, `position`, `rotation`. Damage events become RPCs (`@rpc("any_peer", "call_remote", "reliable")` `_rpc_apply_damage`). `take_damage()` becomes the local visual path; it's invoked on guests via `_rpc_apply_damage_visual`.
- `scripts/enemies/Goblin.gd` — host-only AI calls; visual reactions (eye glow, lay-on-death) replicated via the synchronizer's state field.
- `scripts/throwables/ThrowableSpear.gd` — launcher spawns local visual-only spear immediately; sends `request_throw(throw_id, origin, dir, charge)` RPC to host; host re-simulates with deterministic physics-step and broadcasts `throw_resolved(throw_id, outcome, hit_point, target_id)`. Guest reconciles by snapping the local spear to the resolved outcome.
- `scripts/VoxelGravityManager.gd` — host-only listener on `VoxelEditManager.edit_applied`; clusters spawn via `FallingClusterNet`.
- `scripts/FallingVoxelCluster.gd` — `MultiplayerSynchronizer` child @ 15 Hz (pos, vel, ang_vel, is_sleeping). Damage-on-impact calls become RPCs.
- `scripts/BloodVFX.gd` — add `play_networked(layer, pos, dir, intensity)` helper using `@rpc("authority", "call_remote", "unreliable")`. Local play stays the same; the network broadcast is fire-and-forget.
- `scripts/skills/CombatXPRouter.gd` — currently listens to local Enemy3D signals; once Enemy3D becomes host-only, the router needs to also receive guest hit/kill events. Likely solution: host's CombatXPRouter dispatches `xp_credit(peer_id, skill, amount)` RPCs to the right guest, who applies via SkillManager. (Cross-references the skill PR #201.)

**Acceptance:**
- Two peers fight three goblins in a CombatTest-equivalent multiplayer scene. Both see hits, blood VFX, corpse-lay, and spear-stick on both sides. Kill credit attributes correctly per attacker.

**Estimated complexity:** L (ThrowableSpear predict/reconcile alone is 200+ lines).

---

## MP-5 — Catch-up / late-join

**Goal:** solo host plays for 10 minutes (carving terrain, killing enemies); a guest joins and sees the full world state within ~5 s.

**Files to create:**
- `scripts/net/CatchupCoordinator.gd` (autoload) — host-side payload builder, guest-side receiver + apply order.

**Catch-up payload (sent reliable + ordered after handshake):**
1. **WorldStateSync snapshot** — clock, weather, fog state. Tiny.
2. **GameState flags subset** — `sync_flags_snapshot(dict)`.
3. **EditedChunkRegistry list** — `PackedInt32Array` of edited chunk coords. Guest's terrain prioritizes those.
4. **Chunk delta replay** — host iterates `_edited_chunks`, reads each chunk's deltas from `voxel_deltas.sqlite` on a worker thread, ships in batches of N writes per RPC. May compress to a sqlite blob in MP-8 polish.
5. **Alive enemies** — `{id, scene_path, pos, rot, hp, state}` per enemy.
6. **Active clusters + active throwables** — same shape.
7. **Other peers' player records** — `sync_player_full(state)` per existing peer.
8. **`handshake_ready`** — release the guest into the world.

**Files to modify:**
- `scripts/VoxelEditManager.gd` — add `build_catchup_payload() -> PackedByteArray` (reads sqlite deltas, packs into a payload).
- `scripts/WeatherManager.gd` — add `get_snapshot()` / `apply_snapshot(dict)`.
- `scripts/WorldClock.gd` — add `get_snapshot()` / `apply_snapshot(dict)`.
- `scripts/GameState.gd` — flag mutators reroute through `set_flag_replicated(key, value)` RPC on client; host has `sync_flags_snapshot(dict)` handshake RPC. `player_position` moves out of GameState into per-peer record.

**Acceptance:**
- Solo host for 10 min with 50+ chunk edits + 3 alive goblins + 1 in-flight cluster. Guest joins, sees identical state ≤ 5 s.

**Estimated complexity:** L (chunk delta replay + worker thread is the meat).

---

## MP-6 — Portable character (CharacterRecord)

**Goal:** each guest's character (skills, perks, inventory, gold, equipment, faction dispositions) saves per Steam ID at `user://characters/{steam_id}.tres` and travels into any host's world.

**Files to create:**
- `scripts/net/CharacterRecord.gd` — Resource subclass. Schema_version, character_id (uuid), steam_id, display_name, appearance, **skill_levels**, **skill_xp_progress**, **perks**, **perk_points_unspent**, **legendary_resets**, **faction_dispositions**, **trainer_visits**, inventory_items, equipped, gold, play_time_seconds, last_played_unix.
- `scripts/net/CharacterStore.gd` (autoload) — load/save `user://characters/{steam_id}.tres`. Load triggers: clean disconnect, host save, graceful quit, 60-s autosave during session.
- `scripts/net/CharacterValidator.gd` — host-side allowlist on join: schema version supported; all item IDs exist in registry; no `unique_to_main_character` items; no quest-tagged items unless host whitelists; inventory ≤ 200 stacks; skills ≤ 100 each; perks ⊆ PerkRegistry. Returns `{ok, reason, sanitized}`.
- `scenes/ui/CharacterSelect.tscn` — pick character before hosting/joining.

**Files to modify:**
- `scripts/GameState.gd` — flat-skill state (currently `_skill_levels`, `_skill_xp_progress`, `_owned_perks`, `_perk_points_unspent`, `_legendary_resets`, `_faction_dispositions`, `_trainer_visits`) **migrates to CharacterRecord**. GameState retains world-mutable flags (quest flags, world events) but drops per-character state.
- `scripts/skills/SkillManager.gd` — internal storage swaps from GameState dictionaries to `CharacterStore.local_record`. Public API unchanged.
- `scripts/InventoryManager.gd` — load from CharacterRecord on session start, write back on save triggers. Pickup `claim_pickup(id)` RPC + host `grant_item` RPC to arbitrate concurrent loot grabs.
- `scripts/MainMenu.gd` — add "Character" option that opens CharacterSelect before scene load.

**Important:** the skill PR #201 currently puts skill state on GameState as a transitional measure. MP-6 is what migrates it onto CharacterRecord. The SkillManager API doesn't change; only the backing store does.

**Acceptance:**
- Character "Aelric" with sword + 100 gold + Sword L42 + 8 picked perks travels between two different hosts. A tampered .tres with non-registry legendary item gets rejected with a clear error.

**Estimated complexity:** M (the schema + migration is mostly straightforward).

---

## MP-7 — Proximity cutscene

**Goal:** host's Dialogic timeline pulls in nearby guests (within configurable radius) and freezes them in a mirrored UI; distant guests keep playing freely.

**Files to create:**
- `scripts/net/ProximityCutsceneManager.gd` (autoload, after Dialogic).
- `scenes/ui/CutsceneMirror.tscn` — read-only Dialogic mirror UI shown to in-radius guests.

**Files to modify:**
- `scripts/DialogueTrigger3D.gd` — export `cutscene_pull_radius: float = 20.0` (0 = host-only, -1 = all guests regardless of distance).
- `scripts/PauseMenu.gd` (or `scripts/SaveSlotPicker.gd`) — disable Save while a cutscene is active.

**Behavior:**
- On host's `Dialogic.timeline_started`: capture `global_position` at trigger; find guests within `cutscene_pull_radius`; send `cutscene_begin(timeline_id, origin, radius)` to in-radius guests.
- For every line: mirror `cutscene_text(speaker, line, portrait)`; for choices: `cutscene_choices(opts)` (grayed — host advances).
- In-radius guest: input blocked, velocity zeroed, `is_in_cutscene = true`, `CutsceneMirror.tscn` overlay. Camera stays free by default (per-trigger `mirror_host_camera` flag opts in to host camera sync at 30 Hz).
- Re-evaluate membership every 0.5 s. Wander-in = 1-frame freeze + UI fade-in. Wander-out = exit cutscene mode; host's timeline continues regardless.

**Acceptance:**
- Host triggers dialogue with guest A adjacent + guest B 100 m away. A is frozen + mirrored; B keeps fighting. A walks out → unfreezes; host's timeline continues. Save button locked during cutscene.

**Estimated complexity:** M.

---

## MP-8 — Polish + dev menu

**Goal:** operator tools for shipping. 4-peer 30-minute session is stable.

**Files to create:**
- `scripts/net/MPDevMenu.gd` + `scenes/ui/MPDevMenu.tscn` — kick a peer, toggle lobby visibility, ping each peer, bandwidth in/out, peer rate-limit window, edit queue depth.

**Optional polish:**
- Compressed sqlite-blob catch-up payload (replaces per-chunk RPC stream from MP-5).
- Reconnect-after-host-crash hint UI.
- Voice chat (Steam voice codec + Godot audio bus) — opt-in flag, deferred from MVP.

**Acceptance:**
- 4-peer 30-min session; dev menu accurate; kick + reconnect works.

**Estimated complexity:** M.

---

## Cross-cutting risks (carried from approved plan)

1. **Zylann VoxelTool thread safety under host edits + guest streaming.** VEM's existing async queue is the sole serialization point; MP-3's per-peer rate limit (60 req/s) prevents flood. Re-stress at MP-4 with 5 peers chain-detonating.
2. **RigidBody3D cluster determinism.** Physics is non-deterministic across machines. MP-4 must keep host authoritative; guests interpolate. Tween smoothing on snap to re-deposit position.
3. **`WORLD_GENERATOR_VERSION` mismatch.** Handshake will reject mid-MP-4 with a clear error. Migration is out of scope.
4. **Host save flush stalls.** SQLite flush can hit hundreds of ms. MP-5+ should flush on a worker thread; coalesce; send guests `host_saving` hint for UI indicator.
5. **Voice chat scope creep.** Defer to MP-8 as opt-in flag; promote earlier only if user requests.
6. **10-peer local testing impractical.** Use ENet backend with headless instances for stress; Steam for 2–3 peer integration smoke.
7. **Input gating regressions.** Every new input read in Player3D / EditToolHandler / ThrowableHandler must go through `_can_take_input()`. Code review during each MP milestone.
8. **MultiplayerSpawner whitelist drift.** When MP-4 introduces `EnemySpawner`, enforce a single `EnemyFactory` autoload as the only enemy spawn path so future Enemy3D subclasses replicate automatically.

---

## Recommended order

1. **MP-4** (combat) — most player-visible. Unlocks "fight together" demo.
2. **MP-6** (CharacterRecord) before MP-5 — easier to test catch-up when guests carry persistent characters.
3. **MP-5** (catch-up) — wait until MP-4 + MP-6 land so the snapshot has meaningful payload.
4. **MP-7** (proximity cutscene) — narrative-blocker for any quest playtest.
5. **MP-8** (polish) — at the end, after the queue stabilizes.

Alternative: if narrative testing matters more than combat fidelity, swap MP-4 ↔ MP-7. The transport / presence / edit / character layers all work without combat.
