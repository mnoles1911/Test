class_name LockFaceControl
extends Control
# LockFaceControl — the circular lock-face drawn on screen during lockpicking.
#
# What this does in plain English:
#   This is the visual "dial" the player sees when picking a lock. It draws:
#     • The circular iron lock face (background disc)
#     • A reference notch at 12 o'clock so the player knows where "up" is
#     • The central keyhole shape
#     • The pick indicator — a line from the centre rotating as the player
#       presses A/D. Its colour shifts white → amber → red depending on how
#       close it is to a pin and whether that pin is real or false.
#     • A glow dot at the pick tip that pulses with resonance intensity.
#     • A set-progress arc around the outer rim that fills as a pin is set.
#     • Optional debug overlays (pin positions, resonance zones, etc.)
#
# LockpickingUI.gd owns this node. It updates the exported variables every
# frame and calls queue_redraw() to trigger a repaint.
#
# ART SLOTS — assign textures in the Inspector to replace programmatic drawing:
#   lock_face_texture   — the iron disc background (512×512 PNG, transparent bg)
#   keyhole_texture     — keyhole overlay (centered on disc)
#   pick_texture        — the pick sprite (pivot at left end, tip at right)
#   glow_texture        — radial glow placed at the pick tip (128×128 PNG)
# Any slot left blank falls back to the programmatic version automatically.


# ─── ART SLOTS (assign in Inspector or from LockpickingUI) ─────────────────

@export var lock_face_texture: Texture2D = null
# Optional: 512×512 circular iron disc on transparent background.
# When assigned, replaces the programmatic grey circle.

@export var keyhole_texture: Texture2D = null
# Optional: keyhole shape overlay, centered on the disc.

@export var pick_texture: Texture2D = null
# Optional: pick sprite. Should be horizontal (pointing right), pivot at left.
# Code rotates it from the center of the disc toward the rim.

@export var glow_texture: Texture2D = null
# Optional: radial glow texture (128×128, transparent bg, white-amber centre).
# Placed at the pick tip and alpha-scaled by resonance_intensity.


# ─── STATE (written by LockpickingUI every frame) ──────────────────────────

var angle_deg: float = 0.0
# Current pick angle. 0 = 12 o'clock. Increases clockwise.

var resonance_intensity: float = 0.0
# 0.0 = pick is nowhere near a pin. 1.0 = dead centre on a pin.
# Drives glow size and pick colour.

var on_false_pin: bool = false
# True when the nearest resonance is a false (decoy) pin.
# Shifts pick colour toward red and the glow to a cooler tone.

var set_progress: float = 0.0
# 0.0–1.0. The arc drawn around the outer rim as a pin is being set.
# On a real pin: fills to 1.0 → pin sets.
# On a false pin: fills to ~0.5 then stalls (LockpickingUI caps it).

var debug_show_pins: bool = false
# When true, draws small coloured dots at every pin position.
# White dot = real pin. Orange dot = false resonance.
var _debug_pins: Array = []
# Set by LockpickingUI when debug_show_pins is on.
# Each entry: {pos_deg, is_false, is_set}

var debug_show_zones: bool = false
# When true, draws the resonance zone arcs as faint overlays.
var _debug_zone_deg: float = 40.0
# Half-width of the resonance zone for the current lock tier.

var debug_show_back_pressure: bool = false
# When true, draws a red arc showing the back-pressure danger zone.
var _debug_bp_start_deg: float = 0.0
var _debug_bp_end_deg: float = 0.0

var debug_show_hold_timer: bool = false
# When true, draws a thin white arc around the rim showing time remaining.
var _debug_hold_timer_frac: float = 1.0
# 1.0 = full time remaining. 0.0 = timer about to expire.


# ─── COLOURS ───────────────────────────────────────────────────────────────

const _COL_FACE_BG     := Color("#1c1712")   # dark iron disc
const _COL_RIM         := Color("#4a4038")   # outer ring bevel
const _COL_INNER_RING  := Color("#2a241f")   # inner decorative ring
const _COL_NOTCH       := Color("#6e6358")   # 12-o'clock reference mark
const _COL_KEYHOLE     := Color("#080604")   # keyhole cutout
const _COL_PICK_COOL   := Color("#f3e6c4")   # pick when no resonance (parchment white)
const _COL_PICK_WARM   := Color("#f0a02a")   # pick when near real pin (amber gold)
const _COL_PICK_FALSE  := Color("#b8302a")   # pick when near false pin (dim red)
const _COL_SET_ARC     := Color("#f0c14b")   # set-progress arc (gold)
const _COL_SET_STALL   := Color("#b8302a")   # set-progress arc when stalled (red)
const _COL_DEBUG_REAL  := Color("#ffffff")   # debug: real pin dot
const _COL_DEBUG_FALSE := Color("#f0a02a")   # debug: false pin dot (orange)
const _COL_DEBUG_SET   := Color("#50c878")   # debug: already-set pin dot (green)
const _COL_DEBUG_ZONE  := Color(0.9, 0.8, 0.3, 0.15)   # resonance zone fill
const _COL_DEBUG_BP    := Color(0.8, 0.15, 0.1, 0.18)  # back-pressure zone fill
const _COL_DEBUG_TIMER := Color(1.0, 1.0, 1.0, 0.55)   # hold-timer arc


func _draw() -> void:
	# ── Geometry ──────────────────────────────────────────────────────────
	var center := size / 2.0
	var face_r := min(size.x, size.y) * 0.44   # dial radius, slightly inset

	# ── Lock face background ──────────────────────────────────────────────
	if lock_face_texture:
		# Art path: draw texture centred on the control.
		var tex_size := Vector2(face_r * 2.0, face_r * 2.0)
		var tex_rect := Rect2(center - tex_size / 2.0, tex_size)
		draw_texture_rect(lock_face_texture, tex_rect, false)
	else:
		# Programmatic path: concentric rings suggest iron casting.
		draw_circle(center, face_r, _COL_FACE_BG)
		draw_arc(center, face_r, 0.0, TAU, 80, _COL_RIM, 4.0)
		draw_arc(center, face_r * 0.78, 0.0, TAU, 64, _COL_INNER_RING, 2.0)
		# Tick marks every 30° (like a clock face) — subtle navigation aid.
		for i in 12:
			var tick_rad := deg_to_rad(i * 30.0 - 90.0)
			var tick_outer := center + Vector2(cos(tick_rad), sin(tick_rad)) * (face_r * 0.96)
			var tick_inner := center + Vector2(cos(tick_rad), sin(tick_rad)) * (face_r * 0.88)
			var tick_col := _COL_RIM if i % 3 == 0 else _COL_INNER_RING
			draw_line(tick_inner, tick_outer, tick_col, 1.5)

	# ── 12-o'clock reference notch ────────────────────────────────────────
	# A short bright mark outside the rim so the player always knows "up."
	var notch_outer := center + Vector2(0.0, -(face_r + 8.0))
	var notch_inner := center + Vector2(0.0, -(face_r - 10.0))
	draw_line(notch_outer, notch_inner, _COL_NOTCH, 3.5)

	# ── Keyhole ───────────────────────────────────────────────────────────
	if keyhole_texture:
		var kh_size := Vector2(face_r * 0.22, face_r * 0.32)
		var kh_rect := Rect2(center - kh_size / 2.0, kh_size)
		draw_texture_rect(keyhole_texture, kh_rect, false)
	else:
		# Programmatic keyhole: circle + downward slot.
		draw_circle(center, face_r * 0.072, _COL_KEYHOLE)
		var slot_w := face_r * 0.048
		var slot_h := face_r * 0.12
		draw_rect(Rect2(center.x - slot_w / 2.0, center.y + face_r * 0.058,
		                slot_w, slot_h), _COL_KEYHOLE)

	# ── Debug overlays (drawn under the pick so they don't obscure it) ────
	if debug_show_zones:
		for pin in _debug_pins:
			if pin.is_set:
				continue
			var zone_half := _debug_zone_deg / 2.0
			var zone_start := deg_to_rad(pin.pos_deg - zone_half - 90.0)
			var zone_end   := deg_to_rad(pin.pos_deg + zone_half - 90.0)
			# Filled arc at the resonance zone radius.
			draw_arc(center, face_r * 0.72, zone_start, zone_end, 32,
			         _COL_DEBUG_ZONE, face_r * 0.26)

	if debug_show_back_pressure and _debug_bp_start_deg != _debug_bp_end_deg:
		var bp_start := deg_to_rad(_debug_bp_start_deg - 90.0)
		var bp_end   := deg_to_rad(_debug_bp_end_deg - 90.0)
		draw_arc(center, face_r * 0.72, bp_start, bp_end, 64,
		         _COL_DEBUG_BP, face_r * 0.26)

	# ── Pick indicator ────────────────────────────────────────────────────
	# In Godot 2D: angle 0 = right (3 o'clock). We subtract 90° so that
	# angle_deg=0 points to 12 o'clock, and clockwise = increasing degrees.
	var pick_rad := deg_to_rad(angle_deg - 90.0)
	var pick_dir := Vector2(cos(pick_rad), sin(pick_rad))

	# Colour: interpolate between cool white, warm amber, and false-pin red.
	var pick_col: Color
	if on_false_pin:
		pick_col = _COL_PICK_COOL.lerp(_COL_PICK_FALSE, resonance_intensity)
	else:
		pick_col = _COL_PICK_COOL.lerp(_COL_PICK_WARM, resonance_intensity)

	if pick_texture:
		# Art path: draw the pick sprite rotated around the dial centre.
		# The texture is horizontal (pointing right); we rotate it by pick_rad.
		# Pivot at the left end of the sprite (center of the disc).
		var pick_len := face_r * 0.86
		var tex_w    := pick_texture.get_width()
		var tex_h    := pick_texture.get_height()
		var scale_x  := pick_len / tex_w
		var scale_y  := scale_x  # keep aspect ratio
		var xform    := Transform2D(pick_rad, center)
		xform = xform.scaled(Vector2(scale_x, scale_y))
		xform = xform.translated(Vector2(0.0, -tex_h * 0.5))
		draw_set_transform_matrix(xform)
		draw_texture(pick_texture, Vector2.ZERO, pick_col)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		# Programmatic path: a simple line from near-centre to near-rim.
		var pick_root := center + pick_dir * (face_r * 0.10)
		var pick_tip  := center + pick_dir * (face_r * 0.88)
		draw_line(pick_root, pick_tip, pick_col, 3.0)

	# ── Resonance glow at pick tip ────────────────────────────────────────
	var tip_pos := center + pick_dir * (face_r * 0.88)
	if resonance_intensity > 0.02:
		if glow_texture:
			var glow_size := face_r * 0.36 * resonance_intensity + face_r * 0.08
			var glow_rect := Rect2(tip_pos - Vector2(glow_size, glow_size),
			                       Vector2(glow_size * 2.0, glow_size * 2.0))
			var glow_col  := pick_col
			glow_col.a    = resonance_intensity * 0.85
			draw_texture_rect(glow_texture, glow_rect, false, glow_col)
		else:
			# Soft outer halo.
			var halo_col := pick_col
			halo_col.a   = resonance_intensity * 0.5
			draw_circle(tip_pos, face_r * 0.12 * resonance_intensity + face_r * 0.03, halo_col)
			# Bright inner dot.
			var dot_col := pick_col
			dot_col.a   = minf(resonance_intensity * 1.4, 1.0)
			draw_circle(tip_pos, face_r * 0.04, dot_col)

	# ── Set-progress arc ──────────────────────────────────────────────────
	# Draws clockwise from 12 o'clock around the outer rim.
	if set_progress > 0.002:
		var arc_col  := _COL_SET_STALL if (on_false_pin and set_progress >= 0.49) else _COL_SET_ARC
		var arc_start := -PI / 2.0          # 12 o'clock in Godot radians
		var arc_end   := arc_start + TAU * set_progress
		draw_arc(center, face_r + 8.0, arc_start, arc_end, 80, arc_col, 6.0)

	# ── Debug hold-timer arc (thin white ring draining clockwise) ─────────
	if debug_show_hold_timer and _debug_hold_timer_frac < 0.999:
		var timer_start := -PI / 2.0
		var timer_end   := timer_start + TAU * _debug_hold_timer_frac
		draw_arc(center, face_r + 18.0, timer_start, timer_end, 80,
		         _COL_DEBUG_TIMER, 2.5)

	# ── Debug pin-position dots ───────────────────────────────────────────
	if debug_show_pins:
		for pin in _debug_pins:
			var p_rad  := deg_to_rad(pin.pos_deg - 90.0)
			var p_pos  := center + Vector2(cos(p_rad), sin(p_rad)) * (face_r * 0.72)
			var p_col: Color
			if pin.is_set:
				p_col = _COL_DEBUG_SET
			elif pin.is_false:
				p_col = _COL_DEBUG_FALSE
			else:
				p_col = _COL_DEBUG_REAL
			draw_circle(p_pos, 6.0, p_col)
			# Tiny outer ring so dots are visible on both light and dark faces.
			draw_arc(p_pos, 8.0, 0.0, TAU, 16, Color(0, 0, 0, 0.5), 2.0)
