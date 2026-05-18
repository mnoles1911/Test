@tool
extends EditorScript

# WaterByteCodecParity — Stage 6 Phase 0 gate.
#
# No headless Godot in this project, so this is a @tool EditorScript:
# open the project in Godot 4.6.2, open this file, File → Run (or the
# editor's "Run" on an EditorScript). Read the Output panel; paste the
# final [WBCParity] verdict line back.
#
# It exhaustively round-trips EVERY (level, source, dir) combination
# through WaterByteCodec and asserts:
#   1. each field unpacks to exactly what was packed (no truncation),
#   2. no field bleeds into another (set one, the others are untouched),
#   3. the mutators (set_level/set_dir/set_source) preserve siblings,
#   4. dir <-> grid-offset round-trips for the 6 cardinal codes,
#   5. backward-compat invariants: AIR_BYTE == 0; the pre-Stage-6
#      SOURCE_BYTE numeric value (24) still decodes level 8 / source /
#      STILL (old VoxelStreamSQLite saves remain correct).
#
# Bit-exact is the only acceptable gate (CLAUDE.md C++/codec rule).
# This file is dev-only; it is never loaded by the game.


func _run() -> void:
	var fails: int = 0
	var checks: int = 0

	# --- 1+2. Exhaustive pack/unpack with no field bleed ---
	for level in range(0, WaterByteCodec.MAX_LEVEL + 1):       # 0..8
		for source in [false, true]:
			for dir in range(0, 8):                            # 0..7
				var b: int = WaterByteCodec.pack(level, source, dir)
				checks += 1
				if WaterByteCodec.level_of(b) != level:
					fails += 1
					push_error("[WBCParity] level bleed: in=%d src=%s dir=%d byte=%d -> level_of=%d" % [level, source, dir, b, WaterByteCodec.level_of(b)])
				if WaterByteCodec.is_source(b) != source:
					fails += 1
					push_error("[WBCParity] source bleed: in level=%d src=%s dir=%d byte=%d" % [level, source, dir, b])
				if WaterByteCodec.dir_of(b) != dir:
					fails += 1
					push_error("[WBCParity] dir bleed: level=%d src=%s in dir=%d byte=%d -> dir_of=%d" % [level, source, dir, b, WaterByteCodec.dir_of(b)])
				# byte must fit in 8 bits
				if b < 0 or b > 255:
					fails += 1
					push_error("[WBCParity] byte out of range: %d" % b)

	# --- 3. Mutators preserve sibling fields ---
	# Start from a fully-loaded byte (level 3, source, +X) and mutate
	# each field, asserting the other two are untouched.
	var base: int = WaterByteCodec.pack(3, true, WaterByteCodec.DIR_POS_X)
	for nl in range(0, WaterByteCodec.MAX_LEVEL + 1):
		var m: int = WaterByteCodec.set_level(base, nl)
		checks += 1
		if WaterByteCodec.level_of(m) != nl or not WaterByteCodec.is_source(m) or WaterByteCodec.dir_of(m) != WaterByteCodec.DIR_POS_X:
			fails += 1
			push_error("[WBCParity] set_level clobbered siblings: nl=%d byte=%d" % [nl, m])
	for nd in range(0, 8):
		var m2: int = WaterByteCodec.set_dir(base, nd)
		checks += 1
		if WaterByteCodec.dir_of(m2) != nd or WaterByteCodec.level_of(m2) != 3 or not WaterByteCodec.is_source(m2):
			fails += 1
			push_error("[WBCParity] set_dir clobbered siblings: nd=%d byte=%d" % [nd, m2])
	for ns in [false, true]:
		var m3: int = WaterByteCodec.set_source(base, ns)
		checks += 1
		if WaterByteCodec.is_source(m3) != ns or WaterByteCodec.level_of(m3) != 3 or WaterByteCodec.dir_of(m3) != WaterByteCodec.DIR_POS_X:
			fails += 1
			push_error("[WBCParity] set_source clobbered siblings: ns=%s byte=%d" % [ns, m3])

	# --- 4. dir <-> offset round-trip for the 6 cardinal codes ---
	for dir in [WaterByteCodec.DIR_POS_X, WaterByteCodec.DIR_NEG_X, WaterByteCodec.DIR_POS_Z, WaterByteCodec.DIR_NEG_Z, WaterByteCodec.DIR_DOWN, WaterByteCodec.DIR_UP]:
		checks += 1
		var off: Vector3i = WaterByteCodec.dir_to_offset(dir)
		if WaterByteCodec.offset_to_dir(off) != dir:
			fails += 1
			push_error("[WBCParity] dir<->offset broke: dir=%d off=%s back=%d" % [dir, off, WaterByteCodec.offset_to_dir(off)])
	# STILL and reserved map to zero offset; zero offset maps back to STILL.
	checks += 1
	if WaterByteCodec.dir_to_offset(WaterByteCodec.DIR_STILL) != Vector3i.ZERO:
		fails += 1
		push_error("[WBCParity] STILL offset not zero")
	checks += 1
	if WaterByteCodec.offset_to_dir(Vector3i.ZERO) != WaterByteCodec.DIR_STILL:
		fails += 1
		push_error("[WBCParity] zero offset not STILL")

	# --- 5. Backward-compat invariants ---
	checks += 1
	if WaterByteCodec.AIR_BYTE != 0:
		fails += 1
		push_error("[WBCParity] AIR_BYTE must be 0, got %d" % WaterByteCodec.AIR_BYTE)
	# Pre-Stage-6 SOURCE_BYTE = MAX_LEVEL | SOURCE_BIT = 8 | 16 = 24.
	# Old saves stored exactly this; it must still decode level 8 /
	# source / STILL after the tick→dir repurpose (dir bits were 0).
	checks += 1
	if WaterByteCodec.SOURCE_BYTE != 24:
		fails += 1
		push_error("[WBCParity] SOURCE_BYTE numeric value changed (was 24, now %d) — breaks old saves" % WaterByteCodec.SOURCE_BYTE)
	var sb: int = WaterByteCodec.SOURCE_BYTE
	checks += 1
	if WaterByteCodec.level_of(sb) != WaterByteCodec.MAX_LEVEL or not WaterByteCodec.is_source(sb) or WaterByteCodec.dir_of(sb) != WaterByteCodec.DIR_STILL:
		fails += 1
		push_error("[WBCParity] SOURCE_BYTE decode wrong: lvl=%d src=%s dir=%d" % [WaterByteCodec.level_of(sb), WaterByteCodec.is_source(sb), WaterByteCodec.dir_of(sb)])
	checks += 1
	if WaterByteCodec.is_water(WaterByteCodec.AIR_BYTE) or not WaterByteCodec.is_water(sb):
		fails += 1
		push_error("[WBCParity] is_water wrong for AIR/SOURCE")

	# --- Verdict ---
	if fails == 0:
		print("[WBCParity] PASS — %d checks, 0 failures. Phase 0 codec is bit-exact." % checks)
	else:
		print("[WBCParity] FAIL — %d failures across %d checks (see push_error lines above)." % [fails, checks])
