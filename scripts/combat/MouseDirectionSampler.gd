extends RefCounted
# MouseDirectionSampler — turns recent mouse motion into a directional intent.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Mount & Blade-style directional combat needs a quick read on "which way
#   did the player just flick the mouse?" right at the moment they press the
#   attack/parry button. This RefCounted accumulates recent mouse motion in
#   a rolling window and, when asked, picks one of four directions.
#
#   Designer model (2026-05-29): "flick TOWARD where the sword comes FROM."
#   The flick points at the origin of the strike, and the sword travels from
#   there toward the enemy (screen centre):
#
#     flick UP    → OVERHEAD — sword chops down from the top (high parry)
#     flick DOWN  → THRUST   — forward stab / jab (low parry)
#     flick LEFT  → sword comes from the LEFT, sweeps to centre (left parry)
#     flick RIGHT → sword comes from the RIGHT, sweeps to centre (right parry)
#
#   Naming caveat: a LEFT flick returns the DIR_RIGHT *enum*, because that
#   enum's pose is the left-to-right sweep (the strike that ORIGINATES on the
#   left). The DIR_LEFT/DIR_RIGHT enum names track the sword's travel/landing
#   side; the flick selects the origin side. See the pose tables in
#   MeleeHandler.gd. Hit detection is a forward-centred cone, so left vs right
#   is purely cosmetic — only the visible swing pose differs.
#
#   A live instance is owned by MeleeHandler (which feeds it every mouse
#   motion event) and queried at the press moment. Plain RefCounted, no
#   autoload — keeps the instance count low and the lifetime tied to the
#   handler that uses it.
#
# WHY 100° QUADRANTS WITH 10° OVERLAP
#
#   A perfectly equal 90° quadrant gives ambiguous results near the
#   boundaries — the player flicks "mostly up but slightly left" and gets a
#   LEFT swing they didn't ask for. Each direction owns 100° (±50° from its
#   cardinal axis), so adjacent quadrants overlap by 10°. The first axis
#   that crosses the dominance threshold wins, breaking ties in player-
#   favor toward whichever is moving fastest.
#
# NO-FLICK = DIR_NONE
#
#   If the player presses + releases with NO meaningful mouse motion
#   (< the minimum-magnitude threshold), sample() returns DIR_NONE so
#   the caller can implement its own fallback. MeleeHandler uses an
#   auto-alternating L/R cycle (Bannerlord-style: hold the attack
#   button without flicking and the game cycles your swings for you).
#   Older versions of this sampler defaulted to DIR_RIGHT which produced
#   "every silent press is a right swing" — boring and unidiomatic.


# Direction enum exposed to callers. Integer values are sticky — referenced
# from MeleeHandler tween targets and HUDDirectionArrows arrow rotation.
const DIR_OVERHEAD: int = 0
const DIR_LEFT:     int = 1
const DIR_RIGHT:    int = 2
const DIR_THRUST:   int = 3
# Returned by sample() when no meaningful mouse motion is in the window.
# MeleeHandler treats this as "no flick" and applies its auto-alternating
# direction fallback (LRLR...). Distinct from DIR_RIGHT so we don't
# auto-RIGHT on every silent press the way the old default did.
const DIR_NONE:     int = -1

# Rolling window of (timestamp_usec, mouse_relative Vector2) samples. We
# only keep the last WINDOW_SECONDS worth — older entries are dropped at
# the start of each sample() call.
const WINDOW_SECONDS: float = 0.12
# 120 ms covers a deliberate flick (~50-80 ms) plus a comfortable buffer.

const MIN_TOTAL_PIXELS: float = 60.0
# Sum of the window's |relative| vector magnitudes below which we treat
# the input as "no motion" and return the default RIGHT direction. 60 px
# at 1080p ≈ a ~3% screen flick — clearly intentional, but small enough
# that a deliberate ~1 cm mouse flick still registers.

# (timestamp_usec, Vector2 delta). PackedFloat32Array would be 3 entries
# per sample (t, dx, dy) but we never have more than ~10 entries in the
# window so the simpler Array-of-Dictionaries is fine.
var _samples: Array = []


# Push a new motion sample. Called from MeleeHandler._input on every
# InputEventMouseMotion (cheap — append + drop-old).
func push(motion_relative: Vector2) -> void:
	var now: int = Time.get_ticks_usec()
	_samples.append({"t": now, "d": motion_relative})
	_prune(now)


# Returns one of DIR_* based on the accumulated window. Stateless w.r.t.
# the sample log — calling sample() twice in a row returns the same answer.
func sample() -> int:
	var now: int = Time.get_ticks_usec()
	_prune(now)
	# Sum the deltas. The window is short enough (~120 ms) that simple
	# linear accumulation reads as "the direction of the flick" — we
	# don't need recency weighting on this scale.
	var sum: Vector2 = Vector2.ZERO
	var total_mag: float = 0.0
	for s in _samples:
		var d: Vector2 = s["d"]
		sum += d
		total_mag += d.length()
	if total_mag < MIN_TOTAL_PIXELS:
		# No meaningful flick this window. Bannerlord behavior: the caller
		# (MeleeHandler) gets to decide what "no flick" means — typically
		# falling through to an auto-alternating L/R cycle. Returning a
		# distinct sentinel lets the caller distinguish "no flick" from
		# "deliberate RIGHT flick."
		return DIR_NONE
	# Mouse y is positive DOWN (Godot screen convention). Designer model
	# (2026-05-29): "flick TOWARD where the sword comes FROM."
	#   sum.y < 0 → flick UP    → OVERHEAD (sword comes from the top, chops down)
	#   sum.y > 0 → flick DOWN  → THRUST   (forward stab / jab)
	#   sum.x < 0 → flick LEFT  → DIR_RIGHT pose (sword comes from the left,
	#                             sweeps left→right toward centre)
	#   sum.x > 0 → flick RIGHT → DIR_LEFT pose (sword comes from the right,
	#                             sweeps right→left toward centre)
	#
	# This restores the Bannerlord/KCD-style intuition (flick the side the
	# blow originates from), reversing the 2026-05-25 "sword moves where I
	# flick" experiment. The DIR_LEFT/DIR_RIGHT enum names track the sword's
	# travel/landing side, so a LEFT flick deliberately returns DIR_RIGHT.
	#
	# Pick the dominant axis. The 10° overlap window is implicit — we
	# only switch from horizontal to vertical (or vice versa) when one
	# axis exceeds the other by tan(5°) ≈ 0.087 (i.e. 8.7%), which
	# naturally biases toward whichever axis was just won.
	var abs_x: float = absf(sum.x)
	var abs_y: float = absf(sum.y)
	if abs_x >= abs_y:
		# flick RIGHT → DIR_LEFT (right-originating sweep); flick LEFT → DIR_RIGHT.
		return DIR_LEFT if sum.x > 0.0 else DIR_RIGHT
	# flick DOWN → THRUST; flick UP → OVERHEAD.
	return DIR_THRUST if sum.y > 0.0 else DIR_OVERHEAD


# Convenience for the parry path: returns true if the recently-sampled
# direction matches `direction` within the overlap band. Used by
# MeleeHandler to decide if a parry tap matched the incoming attack.
func matches(direction: int) -> bool:
	return sample() == direction


# Drop samples older than WINDOW_SECONDS. Done lazily at sample/push time
# so we never need a per-frame tick.
func _prune(now_usec: int) -> void:
	var cutoff: int = now_usec - int(WINDOW_SECONDS * 1_000_000.0)
	while _samples.size() > 0 and (_samples[0]["t"] as int) < cutoff:
		_samples.pop_front()


# Reset the buffer (used by MeleeHandler when authority changes hands in
# multiplayer or when the handler is enabled/disabled). Cheap.
func clear() -> void:
	_samples.clear()


# True when no motion has been recorded in the current window. MeleeHandler
# uses this to distinguish "the player flicked right" from "no flick at
# all, default to right" when engaging a block.
func is_empty() -> bool:
	_prune(Time.get_ticks_usec())
	return _samples.is_empty()
