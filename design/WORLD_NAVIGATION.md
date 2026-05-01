# World Navigation

How the player orients themselves in Mira-Thal, moves between locations, and discovers new areas.

> Cross-reference: `design/HUD_AND_UI.md` for the in-game compass and journal overlay.
> `design/JOURNAL_UI.md` for the Map tab layout and hand-drawn map rendering.
> `design/NPC_SYSTEM.md` for NPC schedules and location spawn points.
> `design/INVESTIGATION_SYSTEM.md` for the no-quest-marker approach.
> `lore/WORLD_GEOGRAPHY.md` and `lore/MAP_GENERATION_GUIDE.md` for world layout.

---

## Design Philosophy

**Navigation is attention, not automation.** The game does not place objective arrows, waypoints, or distance counters on the screen. Roland is a trained knight and investigator — he reads terrain, listens to locals, and checks his journal. The player learns to do the same.

**The map is Roland's map.** It is hand-drawn, annotated in his voice, and updated as he explores. It is not a top-down satellite view with precise geometry. Some roads are roughly sketched. Some locations are labeled with Roland's shorthand rather than their official names. It is a player tool, not a GPS.

**Getting lost is temporary, not broken.** Players who do not know where they are should be able to figure it out within two minutes by reading the environment. The world is legible — river flows give direction, sun position gives time of day, distinctive silhouettes mark major locations. A player who feels lost is being invited to look around.

**Travel has weight but not friction.** Walking across the map should feel like Roland is actually going somewhere. It should not feel like running in place while a loading bar fills. There is no fast-travel shortcut by default. Zone boundaries create natural travel rhythms.

---

## The Map and Journal

The **Map tab** of the journal is the player's primary navigation reference.

### What the Map Shows

- **Known roads** — sketched as rough lines when Roland walks them. Unmapped territory appears as blank parchment with hatching at the edge.
- **Settlements and locations** — labeled when discovered. New labels appear in Roland's handwriting, sometimes with a brief personal note: *"Aldenholt — market town, Gate of the Spine road, where Tomlin's contact lives."*
- **Areas of interest** — Roland marks locations relevant to his current quests, but these are journal entries cross-referenced to the map, not waypoints. The player reads the quest context and finds the place.
- **Points of note** — Roland marks things that surprised him or may be useful: a cache location, a shortcut he found, a building that seemed wrong.

### What the Map Does Not Show

- Roland's current real-time position
- Enemy locations
- Quest objective markers
- Distance or travel time estimates
- NPC locations

**Why no player position marker:** The compass strip in the HUD provides directional orientation. The map shows the world. Together, they do the job a GPS dot would do — less precisely, but with more player engagement. A player who looks at the map, then looks at the road ahead, and figures out where they are has navigated. That is the intended experience.

---

## Discovering New Areas

### Exploration Reveal

The map reveals as Roland physically moves through the world. Areas Roland has not visited remain as blank parchment or light hatching indicating "unexplored." The reveal is not a fog-of-war system with sharp edges — it is more like a sketch filling in: roads appear when walked, buildings appear when approached, region names appear when Roland has entered the region.

Roland does not see a "new area discovered" notification unless the location is story-relevant. He does not need to be told he is somewhere new — the world tells him.

### Unmarked Locations

Not every location in the world is listed in quests or on starting maps. Some are:
- **Stumbled upon** by wandering off the main road
- **Mentioned by NPCs** who give directions in natural language (*"There's an old waystation about half a day's walk east of the Spine road, after you cross the second bridge"*) — Roland marks this on his map as a rough note, not a pin
- **Hinted by the environment** — a trail leading into trees, smoke from a chimney below a ridge, a carved marker on a stone

Finding these locations contributes to the Exploration skill domain (see `design/SKILLS_AND_PROGRESSION.md`).

---

## Zone Structure

The world is organized into **zones** — distinct geographic areas connected by **zone boundaries**.

### Zone Boundaries

A zone boundary is an invisible line (usually at a natural transition: road exit, cave entrance, door, or terrain feature). Crossing it:

1. Triggers a brief fade or transition (not a loading screen for adjacent outdoor zones — only for interior scene loads)
2. Updates the map with the new zone name
3. Triggers the appropriate location music theme (see `design/AUDIO_DESIGN.md`)
4. May trigger WorldClock time-of-day transitions if significant time passed in loading

Zone boundaries are placed at narrative transitions: leaving a city, entering a dungeon, descending into a new underground level. They are never in the middle of an open field.

### Zone Types

| Zone type | Transition | Examples |
|---|---|---|
| **Outdoor region** | Seamless or minimal fade | Eastern plains, the Spine road, Ash approaches |
| **Settlement** | Brief fade (populating NPC schedules) | Aldenholt, Caer Brannoch, Solgrade |
| **Interior** | Scene load with fade | The Archive, the Iron Chalice chapel, tavern |
| **Underground / dungeon** | Scene load | The Underway, Vault of Aen-Vael approaches, caves |

Outdoor zones that are adjacent in geography load seamlessly or with a momentary camera cut. Indoor zones always load — they are separate `.tscn` files.

---

## Fast Travel

**Game One has no fast travel system.** Roland walks everywhere. This is a deliberate design decision:

1. **Travel encounters matter.** NPCs met on the road, weather events, ambushes, and environmental discoveries happen in transit. Fast travel skips them.
2. **Distance communicates stakes.** When Roland must walk from Aldenholt to Solgrade, the player feels the journey. The scale of the world is part of the game's emotional register.
3. **Camp breaks the travel.** If travel feels long, the player is encouraged to make camp and rest — which has its own gameplay value.

**Potential Act II addition:** If Act II's wider map makes travel unacceptably slow, a limited fast-travel option (hire a road courier, ride a horse, Brotherhood waypoints) can be introduced as a story-gated convenience — not a default feature.

---

## NPC Directions and Verbal Navigation

Since there are no waypoints, NPCs provide genuine navigational information when asked:

- **Tier 1 NPCs** do not give directions. They are world dressing.
- **Tier 2 NPCs** give directions that Roland notes in his journal as appropriate: *"Ser Brenn trains at the barracks, east gate, past the well."*
- **Tier 3 NPCs** (main cast) discuss routes as part of planning — travel planning is part of those conversations, not separate.

Roland's journal Map tab updates with rough marks when he receives verbal directions — a short annotation in his handwriting, not a pin. The player must then find the place, which is the point.

---

## Landmarks and Legibility

The world is designed around **landmark navigation**: recognizable shapes and features that answer "where am I?" without a map.

### Guiding Principles for Scene Design

1. **Every zone has a silhouette.** The first view of a new zone should contain at least one visually distinctive shape: a mountain peak, a distinctive tower, a river bend, a color difference in the foliage. The player should be able to recognize the zone at a glance on return visits.

2. **Roads lead somewhere obvious.** A road always visually leads toward a destination — a gate in a wall, a break in the trees, a descent toward a valley. Roads do not disappear into featureless terrain.

3. **The sky tells time.** Sun position indicates time of day. Dawn and dusk have distinct colors. Night is distinct. Players who are unsure what time it is can look up.

4. **Water flows downhill.** Rivers always flow in a consistent direction and can be used for cardinal orientation when the sun is not visible.

5. **Interiors have exits.** Every interior scene has a visible or clearly signed exit. Players do not get turned around inside buildings.

---

## SpawnPoints and Return Navigation

When Roland returns to a zone he has visited before, he spawns at the **SpawnPoint3D** nearest to the zone boundary he crossed from.

Each zone has:
- One default entry spawn point per connected zone boundary
- Optional named spawn points for story-placed arrivals (Roland wakes up in Aldenholt inn after collapsing — spawns at the inn interior's bed SpawnPoint3D)

SpawnPoint3D nodes are added to the `spawn_points` group (see `DESIGNER_TODO.md` — Section 2). Their names must match the zone connection they serve (e.g., `"spawn_from_spine_road"` is the spawn used when entering Aldenholt from the east).

---

## GDScript Notes

### Zone transition with TransitionManager

```gdscript
# RoomTrigger3D.gd — fires when Roland crosses the trigger area:
func _on_body_entered(body: Node3D) -> void:
    if not body.is_in_group("player"):
        return
    TransitionManager.go_to_scene(target_scene, target_spawn_point)
```

### Map reveal update

```gdscript
# Called when a new zone is entered:
# GameState tracks which zones have been visited.
GameState.set_flag("visited_" + zone_id, "true")
# JournalUI reads these flags when the Map tab is opened to determine
# which regions to render as revealed vs. unexplored.
```

### Verbal direction → map annotation

```gdscript
# Called from a Dialogic timeline event when an NPC gives directions:
GameState.add_map_note(location_id, annotation_text)
# JournalUI.Map tab reads notes from GameState and renders them as
# handwritten labels at the location_id's known coordinate.
```
