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

# Per-effect toggles (Phase K bundle, 2026-05-27). Each defaults to ON;
# designer can disable any individually via the DebugOverlay GRAPHICS
# sub-view. Persisted alongside the tier in user://graphics.json so
# choices survive runs. Master_post_processing is the "all off" switch
# the designer asked for — flipping it false short-circuits every
# per-effect check (effects act as if their own toggle is false).
#
# Effects honoured (in commit order):
#   selection_outline — EditToolHandler hides _aim_outline when false
#   lens_flare        — LensFlare CanvasLayer.visible = false
#   light_shafts      — WeatherManager skips the per-state god_ray
#                        multiplier push; sun's volumetric fog energy
#                        stays at its baseline (Underwater filter's
#                        on-submerge ramp is independent and unaffected)
#   rainbow           — sky_atmosphere shader rainbow_factor pinned to 0
#
# General rule for new effects: add a flag here, add an `is_effect_enabled`
# getter (combined with master), wire the consumer to call it, surface
# in DebugOverlay GRAPHICS sub-view.
@export var master_post_processing_enabled: bool = true
@export var selection_outline_enabled: bool = true
@export var lens_flare_enabled: bool = true
# Weather rework 2026-05-27 designer playtest verdict: god rays still
# imperceptible even with the per-state WorldEnvironment.volumetric_fog
# co-tune. Deferred for multi-session iteration. Default OFF so the new
# env vol_fog writes don't take effect; scene baseline is preserved.
@export var light_shafts_enabled: bool = false
@export var rainbow_enabled: bool = true
# Weather rework 2026-05 (Phase A) — keep the GPUParticles3D rain rig as
# a fallback so the v1 visual can be A/B'd against the new screen-space
# shader. Defaults OFF — the new shader is the shipping path.
@export var rain_3d_fallback_enabled: bool = false
# Weather rework 2026-05-27 designer playtest verdict: "rain visuals
# look really bad. just turn off all the rain visuals." Master gate
# for the new screen-space rain shader + splash particles + wet-surface
# terrain modulation. Defaults OFF; the entire visual stack is dormant
# until a future iteration session enables it. Audio crossfade rework
# stays live — it's an objective improvement over the linear-dB tween.
@export var rain_visuals_enabled: bool = false
# Water-polish PR 3 (2026-06-10) — lakebed caustics in
# terrain_voxel.gdshader, driven by the water_caustics_strength shader
# global. Default OFF per the default-OFF precedent for new visual
# layers: the designer flips it in the DebugOverlay GRAPHICS view,
# eyeballs a shallow pond at noon, then decides.
@export var caustics_enabled: bool = false
# D4 (10cm micro-detail pass, 2026-06-12) — flowing-water foam: a single
# pooled particle node that WaterFlowManager repositions across the active
# MOVING flow sites near the player. Default OFF per the same default-OFF
# precedent for new visual layers (rain / light_shafts / caustics): the
# designer flips it on his GPU in the DebugOverlay GRAPHICS view, eyeballs a
# river at noon, then decides. WaterFlowManager checks this BEFORE doing any
# foam work, so it costs nothing headless or while off.
@export var water_foam_enabled: bool = false
# Far-grass impostor layer (FarGrassManager, 2026-06-12). GPU-instanced,
# non-interactive grass that fills the LOD1/LOD2 rings (~13..51 m) so the
# REAL LOD0 voxel grass no longer ends in a visible "bald ring" at the
# ~12.8 m LOD0 boundary.
#
# DEFAULT ON — deliberately breaking the repo's "new visual layers default
# OFF" rule (rain_visuals / light_shafts / caustics / water_foam all default
# OFF). The rationale: those layers are NEW effects whose look is unproven.
# This layer is different — it FIXES a seam in an ALREADY-SHIPPED, default-ON
# feature (R4 destructible grass). Shipping it OFF would mean the bald ring
# stays visible by default, i.e. the bug it fixes is the default state. The
# designer explicitly approved this layer ON. Flipping it OFF is instant
# (FarGrassManager frees + stops rebuilding its chunks) — useful for A/B'ing
# the seam fix, which is exactly why the toggle exists.
@export var far_grass_enabled: bool = true

# Signal fired whenever any effect toggle changes so subscribers can
# react without polling. DebugOverlay flips → GraphicsManager emits →
# WeatherManager / EditToolHandler / LensFlare etc. apply the change
# on the next frame.
signal effect_toggles_changed()


func _ready() -> void:
	_build_profiles()
	_load_tier()
	print("[GraphicsManager] Ready — tier = %s." % tier_name(current_tier))


# =============================================================
# EFFECT TOGGLE PUBLIC API  (Phase K bundle, 2026-05-27)
# =============================================================

## True if `effect` should currently render. Folds in the master switch
## so callers don't have to AND-with master themselves. `effect` is the
## name of one of the @export bools above (without the `_enabled` suffix).
func _apply_caustics_global() -> void:
	# Push the toggle into the water_caustics_strength shader global.
	# Runtime _set ONLY — the global is DECLARED in project.godot
	# [shader_globals] (never call global_shader_parameter_add/_get,
	# they're editor-only; see PATTERNS_AND_GOTCHAS).
	RenderingServer.global_shader_parameter_set(
		"water_caustics_strength",
		0.6 if (caustics_enabled and master_post_processing_enabled) else 0.0)


func is_effect_enabled(effect_name: String) -> bool:
	# rain_3d_fallback is independent of master_post_processing — it is a
	# debug A/B switch, not an FX layer. Check it before the master gate.
	if effect_name == "rain_3d_fallback":
		return rain_3d_fallback_enabled
	# far_grass is a GEOMETRY layer (the impostor lawn that continues the
	# real voxel grass), NOT a post-process FX — the "all post FX off"
	# master switch must not blank the lawn. Check it before the master gate.
	if effect_name == "far_grass":
		return far_grass_enabled
	if not master_post_processing_enabled:
		return false
	match effect_name:
		"selection_outline":
			return selection_outline_enabled
		"lens_flare":
			return lens_flare_enabled
		"light_shafts":
			return light_shafts_enabled
		"rainbow":
			return rainbow_enabled
		"rain_visuals":
			return rain_visuals_enabled
		"caustics":
			return caustics_enabled
		"water_foam":
			return water_foam_enabled
		# NOTE: "far_grass" is handled ABOVE the master gate (it's a geometry
		# layer, not a post-FX) — see the early-return at the top.
		_:
			push_warning("[GraphicsManager] is_effect_enabled: unknown effect '%s'." % effect_name)
			return false


## Flip one effect toggle. Persists + emits effect_toggles_changed.
func set_effect_enabled(effect_name: String, enabled: bool) -> void:
	match effect_name:
		"master_post_processing":
			master_post_processing_enabled = enabled
		"selection_outline":
			selection_outline_enabled = enabled
		"lens_flare":
			lens_flare_enabled = enabled
		"light_shafts":
			light_shafts_enabled = enabled
		"rainbow":
			rainbow_enabled = enabled
		"rain_3d_fallback":
			rain_3d_fallback_enabled = enabled
		"rain_visuals":
			rain_visuals_enabled = enabled
		"caustics":
			caustics_enabled = enabled
			_apply_caustics_global()
		"water_foam":
			water_foam_enabled = enabled
		"far_grass":
			far_grass_enabled = enabled
		_:
			push_warning("[GraphicsManager] set_effect_enabled: unknown effect '%s'." % effect_name)
			return
	_save_tier()
	effect_toggles_changed.emit()
	print("[GraphicsManager] %s -> %s." % [effect_name, str(enabled)])


## Reset every per-effect toggle (master included) to ON.
func reset_all_effects_enabled() -> void:
	master_post_processing_enabled = true
	selection_outline_enabled = true
	lens_flare_enabled = true
	# light_shafts + rain_visuals intentionally NOT reset to ON — both
	# default OFF per the 2026-05-27 designer playtest. RESET ALL TO ON
	# would surprise the designer by re-enabling visuals they explicitly
	# turned off as needing multi-session iteration.
	# light_shafts_enabled stays at current value
	# rain_visuals_enabled stays at current value
	# caustics_enabled / water_foam_enabled stay at current value (both
	# default OFF per the new-visual-layer rule — same reasoning as above)
	rainbow_enabled = true
	# far_grass_enabled IS reset to ON — unlike the other new layers it
	# defaults ON (it fixes the bald-ring seam in the shipped grass), so
	# "reset all to ON" correctly restores the seam fix.
	far_grass_enabled = true
	# rain_3d_fallback intentionally NOT reset — debug A/B switch.
	_save_tier()
	effect_toggles_changed.emit()
	print("[GraphicsManager] Reset selection_outline / lens_flare / rainbow / master to ENABLED (light_shafts + rain_visuals + rain_3d_fallback preserved).")


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
	# Renamed conceptually to _save_state — also persists the per-effect
	# toggles added 2026-05-27. Backwards-compatible: missing fields read
	# as their defaults (all true), so an existing user://graphics.json
	# from before the toggles existed loads cleanly.
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GraphicsManager] Could not write %s." % SETTINGS_PATH)
		return
	f.store_string(JSON.stringify({
		"quality_tier": current_tier,
		"master_post_processing_enabled": master_post_processing_enabled,
		"selection_outline_enabled": selection_outline_enabled,
		"lens_flare_enabled": lens_flare_enabled,
		"light_shafts_enabled": light_shafts_enabled,
		"caustics_enabled": caustics_enabled,
		"rainbow_enabled": rainbow_enabled,
		"rain_3d_fallback_enabled": rain_3d_fallback_enabled,
		"rain_visuals_enabled": rain_visuals_enabled,
		"water_foam_enabled": water_foam_enabled,
		"far_grass_enabled": far_grass_enabled,
	}, "\t"))
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
		var d: Dictionary = parsed as Dictionary
		current_tier = clampi(
			int(d.get("quality_tier", DEFAULT_TIER)),
			0, _profiles.size() - 1)
		master_post_processing_enabled = bool(d.get("master_post_processing_enabled", true))
		selection_outline_enabled = bool(d.get("selection_outline_enabled", true))
		lens_flare_enabled = bool(d.get("lens_flare_enabled", true))
		# Defaults for light_shafts + rain_visuals changed to false 2026-05-27
		# (designer-deferred). Missing key in older user://graphics.json
		# reads as the new default.
		light_shafts_enabled = bool(d.get("light_shafts_enabled", false))
		caustics_enabled = bool(d.get("caustics_enabled", false))
		_apply_caustics_global()
		rainbow_enabled = bool(d.get("rainbow_enabled", true))
		rain_3d_fallback_enabled = bool(d.get("rain_3d_fallback_enabled", false))
		rain_visuals_enabled = bool(d.get("rain_visuals_enabled", false))
		# D4 water foam — default OFF (new visual layer); designer flips it.
		water_foam_enabled = bool(d.get("water_foam_enabled", false))
		# Far grass — default ON (fixes the bald-ring seam in shipped grass).
		# Missing key in an older user://graphics.json reads as ON, so the
		# seam fix is on by default for existing players too.
		far_grass_enabled = bool(d.get("far_grass_enabled", true))
	else:
		current_tier = DEFAULT_TIER
