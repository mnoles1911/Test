extends Node
# AudioManager — autoload: the single API for playing sound effects by id.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Every system that wants a sound (a footstep, a pickaxe hit, a campfire,
#   a sword swing) calls one function here with a short string "id" like
#   "vox_pick_strike_stone". This autoload finds the matching .ogg under
#   res://assets/audio/sfx/<folder>/, random-picks a variation if several
#   exist, plays it on the correct audio bus, and (for positional sounds)
#   at the right spot in the 3D world. Nothing else needs to know where
#   files live or how buses are wired.
#
#   THREE APIS:
#
#     play(id, world_pos = null, bus = "")
#       — One-shot. Pass a Vector3 world_pos for a 3D positional sound;
#         omit it for a flat non-positional sound (UI, stingers). The
#         player frees itself when the sound finishes.
#
#     play_loop(id, world_pos = null, bus = "") -> int
#       — Starts a looping sound (campfire, wind bed, swim loop) and
#         returns an integer handle. Keep the handle to stop it later.
#
#     stop_loop(handle)  /  stop_all_loops()
#       — Stop one loop, or all of them (e.g. on scene change).
#
#   GRACEFUL BY DESIGN: we generate SFX to a Desktop review folder first
#   and curate/convert/place them into the repo later. Until a given
#   file is placed, calling its id simply logs one warning and is silent.
#   The game runs fine today, and each sound "switches on" automatically
#   the moment its .ogg lands in assets/audio/sfx/ — no code changes.
#
#   FILE RESOLUTION: the id prefix maps to a folder (mirrors
#   SFX_LIBRARY.md §2 and tools/render_sfx.py). It looks for "<id>.ogg"
#   then "<id>_01.ogg", "<id>_02.ogg", … and random-picks among whatever
#   exists — that is the anti-"machine-gun" variation the footstep and
#   impact sets need.
#
#   BUS: chosen from the id prefix to match default_bus_layout.tres
#   (Combat / Ambient / Voice / NPC / UI / SFX), or pass an override.
#
#   POOLING: AudioStreamPlayer nodes are pre-allocated and reused, the
#   same reason BloodVFX pools particles — during heavy play (footsteps
#   + combat) instantiate-on-demand stutters. Idle players are recycled;
#   if the pool is exhausted a temporary player is made and auto-freed.
#
# LOAD ORDER: registered before the voxel/water/weather/bark managers so
# they can safely call it from their _ready(). Depends on no other
# autoload. NOTE: looping is also enabled per-file by the Godot import
# setting (Import → Loop) per assets/audio/sfx/README.md; play_loop also
# sets the stream's loop flag defensively.

const SFX_ROOT := "res://assets/audio/sfx/"
const MAX_VARIATIONS := 20          # probe <id>_01 .. <id>_20
const POOL_3D := 12                 # reused positional one-shot players
const POOL_2D := 6                  # reused non-positional one-shot players

# id-prefix -> repo folder. Order matters (longest/most specific first).
const PREFIX_FOLDER := [
	["step_", "locomotion"], ["jump", "locomotion"], ["land_", "locomotion"],
	["armor_", "locomotion"], ["climb_", "locomotion"], ["vault_", "locomotion"],
	["water_wade", "locomotion"], ["water_entry", "locomotion"],
	["roland_", "locomotion"],
	["cmb_", "combat"],
	["vox_", "voxel"],
	["wx_", "environment"], ["fire_", "environment"], ["water_", "environment"],
	["amb_", "ambience"],
	["craft_", "crafting"],
	["item_", "items"],
	["lock_", "systems"], ["minigame_", "systems"], ["invest_", "systems"],
	["wld_", "creatures"],
	["npc_", "npc"],
	["econ_", "economy"],
	["ui_", "ui"], ["journal_", "ui"], ["map_", "ui"], ["save_", "ui"],
	["skill_", "ui"], ["camp_rest_", "ui"], ["pause_", "ui"],
]

# id-prefix -> bus name (must exist in default_bus_layout.tres).
const PREFIX_BUS := [
	["cmb_", "Combat"],
	["wx_", "Ambient"], ["fire_", "Ambient"], ["water_", "Ambient"],
	["amb_", "Ambient"],
	["roland_breath", "Voice"], ["roland_effort", "Voice"],
	["roland_jump", "Voice"], ["water_surface_gasp", "Voice"],
	["npc_", "NPC"],
	["ui_", "UI"], ["journal_", "UI"], ["map_", "UI"], ["save_", "UI"],
	["skill_", "UI"], ["camp_rest_", "UI"], ["pause_", "UI"],
]

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}          # handle:int -> player node
var _next_handle: int = 1
var _path_cache: Dictionary = {}     # id -> Array[String] of resource paths
var _warned: Dictionary = {}         # id -> true (warn once per missing id)


func _ready() -> void:
	# Pre-build the reuse pools as children of this autoload node.
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	# Subscribe to gameplay signals once every autoload exists. This
	# autoload loads before VoxelEditManager, so we defer to the end of
	# this frame, by which point all autoloads are present.
	call_deferred("_wire_world_signals")


# --- Public API ----------------------------------------------------------

# One-shot. world_pos: Vector3 for a 3D sound, or null for flat/UI.
func play(id: String, world_pos = null, bus: String = "") -> void:
	var stream := _pick_stream(id)
	if stream == null:
		return
	var bus_name := _bus_for(id, bus)
	if world_pos is Vector3:
		var p := _idle_3d()
		p.bus = bus_name
		p.global_position = world_pos
		p.stream = stream
		p.play()
	else:
		var p := _idle_2d()
		p.bus = bus_name
		p.stream = stream
		p.play()


# Looping sound. Returns a handle for stop_loop(); 0 if the file is absent.
func play_loop(id: String, world_pos = null, bus: String = "") -> int:
	var stream := _pick_stream(id)
	if stream == null:
		return 0
	# Belt-and-suspenders: ensure the stream loops even if the import
	# setting wasn't toggled (AudioStreamOggVorbis exposes `loop`).
	if "loop" in stream:
		stream.loop = true
	var bus_name := _bus_for(id, bus)
	var node: Node
	if world_pos is Vector3:
		var p := AudioStreamPlayer3D.new()
		p.global_position = world_pos
		node = p
	else:
		node = AudioStreamPlayer.new()
	node.bus = bus_name
	node.stream = stream
	add_child(node)
	node.play()
	var handle := _next_handle
	_next_handle += 1
	_loops[handle] = node
	return handle


func stop_loop(handle: int) -> void:
	if _loops.has(handle):
		var n: Node = _loops[handle]
		_loops.erase(handle)
		if is_instance_valid(n):
			n.stop()
			n.queue_free()


func stop_all_loops() -> void:
	for handle in _loops.keys():
		var n: Node = _loops[handle]
		if is_instance_valid(n):
			n.stop()
			n.queue_free()
	_loops.clear()


# --- Internals -----------------------------------------------------------

func _pick_stream(id: String) -> AudioStream:
	var paths := _resolve(id)
	if paths.is_empty():
		if not _warned.has(id):
			_warned[id] = true
			push_warning("AudioManager: no file yet for '%s' (silent until "
				% id + "placed in assets/audio/sfx/). This is expected "
				+ "pre-curation.")
		return null
	return load(paths.pick_random()) as AudioStream


func _resolve(id: String) -> Array:
	if _path_cache.has(id):
		return _path_cache[id]
	var folder := _folder_for(id)
	var found: Array = []
	if folder != "":
		var base := SFX_ROOT + folder + "/"
		if ResourceLoader.exists(base + id + ".ogg"):
			found.append(base + id + ".ogg")
		else:
			for i in range(1, MAX_VARIATIONS + 1):
				var p := base + "%s_%02d.ogg" % [id, i]
				if ResourceLoader.exists(p):
					found.append(p)
				elif i > 1:
					break   # contiguous numbering; stop at first gap
	_path_cache[id] = found
	return found


func _folder_for(id: String) -> String:
	for rule in PREFIX_FOLDER:
		if id.begins_with(rule[0]):
			return rule[1]
	return ""


func _bus_for(id: String, override: String) -> String:
	if override != "":
		return override
	for rule in PREFIX_BUS:
		if id.begins_with(rule[0]):
			return rule[1]
	return "SFX"


func _idle_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	# Pool exhausted: transient player that frees itself when done.
	var t := AudioStreamPlayer3D.new()
	add_child(t)
	t.finished.connect(t.queue_free)
	return t


func _idle_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	var t := AudioStreamPlayer.new()
	add_child(t)
	t.finished.connect(t.queue_free)
	return t


# --- Gameplay signal wiring ----------------------------------------------
#
# The audio layer subscribes to gameplay signals here rather than editing
# the gameplay scripts. Low-risk, localized, idempotent, and guarded — if a
# system is absent the connection is simply skipped.

func _wire_world_signals() -> void:
	# NoEditZone rejection -> the dull "this place doesn't yield" thunk.
	var vem := get_node_or_null("/root/VoxelEditManager")
	if vem != null and vem.has_signal("edit_rejected_no_edit_zone"):
		if not vem.is_connected(
				"edit_rejected_no_edit_zone", _on_edit_rejected):
			vem.connect("edit_rejected_no_edit_zone", _on_edit_rejected)


func _on_edit_rejected(world_pos: Vector3) -> void:
	# Reuses the unbreakable-block thunk for blocked edits (same feel:
	# "this didn't give"). Silent until vox_bedrock_blocked.ogg is placed.
	play("vox_bedrock_blocked", world_pos)
