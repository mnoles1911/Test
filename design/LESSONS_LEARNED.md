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
