// MiraDayNightCycle.h — a self-contained, designer-tunable real-time DAY/NIGHT CYCLE actor.
// ============================================================================================
//
// WHAT THIS IS (plain English)
// ----------------------------
// Drop ONE of these actors into your level and it animates the sky for you: it rotates the
// sun across the sky, warms its color at dawn/dusk, cools and dims it at night, adds a soft
// blue "moonlight" while the sun is down, drifts the fog color, and keeps the Lumen sky
// lighting (the SkyLight) in sync so the whole world's bounced light follows the time of day.
//
// The look is SKYRIM-flavoured: grounded and realistic. Warm low sun at sunrise/sunset,
// neutral-cool bright midday, and a dark-but-still-readable night with cool blue moonlight.
//
// THE 40 / 20 ASYMMETRIC CLOCK
// ----------------------------
// The designer asked for an ACCELERATED real-time clock where the in-game "day" is longer
// than the "night":
//      * 40 real minutes (2400 s) with the SUN ABOVE the horizon  = daytime
//      * 20 real minutes (1200 s) with the SUN BELOW the horizon  = nighttime
//      * total loop = 60 real minutes, then it repeats.
//
// We express the whole loop as a single number, PhaseOfDay, that runs 0.0 -> 1.0 and wraps:
//      PhaseOfDay 0.00 = sunrise (sun exactly on the eastern horizon, start of DAY)
//      PhaseOfDay 0.??  = the DAY segment (sun arcs up to noon and back down)
//      PhaseOfDay X     = sunset (sun reaches the western horizon, DAY ends / NIGHT begins)
//      PhaseOfDay X..1  = the NIGHT segment (sun is below the horizon)
//      PhaseOfDay 1.00  = wraps back to 0.0 (next sunrise)
// Because day and night have DIFFERENT real-world lengths, the split point X is NOT 0.5 —
// it's DayLengthSeconds / (DayLengthSeconds + NightLengthSeconds) = 2400/3600 = 0.6667.
// See MiraDayNightCycle.cpp -> AdvancePhase() and ComputeSunElevationAzimuth() for the math,
// which is commented step-by-step.
//
// SAFE BY DEFAULT
// ---------------
// If the designer hasn't wired up the light/sky references in the Details panel, this actor
// AUTO-FINDS them in the level (the first DirectionalLight, the SkyLight, the SkyAtmosphere,
// the ExponentialHeightFog). If it can't find something, it simply skips driving that thing —
// it NEVER crashes an empty level. So you can literally drop it in and press play.
//
// ACTOR vs SUBSYSTEM (why this is an Actor)
// -----------------------------------------
// We chose a placeable AActor (not a UWorldSubsystem) on purpose:
//   * The designer needs to SEE it in the World Outliner, SELECT it, and TUNE its curves and
//     UPROPERTYs live in the Details panel — actors give that for free; subsystems don't.
//   * It is fundamentally a per-LEVEL, designer-authored thing (which curves? which lights?),
//     and different levels may want different settings. That's an actor's job.
//   * Its work is "drive references that live in this level," so co-locating it in the level
//     with soft references to those siblings is the natural, discoverable fit.
// A subsystem would be the right call if this were a hidden, always-on, code-only service with
// no per-level authoring — that's not what the designer asked for.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MiraDayNightCycle.generated.h"

// Forward declarations keep this header light — the real types are included in the .cpp.
class ADirectionalLight;
class USkyLightComponent;
class USkyAtmosphereComponent;
class UExponentialHeightFogComponent;
class UCurveFloat;
class UCurveLinearColor;

UCLASS(Blueprintable, hidecategories = (Input, Replication, Collision, LOD, Cooking))
class MIRATHALCORE_API AMiraDayNightCycle : public AActor
{
	GENERATED_BODY()

public:
	AMiraDayNightCycle();

	// ========================================================================================
	// CLOCK KNOBS — how fast time flows and where it starts.
	// ========================================================================================

	// How many REAL seconds the daytime (sun above horizon) lasts. Default 2400 = 40 minutes.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Clock",
		meta = (ClampMin = "1.0", UIMin = "60.0", UIMax = "7200.0", Units = "s"))
	float DayLengthSeconds = 2400.f;

	// How many REAL seconds the nighttime (sun below horizon) lasts. Default 1200 = 20 minutes.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Clock",
		meta = (ClampMin = "1.0", UIMin = "30.0", UIMax = "7200.0", Units = "s"))
	float NightLengthSeconds = 1200.f;

	// Where the clock STARTS when the level begins, as a 0..1 fraction of the full loop.
	// 0.0 = sunrise, ~0.33 = midday, 0.6667 = sunset, ~0.83 = midnight. Default 0.15 = morning.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Clock",
		meta = (ClampMin = "0.0", ClampMax = "1.0", UIMin = "0.0", UIMax = "1.0"))
	float StartTimeOfDay = 0.15f;

	// Master speed multiplier. 1.0 = real cadence (40 min day / 20 min night). 2.0 = twice as
	// fast, 0.5 = half speed. Handy for testing a full cycle quickly. Set 0 to freeze, or use
	// bPaused below.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Clock",
		meta = (ClampMin = "0.0", UIMin = "0.0", UIMax = "100.0"))
	float TimeScale = 1.f;

	// Tick this to FREEZE the cycle at the current time of day (good for screenshots / cinematics).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Clock")
	bool bPaused = false;

	// ========================================================================================
	// SUN ARC GEOMETRY — the shape of the sun's path across the sky.
	// ========================================================================================

	// Compass direction (yaw, degrees) the sun travels along. 0 = sun moves along the world +X
	// axis. Rotate this to line the sunrise/sunset up with your landscape. Pure art choice.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|SunArc",
		meta = (ClampMin = "0.0", ClampMax = "360.0", Units = "deg"))
	float SunPathYaw = 100.f;

	// How HIGH the sun climbs at noon, in degrees above the horizon (its peak elevation).
	// 90 = straight overhead (tropical). ~60 is a pleasant, Skyrim-ish "northern" sun that
	// stays a bit low and keeps shadows long and dramatic. Default 62.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|SunArc",
		meta = (ClampMin = "5.0", ClampMax = "90.0", Units = "deg"))
	float MaxSunElevationDeg = 62.f;

	// How far BELOW the horizon the sun dips at the dead of night, in degrees. Bigger = darker
	// "true night" between dusk and dawn. Default 35.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|SunArc",
		meta = (ClampMin = "1.0", ClampMax = "90.0", Units = "deg"))
	float MinSunElevationDeg = 35.f;

	// ========================================================================================
	// LOOK CURVES — the tunable "art" of the cycle. ALL optional: sensible code-driven
	// fallbacks kick in for any curve left empty, so the actor looks good with zero setup.
	// Every curve's X axis is the SUN ELEVATION in degrees (-90 at midnight .. +90 at zenith),
	// EXCEPT the sky-strength curves which are also keyed on elevation. Author them in the
	// Curve Editor; the comments say what each one means.
	// ========================================================================================

	// SUN BRIGHTNESS vs elevation (lux). X = sun elevation deg, Y = directional light intensity.
	// Suggested keys: -10deg -> 0 (sun set, off), 0deg -> ~2 (faint), 15deg -> ~6 (golden),
	// 60deg -> ~10 (full midday). If empty, a built-in curve does roughly this.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveFloat> SunIntensityCurve = nullptr;

	// SUN COLOR TEMPERATURE vs elevation (Kelvin). X = elevation deg, Y = Kelvin.
	// Suggested: 0deg -> ~2000K (deep warm orange), 10deg -> ~3500K (golden), 60deg -> ~6500K
	// (neutral daylight). Lower K = warmer/redder. If empty, a built-in warm->neutral ramp runs.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveFloat> SunTemperatureCurve = nullptr;

	// Optional explicit SUN TINT vs elevation (overrides temperature if assigned). X = elevation
	// deg, RGBA = a LinearColor tint multiplied onto the sun. Leave empty to use temperature only.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveLinearColor> SunColorCurve = nullptr;

	// SKYLIGHT (ambient/GI) intensity vs sun elevation. X = elevation deg, Y = SkyLight intensity.
	// This is the soft fill that lifts shadows; drop it low (not zero) at night so the world
	// stays readable. If empty, a built-in day->night ramp runs.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveFloat> SkyLightIntensityCurve = nullptr;

	// FOG COLOR vs sun elevation. X = elevation deg, RGBA = fog inscattering LinearColor.
	// Suggested: warm grey-orange near the horizon, neutral blue-grey at noon, deep blue at night.
	// If empty, a built-in gradient runs.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveLinearColor> FogColorCurve = nullptr;

	// FOG DENSITY vs sun elevation. X = elevation deg, Y = exponential height fog density.
	// Thicker dawn/dusk haze reads as "atmospheric." If empty, a gentle built-in ramp runs.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Look")
	TObjectPtr<UCurveFloat> FogDensityCurve = nullptr;

	// ========================================================================================
	// MOON KNOBS — a cool blue fill so night isn't pitch black. The moon is OPTIONAL: if you
	// don't assign a MoonLight, we still raise the SkyLight floor so night stays readable.
	// ========================================================================================

	// Peak brightness of the moon directional light at the dead of night (lux). Small on purpose.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Moon",
		meta = (ClampMin = "0.0", UIMin = "0.0", UIMax = "3.0"))
	float MoonPeakIntensity = 0.35f;

	// Color of the moonlight. Cool blue by default — the classic "readable night" look.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Moon")
	FLinearColor MoonColor = FLinearColor(0.55f, 0.68f, 1.0f, 1.0f);

	// If true, the moon rides OPPOSITE the sun (rises as the sun sets). Standard, believable.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Moon")
	bool bMoonOppositeSun = true;

	// ========================================================================================
	// PERFORMANCE — SkyLight recapture cadence.
	// ========================================================================================
	//
	// The SkyLight bakes the sky into the ambient/GI used by Lumen. To make GI follow a moving
	// sun we must REFRESH that capture. Two ways:
	//   (A) RealTimeCapture mode  — the engine refreshes the sky capture every frame on the GPU.
	//       Cleanest result, but it has a per-frame GPU cost.
	//   (B) Periodic RecaptureSky() — we manually re-capture every N seconds. Cheaper on average,
	//       but the ambient light updates in steps, so very fast cycles can look "steppy."
	// Default is RealTimeCapture ON (it's the modern UE path and our cycle is slow enough that
	// the cost is fine). Turn it off and rely on the timer if you're GPU-bound.

	// Use the engine's RealTimeCapture on the SkyLight (recommended). If false, we fall back to
	// periodic manual recapture using SkyLightRecaptureInterval below.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Performance")
	bool bUseRealTimeSkyCapture = true;

	// When RealTimeCapture is OFF, how often (real seconds) to manually RecaptureSky(). Bigger =
	// cheaper but steppier ambient. Ignored when bUseRealTimeSkyCapture is true.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|Performance",
		meta = (ClampMin = "0.1", UIMin = "0.5", UIMax = "30.0", Units = "s",
			EditCondition = "!bUseRealTimeSkyCapture"))
	float SkyLightRecaptureInterval = 2.0f;

	// ========================================================================================
	// REFERENCES — leave EMPTY to auto-find, or assign explicitly for full control.
	// These are soft, designer-assignable pointers to the sibling sky actors in the level.
	// ========================================================================================

	// The SUN. Its DirectionalLightComponent is rotated/colored/dimmed across the day, and is
	// set as the atmosphere's sun light so the SkyAtmosphere draws the sun disc correctly.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|References")
	TObjectPtr<ADirectionalLight> SunLight = nullptr;

	// OPTIONAL second DirectionalLight used as the MOON. Leave empty to skip a moon disc and
	// just lean on the SkyLight floor at night.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|References")
	TObjectPtr<ADirectionalLight> MoonLight = nullptr;

	// The actor that owns the SkyLight component (usually a SkyLight actor). Auto-found if empty.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|References")
	TObjectPtr<AActor> SkyLightActor = nullptr;

	// The actor that owns the SkyAtmosphere component. Auto-found if empty. We mainly use it to
	// confirm the sun is registered as its light; the atmosphere reads the sun's rotation itself.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|References")
	TObjectPtr<AActor> SkyAtmosphereActor = nullptr;

	// The actor that owns the ExponentialHeightFog component. Auto-found if empty.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|DayNight|References")
	TObjectPtr<AActor> ExponentialHeightFogActor = nullptr;

	// ========================================================================================
	// LIVE READOUTS — handy info, shown read-only in the Details panel.
	// ========================================================================================

	// Current position in the loop, 0..1. 0 = sunrise, 0.6667 = sunset, wraps at 1.
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "MiraThal|DayNight|Readout")
	float PhaseOfDay = 0.f;

	// Current sun elevation in degrees (+ above horizon, - below). Negative = it's night.
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "MiraThal|DayNight|Readout")
	float CurrentSunElevationDeg = 0.f;

	// True while the sun is below the horizon (i.e. during the 20-minute night segment).
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "MiraThal|DayNight|Readout")
	bool bIsNight = false;

	// ----------------------------------------------------------------------------------------
	// Blueprint helpers so the designer can read/jump the clock from BP without touching C++.
	// ----------------------------------------------------------------------------------------

	// Jump the clock to a specific point in the loop (0..1) and refresh the sky immediately.
	UFUNCTION(BlueprintCallable, Category = "MiraThal|DayNight")
	void SetTimeOfDay(float NewPhase01);

	// Read the clock as a friendly 24-hour value (0..24), where 0/24 = midnight, 12 = noon.
	UFUNCTION(BlueprintCallable, BlueprintPure, Category = "MiraThal|DayNight")
	float GetClockHours24() const;

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void OnConstruction(const FTransform& Transform) override;

private:
	// --- internal plumbing -----------------------------------------------------------------

	// Find any unassigned references by scanning the level. Safe to call repeatedly.
	void ResolveReferences();

	// One-time setup: register the sun as the atmosphere sun light, turn on RealTimeCapture, etc.
	void InitialiseSkyOnce();

	// Move PhaseOfDay forward by DeltaSeconds of real time (respecting TimeScale / bPaused).
	void AdvancePhase(float DeltaSeconds);

	// The heart of the system: turn PhaseOfDay into a sun elevation + azimuth (the 40/20 arc).
	void ComputeSunElevationAzimuth(float& OutElevationDeg, float& OutAzimuthDeg) const;

	// Push the current time of day onto every assigned reference (sun, moon, sky, fog).
	void ApplyLighting();

	// Built-in fallback evaluators (used when a curve UPROPERTY is left empty). All keyed on
	// sun elevation in degrees so they line up with the curve X axis.
	float       FallbackSunIntensity(float ElevDeg) const;
	float       FallbackSunTemperature(float ElevDeg) const;
	float       FallbackSkyLightIntensity(float ElevDeg) const;
	FLinearColor FallbackFogColor(float ElevDeg) const;
	float       FallbackFogDensity(float ElevDeg) const;

	// Cached component pointers we resolve from the reference actors (so we don't re-find each tick).
	UPROPERTY(Transient) TObjectPtr<USkyLightComponent> CachedSkyLight = nullptr;
	UPROPERTY(Transient) TObjectPtr<USkyAtmosphereComponent> CachedAtmosphere = nullptr;
	UPROPERTY(Transient) TObjectPtr<UExponentialHeightFogComponent> CachedFog = nullptr;

	// Timer for the periodic-recapture fallback path.
	float TimeSinceLastSkyRecapture = 0.f;

	// Guards so one-time init only runs once.
	bool bSkyInitialised = false;
};
