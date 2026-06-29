// MiraDayNightCycle.cpp — implementation of the real-time, accelerated day/night cycle.
// See MiraDayNightCycle.h for the big-picture overview and the designer knob descriptions.
// This file carries the math, the auto-find logic, and the per-tick lighting drive.

#include "Sky/MiraDayNightCycle.h"

// Lighting actors/components we drive. (Including in the .cpp, not the header, keeps compiles fast.)
#include "Engine/DirectionalLight.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/ExponentialHeightFogComponent.h"

// Curve assets (designer "art" inputs) + helpers to scan the level for sibling actors.
#include "Curves/CurveFloat.h"
#include "Curves/CurveLinearColor.h"
#include "EngineUtils.h"            // TActorIterator — used to auto-find lights/sky/fog.
#include "GameFramework/Actor.h"

// ============================================================================================
// Construction
// ============================================================================================
AMiraDayNightCycle::AMiraDayNightCycle()
{
	// We need to update every frame so the sun glides smoothly. The work per tick is tiny
	// (a handful of setters), so a normal Tick is perfectly fine.
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;

	// A trivial root so the actor has a transform/gizmo in the level. The day/night logic
	// does NOT depend on where this actor sits — it drives the sky no matter its position.
	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);

	// Run in the editor too (with the actor selected) so the designer can scrub StartTimeOfDay
	// and preview the look without hitting Play. (OnConstruction handles the preview snap.)
#if WITH_EDITORONLY_DATA
	// nothing extra needed here — OnConstruction drives the editor preview.
#endif
}

// ============================================================================================
// Editor preview — when the designer tweaks a property, snap the sky to StartTimeOfDay so the
// viewport shows roughly what they'll get. (At runtime, BeginPlay/Tick take over.)
// ============================================================================================
void AMiraDayNightCycle::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);

	// Only do the preview in the editor world, never while actually playing.
	if (GetWorld() && !GetWorld()->IsGameWorld())
	{
		ResolveReferences();
		InitialiseSkyOnce();
		PhaseOfDay = FMath::Frac(StartTimeOfDay); // keep it in 0..1
		ApplyLighting();
	}
}

// ============================================================================================
// BeginPlay — find references, do one-time sky setup, and snap to the start time.
// ============================================================================================
void AMiraDayNightCycle::BeginPlay()
{
	Super::BeginPlay();

	ResolveReferences();   // fill in any blank refs by scanning the level (safe / no-op if found)
	InitialiseSkyOnce();   // register sun as atmosphere light, enable RealTimeCapture, etc.

	PhaseOfDay = FMath::Frac(StartTimeOfDay); // start the clock where the designer asked
	ApplyLighting();                          // paint the very first frame correctly
}

// ============================================================================================
// Tick — advance the clock and repaint the sky.
// ============================================================================================
void AMiraDayNightCycle::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	AdvancePhase(DeltaSeconds); // move PhaseOfDay forward (honours TimeScale / bPaused)
	ApplyLighting();            // push sun/moon/sky/fog for the new time

	// Periodic SkyLight recapture fallback (only used when RealTimeCapture is OFF). We count up
	// real time and fire RecaptureSky() every SkyLightRecaptureInterval seconds. This keeps the
	// ambient/GI roughly in step with the sun without paying a per-frame GPU capture cost.
	if (!bUseRealTimeSkyCapture && CachedSkyLight)
	{
		TimeSinceLastSkyRecapture += DeltaSeconds;
		if (TimeSinceLastSkyRecapture >= SkyLightRecaptureInterval)
		{
			TimeSinceLastSkyRecapture = 0.f;
			CachedSkyLight->RecaptureSky();
		}
	}
}

// ============================================================================================
// AdvancePhase — turn elapsed real seconds into movement along the 0..1 loop.
// ============================================================================================
void AMiraDayNightCycle::AdvancePhase(float DeltaSeconds)
{
	if (bPaused || TimeScale <= 0.f)
	{
		return; // frozen — leave PhaseOfDay where it is.
	}

	// The full loop is day + night seconds. Guard against a designer typing 0 for both.
	const float LoopSeconds = FMath::Max(1.f, DayLengthSeconds + NightLengthSeconds);

	// Fraction of the WHOLE loop we covered this frame. TimeScale lets us fast-forward.
	const float PhaseDelta = (DeltaSeconds * TimeScale) / LoopSeconds;

	// Advance and wrap into 0..1. Frac() keeps the loop seamless.
	PhaseOfDay = FMath::Frac(PhaseOfDay + PhaseDelta);
}

// ============================================================================================
// ComputeSunElevationAzimuth — THE CORE MATH. Map PhaseOfDay (0..1) onto the sun's position.
// This is where the asymmetric 40-min-day / 20-min-night arc is built.
// ============================================================================================
void AMiraDayNightCycle::ComputeSunElevationAzimuth(float& OutElevationDeg, float& OutAzimuthDeg) const
{
	// STEP 1 — Where is the DAY/NIGHT boundary inside the 0..1 loop?
	// Day is 2400 s of a 3600 s loop, so the sun is UP for the first 0.6667 of the loop and
	// DOWN for the rest. We call that split "DayFraction."
	const float LoopSeconds = FMath::Max(1.f, DayLengthSeconds + NightLengthSeconds);
	const float DayFraction = FMath::Clamp(DayLengthSeconds / LoopSeconds, 0.01f, 0.99f);

	// STEP 2 — Convert PhaseOfDay into a "local progress" through whichever segment we're in.
	// We want a value 't' that runs 0..1 across the DAY segment, and a separate 0..1 across the
	// NIGHT segment, so we can drive a smooth half-sine arc within each.
	float SegmentT;        // 0..1 progress within the current segment
	bool  bDaySegment;     // true if the sun is above the horizon

	if (PhaseOfDay < DayFraction)
	{
		// We're in the DAY. Remap [0 .. DayFraction) -> [0 .. 1).
		bDaySegment = true;
		SegmentT = PhaseOfDay / DayFraction;
	}
	else
	{
		// We're in the NIGHT. Remap [DayFraction .. 1) -> [0 .. 1).
		bDaySegment = false;
		SegmentT = (PhaseOfDay - DayFraction) / (1.f - DayFraction);
	}

	// STEP 3 — Build the ELEVATION (height above/below horizon) as a smooth half-arc.
	// A half-sine that is 0 at the segment edges and 1 in the middle gives us:
	//    DAY:   0 at sunrise -> peak at noon -> 0 at sunset   (sun rides ABOVE horizon)
	//    NIGHT: 0 at sunset  -> trough at midnight -> 0 at sunrise (sun rides BELOW horizon)
	// sin(pi * t) is exactly that bump: 0 at t=0, 1 at t=0.5, 0 at t=1. Smooth start & end =
	// natural-looking sunrise/sunset with no kink at the horizon. Note the ASYMMETRY is FREE:
	// because the day segment spans more REAL time than the night segment, the day half-arc is
	// simply traversed slower — the sun lingers up high longer than it lingers down low, exactly
	// matching the 40/20 design with no special-casing.
	const float ArcShape = FMath::Sin(PI * SegmentT); // 0..1 bump across the segment

	if (bDaySegment)
	{
		// Above the horizon: 0 deg at the edges, up to MaxSunElevationDeg at noon.
		OutElevationDeg = ArcShape * MaxSunElevationDeg;
	}
	else
	{
		// Below the horizon: 0 deg at the edges (dusk/dawn), down to -MinSunElevationDeg at midnight.
		OutElevationDeg = -ArcShape * MinSunElevationDeg;
	}

	// STEP 4 — AZIMUTH (the compass sweep east->west). We let the sun travel a full 180 degrees
	// of compass heading across the DAY (sunrise on one side, sunset on the other), then continue
	// sweeping back across the NIGHT so it returns to the sunrise side by dawn. We track a single
	// 0..1 "AzimuthProgress" across the WHOLE loop and turn it into a 0..360 sweep, offset by the
	// designer's SunPathYaw so they can aim the whole arc at their landscape.
	const float AzimuthProgress = PhaseOfDay;                 // 0..1 across the entire loop
	OutAzimuthDeg = SunPathYaw + AzimuthProgress * 360.f;     // full revolution per loop
}

// ============================================================================================
// ApplyLighting — push the current time of day onto sun, moon, sky and fog.
// Everything here is null-checked: any missing reference is simply skipped (safe-by-default).
// ============================================================================================
void AMiraDayNightCycle::ApplyLighting()
{
	// Work out where the sun is right now.
	float ElevationDeg, AzimuthDeg;
	ComputeSunElevationAzimuth(ElevationDeg, AzimuthDeg);

	// Update the live readouts the designer sees in the Details panel.
	CurrentSunElevationDeg = ElevationDeg;
	bIsNight = (ElevationDeg < 0.f);

	// --- THE SUN -----------------------------------------------------------------------------
	if (SunLight)
	{
		if (UDirectionalLightComponent* SunComp = SunLight->GetComponent())
		{
			// ROTATION: a directional light shines along its forward (+X) axis. To make it sit at
			// a given elevation/azimuth, we rotate the actor so its pitch = -elevation (pitch is
			// nose-down-positive, and a high sun shines DOWNWARD) and its yaw = azimuth.
			const FRotator SunRot(-ElevationDeg, AzimuthDeg, 0.f);
			SunLight->SetActorRotation(SunRot);

			// INTENSITY: dim toward the horizon, off below it. Curve if provided, else fallback.
			const float SunIntensity = SunIntensityCurve
				? SunIntensityCurve->GetFloatValue(ElevationDeg)
				: FallbackSunIntensity(ElevationDeg);
			SunComp->SetIntensity(FMath::Max(0.f, SunIntensity));

			// COLOR: prefer an explicit color curve; otherwise drive the realistic color
			// TEMPERATURE (Kelvin) so the sun warms at dawn/dusk and neutralises at noon.
			if (SunColorCurve)
			{
				SunComp->SetUseTemperature(false);
				SunComp->SetLightColor(SunColorCurve->GetLinearColorValue(ElevationDeg));
			}
			else
			{
				const float Kelvin = SunTemperatureCurve
					? SunTemperatureCurve->GetFloatValue(ElevationDeg)
					: FallbackSunTemperature(ElevationDeg);
				SunComp->SetUseTemperature(true);
				SunComp->SetTemperature(FMath::Clamp(Kelvin, 1700.f, 12000.f));
				// Keep the base color white so the temperature does all the tinting.
				SunComp->SetLightColor(FLinearColor::White);
			}
		}
	}

	// --- THE MOON ----------------------------------------------------------------------------
	// The moon only contributes when the sun is DOWN. We fade it in as the sun sinks below the
	// horizon, and ride it opposite the sun (if bMoonOppositeSun) so it crosses the night sky.
	if (MoonLight)
	{
		if (UDirectionalLightComponent* MoonComp = MoonLight->GetComponent())
		{
			// Night strength 0..1: 0 while the sun is up, ramping to 1 as the sun sinks. We use
			// the first few degrees below the horizon as the fade band so dusk hands off smoothly.
			const float NightStrength = FMath::Clamp(-ElevationDeg / 12.f, 0.f, 1.f);

			MoonComp->SetIntensity(MoonPeakIntensity * NightStrength);
			MoonComp->SetUseTemperature(false);
			MoonComp->SetLightColor(MoonColor);

			// Aim the moon opposite the sun (or along the same azimuth if the designer prefers).
			// We give it a modest, steady elevation so it lights the scene without being overhead.
			const float MoonElevation = 35.f;                       // gentle, believable moon height
			const float MoonAzimuth = bMoonOppositeSun ? (AzimuthDeg + 180.f) : AzimuthDeg;
			MoonLight->SetActorRotation(FRotator(-MoonElevation, MoonAzimuth, 0.f));
		}
	}

	// --- THE SKYLIGHT (ambient / Lumen GI fill) ---------------------------------------------
	if (CachedSkyLight)
	{
		const float SkyIntensity = SkyLightIntensityCurve
			? SkyLightIntensityCurve->GetFloatValue(ElevationDeg)
			: FallbackSkyLightIntensity(ElevationDeg);
		CachedSkyLight->SetIntensity(FMath::Max(0.f, SkyIntensity));
	}

	// --- THE FOG -----------------------------------------------------------------------------
	if (CachedFog)
	{
		const FLinearColor FogColor = FogColorCurve
			? FogColorCurve->GetLinearColorValue(ElevationDeg)
			: FallbackFogColor(ElevationDeg);
		CachedFog->SetFogInscatteringColor(FogColor);

		const float FogDensity = FogDensityCurve
			? FogDensityCurve->GetFloatValue(ElevationDeg)
			: FallbackFogDensity(ElevationDeg);
		CachedFog->SetFogDensity(FMath::Max(0.f, FogDensity));
	}

	// --- THE ATMOSPHERE ----------------------------------------------------------------------
	// We don't need to push the sun direction into the SkyAtmosphere — it READS the sun light's
	// rotation itself every frame (because we registered the sun as its atmosphere sun light in
	// InitialiseSkyOnce). Rotating the sun above is enough to move the sky's sun disc, sky color,
	// and horizon glow. Nothing to do here, but kept as a marker for clarity.
}

// ============================================================================================
// ResolveReferences — fill any blank reference by scanning the level. Safe / idempotent.
// ============================================================================================
void AMiraDayNightCycle::ResolveReferences()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return;
	}

	// SUN: if the designer didn't assign one, grab the first DirectionalLight in the level.
	// (If there are two — sun and moon — the designer should assign explicitly; auto-find just
	// takes the first so an empty-handed drop-in still works.)
	if (!SunLight)
	{
		for (TActorIterator<ADirectionalLight> It(World); It; ++It)
		{
			SunLight = *It;
			break;
		}
	}

	// SKYLIGHT: find the actor that owns a USkyLightComponent and cache the component.
	if (!CachedSkyLight)
	{
		if (SkyLightActor)
		{
			CachedSkyLight = SkyLightActor->FindComponentByClass<USkyLightComponent>();
		}
		if (!CachedSkyLight)
		{
			for (TActorIterator<AActor> It(World); It; ++It)
			{
				if (USkyLightComponent* C = It->FindComponentByClass<USkyLightComponent>())
				{
					SkyLightActor = *It;
					CachedSkyLight = C;
					break;
				}
			}
		}
	}

	// SKYATMOSPHERE: find the actor that owns a USkyAtmosphereComponent.
	if (!CachedAtmosphere)
	{
		if (SkyAtmosphereActor)
		{
			CachedAtmosphere = SkyAtmosphereActor->FindComponentByClass<USkyAtmosphereComponent>();
		}
		if (!CachedAtmosphere)
		{
			for (TActorIterator<AActor> It(World); It; ++It)
			{
				if (USkyAtmosphereComponent* C = It->FindComponentByClass<USkyAtmosphereComponent>())
				{
					SkyAtmosphereActor = *It;
					CachedAtmosphere = C;
					break;
				}
			}
		}
	}

	// EXPONENTIAL HEIGHT FOG: find the actor that owns a UExponentialHeightFogComponent.
	if (!CachedFog)
	{
		if (ExponentialHeightFogActor)
		{
			CachedFog = ExponentialHeightFogActor->FindComponentByClass<UExponentialHeightFogComponent>();
		}
		if (!CachedFog)
		{
			for (TActorIterator<AActor> It(World); It; ++It)
			{
				if (UExponentialHeightFogComponent* C = It->FindComponentByClass<UExponentialHeightFogComponent>())
				{
					ExponentialHeightFogActor = *It;
					CachedFog = C;
					break;
				}
			}
		}
	}
}

// ============================================================================================
// InitialiseSkyOnce — one-time wiring so the atmosphere + GI follow our sun.
// ============================================================================================
void AMiraDayNightCycle::InitialiseSkyOnce()
{
	if (bSkyInitialised)
	{
		return;
	}

	// Register the SUN as the atmosphere's light #0. This is what makes the SkyAtmosphere draw
	// its sun disc and sky scattering using OUR sun's rotation. Without this, rotating the sun
	// would move shadows but the painted sky wouldn't follow.
	if (SunLight)
	{
		if (UDirectionalLightComponent* SunComp = SunLight->GetComponent())
		{
			SunComp->SetAtmosphereSunLight(true);   // "this directional light lights the atmosphere"
			SunComp->SetAtmosphereSunLightIndex(0);  // index 0 = the primary sun
			// Make sure the sun wins forward-shading ties (water/fog/translucency pick light #0).
			SunComp->SetForwardShadingPriority(10);
		}
	}

	// If there's a moon light, register it as atmosphere light #1 so (optionally) the sky can
	// respond to it too. Lower priority than the sun so the sun stays the dominant forward light.
	if (MoonLight)
	{
		if (UDirectionalLightComponent* MoonComp = MoonLight->GetComponent())
		{
			MoonComp->SetAtmosphereSunLight(true);
			MoonComp->SetAtmosphereSunLightIndex(1);
			MoonComp->SetForwardShadingPriority(0);
		}
	}

	// Turn on (or off) RealTimeCapture on the SkyLight so the ambient/GI follows the moving sky.
	// See the header's Performance section for the cost tradeoff. When OFF, Tick() periodically
	// calls RecaptureSky() instead.
	if (CachedSkyLight)
	{
		CachedSkyLight->SetRealTimeCaptureEnabled(bUseRealTimeSkyCapture);
		if (!bUseRealTimeSkyCapture)
		{
			CachedSkyLight->RecaptureSky(); // prime it once so the first frame isn't black.
		}
	}

	bSkyInitialised = true;
}

// ============================================================================================
// Blueprint helpers
// ============================================================================================
void AMiraDayNightCycle::SetTimeOfDay(float NewPhase01)
{
	PhaseOfDay = FMath::Frac(FMath::Max(0.f, NewPhase01));
	ApplyLighting();
}

float AMiraDayNightCycle::GetClockHours24() const
{
	// Map the loop onto a friendly 24-hour clock for UI: sunrise(phase 0) = 06:00, noon = 12:00,
	// sunset(phase=DayFraction) = 18:00, midnight = 00:00. We anchor on the day/night split so the
	// "hours of daylight" feel right even with the asymmetric arc.
	const float LoopSeconds = FMath::Max(1.f, DayLengthSeconds + NightLengthSeconds);
	const float DayFraction = FMath::Clamp(DayLengthSeconds / LoopSeconds, 0.01f, 0.99f);

	if (PhaseOfDay < DayFraction)
	{
		// Daytime maps onto 06:00 -> 18:00 (12 daylight hours on the clock face).
		return 6.f + (PhaseOfDay / DayFraction) * 12.f;
	}
	// Nighttime maps onto 18:00 -> 30:00(==06:00), wrapped to 0..24.
	const float NightT = (PhaseOfDay - DayFraction) / (1.f - DayFraction);
	return FMath::Fmod(18.f + NightT * 12.f, 24.f);
}

// ============================================================================================
// FALLBACK LOOK — built-in "art" used when a curve UPROPERTY is left empty. These give a
// grounded, Skyrim-ish result out of the box. All are keyed on sun elevation in degrees so they
// line up 1:1 with the curve X axis, making it easy for the designer to "graduate" to real curves.
// ============================================================================================

// Sun brightness (lux): off below the horizon, a quick golden ramp through the first ~15deg,
// then leveling toward a bright neutral midday.
float AMiraDayNightCycle::FallbackSunIntensity(float ElevDeg) const
{
	if (ElevDeg <= -2.f)
	{
		return 0.f; // sun is set — no direct light (the moon + sky handle night).
	}
	// Two-stage rise for a natural sunrise:
	//   * From the horizon up to ~15deg the sun brightens fast (the "golden hour" ramp).
	//   * Above ~15deg it eases the rest of the way to a bright neutral midday.
	const float HorizonLux = 2.5f;  // faint deep-golden sliver right at sunrise/sunset
	const float GoldenLux  = 6.0f;  // golden hour, sun low and warm
	const float MiddayLux  = 10.0f; // bright neutral noon
	if (ElevDeg <= 15.f)
	{
		// 0 lux at -2deg -> HorizonLux as it clears the horizon -> GoldenLux by 15deg.
		const float T = FMath::Clamp((ElevDeg + 2.f) / 17.f, 0.f, 1.f);
		return FMath::Lerp(0.f, GoldenLux, T) + HorizonLux * T * (1.f - T);
	}
	// Above golden hour: ease from GoldenLux up to full MiddayLux by ~45deg, then hold.
	const float T = FMath::Clamp((ElevDeg - 15.f) / 30.f, 0.f, 1.f);
	return FMath::Lerp(GoldenLux, MiddayLux, T);
}

// Sun color temperature (Kelvin): deep warm at the horizon, neutral daylight high in the sky.
float AMiraDayNightCycle::FallbackSunTemperature(float ElevDeg) const
{
	// Below/at horizon: ~2000K (deep orange). By ~10deg: ~3600K (golden hour). By 35deg+: 6500K.
	const float WarmK   = 2000.f;  // sunrise/sunset glow
	const float GoldenK = 3600.f;  // golden hour
	const float NoonK   = 6500.f;  // neutral daylight
	if (ElevDeg <= 0.f)
	{
		return WarmK;
	}
	if (ElevDeg <= 10.f)
	{
		return FMath::Lerp(WarmK, GoldenK, ElevDeg / 10.f);
	}
	const float T = FMath::Clamp((ElevDeg - 10.f) / 25.f, 0.f, 1.f); // 10deg->35deg
	return FMath::Lerp(GoldenK, NoonK, T);
}

// SkyLight (ambient) intensity: bright by day, low-but-nonzero by night so the world stays
// readable under cool moonlight. Crossfades through dusk as the sun dips below the horizon.
float AMiraDayNightCycle::FallbackSkyLightIntensity(float ElevDeg) const
{
	const float DayAmbient   = 1.0f;   // full ambient bounce by day
	const float NightAmbient = 0.08f;  // dim, readable night floor (NOT zero)
	// Crossfade across the horizon band -8deg .. +8deg.
	const float DayWeight = FMath::Clamp((ElevDeg + 8.f) / 16.f, 0.f, 1.f);
	return FMath::Lerp(NightAmbient, DayAmbient, DayWeight);
}

// Fog inscattering color: warm grey-orange near the horizon (dawn/dusk haze), neutral cool-grey
// at noon, deep blue at night. Grounded, atmospheric — not stylized.
FLinearColor AMiraDayNightCycle::FallbackFogColor(float ElevDeg) const
{
	const FLinearColor NightFog(0.015f, 0.025f, 0.055f);  // deep cool blue
	const FLinearColor DuskFog (0.32f,  0.20f,  0.13f);   // warm grey-orange horizon haze
	const FLinearColor NoonFog (0.16f,  0.22f,  0.30f);   // neutral cool-grey daytime

	if (ElevDeg <= -6.f)
	{
		return NightFog;
	}
	if (ElevDeg <= 8.f)
	{
		// Horizon band: blend night -> dusk -> as the sun crosses the horizon.
		const float T = FMath::Clamp((ElevDeg + 6.f) / 14.f, 0.f, 1.f);
		return FMath::Lerp(NightFog, DuskFog, T);
	}
	// Daylight: blend the warm dusk tone up to neutral noon as the sun climbs.
	const float T = FMath::Clamp((ElevDeg - 8.f) / 27.f, 0.f, 1.f); // 8deg -> 35deg
	return FMath::Lerp(DuskFog, NoonFog, T);
}

// Fog density: a touch thicker at dawn/dusk/night for that "atmospheric morning mist" feel,
// thinning out under a high midday sun.
float AMiraDayNightCycle::FallbackFogDensity(float ElevDeg) const
{
	const float ThickHaze = 0.020f; // dawn/dusk/night
	const float ThinHaze  = 0.008f; // clear midday
	const float DayWeight = FMath::Clamp(ElevDeg / 35.f, 0.f, 1.f); // 0 at horizon, 1 at 35deg+
	return FMath::Lerp(ThickHaze, ThinHaze, DayWeight);
}
