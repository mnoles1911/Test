# Multiplayer — Deferred and Wontfix

Companion to `design/MULTIPLAYER.md`. This file is the canonical
record of items considered, scoped, and **deliberately not shipped**
either as a long-term wontfix or as a deferred-but-tracked task.

The MP-0 through MP-8 core stack plus the A–F closeout series
delivered the MVP for friends-only co-op. Items below are everything
that came up during planning + implementation and was punted with a
clear reason.

Keep this file updated alongside any MP-related changes — if you
unship one of the deferred items, move it to the corresponding PR
description and prune the entry here.

---

## Deferred (tracked — likely to land in a future PR)

### Prior-session sqlite delta streaming
- **Where it shows up:** Late-join voxel state. The PR-E session log
  covers edits made WHILE the host has been in a session. Edits
  loaded from `voxel_deltas.sqlite` at world boot (i.e., a host who
  carved 10000 voxels yesterday, saved, and re-launched today) are
  not in the log.
- **Why deferred:** Requires a worker-thread sqlite reader, per-
  frame N-write throttle, and a progress UI on the joining guest.
  Each piece is tractable but together they're a meaningful
  subsystem with its own design questions (compressed payload vs.
  raw delta stream, resumability if the guest disconnects mid-replay).
- **Effect today:** A guest joining a freshly-launched session with
  no carving sees the procedural baseline (same as host). A guest
  joining a re-loaded session with pre-existing edits sees those
  edits MISSING.
- **Tracked:** known UX gap; documented in `CatchupCoordinator.gd`
  header.

### FallingVoxelCluster MultiplayerSpawner integration
- **Where it shows up:** In-flight cluster visuals on guest peers.
  The PR-C work staged the `MultiplayerSynchronizer` on the scene
  but the actual host→guest spawn broadcast still needs a
  `MultiplayerSpawner` on every world scene with explicit authority
  assignment.
- **Why deferred:** Adding MultiplayerSpawner to every world scene
  is invasive and the visual gap is small (guests see re-deposited
  terrain via MP-3's `queue_set_voxels_bulk` replication — they
  just don't see the in-flight rigid body).
- **Effect today:** Guests don't see falling clusters mid-flight;
  they see the final terrain delta when the cluster settles.

### Corpse despawn replication
- **Where it shows up:** Late-joiners who arrive after a host-side
  kill see the corpse (via PR-D's state push), but the
  `corpse_lifetime_seconds` despawn timer only runs on the host's
  authoritative instance. Guest's local corpse may persist past
  host's `queue_free`.
- **Why deferred:** Properly replicating despawn requires either
  a `MultiplayerSpawner` on enemies (same investment as the
  cluster spawner above) or a per-enemy "expire at world time T"
  field synced via MultiplayerSynchronizer.
- **Effect today:** Stale geometry on guests; no functional impact
  (corpse interaction Area3D detects on guests' own player overlap).

### Host hard-reject UI on validation failure
- **Where it shows up:** PR-A's handshake. Currently a hard reject
  (`_rpc_handshake_reject`) just logs on the guest's side and the
  session continues with default inventory. The plan calls for
  a UI message + `leave_session("rejected by host")` after a brief
  delay so the user sees the reason.
- **Why deferred:** Needs a UI hook (toast / dialog) that the
  current dev scenes don't have. Easy follow-up when MainMenu /
  main UI flow is finalized.

### Multi-character roster UI (`CharacterSelect.tscn`)
- **Where it shows up:** PR-A auto-creates a single "Wanderer"
  character per Steam ID. Players can't have multiple characters
  per account through the UI (though `CharacterStore.create_character`
  supports it via scripting).
- **Why deferred:** Needs a proper UI scene with list + create +
  delete + rename buttons. Slot for the polished MainMenu work.

### Skill / perk runtime bridge
- **Where it shows up:** `InventoryManager.save_to_character_record`
  in PR-A doesn't touch `skill_levels` or `perks` — those fields
  live on the record but no live system writes to them yet.
- **Why deferred:** The skill-progression system in
  `design/SKILLS_AND_PROGRESSION.md` isn't implemented yet. When it
  lands, it bridges into `CharacterRecord` the same way inventory
  does.

### Choices made by guest forwarded to host
- **Where it shows up:** PR-B mirrors the host's pending choices to
  guests as a grayed-out list. Guests can't make the choice — only
  host advances Dialogic.
- **Why deferred:** The narrative canon rule says Roland's choices
  are the story. Letting a guest commit to a faction on Roland's
  behalf would violate canon. May land as an opt-in dev tool for
  collaborative storytelling, but never as default play.

### Per-system sync-rate runtime tuning
- **Where it shows up:** Player sync (20Hz), enemy sync (10Hz),
  water flow (4Hz) are baked into `SceneReplicationConfig` resources
  and per-system constants. PR-F added two ProjectSettings
  (`multiplayer/ping_interval_seconds`, `edit_log_max_entries`) but
  the per-`MultiplayerSynchronizer` `replication_interval` overrides
  remain inspector-only.
- **Why deferred:** Runtime adjustment requires re-applying the
  config on every synchronizer node — doable but invasive.

---

## Wontfix (no plans to implement)

### Per-peer bandwidth stats
- **Why not:** Godot 4's MultiplayerAPI doesn't expose per-peer
  send/recv byte counters. Implementing would require wrapping
  every `rpc()` call and tallying serialized payload size — adds
  hot-path cost for a dev-menu nicety.
- **Workaround:** OS-level network monitoring (Wireshark, netstat,
  `ss`) covers the use case.

### Steam lobby visibility runtime toggle
- **Why not:** Switching lobby visibility (public ↔ friends-only ↔
  invite-only) is a Steam-specific operation outside `NetTransport`'s
  abstract surface. Adding it to the abstract layer would force
  every future backend (dedicated, ENet) to stub it.
- **Workaround:** Operator leaves and re-hosts with the desired
  visibility. Single-click operation in the existing dev menu.

### Steam voice chat
- **Why not:** Voice codec integration + Godot audio bus mixing +
  push-to-talk input handling + per-peer volume controls is a
  multi-day effort for what most players just use Discord for. The
  one-PR cost doesn't pay back the gameplay value.
- **Workaround:** Discord, Steam's own voice chat (overlay), or
  in-engine text chat (future MP-9 polish if scope allows).

### Cryptographic signing of CharacterRecord
- **Why not:** Friends-only co-op model. The user explicitly scoped
  out anti-cheat hardening at MP plan time ("no anti-cheat hardening
  required"). Cryptographic signing would defeat motivated tampering,
  but the validator's job is to prevent accidental bad data from
  breaking host's session — which doesn't need crypto.
- **Workaround:** Host can hard-reject suspicious records via the
  CharacterValidator's hooks. If a future Steam Workshop / public
  matchmaking path lands, signing comes back on the table.

### Reconnect to dropped session automatically
- **Why not:** PR-F adds a "Rejoin Last" button (manual). Automatic
  reconnect on network blip is a meaningful subsystem (retry policy,
  state-restore mid-game) that's better solved by the operator
  clicking the button than by hidden retry loops.
- **Workaround:** PR-F's "Rejoin Last Session" button.

### Cross-platform play
- **Why not:** Steam-only assumed. Adding a non-Steam build target
  (console, mobile, web) requires a different transport backend AND
  a different identity model. Out of MVP scope.

### Host migration
- **Why not:** When host disconnects, all guests are dropped. Host
  migration (electing a new host from the remaining guests + re-
  authoritying everything) is a substantial subsystem and not
  expected for friends-only co-op where host-quitting just ends
  the session.
- **Workaround:** Sessions are short; if the host needs to log off,
  they save and signal a planned end.

---

## How to read this file

- **Deferred** = tracked, has a path forward, sized as a future PR.
- **Wontfix** = considered, intentionally not planned. New evidence
  can promote a wontfix back to deferred — just open an issue with
  the rationale.

If you're scoping a new feature and want to know whether something
is already on the radar, this list is the truth. The MP plan
(`/root/.claude/plans/no-i-want-you-agile-willow.md`) is frozen at
MVP scope; this file evolves.
