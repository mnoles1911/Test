extends Resource
# ShaderProfile — one graphics-quality tier's worth of rendering settings.
#
# NOTE: intentionally NO `class_name`. GraphicsManager.gd preloads this
# script by path instead. A brand-new `class_name` is invisible to the
# headless test harness until the editor rescans global classes — that
# would break GraphicsManager's parse headless. Same reasoning as
# scripts/WaterMaterial.gd (see CLAUDE.md). Do not add one.
#
# What this is, in plain English:
#   A "graphics preset". The game has five — POTATO, LOW, MEDIUM, HIGH,
#   ULTRA — and the player picks one in Settings. Each profile is just a
#   bag of on/off switches and numbers that GraphicsManager reads and
#   pushes into the live scene.
#
#   This file only DEFINES the shape of a profile. The five actual
#   profiles (with their values) are built in GraphicsManager.gd. We
#   keep ShaderProfile a Resource so a profile could later be saved as a
#   .tres file and tuned in the Inspector without touching code.
#
# Why these specific knobs:
#   They are exactly the renderer features the 2026-05-20 graphics pass
#   turned on (see design/GRAPHICS_PASS_2026-05-19.md). Turning them
#   DOWN is how a weaker PC keeps a smooth frame rate; the HIGH profile
#   reproduces what World3D.tscn ships with today, so the default
#   experience never changes.

# Human-readable tier name, shown on the Settings button ("HIGH", etc.).
@export var profile_name: String = "HIGH"

# --- Anti-aliasing -------------------------------------------------------
# Multi-sample anti-aliasing for the 3D view — smooths the jagged
# stair-step edges of voxel blocks against the sky. Godot Viewport.MSAA
# values: 0 = off, 1 = 2x, 2 = 4x, 3 = 8x. Higher = cleaner, costs GPU.
@export_enum("Disabled:0", "2x:1", "4x:2", "8x:3") var msaa_3d: int = 2

# Temporal anti-aliasing — removes shimmer in motion and denoises
# SSAO/SSIL. Cheap, but can look slightly soft. On for MEDIUM and up.
@export var taa_enabled: bool = true

# --- Lighting / ambient occlusion ---------------------------------------
# SSAO — soft contact shadows in the crevices between blocks. Adds depth.
@export var ssao_enabled: bool = true

# SSIL — screen-space indirect lighting: faint colour bleed from lit
# surfaces onto nearby ones. The pricier of the two; HIGH and up only.
@export var ssil_enabled: bool = true

# SDFGI — full real-time global illumination. Expensive, and low-value
# on our heightmap terrain (no caves/overhangs to bounce light through),
# so it is ULTRA-only — an opt-in for powerful GPUs.
@export var sdfgi_enabled: bool = false

# --- Glow / bloom --------------------------------------------------------
# Soft glow around bright pixels (sun, fire, emissive blocks).
@export var glow_enabled: bool = true

# --- Shadows -------------------------------------------------------------
# Master switch for directional (sun + moon) shadows. Off on POTATO —
# the single biggest frame-rate saving for a weak GPU.
@export var shadows_enabled: bool = true

# How the sun's shadow map is split across distance. Godot
# DirectionalLight3D.shadow_mode values: 0 = Orthogonal (1 split,
# cheapest), 1 = PSSM 2-split, 2 = PSSM 4-split (sharpest — what the
# graphics pass chose).
@export_enum("Orthogonal:0", "PSSM 2-split:1", "PSSM 4-split:2") var shadow_mode: int = 2

# --- Volumetric fog ------------------------------------------------------
# The 3D fog that produces the atmospheric haze and the underwater god
# rays. Off on the two lowest tiers (they lose underwater god rays — an
# acceptable trade for a weak machine).
@export var volumetric_fog_enabled: bool = true
