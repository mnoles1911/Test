# Multiplayer Design

> **Status (as of MP-3, 2026-05-12):** MP-1 / MP-2 / MP-3 landed on PR #180 (`claude/init-project-setup-rKAHS` → `main`, draft). MP-4..MP-8 outlined in `design/MP_NEXT_STEPS.md`.

## Goal

Up to ~10 Steam friends in a single shared world. MVP delivers walk + voxel edits + combat in co-op. **Single-player remains the canonical experience** — every MP-aware system collapses cleanly when no session is active (`MultiplayerManager.is_offline()` returns true → `is_host()` returns true → existing single-player paths run unchanged).

## Architecture

```
GodotSteam GDExtension (addons/godotsteam/, Steam.gd singleton)
        ↓
NetTransport (autoload)            ← swappable backend: ENet | Steam P2P | future Dedicated
        ↓
MultiplayerManager (autoload)      ← owns SceneTree.multiplayer_peer; OFFLINE/HOST/CLIENT mode
        ↓
Existing autoloads, MP-aware where needed:
        VoxelEditManager           (MP-3: 3 RPCs, host validates + broadcasts)
        WaterFlowManager           (MP-3: host-only physics)
        Player3D                   (MP-2: _can_take_input gate, runtime MPSync child)
        RemotePlayer + PlayerSpawner (MP-2: per-peer presence)
```

### Authority table (MP-3 baseline)

| Domain | Authority | Predicted by | Replication |
|---|---|---|---|
| Local player movement | Local peer | Local peer | MultiplayerSynchronizer @ 20 Hz (pos, rot.y, sprint/crouch flags) |
| Voxel edits (terrain + water) | Host | None | Guest RPC → host → broadcast (`_rpc_replicate_edit`) |
| Water flow simulation | Host (sole simulator) | — | Per-cell byte changes via VoxelEditManager replication |
| WorldClock + Weather | Host | None | Not yet replicated (MP-5 / MP-7) |
| GameState flags | Host | None | Not yet replicated (MP-5 catch-up) |
| Enemies (AI + state + HP) | — | — | Not yet replicated (MP-4) |
| Throwables | — | — | Not yet replicated (MP-4) |
| Camera | Local | Local | Never syncs |
| Inventory | Per-peer local | — | Loot claim RPC pending (MP-4 / MP-6) |

## What's live (MP-1 → MP-3)

### MP-1 — Transport + session lifecycle

- `scripts/net/NetTransport.gd` (autoload) — picks backend at startup from `multiplayer/backend` project setting (`"enet"` | `"steam"`). Re-broadcasts the active backend's signals.
- `scripts/net/NetBackend.gd` (abstract RefCounted) — `start_host(max_peers)`, `join(addr)`, `disconnect()`, `get_peer_ids()`. Async kickoff via `session_ready` / `session_failed` signals.
- `scripts/net/backends/ENetBackend.gd` — `ENetMultiplayerPeer`, default port 7777. Sync but emits `session_ready` via `call_deferred`.
- `scripts/net/backends/SteamP2PBackend.gd` — wraps `SteamMultiplayerPeer`. Defensive: parses without GodotSteam, `is_available()` returns false until plugin installed.
- `scripts/net/MultiplayerManager.gd` (autoload) — owns `multiplayer.multiplayer_peer`, `MP_MODE { OFFLINE, HOST, CLIENT }`, LIFECYCLE state machine, `peers: Dictionary`. Public predicates `is_offline()` / `is_host()` / `is_client()` / `local_peer_id()`. Public methods `host_session(max_peers)` / `join_session(addr)` / `leave_session()`. Signals `session_started` / `session_ended` / `session_failed` / `peer_joined` / `peer_left` / `lifecycle_changed`.

**OFFLINE-is-host policy.** When no session is active, `is_host()` returns true and `local_peer_id()` returns 1. Existing single-player code that asks "am I authoritative?" continues to return true.

**Acceptance:** `scenes/_dev/NetTest.tscn` — two ENet instances on `127.0.0.1` show each other in the peer list.

### MP-2 — Player presence

- `scripts/net/RemotePlayer.gd` + `scenes/player/RemotePlayer.tscn` — lightweight CharacterBody3D for another peer. No camera, no input, no XP routers. Runtime-built `MultiplayerSynchronizer` @ 20 Hz replicates `position`, `rotation.y`, `is_sprinting`, `is_crouching`. Joins both `remote_player` and `player` groups (existing range checks scan `player`).
- `scripts/net/PlayerSpawner.gd` — listens to `MultiplayerManager.peer_joined / peer_left` (with fallback to raw `peer_connected / peer_disconnected`) and parents one RemotePlayer per non-local peer. `set_multiplayer_authority(peer_id)` before `add_child` so the synchronizer accepts replication from the right source. On startup walks `MultiplayerManager.peers` to catch up mid-session.
- `scripts/Player3D.gd` — `_can_take_input()` helper returns `MultiplayerManager.is_offline() OR get_multiplayer_authority() == multiplayer.get_unique_id()`. Every `Input.*` read in the script gates through it. `set_multiplayer_authority(local_peer_id)` set in `_ready()`. Runtime-built `MPSync` child replicates the same fields RemotePlayer needs.

**Acceptance:** `scenes/_dev/MP2Test.tscn` — two-peer walking on a flat 40 m × 40 m floor.

### MP-3 — Voxel edit replication

- `scripts/VoxelEditManager.gd` — additive MP routing layer at the bottom of the file (`_mp_*` helpers + 3 RPCs) plus thin gates inserted into each public `queue_*` function:
  - **Top of each public function:** `if _mp_is_client(): _mp_send_request_to_host({type, ...args}); return true` (optimistic ack).
  - **Bottom of each public function:** `if _mp_is_host_with_peers(): _mp_broadcast_replica({type, ...args})`.
- **Three RPCs:**
  - `@rpc("any_peer", "call_remote", "reliable")` `_rpc_request_edit(cmd: Dictionary)` — guest → host. Host re-runs the same public `queue_*` path; on rejection it `rpc_id(sender, _rpc_edit_rejected, world_pos)`.
  - `@rpc("authority", "call_remote", "reliable")` `_rpc_replicate_edit(cmd: Dictionary)` — host → guests. `_mp_apply_replica` enqueues with NoEditZone bypass.
  - `@rpc("authority", "call_remote", "reliable")` `_rpc_edit_rejected(world_pos: Vector3)` — host → originating guest. Surfaces as the existing `edit_rejected_no_edit_zone` signal so Roland's "doesn't yield" bark fires client-side too.
- **Per-peer rate limit:** sliding 1-s window, 60 req/s cap on `_rpc_request_edit`. A misbehaving client tool can't flood the host queue.
- **All seven edit verbs covered:** `sphere`, `box`, `box_voxels`, `set`, `water_set`, `water_box`, `bulk`.
- `scripts/WaterFlowManager.gd` — `_physics_process` early-returns if not host. Per-cell water byte changes ride the same VoxelEditManager replication path.

**Acceptance:** `scenes/_dev/MP2Test.tscn` "Carve hole at me" button — issues a 1.5 m sphere edit at the local player's feet via `VoxelEditManager.queue_edit_sphere`. Status panel in BOTH windows updates to `APPLIED @ (x, y, z)` within ~50 ms (LAN), proving the dispatch round-trip works in both directions.

## Known gaps + risks

1. **Visual carve test in dev scene is dispatch-only.** `MP2Test.tscn` has a flat StaticBody3D floor, not a `VoxelLodTerrain`. The acceptance is the RPC round-trip (status label flip), not visual carving. Visual two-peer carving needs `World3D.tscn` once a multiplayer entry point lands there.
2. **Chunk-hash desync detector deferred.** Plan calls for a 5-s diagnostic that hashes visible chunk contents on host vs guest. Lands separately when there's MP entry on World3D.
3. **`WORLD_GENERATOR_VERSION` mismatch** — guest with a different version still connects but their replicated edits land on the wrong terrain. Out of MVP scope; documented risk.
4. **Inventory + skills + flags** — not yet replicated. Skill state currently lives on `GameState` (per the parallel skill PR #201); MP-6 (CharacterRecord) will own per-character state including skills/perks/inventory.
5. **NPC interaction ambiguity** — `RemotePlayer` joins both `remote_player` and `player` groups so existing range checks (BarkArea, InteractArea) keep working. Once interactive NPCs become MP-aware (likely MP-4 prep), filter `remote_player` out of those gates.
6. **Falling clusters** — VoxelGravityManager spawns `FallingVoxelCluster` instances that run RigidBody3D physics. Not yet host-gated; MP-4 work.
7. **GodotSteam dormant** — Steam P2P backend parses without the plugin but `is_available()` returns false. Steam path acceptance lands once the plugin is vendored.

## Design philosophy

- **Single-player is canonical.** Every MP system either collapses to a no-op when `is_offline()` OR reads MP state lazily so the OFFLINE path never instantiates a synchronizer / RPC / authority check.
- **Host is authority.** No client-side prediction beyond optimistic ack on voxel edits. MP-4 will introduce predict-and-reconcile for fast-feel attacks but the host always arbitrates.
- **API stability over MP cleverness.** Every public function on `VoxelEditManager` keeps its pre-MP signature. The MP layer lives at the top + bottom of each function in a small wrapper. Same will apply to combat (MP-4) and inventory (MP-6).
- **Reliable channel for everything that mutates world state.** Movement/rotation are unreliable-OK; voxel edits, kills, loot grants, and dialogue triggers are reliable.

## Cross-references

- `design/MP_NEXT_STEPS.md` — MP-4..MP-8 roadmap (combat, catch-up, characters, cutscenes, polish)
- `CLAUDE.md` → "Critical GDScript patterns" — `_can_take_input()` rule, VoxelEditManager-only-route rule.
- `CLAUDE.md` → "Autoload registration status" — load-order rules for NetTransport / MultiplayerManager / WaterFlowManager.
