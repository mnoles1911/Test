class_name WeatherEnvelopeProfile
extends Resource
# WeatherEnvelopeProfile — how an ambient audio bed fades in / out.
#
# Replaces the linear-dB Tween.tween_property(volume_db, ...) from PR #244
# which the designer reported as "still feels like a hard switch" + audio
# onset lagging visual onset by ~5 s.
#
# Knobs (all per-direction; same profile is symmetric for fade-in / fade-out
# unless `out_*` overrides are set):
#   lead_seconds       — delay before the ramp starts. 0.0 by default to
#                        match visual onset. (was implicitly 5 s with the
#                        old AMBIENT_CROSSFADE_S floor.)
#   fade_seconds       — length of the actual ramp.
#   curve_pow          — exponent applied to amplitude t before convert
#                        back to dB. 1.0 = linear-dB (the old behaviour
#                        that read as on/off). 2.0+ = perceptually-linear
#                        loudness ramp that feels like a build-up.
#   lowpass_hz_low     — filter cutoff at t=0 of the ramp. Lower = more
#                        muffled at the start.
#   lowpass_hz_high    — filter cutoff at t=1 (steady state).
#                        Setting both to >=22050 disables the filter sweep.
#
# Out-direction overrides (used when the bed is fading out):
#   out_*              — if any > 0.0, the fade-out uses these instead.
#
# Reference: design/WEATHER_REWORK_2026-05.md → Phase C

# --- Fade IN (state arriving) ----------------------------------------------
@export var lead_seconds: float = 0.0
@export var fade_seconds: float = 6.0
@export var curve_pow: float = 2.2
@export var lowpass_hz_low: float = 800.0
@export var lowpass_hz_high: float = 22050.0

# --- Fade OUT (state leaving) — only used if > 0.0; else mirrors fade-in ---
@export var out_lead_seconds: float = -1.0
@export var out_fade_seconds: float = -1.0
@export var out_curve_pow: float = -1.0
@export var out_lowpass_hz_low: float = -1.0
@export var out_lowpass_hz_high: float = -1.0


# Resolved per-direction value getters — the WeatherManager driver calls
# these so it doesn't have to know which fields override what.
func get_lead_seconds(fading_out: bool) -> float:
	if fading_out and out_lead_seconds >= 0.0:
		return out_lead_seconds
	return lead_seconds


func get_fade_seconds(fading_out: bool) -> float:
	if fading_out and out_fade_seconds >= 0.0:
		return out_fade_seconds
	return fade_seconds


func get_curve_pow(fading_out: bool) -> float:
	if fading_out and out_curve_pow >= 0.0:
		return out_curve_pow
	return curve_pow


func get_lowpass_low(fading_out: bool) -> float:
	if fading_out and out_lowpass_hz_low >= 0.0:
		return out_lowpass_hz_low
	return lowpass_hz_low


func get_lowpass_high(fading_out: bool) -> float:
	if fading_out and out_lowpass_hz_high >= 0.0:
		return out_lowpass_hz_high
	return lowpass_hz_high


# Convert progress t in [0,1] into the corresponding volume_db relative to a
# target_db steady state. Uses an amplitude-domain pow curve so that t=0.5
# reads as "halfway loud" perceptually (rather than -40 dB which sounds
# inaudible). At t=0 returns -60 dB (effectively silent without the abrupt
# attack of -80); at t=1 returns target_db.
func resolve_db(t: float, target_db: float, fading_out: bool) -> float:
	var clamped: float = clampf(t, 0.0, 1.0)
	# Power curve on amplitude: amp = clamped ** pow. pow > 1 -> slow start.
	var amp: float = pow(clamped, get_curve_pow(fading_out))
	# Floor amplitude at 0.001 so linear_to_db doesn't return -inf.
	amp = maxf(amp, 0.001)
	# Convert to dB delta: 20 * log10(amp) — equivalent to linear_to_db.
	var delta_db: float = 20.0 * log(amp) / log(10.0)
	# delta_db is in [-60, 0]; ramp from -60 below target up to target.
	return target_db + delta_db


# Convert progress t in [0,1] into the low-pass cutoff Hz. Sweeps from
# low (muffled, "approaching") to high (open, "arrived").
func resolve_lowpass_hz(t: float, fading_out: bool) -> float:
	var clamped: float = clampf(t, 0.0, 1.0)
	var lo: float = get_lowpass_low(fading_out)
	var hi: float = get_lowpass_high(fading_out)
	return lerpf(lo, hi, clamped)
