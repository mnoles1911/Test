// MiraTestGameMode.cpp - spawn the first-person test pawn + crosshair HUD.
#include "Player/MiraTestGameMode.h"
#include "Player/MiraFPCharacter.h"
#include "Player/MiraHUD.h"

AMiraTestGameMode::AMiraTestGameMode()
{
	DefaultPawnClass = AMiraFPCharacter::StaticClass();
	HUDClass = AMiraHUD::StaticClass(); // centre crosshair for aiming the dig ray
}
