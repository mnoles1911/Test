extends CanvasLayer

# =============================================================
# WaterTuner — live knob panel for wind + #15 foam shader params
# =============================================================
#
# Dev-only. Default OFF. F8 toggles. While ON it OWNS the wind: it
# re-pushes wind every frame so WeatherManager can't fight it, and
# writes the foam shader params live onto the shared water material.
# While OFF it does nothing — normal weather drives the wind again.
#
# Keyboard only by project rule (Button/HSlider signals do not fire
# here — Dialogic consumes mouse input; see CLAUDE.md / WaterDiag).
#
# SETUP (one-time, like every dev autoload here):
#   Project Settings → Autoload → res://scripts/_dev/WaterTuner.gd
#   as "WaterTuner".
#
# CONTROLS (only while the panel is ON):
#   F8            toggle panel on/off
#   Up / Down     select a parameter
#   Left / Right  −/+ the selected parameter by its step
#   Shift+L/R     coarse (×10) step
#   [  /  ]       cycle wind PRESET  (Calm → Breeze → Brisk → Storm → Gale)
#   R             reset every value to the shader defaults
#   P             print the current values to Output (paste into the
#                 .tres to make them the new defaults)
#
# THROW-AWAY-ish: it only WRITES params. Removing the autoload + file
# reverts to weather-driven wind with the .tres defaults. Tune, find
# values you like, P to print them, bake into water_material.tres.

const MAT_PATH: String = "res://assets/shaders/water_material.tres"

# name, shader-param ("" = the wind pseudo-params), value, step, min, max
var _params: Array = [
	{"n": "wind_strength",          "p": "",                       "v": 0.5,  "s": 0.1,  "lo": 0.0,  "hi": 5.0},
	{"n": "wind_dir_deg",           "p": "",                       "v": 0.0,  "s": 15.0, "lo": 0.0,  "hi": 360.0},
	{"n": "surface_motion_strength","p": "surface_motion_strength", "v": 0.7,  "s": 0.05, "lo": 0.0,  "hi": 1.0},
	{"n": "surface_motion_speed",   "p": "surface_motion_speed",    "v": 0.6,  "s": 0.1,  "lo": 0.0,  "hi": 3.0},
	{"n": "surface_ripple_scale",   "p": "surface_ripple_scale",    "v": 0.7,  "s": 0.1,  "lo": 0.05, "hi": 4.0},
	{"n": "foam_wind_ref",          "p": "foam_wind_ref",           "v": 2.0,  "s": 0.1,  "lo": 0.2,  "hi": 5.0},
]
var _defaults: Array = []
const WIND_PRESETS: Array = [
	["Calm", 0.0], ["Breeze", 0.8], ["Brisk", 1.6], ["Storm", 2.8], ["Gale", 4.0],
]

var _active: bool = false
var _sel: int = 0
var _preset: int = 0
var _mat: ShaderMaterial = null
var _label: Label = null
var _bg: ColorRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	visible = false
	for d in _params:
		_defaults.append((d["v"] as float))
	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	_bg.position = Vector2(18, 18)
	_bg.size = Vector2(430, 196)
	add_child(_bg)
	_label = Label.new()
	_label.position = Vector2(30, 26)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(_label)
	set_process(true)
	print("[WaterTuner] loaded (OFF). F8 toggles. Dev-only — see WATER_STAGE6_PLAN / #15.")


func _get_mat() -> ShaderMaterial:
	if _mat == null:
		_mat = load(MAT_PATH) as ShaderMaterial
	return _mat


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_F8:
		_active = not _active
		visible = _active
		if _active:
			_sync_from_material()
			print("[WaterTuner] ON — owns wind+foam (overrides weather).")
		else:
			print("[WaterTuner] OFF — weather drives wind again.")
		get_viewport().set_input_as_handled()
		return
	if not _active:
		return
	# While active, the panel eats its keys so tuning never leaks to play.
	var handled := true
	match k.keycode:
		KEY_UP:
			_sel = (_sel - 1 + _params.size()) % _params.size()
		KEY_DOWN:
			_sel = (_sel + 1) % _params.size()
		KEY_LEFT:
			_nudge(-1.0, k.shift_pressed)
		KEY_RIGHT:
			_nudge(1.0, k.shift_pressed)
		KEY_BRACKETLEFT:
			_cycle_preset(-1)
		KEY_BRACKETRIGHT:
			_cycle_preset(1)
		KEY_R:
			for i in _params.size():
				_params[i]["v"] = _defaults[i]
			print("[WaterTuner] reset to defaults.")
		KEY_P:
			_print_values()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _nudge(dir_sign: float, coarse: bool) -> void:
	var d: Dictionary = _params[_sel]
	var step: float = (d["s"] as float) * (10.0 if coarse else 1.0)
	var nv: float = (d["v"] as float) + dir_sign * step
	d["v"] = clampf(nv, d["lo"] as float, d["hi"] as float)


func _cycle_preset(dir: int) -> void:
	_preset = (_preset + dir + WIND_PRESETS.size()) % WIND_PRESETS.size()
	# Preset drives wind_strength (param 0); foam_wind_ref stays a free
	# knob so you can watch the SAME wind read as more/less foam.
	_params[0]["v"] = float(WIND_PRESETS[_preset][1])
	print("[WaterTuner] wind preset = %s (%.1f)" % [WIND_PRESETS[_preset][0], _params[0]["v"]])


func _sync_from_material() -> void:
	# Start the panel from whatever the material currently has, so it
	# doesn't snap values when you open it.
	var m: ShaderMaterial = _get_mat()
	if m == null:
		return
	for d in _params:
		var p: String = d["p"]
		if p == "":
			continue
		var cur = m.get_shader_parameter(p)
		if cur != null:
			d["v"] = clampf(float(cur), d["lo"] as float, d["hi"] as float)


func _process(_dt: float) -> void:
	if not _active:
		return
	var m: ShaderMaterial = _get_mat()
	if m == null:
		return
	# Foam params straight onto the shared material.
	for d in _params:
		var p: String = d["p"]
		if p != "":
			m.set_shader_parameter(p, d["v"] as float)
	# Wind via WaterFlowManager EVERY frame so it overrides WeatherManager.
	var wfm := get_node_or_null("/root/WaterFlowManager")
	if wfm != null and wfm.has_method("set_global_wind"):
		var deg: float = _params[1]["v"]
		var rad: float = deg_to_rad(deg)
		wfm.set_global_wind(Vector3(cos(rad), 0.0, sin(rad)), _params[0]["v"] as float)
	_refresh_label()


func _refresh_label() -> void:
	var lines: Array = []
	lines.append("WATER TUNER  (F8 off · ↑↓ pick · ←→ ±  Shift=×10)")
	lines.append("wind preset: < %s >   ([ ] cycle · R reset · P print)" % WIND_PRESETS[_preset][0])
	for i in _params.size():
		var d: Dictionary = _params[i]
		var mark: String = "▶ " if i == _sel else "  "
		lines.append("%s%-24s %7.2f" % [mark, d["n"], d["v"]])
	_label.text = "\n".join(lines)


func _print_values() -> void:
	var s: String = "[WaterTuner] values — paste into water_material.tres:\n"
	s += "  wind: strength=%.2f dir_deg=%.0f (preset %s)\n" % [
		_params[0]["v"], _params[1]["v"], WIND_PRESETS[_preset][0]]
	for d in _params:
		if d["p"] != "":
			s += "  shader_parameter/%s = %.3f\n" % [d["p"], d["v"]]
	print(s)
