# Investigation System Design

How Roland examines the world, draws conclusions, and uses observation as a mechanic.

> Cross-reference: `design/SYSTEMS_DESIGN.md` for the "information as currency" design philosophy.
> `design/CONVERSATION_SYSTEM.md` for how investigation findings unlock dialogue branches.
> `design/NPC_SYSTEM.md` for companion observation comments during dialogue.
> `design/JOURNAL_UI.md` for how investigation findings appear in the Codex tab.

---

## Design Philosophy

**Observation is Roland's primary skill.** He is a former knight who has spent years as an investigator. He notices things. The investigation system is the mechanical expression of that: the world contains information that rewards a player who slows down and looks.

**Not everything is an investigation point.** Most objects in the world are scenery. A minority are examination-worthy. A smaller minority yield information Roland can actually use — as dialogue options, as journal entries, as context that changes how a scene reads. The player learns which type an object is by paying attention to what Roland says when he looks at it.

**No false gates.** Roland can always complete a quest by other means. Investigation observations unlock additional paths — a more direct confrontation, a piece of information that skips a step, an option that requires no persuasion — but they are never the only path. A player who investigates everything will have more options. A player who never investigates will have fewer options but will not be locked out.

**Investigation is not a skill check.** Roland either can see something or he cannot. What governs whether a detail is visible is proximity and attention (the player took the time to look), not a dice roll or a skill threshold. The difficulty is in knowing what to look for and knowing what it means, not in passing a perception check.

---

## Investigation Points

An **investigation point** is any world object Roland can examine. They are divided by what they yield.

### Type 1 — Ambient Observation

Roland notes something. A line of internal monologue plays or appears as a brief bark. Nothing is added to the journal. These are the world breathing — they build atmosphere and reinforce the setting without generating mechanical output.

**Example:** Roland examines an old fireplace in an abandoned mill. *"Cold ash. Weeks at least. No one has used this in a long time."*

**Trigger:** Walk within interact radius + press E. Or pass close enough that the observation fires as a proximity bark (no E required for the most obvious ambient details).

**Volume:** Most examination objects in a scene. Numerous, cheap to author.

---

### Type 2 — Relevant Observation

Roland finds something that matters. A journal entry is created or updated. This observation may unlock a dialogue option in a subsequent conversation, or confirm/contradict something Roland already suspects.

**Example:** In Henrietta's quarters (Act I), Roland examines the correspondence on her desk. *"She was corresponding with someone in Solgrade — the seal is House Korvath's. That's not a name Tomlin mentioned."* Journal update: "Henrietta — Korvath connection noted."

**Trigger:** Walk within interact radius + press E. Unlike ambient observations, these do not fire as proximity barks. The player must choose to examine.

**Visual indicator:** A subtle pulse on the object when Roland is close — not an intrusive floating icon, but a brief shimmer in the world that a player paying attention will notice. Players who look at the right things find the right things.

**Volume:** 3–6 per scene. The ones that matter are outnumbered by ambient observations, so finding them feels like discovery.

---

### Type 3 — Deduction Trigger

Two or more Relevant Observations, when both are in Roland's journal, unlock a **deduction** — a conclusion Roland draws from combining what he knows. Deductions unlock the most powerful dialogue options and sometimes change the available story outcomes.

**Example:** Roland has examined the Korvath seal in Henrietta's quarters (Observation A) AND has spoken to the Archive's night guard and noted the replacement door lock (Observation B). Together, these unlock a deduction: *"Someone with access to the Archive knew Henrietta was going to be there. That is not a random crime."* Journal update: "Henrietta's death — inside knowledge suspected."

Deductions are never told to the player directly. The journal entry updates; Roland's available dialogue options expand. The player discovers what Roland concluded by noticing the new options in conversation.

**Volume:** 1–3 per act. The most significant deductions shape the act's resolution.

---

## The Examination Interface

Pressing E on an investigation point plays a short animation (Roland kneels, picks up, leans closer — varies by object type) and then delivers the observation as:

1. **Roland's voice** — spoken aloud if voiced (Tier 1 bark-equivalent), or
2. **Text overlay** — floating near Roland's position, in his handwriting style, fades after 4–5 seconds

The two-layer delivery: voice carries the immediate emotional reaction; text ensures the player catches the content. The text overlay does not pause the game.

If the observation is a Relevant Observation (Type 2), a brief journal indicator appears in the corner: a small quill icon + the word "Noted." The player does not need to open the journal to acknowledge it.

---

## Companion Observations

When companions are present, investigation takes on a second voice. Each companion has an observational lens (per `design/SYSTEMS_DESIGN.md`):

| Companion | Observes |
|---|---|
| **Orion** | Exits, escape routes, signs of recent foot traffic, Brotherhood markers |
| **Dagna** | Structural details, old construction, geological features, underground access |
| **Corvus** *(Game Two+)* | Magical residue, alteration traces, things that should not be where they are |
| **Seren** *(Game Two+)* | Ancient detail, formal Aelorin script, things older than the room they inhabit |

When Roland examines a Type 2 observation point with a relevant companion present, the companion adds a line of their own after Roland's. This is a Tier 1 bark (brief portrait flash + short text), not a full conversation. It adds information Roland's perspective alone would not provide.

**Example:** Roland examines a cracked foundation wall in the Archive. His observation: *"Old damage. The wall has been settling for years."* Dagna, if present: *"That crack follows the grain of the stone, not a settling pattern. Something struck this wall from the outside. Hard."*

The companion observation upgrades a generic environmental note into a specific, useful one. It rewards bringing the right companion.

---

## Investigation Saturation

Roland has a **saturation limit** per scene — a finite number of objects he can meaningfully examine before his attention becomes unfocused. After examining a set number of objects, additional ambient observations stop yielding new lines (Roland says something generic like *"Nothing else here"*). Relevant Observations (Type 2) are always available regardless of saturation.

**Default limit:** 8 ambient examinations per scene. Resets when the player leaves and returns to the scene.

**Purpose:** Prevents the player from exhaustively clicking everything in a scene and reduces the feeling that investigation is a completionist task. The limit encourages looking purposefully rather than clicking every object.

The **Brainhale Tonic** (see `design/ITEM_LIBRARY.md`) raises the saturation limit by 2 for one scene. This is its only mechanical effect.

---

## Roland's Deduction Journal

The Codex tab of the Journal (`design/JOURNAL_UI.md`) has a **People** category and a **Factions** category. Relevant Observations feed into these entries, updating Roland's written notes as he learns more.

Deduction triggers create a new kind of entry: a **Conclusion** entry, marked with a different icon. These conclusions are written in Roland's voice and may contain his reasoning — which is sometimes right and sometimes incomplete. A conclusion written at the end of Act I may be revised or contradicted by Act II evidence.

**The wrong conclusion:** Roland can reach a conclusion that is incorrect if the available evidence supports a wrong interpretation. The journal will not mark it as wrong. The player discovers the error when subsequent evidence contradicts it — and a new conclusion replaces the old one. This is deliberate: Roland is not omniscient. He works from what he can see.

---

## No Quest Markers on Investigation Points

Investigation points are not marked on the map or on the HUD. The player finds them by exploring. In scenes where a specific investigation is relevant to a quest, Roland's journal will sometimes contain a directional hint written in his voice: *"I should look around this room more carefully before I decide what to say to Tomlin."* This is not a waypoint — it is Roland noting that there is more to find here.

The absence of markers is intentional and consistent with the game's broader philosophy of navigation through attention rather than UI assistance.

---

## Scene Design Rules for Investigation Points

Guidelines for authoring investigation points when building scenes:

1. **Minimum 6 ambient observations per interior scene.** The world should feel detailed.
2. **Maximum 6 ambient observations that yield truly new information** — after that they become wallpaper. Audit.
3. **1–3 Type 2 observations per scene that has an active quest component.** Non-quest scenes may have zero.
4. **Place Type 2 observations near natural sight-lines** — the player should find them by looking where someone would naturally look, not by systematically clicking every wall.
5. **At least one observation in every scene should be purely atmospheric** — not quest-related, just a detail that makes the place feel inhabited and specific.
6. **Companion-enhanced observations should feel like genuine addition**, not repetition. If Dagna's comment is just Roland's observation said differently, cut it.

---

## GDScript Implementation Notes

### InvestigationPoint node

Each examination object is a Node3D (or Area3D for proximity triggers) with an attached `InvestigationPoint.gd` script:

```gdscript
class_name InvestigationPoint
extends Area3D

@export var observation_type: int = 1    # 1 = ambient, 2 = relevant, 3 = deduction trigger
@export var observation_id: String       # unique ID; used to track in GameState
@export var roland_line: String          # text overlay content
@export var voiced_line_id: String       # audio file ID for voiced version (if voiced)
@export var journal_flag: String         # GameState flag to set on observe (Type 2+)
@export var required_companion: String   # "" = no companion required; "orion", "dagna", etc.
@export var companion_line: String       # companion's addendum (if companion present)
@export var deduction_requires: Array[String]  # flags that must be set to trigger deduction

func _on_interact():
    if GameState.get_flag("observed_" + observation_id) == "true":
        return  # already observed; don't re-trigger
    _deliver_observation()

func _deliver_observation():
    # Play animation, show text overlay, fire voiced line
    InvestigationUI.show_observation(roland_line, voiced_line_id)

    if observation_type >= 2 and journal_flag != "":
        GameState.set_flag(journal_flag, "true")
        GameState.set_flag("observed_" + observation_id, "true")
        SaveNotification.show_journal_update("Noted")
        _check_deductions()

    if required_companion != "" and PartyManager.companion_present(required_companion):
        InvestigationUI.show_companion_observation(required_companion, companion_line)

func _check_deductions():
    for flag in deduction_requires:
        if GameState.get_flag(flag) != "true":
            return  # not all required observations made yet
    # All conditions met — trigger deduction
    var deduction_id: String = "deduction_" + observation_id
    if GameState.get_flag(deduction_id) != "true":
        GameState.set_flag(deduction_id, "true")
        InvestigationUI.show_deduction(deduction_id)
```

### Saturation tracking

```gdscript
# In GameState.gd (per scene):
func get_scene_examination_count(scene_id: String) -> int:
    return int(get_flag("exam_count_" + scene_id))

func increment_examination_count(scene_id: String) -> void:
    var current: int = get_scene_examination_count(scene_id)
    set_flag("exam_count_" + scene_id, str(current + 1))

# In InvestigationPoint._on_interact() for Type 1 observations:
var count: int = GameState.get_scene_examination_count(current_scene_id)
if count >= SATURATION_LIMIT:  # default 8
    InvestigationUI.show_observation("Nothing else here.", "")
    return
GameState.increment_examination_count(current_scene_id)
_deliver_observation()
```
