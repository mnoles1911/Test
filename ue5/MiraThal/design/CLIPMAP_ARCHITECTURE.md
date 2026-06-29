# Clipmap Architecture — how near and far terrain fit together

The plain-English design of how Mira-Thal shows terrain everywhere the player roams without melting
the machine. Written for the designer, not a programmer. Companions: `UE5_ROAMING_CLIPMAP.md` (the
live tier config + bake-pipeline history) and `BAKE_PIPELINE_GUIDE.md` (how to actually bake).

> **The one-sentence version:** close to the player we draw *real, editable* 10 cm voxels; far away we
> draw a cheap, pre-baked "crust" that is only the **surface skin** of the land; and we hide the seam
> where they meet by sinking the crust slightly underground so the crisp near voxels always win on top.

---

## 1. Why two kinds of terrain at all

The world is a bounded **5 km × 5 km** map, and the player **spawns at random spots and roams freely**.
So terrain detail has to follow the player *anywhere*, not just near the map centre.

Drawing the whole map as live 10 cm voxels is impossible — that's billions of cubes, far too expensive.
Drawing the whole map at full editable fidelity isn't needed either: you can't tell a mountain two
kilometres away is made of individually editable 10 cm cubes. So we split terrain into two layers that
do different jobs:

- **Near — live voxels (10 cm).** Generated on the fly in a small bubble around the player. These are
  the *real* world: you can dig and carve them. Expensive, so the bubble is small (a streaming radius of
  a few dozen metres). This is NOT Nanite — it's our own voxel mesher rebuilding chunks as you edit.

- **Far — baked Nanite "crust".** A pre-cooked, frozen mesh of the land's surface, baked once ahead of
  time (see `BAKE_PIPELINE_GUIDE.md`). It's cheap to draw at scale (Nanite handles the level-of-detail),
  but it's **frozen** — you can't dig it. Its whole job is to make the distance look right.

The word **clipmap** just means: rings of detail centred on the player that follow the player around.
Near the player = fine detail; the further out you look, the coarser the terrain, because you can't see
the fine detail at that distance anyway.

---

## 2. The crust is only a SHELL, not solid rock

This is the most important thing to understand about the baked crust, because it explains a lot of the
design decisions.

The crust is **not** a solid block of baked voxels going all the way down to bedrock. That would be
enormous and pointless — you never see the inside of a hill. Instead, the bake produces only the
**surface shell**: the visible skin of the land, plus a few voxels of downward "skirt" at the edges so
there are no cracks or gaps between neighbouring pieces. Everything below that thin shell is simply not
baked at all — it's empty.

Think of it like a papier-mâché landscape: a hard painted surface with nothing behind it. From the
outside it looks like solid terrain; there's just no interior. This is why the crust is so cheap, and
it's also why the crust can never be dug — there's nothing underneath to dig into. (Digging only happens
in the near live-voxel bubble, which *is* solid all the way down.)

---

## 3. Geo-merge: a few hundred big meshes instead of thousands of tiny ones

The bake chops the land into square **tiles** and, by default, makes one mesh per tile. At fine
resolutions that's a *lot* of tiny meshes — hundreds of thousands — and Unreal chokes on that many
separate assets (the "file wall" — see `BAKE_PIPELINE_GUIDE.md`).

**Geo-merge** (the `-GeoMerge` bake option) is the fix: it **fuses all the tiles in a region into ONE
Nanite mesh and ONE manifest entry.** Instead of thousands of tiny pieces, the whole map becomes a few
hundred big merged meshes. This collapses both the file count and the asset count dramatically (~64× in
practice).

The clever part is that the **runtime needs no changes** to handle a merged region. As far as the
streamer is concerned, a merged region is just a *bigger tile*: the bake writes the region's width into
the manifest's tile-span field (`TileSpanVoxels = RegionSize × TileSpan`), and the existing streamer
places it with the exact same maths it uses for an ordinary tile. The geometry of every fused tile lands
in precisely the spot its own per-tile placement would have put it. (The fuse maths lives in
`Source/MiraThalVoxel/Public/Core/RegionMerge.h`; the bake wiring is in
`Source/MiraThalVoxelBake/Private/VoxelCrustBaker.cpp`.)

The tradeoff is **coarser streaming** — see §5.

---

## 4. The seam: how near and far meet without fighting

Where the near live voxels and the far crust overlap, you have two pieces of terrain trying to draw at
the same spot. If they sit at exactly the same height they "z-fight" — flicker and tear — and worse, the
coarse frozen crust would poke through the crisp editable voxels and ruin the look (and visually cut
through the very cubes you can dig).

The fix is simple and robust: **sink the crust slightly below the true surface.** Each crust tier has a
`VerticalBiasVoxels` setting that pushes its whole mesh down by a few voxels. Because the near live
voxels sit at the real surface and the crust sits just underneath, wherever the two overlap the **near 10
cm voxels always render on top** and hide the crust. You only ever see the crust out beyond where the
live voxels reach. No flicker, no coarse cubes poking through.

(For the current 40 cm approach the sink is `VerticalBiasVoxels = 6`, set by `Saved/wire_40cm_crust.py`.
Finer/closer tiers need a smaller sink; coarser/farther tiers can take a bigger one.)

---

## 5. Band granularity — the tradeoff geo-merge forces

Each crust tier loads tiles whose distance from the player falls inside a **band**, measured in chunks
(1 chunk = 3.2 m): an inner edge and an outer edge. Finer tiers get a near band; coarser tiers get a far
band. The streamer is player-relative, so the bands follow the player around the map.

Geo-merge makes the bands **coarser-grained**, and this is the cost you pay for the huge asset-count
saving. Because a whole region is now a single mesh, the streamer can only load or unload terrain a
*whole region at a time*. At 40 cm a geo-merge region is about **307 m across**. That has two practical
effects:

- **You can't have a tight inner band.** If you told the tier "don't load the region the player is
  standing in," it would punch a 307 m hole right under the player's feet. So for geo-merge tiers the
  inner band is set to **0** (load the player's own region too). That's safe precisely because of the
  seam fix in §4 — the crust under the player is sunk below the surface and hidden by the live voxels, so
  you never actually see it there.

- **The band reach is set by the OUTER edge.** It's tuned to "as far as you can see" (~2.2 km for the
  current 40 cm tier) but band-limited so only the regions in the band load, not the whole map at once
  (which would cause a load-burst freeze).

So: geo-merge trades **fine-grained streaming** (loading small patches exactly where needed) for **far
fewer assets**. That's a good trade for the far crust, which doesn't need patch-level precision — but it's
the reason geo-merge is for the far tiers, never for the near editable voxels.

---

## 6. The runtime model — one mesh component per region (under review)

At runtime the crust streamer (`AVoxelNaniteCrust`, in
`Source/MiraThalVoxelBake/Private/VoxelNaniteCrust.cpp`) works like this: for every tile that's inside the
band, it spawns **one Static Mesh Component** holding that tile's baked mesh, positioned by the tile's
anchor (`PlaceTile`); when a tile leaves the band it tears that component down (`ReleaseTile`). The
components are tracked in a map keyed by tile, so the set of live components is always exactly the tiles
currently in range.

With geo-merge, "one component per tile" becomes "**one component per region**", because a region is now a
single fused tile. That's a big reduction — a few hundred components for the whole far view instead of
thousands.

> **Note — under active review for scale.** The per-region-component model is simple and works, but
> whether it holds up at full map scale (and at finer tiers than 40 cm) is still being evaluated. It may
> change to something that batches regions more aggressively. Treat the per-region-component design as the
> *current* model, not a settled final one.

---

## 7. Putting it together — the current picture

- **Near (a small bubble, tens of metres):** live, editable, solid 10 cm voxels. Not Nanite. You dig
  here.
- **Far (out to the map edge):** baked Nanite crust — a surface shell only, frozen, cheap. Currently the
  active approach is a single **40 cm geo-merged** tier (one fused mesh per ~307 m region), wired up by
  `Saved/wire_40cm_crust.py`.
- **The seam between them:** hidden by sinking the crust a few voxels underground
  (`VerticalBiasVoxels`), so the crisp near voxels always render on top where they overlap.
- **Why it scales:** geo-merge collapses thousands of tiny meshes into a few hundred big ones with no
  runtime change, at the cost of coarser (region-at-a-time) streaming — fine for the far view.

### Key files
- Live voxels (near, editable): the `MiraThalVoxel` module mesher + chunk actors.
- Crust streamer (far, runtime placement/teardown): `Source/MiraThalVoxelBake/Private/VoxelNaniteCrust.cpp`
  (`PlaceTile` / `ReleaseTile`, the per-region component model).
- Region fuse maths: `Source/MiraThalVoxel/Public/Core/RegionMerge.h`.
- Bake wiring (region-pack + geo-merge): `Source/MiraThalVoxelBake/Private/VoxelCrustBaker.cpp`.
- The mesher (the one fixed for oversized baked tiles): `Source/MiraThalVoxel/Private/Core/GreedyMesher.cpp`.
- The current 40 cm wiring script: `Saved/wire_40cm_crust.py`.
- How to bake: `BAKE_PIPELINE_GUIDE.md`. Tier config + history: `UE5_ROAMING_CLIPMAP.md`.
