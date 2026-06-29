// MiraVoxelMesh.h — turn the Core's MeshBuffers into a UE ProceduralMesh.
//
// This is the seam between the engine-agnostic mesher and Unreal. The Core emits
// positions in VOXEL UNITS with a Y-UP basis (Godot heritage); UE is Z-UP and
// works in centimetres. So we (a) swap Y<->Z, (b) scale by 10 (1 voxel = 10 cm =
// 10 UE units), and (c) — because swapping two axes flips handedness — reverse
// triangle winding so faces point outward.
//
// M1 backend is UProceduralMeshComponent (built-in). When RealtimeMeshComponent
// swaps in later, only this file changes; the actor + Core stay put. (That's the
// future IVoxelMeshSink seam — kept as one function for now to keep M1 lean.)

#pragma once

#include "CoreMinimal.h"

namespace mira { struct MeshBuffers; }
class UProceduralMeshComponent;

namespace MiraVoxelMesh
{
	// 1 voxel = 10 cm = 10 UE units (UE unit = 1 cm; the world is 10 voxels/m).
	// Mirror of the Core VoxelScale; kept here as the one place the UE side scales.
	static constexpr float VoxelToUU = 10.0f;

	// Core (Y-up, voxel units) -> UE (Z-up, centimetres). Swap Y/Z, then scale.
	FORCEINLINE FVector PositionToUE(float px, float py, float pz)
	{
		return FVector(px, pz, py) * VoxelToUU;
	}
	// Normals get the same axis swap but no scale.
	FORCEINLINE FVector NormalToUE(float nx, float ny, float nz)
	{
		return FVector(nx, nz, ny);
	}

	// Build every populated section of `Mb` onto `Pmc` (PMC section index ==
	// FaceClass: 0 Opaque, 1 Cutout, 2 Water, 3 Flora). AO is written into vertex
	// color (grey). bReverseWinding flips triangle order for the handedness swap;
	// leave it true unless the chunk renders inside-out, then flip it (it's an
	// editor toggle on the actor so you can fix it without a recompile).
	// PositionScale multiplies every vertex position (after the voxel->UE scale), so a
	// downsampled LOD chunk (positions in COARSE-voxel units) renders at its true world
	// size — pass 2^Lod for a LOD chunk, 1.0 (default) for full-detail.
	//
	// DebugColor (DIAGNOSTIC, default null): when non-null, every vertex's RGB albedo is
	// REPLACED by this flat color (the per-LOD debug tint from mira::lod_debug_color) while
	// the per-vertex AO alpha is KEPT, so the LOD-color debug mode (cvar mira.LodDebug) reads
	// as a flat hue that still has the fake-AO shading. This is a RENDER override only —
	// nothing is written back to the Core MeshBuffers or the voxel/brick store. When null
	// (the default / cvar-off path) the vertex color is byte-for-byte the original albedo×AO.
	MIRATHALVOXEL_API void ApplyMeshBuffers(UProceduralMeshComponent* Pmc,
	                                        const mira::MeshBuffers& Mb,
	                                        bool bReverseWinding,
	                                        bool bCreateCollision,
	                                        float PositionScale = 1.0f,
	                                        const FColor* DebugColor = nullptr);
}
