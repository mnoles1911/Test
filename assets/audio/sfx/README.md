# assets/audio/sfx/

Final, approved game sound effects. **Committed to the repo** (audio is not
gitignored here — unlike TTS dialogue under `audio/dialogue/`).

This is *not* the generation staging area. SFX are generated as candidate
`_vNN` versions into a review folder (default `Desktop\SFX\`, see
`tools/render_sfx.py`). You audition, pick the keeper(s), convert, and place
the result **here**.

## Where each file goes

Folder = the sound's domain (mirrors `design/SFX_LIBRARY.md §2`). The
generator's review folders (`01_locomotion/`, `02_combat/`, `07_weather/`,
`08_water/`, `09_fire_camp/`) remap to these semantic folders on import:

| Folder | What lives here | id prefixes |
|---|---|---|
| `locomotion/` | footsteps, jump/land, climb, wade, armor layer, player breath | `step_ jump* land* armor_ climb_ vault_ roland_ water_wade*` |
| `combat/` | weapon, impacts, enemies | `cmb_` |
| `voxel/` | dig/mine/chop/place/explosive | `vox_` |
| `crafting/` | forge, alchemy, carpentry, … | `craft_` |
| `items/` | pickup/equip/containers/torch | `item_` |
| `environment/` | weather, water, fire | `wx_ water_ fire_` |
| `ambience/` | per-region day/night beds | `amb_` |
| `creatures/` | non-combat ambient fauna | `wld_` |
| `systems/` | lockpicking, mini-games, investigation | `lock_ minigame_ invest_` |
| `ui/` | menu, journal, save, skill, camp chimes | `ui_ journal_ map_ save_ skill_ camp_rest_` |
| `npc/` | non-verbal efforts/reactions/crowd | `npc_` |
| `economy/` | coin, trade | `econ_` |

## Naming

- Single approved take → `<id>.ogg` (e.g. `water_drip_single.ogg`)
- Variation set (`var` ≥ 2 in SFX_LIBRARY, e.g. footsteps) →
  `<id>_01.ogg … _0N.ogg`. The engine random-picks per trigger.

## Format

Mono, 44.1 kHz, OGG Vorbis (per `design/AUDIO_DESIGN.md`). ElevenLabs
returns mp3 — convert the keeper:

```
ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a libvorbis out.ogg
```

Loop files: keep the full-length clip, set **Import → Loop = On** in Godot.
Seamless looping is enabled in-engine, not baked into the file.

## After placing a file

Flip that entry's status to `EXISTING` in `design/SFX_LIBRARY.md` and commit
the asset + the doc change together (see `SFX_LIBRARY.md §24` maintenance).

## Checking loop seams (files marked `0_LOOP_KEEP-1`)

A loop must wrap with no audible click or volume jump. Reliable, version-
proof method in Audacity (do **not** rely on Shift+Space — it is "play once"
in Audacity 3.2+, and OS players insert a fake gap):

1. Open the file → `Ctrl+A` → `Ctrl+C`.
2. Press `End`, then `Ctrl+V` (paste the clip after itself; repeat for more
   cycles).
3. `Spacebar`; listen at each **join** — that join is exactly the in-game
   loop wrap. A tick/click or a volume "breath" there = bad seam.
4. Optional: zoom into the clip's very start and end — both near the zero
   centerline and similar = clean; a big vertical jump = the click.

Bad seam → tighten the loop prompt in `design/SFX_PROMPTS.md` (longer
duration, stronger "no beginning or end / consistent texture" wording) and
re-render just that id; looping itself is enabled by Godot's import
**Loop = On**, not baked into the file.
