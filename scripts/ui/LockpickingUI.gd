class_name LockpickingUI
extends CanvasLayer
# LockpickingUI — the full lockpicking minigame overlay.
#
# What this does in plain English:
#   When Roland presses E at a locked object this overlay appears. The world
#   blurs behind it but keeps running — time passes, enemies patrol. The
#   player sweeps A/D to rotate a pick indicator around a circular dial,
#   listens for the resonance feedback (glow + pitch change), then holds
#   still at the peak to "set" the pin. Set all real pins to open the lock.
#   Hold at the wrong position too long and the pick snaps.
#
# HOW TO OPEN FROM CODE:
#   var ui := LockpickingUI.new()
#   get_tree().root.add_child(ui)
#   ui.lock_opened.connect(_on_lock_opened)
#   ui.lock_closed.connect(_on_lock_closed)
#   ui.open(my_lock_data)
#
# HOW TO ADD ART TEXTURES:
#   After creating the instance, assign the texture exports on the
#   _lock_face child before calling open():
#     ui.set_art(face_tex, keyhole_tex, pick_tex, glow_tex)
#
# This script builds ALL its child nodes in _ready() — no separate .tscn needed.
# Debug mode variables can be set from the outside (LockpickTestBootstrap does this).


# ─── SIGNALS ───────────────────────────────────────────────────────────────

signal lock_opened(lock_id: String)
# Fired when all pins are set and the lock clicks open.

signal lock_closed()
# Fired when the overlay closes for any reason (opened, cancelled, no picks).


# ─── TUNABLE CONSTANTS ─────────────────────────────────────────────────────
# LockpickTestBootstrap exposes these via debug sliders so the designer can
# tune feel at runtime. All are var (not const) so they can be overridden.

var ROTATE_SPEED_DEG: float       = 90.0
# Degrees per second the pick rotates while holding A or D.

var HOLDING_STILL_THRESHOLD: float = 8.0
# Degrees per second — below this the pick is considered "held still."
# Below this threshold the hold-timer starts ticking and the set bar fills.

var BASE_FILL_RATE: float          = 0.65
# Set-bar progress filled per second at resonance intensity 1.0 (dead centre).
# At intensity 0.5 the effective fill rate is 0.65 × 0.5 = 0.325/s.
# A dead-centre Novice pin sets in ~1.5s — well within the 2.5s hold timer.

var DRAIN_RATE_MOVING: float       = 1.5
# Set-bar progress drained per second while the pick is moving.

var DRAIN_RATE_STILL: float        = 0.4
# Set-bar progress drained per second while holding still OFF a resonance zone.

var SNAP_ANIM_DURATION: float      = 0.7
# Seconds the "pick snapped" state shows before the player can retry.

var BACK_PRESSURE_MIN_DIST: float  = 130.0
# Degrees from the nearest set pin beyond which sweeping fast = snap risk.
# E.g. if the first pin was at 60°, the zone beyond 190° (60+130) is dangerous.

# Resonance zone half-width in degrees, indexed by lock tier.
# A pin at position P is detectable within [P - zone, P + zone].
var RESONANCE_ZONE_DEG: Dictionary = {0: 40.0, 1: 25.0, 2: 15.0, 3: 8.0}

# Hold timer in seconds before a snap, indexed by player SKILL tier (not lock tier).
# Skill tier: 0=Novice, 1=Trained, 2=Expert.
var HOLD_TIMER_BY_SKILL: Dictionary = {0: 2.5, 1: 3.5, 2: 5.0}
const FINE_PICK_BONUS: float        = 1.5
# Bonus seconds added to the hold timer when using a Fine Lockpick.

# Back-pressure snap velocity threshold in degrees/sec, by lock tier.
# 0.0 = no back-pressure on that tier. Hard/Very Hard only.
var SNAP_VEL_BY_TIER: Dictionary    = {0: 0.0, 1: 0.0, 2: 110.0, 3: 70.0}


# ─── TIER METADATA ─────────────────────────────────────────────────────────

const TIER_LABELS: Array    = ["Easy", "Medium", "Hard", "Very Hard"]
const TIER_COLORS: Array    = [
	Color("#50c878"),   # Easy — green
	Color("#f0c14b"),   # Medium — gold
	Color("#f0a02a"),   # Hard — amber
	Color("#b8302a"),   # Very Hard — red
]
const DEFAULT_BARKS: Array  = [
	"Cheap iron. I could open this with a bent nail.",
	"Standard work. Two pins, maybe. Someone put thought into this.",
	"Three pins at least. Whoever installed this didn't want it opened.",
	"Masterwork cylinder. Fine tolerances. I'd need steady hands and some luck.",
]
# Number of false resonances generated per tier.
const FALSE_COUNT_BY_TIER: Array = [0, 0, 1, 2]


# ─── DEBUG FLAGS (set from LockpickTestBootstrap) ──────────────────────────

var debug_mode: bool                 = false
# Master switch. When true, debug overlays are possible.

var debug_show_pins: bool            = false
var debug_show_zones: bool           = false
var debug_show_back_pressure: bool   = false
var debug_show_hold_timer: bool      = false


# ─── NODES (built in _build_ui) ────────────────────────────────────────────

var _overlay:        ColorRect         # full-screen dim behind the panel
var _panel:          PanelContainer    # oak-styled central panel
var _tier_label:     Label             # "Easy / Medium / Hard / Very Hard"
var _pick_label:     Label             # "Picks: 7 (3 Fine)"
var _lock_face:      LockFaceControl   # the animated dial
var _set_bar:        ProgressBar       # 0–1 fills as pin is being set
var _pin_row:        HBoxContainer     # row of pin icons
var _hint_label:     Label             # "Hold steady…" / "Pick snapped!" / etc.
var _status_label:   Label             # brief status shown on open/snap/unlock

var _snap_anim:      AnimatedSprite2D  # pick-snap particle (optional art)
var _pin_flash_anim: AnimatedSprite2D  # pin-set confirmation flash (optional art)
var _unlock_anim:    AnimatedSprite2D  # lock-open animation (optional art)
var _false_stall_anim: AnimatedSprite2D # false-pin stall loop (optional art)
var _resonance_pulse_anim: AnimatedSprite2D # ambient pulse while on real-pin resonance

# Audio players. Streams are loaded from res://assets/audio/lockpicking/*.ogg
# in _build_audio(). Missing files fail silently — overlay still works mute.
var _sfx_sweep:     AudioStreamPlayer  # looping; modulated by sweep velocity
var _sfx_resonance: AudioStreamPlayer  # looping; pitch+vol track real-pin intensity
var _sfx_false:     AudioStreamPlayer  # looping; plays on false-pin resonance
var _sfx_pin_set:   AudioStreamPlayer  # one-shot
var _sfx_snap:      AudioStreamPlayer  # one-shot
var _sfx_open:      AudioStreamPlayer  # one-shot

# Reference to the pin icon labels so we can colour them as pins set.
var _pin_icons: Array[Label] = []


# ─── GAME STATE ────────────────────────────────────────────────────────────

var _lock_data: LockData
var _active_pins: Array = []
# Array of Dictionaries: { pos_deg: float, is_false: bool, is_set: bool }

var _pins_set: int         = 0

var _current_angle_deg: float  = 0.0   # current pick position
var _sweep_vel_deg: float      = 0.0   # angular velocity this frame (deg/s)

var _resonance_intensity: float = 0.0  # 0–1 how close to nearest unset pin
var _nearest_pin_idx: int       = -1   # index into _active_pins
var _on_false_pin: bool         = false

var _set_progress: float = 0.0  # 0–1, drives the set bar
var _hold_timer: float   = 0.0  # counts down while holding near a pin
var _is_holding: bool    = false  # true when hold-timer is ticking

var _pick_type: String   = "lockpick_standard"  # which pick is in use this attempt

var _snapping: bool      = false   # true during the snap animation delay
var _snap_timer: float   = 0.0

var _is_open: bool       = false   # true while the overlay is visible

# Skill tier: 0=Novice, 1=Trained, 2=Expert.
# Wire to SkillManager.get_subskill_tier("lockpicking") when that system lands.
var _skill_tier: int = 0


# ─── LIFECYCLE ─────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10            # above the world (HUDOverlay is layer 5)
	_build_ui()
	hide()


func open(lock_data: LockData) -> void:
	# Called by LockObject3D (or test bootstrap) to start a lockpicking attempt.
	_lock_data = lock_data
	_pick_type = _choose_pick_type()
	if _pick_type == "":
		# Caller should have checked, but guard anyway.
		_hint_label.text = "No picks."
		return

	_generate_pins()
	_pins_set        = 0
	_current_angle_deg = 0.0
	_set_progress    = 0.0
	_hold_timer      = _get_hold_timer()
	_is_holding      = false
	_snapping        = false
	_resonance_intensity = 0.0
	_sweep_vel_deg   = 0.0

	_refresh_ui()
	_refresh_pin_icons()
	show()
	_is_open = true
	_hint_label.text = "Sweep to find the pins."


func close() -> void:
	# Clean up: remove from scene tree after emitting the signal.
	_is_open = false
	_stop_all_loops()
	_stop_all_anims()
	hide()
	lock_closed.emit()
	# Give one frame for signal receivers before freeing.
	await get_tree().process_frame
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()


func set_art(face_tex: Texture2D, keyhole_tex: Texture2D,
             pick_tex: Texture2D, glow_tex: Texture2D) -> void:
	# Assign optional art textures BEFORE calling open().
	_lock_face.lock_face_texture = face_tex
	_lock_face.keyhole_texture   = keyhole_tex
	_lock_face.pick_texture      = pick_tex
	_lock_face.glow_texture      = glow_tex


# ─── MAIN LOOP ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _is_open:
		return

	# ── Snap animation hold ──────────────────────────────────────────────
	if _snapping:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snapping = false
			if not _check_has_picks():
				_hint_label.text = "No picks remaining."
				await get_tree().create_timer(1.2).timeout
				close()
			else:
				# Ready for next attempt.
				_pick_type  = _choose_pick_type()
				_hold_timer = _get_hold_timer()
				_set_progress = 0.0
				_hint_label.text = "Sweep to find the pins."
				_refresh_ui()
		return

	# ── Rotate pick from A/D input ────────────────────────────────────────
	# get_axis returns -1.0 (left/A) to +1.0 (right/D).
	var axis: float    = Input.get_axis("ui_left", "ui_right")
	var delta_angle: float = axis * ROTATE_SPEED_DEG * delta
	_current_angle_deg = fmod(_current_angle_deg + delta_angle + 360.0, 360.0)

	# Sweep velocity in degrees per second (used for back-pressure check).
	# Divide by delta with a tiny epsilon to avoid division-by-zero.
	_sweep_vel_deg = delta_angle / maxf(delta, 0.0001)

	# ── Resonance check ───────────────────────────────────────────────────
	_update_resonance()

	# ── Hold-timer and set-bar logic ──────────────────────────────────────
	var still: bool = absf(_sweep_vel_deg) < HOLDING_STILL_THRESHOLD

	if _resonance_intensity > 0.0 and still:
		# Player has stopped near a pin — start or continue the hold timer.
		if not _is_holding:
			_hold_timer  = _get_hold_timer()
			_is_holding  = true

		_hold_timer -= delta

		# Set bar fills proportional to resonance intensity.
		# False pins cap at 0.5 so the bar visibly stalls — that's the tell.
		var fill_cap: float = 0.5 if _on_false_pin else 1.0
		_set_progress = minf(
			_set_progress + BASE_FILL_RATE * _resonance_intensity * delta,
			fill_cap
		)

		if _set_progress >= 1.0:
			_set_pin()
			return  # _set_pin may call close() if last pin

		if _hold_timer <= 0.0:
			_snap_pick()
			return

		# Update hint based on state.
		if _on_false_pin and _set_progress >= 0.48:
			_hint_label.text = "Something's wrong…"
		else:
			_hint_label.text = "Hold steady…"

	else:
		# Moving, or not near any pin — drain the set bar.
		_is_holding = false
		var drain: float = DRAIN_RATE_MOVING if not still else DRAIN_RATE_STILL
		_set_progress = maxf(_set_progress - drain * delta, 0.0)

		if still and _resonance_intensity <= 0.0:
			_hint_label.text = "Sweep to find the pins." if _pins_set == 0 \
			                   else "Find the next pin."

		# Back-pressure snap (Hard / Very Hard only, after first pin sets).
		if _pins_set > 0 and _lock_data.tier >= 2:
			var snap_thresh: float = SNAP_VEL_BY_TIER[_lock_data.tier]
			if snap_thresh > 0.0 and absf(_sweep_vel_deg) > snap_thresh:
				if _in_back_pressure_zone(_current_angle_deg):
					_snap_pick()
					return

	# ── Push state to the lock face visual ───────────────────────────────
	_lock_face.angle_deg          = _current_angle_deg
	_lock_face.resonance_intensity = _resonance_intensity
	_lock_face.on_false_pin       = _on_false_pin
	_lock_face.set_progress       = _set_progress

	# Debug overlays.
	if debug_mode:
		_lock_face.debug_show_pins         = debug_show_pins
		_lock_face.debug_show_zones        = debug_show_zones
		_lock_face.debug_show_back_pressure = debug_show_back_pressure
		_lock_face.debug_show_hold_timer   = debug_show_hold_timer
		_lock_face._debug_pins             = _active_pins
		_lock_face._debug_zone_deg         = RESONANCE_ZONE_DEG[_lock_data.tier] / 2.0
		_lock_face._debug_hold_timer_frac  = clampf(
			_hold_timer / _get_hold_timer(), 0.0, 1.0
		) if _is_holding else 1.0
		_update_back_pressure_debug()

	_lock_face.queue_redraw()

	# ── Update set bar colour ─────────────────────────────────────────────
	var stall_color: bool = _on_false_pin and _set_progress >= 0.48
	var bar_fill_sb: StyleBoxFlat = _set_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if bar_fill_sb:
		bar_fill_sb.bg_color = Color("#b8302a") if stall_color else Color("#f0c14b")

	# ── Update audio loops ────────────────────────────────────────────────
	_update_audio_loops()

	# ── Update resonance pulse animation (looping, intensity-driven alpha) ─
	_update_resonance_pulse_anim()


func _update_resonance_pulse_anim() -> void:
	# Plays the looping resonance glow only while we're on a real pin.
	# Alpha rides resonance_intensity so it fades in/out smoothly.
	var on_real: bool = _resonance_intensity > 0.0 and not _on_false_pin
	var sf: SpriteFrames = _resonance_pulse_anim.sprite_frames
	if sf == null or sf.get_frame_count("default") == 0:
		return

	if on_real:
		if not _resonance_pulse_anim.visible:
			var center: Vector2 = _lock_face.get_global_rect().get_center()
			_resonance_pulse_anim.global_position = center
			_resonance_pulse_anim.scale           = Vector2(1.0, 1.0)
			_resonance_pulse_anim.visible         = true
			_resonance_pulse_anim.play("default")
		_resonance_pulse_anim.modulate.a = clampf(_resonance_intensity, 0.0, 1.0)
	else:
		if _resonance_pulse_anim.visible:
			_resonance_pulse_anim.visible = false
			_resonance_pulse_anim.stop()


func _update_audio_loops() -> void:
	# Sweep scrape: gain rides sweep velocity. Plays only while moving.
	var sweep_norm: float = clampf(absf(_sweep_vel_deg) / ROTATE_SPEED_DEG, 0.0, 1.0)
	if _sfx_sweep.stream:
		if sweep_norm > 0.05:
			if not _sfx_sweep.playing:
				_sfx_sweep.play()
			_sfx_sweep.volume_db = lerpf(-30.0, -6.0, sweep_norm)
		elif _sfx_sweep.playing:
			_sfx_sweep.stop()

	# Real-pin resonance tone: pitch + volume scale with intensity.
	# Only plays when intensity > 0 AND we're on a real pin (not false).
	var on_real_pin: bool = _resonance_intensity > 0.0 and not _on_false_pin
	if _sfx_resonance.stream:
		if on_real_pin:
			if not _sfx_resonance.playing:
				_sfx_resonance.play()
			_sfx_resonance.volume_db   = lerpf(-24.0, -4.0, _resonance_intensity)
			_sfx_resonance.pitch_scale = lerpf(0.85, 1.25, _resonance_intensity)
		elif _sfx_resonance.playing:
			_sfx_resonance.stop()

	# False-pin hum: hollow rattle while detecting a false resonance.
	var on_false: bool = _resonance_intensity > 0.0 and _on_false_pin
	if _sfx_false.stream:
		if on_false:
			if not _sfx_false.playing:
				_sfx_false.play()
			_sfx_false.volume_db = lerpf(-22.0, -8.0, _resonance_intensity)
		elif _sfx_false.playing:
			_sfx_false.stop()


func _stop_all_loops() -> void:
	if _sfx_sweep and _sfx_sweep.playing:     _sfx_sweep.stop()
	if _sfx_resonance and _sfx_resonance.playing: _sfx_resonance.stop()
	if _sfx_false and _sfx_false.playing:     _sfx_false.stop()


func _stop_all_anims() -> void:
	for anim in [_snap_anim, _pin_flash_anim, _unlock_anim,
	             _false_stall_anim, _resonance_pulse_anim]:
		if anim and anim.visible:
			anim.visible = false
			anim.stop()


# ─── RESONANCE ─────────────────────────────────────────────────────────────

func _update_resonance() -> void:
	_resonance_intensity = 0.0
	_nearest_pin_idx     = -1
	_on_false_pin        = false

	var half_zone: float = RESONANCE_ZONE_DEG[_lock_data.tier] / 2.0

	for i in _active_pins.size():
		var pin: Dictionary = _active_pins[i]
		if pin.is_set:
			continue
		var dist: float = _angular_dist(_current_angle_deg, pin.pos_deg)
		if dist < half_zone:
			var intensity: float = 1.0 - (dist / half_zone)
			if intensity > _resonance_intensity:
				_resonance_intensity = intensity
				_nearest_pin_idx     = i
				_on_false_pin        = pin.is_false


# ─── PIN SETTING ───────────────────────────────────────────────────────────

func _set_pin() -> void:
	if _nearest_pin_idx < 0:
		return

	_active_pins[_nearest_pin_idx]["is_set"] = true
	_pins_set    += 1
	_set_progress = 0.0
	_is_holding   = false
	_hold_timer   = _get_hold_timer()

	DebugOverlay.log_action(
		"Lockpick — pin %d set at %.0f° (tier %s)" % [
			_pins_set, _active_pins[_nearest_pin_idx].pos_deg,
			TIER_LABELS[_lock_data.tier]
		]
	)

	_refresh_pin_icons()
	_hint_label.text = "Pin set!" if _pins_set < _lock_data.pin_count \
	                   else ""

	if _sfx_pin_set and _sfx_pin_set.stream:
		_sfx_pin_set.play()

	# Pin-set flash animation — small confirmation burst.
	_play_anim_at_lock_center(_pin_flash_anim, 1.4)

	if _pins_set >= _lock_data.pin_count:
		_on_unlocked()


func _on_unlocked() -> void:
	var lock_id: String = _lock_data.lock_id

	# Only award XP / set flag on the first successful pick of this lock.
	if not GameState.get_flag("picked_" + lock_id):
		GameState.set_flag("picked_" + lock_id, "true")
		var xp_table: Array = [20, 40, 70, 120]
		# SkillManager.add_xp("lockpicking", xp_table[_lock_data.tier])
		# ↑ Uncomment when SkillManager is registered as an autoload.

	DebugOverlay.log_action(
		"Lockpick — OPENED '%s' (tier %s, %d snap(s))" % [
			lock_id, TIER_LABELS[_lock_data.tier], _snap_count
		]
	)

	_hint_label.text = "Unlocked."
	_status_label.text = "✓ Lock opened"
	_status_label.modulate = TIER_COLORS[_lock_data.tier]

	_stop_all_loops()
	if _sfx_open and _sfx_open.stream:
		_sfx_open.play()

	# Lock-open reveal animation across the full dial.
	_play_anim_at_lock_center(_unlock_anim, 1.4)
	# Stop the resonance pulse if it was running.
	if _resonance_pulse_anim.visible:
		_resonance_pulse_anim.visible = false
		_resonance_pulse_anim.stop()

	lock_opened.emit(lock_id)

	# Short delay so the player can see the success feedback.
	await get_tree().create_timer(0.8).timeout
	close()

# Track snap count for the debug log (reset on open).
var _snap_count: int = 0


# ─── PICK SNAP ─────────────────────────────────────────────────────────────

func _snap_pick() -> void:
	InventoryManager.remove_item(_pick_type, 1)
	_snap_count += 1

	_stop_all_loops()
	if _sfx_snap and _sfx_snap.stream:
		_sfx_snap.play()

	# Pick-snap animation — particle burst at the lock centre.
	_play_anim_at_lock_center(_snap_anim, 1.4)
	# Hide the looping resonance pulse if it was visible.
	if _resonance_pulse_anim.visible:
		_resonance_pulse_anim.visible = false
		_resonance_pulse_anim.stop()

	DebugOverlay.log_action(
		"Lockpick — SNAP at %.0f° (%s, %s pick)" % [
			_current_angle_deg,
			"false pin" if _on_false_pin else "hold timer",
			_pick_type
		]
	)

	# Regenerate with fresh random pin positions on each snap.
	_pins_set = 0
	_generate_pins()
	_set_progress        = 0.0
	_is_holding          = false
	_resonance_intensity = 0.0
	_on_false_pin        = false

	_snapping    = true
	_snap_timer  = SNAP_ANIM_DURATION
	_hint_label.text = "Pick snapped!"
	_status_label.text = "✗ Pick broken"
	_status_label.modulate = Color("#b8302a")
	_refresh_pin_icons()
	_refresh_ui()


# ─── PIN GENERATION ────────────────────────────────────────────────────────

func _generate_pins() -> void:
	_active_pins.clear()

	var false_count: int = FALSE_COUNT_BY_TIER[_lock_data.tier]

	var used_positions: Array[float] = []

	# Real pins.
	for _i in _lock_data.pin_count:
		var pos: float = _random_angle_clear_of(used_positions, 50.0)
		used_positions.append(pos)
		_active_pins.append({"pos_deg": pos, "is_false": false, "is_set": false})

	# False resonances (only Hard and Very Hard).
	for _i in false_count:
		var pos: float = _random_angle_clear_of(used_positions, 35.0)
		used_positions.append(pos)
		_active_pins.append({"pos_deg": pos, "is_false": true, "is_set": false})


func _random_angle_clear_of(used: Array, min_sep: float) -> float:
	# Try up to 30 random angles; return first that's far enough from all used.
	for _attempt in 30:
		var angle: float = randf() * 360.0
		var clear: bool  = true
		for u in used:
			if _angular_dist(angle, u) < min_sep:
				clear = false
				break
		if clear:
			return angle
	# Fallback: return a random angle even if it overlaps (prevents infinite loop).
	return randf() * 360.0


# ─── BACK-PRESSURE ZONE ────────────────────────────────────────────────────

func _in_back_pressure_zone(angle: float) -> bool:
	# Back-pressure zone = anywhere more than BACK_PRESSURE_MIN_DIST degrees
	# from every set pin. Think of it as the "far side" of the dial.
	for pin in _active_pins:
		if pin.is_set:
			if _angular_dist(angle, pin.pos_deg) < BACK_PRESSURE_MIN_DIST:
				return false   # close enough to a set pin — safe
	return true  # far from all set pins = danger zone


func _update_back_pressure_debug() -> void:
	# Compute the arc extent of the back-pressure zone for the debug overlay.
	# Simple approach: mark the zone as [first_set_pin + min_dist, ...+ 360-min_dist].
	# For the debug overlay we just pass start/end degrees.
	if _pins_set == 0:
		_lock_face._debug_bp_start_deg = 0.0
		_lock_face._debug_bp_end_deg   = 0.0
		return
	# Use the first set pin as reference.
	for pin in _active_pins:
		if pin.is_set:
			_lock_face._debug_bp_start_deg = fmod(pin.pos_deg + BACK_PRESSURE_MIN_DIST, 360.0)
			_lock_face._debug_bp_end_deg   = fmod(pin.pos_deg - BACK_PRESSURE_MIN_DIST + 360.0, 360.0)
			return


# ─── HELPERS ───────────────────────────────────────────────────────────────

static func _angular_dist(a: float, b: float) -> float:
	# Shortest arc between two angles in degrees.
	var d: float = fmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)


func _choose_pick_type() -> String:
	# Prefer Fine picks (better hold timer); fall back to standard.
	if InventoryManager.has_item("lockpick_fine"):
		return "lockpick_fine"
	elif InventoryManager.has_item("lockpick_standard"):
		return "lockpick_standard"
	return ""


func _get_hold_timer() -> float:
	var base: float  = HOLD_TIMER_BY_SKILL[_skill_tier]
	var bonus: float = FINE_PICK_BONUS if _pick_type == "lockpick_fine" else 0.0
	return base + bonus


func _check_has_picks() -> bool:
	return InventoryManager.has_item("lockpick_standard") \
	    or InventoryManager.has_item("lockpick_fine")


# ─── INPUT ─────────────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_open or _snapping:
		return
	# Escape cancels without consuming a pick.
	if event.is_action_pressed("ui_cancel"):
		DebugOverlay.log_action("Lockpick — cancelled by player (no pick consumed).")
		get_viewport().set_input_as_handled()
		close()


# ─── UI CONSTRUCTION ───────────────────────────────────────────────────────

func _build_ui() -> void:
	# ── Full-screen dim overlay ───────────────────────────────────────────
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# ── Central panel ─────────────────────────────────────────────────────
	_panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color            = Colors.PANEL_OAK_2
	panel_style.border_width_left   = 2
	panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color        = Colors.PANEL_OAK_EDGE
	panel_style.corner_radius_top_left     = 8
	panel_style.corner_radius_top_right    = 8
	panel_style.corner_radius_bottom_left  = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.shadow_size  = 12
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.custom_minimum_size = Vector2(460.0, 560.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	# Margin inside the panel.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# ── Tier label ────────────────────────────────────────────────────────
	_tier_label = Label.new()
	_tier_label.text = "Easy"
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_color_override("font_color", Colors.GOLD)
	_tier_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_tier_label)

	# ── Pick count label ──────────────────────────────────────────────────
	_pick_label = Label.new()
	_pick_label.text = "Picks: —"
	_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_label.add_theme_color_override("font_color", Colors.INK_DIM)
	_pick_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_pick_label)

	# ── Separator ─────────────────────────────────────────────────────────
	var sep1 := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Colors.PANEL_OAK_EDGE
	sep_style.content_margin_top    = 1.0
	sep_style.content_margin_bottom = 1.0
	sep1.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep1)

	# ── Lock face dial (custom drawn) ─────────────────────────────────────
	_lock_face = LockFaceControl.new()
	_lock_face.custom_minimum_size  = Vector2(360.0, 360.0)
	_lock_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_lock_face)

	# ── Set bar row ───────────────────────────────────────────────────────
	var bar_row := HBoxContainer.new()
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bar_row)

	var bar_label := Label.new()
	bar_label.text = "SET"
	bar_label.add_theme_color_override("font_color", Colors.INK_DIM)
	bar_label.add_theme_font_size_override("font_size", 11)
	bar_row.add_child(bar_label)

	_set_bar = ProgressBar.new()
	_set_bar.min_value = 0.0
	_set_bar.max_value = 1.0
	_set_bar.value     = 0.0
	_set_bar.show_percentage = false
	_set_bar.custom_minimum_size = Vector2(280.0, 14.0)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Colors.GOLD
	_set_bar.add_theme_stylebox_override("fill", fill_sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Colors.PANEL_IRON
	_set_bar.add_theme_stylebox_override("background", bg_sb)
	bar_row.add_child(_set_bar)

	# ── Pin icon row ──────────────────────────────────────────────────────
	_pin_row = HBoxContainer.new()
	_pin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pin_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_pin_row)

	# ── Hint label ────────────────────────────────────────────────────────
	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Colors.INK_DIM)
	_hint_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_hint_label)

	# ── Status label (snap / unlock) ──────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_status_label)

	# ── Controls footer ───────────────────────────────────────────────────
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep2)

	var footer := Label.new()
	footer.text = "A / D — Rotate pick     Esc — Cancel"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Colors.INK_MUTE)
	footer.add_theme_font_size_override("font_size", 12)
	vbox.add_child(footer)

	# ── Animated sprite nodes (optional art — hidden until frames assigned) ─
	_snap_anim             = _make_anim_sprite("snap_anim")
	_pin_flash_anim        = _make_anim_sprite("pin_flash_anim")
	_unlock_anim           = _make_anim_sprite("unlock_anim")
	_false_stall_anim      = _make_anim_sprite("false_stall_anim")
	_resonance_pulse_anim  = _make_anim_sprite("resonance_pulse_anim")

	# Hide one-shot anims when finished; loops are managed by _process.
	_snap_anim.animation_finished.connect(func(): _snap_anim.visible = false)
	_pin_flash_anim.animation_finished.connect(func(): _pin_flash_anim.visible = false)
	_unlock_anim.animation_finished.connect(func(): _unlock_anim.visible = false)

	_build_audio()
	_load_static_art()
	_load_animations()


# ─── ART LOADING ───────────────────────────────────────────────────────────

const ART_DIR: String  = "res://assets/lockpick/"
const ANIM_DIR: String = "res://assets/lockpick/anim/"


func _load_static_art() -> void:
	# Auto-load the three textures LockFaceControl knows how to render.
	# lock_face.jpg is fine fully opaque (it's the dial background).
	# lockpick.png and resonance_glow.png are alpha-extracted from their
	# original JPGs (the AI image-gen baked a faux-checkerboard "transparency"
	# into the JPG output; tools/strip_lockpick_checker.js recovers true alpha).
	_lock_face.lock_face_texture = _load_tex_or_null(ART_DIR + "lock_face.jpg")
	_lock_face.pick_texture      = _load_tex_or_null(ART_DIR + "lockpick.png")
	_lock_face.glow_texture      = _load_tex_or_null(ART_DIR + "resonance_glow.png")


func _load_tex_or_null(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ─── ANIMATION LOADING ─────────────────────────────────────────────────────

func _load_animations() -> void:
	# Each animation lives in /assets/lockpick/anim/<folder>/frame_NNN.png.
	# We build a SpriteFrames resource from whatever's there. If the folder
	# is missing or empty, the AnimatedSprite2D stays empty and is never shown.
	#
	# Playback fps is tuned per clip so the in-game duration matches design:
	#   resonance_pulse — 1.5 s loop  (12 fps × 18 frames worth of motion)
	#   pick_snap       — ~1.5 s burst (24 fps)
	#   pin_set_flash   — ~0.8 s burst (24 fps)
	#   lock_open       — 4 s reveal  (12 fps)
	_resonance_pulse_anim.sprite_frames = _build_sprite_frames(
		ANIM_DIR + "resonance_pulse", 12.0, true)
	_snap_anim.sprite_frames = _build_sprite_frames(
		ANIM_DIR + "pick_snap", 24.0, false)
	_pin_flash_anim.sprite_frames = _build_sprite_frames(
		ANIM_DIR + "pin_set_flash", 24.0, false)
	_unlock_anim.sprite_frames = _build_sprite_frames(
		ANIM_DIR + "lock_open", 12.0, false)
	# false_pin_stall (ANIM 5) is intentionally not loaded — designer flagged
	# this as missing. The set bar turning red at 50% is the in-code substitute.


func _build_sprite_frames(folder: String, fps: float, loop_anim: bool) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("default")
	sf.set_animation_speed("default", fps)
	sf.set_animation_loop("default", loop_anim)
	# Remove the auto-added empty default frame so our additions start at 0.
	while sf.get_frame_count("default") > 0:
		sf.remove_frame("default", 0)

	if not DirAccess.dir_exists_absolute(folder):
		return sf

	var dir := DirAccess.open(folder)
	if dir == null:
		return sf

	var names: Array[String] = []
	dir.list_dir_begin()
	while true:
		var fname := dir.get_next()
		if fname == "":
			break
		if fname.ends_with(".png") and fname.begins_with("frame_"):
			names.append(fname)
	dir.list_dir_end()
	names.sort()

	for n in names:
		var path: String = folder.path_join(n)
		var tex: Texture2D = _load_tex_or_null(path)
		if tex:
			sf.add_frame("default", tex)
	return sf


func _play_anim_at_lock_center(anim: AnimatedSprite2D, sprite_scale: float) -> void:
	# Centers the AnimatedSprite2D on the lock face dial and plays "default".
	# SAFE if the SpriteFrames is empty (just no-ops).
	if anim.sprite_frames == null or anim.sprite_frames.get_frame_count("default") == 0:
		return
	var center: Vector2 = _lock_face.get_global_rect().get_center()
	anim.global_position = center
	anim.scale           = Vector2(sprite_scale, sprite_scale)
	anim.modulate.a      = 1.0
	anim.visible         = true
	anim.frame           = 0
	anim.play("default")


func _build_audio() -> void:
	# Loads the six lockpicking SFX from res://assets/audio/lockpicking/.
	# If a file is missing, that one player just stays silent — no crash.
	const BASE_PATH: String = "res://assets/audio/lockpicking/"

	_sfx_sweep     = _make_audio_player("sfx_sweep",     BASE_PATH + "lock_sweep_loop.ogg",     "SFX", -8.0)
	_sfx_resonance = _make_audio_player("sfx_resonance", BASE_PATH + "lock_resonance_tone.ogg", "SFX", -6.0)
	_sfx_false     = _make_audio_player("sfx_false",     BASE_PATH + "lock_false_hum.ogg",      "SFX", -8.0)
	_sfx_pin_set   = _make_audio_player("sfx_pin_set",   BASE_PATH + "lock_pin_set.ogg",        "SFX",  0.0)
	_sfx_snap      = _make_audio_player("sfx_snap",      BASE_PATH + "lock_pick_snap.ogg",      "SFX",  0.0)
	_sfx_open      = _make_audio_player("sfx_open",      BASE_PATH + "lock_open.ogg",           "SFX",  0.0)

	# Mark streams as looping where the .ogg import didn't already.
	_force_loop(_sfx_sweep)
	_force_loop(_sfx_resonance)
	_force_loop(_sfx_false)


func _make_audio_player(node_name: String, stream_path: String,
                        bus: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus  = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.volume_db = volume_db
	if ResourceLoader.exists(stream_path):
		p.stream = load(stream_path) as AudioStream
	add_child(p)
	return p


func _force_loop(p: AudioStreamPlayer) -> void:
	# OggVorbis streams expose a `loop` property; set it true so the
	# sweep / resonance / false hum loop without per-finished-callback chaining.
	if p == null or p.stream == null:
		return
	if "loop" in p.stream:
		p.stream.loop = true


func _make_anim_sprite(node_name: String) -> AnimatedSprite2D:
	var spr := AnimatedSprite2D.new()
	spr.name    = node_name
	spr.visible = false
	add_child(spr)
	return spr


# ─── UI REFRESH ────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	if not _lock_data:
		return

	_tier_label.text     = TIER_LABELS[_lock_data.tier]
	_tier_label.add_theme_color_override("font_color", TIER_COLORS[_lock_data.tier])

	var std_count: int  = InventoryManager.get_quantity("lockpick_standard")
	var fine_count: int = InventoryManager.get_quantity("lockpick_fine")
	if fine_count > 0:
		_pick_label.text = "Picks: %d  |  Fine: %d" % [std_count, fine_count]
	else:
		_pick_label.text = "Picks: %d" % std_count

	_set_bar.value   = _set_progress
	_status_label.text = ""

	# Rebuild the snap count tracker.
	_snap_count = 0


func _refresh_pin_icons() -> void:
	# Rebuild the pin icon row to match current pin states.
	for child in _pin_row.get_children():
		child.queue_free()
	_pin_icons.clear()

	for i in _lock_data.pin_count:
		var icon := Label.new()
		icon.add_theme_font_size_override("font_size", 22)
		icon.add_theme_constant_override("outline_size", 1)

		# Check if this pin index is set (only count non-false pins in order).
		var set_pins: int = 0
		for pin in _active_pins:
			if pin.is_set and not pin.is_false:
				set_pins += 1

		if i < set_pins:
			icon.text = "⬟"    # filled — pin set
			icon.add_theme_color_override("font_color", Colors.GOLD)
		else:
			icon.text = "⬠"    # hollow — pin not set
			icon.add_theme_color_override("font_color", Colors.INK_MUTE)

		_pin_row.add_child(icon)
		_pin_icons.append(icon)
