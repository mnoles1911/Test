// MiraFPCharacter.h - a first-person TEST character for driving the voxel world.
//
// Purpose: give us something to walk/fly through the streamed 10cm voxel terrain
// so we can actually exercise P1 (async streaming), P3 (LOD), and the vistas. This
// is NOT the final game camera - the design's canonical camera is third-person
// over-shoulder (see design/CAMERA_AND_PERSPECTIVE.md, CameraRig.gd). That rig
// comes later. This pawn mirrors the Godot MOVEMENT feel (WASD camera-relative,
// mouse-look, Left-Shift sprint, C crouch, Space jump) and adds an F "fly" toggle
// so you can rise above the 5km map and watch streaming/LOD across distance.
//
// Input is legacy axis/action mappings (Config/DefaultInput.ini) so no Input asset
// authoring is needed - the names below (MoveForward/MoveRight/Turn/LookUp/Jump/
// Sprint/CrouchToggle/FlyToggle) match that file.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "MiraFPCharacter.generated.h"

class UCameraComponent;
class UInputAction;
class UInputMappingContext;

UCLASS()
class MIRATHALCORE_API AMiraFPCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AMiraFPCharacter();

	// Ground walk speed (cm/s). 600 = 6 m/s, a brisk run at 10 vox/m.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "50"))
	float WalkSpeed = 600.0f;

	// Sprint speed while Left-Shift is held (cm/s).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "50"))
	float SprintSpeed = 1100.0f;

	// Crouched walk speed (cm/s) - C toggles the crouch stance.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "10"))
	float CrouchSpeed = 250.0f;

	// Fly speed (cm/s) while the F fly-toggle is on - fast, for surveying the map.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "50"))
	float FlySpeed = 2500.0f;

	// Mouse look sensitivity multiplier (1.0 = UE default per-frame mouse delta).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "0.05"))
	float MouseSensitivity = 1.0f;

	// Camera height above the capsule CENTRE (cm). The capsule centre sits one
	// half-height (90 cm) off the ground, so 78 here puts the eyes at 90 + 78 = 168 cm
	// off the ground when standing — a ~1.68 m human (≈17 voxels at 10 cm/voxel). When
	// crouched the capsule shrinks and the camera follows it down automatically.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement")
	float CameraEyeHeight = 78.0f;

	// Standing capsule half-height (cm). 90 -> a 180 cm (18-voxel) tall human.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "30"))
	float StandingHalfHeight = 90.0f;

	// Standing capsule radius (cm). ~34 is roughly shoulder-to-shoulder half-width.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "10"))
	float CapsuleRadius = 34.0f;

	// First-person field of view (degrees). 90 is UE's default; 95 feels a little more
	// natural/open for FP without the fisheye of very wide values.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement", meta = (ClampMin = "60", ClampMax = "120"))
	float CameraFOV = 95.0f;

	// Start in fly mode so the pawn doesn't fall before the terrain has streamed in
	// under it. Press F to drop into walking once you're over solid ground.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Movement")
	bool bStartFlying = true;

	// --- Dig (LMB): line-trace from the camera and carve the voxel world at the hit,
	//     so you can mine holes while exploring. Exercises CarveAtWorld + P2 journal. ---

	// How far (cm) the dig ray reaches from the camera. 8000 = 80 m, so you can dig
	// from fly height (the old 15 m couldn't reach the ground while hovering).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Dig", meta = (ClampMin = "50"))
	float DigReachCm = 8000.0f;

	// Side length (voxels) of the carve box. 3 = a 30 cm (3x3x3) cube bite — the
	// default mining bite, matching the Godot build.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Dig", meta = (ClampMin = "1", ClampMax = "16"))
	int32 DigSizeVoxels = 3;

	// Draw a wireframe outline around the exact voxels the next LMB dig will carve
	// (the "destroy preview" from the Godot build). Updated every frame from where
	// the crosshair is aiming.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Dig")
	bool bShowDigPreview = true;

	// For top-down digs, follow the surface per-column (each column digs N deep from its
	// own top) instead of a single centered cube — so hillside digs leave no uphill tops.
	// Off = the old centered cube (for A/B comparison). Side/wall digs always use the cube.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Dig")
	bool bSurfaceConformingDig = true;

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	// First-person camera (uses the controller rotation so mouse-look aims it).
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Movement")
	UCameraComponent* FirstPersonCamera = nullptr;

	// --- Enhanced Input: the BUTTON actions. WASD + mouse stay on legacy axis bindings
	//     (they work on the EnhancedInputComponent), but legacy BUTTON bindings are
	//     dropped on it, so the buttons go through Enhanced Input. These actions + the
	//     mapping context are created + key-mapped in the constructor (no asset files). ---
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputMappingContext* MappingContext = nullptr;
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputAction* IA_Jump = nullptr;
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputAction* IA_Sprint = nullptr;
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputAction* IA_Crouch = nullptr;
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputAction* IA_Fly = nullptr;
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Input")
	UInputAction* IA_Dig = nullptr;

	// --- input handlers ---
	void MoveForward(float Value); // W/S - camera-relative; ascends when flying + looking up
	void MoveRight(float Value);   // A/D - camera-relative (horizontal only)
	void Turn(float Value);        // mouse X -> yaw (rotates the body, so move is camera-relative)
	void LookUp(float Value);      // mouse Y -> pitch (camera only)

	// SPACE is dual-purpose by mode. We act on PRESS/RELEASE only (those events fire
	// reliably) and hold the fly-up state in a flag that Tick applies every frame —
	// the per-frame "Triggered" event proved unreliable for this.
	//   walk/run -> Jump (on press) / StopJumping (on release)
	//   fly      -> hold to ASCEND (Tick adds upward input while bAscendHeld)
	void SpacePressed();   // Started   (first frame down)
	void SpaceReleased();  // Completed (release)

	// SHIFT is dual-purpose by mode, same press/release + Tick-flag scheme:
	//   walk/run -> hold to SPRINT (momentary, NOT a toggle)
	//   fly      -> hold to DESCEND (Tick adds downward input while bDescendHeld)
	void ShiftPressed();   // Started
	void ShiftReleased();  // Completed

	void ToggleCrouch();   // C - toggle crouch view (lower) <-> standing (default), walk only
	void ToggleFly();      // F - toggle walk <-> fly
	void Dig(); // LMB: line-trace from camera, carve the voxel world at the hit

private:
	bool bSprinting = false;
	bool bFlying = false;
	bool bAscendHeld = false;   // SPACE held while flying -> rise (applied in Tick)
	bool bDescendHeld = false;  // SHIFT held while flying -> sink (applied in Tick)
	void ApplySpeed(); // push the current Walk/Sprint/Fly speed into the movement component

	// Shared dig ray: trace from the camera, return the hit + the owning voxel world.
	// Used by both Dig() (to carve) and Tick() (to draw the preview outline). Returns
	// null if the ray missed terrain or no voxel world was found.
	class AVoxelWorld* TraceDigTarget(FHitResult& OutHit) const;

	// The dig target the MOST RECENT preview frame resolved. The click carve uses THESE
	// (not a fresh trace), so what gets deleted is exactly the 3x3x3 that was outlined —
	// no 1-voxel drift between the outline (drawn in Tick) and the carve (on click).
	TWeakObjectPtr<class AVoxelWorld> CachedDigWorld;
	FVector CachedDigPoint = FVector::ZeroVector;
	FVector CachedDigNormal = FVector::ZeroVector;
	bool bHasDigTarget = false;
};
