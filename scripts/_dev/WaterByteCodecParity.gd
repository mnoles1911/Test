@tool
extends EditorScript

# WaterByteCodecParity — Stage 6 codec gate (in-editor path).
#
# Open the project in Godot 4.6.2, open this file, File -> Run. Read the
# Output panel; paste the final [WBCParity] verdict line back.
#
# The assertions now live in WaterByteCodecParityLib (pure, no editor /
# no SceneTree) so this in-editor path AND the headless runner
# (tools/headless/runner.gd) call EXACTLY the same code — no divergence.
# Bit-exact is the only acceptable gate (CLAUDE.md C++/codec rule).
# This file is dev-only; it is never loaded by the game.


const ParityLib := preload("res://scripts/_dev/WaterByteCodecParityLib.gd")

func _run() -> void:
	var r: Dictionary = ParityLib.run()
	var checks: int = r["checks"]
	var fails: int = r["fails"]
	var errors: PackedStringArray = r["errors"]
	for e in errors:
		push_error("[WBCParity] %s" % e)
	if fails == 0:
		print("[WBCParity] PASS — %d checks, 0 failures. Codec is bit-exact." % checks)
	else:
		print("[WBCParity] FAIL — %d failures across %d checks (see push_error lines above)." % [fails, checks])
