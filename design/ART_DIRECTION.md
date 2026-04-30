# Art Direction — Mira-Thal: Game One
## Visual production reference

> This document covers visual implementation only. For story, characters, world descriptions, or location lore, go to `/lore`.

---

## North Star Image

The campfire knight image is the visual target for this project. Every art decision should be checked against it.

What makes it work:
- Single dominant warm light source (campfire) against cool ambient (moonlight/night)
- High contrast between lit and unlit areas — shadows are deep, not grey
- Pixel art with painterly texture — rocks have color variation and dithering, not flat fills
- Detail hierarchy: the knight and fire are sharp; the cave background recedes with looser pixels
- Environmental storytelling: sword laid aside, posture at rest, alone but sheltered

This image is the visual benchmark for Milestone 1. When the first walkable scene vibes like this image in lighting and camera angle, the technical pipeline is proven.

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

## Pixel Resolution

- **Character sprites**: 32×48 pixels native
- **Environment tiles**: **32×32 pixels** (confirmed — provides richer tile detail at this viewport size)
- **Native scene resolution**: 320×180 (scales up to fill screen via Godot viewport)
- **Portrait art (dialogue)**: 64×80 pixels native — larger than sprites, more facial detail

At 320×180 with 32×32 tiles: 10 tiles across, ~5.6 tiles tall. This matches Sea of Stars' visible tile density.

For the full art production workflow, see `design/ART_PIPELINE.md`.

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

## Art Approach Decision (confirmed)

**2D pixel art in Godot 4.3. Not 3D.**

The "2.5D" look is an art style achieved by how tiles and sprites are drawn — not by a 3D camera, isometric projection, or 3D engine. This is the same approach as Sea of Stars and Octopath Traveler.

- Terrain and rooms: TileMap with 32×32 tile atlas
- Background layers: hand-painted single assets (not tiled)
- Characters: individual Sprite2D nodes driven by AnimationTree
- Lighting depth: Godot PointLight2D + normal maps on tiles and sprites

Staying 2D means: all existing GDScript code is unchanged, the viewport/camera setup is unchanged, and lighting already works correctly via the campfire system built in Milestone 1.

Full workflow: `design/ART_PIPELINE.md`

---

## Godot Implementation Notes

### 2D lighting setup per scene

```gdscript
# Conceptual structure for a typical night scene (Milestone 1 target):

WorldEnvironment:
  ambient_light: low intensity, cool blue  # moonlight baseline

CanvasModulate:
  color: #1A1F3A  # ~80% darkness for exterior night scenes
  # Adjust per location — underground gets darker and colder at depth

PointLight2D:  # per warm source — campfire, torch, forge
  color: #E8873A  # warm orange
  energy: 1.2 - 1.5
  shadow_enabled: true
  texture: soft-edge glow texture  # custom, not default
```

### Normal maps on sprites

Rocky terrain and stone walls should have normal maps so they react to 2D point lights. This is what creates the painterly lighting depth in the reference image — light raking across stone texture creates micro-shadows.

In Aseprite: export sprite + normal map. In Godot: assign normal map to Sprite2D node alongside main texture.

Priority: terrain tiles, cave walls, Roland's armor sprite. Lower priority: NPCs, props.

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
