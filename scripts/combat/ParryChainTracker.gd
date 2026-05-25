extends RefCounted
# ParryChainTracker — tracks consecutive successful parries within decaying window.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   The directional combat redesign rewards reading-the-fight: chain three
#   successful parries in quick succession and the endurance cost goes to
#   zero (each refund covers the next cost). The window for each successive
#   parry tightens — the player has to keep reading, not just spam.
#
#   Owned by MeleeHandler as a plain RefCounted (no autoload, no node).
#
#   API:
#     register_parry()   → call right after a successful parry. Returns
#                          the NEW chain count.
#     break_chain()      → optional explicit break (used by a missed parry
#                          or a successful enemy hit). The auto-decay
#                          handles "didn't parry in time"; explicit break
#                          is cheaper than waiting for the timeout.
#     tick(delta)        → MeleeHandler calls each frame; ticks the
#                          remaining window. When it hits zero the chain
#                          breaks automatically.
#     current_chain_count → exposed for HUDOverlay chain-count label.
#     should_refund_endurance(base_cost) → bool. True for chained parries
#                          (chain ≥ 2); MeleeHandler refunds full cost.
#
# WINDOW SCHEDULE (per design):
#     chain 1 → 1.0 s to land the next parry
#     chain 2 → 0.7 s
#     chain 3 → 0.5 s
#     chain 4+ → stays at 0.5 s
#   Missing within the window = chain breaks (next parry resets to 1).

const _WINDOW_BY_CHAIN: Array[float] = [
	0.0,   # 0: no chain active (placeholder so chain index aligns)
	1.0,   # 1
	0.7,   # 2
	0.5,   # 3
	0.5,   # 4+
]

var current_chain_count: int = 0
var _window_remaining: float = 0.0


# Returns the new chain count.
func register_parry() -> int:
	current_chain_count += 1
	_window_remaining = _window_for_chain(current_chain_count)
	return current_chain_count


func break_chain() -> void:
	current_chain_count = 0
	_window_remaining = 0.0


func tick(delta: float) -> void:
	if current_chain_count <= 0:
		return
	_window_remaining -= delta
	if _window_remaining <= 0.0:
		break_chain()


# Chained parries (count ≥ 2) refund their full endurance cost — net zero
# EP. The first parry pays normally; the chain is the reward for the
# successive reads.
func should_refund_endurance() -> bool:
	return current_chain_count >= 2


func _window_for_chain(chain: int) -> float:
	if chain <= 0:
		return 0.0
	if chain >= _WINDOW_BY_CHAIN.size():
		return _WINDOW_BY_CHAIN[_WINDOW_BY_CHAIN.size() - 1]
	return _WINDOW_BY_CHAIN[chain]
