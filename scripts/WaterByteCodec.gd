class_name WaterByteCodec
extends RefCounted

# WaterByteCodec — single source of truth for the water byte layout
# stored in VoxelBuffer.CHANNEL_DATA5 (Zylann's first user-defined
# data channel — DATA0..4 are reserved for TYPE/SDF/COLOR/INDICES/
# WEIGHTS).
#
# Every voxel of water in the world is one byte in CHANNEL_DATA5.
# Air water = 0. Anything nonzero is "water of some kind."
#
# Bit layout (8 bits total):
#   bits 0-3 : level (0 = air; 1-8 = water level, 8 = full cell)
#   bit  4   : source bit (1 = permanent source, 0 = flow cell)
#   bits 5-7 : flow DIRECTION (Stage 6) — which way this cell drains
#
# STAGE 6 CHANGE (2026-05-18): bits 5-7 used to be a mod-8 "last-fed
# tick" counter for an old decay rule. That rule died in the Water
# Voxel V2 flow rewrite (the live sim tracks freshness in
# WaterFlowManager dictionaries — _edit_cell_ttl / _pending_water —
# NOT in the voxel byte). The field had ZERO live callers
# (WaterByteCodec.pack / tick_of were unused project-wide), so Stage 6
# repurposes it as the per-voxel flow direction. This is what lets the
# surface mesher slope + animate the water and what flags a waterfall
# (dir == DIR_DOWN && level < MAX_LEVEL). See design/WATER_STAGE6_PLAN.md.
#
# Why this lives in its own file: the generator (worker threads), the
# water surface mesher (main thread), the flow simulator, the edit
# manager, and the player query path all need to encode/decode this
# byte. One file with named constants means a layout change is a
# one-file edit.
#
# Reference: design/SWIMMING_AND_WATER.md, design/WATER_STAGE6_PLAN.md.


# ============================================================
# Bit masks
# ============================================================

const LEVEL_MASK: int   = 0x0F   # bits 0-3
const SOURCE_BIT: int   = 0x10   # bit 4
const DIR_SHIFT: int    = 5
const DIR_MASK: int     = 0xE0   # bits 5-7, in place

const MAX_LEVEL: int    = 8      # full water cell (sources are always 8)
const MIN_LEVEL: int    = 1      # below this = air; level 0 means "not water"


# ============================================================
# Flow direction codes (3 bits, 0-7) — bits 5-7 of the byte
# ============================================================
# The direction a cell is draining toward. STILL = settled / no net
# flow (the common case: lakes, full sources, the deep interior of a
# body). DIR_DOWN is the waterfall trigger. DIR_UP is reserved for a
# possible future pressure rule and is currently treated as STILL by
# dir_to_offset's caller expectations (offset = +Y but the sim does
# not produce it yet). Code 7 is reserved and decodes as STILL.

const DIR_STILL: int = 0
const DIR_POS_X: int = 1   # +X
const DIR_NEG_X: int = 2   # -X
const DIR_POS_Z: int = 3   # +Z
const DIR_NEG_Z: int = 4   # -Z
const DIR_DOWN:  int = 5   # -Y  (waterfall / vertical drain)
const DIR_UP:    int = 6   # +Y  (reserved — pressure; unused by the sim yet)
const DIR_RSVD:  int = 7   # reserved; decodes as STILL


# ============================================================
# Pre-baked common values
# ============================================================

const AIR_BYTE: int     = 0
# A canonical "no water" byte — equivalent to writing nothing.

const SOURCE_BYTE: int  = MAX_LEVEL | SOURCE_BIT
# Permanent source at full level, direction STILL (dir bits = 0, so the
# numeric value is unchanged from the pre-Stage-6 layout — old saves
# that stored this value still decode correctly: level 8, source, STILL).
# Generator writes this for every below-sea-level voxel; bucket
# placements write the same byte.


# ============================================================
# Pack / unpack
# ============================================================

static func pack(level: int, source: bool, dir: int) -> int:
	# Build a water byte from its three logical fields. Each field is
	# clamped/masked so a bad caller can't smuggle bits into a
	# neighbour field. `source` (not `is_source`) so it does not shadow
	# the is_source() accessor below.
	var lvl: int = clampi(level, 0, MAX_LEVEL)
	var src: int = SOURCE_BIT if source else 0
	var d: int = (clampi(dir, 0, 7) << DIR_SHIFT) & DIR_MASK
	return lvl | src | d


static func level_of(byte: int) -> int:
	return byte & LEVEL_MASK


static func is_source(byte: int) -> bool:
	return (byte & SOURCE_BIT) != 0


static func dir_of(byte: int) -> int:
	return (byte & DIR_MASK) >> DIR_SHIFT


static func is_water(byte: int) -> bool:
	# True iff this byte represents any water (source or flow). The flow
	# tick uses this to short-circuit "is the cell above me water?"
	# without unpacking the level field.
	return (byte & LEVEL_MASK) > 0


static func is_inside_water_column(byte: int, frac_y: float) -> bool:
	# Height-aware point test (W5, finite-water track): is a point at
	# fractional height `frac_y` inside THIS voxel (0.0 = the voxel's
	# bottom face, 1.0 = its top face) actually underwater, given the
	# voxel's water byte?
	#
	# A level-N cell is water only up to N/8 of the voxel's height —
	# so wading through a level-2 puddle does NOT count as swimming,
	# and the camera doesn't get the underwater filter from standing
	# over a shallow pool. Level 8 (and legacy/source bytes) fill the
	# whole voxel, which preserves the old behaviour for oceans.
	var lvl: int = byte & LEVEL_MASK
	if lvl <= 0:
		return false
	return frac_y <= float(lvl) / float(MAX_LEVEL)


# ============================================================
# Field mutators — return a NEW byte with one field replaced, the
# others preserved. Phase 1+ flow sim uses these to retarget a cell's
# level/direction without rebuilding all three fields by hand.
# ============================================================

static func set_level(byte: int, level: int) -> int:
	return (byte & ~LEVEL_MASK) | clampi(level, 0, MAX_LEVEL)


static func set_dir(byte: int, dir: int) -> int:
	return (byte & ~DIR_MASK) | ((clampi(dir, 0, 7) << DIR_SHIFT) & DIR_MASK)


static func set_source(byte: int, source: bool) -> int:
	return (byte | SOURCE_BIT) if source else (byte & ~SOURCE_BIT)


# ============================================================
# Direction <-> grid offset. Single source of truth for the spatial
# meaning of a dir code, so the flow sim and the surface mesher agree.
# ============================================================

static func dir_to_offset(dir: int) -> Vector3i:
	match dir:
		DIR_POS_X: return Vector3i(1, 0, 0)
		DIR_NEG_X: return Vector3i(-1, 0, 0)
		DIR_POS_Z: return Vector3i(0, 0, 1)
		DIR_NEG_Z: return Vector3i(0, 0, -1)
		DIR_DOWN:  return Vector3i(0, -1, 0)
		DIR_UP:    return Vector3i(0, 1, 0)
		_:         return Vector3i.ZERO   # STILL / reserved


static func offset_to_dir(offset: Vector3i) -> int:
	# Inverse of dir_to_offset for the canonical 6 unit offsets. The sim
	# passes the offset toward the neighbour it drains into. Anything
	# that is not a unit cardinal step (incl. zero) → STILL.
	if offset == Vector3i(1, 0, 0):  return DIR_POS_X
	if offset == Vector3i(-1, 0, 0): return DIR_NEG_X
	if offset == Vector3i(0, 0, 1):  return DIR_POS_Z
	if offset == Vector3i(0, 0, -1): return DIR_NEG_Z
	if offset == Vector3i(0, -1, 0): return DIR_DOWN
	if offset == Vector3i(0, 1, 0):  return DIR_UP
	return DIR_STILL
