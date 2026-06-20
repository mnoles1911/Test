// MiraFPCharacter.cpp - first-person test pawn (see header).
#include "Player/MiraFPCharacter.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "VoxelWorld.h"               // AVoxelWorld::CarveAtWorld (dig)
#include "Engine/World.h"
#include "Engine/Engine.h"            // GEngine->AddOnScreenDebugMessage (input feedback)
#include "EngineUtils.h"              // TActorIterator (fallback AVoxelWorld lookup)
#include "CollisionQueryParams.h"
#include "DrawDebugHelpers.h"         // DrawDebugBox (dig-preview outline)
// Enhanced Input (button actions):
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputCoreTypes.h"           // EKeys

// Tiny helper: flash a message on screen so you can SEE that an input fired (and what
// it did). Keyed so each line replaces itself instead of stacking. Dev feedback only.
static void MiraScreenMsg(int32 Key, const FColor& Color, const FString& Text)
{
	if (GEngine)
	{
		GEngine->AddOnScreenDebugMessage(Key, 2.0f, Color, Text);
	}
}

// How far (cm) to push the dig point IN from the hit surface before snapping it to a
// voxel. Collision reports the impact point a hair OUTSIDE the surface, so a small
// inset (we used 5 cm) left the centre voxel in the AIR above the surface — the carve
// box's top layer was air and the surface layer survived. One voxel is 10 cm; ~9 cm
// reliably lands inside the solid surface voxel without overshooting a layer too deep.
static constexpr float kDigSurfaceInsetCm = 9.0f;

AMiraFPCharacter::AMiraFPCharacter()
{
	// Tick is ON: it applies continuous fly up/down while SPACE/SHIFT are held and
	// draws the dig-preview outline each frame.
	PrimaryActorTick.bCanEverTick = true;

	// Mouse yaw rotates the BODY (not just the camera) so WASD is always
	// camera-relative - "W moves where you look", mirroring the Godot scheme.
	bUseControllerRotationYaw = true;
	bUseControllerRotationPitch = false;
	bUseControllerRotationRoll = false;

	// Size the capsule to a real human (180 cm tall, 18 voxels) so the eye height and
	// crouch feel right against the 10 cm voxels.
	if (UCapsuleComponent* Capsule = GetCapsuleComponent())
	{
		Capsule->InitCapsuleSize(CapsuleRadius, StandingHalfHeight);
	}

	// First-person camera at eye height, driven by the controller's look rotation.
	FirstPersonCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FirstPersonCamera"));
	FirstPersonCamera->SetupAttachment(GetCapsuleComponent());
	FirstPersonCamera->SetRelativeLocation(FVector(0.0f, 0.0f, CameraEyeHeight));
	FirstPersonCamera->bUsePawnControlRotation = true;
	FirstPersonCamera->SetFieldOfView(CameraFOV);

	if (UCharacterMovementComponent* Move = GetCharacterMovement())
	{
		Move->MaxWalkSpeed = WalkSpeed;
		Move->MaxWalkSpeedCrouched = CrouchSpeed;
		Move->MaxFlySpeed = FlySpeed;
		Move->JumpZVelocity = 600.0f;
		Move->AirControl = 0.5f;
		Move->BrakingDecelerationFlying = 2048.0f;
		Move->NavAgentProps.bCanCrouch = true;
	}

	// --- Enhanced Input button actions + mapping context, created in-code (no asset
	//     files). Each is a digital (button) action; we map keys to them here, and add
	//     the mapping context to the player in BeginPlay. WASD + mouse stay on the
	//     legacy axis bindings in SetupPlayerInputComponent. ---
	IA_Jump   = CreateDefaultSubobject<UInputAction>(TEXT("IA_Jump"));
	IA_Sprint = CreateDefaultSubobject<UInputAction>(TEXT("IA_Sprint"));
	IA_Crouch = CreateDefaultSubobject<UInputAction>(TEXT("IA_Crouch"));
	IA_Fly    = CreateDefaultSubobject<UInputAction>(TEXT("IA_Fly"));
	IA_Dig    = CreateDefaultSubobject<UInputAction>(TEXT("IA_Dig"));
	MappingContext = CreateDefaultSubobject<UInputMappingContext>(TEXT("IMC_MiraDefault"));
	MappingContext->MapKey(IA_Jump,   EKeys::SpaceBar);
	MappingContext->MapKey(IA_Sprint, EKeys::LeftShift);
	MappingContext->MapKey(IA_Crouch, EKeys::C);
	MappingContext->MapKey(IA_Fly,    EKeys::F);
	MappingContext->MapKey(IA_Dig,    EKeys::LeftMouseButton);
}

void AMiraFPCharacter::BeginPlay()
{
	Super::BeginPlay();

	// Place the pawn ON the terrain surface at its spawn XY. Terrain height changes
	// between sessions (heightmap edits / vertical exaggeration), so a hard-coded spawn
	// Z can end up buried underground or floating high — ask the voxel world for the real
	// surface height here instead of trusting the PlayerStart's Z.
	for (TActorIterator<AVoxelWorld> It(GetWorld()); It; ++It)
	{
		const FVector L = GetActorLocation();
		const float SurfaceZ = It->SurfaceWorldZAt(L.X, L.Y);
		// Capsule centre = surface + half-height puts the feet on the ground; +50 cm so we
		// start just clear of it (the pawn begins flying, so it holds this height).
		SetActorLocation(FVector(L.X, L.Y, SurfaceZ + StandingHalfHeight + 50.0f));
		break;
	}

	bFlying = bStartFlying;
	if (UCharacterMovementComponent* Move = GetCharacterMovement())
	{
		Move->SetMovementMode(bFlying ? MOVE_Flying : MOVE_Walking);
	}
	ApplySpeed();

	// Capture the mouse so motion drives the camera (cursor hidden), like the Godot
	// CAPTURED mouse mode during play.
	if (APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		PC->bShowMouseCursor = false;
		FInputModeGameOnly Mode;
		PC->SetInputMode(Mode);

		// Let the player look (almost) straight down / up. The default camera manager
		// clamps pitch short of vertical, which stops you aiming into a shaft you just
		// dug — so you couldn't keep digging downward. -89/+89 lets you mine straight down.
		if (PC->PlayerCameraManager)
		{
			PC->PlayerCameraManager->ViewPitchMin = -89.0f;
			PC->PlayerCameraManager->ViewPitchMax =  89.0f;
		}

		// Activate our Enhanced Input mapping context so the button actions fire.
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem =
			ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			Subsystem->AddMappingContext(MappingContext, /*Priority=*/0);
		}
	}
}

void AMiraFPCharacter::ApplySpeed()
{
	if (UCharacterMovementComponent* Move = GetCharacterMovement())
	{
		Move->MaxWalkSpeed = bSprinting ? SprintSpeed : WalkSpeed;
		Move->MaxWalkSpeedCrouched = CrouchSpeed;
		Move->MaxFlySpeed = FlySpeed;
	}
}

void AMiraFPCharacter::MoveForward(float Value)
{
	if (Value == 0.0f || Controller == nullptr)
	{
		return;
	}
	if (bFlying)
	{
		// Full look direction (includes pitch) so looking up + W climbs.
		AddMovementInput(GetControlRotation().Vector(), Value);
	}
	else
	{
		// Horizontal only on the ground (Y is gravity); forward = camera yaw.
		const FRotator YawOnly(0.0f, GetControlRotation().Yaw, 0.0f);
		AddMovementInput(FRotationMatrix(YawOnly).GetUnitAxis(EAxis::X), Value);
	}
}

void AMiraFPCharacter::MoveRight(float Value)
{
	if (Value == 0.0f || Controller == nullptr)
	{
		return;
	}
	const FRotator YawOnly(0.0f, GetControlRotation().Yaw, 0.0f);
	AddMovementInput(FRotationMatrix(YawOnly).GetUnitAxis(EAxis::Y), Value);
}

void AMiraFPCharacter::Turn(float Value)
{
	AddControllerYawInput(Value * MouseSensitivity);
}

void AMiraFPCharacter::LookUp(float Value)
{
	AddControllerPitchInput(Value * MouseSensitivity);
}

// --- SPACE ---------------------------------------------------------------
// Walk: jump now. Fly: latch "ascend" - Tick applies the upward push every frame
// while it's held (the per-frame input event was unreliable, so we drive it ourselves).
void AMiraFPCharacter::SpacePressed()
{
	if (bFlying)
	{
		bAscendHeld = true;
		MiraScreenMsg(1, FColor::Green, TEXT("FLY UP"));
	}
	else
	{
		Jump();
		MiraScreenMsg(1, FColor::Green, TEXT("JUMP"));
	}
}
void AMiraFPCharacter::SpaceReleased()
{
	bAscendHeld = false;
	if (!bFlying) { StopJumping(); }
}

// --- SHIFT ---------------------------------------------------------------
// Walk: hold to sprint (momentary). Fly: latch "descend" - Tick applies the downward
// push every frame while it's held.
void AMiraFPCharacter::ShiftPressed()
{
	if (bFlying)
	{
		bDescendHeld = true;
		MiraScreenMsg(2, FColor::Yellow, TEXT("FLY DOWN"));
	}
	else
	{
		bSprinting = true;
		ApplySpeed();
		MiraScreenMsg(2, FColor::Yellow, TEXT("SPRINT (hold)"));
	}
}
void AMiraFPCharacter::ShiftReleased()
{
	bDescendHeld = false;
	// Releasing always ends sprint (harmless if we were flying / never sprinting).
	bSprinting = false;
	ApplySpeed();
}

// Apply continuous fly up/down + draw the dig-preview outline, every frame.
void AMiraFPCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (bFlying)
	{
		// World up (+Z) / down (-Z). MaxFlySpeed caps the resulting speed. WASD can be
		// added at the same time, so you can fly forward and climb together.
		if (bAscendHeld)  { AddMovementInput(FVector::UpVector,  1.0f); }
		if (bDescendHeld) { AddMovementInput(FVector::UpVector, -1.0f); }
	}

	// Resolve the dig target every frame and CACHE it (world + dig point + normal). The
	// click (Dig) carves from THIS cache instead of re-tracing, so the deleted volume is
	// exactly the box that was outlined — no 1-voxel drift between outline and carve.
	bHasDigTarget = false;
	if (GetWorld())
	{
		FHitResult Hit;
		if (AVoxelWorld* VoxelWorld = TraceDigTarget(Hit))
		{
			const FVector DigPoint = Hit.ImpactPoint - Hit.ImpactNormal * kDigSurfaceInsetCm;
			CachedDigWorld  = VoxelWorld;
			CachedDigPoint  = DigPoint;
			CachedDigNormal = Hit.ImpactNormal;
			bHasDigTarget   = true;

			// Outline exactly what the click will remove (same point+normal as the carve).
			if (bShowDigPreview)
			{
				// Top-down digs use the surface-conforming per-column outline; wall/side
				// digs (and conforming off) use the single centered box.
				const FVector& N = Hit.ImpactNormal;
				const bool bTopDig = FMath::Abs(N.Z) >= FMath::Abs(N.X) && FMath::Abs(N.Z) >= FMath::Abs(N.Y);
				if (bSurfaceConformingDig && bTopDig)
				{
					TArray<FVector> Centers; FVector Extent;
					if (VoxelWorld->ComputeColumnPreview(DigPoint, N, DigSizeVoxels, Centers, Extent))
					{
						for (const FVector& C : Centers)
						{
							DrawDebugBox(GetWorld(), C, Extent, FQuat::Identity,
								FColor::Yellow, /*bPersistent=*/false, /*Life=*/-1.0f, /*Depth=*/0, /*Thickness=*/2.0f);
						}
					}
				}
				else
				{
					FVector Center, Extent;
					if (VoxelWorld->ComputeCarvePreviewWorld(DigPoint, N, DigSizeVoxels, Center, Extent))
					{
						DrawDebugBox(GetWorld(), Center, Extent, FQuat::Identity,
							FColor::Yellow, /*bPersistent=*/false, /*Life=*/-1.0f, /*Depth=*/0, /*Thickness=*/2.0f);
					}
				}
			}
		}
	}
}

void AMiraFPCharacter::ToggleCrouch()
{
	if (bIsCrouched) { UnCrouch(); } else { Crouch(); }
	MiraScreenMsg(2, FColor::Cyan, bIsCrouched ? TEXT("CROUCH off") : TEXT("CROUCH on"));
}

void AMiraFPCharacter::ToggleFly()
{
	bFlying = !bFlying;
	// Clear any latched vertical intent so we don't keep rising/sinking after the swap.
	bAscendHeld = false;
	bDescendHeld = false;
	if (UCharacterMovementComponent* Move = GetCharacterMovement())
	{
		Move->SetMovementMode(bFlying ? MOVE_Flying : MOVE_Walking);
	}
	ApplySpeed();
	MiraScreenMsg(3, FColor::Green, bFlying ? TEXT("FLY mode (F to walk)") : TEXT("WALK mode (F to fly)"));
}

// Trace the dig ray from the camera and resolve the owning voxel world. Shared by
// Dig() (carve) and Tick() (preview). Returns null on a miss / non-voxel hit.
AVoxelWorld* AMiraFPCharacter::TraceDigTarget(FHitResult& OutHit) const
{
	if (FirstPersonCamera == nullptr || GetWorld() == nullptr)
	{
		return nullptr;
	}

	// Ray from the camera, along the look direction (i.e. the crosshair), out to DigReachCm.
	const FVector Start = FirstPersonCamera->GetComponentLocation();
	const FVector End   = Start + FirstPersonCamera->GetForwardVector() * DigReachCm;

	FCollisionQueryParams Params(SCENE_QUERY_STAT(MiraDig), /*bTraceComplex=*/false, this);
	Params.AddIgnoredActor(this);

	if (!GetWorld()->LineTraceSingleByChannel(OutHit, Start, End, ECC_Visibility, Params))
	{
		return nullptr;
	}

	// The hit actor is a voxel chunk renderer; its owner is the AVoxelWorld manager.
	// Fall back to a level search if the owner isn't set.
	AVoxelWorld* VoxelWorld = nullptr;
	if (AActor* HitActor = OutHit.GetActor())
	{
		VoxelWorld = Cast<AVoxelWorld>(HitActor->GetOwner());
	}
	if (VoxelWorld == nullptr)
	{
		for (TActorIterator<AVoxelWorld> It(GetWorld()); It; ++It)
		{
			VoxelWorld = *It;
			break;
		}
	}
	return VoxelWorld;
}

void AMiraFPCharacter::Dig()
{
	// PRIMARY PATH: carve the EXACT target the preview last outlined (cached in Tick).
	// Because CarveAtWorld and the preview both derive the box from this same
	// (point, normal), the deleted volume is precisely the outlined 3x3x3 — no drift.
	if (bHasDigTarget && CachedDigWorld.IsValid())
	{
		const FVector& N = CachedDigNormal;
		const bool bTopDig = FMath::Abs(N.Z) >= FMath::Abs(N.X) && FMath::Abs(N.Z) >= FMath::Abs(N.Y);
		if (bSurfaceConformingDig && bTopDig)
		{
			CachedDigWorld->CarveColumnConforming(CachedDigPoint, N, DigSizeVoxels);
		}
		else
		{
			CachedDigWorld->CarveAtWorld(CachedDigPoint, N, DigSizeVoxels);
		}
		MiraScreenMsg(4, FColor::Green, FString::Printf(TEXT("DIG %dx%dx%d (outlined)"),
			DigSizeVoxels, DigSizeVoxels, DigSizeVoxels));
		return;
	}

	// FALLBACK (preview off, or nothing outlined this frame): a fresh trace.
	FHitResult Hit;
	AVoxelWorld* VoxelWorld = TraceDigTarget(Hit);
	if (!Hit.bBlockingHit)
	{
		MiraScreenMsg(4, FColor::Orange, FString::Printf(TEXT("DIG: no terrain within %.0f m"), DigReachCm / 100.0f));
		return;
	}
	if (VoxelWorld == nullptr)
	{
		MiraScreenMsg(4, FColor::Orange, TEXT("DIG: hit non-voxel surface"));
		return;
	}
	const FVector DigPoint = Hit.ImpactPoint - Hit.ImpactNormal * kDigSurfaceInsetCm;
	VoxelWorld->CarveAtWorld(DigPoint, Hit.ImpactNormal, DigSizeVoxels);
	MiraScreenMsg(4, FColor::Green, FString::Printf(TEXT("DIG %dx%dx%d"),
		DigSizeVoxels, DigSizeVoxels, DigSizeVoxels));
}

void AMiraFPCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	// WASD + mouse: legacy axis bindings (these DO fire on the EnhancedInputComponent).
	PlayerInputComponent->BindAxis("MoveForward", this, &AMiraFPCharacter::MoveForward);
	PlayerInputComponent->BindAxis("MoveRight",   this, &AMiraFPCharacter::MoveRight);
	PlayerInputComponent->BindAxis("Turn",        this, &AMiraFPCharacter::Turn);
	PlayerInputComponent->BindAxis("LookUp",      this, &AMiraFPCharacter::LookUp);

	// Buttons: Enhanced Input (legacy BindAction is silently dropped on the
	// EnhancedInputComponent — this is the whole reason F/LMB/Shift/C didn't fire).
	if (UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(PlayerInputComponent))
	{
		// SPACE: Started=jump/start-ascend, Completed=stop. Held ascend is applied in Tick.
		EIC->BindAction(IA_Jump,   ETriggerEvent::Started,   this, &AMiraFPCharacter::SpacePressed);
		EIC->BindAction(IA_Jump,   ETriggerEvent::Completed, this, &AMiraFPCharacter::SpaceReleased);
		// SHIFT: Started=sprint/start-descend, Completed=stop. Held descend is applied in Tick.
		EIC->BindAction(IA_Sprint, ETriggerEvent::Started,   this, &AMiraFPCharacter::ShiftPressed);
		EIC->BindAction(IA_Sprint, ETriggerEvent::Completed, this, &AMiraFPCharacter::ShiftReleased);
		// C: toggle crouch view. F: toggle walk/fly. LMB: dig.
		EIC->BindAction(IA_Crouch, ETriggerEvent::Started,   this, &AMiraFPCharacter::ToggleCrouch);
		EIC->BindAction(IA_Fly,    ETriggerEvent::Started,   this, &AMiraFPCharacter::ToggleFly);
		EIC->BindAction(IA_Dig,    ETriggerEvent::Started,   this, &AMiraFPCharacter::Dig);
	}
}
