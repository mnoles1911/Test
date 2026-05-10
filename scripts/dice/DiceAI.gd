class_name DiceAI
extends RefCounted
# DiceAI — naive single-tier opponent for v1.
#
# Heuristic: lock anything appearing twice or more. If no pairs at all,
# lock the single highest die (chase a higher pair / partial straight).
# Always uses both rerolls if any unlocked die remains.
#
# The aggression parameter is accepted but ignored in v1 — slot for
# tuning when we add Novice / Veteran / Master tiers.


static func decide_locks(hand: DiceHand, _reroll_index: int, _aggression: float) -> Array[bool]:
	# Returns a 5-element bool array: true = lock that die for the next reroll.
	var locks: Array[bool] = [false, false, false, false, false]

	var counts: Dictionary = {}
	for face in hand.dice:
		counts[face] = counts.get(face, 0) + 1

	var has_pair_or_better: bool = false
	for face in counts.keys():
		if counts[face] >= 2:
			has_pair_or_better = true
			break

	if has_pair_or_better:
		# Lock every die whose face appears 2+ times.
		for i in DiceHand.DIE_COUNT:
			if counts[hand.dice[i]] >= 2:
				locks[i] = true
		return locks

	# All five dice unique — lock only the highest single.
	var max_face: int = 0
	var max_idx: int = 0
	for i in DiceHand.DIE_COUNT:
		if hand.dice[i] > max_face:
			max_face = hand.dice[i]
			max_idx = i
	locks[max_idx] = true
	return locks
