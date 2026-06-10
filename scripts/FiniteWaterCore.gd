extends RefCounted

# FiniteWaterCore — the finite, volume-conserving water simulation.
# Design + designer decisions: design/WATER_FINITE_SIM_PLAN.md.
#
# What this is in plain English:
#
# Every cell of "finite" water (player-placed buckets, inland pools) is
# an entry in `_ledger`: a dictionary mapping a voxel position to how
# many UNITS of water sit in that cell (1..8; 8 = a full voxel). When
# the sim runs, units physically MOVE between cells — down first, then
# sideways toward lower neighbours — until everything is level. Because
# every move is "subtract 1 here, add 1 there", the total amount of
# water can never silently change. That total is auditable at any
# moment:
#
#   total_units() == placed - evaporated - absorbed - merged
#
# and the headless `finite` selector asserts it after every scenario.
#
# THE ONE BIG LESSON from the previous two water sims (post-mortem in
# WATER_FINITE_SIM_PLAN.md): this class NEVER reads the voxel world to
# learn where its own water is. The ledger is the single authority; the
# voxel world (CHANNEL_TYPE / DATA5) is a write-only projection of it.
# That is why this file has no TTL-retry machinery, no pending-write
# shadow dict, and no self-heal scan — none of it is needed when the
# sim trusts its own memory instead of an async-written buffer.
#
# This file is deliberately PURE:
#   - no SceneTree, no autoload references, no VoxelTool — headless-safe
#   - the world is abstracted behind two Callables (solid / source)
#   - deterministic: active cells are processed in ascending (y, x, z)
#     order with sequential 1-unit transfers, so two runs with the same
#     inputs produce byte-identical states every tick (gated)
# Purity is what makes it testable (tools/headless: `finite` selector)
# and portable to C++ later (PR W6) with a bit-exact parity gate.
#
# NO class_name — loaded via path preload only, like WaterMaterial.gd
# (class_name registration breaks the headless script cache).


# ============================================================
# Tunables (designer dials — see WATER_FINITE_SIM_PLAN.md)
# ============================================================

const SPREAD_REACH_VOXELS: int = 18
# How far water may CREEP ACROSS A LEVEL SURFACE from where it was
# introduced, in voxels (18 vox = 3 m at 6 vox/m). Each sideways step
# into fresh air increments a cell's "distance budget"; at 18 the front
# stops advancing and the pool deepens instead. Falling down a ledge
# RESETS the budget (a waterfall starts a fresh pool at its base).
# Equalization between cells that are already water ignores this —
# otherwise a pool could never flatten.

const EVAP_TTL: int = 40
# Ticks (~10 s at 4 Hz) before an ORPHANED 1-unit cell evaporates.
# Level-1 cells can never donate sideways (the donor rule needs >= 2
# units), so thin films can't creep — but draining can strand a lone
# 1-unit cell on a ledge. If such a cell has NO water in any of its 6
# face-neighbours, it arms this countdown; any water arriving next to
# it cancels the countdown. Evaporated units are ledgered so the
# conservation audit still balances.

const MAX_UNITS_PER_CELL: int = 8
# A full voxel of water. Matches WaterByteCodec.MAX_LEVEL — level and
# units are the SAME number, which is what lets the renderer draw a
# 3-unit cell as the existing level-3 fluid model with zero new code.


# ============================================================
# World plumbing (set once by the owner before stepping)
# ============================================================

var solid_cb: Callable = Callable()
# func(pos: Vector3i) -> bool. True = terrain blocks water here (solid
# voxel, or a NoEditZone that blocks water flow). The headless gates
# pass simple lambdas; WaterFlowManager passes a snapshot-backed test.

var source_cb: Callable = Callable()
# func(pos: Vector3i) -> bool. True = INFINITE water here (the ocean,
# designer headwaters — DATA5 source bit). Source cells are immutable
# boundary conditions: they never change, never donate. Finite water
# that flows INTO one is swallowed (absorbed/merged, ledgered).

var sea_y: int = -0x7fffffff
# Voxel Y of sea level. Only used for the two ocean-interaction rules
# (merge + lateral absorb). The default (very low) means "no ocean" —
# pure inland behaviour — which is also what the headless gates use
# unless a scenario sets it.


# ============================================================
# Sim state — _ledger is the authority, everything else is bookkeeping
# ============================================================

var _ledger: Dictionary = {}
# Vector3i -> int units (1..8). THE TRUTH. A cell not in here has no
# finite water, full stop.

var _dist: Dictionary = {}
# Vector3i -> int. Spread-reach budget spent to get here (0 where water
# was placed or fell; +1 per sideways step into fresh air). Transient —
# deliberately NOT persisted (see design doc: after save/load, water is
# dormant until disturbed, and the disturbance grants a fresh budget).

var _evap_ttl: Dictionary = {}
# Vector3i -> int. Armed evaporation countdowns (orphaned 1-unit cells
# only). Absent = not armed.

var _dir: Dictionary = {}
# Vector3i -> int WaterByteCodec.DIR_* code. Which way this cell mostly
# drained last tick — the renderer/currents read this. Settled cells
# revert to DIR_STILL.

var _active: Dictionary = {}
# Vector3i -> true. Cells the next step() must look at. Quiet cells
# drop out; a 3x3x3 dump only ever touches its own neighbourhood, never
# the world.

var _merged_sources: Dictionary = {}
# Vector3i -> true. Finite cells that joined the ocean (merge rule).
# The projection writes SOURCE_BYTE there, but until the owner's source
# snapshot refreshes, the core must remember these itself so the very
# next tick already treats them as infinite.

var _external_changed: Dictionary = {}
# Vector3i -> true. Cells mutated OUTSIDE step() (place / ingest /
# remove). The next step() folds these into its change stream so the
# owner has exactly ONE projection path — no special-case writes at
# call sites, no cell can be shown stale because a placement happened
# between ticks.

# Conservation counters (the audit trail).
var placed: int = 0        # units ever introduced via place()/ingest()
var evaporated: int = 0    # orphaned 1-unit cells that timed out
var absorbed: int = 0      # units that fell/flowed into source water
var merged: int = 0        # units in cells that joined the ocean
var removed: int = 0       # units scooped back out (bucket fill)


# ============================================================
# Public API
# ============================================================

func place(pos: Vector3i, units: int) -> int:
	# Introduce water. Fills `pos` up to 8 units, then stacks any excess
	# into the cells directly above (a 1000-unit "place" is a tall
	# column that immediately starts collapsing — gate scenario 5).
	# Returns how many units were actually placed (solid cells block).
	var remaining: int = maxi(0, units)
	var k: int = 0
	while remaining > 0 and k < 256:
		var p: Vector3i = pos + Vector3i(0, k, 0)
		if _is_solid(p) or _is_source(p):
			break   # can't pour into rock or into the (infinite) ocean
		var cur: int = int(_ledger.get(p, 0))
		var add: int = mini(MAX_UNITS_PER_CELL - cur, remaining)
		if add > 0:
			_ledger[p] = cur + add
			if cur == 0:
				_dist[p] = 0   # fresh water starts a fresh spread budget
			placed += add
			remaining -= add
			_external_changed[p] = true
			_activate_with_neighbours(p)
		k += 1
	return maxi(0, units) - remaining


func activate(pos: Vector3i) -> void:
	# Poke a cell awake (e.g. terrain next to it was just carved). Safe
	# to call on anything; only ledger cells actually wake.
	_activate_with_neighbours(pos)


func ingest(pos: Vector3i, units: int) -> void:
	# Adopt water that already exists in the world (dormant DATA5 water
	# the player just disturbed — W4 activation path). Unlike place()
	# this does NOT stack upward and DOES count toward `placed`, because
	# from the ledger's point of view this water is newly tracked.
	if units <= 0 or _is_solid(pos) or _is_source(pos):
		return
	if _ledger.has(pos):
		return   # already tracked — don't double-count
	_ledger[pos] = clampi(units, 1, MAX_UNITS_PER_CELL)
	_dist[pos] = 0
	placed += int(_ledger[pos])
	_external_changed[pos] = true
	_activate_with_neighbours(pos)


func remove(pos: Vector3i, max_units: int) -> int:
	# Scoop water back out (bucket fill). Takes up to max_units from
	# this cell, then from the cells stacked directly above it (you
	# scoop from the top of a column's worth of standing water at this
	# spot, but a single call never drains more than one bucket).
	# Returns the units actually removed; they are ledgered so the
	# conservation audit still balances.
	var got: int = 0
	var k: int = 0
	while got < max_units and k < 16:
		var p: Vector3i = pos + Vector3i(0, k, 0)
		if _ledger.has(p):
			var u: int = int(_ledger[p])
			var take: int = mini(u, max_units - got)
			got += take
			if take >= u:
				_clear_cell(p)
			else:
				_ledger[p] = u - take
			_external_changed[p] = true
			_wake_ledger_neighbours(p)
			_activate_with_neighbours(p)
		k += 1
	removed += got
	return got


func projected_byte(pos: Vector3i) -> int:
	# Public read of "what DATA5 byte should the world show here" — the
	# owner uses this to re-queue writes the edit queue rejected.
	return _projected_byte(pos)


func has_cell(pos: Vector3i) -> bool:
	return _ledger.has(pos)


func total_units() -> int:
	var sum: int = 0
	for p in _ledger.keys():
		sum += int(_ledger[p])
	return sum


func is_settled() -> bool:
	return _active.is_empty()


func has_pending_changes() -> bool:
	# True while anything still needs a tick: cells to simulate OR
	# externally-mutated cells whose projection hasn't been flushed.
	return not _active.is_empty() or not _external_changed.is_empty()


func units_at(pos: Vector3i) -> int:
	return int(_ledger.get(pos, 0))


func conservation_delta() -> int:
	# 0 when the books balance. Anything else is a bug — the engine
	# integration prints a loud warning if this ever goes nonzero.
	return total_units() - (placed - evaporated - absorbed - merged - removed)


func stats() -> Dictionary:
	return {
		"units": total_units(),
		"active": _active.size(),
		"placed": placed,
		"evaporated": evaporated,
		"absorbed": absorbed,
		"merged": merged,
		"removed": removed,
	}


func state_signature() -> String:
	# Deterministic fingerprint of the full sim state, for the
	# determinism + C++ parity gates. Sorted (y, x, z) so the string is
	# identical across runs/languages regardless of dictionary order.
	var keys: Array = _ledger.keys()
	keys.sort_custom(_cell_order)
	var parts: PackedStringArray = PackedStringArray()
	for p in keys:
		parts.append("%d,%d,%d=%d/%d/%d" % [
			p.x, p.y, p.z, int(_ledger[p]),
			int(_dist.get(p, 0)), int(_dir.get(p, WaterByteCodec.DIR_STILL)),
		])
	return ";".join(parts)


func step(budget: int) -> Dictionary:
	# Advance the sim one tick. Processes up to `budget` active cells in
	# ascending (y, x, z) order (lowest first — bottoms settle before
	# tops, and the order is the determinism contract). Returns:
	#   changes: PackedInt32Array stream [x, y, z, byte, ...] — every
	#            cell whose projected DATA5 byte changed this tick.
	#            byte 0 = water gone; SOURCE_BYTE = joined the ocean;
	#            anything else = pack(units, false, dir).
	#   stats:   the conservation counters (see stats()).
	var changed: Dictionary = {}   # Vector3i -> true
	# Fold in cells mutated between ticks (place / ingest / remove) so
	# their projection rides the same change stream as sim moves.
	for p in _external_changed.keys():
		changed[p] = true
	_external_changed.clear()

	var worklist: Array = _active.keys()
	worklist.sort_custom(_cell_order)
	if budget > 0 and worklist.size() > budget:
		worklist = worklist.slice(0, budget)

	for c in worklist:
		_active.erase(c)   # re-armed below if the cell is still busy
		if not _ledger.has(c):
			_evap_ttl.erase(c)
			continue
		_step_cell(c, changed)

	# Build the change stream.
	var out_changes: PackedInt32Array = PackedInt32Array()
	var ckeys: Array = changed.keys()
	ckeys.sort_custom(_cell_order)
	for p in ckeys:
		out_changes.append(p.x)
		out_changes.append(p.y)
		out_changes.append(p.z)
		out_changes.append(_projected_byte(p))
	return {"changes": out_changes, "stats": stats()}


# ============================================================
# Internal — per-cell rules (the order here IS the spec; see
# WATER_FINITE_SIM_PLAN.md "Sim rules")
# ============================================================

func _step_cell(c: Vector3i, changed: Dictionary) -> void:
	var u: int = int(_ledger[c])

	# RULE 5 — ocean merge. Touching the infinite ocean at/below sea
	# level means this cell IS ocean now; its units leave the finite
	# books (ledgered as merged).
	if c.y <= sea_y and _touches_source(c):
		merged += u
		_clear_cell(c)
		_merged_sources[c] = true
		changed[c] = true
		_wake_ledger_neighbours(c)
		return

	# RULE 1 — DOWN first. Water under us beats everything else.
	var below: Vector3i = c + Vector3i(0, -1, 0)
	var moved_down: int = 0
	if not _is_solid(below):
		if _is_source(below):
			# Falling into the ocean: swallowed entirely.
			absorbed += u
			_clear_cell(c)
			changed[c] = true
			_wake_ledger_neighbours(c)
			return
		var ub: int = int(_ledger.get(below, 0))
		if ub < MAX_UNITS_PER_CELL:
			var m: int = mini(u, MAX_UNITS_PER_CELL - ub)
			_ledger[below] = ub + m
			if ub == 0:
				_dist[below] = 0   # a drop starts a fresh spread budget
			u -= m
			moved_down = m
			changed[below] = true
			_activate_with_neighbours(below)
			if u == 0:
				_clear_cell(c)
				changed[c] = true
				_wake_ledger_neighbours(c)
				return
			_ledger[c] = u
			changed[c] = true   # partial drop still changed OUR level

	# RULE 2 — lateral equalization. Only donors with >= 2 units, and
	# only while standing on something (solid / source / full water) —
	# free-falling water doesn't fan out sideways mid-air.
	var lateral_moved: Dictionary = {}   # dir code -> units moved that way
	if u >= 2 and _is_supported(c):
		var my_dist: int = int(_dist.get(c, 0))
		while u >= 2:
			var best_n: Vector3i = c
			var best_u: int = 0x7fffffff
			var best_code: int = WaterByteCodec.DIR_STILL
			for i in range(4):
				var d: Vector3i = _LATERAL[i]
				var n: Vector3i = c + d
				if _is_solid(n):
					continue
				var n_eff: int
				if _is_source(n):
					if n.y > sea_y:
						continue   # never absorb into an above-sea headwater
					n_eff = -1     # the ocean is always "lower" — absorb
				elif _ledger.has(n):
					n_eff = int(_ledger[n])
					if n_eff > u - 2:
						continue   # gap of 1 is level enough — stop (this
						           # is what makes convergence terminate)
				else:
					if my_dist >= SPREAD_REACH_VOXELS:
						continue   # front has used up its creep budget
					n_eff = 0
				if n_eff < best_u:
					best_u = n_eff
					best_n = n
					best_code = _LATERAL_CODE[i]
			if best_u == 0x7fffffff:
				break   # nowhere lower to go
			# Move exactly 1 unit (integer moves = exact conservation).
			u -= 1
			_ledger[c] = u
			if best_u == -1:
				absorbed += 1
			else:
				var was_empty: bool = not _ledger.has(best_n)
				_ledger[best_n] = int(_ledger.get(best_n, 0)) + 1
				if was_empty:
					_dist[best_n] = my_dist + 1
				_evap_ttl.erase(best_n)   # fresh water cancels any countdown
				changed[best_n] = true
				_activate_with_neighbours(best_n)
			lateral_moved[best_code] = int(lateral_moved.get(best_code, 0)) + 1
			changed[c] = true

	# Flow-direction byte: whichever way the most units went this tick.
	# DOWN beats laterals on a tie (it reads better as a waterfall).
	var new_dir: int = WaterByteCodec.DIR_STILL
	var best_moved: int = 0
	for i in range(4):
		# Fixed iteration order (+X, -X, +Z, -Z) — part of the
		# determinism contract; dictionary order is NOT.
		var code: int = _LATERAL_CODE[i]
		var m_code: int = int(lateral_moved.get(code, 0))
		if m_code > best_moved:
			best_moved = m_code
			new_dir = code
	if moved_down >= best_moved and moved_down > 0:
		new_dir = WaterByteCodec.DIR_DOWN
	var old_dir: int = int(_dir.get(c, WaterByteCodec.DIR_STILL))
	if new_dir != old_dir:
		_dir[c] = new_dir
		changed[c] = true

	var did_move: bool = moved_down > 0 or not lateral_moved.is_empty()

	# RULE 4 — orphaned-film evaporation. A lone 1-unit cell with no
	# water beside it counts down and disappears (ledgered).
	if u == 1 and not _has_water_neighbour(c):
		var t: int = int(_evap_ttl.get(c, 0)) + 1
		if t >= EVAP_TTL:
			evaporated += 1
			_clear_cell(c)
			changed[c] = true
			return
		_evap_ttl[c] = t
		_active[c] = true   # must keep ticking or the countdown freezes
		return
	else:
		_evap_ttl.erase(c)

	# RULE 3 — stay awake only while something is happening. A cell
	# whose units changed must ALSO wake its water neighbours: losing
	# units can make this cell a valid target for a neighbour that had
	# already gone quiet (e.g. neighbour=3 next to us at 1 — it must
	# get another turn or the pool freezes one step short of level).
	if did_move:
		_active[c] = true
		_wake_ledger_neighbours(c)
	# else: cell goes dormant. Neighbours it fed were woken above; if
	# anything changes next to it later, _activate_with_neighbours will
	# pull it back in.


# ============================================================
# Internal — small helpers
# ============================================================

# Lateral neighbour order is FIXED (+X, -X, +Z, -Z): it is the
# tie-break rule and therefore part of the determinism contract. The
# C++ port (W6) must use the identical order.
const _LATERAL: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const _LATERAL_CODE: Array = [
	WaterByteCodec.DIR_POS_X, WaterByteCodec.DIR_NEG_X,
	WaterByteCodec.DIR_POS_Z, WaterByteCodec.DIR_NEG_Z,
]

const _FACES_6: Array = [
	Vector3i(0, -1, 0), Vector3i(0, 1, 0),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func _cell_order(a: Vector3i, b: Vector3i) -> bool:
	# Ascending (y, x, z) — the project's cross-language total ordering
	# (extensions/voxel_gen/CLAUDE.md rule 4).
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return a.z < b.z


func _is_solid(p: Vector3i) -> bool:
	return solid_cb.is_valid() and bool(solid_cb.call(p))


func _is_source(p: Vector3i) -> bool:
	if _merged_sources.has(p):
		return true
	return source_cb.is_valid() and bool(source_cb.call(p))


func _is_supported(c: Vector3i) -> bool:
	var b: Vector3i = c + Vector3i(0, -1, 0)
	return _is_solid(b) or _is_source(b) \
		or int(_ledger.get(b, 0)) >= MAX_UNITS_PER_CELL


func _touches_source(c: Vector3i) -> bool:
	for d in _FACES_6:
		if _is_source(c + d):
			return true
	return false


func _has_water_neighbour(c: Vector3i) -> bool:
	for d in _FACES_6:
		var n: Vector3i = c + d
		if _ledger.has(n) or _is_source(n):
			return true
	return false


func _clear_cell(c: Vector3i) -> void:
	_ledger.erase(c)
	_dist.erase(c)
	_evap_ttl.erase(c)
	_dir.erase(c)


func _activate_with_neighbours(p: Vector3i) -> void:
	if _ledger.has(p):
		_active[p] = true
	_wake_ledger_neighbours(p)


func _wake_ledger_neighbours(p: Vector3i) -> void:
	for d in _FACES_6:
		var n: Vector3i = p + d
		if _ledger.has(n):
			_active[n] = true


func _projected_byte(p: Vector3i) -> int:
	# The DATA5 byte the world should show for this cell right now.
	if _merged_sources.has(p):
		return WaterByteCodec.SOURCE_BYTE
	if not _ledger.has(p):
		return WaterByteCodec.AIR_BYTE
	return WaterByteCodec.pack(
		int(_ledger[p]), false,
		int(_dir.get(p, WaterByteCodec.DIR_STILL)))
