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
| 1 (current) | Camera2D follows player, default settings | No — placeholder art is flat |
| Art pass begins | No camera changes | Yes — emerges from sprite design |
| Final polish | Possible: add camera limits, zoom, shake effects | Yes |

When the art pass begins, the only camera-adjacent work is:
- Setting `Camera2D` limits so the player can't scroll past the edge of a room
- Optional: subtle zoom per zone (e.g., tighter in cramped tunnels)
- Optional: camera shake for impacts or earthquakes (a separate script)

None of these require changing the fundamental 2D camera setup.
