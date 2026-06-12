extends Node3D

# WaterFoamManager — D4 flowing-water foam (10cm micro-detail pass).
#
# WHAT (plain English): where the finite water sim says a cell is MOVING
# (its DATA5 DIR bits are not STILL), we want a faint puff of white foam so
# rivers and pour-points read as alive instead of glassy. The naive way —
# one particle node per moving cell — would spawn hundreds of nodes. Instead
# this manager owns ONE pooled GPUParticles3D (CPUParticles3D fallback if GPU
# particles look dicey) and REPOSITIONS it across up to MAX_FOAM_SITES active
# flow sites near the player each sim tick. A single emitter visiting many
# sites reads as scattered foam at a fraction of the cost.
#
# OWNERSHIP + GATING: WaterFlowManager creates this node as a child (only in
# a real windowed game — never headless) and calls update_foam_sites() each
# sim tick, but ONLY after checking GraphicsManager.water_foam_enabled. The
# feature ships DEFAULT OFF (new-visual-layer rule); the designer flips it on
# his GPU. When off, WaterFlowManager never even calls in here, so foam costs
# nothing.
#
# This script lives under scripts/graphics/ alongside GraphicsManager. It is
# instantiated programmatically (no .tscn) so existing scenes need no edits.

# Max simultaneous flow sites the single emitter visits per tick. The
# emitter is repositioned to the FIRST site and a short burst is emitted;
# the remaining sites are covered by the pooled CPU/GPU particle lifetime
# spreading across positions as the emitter hops between ticks. Kept small
# (~8) so the visual stays subtle and cheap.
const MAX_FOAM_SITES: int = 8

# Particle look. White, short-lived, small — a faint spray, not a fountain.
const FOAM_LIFETIME_S: float = 0.8
const FOAM_BASE_AMOUNT: int = 24
const FOAM_COLOR: Color = Color(1.0, 1.0, 1.0, 0.65)

var _particles: Node3D = null     # GPUParticles3D or CPUParticles3D
var _is_gpu: bool = false
var _ready_ok: bool = false


func _ready() -> void:
	_build_emitter()


func _build_emitter() -> void:
	# Prefer GPUParticles3D; fall back to CPUParticles3D if it can't be made
	# (some headless / software-renderer contexts). The caller already
	# guarantees we're not in the headless harness, but be defensive.
	if ClassDB.class_exists("GPUParticles3D"):
		var p := GPUParticles3D.new()
		p.amount = FOAM_BASE_AMOUNT
		p.lifetime = FOAM_LIFETIME_S
		p.one_shot = false
		p.emitting = false
		p.local_coords = false
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 35.0
		mat.initial_velocity_min = 0.2
		mat.initial_velocity_max = 0.8
		mat.gravity = Vector3(0, -1.5, 0)
		mat.scale_min = 0.4
		mat.scale_max = 1.0
		mat.color = FOAM_COLOR
		p.process_material = mat
		p.draw_pass_1 = _make_foam_mesh()
		add_child(p)
		_particles = p
		_is_gpu = true
		_ready_ok = true
		return
	if ClassDB.class_exists("CPUParticles3D"):
		var c := CPUParticles3D.new()
		c.amount = FOAM_BASE_AMOUNT
		c.lifetime = FOAM_LIFETIME_S
		c.one_shot = false
		c.emitting = false
		c.local_coords = false
		c.direction = Vector3(0, 1, 0)
		c.spread = 35.0
		c.initial_velocity_min = 0.2
		c.initial_velocity_max = 0.8
		c.gravity = Vector3(0, -1.5, 0)
		c.scale_amount_min = 0.4
		c.scale_amount_max = 1.0
		c.color = FOAM_COLOR
		c.mesh = _make_foam_mesh()
		add_child(c)
		_particles = c
		_is_gpu = false
		_ready_ok = true
		return
	push_warning("[WaterFoamManager] No particle class available; foam disabled.")


func _make_foam_mesh() -> Mesh:
	# A tiny quad billboard for each foam particle. Unshaded white so it
	# reads bright against teal water; transparent so the spray is soft.
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.08)   # ~8 cm — one micro-voxel wide
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.albedo_color = FOAM_COLOR
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = bm
	return qm


# Called by WaterFlowManager each sim tick (ONLY when the toggle is on).
# `sites` is an Array of Dictionaries: { "pos": Vector3 (world), "flow": float
# 0..1 }. We move the single emitter to the strongest site and scale its
# emission rate by that site's flow level. An empty list stops emission.
func update_foam_sites(sites: Array) -> void:
	if not _ready_ok or _particles == null:
		return
	if sites.is_empty():
		_set_emitting(false)
		return
	# Pick the strongest of up to MAX_FOAM_SITES sites as the anchor (the
	# pooled emitter can only be in one place; visiting the strongest site
	# each tick keeps the most visible flow foamy).
	var best: Dictionary = sites[0]
	var best_flow: float = float(best.get("flow", 0.0))
	var count: int = mini(sites.size(), MAX_FOAM_SITES)
	for i in range(1, count):
		var f: float = float(sites[i].get("flow", 0.0))
		if f > best_flow:
			best_flow = f
			best = sites[i]
	_particles.global_position = best.get("pos", Vector3.ZERO)
	# Emission rate scales with flow level (more flow = more foam). Clamp to
	# at least a trickle so a slow current still shows something.
	var amt: int = int(round(lerpf(float(FOAM_BASE_AMOUNT) * 0.4, float(FOAM_BASE_AMOUNT), clampf(best_flow, 0.0, 1.0))))
	if _is_gpu:
		(_particles as GPUParticles3D).amount = maxi(amt, 1)
	else:
		(_particles as CPUParticles3D).amount = maxi(amt, 1)
	_set_emitting(true)


func _set_emitting(on: bool) -> void:
	if _particles == null:
		return
	if _is_gpu:
		(_particles as GPUParticles3D).emitting = on
	else:
		(_particles as CPUParticles3D).emitting = on
