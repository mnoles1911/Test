// VoxelGpuMeshPass.h — the C++ that (eventually) dispatches the M8 GPU greedy mesh.
//
// WHAT THIS DOES (plain English):
//   Drives VoxelGreedyMesh.usf: hands a single apron'd slab (34^3 type bytes) to a
//   compute shader that builds the same quads mira::greedy_mesh builds on the CPU,
//   appending them into a GPU quad buffer that the readback test (or, later, the RMC
//   sink) consumes. The CPU GreedyMesher (test_mesher.cpp) is the parity oracle.
//
//   SCAFFOLD STATUS: the public API + the FGlobalShader parameter struct are REAL.
//   The Dispatch body is STUBBED (no actual RDG pass added) — the shader's inner
//   merge loop is itself a TODO, so there is nothing correct to run yet. Commented.

#pragma once

#include "CoreMinimal.h"
#include "RenderGraphResources.h"   // FRDGBufferRef / FRDGBuilder

#include "Core/VoxelChunk.h"        // mira::DenseGrid, MESH_SLAB_SIDE (34)

namespace MiraVoxelGPU
{
	// Inputs to one GPU mesh dispatch. The slab is the SAME apron'd 34^3 DenseGrid
	// the CPU mesher takes (Core/VoxelChunk.h), so the parity test feeds identical
	// data to both paths.
	struct FGpuMeshInput
	{
		const mira::DenseGrid* Slab = nullptr;   // apron'd slab; side must be 34
		// (chunk-local origin / LWC tile offset would be added here for placement;
		//  irrelevant to the mesh CONTENT the parity test checks, so omitted for now.)
	};

	// Output handles the caller binds for readback / upload.
	struct FGpuMeshOutput
	{
		FRDGBufferRef QuadBuffer = nullptr;       // AppendStructuredBuffer<FQuad>
		FRDGBufferRef QuadCountBuffer = nullptr;  // the append counter (for readback)
	};
}

// FVoxelGpuMeshPass — stateless dispatcher. Static so callers don't hold an instance.
class MIRATHALVOXELRENDER_API FVoxelGpuMeshPass
{
public:
	// Add the GPU greedy-mesh compute pass(es) to the RDG. Real version dispatches
	// VoxelGreedyMesh.usf once per face direction (6) over the slab and produces the
	// quad buffer. STUB: currently allocates nothing and logs a TODO — see the .cpp.
	//
	// VERIFY: the 6-direction split (one dispatch per FaceDir) vs a single dispatch
	// with dir looping inside — decide at bring-up; the CPU sweeps all 6 dirs.
	static void AddPass(FRDGBuilder& GraphBuilder,
	                   const MiraVoxelGPU::FGpuMeshInput& Input,
	                   MiraVoxelGPU::FGpuMeshOutput& OutOutput);
};
