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

	// --- AI diffusion DEM (Phase 1, additive) ---------------------------------
	// When the height source is the runtime AI DEM, Heightmap above already points at
	// the diffusion ImageHeightmap and bUseEXR is set true (it reuses the EXR plumbing
	// verbatim — same immutable-image socket BuildGen attaches). These extra fields
	// carry the diffusion IDENTITY so the fingerprint distinguishes an AI surface from
	// an EXR one even if their georef happened to match, and so a seed/region change is
	// caught by the stale-crust check. Zero/false on every non-diffusion path.
	bool    bDiffusionAI = false;        // height comes from an installed AI DEM
	int64   DiffusionSeed = 0;           // seed the DEM was generated from
	double  DiffusionRegionOriginX = 0.0;// region origin in world voxels (== image origin)
	double  DiffusionRegionOriginZ = 0.0;
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

// =============================================================================
// GENERATOR FINGERPRINT — a single number that identifies "which terrain shape".
//
// WHY THIS EXISTS (plain English):
// The baked far "crust" is frozen geometry. It only lines up with the live near
// voxels if BOTH were produced by the EXACT same generator settings. If a designer
// later nudges the seed, the sea level, the macro amplitude, etc., and forgets to
// re-bake, the crust silently stops matching the near voxels — a visible seam.
//
// To catch that, we boil ALL the seam-affecting generator knobs down into one
// 64-bit number (a "fingerprint"). The baker stamps this number into the manifest;
// the runtime recomputes it from the LIVE world and compares. Same number => same
// terrain => crust is valid. Different number => the crust was baked with stale
// settings => warn the designer to re-bake.
//
// The number is computed with FNV-1a, a tiny, well-known, deterministic hash: feed
// it bytes, it mixes them into a running 64-bit value. "Deterministic" is the whole
// point here — the SAME knobs must always give the SAME number, on any machine, in
// any process, this run or next month. (FNV-1a uses no randomness and no addresses,
// so it does.) It is NOT cryptographic — it's just a stable id, and that's all we need.
// =============================================================================

// FNV-1a step: fold one 64-bit chunk of data into the running hash. (Two magic
// constants are the standard 64-bit FNV offset/prime — don't change them or old
// fingerprints stop matching.)
inline void FingerprintMix(uint64& Hash, uint64 Value)
{
	// XOR the value in a byte at a time, multiplying by the FNV prime each step.
	for (int ByteIndex = 0; ByteIndex < 8; ++ByteIndex)
	{
		const uint8 Byte = static_cast<uint8>((Value >> (ByteIndex * 8)) & 0xFF);
		Hash ^= static_cast<uint64>(Byte);
		Hash *= 0x00000100000001B3ULL; // 64-bit FNV prime
	}
}

// Fold a float into the hash by its EXACT bit pattern (so two different floats that
// happen to be close still hash differently, and identical floats always match).
inline void FingerprintMixFloat(uint64& Hash, float Value)
{
	uint32 Bits = 0;
	FMemory::Memcpy(&Bits, &Value, sizeof(Bits)); // reinterpret the float's raw bits
	FingerprintMix(Hash, static_cast<uint64>(Bits));
}

// Same, for a double (the EXR heightmap's georef fields are doubles).
inline void FingerprintMixDouble(uint64& Hash, double Value)
{
	uint64 Bits = 0;
	FMemory::Memcpy(&Bits, &Value, sizeof(Bits));
	FingerprintMix(Hash, Bits);
}

// THE FINGERPRINT. Hash every FGenParams field that changes the GROUND HEIGHT or the
// surface MATERIAL — i.e. anything that could move the seam. Fields that only describe
// per-column gen RESOLUTION (GenLod, bCoarseFarGen) are deliberately EXCLUDED: the bake
// always runs them at 0/false and the live near band sets them per-column, so they say
// nothing about terrain SHAPE and including them would raise false "mismatch" alarms.
//
// Hashed fields (the seam-affecting set of FGenParams):
//   Seed            — the master noise seed (the biggest lever on shape)
//   MacroRange      — macro height range in voxels (overall relief amplitude)
//   MidAmp          — mid-octave amplitude in voxels
//   HeightOffset    — vertical offset of the whole surface in voxels
//   MacroFreq       — macro noise frequency (how stretched the big features are)
//   ChunkDepthBelow — how many chunks of solid fill sit below the surface
//   SeaLevel        — sea level in voxels (shoreline + water material boundary)
//   bUseEXR         — whether an imported Gaea heightmap drives the height at all
//   Heightmap georef (only when bUseEXR) — width/height/voxels_per_pixel/origin x,z/
//                     flip_z/vertical_scale/vertical_base: every knob that maps an
//                     image pixel to a ground voxel-Y. (We do NOT hash the raw pixel
//                     array — it can be millions of floats; the georef + the bUseEXR
//                     flag is the practical "which heightmap, mapped how" signal.)
inline uint64 FingerprintGenParams(const FGenParams& P)
{
	uint64 Hash = 0xCBF29CE484222325ULL; // 64-bit FNV offset basis (the starting value)

	FingerprintMix(Hash, static_cast<uint64>(P.Seed));
	FingerprintMixFloat(Hash, P.MacroRange);
	FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(P.MidAmp)));
	FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(P.HeightOffset)));
	FingerprintMixFloat(Hash, P.MacroFreq);
	FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(P.ChunkDepthBelow)));
	FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(P.SeaLevel)));
	FingerprintMix(Hash, P.bUseEXR ? 1ULL : 0ULL);

	// EXR heightmap georeferencing — only meaningful (and only present) when EXR is on.
	if (P.bUseEXR && P.Heightmap != nullptr)
	{
		const mira::ImageHeightmap& H = *P.Heightmap;
		FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(H.width)));
		FingerprintMix(Hash, static_cast<uint64>(static_cast<int64>(H.height)));
		FingerprintMixDouble(Hash, H.voxels_per_pixel);
		FingerprintMixDouble(Hash, H.origin_voxel_x);
		FingerprintMixDouble(Hash, H.origin_voxel_z);
		FingerprintMix(Hash, H.flip_z ? 1ULL : 0ULL);
		FingerprintMixDouble(Hash, H.vertical_scale_voxels);
		FingerprintMixDouble(Hash, H.vertical_base_voxels);
	}

	// AI diffusion DEM identity (additive). The georef above is already folded in via the
	// bUseEXR block (the diffusion path sets bUseEXR), so here we ONLY add what makes an AI
	// surface DISTINCT from an EXR one with the same georef: the generation SEED and the
	// region ORIGIN. Re-running the AI with a different seed/region (a different terrain
	// SHAPE) thus yields a different fingerprint, so a crust baked against the old DEM is
	// correctly flagged stale.
	//
	// IMPORTANT — only mixed when bDiffusionAI is set. We deliberately fold NOTHING for the
	// procedural/EXR paths so their fingerprints stay BYTE-IDENTICAL to before this change
	// (existing baked-crust manifests keep matching; no false "re-bake needed" alarms). A
	// diffusion surface is already distinct from an EXR one because it ALSO adds these extra
	// mixes, and distinct from procedural because it sets bUseEXR (running the georef block).
	if (P.bDiffusionAI)
	{
		FingerprintMix(Hash, static_cast<uint64>(P.DiffusionSeed));
		FingerprintMixDouble(Hash, P.DiffusionRegionOriginX);
		FingerprintMixDouble(Hash, P.DiffusionRegionOriginZ);
	}

	return Hash;
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
	// AI diffusion DEM: a runtime-installed ImageHeightmap. It feeds the SAME immutable-
	// image socket as the EXR path, so we just route Heightmap at it and set bUseEXR true
	// (BuildGen needs no change — it attaches whatever Heightmap points at). bDiffusionAI
	// records WHICH source so the fingerprint can tell them apart.
	const bool bUseDiffusion =
		(W.HeightSource == EVoxelHeightSource::DiffusionAI && W.DiffusionHeightmap.valid());
	P.bUseEXR    = bUseEXR || bUseDiffusion;
	P.Heightmap  = bUseEXR ? &W.ImportedHeightmap
	             : (bUseDiffusion ? &W.DiffusionHeightmap : nullptr);
	P.bDiffusionAI = bUseDiffusion;
	if (bUseDiffusion)
	{
		P.DiffusionSeed          = W.DiffusionSeed;
		P.DiffusionRegionOriginX = W.DiffusionHeightmap.origin_voxel_x;
		P.DiffusionRegionOriginZ = W.DiffusionHeightmap.origin_voxel_z;
	}
	// Sea level (voxels) from the designer knob (metres × 10 vox/m).
	P.SeaLevel   = FMath::RoundToInt(W.SeaLevelMeters * 10.0f);
	// Coarse far-generation: GenLod is the per-column desired gen resolution and
	// bCoarseFarGen is the master flag (off -> fill is full-res regardless of GenLod).
	P.GenLod         = GenLod;
	P.bCoarseFarGen  = bCoarseFarGen;
	return P;
}
