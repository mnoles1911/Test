// WorldEditPersistence.cpp — region delta-file I/O.
#include "WorldEditPersistence.h"

#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformFileManager.h"

namespace MiraWorldPersist
{
	FString WorldDir(const FString& WorldSaveName)
	{
		const FString Name = WorldSaveName.IsEmpty() ? TEXT("DefaultWorld") : WorldSaveName;
		return FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Worlds"), Name);
	}

	FString RegionFilePath(const FString& WorldSaveName, const FIntPoint& Region)
	{
		// FIntPoint.X = region X tile, FIntPoint.Y = region Z tile.
		const FString File = FString::Printf(TEXT("r_%d_%d.delta"), Region.X, Region.Y);
		return FPaths::Combine(WorldDir(WorldSaveName), File);
	}

	bool RegionFileExists(const FString& WorldSaveName, const FIntPoint& Region)
	{
		return FPaths::FileExists(RegionFilePath(WorldSaveName, Region));
	}

	bool SaveRegion(const FString& WorldSaveName, const FIntPoint& Region,
	                const std::vector<uint8_t>& Bytes)
	{
		const FString Dir = WorldDir(WorldSaveName);
		IFileManager& FM = IFileManager::Get();
		FM.MakeDirectory(*Dir, /*Tree=*/true);

		// Bridge std::vector -> TArray for FFileHelper.
		TArray<uint8> Arr;
		Arr.Append(Bytes.data(), static_cast<int32>(Bytes.size()));

		// Atomic-ish: write a temp then move over the target so a crash mid-write
		// never leaves a half-written (CRC-failing) region file.
		const FString Final = RegionFilePath(WorldSaveName, Region);
		const FString Temp  = Final + TEXT(".tmp");
		if (!FFileHelper::SaveArrayToFile(Arr, *Temp))
		{
			return false;
		}
		// Move replaces the destination if present.
		if (!FM.Move(*Final, *Temp, /*bReplace=*/true, true, true, true))
		{
			// Fall back to a direct write if the move failed for some reason.
			return FFileHelper::SaveArrayToFile(Arr, *Final);
		}
		return true;
	}

	bool LoadRegion(const FString& WorldSaveName, const FIntPoint& Region,
	                std::vector<uint8_t>& OutBytes)
	{
		const FString Path = RegionFilePath(WorldSaveName, Region);
		if (!FPaths::FileExists(Path))
		{
			return false; // never-edited region — no file is the normal empty case
		}
		TArray<uint8> Arr;
		if (!FFileHelper::LoadFileToArray(Arr, *Path))
		{
			return false;
		}
		OutBytes.assign(Arr.GetData(), Arr.GetData() + Arr.Num());
		return true;
	}
}
