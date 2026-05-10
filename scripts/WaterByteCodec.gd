class_name WaterByteCodec
extends RefCounted

# WaterByteCodec — single source of truth for the water byte layout
# stored in VoxelBuffer.CHANNEL_DATA5 (Zylann's first user-defined
# data channel — DATA0..4 are reserved for TYPE/SDF/COLOR/INDICES/
# WEIGHTS).
#
# Every voxel of water in the world is one byte in CHANNEL_DATA.
# Air water = 0. Anything nonzero is "water of some kind."
#
# Bit layout (8 bits total):
#   bits 0-3 : level (0 = air; 1-8 = water level, 8 = full cell)
#   bit  4   : source bit (1 = permanent source, 0 = flow cell)
#   bits 5-7 : last-fed-tick (mod-8 counter used by the flow decay rule)
#
# Why this lives in its own file: the generator (worker threads), the
# water mesher (main thread), the flow simulator, the edit manager,
# and the player query path all need to encode/decode this byte. Putting
# the layout in one file with named constants means a layout change is
# a one-file edit.
#
# Reference: design/SWIMMING_AND_WATER.md (Voxel Water Architecture).


# ============================================================
# Bit masks
# ============================================================

const LEVEL_MASK: int   = 0x0F   # bits 0-3
const SOURCE_BIT: int   = 0x10   # bit 4
const TICK_SHIFT: int   = 5
const TICK_MASK: int    = 0xE0   # bits 5-7, shifted up

const MAX_LEVEL: int    = 8      # full water cell (sources are always 8)
const MIN_LEVEL: int    = 1      # below this = air; level 0 means "not water"


# ============================================================
# Pre-baked common values
# ============================================================

const AIR_BYTE: int     = 0
# A canonical "no water" byte — equivalent to writing nothing.

const SOURCE_BYTE: int  = MAX_LEVEL | SOURCE_BIT
# Permanent source at full level. Generator writes this for every
# below-sea-level voxel; bucket placements write the same byte.


# ============================================================
# Pack / unpack
# ============================================================

static func pack(level: int, source: bool, tick: int) -> int:
	# Build a water byte from its three logical fields. Each field is
	# clamped/masked so a bad caller can't smuggle bits into a neighbour
	# field. Param is named `source` (not `is_source`) so it doesn't
	# shadow the `is_source` accessor static below.
	var lvl: int = clampi(level, 0, MAX_LEVEL)
	var src: int = SOURCE_BIT if source else 0
	var t: int = (tick & 0x07) << TICK_SHIFT
	return lvl | src | t


static func level_of(byte: int) -> int:
	return byte & LEVEL_MASK


static func is_source(byte: int) -> bool:
	return (byte & SOURCE_BIT) != 0


static func tick_of(byte: int) -> int:
	return (byte & TICK_MASK) >> TICK_SHIFT


static func is_water(byte: int) -> bool:
	# True iff this byte represents any water (source or flow). The flow
	# tick uses this to short-circuit "is the cell above me full of
	# water?" without needing to unpack the level field.
	return (byte & LEVEL_MASK) > 0
