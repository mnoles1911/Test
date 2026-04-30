# Camera and Perspective — Design Note

## The "3/4 Isometric" Look

Game One targets a visual style like Sea of Stars and Octopath Traveler: characters viewed from a slight angle above, environments painted with forced perspective so walls and floors feel three-dimensional. This is called a **3/4 view** or **3/4 isometric** perspective.

**Important:** This look is entirely an art decision. It comes from how sprites and backgrounds are drawn, not from any camera setting.

---

## What the Camera Actually Does

In Godot 4, `Camera2D` is a standard 2D follow camera. It:
- Centers the viewport on the player (or whatever node it's attached to)
- Scrolls the world as the player moves
- Does **not** tilt, rotate, skew, or apply any transform to simulate perspective

The camera sees the world exactly as it is laid out in 2D space. The 3/4 angle exists in the art, not in the camera.

---

## Why the Placeholder Scene Looks Flat

Milestone 1 uses colored rectangles instead of real art. Rectangles have no perspective baked into them, so the scene looks completely flat and top-down. **This is correct and expected.**

The 3/4 perspective will appear naturally once real pixel art sprites are added:
- Character sprites drawn with legs at bottom, head at top, body slightly angled
- Tile backgrounds painted with floor receding upward and walls rising from the bottom edge of the tile
- No camera changes required at that point

---

## References

- **Sea of Stars** (Sabotage Studio) — same engine approach, standard Camera2D follow
- **Octopath Traveler** (Square Enix) — "HD-2D" style, same principle in a different engine
- **Chrono Trigger** — the original 3/4 SNES look this style descends from

---

## What This Means for Development

| Milestone | Camera state | Perspective visible? |
|---|---|---|
| 1–3 (complete) | Camera2D follows player, default settings | No — placeholder rectangles are flat |
| Milestone 5 (art pass) | No camera changes needed | Yes — emerges from 32×32 tile and 32×48 sprite design |
| Zone framework (Chunk 1) | Camera limits set by RoomTrigger per room | Yes — rooms frame correctly |
| Final polish | Add zoom per zone, camera shake for impacts | Yes |

When the art pass begins, the only camera-adjacent work is:
- `Camera2D` limits — already handled by `RoomTrigger.gd` (Chunk 1)
- Optional: subtle zoom per zone (e.g., tighter in cramped tunnels)
- Optional: camera shake for impacts (a separate script, not yet built)

None of these require changing the fundamental 2D camera setup.

---

## Confirmed: Not Building in 3D

The question was asked: "should we build in 3D to get better lighting?"

Answer: No. Godot 4's 2D renderer with `PointLight2D` and normal maps on `TileSet` resources achieves the same lighting depth as Unity 3D games using sprite rendering. Switching to 3D would require rebuilding every scene node type (CharacterBody3D, MeshInstance3D, etc.), a 3D camera rig, and a completely different physics layer — none of which we gain from. The campfire flicker and cave lighting already look correct in 2D.

Lore: `design/ART_DIRECTION.md` — "Art Approach Decision" section
Pipeline: `design/ART_PIPELINE.md`
