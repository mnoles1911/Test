// MiraHUD.h - a minimal HUD that draws a centre crosshair so you can see exactly
// where the dig ray is aiming. Mirrors the Godot build's centre reticle. Set as the
// game mode's HUDClass (see AMiraTestGameMode). The 3D dig-preview OUTLINE (the box
// showing which 3x3x3 voxels will be carved) is drawn by the pawn itself, not here.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "MiraHUD.generated.h"

UCLASS()
class MIRATHALCORE_API AMiraHUD : public AHUD
{
	GENERATED_BODY()

public:
	// Called every frame by the engine; we draw the crosshair onto the Canvas here.
	virtual void DrawHUD() override;

	// Half-length of each crosshair arm in pixels (so the cross is 2x this wide/tall).
	UPROPERTY(EditAnywhere, Category = "MiraThal|HUD", meta = (ClampMin = "2"))
	float CrosshairArmPixels = 10.0f;

	// Pixel gap left empty at the very centre, so the lines form a + with a hole (a
	// classic reticle) rather than a solid plus. 0 = solid cross.
	UPROPERTY(EditAnywhere, Category = "MiraThal|HUD", meta = (ClampMin = "0"))
	float CrosshairGapPixels = 4.0f;

	// Line thickness in pixels.
	UPROPERTY(EditAnywhere, Category = "MiraThal|HUD", meta = (ClampMin = "1"))
	float CrosshairThickness = 2.0f;

	// Crosshair colour (white, slightly translucent so it reads on any terrain).
	UPROPERTY(EditAnywhere, Category = "MiraThal|HUD")
	FLinearColor CrosshairColor = FLinearColor(1.0f, 1.0f, 1.0f, 0.85f);

	// Show the top-right debug readout (FPS, frame ms, world XYZ). On by default for the
	// test rig; used to read coordinates for placing the spawn.
	UPROPERTY(EditAnywhere, Category = "MiraThal|HUD")
	bool bShowDebug = true;
};
