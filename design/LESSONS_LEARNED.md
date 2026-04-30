# Lessons Learned

Date | Problem | Fix | PR
---|---|---|---
2026-04-29 | `delta` unused warning in `_physics_process` | Rename to `_delta` | #27
2026-04-29 | `offset` shadows `PointLight2D.offset` in CampfireFlicker | Rename to `energy_offset` | #27
2026-04-29 | E key trigger did nothing | `Input.is_action_just_pressed()` requires editor-configured action; switched to `_unhandled_input` + direct `KEY_E` check | #27
2026-04-29 | `Engine.has_singleton("Dialogic")` always false | That API is for C++ singletons only; use `get_node_or_null("/root/Dialogic")` for autoloads | #29
2026-04-29 | `timeline_ended` crash on CanvasLayer | `Dialogic.start()` returns the layout node, not a timeline; connect `timeline_ended` on the `Dialogic` autoload with `CONNECT_ONE_SHOT` | #30
2026-04-29 | Dialogic dialogue box overflows 320x180 viewport | Default Dialogic style is sized for 1080p. In Dialogic → Styles, set box width ~280px, height ~60-70px, anchored bottom-center. Font size 6-8px (renders crisp at 4x scale). Configure via editor only — not a code fix. | —
