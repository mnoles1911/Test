# Lessons Learned

Date | Problem | Fix | PR
---|---|---|---
2026-04-29 | `delta` unused warning in `_physics_process` | Rename to `_delta` | #27
2026-04-29 | `offset` shadows `PointLight2D.offset` in CampfireFlicker | Rename to `energy_offset` | #27
2026-04-29 | E key trigger did nothing | `Input.is_action_just_pressed()` requires editor-configured action; switched to `_unhandled_input` + direct `KEY_E` check | #27
2026-04-29 | `Engine.has_singleton("Dialogic")` always false | That API is for C++ singletons only; use `get_node_or_null("/root/Dialogic")` for autoloads | #29
2026-04-29 | `timeline_ended` crash on CanvasLayer | `Dialogic.start()` returns the layout node, not a timeline; connect `timeline_ended` on the `Dialogic` autoload with `CONNECT_ONE_SHOT` | #30
2026-04-29 | Dialogic dialogue box overflows 320x180 viewport | Default Dialogic style is sized for 1080p. In Dialogic → Styles, set box width ~280px, height ~60-70px, anchored bottom-center. Font size 6-8px (renders crisp at 4x scale). Configure via editor only — not a code fix. | —
2026-04-30 | `move_toward(Vector2.ZERO, SPEED)` causes instant stop | Step arg is per-call, not per-second. Player hit zero velocity in one frame. Add a `DECEL` constant and multiply by `delta` so braking is frame-rate independent. | #34
2026-04-30 | ColorRect (Control node) drifts from world-space siblings | Control nodes anchor to screen/viewport space. When Camera2D moves, a ColorRect placed under Node2D shifts visually while Node2D siblings stay fixed. Use Polygon2D or Sprite2D (Node2D subclasses) for world-space placeholder visuals. | #34
2026-04-30 | PointLight2D light bleeds through walls | `CollisionShape2D` blocks physics but NOT light. Add `LightOccluder2D` + `OccluderPolygon2D` to walls so 2D light is contained. | #36
2026-04-30 | Radial light origin offset by ~128px (light "from outside" the campfire) | `GradientTexture2D` `fill_from` defaults to `(0,0)` (top-left) — NOT center. With `fill = 1` (radial), the bright spot lands at the texture's top-left, not its middle. Always set `fill_from = Vector2(0.5, 0.5)` and `fill_to = Vector2(1, 0.5)` for centered radial gradients used as light textures. | #37
2026-04-30 | 2D→3D coordinate confusion: `Input.get_vector` returns Vector2(x, y) but in 3D, the floor is the **XZ plane** with Y as up. | Map `input_dir.x → velocity.x`, `input_dir.y → velocity.z`. Don't try to use `input_dir.y → velocity.y` — that would launch the player into the air. | M4-3D
2026-04-30 | Camera clipping through walls in 3D | Use `SpringArm3D` as the camera mount (not a bare Camera3D). `SpringArm3D` casts a sphere from the pivot toward the camera position and shortens the arm if anything blocks it — built-in wall avoidance, no script needed. | M4-3D
2026-04-30 | `PointLight2D.energy` flicker logic doesn't compile under `OmniLight3D` | The 3D property is `light_energy`, not `energy`. Math is identical, only the property name changes. | M4-3D
2026-04-30 | `CollisionShape3D` placed at the origin makes a CharacterBody3D's feet sink into the floor by half its height | A capsule shape's origin is its **center**. For a 1.7 m tall capsule, set the CollisionShape3D's local Y position to `+height/2` (e.g. 0.85) so the bottom of the capsule sits on Y=0. Same for the visual mesh. | M4-3D
