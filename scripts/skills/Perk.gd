extends RefCounted
class_name Perk

# Base class for active perks. Subclasses live at
# scripts/skills/perks/{skill}/{perk_id}.gd and override the hook
# methods they care about. Subclasses MUST set `data` via _init
# or PerkRegistry will reject them at load time.

var data: PerkData = null

# Called once when the player picks the perk. Use for one-shot
# stat changes (e.g. raise max stamina by 10). Reversible via on_unpicked
# only if the perk supports Legendary refund — most don't and rely on
# SkillManager rebuilding from scratch.
func on_picked() -> void: pass
func on_unpicked() -> void: pass

# Event hooks. ctx is a Dictionary with event-specific keys. Mutating
# ctx is the canonical way to apply damage/yield modifiers — see
# SkillManager._dispatch_event for the per-hook contract.
func on_attack(ctx: Dictionary) -> void: pass
func on_parry(ctx: Dictionary) -> void: pass
func on_kill(ctx: Dictionary) -> void: pass
func on_take_damage(ctx: Dictionary) -> void: pass
func on_voxel_broken(ctx: Dictionary) -> void: pass
func on_xp_gained(ctx: Dictionary) -> void: pass
func on_potion_drunk(ctx: Dictionary) -> void: pass
func on_lock_opened(ctx: Dictionary) -> void: pass
