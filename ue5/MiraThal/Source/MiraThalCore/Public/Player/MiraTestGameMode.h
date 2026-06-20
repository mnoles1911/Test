// MiraTestGameMode.h - a minimal game mode that spawns the first-person test pawn.
//
// Set this as the level's GameMode Override (World Settings) so pressing Play spawns
// AMiraFPCharacter at the PlayerStart. Used only for driving/testing the voxel world.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "MiraTestGameMode.generated.h"

UCLASS()
class MIRATHALCORE_API AMiraTestGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AMiraTestGameMode();
};
