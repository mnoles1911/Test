# SFX Prompts — ElevenLabs Pass (Phase 1 Core)

Generation prompts for the Phase 1 core of `design/SFX_LIBRARY.md`, written
for **ElevenLabs Sound Effects**. This is the copy-paste / batch-feed spec:
one row per library entry.

> Source spec: `design/SFX_LIBRARY.md` (the inventory). Routing/format:
> `design/AUDIO_DESIGN.md`. This doc only covers **Phase 1** (combat &
> locomotion core + camp/weather/water basics). Phases 2–6 follow after review.

---

## 1. How to use this doc

**Columns**
- **id** — file stem. Render `var` takes; save as `<id>_01.ogg … _0N.ogg`
  into the `assets/audio/sfx/<folder>/` from `AUDIO_DESIGN.md` /
  `SFX_LIBRARY.md §2`. Unique entries (`var 1`) save as `<id>.ogg`.
- **prompt** — paste verbatim into the ElevenLabs SFX text box.
- **dur** — `duration_seconds`. A number, or `auto` to let ElevenLabs decide
  (good for organic one-shots). Loops use a fixed 12–20 s.
- **infl** — `prompt_influence` 0.0–1.0. Higher = more literal/precise (good
  for mechanical, impacts, cues); lower = more organic variation (good for
  foley, breath, ambient).
- **loop** — `Y`: prompt is written as a seamless loop; render long, then
  loop in Godot (ElevenLabs has no true loop, so the prompt forces a
  consistent no-start/no-end texture and we loop in-engine). `N`: one-shot.
- **var** — how many takes to keep (the variation count from SFX_LIBRARY).
  **Workflow:** generate ~`var × 2` takes from the *same* prompt, keep the
  `var` best/most-distinct. ElevenLabs varies naturally per generation —
  do **not** reword the prompt per variation.
- **bus** — engine routing (`AUDIO_DESIGN.md`).

**Global rules baked into every prompt (don't re-add per row):**
- Mono, **dry, close-mic'd, no reverb** — the engine adds spatialization and
  per-environment reverb. Prompts say "dry, close, no reverb".
- **No music, no musicality, no melody** — these are sound effects.
- Single discrete event for one-shots; consistent texture for loops.
- Realistic / grounded, low-fantasy (KCD2/Minecraft reference), not cartoony.

**Batch feed:** the table is API-ready — iterate rows, call ElevenLabs SFX
with `text=prompt`, `duration_seconds=dur`, `prompt_influence=infl`, request
`var×2` generations per row.

**Phase 1 scope (~165 entries):** Cat 01 live-surface locomotion · Cat 02
universal combat verbs + Roland's longsword + shipped spear · Cat 03 core
impact matrix + the 4 implemented enemies · Cat 09 fire & camp · Cat 07
weather basics · Cat 08 water core.

---

## 2. Category 01 — Locomotion (live surfaces)

Footsteps: live surfaces only (`grass, dirt, stone, wood, sand,
shallow_water`) × gaits (`walk, run, sprint, crouch`). Single footstep =
one shoe contact (engine triggers per step); render as a *single step*, not
a sequence. `infl` mid (0.4) so takes vary naturally.

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| step_walk_grass | A single soft footstep on grass and soil, a leather boot pressing down, faint dry grass crunch, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_walk_dirt | A single footstep on bare packed dirt, soft earthy thud, slight grit, leather boot, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_walk_stone | A single footstep on stone flagging, hard leather-on-rock tap with a faint scuff, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_walk_wood | A single footstep on an old wooden plank floor, dull hollow knock with a slight creak, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_walk_sand | A single footstep into dry sand, soft muffled compression, fine grain shift, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_walk_shallow_water | A single footstep into shallow water over mud, a low wet splash and squelch, dry close mono, no reverb, no music | 0.6 | 0.4 | N | 5 | SFX |
| step_run_grass | A single fast running footstep on grass and soil, harder impact, dry grass scuff, leather boot, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_run_dirt | A single fast running footstep on packed dirt, firm earthy impact and grit, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_run_stone | A single fast running footstep on stone, sharp hard boot strike with scuff, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_run_wood | A single fast running footstep on wooden planks, loud hollow knock and creak, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_run_sand | A single fast running footstep in sand, hard muffled compression, kicked grain, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_run_shallow_water | A single fast running footstep through shallow water, hard wet splash, dry close mono, no reverb, no music | 0.6 | 0.4 | N | 5 | SFX |
| step_sprint_grass | A single hard sprinting footstep on grass, heavy fast impact and grass tear, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_sprint_dirt | A single hard sprinting footstep on dirt, heavy fast earthy slam and grit spray, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_sprint_stone | A single hard sprinting footstep on stone, loud sharp boot slam and skid, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_sprint_wood | A single hard sprinting footstep on wood planks, loud hollow boom and creak, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 5 | SFX |
| step_sprint_sand | A single hard sprinting footstep in sand, heavy muffled thud, sand spray, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 5 | SFX |
| step_sprint_shallow_water | A single hard sprinting footstep through shallow water, big hard splash and spray, dry close mono, no reverb, no music | 0.7 | 0.4 | N | 5 | SFX |
| step_crouch_grass | A single very soft slow crouched footstep on grass, careful muffled press, faint, dry close mono, no reverb, no music | 0.6 | 0.35 | N | 5 | SFX |
| step_crouch_dirt | A single very soft slow crouched footstep on dirt, careful muffled earthy press, dry close mono, no reverb, no music | 0.6 | 0.35 | N | 5 | SFX |
| step_crouch_stone | A single soft slow crouched footstep on stone, quiet controlled leather contact, faint scuff, dry close mono, no reverb, no music | 0.6 | 0.4 | N | 5 | SFX |
| step_crouch_wood | A single soft slow crouched footstep on wood, careful low creak, suppressed knock, dry close mono, no reverb, no music | 0.6 | 0.4 | N | 5 | SFX |
| step_crouch_sand | A single soft slow crouched footstep in sand, near-silent muffled grain shift, dry close mono, no reverb, no music | 0.6 | 0.35 | N | 5 | SFX |
| step_crouch_shallow_water | A single slow careful crouched footstep into shallow water, gentle controlled wet trickle, dry close mono, no reverb, no music | 0.7 | 0.35 | N | 5 | SFX |

Jump / land (live surfaces) + effort:

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| jumpland_grass | A body landing from a jump onto grass and soil, a firm two-foot thud with grass crunch, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 5 | SFX |
| jumpland_dirt | A body landing onto packed dirt, firm earthy double thud and grit, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 5 | SFX |
| jumpland_stone | A body landing onto stone, hard heavy boot impact with a sharp scuff, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 5 | SFX |
| jumpland_wood | A body landing onto a wood plank floor, loud hollow boom and timber creak, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 5 | SFX |
| jumpland_sand | A body landing into sand, heavy muffled compression and grain spray, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 5 | SFX |
| jumpland_shallow_water | A body landing into shallow water, big heavy splash and spray, dry close mono, no reverb, no music | 0.8 | 0.45 | N | 5 | SFX |
| jump_exert_grunt | A short light male effort grunt on jumping, breath push, no words, dry close mono, no reverb, no music | 0.6 | 0.35 | N | 3 | Voice |
| land_heavy_stagger | A heavy hard landing from a high fall, boots slamming and a stumbling scuff, pained breath, dry close mono, no reverb, no music | 1.0 | 0.5 | N | 3 | SFX |
| land_soft | A gentle low-height landing, soft controlled boot touch, faint cloth, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 3 | SFX |

Armor-weight movement loops (mixed over steps by equipped weight) + traversal
+ player breath:

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| armor_cloth_move_loop | Seamless loop of soft cloth and leather garment rustle from a walking body, steady consistent texture, no beginning or end, dry close mono, no reverb, no music | 14 | 0.3 | Y | 1 | SFX |
| armor_leather_move_loop | Seamless loop of creaking leather armor flexing on a moving body, steady consistent, no start or end, dry close mono, no reverb, no music | 14 | 0.35 | Y | 1 | SFX |
| armor_mail_move_loop | Seamless loop of chainmail rings shifting and jingling on a walking body, steady consistent metallic rustle, no start or end, dry close mono, no reverb, no music | 14 | 0.4 | Y | 1 | SFX |
| armor_plate_move_loop | Seamless loop of plate armor clanking and leather straps creaking on a moving body, steady heavy consistent, no start or end, dry close mono, no reverb, no music | 14 | 0.45 | Y | 1 | SFX |
| water_wade_shallow_loop | Seamless loop of a person wading steadily through shallow water, continuous rhythmic sloshing, no start or end, dry close mono, no reverb, no music | 12 | 0.35 | Y | 1 | SFX |
| water_entry_walk | A person walking into water from shore, steps turning to wading splashes, dry close mono, no reverb, no music | 1.5 | 0.4 | N | 3 | SFX |
| water_entry_run_plunge | A person running and plunging into deep water, a big heavy splash and churn, dry close mono, no reverb, no music | 1.5 | 0.45 | N | 3 | SFX |
| climb_rock_loop | Seamless loop of hands and boots scrabbling and gripping on rock while climbing, grit and cloth strain, steady, no start or end, dry close mono, no reverb, no music | 12 | 0.35 | Y | 1 | SFX |
| climb_grunt | A short strained male effort grunt while pulling up a climb, no words, dry close mono, no reverb, no music | 0.7 | 0.35 | N | 3 | Voice |
| vault_ledge | A quick body vault over a ledge, a hand slap on stone, cloth scuff and a light landing, dry close mono, no reverb, no music | 0.9 | 0.4 | N | 3 | SFX |
| roland_breath_idle_loop | Seamless loop of calm quiet steady human breathing at rest, relaxed, no start or end, dry close mono, no reverb, no music | 10 | 0.3 | Y | 1 | Voice |
| roland_breath_exert_loop | Seamless loop of heavy winded human breathing after exertion, fast and laboured but controlled, steady, no start or end, dry close mono, no reverb, no music | 10 | 0.35 | Y | 1 | Voice |
| roland_breath_lowhp_loop | Seamless loop of pained laboured human breathing, strained and uneven, hurt but not theatrical, no start or end, dry close mono, no reverb, no music | 10 | 0.35 | Y | 1 | Voice |
| roland_breath_critical_loop | Seamless loop of ragged desperate shallow human breathing, badly wounded, gasping, no start or end, dry close mono, no reverb, no music | 10 | 0.4 | Y | 1 | Voice |
| roland_effort_grunt | A short sharp male combat effort grunt, exertion, no words, dry close mono, no reverb, no music | 0.5 | 0.35 | N | 5 | Voice |
| roland_jump_exhale | A short sharp breath exhale on physical effort, no words, dry close mono, no reverb, no music | 0.4 | 0.35 | N | 3 | Voice |

---

## 3. Category 02 — Combat: Player (universal + longsword + spear)

Universal combat verbs (the parry/heavy/unblock cues are **diegetic from the
enemy's stance, not UI beeps** — keep them physical, per `AUDIO_DESIGN.md`):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_block_hold_loop | Seamless loop of a sword blade braced under continuous pressure, a low metallic resonant strain with faint scrape, no start or end, dry close mono, no reverb, no music | 6 | 0.4 | Y | 1 | Combat |
| cmb_block_impact | A heavy blow caught on a raised steel sword, a hard resonant clang with a scrape, dry close mono, no reverb, no music | 0.8 | 0.55 | N | 5 | Combat |
| cmb_parry_success | A clean sharp steel-on-steel parry, a bright high ringing deflection, satisfying and precise, dry close mono, no reverb, no music | 0.7 | 0.6 | N | 4 | Combat |
| cmb_riposte_strike | A fast follow-up sword strike biting into a body, a quick whoosh and wet armored hit, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 3 | Combat |
| cmb_cue_parry_green | A brief soft physical chime resonance from an enemy weapon stance, very short, subtle, not electronic, dry close mono, no reverb, no music | 0.4 | 0.55 | N | 2 | Combat |
| cmb_cue_heavy_yellow | A low tonal warning resonance from an enemy winding up a heavy blow, a physical creak of force gathering, short, not electronic, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 2 | Combat |
| cmb_cue_unblock_red | A low menacing thud and growl-like surge from an enemy committing to an unblockable strike, physical not electronic, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 2 | Combat |
| cmb_dodge_roll | A fast body roll across the ground, cloth and armor tumble with a quick scuff, dry close mono, no reverb, no music | 0.8 | 0.4 | N | 4 | Combat |
| cmb_dodge_step | A quick sharp evasive side-step, fast cloth and foot scuff, dry close mono, no reverb, no music | 0.5 | 0.4 | N | 4 | Combat |
| cmb_stagger_break | A guard broken by exhaustion, a stumbling armored stagger with a sharp winded gasp, dry close mono, no reverb, no music | 1.2 | 0.45 | N | 3 | Combat |
| cmb_endurance_empty | A sharp exhausted gasp as stamina fails, breath emptied, no words, dry close mono, no reverb, no music | 0.7 | 0.35 | N | 3 | Voice |
| cmb_lockon_toggle | A very short subtle physical tick of focus snapping onto a target, minimal, not electronic, dry close mono, no reverb, no music | 0.3 | 0.5 | N | 1 | UI |
| cmb_timeslow_enter | A short downward-pitching whoosh as time slows after a lethal hit, air warping low, dry close mono, no reverb, no music | 0.8 | 0.45 | N | 1 | Combat |
| cmb_timeslow_exit | A short upward-pitching whoosh as time snaps back to normal speed, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 1 | Combat |

Longsword class (Roland's mainline weapon):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_longsword_swing_light | A fast light sword swing through air, a quick sharp steel whoosh, dry close mono, no reverb, no music | 0.5 | 0.5 | N | 5 | Combat |
| cmb_longsword_swing_heavy | A slow heavy committed two-handed sword swing through air, a deep powerful whoosh, dry close mono, no reverb, no music | 0.8 | 0.5 | N | 4 | Combat |
| cmb_longsword_swing_miss_air | A sword swung hard and missing, a wide hollow air-displacement whoosh, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 4 | Combat |
| cmb_longsword_draw | A longsword drawn from a leather scabbard, a smooth metallic scrape ending in a light ring, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 3 | Combat |
| cmb_longsword_sheathe | A longsword sliding into a leather scabbard, a metallic scrape ending in a soft seat, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 3 | Combat |
| cmb_longsword_block_hold_loop | Seamless loop of a longsword held braced under pressure, low metallic strain and faint grind, no start or end, dry close mono, no reverb, no music | 6 | 0.4 | Y | 1 | Combat |
| cmb_longsword_parry | A longsword deflecting an incoming blade, a sharp bright clean ring, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_longsword_special | A powerful committed longsword thrust and finisher, a hard whoosh into a heavy armored impact, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 3 | Combat |

Tier / condition timbre layers (mixed over the base hit, not standalone hits):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_tier_common_layer | A thin dull iron resonance layer for a low-quality blade impact, plain and slightly muted, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 1 | Combat |
| cmb_tier_quality_layer | A brighter cleaner steel resonance layer for a fine blade impact, clear ring, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 1 | Combat |
| cmb_tier_masterwork_layer | A rich sustained bell-like steel resonance layer for a masterwork blade impact, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 1 | Combat |
| cmb_condition_dull_layer | A dull flat lifeless metallic layer for a worn damaged blade impact, no ring, dry close mono, no reverb, no music | 0.5 | 0.45 | N | 1 | Combat |
| cmb_condition_break_fail | A worn blade failing under a blocked blow, a cracked dull metallic give and rattle, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 2 | Combat |

Shipped ThrowableSpear set:

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_spear_windup | A spear drawn back and braced to throw, cloth and arm tension with a faint shaft creak, dry close mono, no reverb, no music | 0.7 | 0.4 | N | 3 | Combat |
| cmb_spear_throw | A spear thrown hard, a sharp whoosh of a wooden shaft cutting air, dry close mono, no reverb, no music | 0.6 | 0.5 | N | 3 | Combat |
| cmb_spear_inflight_loop | Seamless loop of a spear shaft spinning and whirring through the air, steady consistent whir, no start or end, dry close mono, no reverb, no music | 4 | 0.4 | Y | 1 | Combat |
| cmb_spear_embed_flesh | A spear point striking and sinking into a body, a hard wet meaty impact and shaft quiver, dry close mono, no reverb, no music | 0.7 | 0.55 | N | 3 | Combat |
| cmb_spear_embed_wood | A spear point striking and sticking into wood, a sharp solid thunk and shaft vibration, dry close mono, no reverb, no music | 0.7 | 0.55 | N | 3 | Combat |
| cmb_spear_embed_stone | A spear point striking stone and skittering off, a hard sharp clang and clatter, dry close mono, no reverb, no music | 0.7 | 0.55 | N | 3 | Combat |
| cmb_spear_retrieve | A spear pulled free from a body or surface and grabbed, a wet or wooden tug and a wooden handle grab, dry close mono, no reverb, no music | 0.8 | 0.45 | N | 3 | Combat |
| cmb_throw_arc | A short light whoosh of a thrown object arcing through the air, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 3 | Combat |

---

## 4. Category 03 — Impacts (core) & the 4 Enemies

Core impact matrix — Phase 1 live damage types `slash` (longsword) and
`pierce` (spear) against the seven targets:

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_hit_slash_flesh_unarmored | A sword slashing into unarmored flesh, a fast wet cutting impact, grounded not gory-cartoon, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_slash_flesh_padded | A sword slash landing on padded gambeson over a body, a muffled cloth-dampened thud with a faint cut, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_slash_mail | A sword blow against chainmail, a deflecting metallic clatter of rings, little penetration, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_hit_slash_plate | A sword blow glancing off steel plate, a hard bright clang and skid, no penetration, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_hit_slash_shield | A sword strike on a wooden shield, a solid woody thud with a metal rim ring, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_slash_wood | A sword chopping into a wooden surface, a sharp bite and splinter, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_slash_stone | A sword striking stone, a hard bright clang and scrape with a spark feel, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_hit_pierce_flesh_unarmored | A spear or point thrust into unarmored flesh, a sharp wet stab, grounded not cartoon, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_pierce_flesh_padded | A point driven through padded cloth into a body, a muffled tearing stab, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_pierce_mail | A point driven against chainmail, a metallic ring with strained rings parting, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_hit_pierce_plate | A point skidding off steel plate, a sharp hard scrape and clang, no penetration, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |
| cmb_hit_pierce_shield | A spear point punching into a wooden shield, a hard splintering thunk, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_pierce_wood | A spear point stabbing into wood, a sharp solid thunk, dry close mono, no reverb, no music | 0.6 | 0.55 | N | 4 | Combat |
| cmb_hit_pierce_stone | A spear point jabbing stone and slipping, a sharp clack and scrape, dry close mono, no reverb, no music | 0.6 | 0.6 | N | 4 | Combat |

**Goblin** (small, wiry, swarm, unarmored — vocalizations are guttural and
non-human, never words):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_goblin_idle_chatter | Low guttural muttering and clicking of a small wiry goblin creature idling, non-verbal, menacing but small, dry close mono, no reverb, no music | 1.5 | 0.4 | N | 5 | Combat |
| cmb_goblin_alert_shout | A sharp guttural shriek of a goblin spotting an enemy, an alarm screech, non-verbal, dry close mono, no reverb, no music | 0.8 | 0.45 | N | 3 | Combat |
| cmb_goblin_group_alert | Several goblins screeching and snarling together as a pack rouses, non-verbal, dry close mono, no reverb, no music | 1.5 | 0.4 | N | 2 | Combat |
| cmb_goblin_attack_jab | A goblin's quick vicious attack snarl with a small weapon jab whoosh, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 4 | Combat |
| cmb_goblin_attack_leap | A goblin shrieking and leaping in to attack, a lunging snarl, dry close mono, no reverb, no music | 0.8 | 0.45 | N | 3 | Combat |
| cmb_goblin_hurt | A goblin taking a hit, a sharp pained guttural yelp, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 5 | Combat |
| cmb_goblin_death | A goblin killed, a choked guttural death cry collapsing to a small body fall, dry close mono, no reverb, no music | 1.2 | 0.45 | N | 4 | Combat |
| cmb_goblin_gib_overkill | A goblin destroyed by a massive overkill blow, a wet violent burst and spatter, grounded, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 2 | Combat |
| cmb_goblin_flee | A goblin panicking and fleeing, frightened gibbering and scrambling, non-verbal, dry close mono, no reverb, no music | 1.2 | 0.4 | N | 3 | Combat |
| cmb_goblin_footstep_loop | Seamless loop of a small light creature's scrabbling running footsteps on dirt, quick and erratic, no start or end, dry close mono, no reverb, no music | 6 | 0.35 | Y | 1 | Combat |

**Ashfallen** (elite, faceless, heavy armor — **no voice**; identity is armor
foley and breath behind a helm):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_ashfallen_footstep_heavy | A single slow heavy armored footstep, a steel boot and plate weight pressing down with a strap creak, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 5 | Combat |
| cmb_ashfallen_armor_creak_idle_loop | Seamless loop of heavy plate armor and leather straps creaking with slow breathing behind a helm, steady, no start or end, dry close mono, no reverb, no music | 10 | 0.4 | Y | 1 | Combat |
| cmb_ashfallen_telegraph_measured | A measured heavy sword raised to strike, a slow deliberate armored shift and blade lift, physical tell, dry close mono, no reverb, no music | 0.8 | 0.5 | N | 2 | Combat |
| cmb_ashfallen_telegraph_heavy | A big heavy blow winding up, armor straining and a deep gathering shift of force, physical tell, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 2 | Combat |
| cmb_ashfallen_telegraph_thrust_red | A short sharp committed armored lunge wind-up for an unblockable thrust, a hard exhale behind a helm, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 2 | Combat |
| cmb_ashfallen_shield_bash | A heavy steel shield bash slamming forward, a hard flat metallic impact, dry close mono, no reverb, no music | 0.7 | 0.55 | N | 3 | Combat |
| cmb_ashfallen_hurt_clang_chip | A blow landing on heavy armor, a hard metallic clang and chip with a stifled grunt behind a helm, dry close mono, no reverb, no music | 0.7 | 0.55 | N | 5 | Combat |
| cmb_ashfallen_death_collapse | A heavily armored warrior killed, a final stifled breath and a heavy plate-armored body crashing to the ground, dry close mono, no reverb, no music | 1.5 | 0.5 | N | 3 | Combat |
| cmb_ashfallen_blade_drop | A rusted heavy blade dropping and clattering onto the ground, dry close mono, no reverb, no music | 0.9 | 0.5 | N | 2 | Combat |

**Wolf** (pack flanker — audible before seen):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_wolf_breath_pant_loop | Seamless loop of a large wolf panting and breathing low, steady, slightly threatening, no start or end, dry close mono, no reverb, no music | 8 | 0.35 | Y | 1 | Combat |
| cmb_wolf_undergrowth_move | A wolf moving fast through brush and undergrowth, rustling leaves and paws, dry close mono, no reverb, no music | 1.0 | 0.35 | N | 4 | Combat |
| cmb_wolf_alert_growl | A low rising menacing wolf growl as it locks on, dry close mono, no reverb, no music | 1.0 | 0.45 | N | 3 | Combat |
| cmb_wolf_lunge_windup | A wolf snarling and coiling to lunge, a fast aggressive bark-snarl, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 3 | Combat |
| cmb_wolf_bite | A wolf's fast snapping bite, jaws clashing with a wet snap, dry close mono, no reverb, no music | 0.5 | 0.5 | N | 4 | Combat |
| cmb_wolf_yelp_hurt | A wolf hit and yelping in pain, a sharp canine cry, dry close mono, no reverb, no music | 0.6 | 0.45 | N | 4 | Combat |
| cmb_wolf_death | A wolf killed, a final pained snarl-whine cut short, body drop, dry close mono, no reverb, no music | 1.0 | 0.45 | N | 3 | Combat |
| cmb_wolf_paw_steps_loop | Seamless loop of a four-legged animal trotting fast on soil and leaves, soft rapid paw pattern, no start or end, dry close mono, no reverb, no music | 6 | 0.35 | Y | 1 | Combat |

**Bear** (solo mini-boss, heavy and slow):

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| cmb_bear_growl_idle_loop | Seamless loop of a huge bear breathing and low rumbling growls, slow and massive, no start or end, dry close mono, no reverb, no music | 9 | 0.4 | Y | 1 | Combat |
| cmb_bear_charge_telegraph | A bear rearing into a charge with a deep explosive roar, dry close mono, no reverb, no music | 1.2 | 0.5 | N | 2 | Combat |
| cmb_bear_run_thunder | A massive bear running, thunderous heavy four-legged ground impacts, dry close mono, no reverb, no music | 1.5 | 0.45 | N | 3 | Combat |
| cmb_bear_claw_swipe | A bear's wide heavy claw swipe, a huge whoosh of force, dry close mono, no reverb, no music | 0.8 | 0.5 | N | 4 | Combat |
| cmb_bear_bite | A bear's huge crushing bite, massive jaws snapping wetly, dry close mono, no reverb, no music | 0.7 | 0.5 | N | 3 | Combat |
| cmb_bear_rear_roar | A wounded enraged bear rearing up with a colossal echoing roar, dry close mono, no reverb, no music | 2.0 | 0.5 | N | 2 | Combat |
| cmb_bear_slam | A bear slamming both forelimbs down, a tremendous ground-shaking impact, dry close mono, no reverb, no music | 1.0 | 0.5 | N | 3 | Combat |
| cmb_bear_footfall_heavy | A single colossal bear footfall on soil, deep heavy weight, dry close mono, no reverb, no music | 0.7 | 0.45 | N | 5 | Combat |
| cmb_bear_hurt_deep | A bear taking a hit, a deep enraged pained roar-grunt, dry close mono, no reverb, no music | 0.9 | 0.45 | N | 4 | Combat |
| cmb_bear_death_heavy | A bear killed, a final deep collapsing roar and a massive body crashing down, dry close mono, no reverb, no music | 2.0 | 0.5 | N | 3 | Combat |

---

## 5. Category 09 — Fire & Camp

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| fire_campfire_crackle_loop | Seamless loop of a steady campfire, continuous wood crackle and soft flame whoosh, consistent, no start or end, dry close mono, no reverb, no music | 18 | 0.3 | Y | 1 | Ambient |
| fire_ember_pop | A single sharp pop and spark snap from a fire ember, dry close mono, no reverb, no music | 0.4 | 0.4 | N | 5 | Ambient |
| fire_log_settle | A burning log shifting and collapsing in a fire with a soft crumble and spark burst, dry close mono, no reverb, no music | 1.0 | 0.35 | N | 3 | Ambient |
| fire_ignite_whoosh | A fire catching and flaring up, a soft whoomph of flame taking hold, dry close mono, no reverb, no music | 1.0 | 0.45 | N | 3 | Ambient |
| fire_tinder_kindle | Tinder and small twigs catching, faint crackle building from a struck spark, dry close mono, no reverb, no music | 1.5 | 0.35 | N | 2 | Ambient |
| fire_extinguish_hiss | A fire doused, a sharp steam hiss and sputter dying out, dry close mono, no reverb, no music | 1.2 | 0.4 | N | 2 | Ambient |
| fire_smoke_fade | Faint soft smoke and last embers fading after a fire is out, very quiet, dry close mono, no reverb, no music | 1.5 | 0.3 | N | 1 | Ambient |
| fire_torch_flutter_loop | Seamless loop of a handheld torch flame fluttering and guttering, steady, no start or end, dry close mono, no reverb, no music | 12 | 0.3 | Y | 1 | Ambient |
| fire_brazier_loop | Seamless loop of a large steady brazier fire burning, fuller and deeper than a torch, no start or end, dry close mono, no reverb, no music | 16 | 0.3 | Y | 1 | Ambient |
| camp_rest_fade_sting | A very soft brief tonal breath as the world fades to rest, gentle, almost silent, dry close mono, no reverb, no music | 1.0 | 0.3 | N | 1 | UI |
| camp_rest_autosave_chime | A single very soft understated low resonance marking a quiet autosave, no fanfare, dry close mono, no reverb, no music | 0.8 | 0.4 | N | 1 | UI |

---

## 6. Category 07 — Weather (basics)

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| wx_clear_bed_loop | Seamless loop of a calm clear-day outdoor ambience, very gentle air and faint distant openness, steady, no start or end, mono, no reverb, no music | 20 | 0.25 | Y | 1 | Ambient |
| wx_wind_calm_loop | Seamless loop of soft light calm wind, gentle steady air movement, no gusts, no start or end, mono, no reverb, no music | 18 | 0.25 | Y | 1 | Ambient |
| wx_wind_breeze_loop | Seamless loop of a moderate breeze through open land, steady with mild swells, no start or end, mono, no reverb, no music | 18 | 0.3 | Y | 1 | Ambient |
| wx_wind_storm_loop | Seamless loop of strong howling storm wind, powerful sustained gusting, no start or end, mono, no reverb, no music | 18 | 0.35 | Y | 1 | Ambient |
| wx_rain_light_soil_loop | Seamless loop of light rain falling on soil and grass, soft steady patter, no start or end, mono, no reverb, no music | 16 | 0.3 | Y | 1 | Ambient |
| wx_rain_light_stone_loop | Seamless loop of light rain on stone and pavement, fine bright steady patter, no start or end, mono, no reverb, no music | 16 | 0.3 | Y | 1 | Ambient |
| wx_rain_heavy_soil_loop | Seamless loop of heavy rain on soil and earth, dense drumming downpour, no start or end, mono, no reverb, no music | 16 | 0.35 | Y | 1 | Ambient |
| wx_rain_heavy_foliage_loop | Seamless loop of heavy rain hammering a forest canopy, dense leafy roar, no start or end, mono, no reverb, no music | 16 | 0.35 | Y | 1 | Ambient |
| wx_thunder_distant | A low distant rolling thunder rumble far away, dry, mono, no reverb, no music | 4 | 0.35 | N | 4 | Ambient |
| wx_thunder_near_crack | A close violent thunder crack and sharp boom rolling off, dry, mono, no reverb, no music | 4 | 0.45 | N | 3 | Ambient |
| wx_rain_onset_ramp | Rain beginning, the first scattered drops building into a steady patter, mono, no reverb, no music | 6 | 0.3 | N | 1 | Ambient |
| wx_rain_tailoff | Rain easing off, a steady patter thinning to scattered last drops, mono, no reverb, no music | 6 | 0.3 | N | 1 | Ambient |

---

## 7. Category 08 — Water (core)

| id | prompt | dur | infl | loop | var | bus |
|---|---|---|---|---|---|---|
| water_swim_surface_loop | Seamless loop of a person swimming at the surface, steady rhythmic strokes and splashes, no start or end, dry close mono, no reverb, no music | 12 | 0.35 | Y | 1 | Ambient |
| water_swim_submerged_loop | Seamless loop of a body moving underwater, muffled low swishes and kicks, steady, no start or end, mono, no reverb, no music | 12 | 0.35 | Y | 1 | Ambient |
| water_submerge_plunge | A body dropping underwater, a heavy plunging splash cutting to muffled, dry close mono, no reverb, no music | 1.2 | 0.4 | N | 3 | Ambient |
| water_surface_gasp | A person breaking the water surface with a sharp gasp and water-shedding splash, dry close mono, no reverb, no music | 1.0 | 0.4 | N | 3 | Voice |
| water_underwater_ambient_loop | Seamless loop of a low muffled underwater ambience with faint bubble drift, steady, no start or end, mono, no reverb, no music | 18 | 0.25 | Y | 1 | Ambient |
| water_splash_small | A small light water splash, a foot or hand entering, dry close mono, no reverb, no music | 0.6 | 0.4 | N | 5 | Ambient |
| water_splash_medium | A medium water splash, a body-sized entry, dry close mono, no reverb, no music | 0.9 | 0.4 | N | 4 | Ambient |
| water_splash_large | A large heavy water splash and churn, a big mass hitting water, dry close mono, no reverb, no music | 1.2 | 0.4 | N | 3 | Ambient |
| water_drip_single | A single isolated water drip falling and plopping, dry close mono, no reverb, no music | 0.5 | 0.35 | N | 5 | Ambient |

---

## 8. Phase 1 rollup & next

| Category | Entries | Files (with var) |
|---|---|---|
| 01 Locomotion (live) | 49 | ≈ 175 |
| 02 Combat: Player | 35 | ≈ 110 |
| 03 Impacts + 4 enemies | 51 | ≈ 165 |
| 09 Fire & Camp | 11 | ≈ 25 |
| 07 Weather basics | 12 | ≈ 16 |
| 08 Water core | 9 | ≈ 28 |
| **Phase 1 total** | **≈ 167 prompts** | **≈ 520 rendered files** |

**Workflow per row:** call ElevenLabs SFX with `text=prompt`,
`duration_seconds=dur`, `prompt_influence=infl`; generate `var × 2`
candidates; audition; keep the `var` best as `<id>_01..0N.ogg`; convert to
mono 44.1 kHz `.ogg`; place per `AUDIO_DESIGN.md §folder structure`; flip the
entry to EXISTING in `SFX_LIBRARY.md`.

**Loop rows (`loop=Y`):** the prompt forces a consistent no-start/no-end
texture; trim to a clean zero-crossing and set the AudioStream to loop in
Godot. If a generated loop has an audible seam, regenerate or crossfade-trim;
escalate to a Suno bed (per the music doc) only if a category proves
un-loopable in ElevenLabs.

**After review, Phase 2** = full voxel tool×material set for the 4 wired
materials (Cat 04), then weather/region beds (Cat 10), then systems/UI/
mini-game gaps (Cat 12–18), then the long tail per `SFX_LIBRARY.md §23`.

---

## 9. Maintenance

- This doc is generated *from* `SFX_LIBRARY.md`. If an entry's design
  changes, change it there first, then regenerate the prompt here.
- Keep the global rules (mono, dry, no reverb, no music) in §1, not in every
  cell, so prompts stay terse and ElevenLabs stays focused.
- As phases are generated, append their tables here and update §8.
