# AI-Driven Asset Pipeline — Game One

> Companion to `design/ART_PIPELINE.md` (the original manual workflow) and `tools/AI_TEXTURE_PROMPTS.md` (the existing terrain texture pipeline). This doc covers the AI-heavy pipeline for **3D characters, enemies, props, and concept reference art**, plus AI-generated sound effects.

> **When to read this doc:** Before authoring any new character, enemy, or non-trivial 3D asset. Two prompts are provided per asset — Version A is for image-to-3D conversion (clean T-pose, white background), Version B is for in-scene concept reference (dynamic pose, mood). Pick the version that matches what you need.

---

## Purpose

The original `ART_PIPELINE.md` assumes characters are built by hand in MagicaVoxel + Blender. That works but is slow (~2 hours per character). Combined with image generation tools (Nano Banana 2) we already use successfully in `tools/AI_TEXTURE_PROMPTS.md`, plus AI 3D model generation and auto-rigging, we can cut character authoring to ~45 minutes per asset while preserving the project's voxel aesthetic.

This document is the canonical reference for that AI-heavy pipeline. The original `ART_PIPELINE.md` stays valid for anything not covered here (building tiles, simple props, animated UI elements).

---

## Pipeline overview

```
┌─────────────────────────────────────────────────────────────────┐
│  CHARACTER / ENEMY / HUMANOID NPC AUTHORING                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [1] Concept image                                              │
│      Nano Banana 2 — Version A prompt (T-pose, white BG)        │
│      Output: 1024×1024 PNG reference                            │
│                                                                 │
│  [2] AI 3D generation                                           │
│      Meshy v4 (image-to-3D, "stylized" preset)                  │
│      Output: smooth_<asset>.glb with PBR textures               │
│                                                                 │
│  [3] Blender bridge                                             │
│      a. Import .glb                                             │
│      b. Mesh → Clean Up → Merge by Distance                     │
│      c. Symmetrize (X axis)                                     │
│      d. Bake textures → vertex colors                           │
│      e. Add Remesh modifier, Blocks mode, octree depth 6        │
│      f. Optional: palette-snap script                           │
│      g. Export <asset>_voxel.glb                                │
│                                                                 │
│  [4] Mixamo auto-rig + animation                                │
│      a. Upload to mixamo.com                                    │
│      b. Place auto-rig markers                                  │
│      c. Download rigged + standard animations                   │
│      d. Save to assets/models/<asset>.glb                       │
│                                                                 │
│  [5] Custom animations (only when Mixamo lacks them)            │
│      a. Cascadeur for keyframe + AI auto-pose work              │
│      b. OR Move.ai webcam mocap for performance capture         │
│      c. Merge into the rigged .glb in Blender                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Total time per character: ~45 minutes** (down from ~2 hours).

For non-character assets (props, decals), the pipeline collapses to: Nano Banana → Meshy → Blender voxelize → drop in `assets/voxel/` (~15 minutes).

---

## Tools

| Tool | Role | Cost (May 2026) | When to use |
|---|---|---|---|
| **Nano Banana 2** (Gemini Image) | Concept reference, 3D-input refs | ~$0 (paid AI Pro plan) | Every visual asset starts here |
| **Meshy v4** (meshy.ai) | Image-to-3D for characters/props | ~$20/mo | Hero characters, enemies, complex props |
| **Tripo 2.0** (tripo3d.ai) | Fast image-to-3D | Free tier covers solo dev | Background NPCs, prototyping, fast iteration |
| **Hyper3D Rodin** | High-quality stylized 3D | Paid, slower | Reserve for hero models if Meshy quality lags |
| **Sloyd.ai** | Parametric props, modular building parts | Free tier | Furniture, repeated building geometry |
| **Blender 4.x** | Bridge: voxelize, retopo, rig touchups, vertex bake | Free | Always — every asset passes through here |
| **Mixamo** (Adobe) | Humanoid auto-rig + animation library | Free | Default for any humanoid character |
| **Cascadeur** | Custom animation with AI auto-pose | Free tier | Custom anims Mixamo doesn't have (spear charge, throw release) |
| **Move.ai** / **RADiCAL** | Webcam mocap | Paid, monthly | Performance capture for unique anims |
| **MagicaVoxel** | Hand-built voxel models | Free | Weapons, simple props, building tiles — keep using for these |
| **ElevenLabs Audio** | SFX + voice generation | Paid, per-character | Goblin vocals, custom SFX needing tonal consistency |
| **Suno v4** / **Udio** | Music + ambient | Paid | Music tracks |
| **freesound.org** | CC0 SFX library | Free | Generic whoosh / thump / dust |
| **Aseprite** | Portrait dialogue art | ~$20 | Existing pipeline — unchanged |

---

## Meshy generation settings

The canonical Meshy configuration for Game One characters. Lock these on every generation unless you have a specific reason to deviate.

| Setting | Value | Why |
|---|---|---|
| **Mode** | Standard | Low-poly beta produces sparse vertex meshes; the vertex-color bake (Blender Step 3.d) gets coarse color sampling that visibly bands across the chunky cubes after Remesh. Standard's denser vertex layout interpolates cleanly into the voxelized output. |
| **Preset / style** | Stylized | Flatter saturated colors that survive the texture-to-vertex bake. Realistic preset's PBR detail is wasted — we throw the textures away in Step 3.g. |
| **Target tri count** | 3,000–8,000 | After Blender Remesh at octree depth 6, output lands at 2,500–4,000 tris — well within Mixamo's 10k cap with headroom. Standard mode hits this range natively; low-poly often produces 500–2,000 source tris, which after Remesh drops below Mixamo's auto-rig sweet spot of 2,000+ and starts misplacing wrist/elbow markers. |
| **Texture resolution** | 4K PBR | All channels (albedo, normal, roughness) ship from Meshy. We bake only the **albedo** into vertex colors in Step 3.d — normal and roughness are discarded with the rest of the texture pack at export. Generating at 4K vs 2K costs only a small credit bump and gives meaningfully cleaner vertex-color sampling. |
| **Topology** | Quads preferred | Blender's importer triangulates on the way in — both quad and tri Meshy output work. Quads are marginally cleaner for symmetrize / merge-by-distance steps. |
| **Rig / animation in Meshy** | OFF | Meshy's built-in rig is destroyed by Blender Remesh (skin weights live on vertices; Remesh rebuilds every vertex). Rigging happens downstream in Mixamo. Skipping it on the Meshy side saves credits. |

### Generation cost estimate

For a 6-character v1 cast (Roland, Goblin, future Ashfallen, Wolf, Bear, generic NPC) at Standard + 4K + no rig: ~30–60 Meshy credits total. Small money relative to the Blender + Mixamo bridge time per character.

### When to deviate

- **Low-poly beta** — only worth testing once on a simple asset (the Goblin is a good candidate: simple silhouette, distinct color). Generate the same character in both modes, run both through Blender Remesh, compare vertex-color bake quality side by side. If low-poly's bake looks identical to standard's, switch — you save credits and generation time. If color banding shows up on the chunky output, stay on standard.
- **Quick prototypes** — for one-off concept tests where the asset will be thrown away, low-poly + 2K is fine. Don't use that output for production assets.

### Caveat on the beta tag

Meshy's low-poly mode is labeled beta as of May 2026. Beta features ship with unknown quality variance — review the changelog before each generation pass and re-test if Meshy reports significant updates to the algorithm.

---

## How to use these prompts

The prompts below mirror the **split-prompt pattern** from `tools/AI_TEXTURE_PROMPTS.md`:

1. **System prompt** — paste once into the system / style / context field of your image generator. Carries shared style, framing, and game context.
2. **Per-asset prompts** — short pure-descriptive blocks. Paste one into the main prompt field for each asset.

### Why split

When system instructions and per-asset details are combined into one prompt, Nano Banana 2's recitation filter rejects every prompt. The filter trips when one block stacks too many specific signals at once. Splitting the load is the only thing that works in practice. (Discovered while standing up `tools/AI_TEXTURE_PROMPTS.md`; same rule applies here.)

If your generator has no separate system field, paste the system prompt first then the per-asset prompt as one continuous block.

### Two versions per asset — what they're for

- **Version A — 3D-conversion input.** Clean T-pose, pure white background, no environment, no shadows, no held props, even lighting. Optimized to feed Meshy or Tripo for image-to-3D conversion. The output is meant for the pipeline, not for human aesthetic enjoyment.
- **Version B — Concept and mood reference.** Dynamic pose, in-environment, atmospheric lighting, full scene composition. Optimized to inform design decisions, validate aesthetic, share with collaborators, or seed AI 3D when you want a more characterful pose at the cost of rig usability.

When in doubt: **Version A** for any asset you're going to put in the game. **Version B** for anything you're sharing in a design doc, pitch deck, or moodboard.

---

## SYSTEM PROMPTS

### System prompt — Version A (3D-conversion input)

*Paste this once into the system / style / context field when generating image-to-3D inputs.*

> You are generating clean stylized 3D character reference images for an image-to-3D conversion pipeline (Meshy AI or Tripo). Output: 1024×1024 PNG, pure white background, neutral T-pose with arms straight out from the shoulders, legs straight and shoulder-width apart, palms down, no head tilt, no cape or fabric flow that obscures the silhouette.
>
> Art style: Stylized low-poly fantasy reminiscent of Veloren, Trove, or Hytale — chunky proportions but clean topology suitable for auto-rigging in Mixamo. Flat-shaded surfaces with rich vertex-color variation. Warm saturated palette aligned with painterly medieval fantasy. No texture detail finer than what could survive being voxelized at approximately 18 voxels per meter character height. Even front-facing studio lighting, no cast shadows on the floor, no atmospheric effects.
>
> Pose requirements: Pure T-pose, fully symmetric, arms at exactly 90 degrees from the body, legs vertical, palms facing the floor. The model must be ready for skeletal auto-rigging — anything occluding limb visibility breaks the rig step. No held weapons, no held props, no jewelry that drapes off the body, no hair flowing past the shoulders.

### System prompt — Version B (concept and mood)

*Paste this once into the system / style / context field when generating concept reference art.*

> You are generating concept and mood reference images for a 3D voxel narrative RPG titled Game One, set in the world of Mira-Thal. The aesthetic is "Veloren meets Skyrim" — chunky voxel terrain at 6 voxels per meter, slightly higher-resolution voxel characters at 18 voxels per meter, real-time third-person over-shoulder camera, painterly medieval fantasy palette.
>
> Style references: blend the cubic voxel charm of Minecraft and Trove with the cinematic atmosphere of Witcher 3 and the warm directional lighting of Lord of the Rings. Heavy use of warm-cool palette splits — warm orange firelight against cool blue night, warm afternoon sun against cool stone shadow.
>
> Composition: cinematic framing with the main subject in the foreground or mid-ground, environment context visible behind, characters at slightly higher voxel resolution than terrain so they read as the protagonists of the scene. Saturated colors where they pop (blood, fire, magic) against muted natural tones (dirt, stone, foliage).
>
> No HUD elements, no UI overlays, no text annotations on the image. Output: 1920×1080 landscape PNG.

---

## PER-ASSET PROMPTS

For each asset: filename to save as, Version A (3D-conversion), Version B (concept). Save outputs to `assets/concept/<category>/` so they're tracked but separated from production assets.

---

### Roland — protagonist

**Save as:** `roland_a.png` and `roland_b.png` in `assets/concept/characters/`

#### Version A — 3D-conversion input

```
Male warrior, mid-twenties, athletic build, 1.8 meters tall. Short
chestnut-brown hair. Determined but weary expression. Wearing chainmail
gambeson over dark leather armor with iron studding. Fur-trimmed cloak
hanging flat down the back (not flowing). Brown leather boots. Empty
sword scabbard at left hip (visible but no sword in hand). Color
palette: warm browns, iron grey, cream chainmail, deep burgundy cloak.
Strict T-pose, palms flat to the floor, no held items.
```

#### Version B — Concept and mood

```
Male warrior Roland, mid-twenties, weathered but unbroken, in a
late-afternoon forest clearing. Standing in a balanced ready stance
with right hand resting on the pommel of a sheathed sword, left hand
loose at his side. Wearing chainmail gambeson over dark leather armor,
fur-trimmed burgundy cloak catching a slight breeze. Warm sunset light
streaming through chunky voxel pine trees behind him casting long
shadows. Mid-shot framing from slightly low angle. Determined
expression looking off-frame to the right as if scanning the treeline.
Painterly voxel aesthetic: chunky cubic terrain, slightly higher-
resolution character. The mood is "veteran of a hard road, not done
yet."
```

---

### Goblin — v1 enemy

**Save as:** `goblin_a.png` and `goblin_b.png` in `assets/concept/enemies/`

#### Version A — 3D-conversion input

```
Lanky humanoid creature, 1.8 meters tall, slight forward hunch in the
shoulders only (T-pose otherwise pure). Sickly green skin in three
tones: dark moss, mid green, pale highlight. Bald square skull with
two small bright glowing green eyes — the only visible facial features.
Bare-chested, dark brown leather loincloth, bare feet with three-toed
stylized claws. Wiry arms ending in three-fingered hands. No weapons,
no jewelry, no held props. Color palette: dark moss to pale green
skin, dark brown loincloth, bone-white claws.
```

#### Version B — Concept and mood

```
A pack of three voxel goblins emerging from the shadows at the edge
of a torchlit forest clearing at night. Sickly green skin, bald
square skulls, bright emissive green eyes that glow faintly in the
darkness — the only feature visible on their nearly-silhouette
bodies. Hunched predatory postures, three-fingered hands held low,
mouths slightly open showing dim teeth. Cool blue-black night palette
in the surrounding trees, warm orange torchlight bleeding in from the
left edge of the frame. Wide ground-level shot from inside the
clearing looking out into the dark woods. Atmospheric, threatening,
predatory mood — these creatures have spotted you.
```

---

### Ashfallen — corrupted knight enemy (future)

**Save as:** `ashfallen_a.png` and `ashfallen_b.png` in `assets/concept/enemies/`

#### Version A — 3D-conversion input

```
Tall corrupted knight in full plate armor, 1.95 meters tall, faceless
visor helmet with a cracked design suggesting decay and ash damage.
Armor is grey steel with rust streaks and faded heraldry from an
extinct knight order. Tattered cloak hanging flat behind shoulders
(not flowing). Empty hands in T-pose. Color palette: weathered iron
grey, rust orange streaks, desaturated maroon for the cloak, ash-grey
accents on shoulder pauldrons.
```

#### Version B — Concept and mood

```
A solitary Ashfallen knight standing guard at the foot of a ruined
stone arch in a grey volcanic wasteland. Full plate armor weathered
and rust-streaked, faceless cracked visor helmet, tattered maroon
cloak hanging in still air. One hand rests on the pommel of a long
greatsword planted point-down in the ash at his feet. Cold grey
overcast light, no warmth. Distant volcano on the horizon spits a
dim orange glow. Wide cinematic shot, low angle to emphasize the
knight's height. Mood: implacable, patient, corrupted from within —
this used to be one of Roland's brothers.
```

---

### Wolf — non-humanoid enemy (future)

**Save as:** `wolf_a.png` and `wolf_b.png` in `assets/concept/enemies/`

#### Version A — 3D-conversion input

```
Large grey timberwolf, 1.4 meters at the shoulder, in a neutral
standing pose with all four legs straight, tail level, head facing
forward. Coat is layered grey: dark dorsal stripe, mid grey flanks,
pale belly. Yellow eyes. Pointed ears upright. No collar, no held
props. Stylized chunky voxel proportions but clean topology. Auto-rig
will be manual in Blender (Mixamo doesn't auto-rig quadrupeds), so
the topology should support that — clear distinct legs, visible spine
line, no fused mass.
```

#### Version B — Concept and mood

```
A timberwolf at the head of a small pack of three on a snowbound
ridge at dusk. Lead wolf in mid-step on a rocky outcrop, head
lowered, yellow eyes fixed forward, breath visible in the cold air.
Two more wolves visible behind in the snow. Cold blue twilight
palette, last light of day fading orange on the distant peaks. Wide
landscape shot. Voxel aesthetic with chunky snow-covered rocks and
trees. Mood: a hunt has begun, you are the prey.
```

---

### Bear — mini-boss enemy (future)

**Save as:** `bear_a.png` and `bear_b.png` in `assets/concept/enemies/`

#### Version A — 3D-conversion input

```
Massive brown grizzly bear, 1.8 meters at the shoulder when on all
fours, neutral standing pose with all four legs straight, head facing
forward, mouth closed. Coat is dark brown with reddish-amber tips on
back and shoulders. Small dark eyes. Visible claws on each paw.
Stylized chunky voxel proportions — exaggerated mass on shoulders
and head, large paws, smaller hindquarters. Clean topology suitable
for manual rigging in Blender (no Mixamo for quadrupeds).
```

#### Version B — Concept and mood

```
An enormous brown grizzly bear rearing onto its hind legs at the
mouth of a moss-covered stone cave, dwarfing the surrounding voxel
trees. Mid-roar, mouth open showing chunky cube teeth, claws
spread. Late-morning light filtered through forest canopy
illuminating the bear from the front-left, leaving the cave behind
in deep shadow. Wide low-angle shot from a hidden vantage point in
the brush. Mood: mini-boss territorial reveal — this is the moment
the player realizes they're in the wrong place.
```

---

### Companion: Orion (future)

**Save as:** `orion_a.png` and `orion_b.png` in `assets/concept/companions/`

#### Version A — 3D-conversion input

```
Male companion warrior, late twenties, leaner build than Roland, 1.78
meters tall. Long dark hair tied back. Hawkish features. Wearing
travel-worn leather armor with a green-grey hood folded down,
crossbody quiver strap visible. Empty hands in T-pose. Color palette:
forest greens, warm browns, faded leather tan, slate grey hood. No
held bow, no arrows in hand.
```

#### Version B — Concept and mood

```
Companion Orion crouched on a tree branch ten meters above the
ground in a dense voxel forest at dawn. Composite bow held at low
ready, arrow nocked but not drawn. Eyes scanning the forest floor
below. Green-grey hood pulled up. Cool blue dawn light filtered
through chunky voxel canopy. Mid-shot from slightly above, looking
down toward where Orion is looking. Mood: he has eyes Roland doesn't.
```

---

### Companion: Dagna (future)

**Save as:** `dagna_a.png` and `dagna_b.png` in `assets/concept/companions/`

#### Version A — 3D-conversion input

```
Female dwarf companion, 1.4 meters tall, broad-shouldered, in T-pose.
Red hair in two thick braids on either side of her head. Round
weathered face. Wearing iron-banded leather armor, smith's apron over
chest. Empty hands. Color palette: copper-red hair, warm browns,
iron grey banding, scorched-tan apron. Slightly hunched shoulders
to read as a smith's posture but T-pose otherwise pure.
```

#### Version B — Concept and mood

```
Dwarf companion Dagna at her forge, mid-strike, hammer raised over
a glowing orange iron bar on the anvil. Red-orange forge fire
illuminating her face from below, warm sparks scattering. Smith's
apron, copper-red braided hair, focused expression. Dim warm
interior of a stone forge in a dwarven hold. Close-mid shot, slight
low angle. Mood: master craftsperson at work, the only world that
matters is the metal in front of her.
```

---

### Spear — thrown weapon (kept in MagicaVoxel)

The spear is a 4×36×4 voxel prop. **Use the original MagicaVoxel authoring brief from `design/COMBAT_DESIGN_3D.md` (Appendix A.2 of the v1 plan)** rather than the AI 3D pipeline — for objects this simple, MagicaVoxel is faster and gives more direct control.

If you want a concept reference image:

#### Version B — Concept and mood

```
Single voxel-style throwing spear lying horizontal on weathered oak
plank flooring in soft late-afternoon window light. Two meters long.
Wooden shaft with visible grain, dark leather grip wrap in middle,
iron diamond-shaped head at one end with a small dark iron butt cap
at the other. Chunky voxel cubes, ~18 voxels per meter resolution.
Tight close-up product-shot framing, shallow depth of field,
neutral parchment-tan plank background. Mood: a tool of a hard
trade, well-cared-for.
```

---

### The bloody payoff frame — concept reference for v1

**Save as:** `combat_v1_money_shot.png` in `assets/concept/combat/`

Used to align everyone on what the v1 gore moment looks like. Reference for VFX tuning and asset polish.

#### Version B — Concept and mood

```
A throwing spear has just buried itself in a green-skinned voxel
goblin's chest. Frozen moment of impact. Cubic red blood particles
erupting from the wound in a directional cone along the spear's
travel path, deep arterial red, scattered cube particles
approximately 3 cm each suspended in mid-air. Spear shaft protrudes
from torso. Goblin's body beginning to recoil backward, expression
of shock. Forest clearing setting, late-afternoon light filtered
through chunky voxel pine trees. Saturated red blood popping against
muted forest greens and browns. Close third-person camera angle,
mid-shot, framed for a video-game cinematic moment. Voxel aesthetic
with chunky terrain and slightly higher-resolution characters.
```

---

### Goblin death explosion — concept reference

**Save as:** `goblin_explosion_v1.png` in `assets/concept/combat/`

#### Version B — Concept and mood

```
A voxel goblin mid-explosion after a lethal hit. Body breaking apart
into approximately 80 separate cube chunks flying outward in a radial
spray. Mix of green outer-skin cubes and revealed deep red flesh
cubes intermingled in the cluster. Spear still embedded in the
largest central chunk. Motion blur on flying pieces, frozen at peak
spread. Forest dirt floor below catching the first scattered cubes
as a beginning blood pool. Late-afternoon warm light. Voxel
aesthetic, 18 voxels per meter character resolution, 3 cm blood
particles in the spray. Cinematic gore moment, visceral but stylized
through the cubic abstraction. Mood: the satisfying payoff of a
charged spear throw landing perfectly.
```

---

### CombatTest dev arena — mood reference

**Save as:** `combat_test_arena.png` in `assets/concept/environments/`

#### Version B — Concept and mood

```
Small flat circular forest clearing approximately 30 meters across,
surrounded by chunky voxel pine trees. Dirt and grass ground at 6
voxels per meter resolution. Three green-skinned voxel goblins
standing in a loose triangle formation in the center, idle pose.
Late-afternoon warm sunlight casting long shadows across the
clearing. Cool sky color above, warm ground below. Slight haze.
Wide cinematic establishing shot from a low angle near the southern
edge of the clearing. Style matches the existing project concept
art: chunky voxel terrain, slightly higher-resolution character
figures, painterly fantasy aesthetic.
```

---

### Background NPC — generic templates (future)

**Save as:** `npc_villager_a.png`, `npc_villager_b.png`, etc.

#### Version A — 3D-conversion input

```
Generic medieval voxel villager in T-pose against pure white
background. Mid-thirties, average build, 1.7 meters tall. Wearing
simple linen tunic in muted color (green / blue / red / brown — one
per generation), brown trousers, leather belt, simple shoes.
Friendly but neutral expression. Empty hands. Forgettable face — this
is a Tier 0 background figure that should read as "a person" without
demanding individual attention. Color palette: muted earth tones for
clothing, warm skin tones, brown hair.
```

(Generate four with different tunic colors for crowd variety: green / blue / red / brown.)

#### Version B — Concept and mood

```
A bustling medieval town market square at midday. Eight to ten
generic voxel villagers in muted earth-tone clothing browsing stalls
of vegetables, fish, and cloth. Cobblestone ground, timber-framed
buildings on either side, bunting strung between rooftops. Warm
midday light. Chunky voxel terrain and architecture, slightly
higher-resolution villagers. Wide ground-level establishing shot.
Mood: lived-in, ordinary, the world goes on.
```

---

## Blender bridge — step-by-step

After Meshy or Tripo returns a smooth `.glb`, every character passes through this Blender process before going into Mixamo. Save this checklist near your Blender workspace.

### Setup (one time per project)

You'll do this once. The template file lives under `tools/blender/` so it's tracked in the repo and available on any machine where you check out the project.

#### Create the `voxel_character_template.blend`

This is a starter file with the Remesh modifier pre-configured. Per-character workflow: open the template, import the Meshy `.glb`, copy the modifier from the placeholder mesh onto the imported mesh, then save the file as `working_<asset>.blend`.

1. **Open Blender** and start a fresh file (File → New → General).

2. **Delete everything in the default scene** — select all (`A`), then `X → Delete`. You should have an empty scene with just the camera and light remaining (those don't matter; ignore them).

3. **Add a placeholder cube** — `Shift+A → Mesh → Cube`. Name it `_ModifierTemplate` in the Outliner (double-click the name) so it's clearly not for export.

4. **Add the Remesh modifier:**
   - With the placeholder cube selected, open the **Modifier Properties** panel (the wrench icon in the Properties editor on the right side of the default workspace).
   - Click **Add Modifier → Generate → Remesh**.
   - Configure these exact values:

     | Field | Value |
     |---|---|
     | Mode | **Blocks** |
     | Octree Depth | **6** |
     | Scale | 0.99 (default) |
     | Threshold | 1.0 (default) |
     | Remove Disconnected | **OFF** (so floating eye / accessory cubes survive) |
     | Smooth Shading | **OFF** |

   - **Do NOT apply the modifier** — we want it to stay live on the placeholder so it can be copied to imported meshes.

5. **Save the file** — File → Save As → navigate to `tools/blender/` (create the folder if it doesn't exist) → filename `voxel_character_template.blend`.

6. **Commit the template** so it's available to anyone working on the project:
   ```
   git add tools/blender/voxel_character_template.blend
   git commit -m "Add Blender template for voxel character pipeline"
   ```

#### Per-character usage of the template

When you start working on a new character (e.g. importing `smooth_goblin.glb` from Meshy):

1. **Open the template:** File → Open → `tools/blender/voxel_character_template.blend`.

2. **Immediately Save As:** File → Save As → `working_goblin.blend` somewhere outside the repo (the working file shouldn't be committed — only the final .glb exports go in `assets/models/`).

3. **Import the Meshy mesh:** File → Import → glTF 2.0 → select `smooth_goblin.glb`. The imported mesh appears alongside the `_ModifierTemplate` cube.

4. **Copy the Remesh modifier onto the imported mesh:**
   - Select the imported mesh first.
   - **Shift+click** the `_ModifierTemplate` cube to add it to the selection. The template cube must be the **active** object (last selected, highlighted brighter) — Blender copies *from* the active object.
   - **Ctrl+L → Copy Modifiers** (Make Links menu → Copy Modifiers). The Remesh modifier appears on the imported mesh, pre-configured.

5. **Delete the placeholder cube** — select `_ModifierTemplate`, press `X`. The imported mesh keeps its Remesh modifier because the modifier was copied, not linked.

6. **Proceed with the per-character process below** (mesh cleanup → bake textures → apply Remesh → export).

If Blender ever shows the Modifier Properties panel as empty after you load the template, that means you selected the imported mesh, not the placeholder cube — the modifier lives on the placeholder until you copy it.

---

### Per-character process

```
┌──────────────────────────────────────────────────────────────────┐
│  1. Import smooth_<asset>.glb                                    │
│     File → Import → glTF 2.0                                     │
│                                                                  │
│  2. Mesh cleanup (Object Mode, then Edit Mode)                   │
│     Select All (A)                                               │
│     Mesh → Clean Up → Merge by Distance (default 0.0001 m)       │
│     Mesh → Symmetrize → +X to -X                                 │
│                                                                  │
│  3. Bake textures to vertex colors                               │
│     Open the asset's image texture in the Shader Editor          │
│     With the mesh selected, switch to Vertex Paint mode          │
│     Paint menu → Color from Active Texture                       │
│     This bakes the AI's PBR texture into vertex color data       │
│     The .glb can then ship without external texture files        │
│                                                                  │
│  4. Apply Remesh modifier (Blocks mode)                          │
│     Modifier Properties → Add → Generate → Remesh                │
│     Mode: Blocks                                                 │
│     Octree Depth: 6 (gives ~22 voxel-tall figure)                │
│     Threshold: 1.0                                               │
│     Use Smooth Shading: OFF                                      │
│     Apply the modifier (do not leave it stacked)                 │
│                                                                  │
│  5. (Optional) Palette snap                                      │
│     Run scripts/blender/palette_snap.py from Blender's text      │
│     editor to round each vertex color to the nearest of the      │
│     32-color project palette. Locks the visual style.            │
│                                                                  │
│  6. Sanity checks before export                                  │
│     - Mesh stats: face count under 5000 (Mixamo limit)           │
│     - No internal walls (Wireframe view, look inside)            │
│     - Symmetry intact (X axis)                                   │
│     - Vertex colors look correct in Vertex Paint preview         │
│                                                                  │
│  7. Export <asset>_voxel.glb                                     │
│     File → Export → glTF 2.0 (Binary) (.glb)                     │
│     Include: Selected Objects, Custom Properties, Vertex Colors  │
│     Compression: OFF (for Mixamo upload)                         │
└──────────────────────────────────────────────────────────────────┘
```

### Common pitfalls

- **Mixamo rig fails** → mesh too chunky after Remesh. Reduce octree depth to 5 or skip palette snap until after rig.
- **Faces look wrong colors** → vertex colors not baked before Remesh. Order matters: bake first, then Remesh.
- **Asymmetric T-pose** → Symmetrize step skipped. Always symmetrize before Remesh.
- **Texture seams visible** → texture not baked to vertex colors. Remesh breaks UVs; vertex colors survive Remesh, UV-mapped textures don't.

---

## Mixamo workflow

Once you have a `<asset>_voxel.glb`:

1. Open https://www.mixamo.com (free Adobe account required).
2. Click **Upload Character** → select your .glb file.
3. Place auto-rig markers: chin, wrists, elbows, knees, groin (5 markers, ~30 sec).
4. Click **Next** — Mixamo runs auto-rig (~30 sec).
5. Browse the animation library. Search for the clips you need (idle, walk, run, attack, react, death).
6. For each animation: click **Download** → format **FBX for Unity** (works with Godot via auto-import), or **GLB**, choose **With Skin** for the first download and **Without Skin** for subsequent downloads (saves disk space).
7. Save downloads to `assets/models/<asset>_anims/`.

For the **Roland** rig specifically, grab these Mixamo clips:
- `Idle` — search "idle" → "Sword And Shield Idle"
- `Walking` — "Walking"
- `Running` — "Running"
- `Combat Roll` — "Combat Roll"
- `React Hit` — "React Hit From Right"
- `Death` — "Sword And Shield Death"

For **Goblin**, grab:
- `Goblin Idle` — search "zombie" → "Zombie Idle" works as a base, or "Mma Idle"
- `Goblin Walk` — "Zombie Walking"
- `Goblin Attack` — "Zombie Attack"
- `Goblin Death` — used only briefly before topple cluster takes over; "Falling Forward" works

Animation names in Godot will match the Mixamo clip names; rename in `AnimationPlayer` if you want cleaner identifiers.

---

## Troubleshooting Mixamo skinning — Voxel Heat Diffuse Skinning fallback

Mixamo computes its own skin weights when you upload a mesh, so in the normal path you never touch skinning in Blender. **You only need this section if Mixamo's auto-skinning produces visible deformation problems on a specific character** — limbs detaching during animation playback, fingers exploding outward, head shearing off the neck on rotation.

### When this happens

Most often on:
- Highly chunky voxelized humanoids where limb-torso cube boundaries are ambiguous to Mixamo's algorithm
- Characters with floating accessory geometry (loose belts, capes, jewelry) that Mixamo binds to the wrong bone
- Non-humanoid characters (Wolf, Bear) — Mixamo doesn't auto-rig quadrupeds at all, so you have to rig and skin them in Blender from the start

### The fallback: Voxel Heat Diffuse Skinning

This is a Blender add-on that uses a volumetric voxel-based diffusion algorithm to compute skin weights — much more robust on chunky / blocky meshes than Blender's default heat-diffusion method.

**You don't have to buy it.** Mesh Online sells a Pro version (~$30, faster execution, batch processing), but they also offer a free version on the same page that's sufficient for one-at-a-time character work.

#### Install

1. Download from Mesh Online: **https://www.meshonline.net/voxel-heat-diffuse-skinning.html**
   - Pick the free version unless you're batch-processing many characters.
   - Save the `.zip` to a stable location (Blender references the install path).

2. In Blender: **Edit → Preferences → Add-ons → Install from Disk** (Blender 4.6 menu path).

3. Browse to the downloaded `.zip`, click **Install Add-on**.

4. Search the add-on list for **"Voxel Heat Diffuse Skinning"** and check the box to enable it.

5. Save preferences: **Preferences hamburger menu → Save Preferences** so it persists across restarts.

#### Use it on a failing character

1. In Blender, with the problem mesh + an armature (either Mixamo's downloaded rig or your own manual one):
   - Select the mesh first, then **Shift+click the armature** so the armature is the active object.
   - **Object menu → Voxel Heat Diffuse Skinning → Generate**.

2. Wait — voxel diffusion is slower than Blender's default automatic weights, often 30–60 seconds for a Game-One-sized character.

3. Test the new skinning by selecting the armature → Pose Mode → rotate individual bones and check that the mesh deforms cleanly with no exploded vertices.

4. Re-export the rigged mesh (`.glb`) and re-upload to Mixamo. Mixamo will accept a pre-rigged mesh and let you grab animations against the existing skeleton instead of generating a new one.

For **quadruped characters** (Wolf, Bear), this is the canonical skinning path since Mixamo can't help at all — you build the armature manually in Blender first, then run Voxel Heat Diffuse Skinning to compute weights.

---

## Custom animations — Cascadeur and Move.ai

When Mixamo doesn't have what you need (the spear charge wind-up, the throw release, a unique combat finisher), you have two paths:

### Path A — Cascadeur

1. Download the rigged `<asset>.glb` from Mixamo.
2. Open in Cascadeur — File → Import → FBX (export from Blender as FBX first if needed).
3. Use the AutoPosing tool to roughly block in keyframes (~5 min).
4. Cascadeur's physics-aware in-betweens fill the rest.
5. Refine timing.
6. Export FBX → re-import into Blender → merge into the rigged .glb.

Best for: animations with strong physics character (spear throw release, falling, combat impacts) where the AI auto-pose saves significant keyframe time.

### Path B — Move.ai webcam mocap

1. Set up a webcam in good lighting.
2. Open Move.ai in the browser, start recording.
3. Perform the animation yourself (~30 sec for a one-shot anim like spear throw).
4. Move.ai converts the video to BVH or FBX mocap data.
5. Import into Blender, retarget to your character's rig (Auto-Rig Pro plugin makes this easier; free tier exists).
6. Save the retargeted clip into the rigged .glb.

Best for: idle gestures, dialogue body language, idiosyncratic character movements that benefit from human performance.

### Animations needed for Voxel Combat v1

| Clip name | Owner | Source | Duration | Notes |
|---|---|---|---|---|
| `roland_idle` | Roland | Mixamo "Sword And Shield Idle" | loop | Default standing |
| `roland_walk` | Roland | Mixamo "Walking" | loop | |
| `roland_run` | Roland | Mixamo "Running" | loop | Sprint |
| `roland_react_hit` | Roland | Mixamo "React Hit" | one-shot 0.5s | Goblin contact damage |
| `roland_spear_charge_windup` | Roland | **Cascadeur custom** | 0.7s, ends in held pose | Phase 3 work |
| `roland_spear_throw_release` | Roland | **Cascadeur custom** | 0.6s | Phase 3 work |
| `goblin_idle` | Goblin | Mixamo "Zombie Idle" | loop | |
| `goblin_walk` | Goblin | Mixamo "Zombie Walking" | loop | |
| `goblin_alert` | Goblin | Mixamo "Standing Reaction Look" | 0.5s | IDLE → ALERT cue |
| `goblin_attack_lunge` | Goblin | Mixamo "Zombie Attack" | 0.8s | Contact damage |
| `goblin_topple` | Goblin | Mixamo "Falling Forward" | 0.4s | Brief — cluster takes over |

---

## Sound effect prompts

Eighteen SFX needed for Voxel Combat v1, sourced primarily from ElevenLabs Audio (paid, dedicated SFX mode) with freesound.org as fallback. Generate the goblin vocal pack as one ElevenLabs session for tonal consistency.

### ElevenLabs Audio system prompt

> Voxel-style fantasy combat sound effect. Mono. Punchy attack, no ambient bed, no music, no Foley reverb. Mid-fidelity — slight retro edge but realistic core. Format: 44.1 kHz, OGG Vorbis target. Tag for Game One: Mira-Thal voxel RPG.

### Per-SFX prompts

#### Spear sounds

```
sfx_spear_charge_loop.ogg
Rising tense low hum that builds slowly in volume and pitch over 700ms,
designed to loop seamlessly. Suggests muscular tension being wound up.
Subtle leather creak undertone, almost subliminal. Mono. 700ms.
```

```
sfx_spear_release_light.ogg
Quick sharp whip-crack whoosh of a thrown wooden projectile leaving a
hand. 200ms total. Punchy mid-frequency snap, no body. Mono.
```

```
sfx_spear_release_charged.ogg
Heavier whoosh combined with a deep low thump of muscular force. 300ms.
More body, weight, and follow-through than the light version. Mono.
```

```
sfx_spear_flight_loop.ogg
Subtle continuous whoosh of a wooden shaft cutting through air.
Loopable seamlessly. Mid-frequency, slight wobble suggesting rotation.
Mono.
```

```
sfx_spear_impact_flesh.ogg
Wet meaty thud combined with a brief fabric tear. 250ms. Visceral but
not cartoonish — a real spear into a real body, not a horror-film
exaggeration. Mono.
```

```
sfx_spear_impact_terrain.ogg
Stone-and-dirt thunk with a slight crack at the end. 200ms. Solid
impact, slight rebound. Mono.
```

```
sfx_spear_pickup.ogg
Soft wood-on-leather rustle, brief. 150ms. Tactile pickup sound,
satisfying but quiet. Mono.
```

#### Blood / gore sounds

```
sfx_blood_burst.ogg
Wet pressurized spray sound, brief and punchy. 350ms. Like a small
hose burst or arterial spray. Mono. Visceral but not gross.
```

```
sfx_blood_drip_loop.ogg
Slow rhythmic drip of liquid onto soft soil, approximately one drip
per second, loopable seamlessly over 2 seconds. Mono. Quiet,
atmospheric, suggests ongoing wound bleed.
```

```
sfx_blood_pool_splat.ogg
Heavy wet plop of liquid hitting the ground. 200ms. Substantial
weight, definitive. Mono.
```

#### Goblin vocals

> *Generate all five in a single ElevenLabs session with the same voice character settings for tonal consistency.*

```
sfx_goblin_alert_yelp.ogg
Short sharp surprised bark from a small humanoid creature, like a
startled goblin spotting an intruder. 250ms. Higher-pitched, raspy.
Mono.
```

```
sfx_goblin_combat_growl.ogg
Aggressive guttural snarl from a small humanoid creature preparing to
attack. 400ms. Lower pitch than the yelp. Threatening, hungry. Mono.
```

```
sfx_goblin_hurt_grunt.ogg
Pained low grunt from a wounded small humanoid creature, surprised by
its own injury. 300ms. Mono.
```

```
sfx_goblin_death_topple.ogg
Choked gurgle followed by a heavy body thump as it hits the ground.
600ms. Definitive death sound, no return. Mono.
```

```
sfx_goblin_death_explode.ogg
Wet meaty pop, like a balloon of stew bursting under pressure. 400ms.
Final, gory, but stylized rather than gross. Mono.
```

#### Impact / camera

```
sfx_camera_kick_thump.ogg
Sub-bass dull thump, very brief. 100ms. Felt more than heard, like a
low impact through a wall. Mono.
```

```
sfx_time_slow_in.ogg
Pitched-down whoosh with a sense of ear pressure dropping. 150ms.
Cinematic time-dilation effect. Mono.
```

```
sfx_time_slow_out.ogg
Pitched-up restoration whoosh, the inverse of time_slow_in. 100ms.
Returns to normal time. Mono.
```

```
sfx_dust_burst.ogg
Soft dirt poof, like a small bag dropped on dry earth. 200ms. Mono.
```

---

## Quality checks — what to watch for

AI 3D commonly introduces these problems. Catch them in Blender before Mixamo upload.

| Problem | How to spot | Fix |
|---|---|---|
| Non-manifold geometry | Wireframe view shows internal walls | `Mesh → Clean Up → Merge by Distance` |
| Asymmetric T-pose | Vertex count differs left vs right | `Mesh → Symmetrize → +X to -X` |
| Hollow eyes / floating bits | Visible recesses where eyes should be solid | Delete after voxelization, add manual cubes |
| Texture seams visible | Stripes on chest or shoulders post-Remesh | Bake to vertex colors *before* Remesh |
| Mixamo rig fails | "Could not auto-rig" error | Reduce Remesh octree depth to 5; check humanoid proportions |
| Vertex colors clip to white | Some surfaces too bright after palette snap | Skip palette snap; or widen palette tolerance |
| Topology too dense | Mesh > 5000 faces | Decimate modifier (ratio 0.5) before Remesh |

---

## What NOT to AI

These asset classes are NOT improved by AI generation and should stay manual:

- **Buildings** — they need to tile, snap to grid, integrate with voxel terrain. AI 3D produces one-offs that don't compose. Keep MagicaVoxel modular tile authoring per `design/ART_PIPELINE.md`.
- **Simple weapons / props** — the spear, swords, basic furniture. 5–15 min in MagicaVoxel beats 15 min of AI pipeline overhead for the same result.
- **Particle systems / VFX** — these are runtime Godot, not asset pipeline. The blood burst, dust, weather particles are all GPUParticles3D nodes built in code. Don't try to "generate blood particles."
- **UI elements** — icons, HUD chrome, menu styling all live in `assets/ui/css/` and follow the `Colors` autoload + `UIStyles` helper class. AI image gen for UI breaks the design system.
- **Hero animations carrying emotional weight** — Roland's death, the celebration after a major quest, the first dialogue idle. Mixamo + Cascadeur cover the technical motion, but final passes benefit from human authorship.

---

## Folder layout (post-pipeline)

```
assets/
├── concept/               ← AI-generated reference images, NOT in build
│   ├── characters/
│   │   ├── roland_a.png
│   │   ├── roland_b.png
│   │   └── ...
│   ├── enemies/
│   │   ├── goblin_a.png
│   │   ├── goblin_b.png
│   │   └── ...
│   ├── companions/
│   ├── combat/            ← v1 money-shot frames
│   └── environments/
├── models/                ← Production .glb characters/enemies (in build)
│   ├── roland.glb
│   ├── goblin.glb
│   └── ...
├── voxel/                 ← MagicaVoxel exports (in build)
│   ├── props/
│   │   └── spear.glb
│   └── ...
├── voxels/                ← Texture pack atlases (in build)
│   └── texture_packs/default/
└── audio/sfx/             ← AI-gen + freesound SFX (in build)
    └── combat/
        ├── sfx_spear_release_light.ogg
        └── ...
```

The `assets/concept/` folder is intended to be **excluded from the export build** via Godot's export filter — these are reference images, not runtime assets. Add `*.png` under `assets/concept/` to the export ignore list in `export_presets.cfg` once that file lands.

---

## Maintenance

This document goes stale as the pipeline evolves. Update it when:

- A new AI tool ships that displaces one of the recommendations above (write a deprecation note + new section).
- The character voxel scale changes from 18 vx/m (would invalidate the system prompt's voxel-detail clause).
- A new asset class lands that doesn't fit any existing prompt template.
- A pipeline step fails repeatedly enough that a workaround belongs here (e.g. a Mixamo limit changes).

Cross-reference the `Files requiring regular maintenance` table in `CLAUDE.md` and add `design/ASSET_PIPELINE_AI.md` there once this doc is committed.
