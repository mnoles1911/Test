extends Node
# GraphicsManager — owns the graphics-quality tier and applies it.
#
# What this does, in plain English:
#   The game has five graphics presets (see ShaderProfile.gd). This
#   autoload remembers which one the player picked, saves it to disk,
#   and — whenever a world scene loads — pushes that preset's settings
#   into the live WorldEnvironment, the viewport, and the sun/moon
#   lights.
#
#   The HIGH preset is the default and reproduces exactly what
#   World3D.tscn ships with, so a first-time player sees no change.
#   Lower presets switch expensive features off so a weaker PC stays
#   smooth; ULTRA adds SDFGI on top for powerful GPUs.
#
# Where the pieces are:
#   - Tier definitions (the actual numbers): _build_profiles() below —
#     edit those longhand assignments to retune a tier.
#   - The chosen tier: persisted to user://graphics.json.
#   - Applied by: World3DBootstrap._ready() calls apply_current().
#   - Changed by: the GRAPHICS QUALITY button in Settings, which calls
#     cycle_tier().
#
# Headless-safe: every apply step null-guards. In the headless test
# harness there is no real viewport / lights, so apply_current() just
# sets harmless properties and moves on.

# ShaderProfile is preloaded by PATH (not referenced via class_name) so
# this script parses cleanly in the headless harness, which does not
# rescan global classes. The const doubles as a usable type annotation.
const ShaderProfile := preload("res://scripts/graphics/ShaderProfile.gd")

# Tier order MUST match the array index used in _build_profiles().
enum Tier { POTATO, LOW, MEDIUM, HIGH, ULTRA }

const SETTINGS_PATH: String = "user://graphics.json"

# Default tier. HIGH == what World3D.tscn ships with → no first-run change.
const DEFAULT_TIER: int = Tier.HIGH

# Group set on the WorldEnvironment node in World3D.tscn. UnderwaterFilter
# resolves the same node the same way.
const WORLD_ENV_GROUP: String = "world_environment"

# The five presets, indexed by Tier value. Filled by _build_profiles().
var _profiles: Array[ShaderProfile] = []

# The currently-selected tier (a Tier value / index into _profiles).
var current_tier: int = DEFAULT_TIER


func _ready() -> void:
	_build_profiles()
	_load_tier()
	print("[GraphicsManager] Ready — tier = %s." % tier_name(current_tier))


# =============================================================
# PUBLIC API
# =============================================================

## Display name of a tier ("POTATO", "HIGH", ...).
func tier_name(tier: int) -> String:
	if _profiles.is_empty():
		return "HIGH"
	return _profiles[clampi(tier, 0, _profiles.size() - 1)].profile_name


## Change the active tier, persist it, and apply it to the live world.
func set_tier(tier: int) -> void:
	current_tier = clampi(tier, 0, _profiles.size() - 1)
	_save_tier()
	apply_current()
	print("[GraphicsManager] Tier set to %s." % tier_name(current_tier))


## Advance to the next tier, wrapping ULTRA → POTATO. The Settings
## button calls this — one click cycles one step (same UX as the
## Mining-Anchor button).
func cycle_tier() -> void:
	if _profiles.is_empty():
		return
	set_tier((current_tier + 1) % _profiles.size())


## Apply the current tier to whatever world scene is loaded right now.
## Safe to call when there is no world / no WorldEnvironment (menu
## scenes, headless) — those branches simply no-op.
func apply_current() -> void:
	if _profiles.is_empty():
		return
	var profile: ShaderProfile = _profiles[clampi(current_tier, 0, _profiles.size() - 1)]
	_apply_viewport(profile)
	_apply_environment(profile)
	_apply_lights(profile)
	print("[GraphicsManager] Applied %s profile." % profile.profile_name)


# =============================================================
# APPLY STEPS  (each null-guards so menu / headless scenes are safe)
# =============================================================

func _apply_viewport(profile: ShaderProfile) -> void:
	# MSAA + TAA live on the root Viewport, not on the Environment.
	var vp := get_viewport()
	if vp == null:
		return
	vp.msaa_3d = profile.msaa_3d
	vp.use_taa = profile.taa_enabled


func _apply_environment(profile: ShaderProfile) -> void:
	# The WorldEnvironment node carries the Environment resource that
	# holds the SSAO / SSIL / SDFGI / glow / volumetric-fog switches.
	var we := get_tree().get_first_node_in_group(WORLD_ENV_GROUP)
	if we == null or not (we is WorldEnvironment):
		return  # menu scene / headless — no world environment to drive
	var env: Environment = (we as WorldEnvironment).environment
	if env == null:
		return
	env.ssao_enabled = profile.ssao_enabled
	env.ssil_enabled = profile.ssil_enabled
	env.sdfgi_enabled = profile.sdfgi_enabled
	env.glow_enabled = profile.glow_enabled
	env.volumetric_fog_enabled = profile.volumetric_fog_enabled


func _apply_lights(profile: ShaderProfile) -> void:
	# Sun + Moon are DirectionalLight3D nodes. We walk the loaded scene
	# for every DirectionalLight3D so this catches both without relying
	# on node names. (The Sun is in the "sun_light" group, but the Moon
	# is not — a tree walk is the simplest catch-all.)
	var scene := get_tree().current_scene
	if scene == null:
		return
	for light in _find_directional_lights(scene):
		light.shadow_enabled = profile.shadows_enabled
		light.directional_shadow_mode = profile.shadow_mode


func _find_directional_lights(node: Node) -> Array[DirectionalLight3D]:
	var found: Array[DirectionalLight3D] = []
	if node is DirectionalLight3D:
		found.append(node as DirectionalLight3D)
	for child in node.get_children():
		found.append_array(_find_directional_lights(child))
	return found


# =============================================================
# PROFILE DEFINITIONS  (edit these longhand assignments to retune)
# =============================================================

func _build_profiles() -> void:
	_profiles.clear()
	_profiles.resize(Tier.size())

	# POTATO — everything expensive OFF, for the weakest hardware.
	# Loses: anti-aliasing, ambient occlusion, glow, shadows, god rays.
	var potato := ShaderProfile.new()
	potato.profile_name = "POTATO"
	potato.msaa_3d = 0
	potato.taa_enabled = false
	potato.ssao_enabled = false
	potato.ssil_enabled = false
	potato.sdfgi_enabled = false
	potato.glow_enabled = false
	potato.shadows_enabled = false
	potato.shadow_mode = 0
	potato.volumetric_fog_enabled = false
	_profiles[Tier.POTATO] = potato

	# LOW — shadows + glow back on; still no AA / AO / god rays.
	var low := ShaderProfile.new()
	low.profile_name = "LOW"
	low.msaa_3d = 0
	low.taa_enabled = false
	low.ssao_enabled = false
	low.ssil_enabled = false
	low.sdfgi_enabled = false
	low.glow_enabled = true
	low.shadows_enabled = true
	low.shadow_mode = 1
	low.volumetric_fog_enabled = false
	_profiles[Tier.LOW] = low

	# MEDIUM — anti-aliasing + SSAO + volumetric fog on; SSIL still off.
	var medium := ShaderProfile.new()
	medium.profile_name = "MEDIUM"
	medium.msaa_3d = 1
	medium.taa_enabled = true
	medium.ssao_enabled = true
	medium.ssil_enabled = false
	medium.sdfgi_enabled = false
	medium.glow_enabled = true
	medium.shadows_enabled = true
	medium.shadow_mode = 2
	medium.volumetric_fog_enabled = true
	_profiles[Tier.MEDIUM] = medium

	# HIGH — the default. Mirrors World3D.tscn exactly: MSAA 4x, SSAO,
	# SSIL, PSSM 4-split shadows, glow, volumetric fog. SDFGI off.
	var high := ShaderProfile.new()
	high.profile_name = "HIGH"
	high.msaa_3d = 2
	high.taa_enabled = true
	high.ssao_enabled = true
	high.ssil_enabled = true
	high.sdfgi_enabled = false
	high.glow_enabled = true
	high.shadows_enabled = true
	high.shadow_mode = 2
	high.volumetric_fog_enabled = true
	_profiles[Tier.HIGH] = high

	# ULTRA — HIGH plus 8x MSAA and SDFGI (full global illumination).
	# SDFGI is low-value on our heightmap terrain (no overhangs to
	# bounce light through), so it is intentionally ULTRA-only.
	var ultra := ShaderProfile.new()
	ultra.profile_name = "ULTRA"
	ultra.msaa_3d = 3
	ultra.taa_enabled = true
	ultra.ssao_enabled = true
	ultra.ssil_enabled = true
	ultra.sdfgi_enabled = true
	ultra.glow_enabled = true
	ultra.shadows_enabled = true
	ultra.shadow_mode = 2
	ultra.volumetric_fog_enabled = true
	_profiles[Tier.ULTRA] = ultra


# =============================================================
# PERSIST  (own file — does not touch Settings' user://settings.json)
# =============================================================

func _save_tier() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GraphicsManager] Could not write %s." % SETTINGS_PATH)
		return
	f.store_string(JSON.stringify({"quality_tier": current_tier}, "\t"))
	f.close()


func _load_tier() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		current_tier = DEFAULT_TIER
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		current_tier = DEFAULT_TIER
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		current_tier = clampi(
			int((parsed as Dictionary).get("quality_tier", DEFAULT_TIER)),
			0, _profiles.size() - 1)
	else:
		current_tier = DEFAULT_TIER
