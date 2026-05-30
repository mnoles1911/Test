# assets/CLAUDE.md

Game assets — textures, models, audio, fonts, resources.

## Layout

| Subdir | Contents |
|---|---|
| `audio/sfx/` | 548 raw SFX takes (5 categories: locomotion / voxel / weather / water / fire). Pipeline: `tools/render_sfx.py` (ElevenLabs). Resolve at runtime via `AudioManager.play(id)` |
| `audio/music/` | Music tracks (prompts in `tools/MUSIC_PROMPTS.md`) |
| `audio/dice/`, `audio/lockpicking/` | Mini-game SFX |
| `fonts/` | Voxelmark UI fonts |
| `heightmaps/` | EXR / PNG heightmap source data (Copper Isles, Mira) |
| `lockpick/anim/` | Lockpicking mini-game animations |
| `menu_backgrounds/` | Main menu / loading screen art |
| `models/` | `.glb` characters + props from Blender / MagicaVoxel. `goblin_anims/` = Mixamo animation library |
| `npcs/` | `.tres` `NPCData` resources, one per character. `trainers/` for skill trainers |
| `portraits/` | 256×320 dialogue portraits |
| `profiles/` | `WeatherLocationProfile` + `AtmosphereProfile` `.tres` |
| `shaders/` | All `.gdshader` files + `.tres` ShaderMaterials |
| `skills/perks/` | 300 `PerkData` `.tres` walked by `PerkRegistry` at startup |
| `sky/` | Sky panoramas (16 time-of-day anchors used by `AtmosphereProfile`) |
| `ui/` | `Colors.gd` (palette source) + `UIStyles.gd` (StyleBox builders) + `css/menus_shared.css` |
| `voxel/`, `voxels/` | Voxel atlas (texture_packs/default/) + material definitions |

## Rules

- **Voxel textures must be pixel art**, not photo-style. Use Retrodiffusion / PixelLab.ai / Aseprite; demote NB / DALL-E to fallback-only (their output is continuous-gradient photo style; nearest-downscale samples random pixels → noise). `tools/build_texture_atlas.py` has a `_warn_if_not_pixel_art` heuristic.
- **Voxel atlas:** 16 px tile × 64 cols (1024²), nearest filtering with mipmaps + anisotropy.
- **Audio file paths:** `assets/audio/sfx/<folder>/<id>[.ogg|_NN.ogg]` (variations enumerated). `AudioManager` picks one at random per call.
- **NPCData resources:** one `.tres` per character, assigned to the `NPC.gd` script in the Inspector.
- **Shader materials** authored in `.tres` may not restore correctly on load — runtime re-injection in `World3DBootstrap` is sometimes required (water case).

## Pipelines

- **SFX:** `tools/render_sfx.py` (ElevenLabs, ~9 cr/s + 20 cr/gen). Prompts in `SFX_PROMPTS.md` (project root or `tools/`).
- **Voxel textures:** `tools/build_texture_atlas.py` + `tools/AI_TEXTURE_PROMPTS.md`.
- **NPC voicing:** `tools/render_voice.py` (when present), `design/TTS_PIPELINE.md`.

## When adding an asset

1. Put it in the right subdir (resolve by AudioManager / NPC.gd / etc. conventions).
2. If it needs a new pipeline tool, add to `../tools/` + document in `../tools/CLAUDE.md`.
3. If it's PR-blocking-on-art (e.g. designer needs to commit a `.glb`), add a row to `../DESIGNER_TODO.md`.
