class_name DiceHandResult
extends RefCounted
# DiceHandResult — the evaluated rank of a 5-die hand, plus tiebreaker dice.
#
# Hand ranks (ascending):
#   HIGH_CARD < PAIR < TWO_PAIR < THREE_KIND < STRAIGHT < FULL_HOUSE
#     < FOUR_KIND < FIVE_KIND
#
# Straight is "large straight only" — exactly 1-2-3-4-5 or 2-3-4-5-6.
# A run of four (e.g., 1-2-3-4-6) is HIGH_CARD here, not STRAIGHT.
#
# Tiebreaker dice are stored in priority order. compare() walks them
# left-to-right and returns the first non-zero difference. If both
# arrays are equal at every index, hands tie (returns 0).

enum HandRank {
	HIGH_CARD,
	PAIR,
	TWO_PAIR,
	THREE_KIND,
	STRAIGHT,
	FULL_HOUSE,
	FOUR_KIND,
	FIVE_KIND,
}

var rank: HandRank = HandRank.HIGH_CARD
var tiebreaker: PackedInt32Array = PackedInt32Array()


func compare(other: DiceHandResult) -> int:
	# Returns -1 if self loses, +1 if self wins, 0 if hands tie.
	if rank > other.rank:
		return 1
	if rank < other.rank:
		return -1
	# Same rank — walk tiebreaker arrays.
	var n: int = min(tiebreaker.size(), other.tiebreaker.size())
	for i in n:
		if tiebreaker[i] > other.tiebreaker[i]:
			return 1
		if tiebreaker[i] < other.tiebreaker[i]:
			return -1
	return 0


func rank_label() -> String:
	# Human-readable label for UI. Keeps the canonical wording in one place.
	match rank:
		HandRank.HIGH_CARD: return "High Card"
		HandRank.PAIR: return "Pair"
		HandRank.TWO_PAIR: return "Two Pair"
		HandRank.THREE_KIND: return "Three of a Kind"
		HandRank.STRAIGHT: return "Straight"
		HandRank.FULL_HOUSE: return "Full House"
		HandRank.FOUR_KIND: return "Four of a Kind"
		HandRank.FIVE_KIND: return "Five of a Kind"
	return "?"
