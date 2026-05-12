extends Object
class_name SkillCurve

# Skyrim XP curve: xp_to_next_level(L) = 25 * L^1.95.
# Total XP to reach level N from level 1 = sum(xp_to_next_level(1..N-1)).
# Cap = 100. Total to cap ≈ 430,000 XP. L99 → L100 alone is ≈ 32,000 XP.
# All callers go through SkillManager — this class is pure math.

const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 100
const LEGENDARY_RESET_LEVEL: int = 15
const PERK_MILESTONE_INTERVAL: int = 4  # perk milestones at L4, L8, ..., L100 (25 total)

# XP required to advance from `current_level` to `current_level + 1`.
# At current_level >= MAX_LEVEL this returns 0 (no further XP accepted).
static func xp_to_next_level(current_level: int) -> float:
	if current_level >= MAX_LEVEL:
		return 0.0
	var lvl: float = float(max(current_level, MIN_LEVEL))
	return 25.0 * pow(lvl, 1.95)

# Return new (level, leftover_xp_progress) after applying `amount` XP at
# the given starting state. Handles multi-level jumps if amount is huge.
static func apply_xp(current_level: int, xp_progress: float, amount: float) -> Array:
	var lvl: int = current_level
	var prog: float = xp_progress + amount
	while lvl < MAX_LEVEL:
		var need: float = xp_to_next_level(lvl)
		if prog < need:
			break
		prog -= need
		lvl += 1
	if lvl >= MAX_LEVEL:
		prog = 0.0  # cap stops accumulation
	return [lvl, prog]

# How many perk milestones a skill at this level has unlocked.
# Level 4 → 1 milestone, level 100 → 25 milestones.
static func milestones_unlocked(level: int) -> int:
	return level / PERK_MILESTONE_INTERVAL

# Which milestone index (0..24) does the level just-reached unlock, if any?
# Returns -1 if this level didn't cross a milestone boundary.
static func milestone_for_level(level: int) -> int:
	if level <= 0 or level > MAX_LEVEL:
		return -1
	if level % PERK_MILESTONE_INTERVAL != 0:
		return -1
	return (level / PERK_MILESTONE_INTERVAL) - 1
