// WorldEditPersistence.h — read/write the per-region edit-journal files on disk.
//
// The Core WorldEditStore owns the in-memory edits and RegionFormat does the byte
// packing (varint + CRC). This thin UE layer is just the FILE side: turn a region
// coord into a path under Saved/Worlds/<name>/ and read/write the bytes there.
// Authoritative data (never auto-deleted) — see design/UE5_WORLD_STREAMING_PLAN §7a.

#pragma once

#include "CoreMinimal.h"
#include <vector>
#include <cstdint>

namespace MiraWorldPersist
{
	// Absolute directory for a named world's region files (created on demand).
	FString WorldDir(const FString& WorldSaveName);

	// Path of one region's delta file: <WorldDir>/r_<x>_<z>.delta.
	FString RegionFilePath(const FString& WorldSaveName, const FIntPoint& Region);

	// Write a region's encoded delta-log bytes to disk (atomic: temp + rename).
	// Returns false on any I/O failure.
	bool SaveRegion(const FString& WorldSaveName, const FIntPoint& Region,
	                const std::vector<uint8_t>& Bytes);

	// Read a region's delta-log bytes. Returns false if the file is absent/unreadable
	// (a never-edited region simply has no file — that's the normal empty case).
	bool LoadRegion(const FString& WorldSaveName, const FIntPoint& Region,
	                std::vector<uint8_t>& OutBytes);

	// True if a region file exists on disk.
	bool RegionFileExists(const FString& WorldSaveName, const FIntPoint& Region);
}
