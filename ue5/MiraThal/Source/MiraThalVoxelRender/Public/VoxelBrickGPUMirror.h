// VoxelBrickGPUMirror.h — the CPU-side object that mirrors the sparse Brickmap
// into GPU buffers for the M7 far-field ray-march (and, later, the M8 GPU mesher).
//
// WHAT THIS DOES (plain English):
//   The world's truth is mira::Brickmap — a sparse hash of 8x8x8 bricks living in
//   CPU RAM (see MiraThalVoxel/Public/Core/Brickmap.h). The GPU cannot read that
//   hash map. So this class walks the resident bricks and packs them into flat GPU
//   buffers the shader CAN read:
//
//     * a BRICK INDEX buffer — for every brick slot in a bounded region, "is there
//       a brick here, and does it have any solid voxels?" This is the coarse
//       skip-empty-bricks structure the two-level DDA keys off (mirrors the CPU
//       Brickmap::has_brick / brick_solid_count / brick_has_solid index).
//     * a VOXEL TYPE buffer — the 512 type bytes (material id, 0 = air) for each
//       resident brick, packed back-to-back. The shader walks these to find the
//       first solid voxel inside an occupied brick.
//
//   The shader then: marches the index buffer brick-by-brick (skipping empties),
//   and inside any occupied brick does an Amanatides-Woo voxel walk over its 512
//   type bytes — the exact two-level walk described in design/UE5_GPU_PHASES.md M7.
//
//   SCAFFOLD STATUS: the BUFFER LAYOUT and the PUBLIC API here are REAL and final.
//   The actual RHI upload (creating FRDGBuffer / pooled buffers and memcpy'ing the
//   packed data to the GPU) is STUBBED with a clear TODO. Nothing here touches the
//   GPU yet — BuildPackedData() fills CPU-side arrays; UploadToGPU() is the stub.

#pragma once

#include "CoreMinimal.h"
#include "RenderGraphResources.h"   // FRDGBufferRef / FRDGBuilder (used by the API)

// The CPU Core types. MiraThalVoxel puts Public/Core/* on the public include path,
// so these resolve exactly as they do inside the MiraThalVoxel module itself.
#include "Core/Brickmap.h"      // mira::Brickmap, mira::Vec3i
#include "Core/ChunkCoords.h"   // coords::BRICK, VOXELS_PER_BRICK, brick math

// ---------------------------------------------------------------------------
// GPU-SIDE LAYOUT CONSTANTS — these MUST stay in lockstep with the .usf shaders.
// The shader hard-codes 8 and 512 too; if BRICK ever changes, both sides change.
// ---------------------------------------------------------------------------
namespace MiraVoxelGPU
{
	// Edge of a brick in voxels — mirrors mira::coords::BRICK (8). static_assert
	// below pins them together so a Core change can't silently desync the shader.
	static constexpr int32 BrickEdge = 8;
	static constexpr int32 VoxelsPerBrick = BrickEdge * BrickEdge * BrickEdge; // 512

	static_assert(BrickEdge == mira::coords::BRICK, "GPU BrickEdge must match Core coords::BRICK");
	static_assert(VoxelsPerBrick == mira::coords::VOXELS_PER_BRICK, "GPU VoxelsPerBrick must match Core");

	// One entry in the BRICK INDEX buffer (one per brick slot in the mirrored region).
	// Packed as a single uint32 on the GPU; this struct documents the bit layout the
	// shader unpacks. We keep it tight (4 bytes) so a large region's index stays small.
	//
	//   bit 31      : RESIDENT  — 1 if a brick exists at this slot (CPU has_brick)
	//   bits 0..23  : DATA_OFFSET — index of this brick's first voxel byte in the
	//                 voxel type buffer, in UNITS OF VoxelsPerBrick (i.e. brick slot
	//                 number within the packed voxel buffer). 24 bits => up to 16M
	//                 resident bricks, far beyond any far-field region.
	//   bits 24..30 : reserved (future: solid_count bucket for finer skip). For now
	//                 the shader treats RESIDENT-with-solids via a separate test, so
	//                 we ALSO fold "has any solid" into bit 31 meaning: we only mark
	//                 RESIDENT for bricks that have solids (empty-but-present bricks
	//                 are stored as non-resident, since the march only cares about
	//                 solids — this matches brick_has_solid, not bare has_brick).
	struct FBrickIndexEntry
	{
		uint32 Packed = 0;

		static constexpr uint32 ResidentBit = 0x80000000u;
		static constexpr uint32 DataOffsetMask = 0x00FFFFFFu;

		static FBrickIndexEntry MakeResident(uint32 DataOffsetInBricks)
		{
			FBrickIndexEntry E;
			E.Packed = ResidentBit | (DataOffsetInBricks & DataOffsetMask);
			return E;
		}
		bool IsResident() const { return (Packed & ResidentBit) != 0; }
		uint32 DataOffset() const { return Packed & DataOffsetMask; }
	};

	// The CPU-side packed payload, ready to be memcpy'd into GPU buffers. BuildPackedData
	// fills these; UploadToGPU (stub) is what would push them to the RHI.
	struct FPackedBrickData
	{
		// The mirrored region, in BRICK coordinates: [RegionMinBrick, RegionMinBrick+RegionDimBricks).
		mira::Vec3i RegionMinBrick = {};
		mira::Vec3i RegionDimBricks = {};   // e.g. {64,64,64} bricks => 512^3 voxels

		// Brick index: RegionDimBricks.x*y*z entries, addressed
		//   idx = bx + by*Dim.x + bz*Dim.x*Dim.y   (X-fastest, matches coords::flatten)
		// so the shader's brick-slot math is identical to the CPU's flatten().
		TArray<FBrickIndexEntry> BrickIndex;

		// Voxel type bytes: VoxelsPerBrick (512) per resident brick, back-to-back, in
		// the SAME local order as the CPU brick (coords::flatten(lx,ly,lz, BRICK)).
		// A brick's slice starts at  entry.DataOffset() * VoxelsPerBrick.
		TArray<uint8> VoxelTypes;

		void Reset()
		{
			RegionMinBrick = {};
			RegionDimBricks = {};
			BrickIndex.Reset();
			VoxelTypes.Reset();
		}

		int32 NumBrickSlots() const
		{
			return RegionDimBricks.x * RegionDimBricks.y * RegionDimBricks.z;
		}
		int32 NumResidentBricks() const
		{
			return VoxelTypes.Num() / VoxelsPerBrick;
		}
	};
}

// ---------------------------------------------------------------------------
// FVoxelBrickGPUMirror — owns the packed data + (eventually) the GPU buffers.
//
// Lifetime: created once per far-field region; rebuilt (or incrementally updated)
// when bricks in that region change. The CPU Brickmap remains the truth; this is a
// derived, GPU-shaped copy.
// ---------------------------------------------------------------------------
class MIRATHALVOXELRENDER_API FVoxelBrickGPUMirror
{
public:
	FVoxelBrickGPUMirror() = default;
	~FVoxelBrickGPUMirror() = default;

	// Pack the resident bricks of `Map` inside the brick-space box
	// [MinBrick, MinBrick + DimBricks) into CPU-side flat arrays (PackedData).
	//
	// REAL: this is the layout/packing logic, written against the real Brickmap API
	// (has_brick / brick_has_solid / type_at). It produces exactly what the shader
	// expects. It does NOT touch the GPU.
	//
	// VERIFY (parity): the per-voxel local order written here MUST equal the order
	// the CPU uses internally (coords::flatten(local, BRICK)); the GpuParityPlan
	// readback test pins this. See VoxelBrickGPUMirror.cpp for the loop.
	void BuildPackedData(const mira::Brickmap& Map,
	                     const mira::Vec3i& MinBrick,
	                     const mira::Vec3i& DimBricks);

	// STUB: would create/refresh the GPU structured buffers from PackedData inside
	// the given RDG builder and store FRDGBufferRef handles for the shader pass to
	// bind. Currently a no-op with a TODO — see the .cpp.
	//
	// VERIFY: in UE 5.7 the typical pattern is CreateStructuredBuffer / CreateBuffer
	// on FRDGBuilder, then RegisterExternalBuffer for persistence across frames
	// (the index/voxel buffers are large and should be pooled, not rebuilt per frame).
	void UploadToGPU(FRDGBuilder& GraphBuilder);

	// Accessors the shader-pass setup reads. The FRDGBufferRef getters return null
	// until UploadToGPU is implemented (scaffold).
	const MiraVoxelGPU::FPackedBrickData& GetPackedData() const { return PackedData; }
	FRDGBufferRef GetBrickIndexBuffer() const { return BrickIndexBuffer; }
	FRDGBufferRef GetVoxelTypeBuffer() const { return VoxelTypeBuffer; }

	bool HasPackedData() const { return PackedData.NumBrickSlots() > 0; }

private:
	MiraVoxelGPU::FPackedBrickData PackedData;

	// SCAFFOLD: set by UploadToGPU once implemented; null in the scaffold.
	FRDGBufferRef BrickIndexBuffer = nullptr;
	FRDGBufferRef VoxelTypeBuffer = nullptr;
};
