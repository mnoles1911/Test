extends Control
class_name LoadingHourglass
# LoadingHourglass — a hand-drawn hourglass that progresses sand from
# the top half to the bottom half as `progress` (0.0 → 1.0) advances.
#
# What this does in plain English:
#   The hourglass is drawn with two triangles meeting at the centre
#   (the "waist"). The TOP triangle starts full of sand and drains; the
#   BOTTOM triangle starts empty and fills. Call set_progress(p) to
#   update the sand levels — the Control redraws on the next frame.
#
# Geometry (in local Control coordinates, where (0,0) is the top-left
# and (size.x, size.y) is the bottom-right):
#   - Top triangle vertices:    (0,0), (w,0), (w/2, h/2)
#   - Bottom triangle vertices: (w/2, h/2), (0,h), (w,h)
#   - At progress p, the top sand surface sits at y = p·(h/2). Sand below
#     that line (down to the waist) is what's still in the top half.
#   - The bottom sand surface sits at y = h − p·(h/2). Sand below that
#     (down to the base) is what has accumulated.

@export var sand_color: Color = Color(0.92, 0.78, 0.42, 1.0)
@export var frame_color: Color = Color(0.92, 0.86, 0.7, 1.0)
@export var frame_width: float = 3.0

# 0.0 = full at top, empty at bottom. 1.0 = empty at top, full at bottom.
var progress: float = 0.0


func set_progress(p: float) -> void:
	progress = clamp(p, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	var w: float = s.x
	var h: float = s.y
	var half_h: float = h * 0.5
	var p: float = progress

	# Epsilon margin: when the sand surface is within this fraction of
	# 0 or 1, the trapezoid we'd build collapses to a degenerate polygon
	# (two coincident vertices, or zero area). Godot's triangulator
	# rejects those with "Invalid polygon data, triangulation failed".
	# We snap to a clean triangle (or skip the draw) at the endpoints.
	const EPSILON: float = 0.001

	# --- Top sand pile (drains as p → 1) -------------------------------
	# At y inside the top triangle, the left edge sits at x = (y/half_h)·(w/2).
	# So at the sand surface y = p·half_h, the inset from each side is
	# p·(w/2). The remaining sand is a triangle from that surface down to
	# the waist point at (w/2, half_h). At p≈1 it collapses to a point —
	# skip the draw entirely.
	if p < 1.0 - EPSILON:
		var top_surface_y: float = p * half_h
		var top_inset: float = p * (w * 0.5)
		var top_sand: PackedVector2Array = PackedVector2Array([
			Vector2(top_inset, top_surface_y),
			Vector2(w - top_inset, top_surface_y),
			Vector2(w * 0.5, half_h),
		])
		draw_colored_polygon(top_sand, sand_color)

	# --- Bottom sand pile (fills as p → 1) -----------------------------
	# Mirror of the top: as p grows, the surface rises from y=h up toward
	# the waist. At p≈0 there's no sand to draw. At p≈1 the trapezoid's
	# top edge collapses to a point at the waist — switch to a triangle
	# (waist, bottom-right, bottom-left) so triangulation stays valid.
	if p > EPSILON:
		var bot_sand: PackedVector2Array
		if p >= 1.0 - EPSILON:
			bot_sand = PackedVector2Array([
				Vector2(w * 0.5, half_h),
				Vector2(w, h),
				Vector2(0.0, h),
			])
		else:
			var bot_surface_y: float = h - p * half_h
			var bot_inset: float = p * (w * 0.5)
			bot_sand = PackedVector2Array([
				Vector2(bot_inset, bot_surface_y),
				Vector2(w - bot_inset, bot_surface_y),
				Vector2(w, h),
				Vector2(0.0, h),
			])
		draw_colored_polygon(bot_sand, sand_color)

	# --- Falling sand stream -------------------------------------------
	# Thin vertical line at the waist while sand is still draining.
	if p > EPSILON and p < 1.0 - EPSILON:
		var stream_end_y: float = h - p * half_h
		draw_line(
			Vector2(w * 0.5, half_h),
			Vector2(w * 0.5, stream_end_y),
			sand_color,
			2.0
		)

	# --- Glass outline -------------------------------------------------
	# Walk the perimeter of both triangles in one polyline. The path
	# revisits the waist twice (once from each side) so both halves are
	# stroked cleanly.
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(w, 0.0),
		Vector2(w * 0.5, half_h),
		Vector2(w, h),
		Vector2(0.0, h),
		Vector2(w * 0.5, half_h),
		Vector2(0.0, 0.0),
	])
	draw_polyline(outline, frame_color, frame_width, true)

	# --- Wooden caps (top + bottom) ------------------------------------
	# Small horizontal bars overhanging each side, hinting at the frame.
	var cap_thickness: float = max(4.0, h * 0.04)
	var cap_overhang: float = w * 0.08
	draw_rect(
		Rect2(-cap_overhang, -cap_thickness, w + cap_overhang * 2.0, cap_thickness),
		frame_color,
		true
	)
	draw_rect(
		Rect2(-cap_overhang, h, w + cap_overhang * 2.0, cap_thickness),
		frame_color,
		true
	)
