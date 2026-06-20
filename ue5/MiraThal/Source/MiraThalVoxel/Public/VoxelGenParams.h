// VoxelGenParams.h — the worker-thread snapshot of the terrain generator's knobs.
//
// WHY THIS EXISTS (plain English):
// Terrain for one chunk-column is PURE: it reads only the immutable heightmap + a
// handful of scalar knobs (seed, amplitude, sea level, ...). So we can generate it on
// a background thread — but a worker must NOT touch the live AVoxelWorld actor (that's
// game-thread-only state). The trick is to SNAPSHOT the knobs into a plain struct
// (FGenParams) and hand the worker a copy. BuildGen() then reconstructs an identical
// Core HeightmapGenerator from that snapshot anywhere — on a worker, OR in the offline
// Nanite cold-bake.
//
// THIS HEADER WAS PROMOTED OUT OF VoxelWorld.cpp on purpose: the live streaming path
// AND the bake module must build BYTE-IDENTICAL generators, or the baked far "crust"
// won't line up with the near voxels at the seam. One shared definition = one source of
// truth = guaranteed seam alignment. Moving it here is a PURE REFACTOR — every field
// (including the coarse-far-gen GenLod/bCoarseFarGen pair) and every caller is preserved.
//
// Pure-ish: this header pulls in the Core generator + heightmap, and (for the
// SnapshotGenParams convenience overload) the full AVoxelWorld so it can read the knobs.

#pragma once

#include "CoreMinimal.h"
#include "Core/HeightmapGenerator.h"  // mira::HeightmapGenerator — what BuildGen configures
#include "Core/ImageHeightmap.h"      // mira::ImageHeightmap — the immutable surface pointer
#include "VoxelWorld.h"               // AVoxelWorld — SnapshotGenParams reads its knob members

// The snapshot a worker (or the offline baker) carries instead of the live actor. Plain
// data, trivially copyable — exactly what Async() wants to capture by value. Mirrors
// AVoxelWorld::ConfigureGenerator but holds NO actor reference.
struct FGenParams
{
	int64   Seed = 0;
	float   MacroRange = 140.0f;
	int32   MidAmp = 14;
	int32   HeightOffset = 110;
	float   MacroFreq = 0.005f;
	int32   ChunkDepthBelow = 2;
	int32   SeaLevel = 120; // sea_level_voxels (= SeaLevelMeters × 10)
	bool    bUseEXR = false;
	const mira::ImageHeightmap* Heightmap = nullptr; // immutable during streaming/bake
	// Coarse far-generation (flag-gated). GenLod 0 = full-res (legacy/default);
	// GenLod L>0 generates this column directly at LOD L's resolution. bCoarseFarGen
	// is the master flag — when off, GenLod is always 0 and the fill is unchanged.
	int32   GenLod = 0;
	bool    bCoarseFarGen = false;
};

// Build a Core generator from a knob snapshot (mirrors AVoxelWorld::ConfigureGenerator,
// but reads NO actor members — safe to call from a worker thread OR the offline baker).
inline void BuildGen(const FGenParams& P, mira::HeightmapGenerator& Gen)
{
	Gen.set_seed(P.Seed);
	Gen.height_range_voxels  = P.MacroRange;
	Gen.mid_amplitude_voxels = P.MidAmp;
	Gen.height_offset_voxels = P.HeightOffset;
	Gen.macro_frequency      = P.MacroFreq;
	Gen.sea_level_voxels     = P.SeaLevel;
	if (P.bUseEXR && P.Heightmap && P.Heightmap->valid())
	{
		Gen.set_height_source(P.Heightmap);
	}
}

// Snapshot the world's CURRENT generator knobs into a plain FGenParams a worker (or the
// baker) can carry. Reads the knobs straight off the actor on the game thread; the
// resulting struct is then safe to copy into an Async() lambda. GenLod/bCoarseFarGen are
// passed in because the caller decides the desired gen resolution per column (the
// streaming ring) — super-chunks and the crust bake pass GenLod 0 / coarse-gen off since
// they sample at their own stride. This single definition keeps the live and bake
// generators byte-identical (seam alignment).
inline FGenParams SnapshotGenParams(const AVoxelWorld& W, int32 GenLod, bool bCoarseFarGen)
{
	FGenParams P;
	P.Seed            = W.Seed;
	P.MacroRange      = W.MacroRangeVoxels;
	P.MidAmp          = W.MidAmplitudeVoxels;
	P.HeightOffset    = W.HeightOffsetVoxels;
	P.MacroFreq       = W.MacroFrequency;
	P.ChunkDepthBelow = W.ChunkDepthBelow;
	const bool bUseEXR =
		(W.HeightSource == EVoxelHeightSource::HeightmapEXR && W.ImportedHeightmap.valid());
	P.bUseEXR    = bUseEXR;
	P.Heightmap  = bUseEXR ? &W.ImportedHeightmap : nullptr;
	// Sea level (voxels) from the designer knob (metres × 10 vox/m).
	P.SeaLevel   = FMath::RoundToInt(W.SeaLevelMeters * 10.0f);
	// Coarse far-generation: GenLod is the per-column desired gen resolution and
	// bCoarseFarGen is the master flag (off -> fill is full-res regardless of GenLod).
	P.GenLod         = GenLod;
	P.bCoarseFarGen  = bCoarseFarGen;
	return P;
}
