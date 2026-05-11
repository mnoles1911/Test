# Multiplayer — Co-Op Architecture Spec

Game One ships as single-player. Co-op is designed in alongside it so the
authoritative-state layer doesn't have to be retrofitted later.

> Cross-references: `design/SYSTEMS_DESIGN.md` for the single-player
> systems this builds on; `CLAUDE.md` for autoload load-order rules
> that constrain where new MP autoloads slot in.

**This document supersedes the previous 2-player Dark Souls–summon design
(2026 draft). The scope is now 5–10 Steam friends sharing one world. The
old draft's narrative canon rule survives; the rest is rewritten.**

---

## Design Scope

- **Up to ~10 Steam friends per session.** Host plays Roland (canonical
  PC). Guests are nameless adventurer mercenaries — full combat / edits /
  skills / inventory, no narrative role.
- **Hosting model:** Local-host MVP. The authoritative-state layer is
  transport-agnostic, so a future headless Godot dedicated-server build
  is a drop-in replacement.
- **Transport:** GodotSteam GDExtension. Steam P2P + Steam relay
  (NAT-free), friends-only Steam lobbies, Steam invites via overlay.
  Steam voice optional (deferred to MP-8).
- **Combat sync:** client-predicted attacks, host-validated. Player
  swings locally for instant feedback; host arbitrates; guest reconciles.
- **Edit permissions:** full trust. Any connected player can carve /
  place / detonate anywhere NoEditZones don't already forbid.
- **Narrative model:** Dialogic runs on host. When host enters a
  cutscene, **guests within a configurable proximity radius are pulled
  in** (frozen + mirrored UI). Distant guests keep fighting/exploring
  freely. See Proximity Cutscene section below.
- **Persistence:** host's world (voxel deltas, weather, NPC state) saves
  on the host's machine, as today. Each guest's character (skills,
  inventory, gold, equipment) is **portable** — saved on their own
  machine, travels into any host's world.

### Out of scope for the MVP (deferred)

- NPC interaction for guests (NPCs are host-only in MVP; stubs left on
  `NPC.gd`)
- Quest progression for guests
- WaterFlowManager simulation centered on guests (host-position only)
- Anti-cheat hardening beyond character allowlist
- Dedicated server build (architecture supports it; no implementation)
- Host migration on host disconnect (session ends instead)
- `WORLD_GENERATOR_VERSION` mid-session migration (handshake rejects)
- Voice chat (deferred to MP-8)
- Cross-platform play (Steam-only assumed)

---

## Network Architecture

### Transport stack

```
GodotSteam GDExtension       (addons/godotsteam/ — see INSTALL.md)
        ↓
NetTransport (autoload)      Backend abstraction.
        ↓                    Backends: SteamP2P (MVP) | ENet (LAN dev) |
                             Dedicated (future stub).
MultiplayerManager (autoload)
        ↓                    Owns SceneTree's multiplayer_peer.
                             MP_MODE = OFFLINE | HOST | CLIENT.
Existing autoloads, made MP-aware (VoxelEditManager, GameState, etc.)
+ new: CharacterStore, ProximityCutsceneManager, WorldStateSync
```

The SceneTree's `multiplayer_peer` is assigned **once** (not a custom
MultiplayerAPI on a subtree). Autoloads declare `@rpc` methods and need
a unified routing layer. In OFFLINE mode the peer stays `null` so
`is_multiplayer_authority()` returns true everywhere — existing
single-player paths are untouched.

### Authority table

| Domain | Authority | Predicted by | Replication |
|---|---|---|---|
| Local player movement | Local peer | Local peer | MultiplayerSynchronizer @ 20Hz (pos, rot.y, anim_state, sprint/crouch/swim flags) |
| Local player HP / endurance | Host | Local (optimistic HUD) | RPC mutators + sync reconcile |
| Voxel edits (terrain + water bytes) | Host | None | Guest RPC → host → broadcast |
| Falling clusters | Host | None | MultiplayerSpawner + 15Hz sync |
| Enemies (AI + state + HP) | Host | None | MultiplayerSpawner + 10Hz sync; damage = RPC |
| ThrowableSpear | Host (final), launcher (visual) | Launcher | local visual + `request_throw` RPC + `throw_resolved` |
| Blood / hit VFX | None (visual only) | Local | Unreliable RPC |
| WorldClock + Weather | Host | None | WorldStateSync node @ 2Hz |
| GameState flags | Host | None | RPC mutators + handshake snapshot |
| NPCs | Host-only (MVP) | — | Not replicated; v2 stub on `NPC.gd` |
| Inventory contents | Per-peer local | — | Loot claim RPC → host arbitrates → grant RPC |
| Camera | Local | Local | Never syncs |

---

## Terrain Sync — VoxelEditManager-Routed

The procedural baseline is deterministic from `WORLD_GENERATOR_VERSION` +
seed, so it doesn't sync. Only edits replicate.

**API preservation:** `VoxelEditManager`'s public surface
(`queue_edit_sphere`, `queue_edit_box`, `queue_set_voxels_bulk`,
`queue_set_water_voxel/box`) stays verbatim. Every method gets an MP
gate at the top:

- OFFLINE / HOST: run the existing path. On HOST, if the edit succeeds,
  broadcast `_rpc_replicate_edit(...)` to all non-author peers; they
  mirror the write into their local terrain.
- CLIENT: send `_rpc_request_edit(...)` to host and return optimistic
  ack. No local apply — guest waits for host's broadcast to land.

NoEditZone validation stays host-side. Rejections come back via
`_rpc_edit_rejected(reason, args)` and the caller may fire Roland's
*"This place doesn't yield to me."* bark.

**Late-join chunk delta replay:** host iterates `_edited_chunks`, reads
each chunk's deltas from `voxel_deltas.sqlite` on a worker thread, and
ships them in batches of N writes per RPC to avoid frame stalls.
EditedChunkRegistry coord list goes first so the guest's terrain
streamer prioritizes those chunks.

(Compressed-blob SQLite shipment is a polish path for MP-8 if the per-
chunk replay turns out too slow on long sessions.)

**Conflict policy:** last-writer-wins, arbitrated by host. No locking.
Per-peer edit rate limit (configurable, default ~30 edits/sec/guest) is
the only griefing safety valve.

---

## Combat Sync — Predict / Validate / Reconcile

- Each peer simulates **their own** player movement + attacks locally
  for instant feedback. Host re-validates and reconciles.
- Enemy AI + state machines run **on host only.** Guests see replicated
  positions / states via `MultiplayerSpawner` + 10Hz sync nodes. Damage
  events flow as RPCs.
- `ThrowableSpear` uses a predict / reconcile pattern with an
  incrementing `throw_id`: launcher spawns a local visual-only spear,
  sends `request_throw(throw_id, start_pos, velocity)` to host, host
  re-simulates the authoritative spear, broadcasts
  `throw_resolved(launcher_peer, throw_id, outcome)` where outcome is
  `terrain_stick` / `enemy_stick` / `miss`. Launcher despawns the
  visual and adopts the authoritative one.
- `BloodVFX` gains a `play_networked(pos, dir, intensity)` helper that
  fires unreliable RPCs in addition to the local play. Pool pattern
  preserved.

Netfox was considered for parry-timing rollback and is no longer in
scope for the MVP — the predict / validate / reconcile pattern above is
sufficient at the latencies Steam relay typically delivers (<150ms RTT
between friends).

---

## Catch-Up Protocol (Late-Join)

After `handshake_accept`, host streams the following to the joining
guest (reliable, ordered):

1. **WorldStateSync snapshot** — current clock + weather (tiny).
2. **GameState flags subset** — `sync_flags_snapshot(dict)`.
3. **EditedChunkRegistry list** — `PackedInt32Array` of edited chunk
   coords. Guest's terrain stream prioritizes those.
4. **Chunk delta replay** — batched writes per chunk, worker-threaded
   reader on host.
5. **Alive enemies** — `{id, scene_path, pos, rot, hp, state}` per
   enemy. MultiplayerSpawner then populates them on the guest.
6. **Active falling clusters + in-flight throwables** — same shape.
7. **Other peers' player records** — `sync_player_full(state)` per
   already-connected peer.
8. **`handshake_ready`** — release the guest into normal play.

---

## Proximity Cutscene Mechanics

Dialogic runs only on the host's machine. The new
`ProximityCutsceneManager` autoload (registered after Dialogic) decides
which guests get pulled into a triggered cutscene:

- On `Dialogic.timeline_started`, capture the trigger's
  `global_position`.
- Find guests within `cutscene_pull_radius` (exported on
  `DialogueTrigger3D`, default 20m; `0` = host-only, `-1` = all guests
  regardless).
- Send `cutscene_begin(timeline_id, origin, radius)` to in-radius
  guests; mirror each new line via `cutscene_text(speaker, line,
  portrait_path)`; mirror choices via `cutscene_choices(opts)` (grayed
  out — only host can advance).
- In-radius guest: input blocked, velocity zeroed, `is_in_cutscene =
  true`, `scenes/ui/CutsceneMirror.tscn` overlay shown.
- Camera stays free by default; per-trigger flag `mirror_host_camera`
  opts into syncing the host's camera transform at 30Hz.
- Membership re-evaluated every 0.5s. Wander-in = 1-frame freeze + UI
  fade-in. Wander-out = exit cutscene mode; host's timeline continues
  regardless.
- **Save lockout:** host cannot save while a cutscene is active.

Out-of-radius guests get **nothing** — no UI, no freeze, no
notification. They keep fighting / exploring / mining on the host's
shared world.

---

## Portable Character Format

Each guest's character is saved on their own machine, not the host's:

```
user://characters/{steam_id_decimal}.tres   (CharacterRecord Resource)
schema_version, steam_id, character_id (uuid), display_name,
created_unix, last_played_unix, appearance{}, skill_levels{},
perks[], inventory_items[], equipped{}, gold, play_time_seconds
```

**Save triggers:** clean disconnect, host save (each connected guest
gets a `request_character_save` RPC and saves locally), graceful quit,
60s in-session autosave.

**Host validation on join** (`CharacterStore.validate_for_host`):
schema version supported; all item IDs exist in the host's item
registry; no `unique_to_main_character` items; no quest-tagged items
unless host's policy whitelists them; inventory ≤ 200 stacks; skill
levels ≤ 100. Returns `{ok, reason, sanitized}` — host may
sanitize-and-warn or hard-reject.

---

## Narrative Canon Rule (preserved)

**Roland's choices are the story.** Co-op is a shared experience of
Roland's narrative, not a split campaign. Guests fight alongside Roland,
mine and build, manage their own equipment, and accrue their own
skills — but quest outcomes, faction commitments, and the flag file
belong to Player 1.

Same convention as Dark Souls / Elden Ring summon co-op: the
summoner's world is the canonical world. The trilogy's cross-game
persistence carries forward only the host's flags.

---

## Implementation Milestones

The full plan, ordered MP-0 through MP-8, lives in the approved plan
file:

`/root/.claude/plans/no-i-want-you-agile-willow.md`

Summary of phasing:

| # | Goal | Complexity |
|---|---|---|
| MP-0 | Plugin install + Hello Steam (this milestone) | S |
| MP-1 | Transport abstraction + connection lifecycle | M |
| MP-2 | Player presence + chat | M |
| MP-3 | Voxel edit replication | L |
| MP-4 | Combat replication | L |
| MP-5 | Catch-up / late-join | L |
| MP-6 | Portable character save/load | M |
| MP-7 | Proximity cutscene system | M |
| MP-8 | Polish + dev menu (kick, ping, optional voice) | M |

---

## What Not to Do

- **Do not bypass `VoxelEditManager`.** Even in MP-aware paths, every
  voxel write goes through `queue_edit_*` so the same NoEditZone gate,
  EditedChunkRegistry, async queue, and gravity-flood-fill subscriber
  fire on host. Direct `VoxelTool.do_*` calls desync the registry and
  break gravity (see CLAUDE.md "Critical GDScript patterns").
- **Do not transmit the mesh-bake cache.** Regeneratable from deltas;
  transmitting it is pure waste.
- **Do not let the guest write to `voxel_deltas.sqlite`.** Only the
  host persists. Guests' local terrain is in-memory only.
- **Do not give the guest write access to GameState flags.** All
  mutations RPC to host.
- **Do not build a parallel `NetworkedEditManager` alongside the
  existing `VoxelEditManager`.** Extend the existing public methods
  with an MP gate at the top. One queue, one authority, one
  EditedChunkRegistry.
- **Do not assume `Button.pressed` will fire in MP UI scenes.** Per
  CLAUDE.md, manual `_input` click dispatch is non-negotiable. The
  HelloSteam dev scene follows the pattern from the first commit.
- **Do not couple to Steam at gameplay-script call sites.** Everything
  Steam-specific lives behind `NetTransport`. Gameplay calls
  `MultiplayerManager.is_host()` / `is_offline()` / `local_peer_id()`
  and never imports `Steam.*`.
