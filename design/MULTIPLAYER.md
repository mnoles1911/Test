# Multiplayer — Co-Op Architecture Spec

Game One ships as single-player. Co-op support (2-player, same-session) is designed in from the start so the architecture does not need to be rebuilt later.

> This document covers the co-op technical architecture. Narrative canon rules are at the bottom.
> Cross-reference: `design/SYSTEMS_DESIGN.md` for single-player systems these build on.

---

## Design Scope

- **2 players maximum** — host (Player 1 = Roland) and one guest (Player 2 = Orion, after he joins in Act II)
- **Client-server model** — host's machine is the server (peer_id = 1); guest connects as client
- **Single-player first** — all systems are built for single-player; co-op is layered on top via `@rpc` annotations and `MultiplayerSpawner` / `MultiplayerSynchronizer`
- **Not shipped in Act I** — co-op is enabled once Orion joins (Phase 10-3D / Caer Brannoch arc)
- **LAN + Steam Remote Play** for initial release; dedicated server not planned

---

## Network Architecture

### Transport Layer

Godot 4's built-in `ENetMultiplayerPeer` (UDP, reliable/unreliable channels).

```gdscript
# Host:
var peer = ENetMultiplayerPeer.new()
peer.create_server(PORT, MAX_CLIENTS)  # MAX_CLIENTS = 1
multiplayer.multiplayer_peer = peer

# Guest:
var peer = ENetMultiplayerPeer.new()
peer.connect_to_host(HOST_IP, PORT)
multiplayer.multiplayer_peer = peer
```

No third-party netcode library for movement sync — Godot's built-in `MultiplayerSynchronizer` handles player position and animation state. **Netfox** (GDScript, MIT license) is used for combat rollback netcode only (parry timing, hit detection).

### Authority Model

- `peer_id = 1` (host) = authoritative server
- Guest has input authority over their character node only
- All game state (flags, quest progress, inventory, NPC disposition) lives on host — guest reads it, never writes directly
- `@rpc("any_peer", "call_local")` for guest actions that affect shared state; host validates and applies

---

## Terrain Sync (Free — No Work Needed)

`VoxelLodTerrain` with `VoxelGeneratorGraph` generates terrain **deterministically** from the same parameters on every client. Both players generate the same terrain independently. Nothing to sync.

Each player gets their own `VoxelViewer` node — the terrain streaming system uses `STREAMING_SYSTEM_CLIPBOX` mode, which supports multiple viewers. Terrain around both players streams simultaneously.

```
World3D (Node3D)
├── VoxelLodTerrain
│   └── VoxelGeneratorGraph
├── VoxelViewer_P1    ← follows Player 1 (Roland)
├── VoxelViewer_P2    ← follows Player 2 (Orion) — added when guest connects
├── Player3D (Roland)
├── Orion (CharacterBody3D — Player 2's node)
└── EntityStreamer
```

---

## Entity Sync

### Player Positions

Use `MultiplayerSynchronizer` on each player node — syncs `global_position`, `rotation.y`, and current animation state at a fixed tick rate (~20 Hz is sufficient for cooperative play).

```gdscript
# On Player3D / Orion nodes — configured in scene inspector:
# MultiplayerSynchronizer → replication properties:
#   - global_position
#   - rotation
#   - _animation_state (String)
```

Input stays local — each player processes their own inputs. Positions are broadcast.

### NPCs and Enemies

Host is authoritative. NPC positions, states, and AI decisions run on host only. Guest sees replicated results via `MultiplayerSynchronizer` on each NPC node. Enemy HP changes, death, and loot are all applied on host → replicated to guest.

### EntityStreamer

Both VoxelViewers contribute to the load radius. If either player is within load distance of an entity, it loads. The host's `EntityStreamer` makes all instantiation decisions.

---

## Combat Sync — Netfox for Rollback

Basic attacks and movement are lag-tolerant (visual desync of <100ms is acceptable). Parry timing windows are not — a missed parry due to latency feels wrong.

**Netfox** (https://github.com/foxssake/netfox, GDScript, MIT) provides:
- Rollback netcode for inputs — client predicts, host confirms, client corrects
- Input buffering for parry/dodge windows
- Interpolation for smooth visual sync between ticks

Netfox is added only when co-op is enabled (Phase 10-3D). It is not needed for single-player.

---

## Save System in Co-Op

**Host's save is canonical.** The guest's progress is not saved independently.

- When a co-op session ends, host's GameState (flags, quest progress, inventory, faction states) is the save that persists
- Guest's character (Orion's HP, equipment changes made during session) syncs back to host's save at session end
- Guest does not get a separate save slot; they are playing in the host's game

**Rationale:** The game's cross-game persistence (Game One flags → Game Two) requires one authoritative flag file. Two players diverging on flags is undefined behavior. The host is Roland's player — Roland's choices are what the trilogy carries forward.

---

## Dialogue in Co-Op

Dialogic timelines run on host. Guest sees the dialogue UI (replicated CanvasLayer). Guest cannot advance dialogue or make choices — only Roland's player makes narrative decisions. Guest can open their journal or inventory during the host's dialogue.

**Companion barks during dialogue:** Orion's in-dialogue comments (short portrait interjections) are still authored and shown — they appear on both screens simultaneously since they are triggered by host timeline events.

---

## Narrative Canon Rule

**Roland's choices are the story.** Co-op is a shared experience of Roland's narrative, not a split campaign. Orion can fight alongside Roland, open chests, and manage his own equipment — but the quest outcomes, faction commitments, and flag file belong to Player 1.

This is the same convention as Dark Souls / Elden Ring summon co-op: the summoner's world is the canonical world.

---

## What Not to Do

- **Do not sync voxel data** — terrain is deterministic; syncing it doubles bandwidth for zero benefit
- **Do not give guest write access to GameState** — all flag changes go through host via `@rpc`
- **Do not build co-op into Phase 5–9 systems** — keep single-player path clean; add the `@rpc` layer in Phase 10-3D when Orion's join scene is built
- **Do not use a dedicated relay server** — ENet direct connect + Steam Remote Play covers the audience; dedicated infra adds cost and complexity with no benefit at this scale
