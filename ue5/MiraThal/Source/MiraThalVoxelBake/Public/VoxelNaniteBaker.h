// VoxelNaniteBaker.h — M6 "Nanite cold-bake": voxel chunk -> Nanite UStaticMesh.
//
// WHAT THIS IS (plain English):
// The live voxel renderer (MiraThalVoxel module) draws each chunk with a
// ProceduralMeshComponent — great for chunks you're actively digging, because we
// can rebuild them instantly. But a chunk far away that nobody has touched in a
// while doesn't need to be editable. For those we "bake" the geometry once into a
// permanent UStaticMesh with NANITE enabled. Nanite then draws that mesh extremely
// cheaply at distance (it culls down to roughly one triangle per pixel).
//
// This file is a small LIBRARY (just free functions in a namespace, no objects to
// instantiate). The caller decides WHEN to bake and WHEN to swap — this file only
// knows HOW:
//
//   1. BuildNaniteStaticMeshFromSlab(...) — take a voxel slab (the same apron'd
//      DenseGrid the live mesher eats), greedy-mesh it, and produce a Nanite
//      UStaticMesh whose vertices/colors match the live mesh exactly.
//
//   2. SwapChunkToNanite(...) — attach a UStaticMeshComponent carrying that baked
//      mesh onto a chunk actor. (It does NOT hide/remove the old PMC — the caller
//      owns that policy, because deciding "is this chunk truly quiet?" is gameplay,
//      not rendering.)
//
// IMPORTANT — we reuse, we don't reinvent: the position swap (Y<->Z), the x10
// voxel->centimetre scale, and the vertex-color packing (rgb = baked albedo,
// alpha = ambient occlusion) all come straight from MiraVoxelMesh so a baked chunk
// is visually identical to a live one and uses the SAME terrain material.

#pragma once

#include "CoreMinimal.h"

// Forward declarations keep this header light (no heavy includes leak to callers).
namespace mira { struct MeshBuffers; }
class UStaticMesh;
class UStaticMeshComponent;
class UMaterialInterface;
class UObject;
class AActor;

namespace VoxelNaniteBaker
{
	// -----------------------------------------------------------------------
	// BuildNaniteStaticMeshFromMesh
	// -----------------------------------------------------------------------
	// Build a Nanite-enabled UStaticMesh from an ALREADY-MESHED chunk. The caller
	// (in MiraThalVoxel, which owns the Core mesher) greedy-meshes the apron'd slab
	// and passes the resulting MeshBuffers — we don't call the mesher here because that
	// Core .cpp isn't exported across the module boundary, and the caller usually has
	// the MeshBuffers in hand already from building the live PMC mesh.
	//
	//   Mb              — the greedy-mesh output (Opaque + Cutout faces, voxel units).
	//   TerrainMaterial — the terrain material to assign to every face section
	//                     (Opaque + Cutout share it, exactly like the live path).
	//                     May be null; the mesh still builds, just untextured.
	//   Outer           — the UObject that will own the new mesh (lifetime parent).
	//                     Use the chunk actor, its world, or GetTransientPackage().
	//   Name            — a name for the new asset (use NAME_None for an auto name).
	//
	// Returns the finished Nanite UStaticMesh, or nullptr if Mb had no visible geometry
	// (e.g. an all-air or fully-buried chunk produces zero faces).
	//
	// NOTE: only SOLID terrain should be in Mb (Opaque + Cutout). Water and flora are
	// intentionally skipped — they animate / are walk-through and belong on the live
	// path, not in a static cold-bake (matches the M6 spec).
	UStaticMesh* BuildNaniteStaticMeshFromMesh(const mira::MeshBuffers& Mb,
	                                           UMaterialInterface* TerrainMaterial,
	                                           UObject* Outer,
	                                           FName Name);

	// -----------------------------------------------------------------------
	// SwapChunkToNanite
	// -----------------------------------------------------------------------
	// Attach a freshly-created UStaticMeshComponent (carrying `BakedMesh`) to
	// `ChunkActor` and register it so it renders. Returns the new component, or
	// nullptr on bad input.
	//
	// This does the MECHANICAL swap-in only. It does NOT decide whether to bake, and
	// it does NOT hide or destroy the actor's existing ProceduralMeshComponent — the
	// caller drives that policy (e.g. after the bake settles, hide the PMC). Keeping
	// those decisions out here means this helper is safe to call from anywhere.
	UStaticMeshComponent* SwapChunkToNanite(AActor* ChunkActor, UStaticMesh* BakedMesh);
}
