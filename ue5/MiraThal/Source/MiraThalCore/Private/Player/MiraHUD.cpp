// MiraHUD.cpp - centre crosshair + a top-right debug readout (see header).
#include "Player/MiraHUD.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"               // GEngine->GetSmallFont(), GAverageFPS/GAverageMS
#include "Engine/Font.h"                 // UFont
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "EngineUtils.h"                 // TActorIterator — to find the AVoxelWorld each frame
#include "VoxelWorld.h"                  // AVoxelWorld + FMiraFarRenderStats (far-render diagnostics)

// Engine-wide smoothed perf globals (declared in the engine, not surfaced by a public
// header here) — the same values the `stat fps` / `stat unit` displays read.
extern ENGINE_API float GAverageFPS;
extern ENGINE_API float GAverageMS;

void AMiraHUD::DrawHUD()
{
	Super::DrawHUD();

	if (Canvas == nullptr)
	{
		return;
	}

	// --- Centre crosshair ---
	const float CX = Canvas->ClipX * 0.5f;
	const float CY = Canvas->ClipY * 0.5f;

	const float Gap  = CrosshairGapPixels;
	const float Arm  = CrosshairArmPixels;
	const FLinearColor Col = CrosshairColor;
	const float Thick = CrosshairThickness;

	DrawLine(CX - Gap - Arm, CY, CX - Gap, CY, Col, Thick); // left
	DrawLine(CX + Gap, CY, CX + Gap + Arm, CY, Col, Thick); // right
	DrawLine(CX, CY - Gap - Arm, CX, CY - Gap, Col, Thick); // up
	DrawLine(CX, CY + Gap, CX, CY + Gap + Arm, Col, Thick); // down

	// --- Top-right debug readout: FPS, frame time, and the pawn's world XYZ (cm). Fly
	//     to a spot, read X/Y/Z here, and paste those into the PlayerStart to set spawn. ---
	if (!bShowDebug)
	{
		return;
	}

	UFont* Font = GEngine ? GEngine->GetSmallFont() : nullptr;
	const float RightX = Canvas->ClipX - 240.0f;
	float Y = 18.0f;
	const float LineH = 18.0f;
	const FLinearColor Lime(0.45f, 1.0f, 0.45f, 1.0f);

	// FPS + frame time (GAverageMS is the per-frame render latency in single-player).
	DrawText(FString::Printf(TEXT("FPS %.0f   (%.1f ms)"), GAverageFPS, GAverageMS), Lime, RightX, Y, Font);
	Y += LineH;

	FVector Loc = FVector::ZeroVector;
	if (PlayerOwner)
	{
		if (APawn* P = PlayerOwner->GetPawn())
		{
			Loc = P->GetActorLocation();
		}
	}
	// World coordinates in UE units (cm) — exactly what a PlayerStart's Location takes.
	DrawText(FString::Printf(TEXT("X %.0f"), Loc.X), Lime, RightX, Y, Font); Y += LineH;
	DrawText(FString::Printf(TEXT("Y %.0f"), Loc.Y), Lime, RightX, Y, Font); Y += LineH;
	DrawText(FString::Printf(TEXT("Z %.0f"), Loc.Z), Lime, RightX, Y, Font); Y += LineH;
	// Z also in voxels (1 voxel = 10 cm) for quick mental math against the terrain.
	DrawText(FString::Printf(TEXT("(Z %.1f voxels up)"), Loc.Z / 10.0f), Lime, RightX, Y, Font); Y += LineH;

	// --- Far-render load readout (super-chunks, coarse far-gen, 3D-shell trim, fades) ---
	// Find the voxel world this frame (there's one AVoxelWorld) and ask it for a READ-ONLY
	// stats snapshot. Guarded against null so the overlay is harmless if the world isn't
	// up yet. Gated by the SAME bShowDebug toggle as the FPS/XYZ lines above (we already
	// returned early if it was off). Pure display — no streaming/render state is touched.
	AVoxelWorld* VoxWorld = nullptr;
	if (UWorld* W = GetWorld())
	{
		for (TActorIterator<AVoxelWorld> It(W); It; ++It)
		{
			VoxWorld = *It;
			break;
		}
	}
	if (VoxWorld)
	{
		const FMiraFarRenderStats Far = VoxWorld->GetFarRenderStats();
		Y += LineH; // a blank gap separating the perf/XYZ block from the far-render block
		DrawText(FString::Printf(TEXT("SUPER %d (r%d)"), Far.SuperActorsTotal, Far.SuperRadiusChunks), Lime, RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("  L0-5 %d/%d/%d/%d/%d/%d"),
			Far.SuperByLod[0], Far.SuperByLod[1], Far.SuperByLod[2],
			Far.SuperByLod[3], Far.SuperByLod[4], Far.SuperByLod[5]), Lime, RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("coarseGen %d"), Far.CoarseGenColumns), Lime, RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("shellCulled %d"), Far.ShellCulledColumns), Lime, RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("fades %d"), Far.ActiveFades), Lime, RightX, Y, Font); Y += LineH;

		// --- Chunk-loading profiler (TOOL 2) ---
		// Correlate hitches with loading: how much the last tick uploaded (gen/mesh ops),
		// how deep the worker queues are (inFlight/pending), and a rolling WORST-FRAME window
		// (~2 s) so a 150 ms spike stays readable after it passes — plus the worst frame that
		// landed on a LOADING tick. The worst-frame lines turn amber/red as the spike grows so
		// the eye catches them. Pure read-only display; touches no streaming state.
		Y += LineH; // blank gap separating the far-render block from the profiler block
		DrawText(FString::Printf(TEXT("gen %d  mesh %d  /tick"), Far.GenOpsThisTick, Far.MeshOpsThisTick), Lime, RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("inFlight %d  pending %d"), Far.JobsInFlight, Far.Pending), Lime, RightX, Y, Font); Y += LineH;

		// Color the worst-frame readouts by severity: green < 33 ms (~30 fps), amber < 100 ms,
		// red beyond (the single-digit-FPS spikes the designer is chasing).
		auto MsColor = [](float Ms) -> FLinearColor
		{
			if (Ms >= 100.0f) { return FLinearColor(1.0f, 0.30f, 0.30f, 1.0f); } // red
			if (Ms >= 33.0f)  { return FLinearColor(1.0f, 0.80f, 0.30f, 1.0f); } // amber
			return FLinearColor(0.45f, 1.0f, 0.45f, 1.0f);                        // lime
		};
		DrawText(FString::Printf(TEXT("worst %.0f ms (2s)"), Far.WorstFrameMs), MsColor(Far.WorstFrameMs), RightX, Y, Font); Y += LineH;
		DrawText(FString::Printf(TEXT("worst-load %.0f ms"), Far.WorstLoadFrameMs), MsColor(Far.WorstLoadFrameMs), RightX, Y, Font);
	}
}
