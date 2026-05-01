# NPCData.gd
# A Resource that holds all static data for a single NPC.
#
# HOW TO USE:
#   1. In the FileSystem panel, right-click /assets/npcs/ → New Resource → NPCData.
#   2. Fill in the fields in the Inspector.
#   3. On any NPC node, set the "npc_data" export to point to your .tres file.
#
# One .tres file per NPC. The same .tres can be shared across multiple scenes
# (e.g. Tomlin appears in two rooms — same NPCData, two nodes).

class_name NPCData
extends Resource

# ── Tier Enum ────────────────────────────────────────────────────────────────
# Determines which features are active on the NPC node.
# Higher tiers include all features of lower tiers.

enum Tier {
	BACKGROUND    = 0,  # Visual only. No script. Do not use NPC.gd at all.
	BARK          = 1,  # Fires bark lines when player is nearby.
	CONVERSATIONAL = 2, # Full Dialogic conversation + daily schedule.
	QUEST_LINKED  = 3   # Conversational + service functions + quest hooks.
}

# ── Identity ─────────────────────────────────────────────────────────────────

## Unique machine-readable ID. Use snake_case.
## Examples: "tomlin", "calla_vane", "aldenholt_vendor_03"
@export var npc_id: String = ""

## Name shown in the dialogue nameplate and bark overlay.
@export var display_name: String = ""

## Which tier this NPC belongs to.
@export var tier: Tier = Tier.BARK

# ── Voice and Portrait ────────────────────────────────────────────────────────
# Used by Dialogic timelines and the bark text overlay.

## Path to the portrait image file (256x320 px).
## Example: "res://assets/portraits/tomlin.png"
@export var portrait_path: String = ""

## TTS voice profile name — must match an entry in dialogue/CHARACTER_VOICES.md.
## Examples: "tomlin_archivist", "calla_eldermark"
@export var voice_profile: String = ""

# ── World Identity ────────────────────────────────────────────────────────────

## The faction this NPC belongs to. Used for bark tone and disposition checks.
## Examples: "iron_chalice", "korvath", "aldenholt_civilian", "none"
@export var faction: String = "none"

## The scene filename this NPC is home to (used by the schedule system).
## Example: "aldenholt_archive.tscn"
@export var home_scene: String = ""

# ── Disposition ───────────────────────────────────────────────────────────────
# Disposition is a 0–100 integer representing how this NPC feels about the player.
#   0  = Hostile (will not talk, may attack)
#   25 = Unfriendly (curt, refuses most requests)
#   50 = Neutral (default for most civilians)
#   75 = Friendly (warmer greetings, more information)
#   100 = Trusted (unlocks deepest dialogue branches)

## Starting disposition before any player actions.
@export_range(0, 100) var base_disposition: int = 50

# ── Bark Configuration (Tier 1+) ──────────────────────────────────────────────
# Bark lines themselves live in dialogue/scripts/barks/{category}/{npc_id}.txt
# and are loaded by BarkManager at runtime.
# Here you configure which triggers are ACTIVE for this NPC and their cooldowns.
#
# Format:  { "TRIGGER_ID": cooldown_seconds }
# Example: { "PLAYER_NEARBY": 60.0, "COMBAT_ENGAGE": 0.0 }
# A cooldown of 0.0 means "always fire when triggered."
# Leave empty to use BarkManager defaults for all triggers.

@export var bark_triggers: Dictionary = {}

# ── Dialogue Configuration (Tier 2+) ─────────────────────────────────────────

## Dialogic timeline name to start when the player presses E.
## Do not include the file extension — just the timeline ID.
## Example: "tomlin_sorting_room"
@export var dialogue_timeline: String = ""

## Daily schedule. Each entry is an NPCScheduleEntry resource.
## The NPC moves to the entry's location at the matching hour.
## Entries should cover 0–23 without gaps. Uncovered hours = NPC stays put.
@export var schedule: Array[Resource] = []

# ── Service Configuration (Tier 3) ────────────────────────────────────────────
# Only relevant for NPCs that provide a service to the player.

## What service this NPC offers, if any.
## Valid values: "SHOP", "INN", "SMITH", "HEALER", "TRANSPORT", ""
## Empty string means no service — this NPC is conversation-only.
@export var service_type: String = ""

## Quest IDs this NPC can hand out. Checked against GameState flags at dialogue start.
## Example: ["quest_lost_shipment", "quest_archive_key"]
@export var quest_hooks: Array[String] = []
