class_name DiceHand
extends RefCounted
# DiceHand — the live state of a 5-die roll: face values + lock flags.
#
# Faces are 1..6 (inclusive). A locked die is preserved across re-rolls;
# an unlocked die is re-rolled when roll_unlocked() is called.
#
# This class is data-only — it does not own RNG state and does not draw
# anything. The 3D table (DiceTable3D) handles physics; this class
# carries the canonical face values and the rank evaluator.

const DIE_COUNT: int = 5

var dice: PackedInt32Array = PackedInt32Array()      # 5 entries, 1..6
var locked: Array[bool] = [false, false, false, false, false]


func _init() -> void:
	dice.resize(DIE_COUNT)
	for i in DIE_COUNT:
		dice[i] = 1


func roll_all(rng: RandomNumberGenerator) -> void:
	# Rolls every die, ignoring lock state. Used for the opening roll.
	for i in DIE_COUNT:
		dice[i] = rng.randi_range(1, 6)


func roll_unlocked(rng: RandomNumberGenerator) -> void:
	# Rolls only the dice that are NOT locked. Used for re-rolls.
	for i in DIE_COUNT:
		if not locked[i]:
			dice[i] = rng.randi_range(1, 6)


func toggle_lock(idx: int) -> void:
	if idx < 0 or idx >= DIE_COUNT:
		return
	locked[idx] = not locked[idx]


func clear_locks() -> void:
	for i in DIE_COUNT:
		locked[i] = false


func unlocked_count() -> int:
	var n: int = 0
	for i in DIE_COUNT:
		if not locked[i]:
			n += 1
	return n


func evaluate() -> DiceHandResult:
	# Counts each face, then matches against rank patterns from highest
	# to lowest. Tiebreaker dice are populated per-rank: the matched
	# pattern's face value first, then any kicker dice descending.

	var counts: Dictionary = {}   # face → occurrences
	for face in dice:
		counts[face] = counts.get(face, 0) + 1

	var faces_by_count: Dictionary = {}   # occurrences → Array[int faces]
	for face in counts.keys():
		var c: int = counts[face]
		var arr: Array = faces_by_count.get(c, [])
		arr.append(face)
		faces_by_count[c] = arr

	# Sort each count bucket descending so the highest face comes first.
	for c in faces_by_count.keys():
		(faces_by_count[c] as Array).sort_custom(func(a, b): return a > b)

	var result: DiceHandResult = DiceHandResult.new()

	# 5K
	if faces_by_count.has(5):
		result.rank = DiceHandResult.HandRank.FIVE_KIND
		result.tiebreaker = PackedInt32Array([faces_by_count[5][0]])
		return result

	# 4K
	if faces_by_count.has(4):
		var quad_face: int = faces_by_count[4][0]
		var kicker: int = faces_by_count[1][0]
		result.rank = DiceHandResult.HandRank.FOUR_KIND
		result.tiebreaker = PackedInt32Array([quad_face, kicker])
		return result

	# Full House (3 + 2)
	if faces_by_count.has(3) and faces_by_count.has(2):
		result.rank = DiceHandResult.HandRank.FULL_HOUSE
		result.tiebreaker = PackedInt32Array([faces_by_count[3][0], faces_by_count[2][0]])
		return result

	# Straight — large straight only: exactly 1-2-3-4-5 or 2-3-4-5-6.
	# That means we need exactly 5 distinct faces AND the (max - min) == 4.
	if counts.size() == 5:
		var sorted: Array = counts.keys()
		sorted.sort()
		if int(sorted[4]) - int(sorted[0]) == 4:
			result.rank = DiceHandResult.HandRank.STRAIGHT
			result.tiebreaker = PackedInt32Array([int(sorted[4])])
			return result

	# 3K
	if faces_by_count.has(3):
		var trip_face: int = faces_by_count[3][0]
		var singles: Array = faces_by_count.get(1, [])
		result.rank = DiceHandResult.HandRank.THREE_KIND
		var tb: Array[int] = [trip_face]
		for s in singles:
			tb.append(int(s))
		result.tiebreaker = PackedInt32Array(tb)
		return result

	# Two Pair
	if faces_by_count.has(2) and (faces_by_count[2] as Array).size() == 2:
		var pairs: Array = faces_by_count[2]
		var single_faces: Array = faces_by_count.get(1, [])
		result.rank = DiceHandResult.HandRank.TWO_PAIR
		var tb2: Array[int] = [int(pairs[0]), int(pairs[1])]
		for s in single_faces:
			tb2.append(int(s))
		result.tiebreaker = PackedInt32Array(tb2)
		return result

	# Pair
	if faces_by_count.has(2):
		var pair_face: int = faces_by_count[2][0]
		var single_kickers: Array = faces_by_count.get(1, []).duplicate()
		single_kickers.sort_custom(func(a, b): return a > b)
		result.rank = DiceHandResult.HandRank.PAIR
		var tb3: Array[int] = [pair_face]
		for s in single_kickers:
			tb3.append(int(s))
		result.tiebreaker = PackedInt32Array(tb3)
		return result

	# High Card — every face descending.
	var sorted_faces: Array = []
	for face in dice:
		sorted_faces.append(int(face))
	sorted_faces.sort_custom(func(a, b): return a > b)
	var tb4: Array[int] = []
	for s in sorted_faces:
		tb4.append(int(s))
	result.rank = DiceHandResult.HandRank.HIGH_CARD
	result.tiebreaker = PackedInt32Array(tb4)
	return result


func clone() -> DiceHand:
	# Used by the AI to evaluate hypothetical rolls without disturbing
	# the live hand on the table.
	var copy: DiceHand = DiceHand.new()
	copy.dice = dice.duplicate()
	copy.locked = locked.duplicate()
	return copy
