extends Control
class_name LoadingHourglass
# LoadingHourglass — port of the .hg block in
# assets/ui/html/Voxelmark Loading Screen.html.
#
# Visual elements (drawn in _draw, layered back→front):
#   1. Back support pillars (left + right, dimmed for fake 3D depth).
#   2. Glass diamond — two opposed triangles meeting at the waist,
#      with a thin gold stroke and a faint inner outline.
#   3. Top sand triangle — shrinks from a full triangle (apex at waist)
#      to nothing as `progress` advances 0 → 1.
#   4. Bottom sand mound — grows from a point at the waist into a wide
#      triangle as `progress` advances. Slight settling bevel near the
#      apex so the mound reads as soft sand, not a triangle wedge.
#   5. Falling grain particles — 1.5 px squares that spawn at the waist
#      with gravity + small horizontal jitter, and despawn on contact
#      with either the mound (using moundContains check) or the floor.
#   6. Front support pillars (left + right, full brightness).
#   7. Brass caps (top + bottom) — gradient horizontal strips overhanging
#      the diamond on both sides.
#
# All math is computed in SVG-mock space (40 × 60) and scaled to the
# Control's actual size at draw time so the look is identical at any
# size the host picks via `custom_minimum_size`. The mock spec is 40×60
# inside an 80×90 stage; we size to ~96×144 (a clean 2.4× upscale)
# inside an outer Control with a bit of breathing room.
#
# Public API:
#   set_progress(p: float) — 0..1, drives sand levels and grain spawn rate
#
# Animation: _process runs the particle simulation (gravity + collision)
# every frame regardless of progress, so the hourglass stays "alive"
# even while progress is paused (e.g. while the world streams chunks).
# Progress changes are pushed in by TransitionManager.

# Mock SVG-space dimensions — every helper computes in this space, then
# we scale to actual Control size when drawing.
const SVG_W: float = 40.0
const SVG_H: float = 60.0
const WAIST_X: float = 20.0
const WAIST_Y: float = 30.0

# Particle simulation tuning. Numbers from the mock JS, kept verbatim
# for visual parity. Velocities are in SVG-units / frame (the original
# loop runs at ~60 Hz).
const MAX_GRAINS: int = 24    # Mock's 38, scaled down — fewer per-frame draw calls and array writes during chunk-stream load.
const SPAWN_INTERVAL_S: float = 0.045   # mock: `interval = 32 ms`; bumped to 45 ms to match the lower cap

# Fixed-timestep sub-tick for the particle physics. At low frame rates
# (e.g. 10 FPS during heavy chunk-stream load) the original frame_dt =
# delta * 60 multiplier produced 6× normal physics jumps, which made
# grains skip past the mound and look broken. Running multiple small
# sub-ticks per _process call keeps motion visually smooth regardless
# of frame rate. PHYS_TICK_S is the real-time duration of one sub-tick;
# the mock's 60 Hz loop converts to PHYS_TICK_S = 1/60 ≈ 16.67 ms.
const PHYS_TICK_S: float = 1.0 / 60.0
const MAX_SUBTICKS_PER_FRAME: int = 4    # safety cap so a long stall doesn't kick off dozens of catch-up ticks
const GRAVITY: float = 0.012             # mock: `g.vy += 0.012` per frame
const SPAWN_VY_BASE: float = 0.18
const SPAWN_VY_RAND: float = 0.10
const SPAWN_VX_RAND: float = 0.10
const SPAWN_X_JITTER: float = 0.6

# Palette pulled straight from :root in the mock CSS.
const COL_BRASS_1 := Color("#d8a050")
const COL_BRASS_2 := Color("#a87320")
const COL_BRASS_3 := Color("#6b4520")
const COL_BRASS_4 := Color("#3a2410")
const COL_SAND_BRIGHT := Color("#F5D06E")
const COL_SAND_MID := Color("#D9A84A")
const COL_SAND_DEEP := Color("#A87320")
const COL_GLASS_STROKE := Color("#d8a050")
const COL_GLASS_INNER_STROKE := Color(1.0, 0.92, 0.706, 0.18)   # rgba(255,235,180,0.18)
const COL_GLASS_FILL := Color(0.961, 0.816, 0.431, 0.05)         # rgba(245,208,110,0.05)
const COL_TOP_SURFACE := Color(1.0, 0.914, 0.659, 0.7)           # #FFE9A8 @0.7

const COL_BRASS_BACK_TINT := Color(0.55, 0.55, 0.55, 1.0)        # filter brightness(0.55)


# Public progress, range 0..1. Set via set_progress().
var progress: float = 0.0

# Particle state. Each grain: flat dict { pos_x, pos_y, vel_x, vel_y, size, col }.
var _grains: Array = []
var _spawn_accum: float = 0.0
# Accumulator for the fixed-timestep sub-tick loop in _process.
var _phys_accum: float = 0.0


# --- Public API -----------------------------------------------------

func set_progress(p: float) -> void:
	progress = clamp(p, 0.0, 1.0)
	# Trigger redraw — the static sand levels and the grain field share
	# one _draw call so we just request a redraw on either change.
	queue_redraw()


# --- Lifecycle ------------------------------------------------------

func _ready() -> void:
	# We draw everything ourselves; no children needed.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# Fixed-timestep particle sim. Accumulates real time and runs as
	# many PHYS_TICK_S-sized sub-ticks as fit, capped to avoid catch-up
	# explosions on a long stall. This keeps grain motion visually
	# smooth regardless of frame rate — at 10 FPS we run ~4 small ticks
	# per frame instead of one giant 6×-magnitude jump that flings
	# grains past the mound.
	_phys_accum += delta
	var ticks: int = 0
	while _phys_accum >= PHYS_TICK_S and ticks < MAX_SUBTICKS_PER_FRAME:
		_phys_accum -= PHYS_TICK_S
		_physics_tick()
		ticks += 1
	# If the accumulator's still huge (stall longer than 4 ticks), drop
	# the leftover so we don't try to catch up forever next frame.
	if _phys_accum > PHYS_TICK_S * MAX_SUBTICKS_PER_FRAME:
		_phys_accum = 0.0

	queue_redraw()


# One fixed sub-tick of particle physics — gravity + position update +
# floor/mound collision. frame_dt is implicitly 1.0 (the mock's per-
# frame magnitudes assume 60 Hz, which matches PHYS_TICK_S).
func _physics_tick() -> void:
	# Spawn cadence — bursty during mid-progress (matches the mock's
	# `progress > 0.2 && progress < 0.8 && Math.random() < 0.5` double-spawn).
	if progress > 0.005 and progress < 0.995 and _grains.size() < MAX_GRAINS:
		_spawn_accum += PHYS_TICK_S
		while _spawn_accum >= SPAWN_INTERVAL_S:
			_spawn_accum -= SPAWN_INTERVAL_S
			_spawn_grain()
			if progress > 0.2 and progress < 0.8 and randf() < 0.5:
				_spawn_grain()

	# Tick existing grains. Iterating backwards so removals don't skew
	# the indices. Dictionaries in GDScript are reference-typed, so
	# mutating `g["key"] = value` updates the entry in place.
	for i in range(_grains.size() - 1, -1, -1):
		var g: Dictionary = _grains[i]
		var vy: float = g["vel_y"] + GRAVITY
		var px: float = g["pos_x"] + g["vel_x"]
		var py: float = g["pos_y"] + vy
		if py >= SVG_H or _mound_contains(px, py):
			_grains.remove_at(i)
			continue
		g["pos_x"] = px
		g["pos_y"] = py
		g["vel_y"] = vy


# --- Particle helpers ----------------------------------------------

func _spawn_grain() -> void:
	# Spawn at the waist with small horizontal jitter (matches mock JS).
	# Flat-key dictionary (no nested Vector2) — slightly faster to
	# index in the hot loop and saves a Vector2 allocation per spawn.
	var g: Dictionary = {
		"pos_x": WAIST_X + (randf() - 0.5) * SPAWN_X_JITTER,
		"pos_y": WAIST_Y,
		"vel_x": (randf() - 0.5) * SPAWN_VX_RAND,
		"vel_y": SPAWN_VY_BASE + randf() * SPAWN_VY_RAND,
		"size": 0.9 if randf() < 0.4 else 0.7,
		"col": COL_SAND_BRIGHT if randf() < 0.5 else Color("#E8B850"),
	}
	_grains.append(g)


# Triangle test: does (x, y) sit inside the bottom mound?
# Mound apex is at (WAIST_X, apexY), base spans the floor (y = SVG_H).
# halfW at any y inside the mound is t * 20 where t = (y - apexY) / (SVG_H - apexY).
func _mound_contains(x: float, y: float) -> bool:
	var apex_y: float = SVG_H - progress * (SVG_H - WAIST_Y)
	if y < apex_y:
		return false
	if y > SVG_H:
		return true
	var t: float = (y - apex_y) / (SVG_H - apex_y) if (SVG_H - apex_y) > 0.0001 else 1.0
	var half_w: float = t * (SVG_W * 0.5)
	return absf(x - WAIST_X) <= half_w


# --- Drawing --------------------------------------------------------

func _draw() -> void:
	var s: Vector2 = size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	# Scale factor from mock SVG-space (40×60) to control space.
	var sx: float = s.x / SVG_W
	var sy: float = s.y / SVG_H

	# 1. (Back pillars dropped for performance — the fake 3D depth they
	# added was barely visible at 96×144 and the four extra rect/outline
	# draws per frame compound during the chunk-stream load.)

	# 2. Glass diamond fill + outline.
	# Mock SVG: polygon points "0,0 40,0 21,30 40,60 0,60 19,30"
	# That's an asymmetric diamond — the right waist is at x=21, the
	# left waist is at x=19. Preserved for visual character.
	# Anti-aliasing on draw_polyline is expensive (the engine triangulates
	# each segment); we draw without AA at 1 px width, which still reads
	# clean at 96×144 since the line sits on whole-pixel boundaries.
	var diamond := PackedVector2Array([
		_p(0.0, 0.0, sx, sy),
		_p(SVG_W, 0.0, sx, sy),
		_p(21.0, WAIST_Y, sx, sy),
		_p(SVG_W, SVG_H, sx, sy),
		_p(0.0, SVG_H, sx, sy),
		_p(19.0, WAIST_Y, sx, sy),
	])
	draw_colored_polygon(diamond, COL_GLASS_FILL)
	draw_polyline(_close(diamond), COL_GLASS_STROKE, 1.0, false)

	# (Inner glass stroke dropped — purely decorative inset, hard to
	# perceive at small scale; saves a second polyline + triangulation.)

	# 3. Top sand — a triangle that drains as progress advances.
	# At p=0 the surface sits at y=0.5 spanning 0.5..39.5; at p=1 it
	# collapses to the waist point. Skip when nearly empty to avoid a
	# degenerate triangle.
	if progress < 0.97:
		var y_surf: float = 0.5 + progress * 28.5
		var half_w: float = (1.0 - progress) * 19.5
		var x_l: float = WAIST_X - half_w
		var x_r: float = WAIST_X + half_w
		var top_sand := PackedVector2Array([
			_p(x_l, y_surf, sx, sy),
			_p(x_r, y_surf, sx, sy),
			_p(WAIST_X, 29.5, sx, sy),
		])
		draw_colored_polygon(top_sand, COL_SAND_MID)
		# (Surface highlight line dropped — barely visible at 96 px,
		# saved a per-frame antialiased line draw.)

	# 4. Bottom mound — grows from the waist downward as p advances.
	# At very low progress the polygon collapses; the mock's bevel
	# trick (`apexY + 0.5`) ALSO overshoots the floor when the mound
	# is nearly invisible, producing a self-intersecting polygon that
	# fails Godot's triangulator. So below a threshold we draw a clean
	# triangle, and above it we add the 5-vertex bevel — but clamp the
	# bevel y so it never exceeds the floor.
	if progress > 0.005:
		var apex_y: float = SVG_H - progress * (SVG_H - WAIST_Y)
		var half_w_m: float = progress * (SVG_W * 0.5)
		var mound: PackedVector2Array
		if half_w_m < 2.0:
			# Tiny mound — clean triangle, no bevel.
			mound = PackedVector2Array([
				_p(WAIST_X - half_w_m, SVG_H, sx, sy),
				_p(WAIST_X + half_w_m, SVG_H, sx, sy),
				_p(WAIST_X, apex_y, sx, sy),
			])
		else:
			# Full mound — 5-vertex with apex bevel. Clamp bevel y so
			# it sits between the apex and the floor (avoids the self-
			# intersecting polygon at low progress).
			var bevel: float = half_w_m * 0.06
			var bevel_y: float = min(apex_y + 0.5, SVG_H - 0.1)
			mound = PackedVector2Array([
				_p(WAIST_X - half_w_m, SVG_H, sx, sy),
				_p(WAIST_X + half_w_m, SVG_H, sx, sy),
				_p(WAIST_X + bevel, bevel_y, sx, sy),
				_p(WAIST_X, apex_y, sx, sy),
				_p(WAIST_X - bevel, bevel_y, sx, sy),
			])
		draw_colored_polygon(mound, COL_SAND_DEEP)

	# 5. Falling grains.
	for g in _grains:
		var gx: float = g["pos_x"]
		var gy: float = g["pos_y"]
		var gs: float = g["size"]
		var col: Color = g["col"]
		var rect := Rect2(
			Vector2((gx - gs * 0.5) * sx, (gy - gs * 0.5) * sy),
			Vector2(gs * sx, gs * sy)
		)
		draw_rect(rect, col, true)

	# 6. Front pillars (full brightness, on top of the glass).
	_draw_pillar(-4.0, sx, sy, false)
	_draw_pillar(SVG_W + 2.0, sx, sy, false)

	# 7. Brass caps — top + bottom 6 px high strips that overhang the
	# diamond by 6 px on each side. Drawn last so they sit above the
	# pillars.
	_draw_cap(-3.0, sx, sy)            # top cap
	_draw_cap(SVG_H - 3.0, sx, sy)     # bottom cap


# Helper — point in mock space → control space.
func _p(mx: float, my: float, sx: float, sy: float) -> Vector2:
	return Vector2(mx * sx, my * sy)


# Helper — append the first vertex to the end of an array so a polyline
# closes back on itself (Godot draw_polyline doesn't auto-close).
func _close(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out


# Pillar at SVG-x, full SVG-height, 2 mock-px wide. Dimmed = back layer.
func _draw_pillar(svg_x: float, sx: float, sy: float, back: bool) -> void:
	var col_top := COL_BRASS_1
	var col_mid := COL_BRASS_3
	var col_bot := COL_BRASS_4
	if back:
		col_top = col_top * COL_BRASS_BACK_TINT
		col_mid = col_mid * COL_BRASS_BACK_TINT
		col_bot = col_bot * COL_BRASS_BACK_TINT
	# Mock pillar: top:2 bottom:2 (so y=2..58), width:2.
	var w_px: float = 2.0 * sx
	var top_y: float = 2.0 * sy
	var bot_y: float = (SVG_H - 2.0) * sy
	# Three-stop gradient drawn as three thin rects for cheap fidelity.
	var seg_h: float = (bot_y - top_y) / 3.0
	var x_px: float = svg_x * sx
	draw_rect(Rect2(x_px, top_y, w_px, seg_h), col_top, true)
	draw_rect(Rect2(x_px, top_y + seg_h, w_px, seg_h), col_mid, true)
	draw_rect(Rect2(x_px, top_y + seg_h * 2.0, w_px, seg_h), col_bot, true)
	# Black outline (1 px in mock).
	draw_rect(Rect2(x_px, top_y, w_px, bot_y - top_y), Color.BLACK, false, 1.0)


# Brass cap at SVG-y, height 6, overhang -6..SVG_W+6 in mock space.
# Stripped to two bands + black border — the previous version had the
# mock's inset highlight + shadow lines but those were imperceptible at
# 96 px and added two per-frame draw_line calls per cap.
func _draw_cap(svg_y: float, sx: float, sy: float) -> void:
	var x_px: float = -6.0 * sx
	var y_px: float = svg_y * sy
	var w_px: float = (SVG_W + 12.0) * sx
	var h_px: float = 6.0 * sy
	# Two-stop gradient via two horizontal bands.
	var band_h: float = h_px * 0.5
	draw_rect(Rect2(x_px, y_px, w_px, band_h), COL_BRASS_1, true)
	draw_rect(Rect2(x_px, y_px + band_h, w_px, band_h), COL_BRASS_3, true)
	# Black border.
	draw_rect(Rect2(x_px, y_px, w_px, h_px), Color.BLACK, false, 1.0)
