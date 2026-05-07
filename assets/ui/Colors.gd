extends Node

# Voxelmark UI palette — direct port of CSS custom properties from
# assets/ui/css/menus_shared.css. Single source of truth for every menu,
# HUD widget, and StyleBox in the project. theme.tres reads from these
# constants at build time; runtime per-script tinting (HP low-flash,
# rarity outlines on Slot.tscn, weather fog) reads them at runtime.
#
# Registered as an autoload named "Colors" in project.godot.
# Access pattern: `Colors.GOLD`, `Colors.PARCHMENT`, etc.

# Backgrounds
const BG_NIGHT       := Color("#0d0a07")
const BG_STONE       := Color("#1a1410")

# Oak panels (menu bodies, pause menu, save/load dialogs)
const PANEL_OAK_1    := Color("#4a2f1a")
const PANEL_OAK_2    := Color("#2e1b0d")
const PANEL_OAK_EDGE := Color("#6b4422")

# Iron panels (HUD strips, slot backgrounds, kbd chips)
const PANEL_IRON     := Color("#2a241f")
const PANEL_IRON_EDGE:= Color("#4a4038")

# Parchment (quest details, codex entries, save dialog context band)
const PARCHMENT      := Color("#e8d9b0")
const PARCHMENT_2    := Color("#d4c08c")
const PARCHMENT_EDGE := Color("#a8895a")
const PARCHMENT_INK  := Color("#3a2a14")

# Metals (button trim, accents)
const BRONZE         := Color("#b07a3a")
const BRONZE_DEEP    := Color("#6b4520")
const GOLD           := Color("#f0c14b")
const GOLD_DEEP      := Color("#a87320")
const IRON           := Color("#6e6358")
const IRON_DEEP      := Color("#3a342d")

# Status bars (HUD vitals)
const HP             := Color("#b8302a")
const HP_DEEP        := Color("#5a1410")
const HP_BRIGHT      := Color("#e84a3a")
const STAM           := Color("#c8a04a")
const HUNGER         := Color("#8a5a28")
const MANA           := Color("#3a6fb8")

# Item rarity outlines (Slot.tscn border)
const RARE_COMMON    := Color("#8a8378")
const RARE_UNCOMMON  := Color("#5fa84a")
const RARE_RARE      := Color("#4a86d8")
const RARE_EPIC      := Color("#a04ac8")
const RARE_LEGENDARY := Color("#f0a02a")

# Text
const INK            := Color("#f3e6c4")
const INK_DIM        := Color("#b4a07a")
const INK_MUTE       := Color("#7a6a4e")

# Convenience: rarity name -> color (for Slot, tooltips, codex)
const RARITY_COLORS := {
	"common": RARE_COMMON,
	"uncommon": RARE_UNCOMMON,
	"rare": RARE_RARE,
	"epic": RARE_EPIC,
	"legendary": RARE_LEGENDARY,
}
