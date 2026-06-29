// VoxelBrickGPUMirror.cpp — packs the sparse CPU Brickmap into flat GPU buffers.
//
// REAL: BuildPackedData walks the resident bricks and lays them out exactly as the
//       shader expects (see VoxelBrickGPUMirror.h for the layout contract).
// STUB: UploadToGPU is a documented no-op — it's where the RHI buffer creation goes.

#include "VoxelBrickGPUMirror.h"
#include "RenderGraphBuilder.h"

#include "Core/MaterialIds.h"   // mira::mat::AIR

using namespace MiraVoxelGPU;

void FVoxelBrickGPUMirror::BuildPackedData(const mira::Brickmap& Map,
                                          const mira::Vec3i& MinBrick,
                                          const mira::Vec3i& DimBricks)
{
	PackedData.Reset();
	PackedData.RegionMinBrick = MinBrick;
	PackedData.RegionDimBricks = DimBricks;

	const int32 NumSlots = DimBricks.x * DimBricks.y * DimBricks.z;
	if (NumSlots <= 0)
	{
		return; // empty / degenerate region
	}

	// Index has one entry per brick slot; default-constructed = non-resident (0).
	PackedData.BrickIndex.SetNum(NumSlots);

	// Walk every brick slot in the region. For each, ask the CPU Brickmap whether a
	// brick with SOLIDS exists there (brick_has_solid). If so, append its 512 type
	// bytes to the voxel buffer and mark the index entry resident with the offset.
	//
	// IMPORTANT layout parity (matches the shader + the CPU flatten):
	//   * brick-slot index:  bx + by*Dim.x + bz*Dim.x*Dim.y   (X-fastest)
	//   * voxel-within-brick: coords::flatten(lx,ly,lz, BRICK) (also X-fastest)
	// These are the SAME ordering rules the CPU Core uses, so a GPU readback of a
	// brick's bytes equals the CPU's byte order one-for-one (GpuParityPlan asserts it).
	uint32 ResidentCount = 0;
	for (int32 bz = 0; bz < DimBricks.z; ++bz)
	{
		for (int32 by = 0; by < DimBricks.y; ++by)
		{
			for (int32 bx = 0; bx < DimBricks.x; ++bx)
			{
				const mira::Vec3i BrickCoord{ MinBrick.x + bx, MinBrick.y + by, MinBrick.z + bz };

				// Only mirror bricks that actually have solid voxels — the march only
				// cares about solids, so an empty-but-present brick is stored as
				// non-resident (mirrors brick_has_solid, not bare has_brick).
				if (!Map.brick_has_solid(BrickCoord))
				{
					continue; // leave the index entry at its default (non-resident)
				}

				const int32 SlotIdx = bx + by * DimBricks.x + bz * DimBricks.x * DimBricks.y;

				// Reserve this brick's slice in the voxel buffer.
				const int32 SliceStart = PackedData.VoxelTypes.Num();
				PackedData.VoxelTypes.AddUninitialized(VoxelsPerBrick);

				// Copy the 512 type bytes in coords::flatten order. We read voxel-by-
				// voxel via the public type_at API (the Brick internals are private).
				const mira::Vec3i BrickOrigin = mira::coords::brick_origin_voxel(BrickCoord);
				for (int32 lz = 0; lz < BrickEdge; ++lz)
				{
					for (int32 ly = 0; ly < BrickEdge; ++ly)
					{
						for (int32 lx = 0; lx < BrickEdge; ++lx)
						{
							const int32 Local = mira::coords::flatten(lx, ly, lz, BrickEdge);
							const mira::Vec3i V{ BrickOrigin.x + lx, BrickOrigin.y + ly, BrickOrigin.z + lz };
							const uint8 Type = Map.type_at(V);
							PackedData.VoxelTypes[SliceStart + Local] = Type;
						}
					}
				}

				// DataOffset is in UNITS OF whole bricks (SliceStart / 512).
				const uint32 DataOffsetInBricks = static_cast<uint32>(SliceStart / VoxelsPerBrick);
				PackedData.BrickIndex[SlotIdx] = FBrickIndexEntry::MakeResident(DataOffsetInBricks);
				++ResidentCount;
			}
		}
	}

	// (No GPU work here — the packed CPU arrays are the deliverable of this step.)
	(void)ResidentCount;
}

void FVoxelBrickGPUMirror::UploadToGPU(FRDGBuilder& GraphBuilder)
{
	// =====================================================================
	// SCAFFOLD STUB — NOT A WORKING UPLOAD. Pending GPU verification.
	// =====================================================================
	//
	// What this method WILL do (M7 bring-up):
	//   1. Create (or refresh, if pooled) two GPU buffers from PackedData:
	//        BrickIndexBuffer  : structured buffer of uint32, NumBrickSlots() entries
	//        VoxelTypeBuffer   : byte-address (or uint-packed) buffer of the type bytes
	//   2. Upload PackedData.BrickIndex / PackedData.VoxelTypes into them.
	//   3. Stash the FRDGBufferRef handles so the raymarch pass binds them as SRVs.
	//
	// Sketch of the intended 5.7 calls (left commented — VERIFY each signature):
	//
	//   const FRDGBufferDesc IndexDesc = FRDGBufferDesc::CreateStructuredDesc(
	//       sizeof(uint32), FMath::Max(1, PackedData.BrickIndex.Num()));
	//   BrickIndexBuffer = GraphBuilder.CreateBuffer(IndexDesc, TEXT("MiraVoxel.BrickIndex"));
	//   GraphBuilder.QueueBufferUpload(BrickIndexBuffer, PackedData.BrickIndex.GetData(),
	//       PackedData.BrickIndex.Num() * sizeof(uint32));
	//
	//   // Voxel bytes -> a byte-address buffer the shader reads 4 bytes at a time, OR
	//   // repack to uint32 first. VERIFY which is cleaner on this build.
	//   const FRDGBufferDesc VoxelDesc = FRDGBufferDesc::CreateByteAddressDesc(
	//       FMath::Max(4, PackedData.VoxelTypes.Num()));
	//   VoxelTypeBuffer = GraphBuilder.CreateBuffer(VoxelDesc, TEXT("MiraVoxel.VoxelTypes"));
	//   GraphBuilder.QueueBufferUpload(VoxelTypeBuffer, PackedData.VoxelTypes.GetData(),
	//       PackedData.VoxelTypes.Num());
	//
	// VERIFY: FRDGBufferDesc::CreateStructuredDesc / CreateByteAddressDesc and
	//         FRDGBuilder::QueueBufferUpload signatures on UE 5.7 (RenderGraphBuilder.h).
	// VERIFY: for cross-frame persistence these should be POOLED buffers registered
	//         via GraphBuilder.RegisterExternalBuffer(TRefCountPtr<FRDGPooledBuffer>),
	//         not recreated every frame (the region buffer is large + mostly static).
	//
	// Until then this is a no-op so the module compiles and the packing path can be
	// unit-tested on the CPU side without a live RHI.
	(void)GraphBuilder;
	BrickIndexBuffer = nullptr;
	VoxelTypeBuffer = nullptr;
}
