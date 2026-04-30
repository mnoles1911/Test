# Art Direction — Mira-Thal: Game One
## Visual production reference

> This document covers visual implementation only. For story, characters, world descriptions, or location lore, go to `/lore`.

---

## Art Approach — CONFIRMED: 3D Voxel

**Engine:** Godot 4.3, 3D mode. NOT 2D.  
**Style:** Voxel world (Veloren / Cube World aesthetic) with Skyrim-scale atmosphere.  
**Full migration plan:** `design/3D_VOXEL_MIGRATION.md`

The pivot from 2D pixel art to 3D voxel was confirmed. All 2D scene files (World.tscn, Player.tscn) will be replaced with 3D equivalents. All logic autoloads (GameState, Journal, Inventory, etc.) are unchanged.

---

## North Star Aesthetic

**Veloren meets Skyrim.** The campfire knight image from Milestone 1 still defines the MOOD — that specific feeling of warm light against ancient stone, a lone figure at rest in a hostile world. In 3D voxel, this translates to:

- A campfire rendered as a `PointLight3D` with `CampfireFlicker3D.gd`, casting real volumetric glow across cave voxels
- Cave walls built from hand-assembled MagicaVoxel blocks, each face catching light differently
- Roland represented as a low-poly 3D model or billboard sprite — small against the environment, not filling the screen
- Camera at ~50° elevation, fixed angle (Hades / Diablo 3 camera) — reveals depth without going first-person
- `WorldEnvironment` with SSAO, fog, and a dark ambient — the world is not safely lit

**The "Skyrim feel"** is not about first-person camera. It's about:
- Environments that communicate age and weight — stone has mass, tunnels feel real
- Lighting that makes the player feel small and the world feel large
- A world that extends visually beyond where the player is standing
- Atmospheric fog that obscures distance, not just darkness

**Visual references:**
- Veloren — world scale and voxel tone
- Cube World — character art style
- Hades — camera angle and follow behavior
- Zelda: Link's Awakening (2019) — low-poly character charm in 3D world

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
- **Voxel block size**: 8–16 units per block (NOT 1-meter Minecraft cubes — fine-grain detail)
- **Character models**: 200–500 triangles (low-poly), or 32×48 pixel billboard sprites if using Sprite3D
- **Portrait art (dialogue)**: 256×320 pixels — larger than before, room for painted detail
- **MagicaVoxel canvas**: per asset; buildings typically 32–64 voxels wide

For the full art production workflow (MagicaVoxel, Blender, Godot import), see `design/ART_PIPELINE.md`.

---

## Location Visual Identity

Each location's visual signature derives from `/lore/CITY_DESCRIPTIONS.md` and `/lore/WORLD_GEOGRAPHY.md`. What follows is implementation-focused — the feel and technical notes for each Game One location.

### Aldenholt (Act I hub)
Largest walled city in the world. Stone walls three men thick. Market district never fully closes. Game One opens here at night during Roland's chase.

- **Atmosphere**: grand, political, slightly oppressive. Night cycle matters
- **Tiles**: cobblestone, heavy stone walls, iron-banded doors, market awnings, torch sconces every ~6m
- **Lighting**: torch-lit streets at night. Loremaster's Archive: windowless, lamp-lit, dust-particle effects. Iron Chalice chapel: warm altar-lit interior, single focused light source on the pommel
- **Key detail**: the chase route through the alleys uses deep shadows and cool palette — Roland is hunted here before the player understands why

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
- **Tiles**: terracotta rooftiles, banking house facades, colored awnings, open market courtyards
- **Lighting**: bright daylight is the default. Shadows crisp, not soft. Council Hall has twelve equal entrances — visual symmetry is the point

### Lirien-Thal (Aelorin capital, deep Greatwood)
Built into the canopy of silverwood trees. The trees are ancestors — elder Aelorin who completed the Aelthiren; their hair became leaves, their bodies bark.

- **Atmosphere**: ancient, beautiful, melancholy. Every tree was someone
- **Tiles**: massive silverwood trunks (custom 32x96 tiles or wider), root-bridges, hanging lanterns of soft light, woven-bough walkways
- **Lighting**: silverwood has faint bioluminescence at night. No torches. Filtered silver-green by day
- **CRITICAL**: the silverwood trees should look different from normal trees. Faces in the bark — not obvious, subtle. The player who looks will see them. Implementation: secondary detail layer on tree sprites, only visible when the player is close

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
- **Lighting**: the binding site atmospheric shift — CanvasModulate warms slightly toward orange during the Crown assembly ritual sequence. Subtle. The world responding to something being made right.

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

Voxel surfaces respond to 3D lighting naturally — no normal maps required on voxel terrain because each voxel face is a real 3D surface. The Transvoxel mesher produces geometry that catches directional and point light correctly.

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
