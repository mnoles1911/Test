# Art Direction — Mira-Thal: Game One
## Visual production reference

> This document covers visual implementation only. For story, characters, world descriptions, or location lore, go to `/lore`.

---

## Art Approach — CONFIRMED: 3D Voxel

**Engine:** Godot 4.6.2, 3D mode. NOT 2D.  
**Style:** Voxel world (Veloren / Cube World aesthetic) with Skyrim-scale atmosphere.  
**Full migration plan:** `design/3D_VOXEL_MIGRATION.md`

The pivot from 2D pixel art to 3D voxel was confirmed. All 2D scene files (World.tscn, Player.tscn) will be replaced with 3D equivalents. All logic autoloads (GameState, Journal, Inventory, etc.) are unchanged.

---

## North Star Aesthetic

**Veloren meets Skyrim.** The campfire knight image from Milestone 1 still defines the MOOD — that specific feeling of warm light against ancient stone, a lone figure at rest in a hostile world. In 3D voxel, this translates to:

- A campfire rendered as a `PointLight3D` with `CampfireFlicker3D.gd`, casting real volumetric glow across cave voxels
- Cave walls built from hand-assembled MagicaVoxel blocks, each face catching light differently
- Roland represented as a low-poly 3D Blender model — small against the environment, not filling the screen
- Camera in third-person over-shoulder, ~15° above horizontal — reveals the horizon and distant geography; player-rotatable
- `WorldEnvironment` with SSAO, fog, and a dark ambient — the world is not safely lit

**The "Skyrim feel"** is not about first-person camera. It's about:
- Environments that communicate age and weight — stone has mass, tunnels feel real
- Lighting that makes the player feel small and the world feel large
- A world that extends visually beyond where the player is standing
- Atmospheric fog that obscures distance, not just darkness

**Visual references:**
- Veloren — world scale and voxel tone
- The Witcher 3 / Dark Souls — third-person over-shoulder camera, combat readability
- Zelda: Link's Awakening (2019) — low-poly character charm in 3D world
- Kingdom Come: Deliverance — grounded medieval architecture tone (half-timbered buildings, mud, weight)

**Validated by concept art (2026-05-01):** Five concept art sheets generated at 6–8 voxels per meter with low-to-mid poly character models confirm this direction is achievable and correct. Key visual signature confirmed: warm OmniLight3D torchlight against cool voxel stone reads exactly as intended at this voxel scale.

---

## Palette Rules

### Warm palette — safety, firelight, human spaces
- Primary: orange-amber (#E8873A range)
- Secondary: deep red-brown (#8B3A1A range)
- Highlight: pale yellow-white (#F5D06E range)

### Cool palette — night, Aelorin spaces, the uncanny
- Primary: deep blue-black (#1A1F3A range)
- Secondary: slate blue (#3A4A6B range)
- Highlight: pale blue-white (#B8C8E8 range)

### Neutral — stone, earth, metal
- Weathered stone: #6B5A4A to #8B7B6B
- Dark earth: #3A2D1F
- Iron/steel: #8B8B8B to #C8C8C8

### Faction-specific palette accents

Per `/lore/PEOPLES.md` and `/lore/CITY_DESCRIPTIONS.md` regional identities:

- **Eldermark / Iron Chalice**: iron grey, weathered stone, oak brown
- **Caer Brannoch / Tidewarden**: bronze, sea-grey, wet slate, salt-bleached wood
- **Vosskara / Frost Brotherhood**: dark iron, fur browns, the blue-grey of cold dawn
- **Solgrade / Golden Lance**: terracotta red, warm ochre, brass
- **Aelorin**: silver-green, pale wood, soft bioluminescence
- **Dwarven (all three holds)**: forge-warm orange in upper levels, cooling to grey-black at depth
- **Ashen Hand**: muted greys with occasional violet undertones — instruments from nowhere specifically
- **Naergrim**: black obsidian, bone white, no warm tones at all

### The Aeluvain — special case
Pale blue-white, #C8E0F0. Absorbs light and returns it slightly warmer. Its presence shifts the color temperature of nearby pixels subtly. This is a Godot shader effect, not a sprite paint job. Triggered by story flag `aeluvain_present` (Game Two onward). Should not be obvious. Should be felt.

### Total game palette target
32–48 colors across the entire game. Each location uses a subset. Consistent palette is what makes the world feel coherent across hundreds of scenes.

---

## Resolution and Asset Scale

- **Viewport resolution**: 1920×1080 native (no pixel resolution target — 3D renders at display resolution)
- **Voxel block size**: 8 voxels per meter (NOT 1-meter Minecraft cubes — each block is 12.5 cm; noticeably blocky but fine enough to read as stone texture, cobblestone, timber planks)
- **Character models — named characters**: 500–1500 triangles (low-to-mid poly Blender export). This is the look of Yaromir and the Lirien-Thal Aelorin in the concept art sheets — readable silhouette, no per-pixel texture detail, but enough geometry for armor shape and cloth drape.
- **Character models — background NPCs**: voxel-block humanoids built in MagicaVoxel at 8×16 voxels tall. These are the crowd figures visible in the market and courtyard concept sheets. Fast to produce, visually consistent with the world.
- **Portrait art (dialogue)**: 256×320 pixels — painted at this resolution for the 1080p viewport
- **MagicaVoxel canvas**: per asset; buildings typically 32–96 voxels wide (larger for keeps and landmark structures)

For the full art production workflow (MagicaVoxel, Blender, Godot import), see `design/ART_PIPELINE.md`.

---

## Architecture by Region

Visual identity is carried by building construction style as much as palette. These are the dominant construction styles per region, validated by concept art.

### Eldermark (Aldenholt, rural settlements)
- **Half-timbered / timber-frame**: exposed dark oak or elm beams against pale plaster or whitewash — the structural skeleton is visible on the exterior. Upper stories often overhang the street slightly.
- **Stone base, timber upper**: ground floor of heavy cut stone (load-bearing, flood-resistant), upper floors of timber frame. Creates a strong horizontal visual divide.
- **Roofing**: dark grey slate in Aldenholt proper; thatch on rural buildings.
- **Iron details**: hinges, bolt heads, portcullis, door banding — Eldermark buildings show their iron.
- **Scale**: Aldenholt buildings 3–5 stories near the market; single-story cottages at the city fringe and in villages.

### Vosskara
- **Low-profile stone**: walls deliberately squat, wide doors for equipment passage, minimal windows (heat retention).
- **No timber frame**: all-stone, iron-banded. No decorative elements — purely functional.

### Solgrade
- **Terracotta and cream render**: warm ochre render over stone, terracotta tile roofing, arched colonnades. No timber frame.
- **Open frontages**: shops open to the street, no glass — just open arches with awnings.
- **Canal-side construction**: buildings with private dock-access at the rear, stepped embankments of pale stone.

### Aelorin (Lirien-Thal, Sirathiel)
- **Living wood**: structures grow from or merge with silverwood trunks. No cut stone. No timber frame in the human sense — the building and the tree are the same object.
- **Rope and woven-bough bridges**: all horizontal connections between tree-structures are suspended, not built on foundations.

### Dwarven (all three holds)
- **Carved rock**: every surface is stone, cut and shaped, not assembled from blocks. Passage cross-sections are arched. Rune-work in recessed channels.
- **No exterior facades**: dwarven construction goes inward, not outward. The exterior is the mountain face.

---

## Faction Banners and Signage

Banners are how factions claim space in the world. They are always present at gates, keeps, and market squares, and should be among the first assets built for each major location.

- **Eldermark / Iron Chalice**: iron-grey field, white boar or chalice device. Flies from Aldenholt's gatehouse and King Othric's Longhall Keep.
- **Caer Brannoch / Tidewarden**: sea-grey field, silver anchor or wave device.
- **Vosskara / Frost Brotherhood**: black field, white iron cross device. Flies from battlements only — never market spaces.
- **Solgrade / Golden Lance**: terracotta field, brass lance or sheaf device.
- **Aelorin**: no banners — they use carved tree-sigils at entrances.
- **Dwarven holds**: carved stone relief above entrances rather than cloth banners.

Banner physics: cloth banners should use Godot's `SoftBody3D` or a simple AnimationPlayer wind-sway. Don't simulate per-vertex — a simple 2-bone swing animation reused on all banners is sufficient and visually convincing at the camera distance.

---

## Weather and Atmosphere Conditions

Each major location has a default atmospheric condition and 1–2 variants. Weather is not a runtime simulation — it is a per-scene `WorldEnvironment` preset chosen at scene load time.

| Location | Default | Variant A | Variant B |
|---|---|---|---|
| Aldenholt | night / torch-lit | rainy day (wet cobbles, puddles) | foggy morning |
| Caer Brannoch | overcast / salt wind | heavy rain | grey daylight |
| Vosskara | sleet / cold grey | blizzard (near-zero visibility) | cold clear day |
| Solgrade | bright sun | afternoon heat haze | clear dusk |
| Lirien-Thal | filtered silver-green | night / bioluminescent | dawn mist |
| Khorumzad | forge-warm interior | deep-level cold (levels 7-9) | — |
| Ashfields | permanent overcast | ash-haze thick (near Drûn-Khazad) | — |

**Technical implementation:**
- Weather variants are `WorldEnvironment` resources swapped at scene start based on `GameState` flags.
- Rain: Godot `GPUParticles3D` with a large emission plane above the scene, angled slightly for wind.
- Fog: `WorldEnvironment.fog_density` raised; add a `FogVolume` node near ground level for ground fog.
- Puddles / wet cobbles: a secondary material on flat surfaces with higher roughness_texture contrast and reflection enabled.
- Snow: `GPUParticles3D` with slow drift, very low velocity. Snow accumulation on surfaces is a texture variant, not geometry.

---

## Dialogue UI Specification (1920×1080)

The Dialogic 2 layout must be manually configured for 1920×1080. The default layout is sized for small viewports and will be tiny or wrong at 1080p.

**Dialogue box:**
- Width: 1400 px, centered (260 px margins each side)
- Height: 220 px
- Position: bottom-center, 40 px from screen bottom
- Background: `Color(0.08, 0.08, 0.12, 0.88)` — dark blue-black, slightly transparent
- Corner radius: 8 px

**Portrait:**
- Size: 256×320 px (files in `res://assets/portraits/`)
- Position: left of box, anchored to box baseline, 20 px margin from left edge
- The portrait extends above the box top — this is intentional and consistent with RPG convention

**Text area:**
- Left offset: 296 px from box left (portrait 256 + 40 px padding)
- Padding inside text area: 20 px all sides
- Font size (body): 20 px
- Font size (character name label): 22 px
- Characters per line: ~80

**Font:** Use a legible serif or slab serif `.ttf` at 20 px. Avoid pixel fonts — they feel anachronistic against the 3D world.

For full setup steps (layout editor, character definitions, input map), see `design/DIALOGIC_SETUP.md`.

---

---

## Location Visual Identity

Each location's visual signature derives from `/lore/CITY_DESCRIPTIONS.md` and `/lore/WORLD_GEOGRAPHY.md`. What follows is implementation-focused — the feel and technical notes for each Game One location.

### Aldenholt (Act I hub)
Largest walled city in the world. Stone walls three men thick. Market district never fully closes. Game One opens here at night during Roland's chase.

- **Atmosphere**: grand, political, slightly oppressive. Night cycle matters
- **Architecture**: half-timbered upper stories over stone ground floors. The city shows its age in patched mortar, worn cobbles, iron hinges dark with rust.
- **Tiles**: cobblestone (varied grey stone, not uniform), heavy stone walls, iron-banded doors, market awnings, torch sconces every ~6m on iron brackets
- **Market stall color**: striped canvas awnings in fully saturated colors — red, green, blue, yellow — against the neutral grey-stone backdrop. This pop of color is intentional: the market is the city's life. Use it as a quick visual read that you are in a populated, functioning district.
- **Lighting**: torch-lit streets at night. Loremaster's Archive: windowless, lamp-lit, dust-particle effects. Iron Chalice chapel: warm altar-lit interior, single focused light source on the pommel
- **Key detail**: the chase route through the alleys uses deep shadows and cool palette — Roland is hunted here before the player understands why

**Aldenholt landmark locations (each needs a distinct visual signature):**

- **King Othric's Longhall Keep**: A fortified great hall complex — stone gatehouse and towers, with a half-timbered great hall built inside the curtain wall. Royal banners of Eldermark (iron-grey field, white boar) fly from the keep towers and gate arch. The longhall interior is large, dark-timbered, firepit-lit: the power center of the kingdom should feel old and slightly oppressive.

- **River Confluence Docks** (where Aldwater meets Silverthread): Voxel quays of heavy stone, barge moorings, wooden crane jibs for cargo. Two rivers meeting means two different current colors — use slight water-shader variation. Dock warehouses: stone lower, timber-frame upper, with loading doors at upper-floor level for crane access. This is where contraband moves, where the Brotherhood has informants, where the world feels transactional.

- **Temple of Aldrath & Aeadis** (dual shrine): A single stone building housing two facing shrines. Over the main entrance: a war hammer and a wheat sheaf carved in relief — not painted, carved, because these gods are old enough that paint would be presumptuous. Interior: Aldrath's side has forge-warm light (OmniLight3D, amber); Aeadis's side has cool daylight from a high window. The two light sources should be visibly distinct, separated by the central aisle.

- **Aldenholt Night Market**: The market never fully closes. Night variant: warm amber-orange from hundreds of small torch and lantern sources. The palette shifts entirely to the warm side — no blue-grey in the market at night. Vendor stalls, open crates, braziers for warmth. The single scene in the game where the warm palette dominates at a large scale without any cool counterpoint. It should feel almost excessive — that warmth is the point.

### Caer Brannoch
Cliff-fortress city in two parts: upper (headland fortress) and lower (sea level docks). Sea-lifts on counterweight systems built by dwarven engineers two centuries ago.

- **Atmosphere**: wet, windswept, naval. Salt and stone
- **Tiles**: barnacled lower-city walls, rope-and-pulley sea-lift machinery, slick stone, wet wood planking
- **Lighting**: grey filtered light by day. Lighthouse beacon at headland tip visible in background. Lantern-lit quay at night
- **Signature**: the upper/lower city height split. The camera should occasionally reveal vertical scale by panning

### Vosskar-on-the-Iron (Vosskara capital)
River-bend fortress. Three sides of water defense. Iron-banded walls. Yaromir's citadel deliberately squat and ugly — low profile for defense.

- **Atmosphere**: cold, garrison-functional, zero ornament
- **Tiles**: iron-banded stone, wide doors for equipment, low ceilings for heat retention
- **Lighting**: hearth-warm interior contrasts sharply with sleet-grey exterior. The war council chamber is underground — torch-lit only
- **Atmosphere detail**: ash-haze visible from eastern wall on clear days. Godot particle effect — sparse, slow drift, low-opacity grey

### Solgrade (merchant republic, no walls)
Terracotta roofs throughout. Warm orange-red distinctive from a distance. No walls — political statement. The Council of Twelve Houses governs.

- **Atmosphere**: Mediterranean, open, commercial. Crisp sun shadows
- **Architecture**: cream-rendered stone with terracotta tile roofing. Arched colonnades along main streets. Canal-side buildings have stepped stone embankments at water level and private dock access at their rear.
- **Tiles**: terracotta rooftiles, banking house facades, colored awnings, open market courtyards, pale stone canal embankments
- **Lighting**: bright daylight is the default. Shadows crisp, not soft. Council Hall has twelve equal entrances — visual symmetry is the point

**Solgrade Grand Canal**: The defining feature of Solgrade is its canal network — flat-bottomed trade barges and passenger gondolas moving between quays. The water reflects the warm terracotta architecture; use Godot's screen-space reflections or a reflection probe to capture this. Canal-side market stalls have striped awnings in the same palette as Aldenholt's market but warmer: more yellow and red, fewer blues. The canal is Solgrade's main street.

### Lirien-Thal (Aelorin capital, deep Greatwood)
Built into the canopy of silverwood trees. The trees are ancestors — elder Aelorin who completed the Aelthiren; their hair became leaves, their bodies bark.

- **Atmosphere**: ancient, beautiful, melancholy. Every tree was someone
- **Tiles**: massive silverwood trunks (32×96 voxels or wider at the base), root-bridges, hanging lanterns, woven-bough walkways at canopy height
- **Lighting (day)**: filtered silver-green from above. No direct sun — the canopy is dense. The ambient is cooler and greener than any human city.
- **Lighting (night)**: the bioluminescence is DRAMATIC, not subtle. Concept art confirms: the blue-white glow from silverwood bark and Aelorin lanterns is the dominant light source at night, bright enough to cast visible shadows and read clearly at the game's camera distance. Use `OmniLight3D` nodes at the trunk surfaces with `color: Color(0.7, 0.85, 1.0)` (blue-white) and energy 1.5–2.0. The overall scene at night should read primarily in blue-white with deep forest shadow between lit areas. This is not a safe warm glow — it is alien and beautiful.
- **CRITICAL**: the silverwood trees should look different from normal trees. Faces in the bark — not obvious, subtle. The player who looks will see them. Implementation: secondary normal-map detail layer on tree trunk surfaces, only visible when the player is close. At distance, reads as rough bark. Close up, reads as a sleeping face.

### Sirathiel-by-the-Sea (Aelorin coastal city — entry point for Greatwood arc)
The only Aelorin city admitting humans without special escort. Pale coastal stone with mother-of-pearl inlay work.

- **Atmosphere**: faintly iridescent in sunlight. More architecturally visible and approachable than Lirien-Thal
- **Lighting**: cleaner and more open than Lirien-Thal — the most welcoming Aelorin city should feel accordingly

### Karaz-Dûn (northern dwarven hold — Spine of the World)
The forges have not gone cold in four thousand years. Dragon-Watcher order headquartered here.

- **Atmosphere**: warm year-round from forge heat rising through rock. Prosperity, craft, tradition
- **Tiles**: carved stone passages, rune-lit wall sconces, forge-glow from side chambers
- **Lighting**: orange-amber dominant in upper levels. Cooler in deeper treasury and records vault

### Khorumzad (central dwarven hold — primary Game Two location)
Nine dig levels below the great hall. Per lore: Level 4 is where gold-hunger contamination begins. Levels 4-6 contain Second Age construction predating the dwarves — unknown architect, wrong angles. Level 8 has air that has not moved in centuries.

- **Atmosphere descent rule**: light temperature gets colder with each level. By Level 8, the only warm light is what the party carries
- **Architecture transition**: Levels 1-3 are dwarven (carved stone, runework). Levels 4-6 are Second Age (pale stone, unknown style, subtly wrong proportions). Levels 7-9 are older and stranger still
- **CANONICAL NOTE**: The Vault of Aen-Vael is below Khorumzad in the Spine of Mira — NOT below Drun-Khazad. The Grand Alliance placed it as far from Drun-Khazad as the world allows. Khorumzad is the primary Game Two location, not a side trip.

### The Underway (dwarven tunnel network beneath the Spine)
Connects all three holds. Dotted-line on the world map. Dagna marks every junction she passes through out of habit.

- **Atmosphere**: ancient infrastructure, well-maintained, dimly lit. The Underway feels safe in a way the surface does not always
- **Tiles**: vaulted stone, regular spacing, occasional waystation alcoves with supply caches
- **Lighting**: low warm runelight. Not dark — maintained. The dwarves use this route constantly

### Mor-Vethrin (Naergrim city — eastern Vrothmor Peaks, Thal)
Built into black obsidian cliff face. No windows facing west. Single gate with a bone arch — actual bone from something large, mortared when the city was founded.

- **Atmosphere**: vertical sheer-face construction, narrow passages, no wasted material anywhere
- **Tiles**: black obsidian, bone-mortared seams, volcanic-vent heating grates
- **Lighting**: no warm tones. The Naergrim do not use firelight indoors. Pale, cold, even illumination from sources the player cannot identify
- **Serethi's audience chamber**: bare except for one carved chair and one carved bowl. Visually silent

### The Ashfields (Act IV — the binding site)
Eastern Mira beyond the Spine. Grey dead ground, thin soil over ancient lava beds, permanent ash-haze drifting from Drun-Khazad far across the Shroud Sea.

- **Atmosphere**: thin, muted, perpetually overcast. Roland grew up near here. The haze is normal to him.
- **Tiles**: cracked grey ground, occasional basalt outcropping, sparse dead grass
- **Lighting**: the binding site atmospheric shift — `WorldEnvironment` ambient tint and fog color shift slightly toward orange during the Crown assembly ritual sequence. Subtle. The world responding to something being made right.

### The Sorrowmarsh (referenced; possibly visited in side quests)
Dead wetland. Site of the Second Age battle that broke Mordvar's first host. Nothing grows. Ghost-lights at night.

- **Tiles**: black mud, dead trees bleached white at wrong angles, standing water with no reflection
- **Ghost-lights**: small blue-green Godot point-lights, low energy, slow drift. Cannot be approached — slight repulsion behavior near player

### Drun-Khazad (Game Three — visual planning now for palette continuity)
Active shield volcano. Permanent lava glow. The Aescstol (Ash Throne) and the Hollow Hearth are within the caldera. The Vault of Aen-Vael is NOT here.

- **The campfire is safety. The volcano is not.** This visual inversion is deliberate — instead of warm campfire against cool night, the volcano is hot orange-red against grey-black ash sky. When players first see Drun-Khazad on the horizon, they should feel the wrongness of the campfire's warmth weaponized
- Not built for Game One but palette and shader planning must happen now for consistency

---

## Character Visual Design

Per `/lore/CHARACTERS_PROTAGONIST.md`, `/lore/CHARACTERS_COMPANIONS.md`, and the relevant `BACKSTORY_*.md` files.

### Roland Ashford
- Lean and weathered beyond his years — the Ashfields age people
- Brown hair cut short, always slightly too long by the time he gets around to cutting it again
- Grey eyes. Scar on his jaw from a training accident at fourteen — he stopped noticing it long ago
- Worn but maintained gear. Former knight — armor good quality but repaired multiple times
- Carries himself like someone trained to stand straight who has slowly stopped bothering
- No dramatic colors: browns, dark greys, cream of well-worn linen. He moves through spaces without announcing himself
- **Idle animation**: slight weight shift, one hand near his belt where a weapon would be. Habit.

### Orion Farr
- 22 at Game One start. Short, compact, sun-dark, constantly moving
- Sailor's practical clothing. Brotherhood insignia present but not prominent
- **Idle cue**: subtle head-turn glance when entering a new scene — assessing exits. Corvus finds it annoying. Roland finds it useful.
- Moves economically. No wasted motion.

### Dagna Irontrack
- Compact even for a dwarf. Iron-grey braids wound tight against her skull
- Burns on her left forearm from a vent-sampling accident — she considers them professional credentials
- Always has chalk on her hands. Subtle white smudge texture on her sprite's hand area
- Dragon-Watcher gear is functional: chalk marks on belt pouches, measuring equipment
- **Idle cue**: occasional pause + brief gesture toward a wall when entering a new corridor. She marks junctions out of habit, even in towns, even when no one asked her to chart anything

### The Ashlord (visual planning for Game Three — do not build yet)
Per `/lore/CHARACTERS_NPCS.md` and `/lore/BACKSTORY_CAERITH.md`:
- Obsidian mask: smooth, expressionless, black. No decoration whatsoever
- Robes: ash-grey with Aelorin structural elements the player may not consciously recognize but Seren would
- Movement: precise and ancient simultaneously. Not jerky like the Ashfallen. Old.
- **The reveal**: when the mask cracks, beneath it is an aged Aelorin face — silver hair, amber eyes faded almost to white. The expression is relief, not anguish.
- **Implementation**: the mask crack is a single Godot animation event — mask sprite replaced by face sprite on the exact frame the mask breaks. This must be the most carefully timed animation in the game. Do not placeholder it.

### Future companions (for forward-compatible sprite planning)
- **Corvus** (Game Two): slight, dark-skinned, always slightly pale. Hair going white in patches from 27 onward — the first permanent cost of magic. By Game Three: eye color altered, aging visibly accelerated.
- **Seren** (Game Two): tall for an Aelorin. Silver-grey hair kept practical. Amber eyes. Clothes suited for moving through varied terrain, not ceremonial dress. Carries a bow she made from Third Glade silverwood.
- **Aldric Vane** (Game Three): broad-shouldered, scarred hands from the forge, grey starting at his temples. Looks exactly like what he is — a man who has spent twenty years hammering metal and would rather be doing that.

---

## Animation Priority List

Build in this order:

1. Roland — walk cycle (8 directions)
2. Roland — idle (weight-shift, hand-near-belt)
3. Roland — interact (reaching toward something)
4. Generic NPC — stand/idle (reused widely)
5. Combat: Roland attack + timing animation
6. Combat: enemy attack + telegraph animation
7. Combat: block success + block fail
8. Orion — walk cycle + idle (with exit-glance cue)
9. Dagna — walk cycle + idle (with chalk-mark gesture)
10. Enemy type: Ashfallen soldier (most common Game One enemy)

Do not animate Mordvar until Game Three. Do not animate the Ashlord until Game Three. Do not placeholder-animate either — both require specific attention and building placeholder habits produces lasting bad results.

---

## Godot 3D Implementation Notes

### Lighting setup per scene (3D)

```gdscript
# Typical 3D cave scene structure:

WorldEnvironment:
  background_mode: Sky (or Color for underground)
  ambient_light_color: Color(0.05, 0.06, 0.12)  # very dark cool blue
  ambient_light_energy: 0.3
  ssao_enabled: true          # ambient occlusion — cheap, always on
  fog_enabled: true
  fog_density: 0.02           # higher underground, lower outdoors
  sdfgi_enabled: true         # global illumination — disable for low-end hardware

DirectionalLight3D:           # sun/moon
  color: Color(0.85, 0.82, 0.95)   # cool moonlight
  energy: 0.6
  shadow_enabled: true

OmniLight3D:                  # per warm source — campfire, torch, forge
  color: Color(0.91, 0.53, 0.23)   # warm orange #E8873A
  energy: 2.0
  range: 8.0
  shadow_enabled: true
```

### Voxel terrain lighting

Voxel surfaces respond to 3D lighting naturally — no normal maps required on voxel terrain because each voxel face is a real 3D surface. `VoxelMesherCubes` produces hard-edged cubic faces that catch directional and point light with strong, readable shadows — the step faces on a cliff or hillside read clearly as depth.

Normal maps ARE still valuable for:
- Character models (Roland's armor, cloth textures)
- Props that need surface detail (ancient stone archways, wooden doors)
- Large flat MagicaVoxel surfaces that would otherwise look too uniform

### Shader — The Aeluvain Effect (Game Two onward)

When `GameState.aeluvain_present` is true, a canvas-level shader shifts color temperature — the scene's cool tones become marginally less cold. Imperceptible on first viewing. Retroactively noticeable on replay.

Should NOT be obvious. Should be felt.

### Shader — The Hollow (Game Three primarily)

When Mordvar's presence is felt: desaturation toward grey, slight reduction in light energy across the scene, a sense that color itself is leaching. This is absence visualized — not evil aura coloration. Adjustable intensity via a canvas shader parameter keyed to proximity to Mordvar.

### Shader — Ashfallen Recognition

When the player encounters an Ashfallen wearing a familiar face, that sprite renders with subtle wrongness: slightly off color balance, shadows that do not quite match the scene's lighting direction. The player should feel something is off before they consciously identify what.

---

## Music and Sound Principles

For composer brief when that time comes.

- Each kingdom has a distinct musical identity: Anglo-Saxon for Eldermark, Celtic for Caer Brannoch, Slavic for Vosskara, Mediterranean for Solgrade, ancient vocal for Aelorin
- Dwarven holds: forge percussion, deep horns, the resonance of stone
- The Ashen Hand: absence of regional identity — instruments from nowhere specifically
- **Mordvar has no theme. He is the silence between other things.**
- The Aeluvain hums at a frequency only Aelorin can hear. Sub-audible tone in scenes where it is present. Only consciously heard on headphones. Only consciously named by Seren.
