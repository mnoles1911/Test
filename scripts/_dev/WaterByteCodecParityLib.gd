class_name WaterByteCodecParityLib
extends RefCounted

# WaterByteCodecParityLib — shared parity assertions for WaterByteCodec.
#
# The logic lives here (pure, no editor / no SceneTree) so BOTH run paths
# call exactly the same code with no divergence:
#   • in-editor:  scripts/_dev/WaterByteCodecParity.gd  (@tool EditorScript,
#                 File -> Run, reads the Output panel) — unchanged workflow.
#   • headless:   tools/headless/runner.gd  (godot --headless --script ...)
#
# run() returns { checks:int, fails:int, errors:PackedStringArray }.
# Callers decide how to print / what exit code to use. Bit-exact is the
# only acceptable gate (CLAUDE.md C++/codec rule).


static func run() -> Dictionary:
	var fails: int = 0
	var checks: int = 0
	var errors: PackedStringArray = PackedStringArray()

	# --- 1+2. Exhaustive pack/unpack with no field bleed ---
	for level in range(0, WaterByteCodec.MAX_LEVEL + 1):       # 0..8
		for source in [false, true]:
			for dir in range(0, 8):                            # 0..7
				var b: int = WaterByteCodec.pack(level, source, dir)
				checks += 1
				if WaterByteCodec.level_of(b) != level:
					fails += 1
					errors.append("level bleed: in=%d src=%s dir=%d byte=%d -> level_of=%d" % [level, source, dir, b, WaterByteCodec.level_of(b)])
				if WaterByteCodec.is_source(b) != source:
					fails += 1
					errors.append("source bleed: in level=%d src=%s dir=%d byte=%d" % [level, source, dir, b])
				if WaterByteCodec.dir_of(b) != dir:
					fails += 1
					errors.append("dir bleed: level=%d src=%s in dir=%d byte=%d -> dir_of=%d" % [level, source, dir, b, WaterByteCodec.dir_of(b)])
				if b < 0 or b > 255:
					fails += 1
					errors.append("byte out of range: %d" % b)

	# --- 3. Mutators preserve sibling fields ---
	var base: int = WaterByteCodec.pack(3, true, WaterByteCodec.DIR_POS_X)
	for nl in range(0, WaterByteCodec.MAX_LEVEL + 1):
		var m: int = WaterByteCodec.set_level(base, nl)
		checks += 1
		if WaterByteCodec.level_of(m) != nl or not WaterByteCodec.is_source(m) or WaterByteCodec.dir_of(m) != WaterByteCodec.DIR_POS_X:
			fails += 1
			errors.append("set_level clobbered siblings: nl=%d byte=%d" % [nl, m])
	for nd in range(0, 8):
		var m2: int = WaterByteCodec.set_dir(base, nd)
		checks += 1
		if WaterByteCodec.dir_of(m2) != nd or WaterByteCodec.level_of(m2) != 3 or not WaterByteCodec.is_source(m2):
			fails += 1
			errors.append("set_dir clobbered siblings: nd=%d byte=%d" % [nd, m2])
	for ns in [false, true]:
		var m3: int = WaterByteCodec.set_source(base, ns)
		checks += 1
		if WaterByteCodec.is_source(m3) != ns or WaterByteCodec.level_of(m3) != 3 or WaterByteCodec.dir_of(m3) != WaterByteCodec.DIR_POS_X:
			fails += 1
			errors.append("set_source clobbered siblings: ns=%s byte=%d" % [ns, m3])

	# --- 4. dir <-> offset round-trip for the 6 cardinal codes ---
	for dir in [WaterByteCodec.DIR_POS_X, WaterByteCodec.DIR_NEG_X, WaterByteCodec.DIR_POS_Z, WaterByteCodec.DIR_NEG_Z, WaterByteCodec.DIR_DOWN, WaterByteCodec.DIR_UP]:
		checks += 1
		var off: Vector3i = WaterByteCodec.dir_to_offset(dir)
		if WaterByteCodec.offset_to_dir(off) != dir:
			fails += 1
			errors.append("dir<->offset broke: dir=%d off=%s back=%d" % [dir, off, WaterByteCodec.offset_to_dir(off)])
	checks += 1
	if WaterByteCodec.dir_to_offset(WaterByteCodec.DIR_STILL) != Vector3i.ZERO:
		fails += 1
		errors.append("STILL offset not zero")
	checks += 1
	if WaterByteCodec.offset_to_dir(Vector3i.ZERO) != WaterByteCodec.DIR_STILL:
		fails += 1
		errors.append("zero offset not STILL")

	# --- 5. Backward-compat invariants ---
	checks += 1
	if WaterByteCodec.AIR_BYTE != 0:
		fails += 1
		errors.append("AIR_BYTE must be 0, got %d" % WaterByteCodec.AIR_BYTE)
	checks += 1
	if WaterByteCodec.SOURCE_BYTE != 24:
		fails += 1
		errors.append("SOURCE_BYTE numeric value changed (was 24, now %d) — breaks old saves" % WaterByteCodec.SOURCE_BYTE)
	var sb: int = WaterByteCodec.SOURCE_BYTE
	checks += 1
	if WaterByteCodec.level_of(sb) != WaterByteCodec.MAX_LEVEL or not WaterByteCodec.is_source(sb) or WaterByteCodec.dir_of(sb) != WaterByteCodec.DIR_STILL:
		fails += 1
		errors.append("SOURCE_BYTE decode wrong: lvl=%d src=%s dir=%d" % [WaterByteCodec.level_of(sb), WaterByteCodec.is_source(sb), WaterByteCodec.dir_of(sb)])
	checks += 1
	if WaterByteCodec.is_water(WaterByteCodec.AIR_BYTE) or not WaterByteCodec.is_water(sb):
		fails += 1
		errors.append("is_water wrong for AIR/SOURCE")

	# --- 6. Height-aware point test (W5 finite-water track) ---
	# A level-N cell holds water up to N/8 of the voxel: the boundary
	# itself counts as wet (<=), level 0 is never wet, level 8 fills
	# the whole voxel (incl. SOURCE_BYTE — old ocean behaviour intact).
	for lvl in range(0, 9):
		var b: int = WaterByteCodec.pack(lvl, false, WaterByteCodec.DIR_STILL)
		for f in [0.0, 0.124, 0.5, 0.874, 1.0]:
			checks += 1
			var want: bool = lvl > 0 and f <= float(lvl) / 8.0
			if WaterByteCodec.is_inside_water_column(b, f) != want:
				fails += 1
				errors.append("is_inside_water_column wrong: lvl=%d frac=%.3f" % [lvl, f])
	checks += 1
	if not WaterByteCodec.is_inside_water_column(WaterByteCodec.SOURCE_BYTE, 1.0):
		fails += 1
		errors.append("SOURCE_BYTE must fill the whole voxel")

	return {"checks": checks, "fails": fails, "errors": errors}
