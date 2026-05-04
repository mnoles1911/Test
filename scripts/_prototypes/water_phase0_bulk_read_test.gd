extends Node3D
# WaterPhase0BulkReadTest — measures the cost of bulk VoxelTool.get_voxel
# calls at the design tick rate of 4 Hz (every 15 physics frames at 60 fps).
#
# What this validates: the WaterFlowManager flow tick is designed to do
# ~30k voxel reads per 4 Hz tick. If that costs more than ~2 ms per tick,
# we need a per-chunk packed-cache layer in Phase 1. This script measures
# the actual cost on a real loaded VoxelLodTerrain so we know before we
# commit to Phase 1+.
#
# Usage: open `scenes/_prototypes/water_phase0.tscn` in Godot and run.
# Output panel logs a rolling average frame time spent on bulk reads
# every 5 seconds. Note the value, copy it into design/LESSONS_LEARNED.md.
#
# Throwaway code — delete after Phase 0 validation completes.

const READS_PER_TICK: int = 30_000
const TICK_INTERVAL_FRAMES: int = 15  # ~4 Hz at 60 fps
const REPORT_INTERVAL_SECONDS: float = 5.0

var _frame_count: int = 0
var _ticks_run: int = 0
var _total_usec: int = 0
var _seconds_since_report: float = 0.0


func _physics_process(delta: float) -> void:
	_frame_count += 1
	_seconds_since_report += delta

	if _frame_count >= TICK_INTERVAL_FRAMES:
		_frame_count = 0
		_run_one_tick()

	if _seconds_since_report >= REPORT_INTERVAL_SECONDS:
		_seconds_since_report = 0.0
		_report()


func _run_one_tick() -> void:
	# Find VoxelLodTerrain via VoxelEditManager autoload (which already
	# caches it). If it's not ready yet, skip this tick.
	var terrain: Node = VoxelEditManager.get_terrain() if VoxelEditManager.has_method("get_terrain") else null
	if terrain == null:
		return

	var tool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = 2  # CHANNEL_COLOR

	# Sample 30k voxels in a sphere around origin (or wherever the terrain
	# has actual data loaded — the scene puts the prototype Node3D near
	# the test world's origin).
	var center: Vector3i = Vector3i(0, 50, 0)
	var radius: int = 20  # 20 vox = ~3.3 m at 6 vox/m

	var t0: int = Time.get_ticks_usec()
	var reads_done: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _ticks_run
	while reads_done < READS_PER_TICK:
		var dx: int = rng.randi_range(-radius, radius)
		var dy: int = rng.randi_range(-radius, radius)
		var dz: int = rng.randi_range(-radius, radius)
		var _packed: int = tool.get_voxel(center + Vector3i(dx, dy, dz))
		reads_done += 1
	var elapsed: int = Time.get_ticks_usec() - t0

	_total_usec += elapsed
	_ticks_run += 1


func _report() -> void:
	if _ticks_run == 0:
		print("[WaterPhase0] no ticks run yet (terrain not ready?)")
		return
	var avg_us: float = float(_total_usec) / float(_ticks_run)
	var avg_ms: float = avg_us / 1000.0
	print("[WaterPhase0] %d ticks of %d reads — avg %.2f ms/tick (target < 2.00 ms)" % [
		_ticks_run, READS_PER_TICK, avg_ms,
	])
