// VoxelGpuMeshPass.cpp — dispatches VoxelGreedyMesh.usf (scaffold).
//
// REAL: the FGlobalShader declaration + parameter struct that BIND to the .usf, and
//       the public API. These pin the C++<->HLSL contract.
// STUB: AddPass does not actually add the RDG compute pass (the shader's merge loop
//       is itself a TODO). Documented no-op so the module compiles.

#include "VoxelGpuMeshPass.h"

#include "GlobalShader.h"
#include "ShaderParameterStruct.h"
#include "RenderGraphBuilder.h"
#include "RenderGraphUtils.h"
#include "DataDrivenShaderPlatformInfo.h"   // IsFeatureLevelSupported (RHI/Public; RHI dep)

// ---------------------------------------------------------------------------
// FVoxelGreedyMeshCS — the compute shader that runs VoxelGreedyMesh.usf::MainCS.
//
// VERIFY: every macro/signature here is the standard UE 5.7 global-shader idiom
// (DECLARE_GLOBAL_SHADER / SHADER_USE_PARAMETER_STRUCT / BEGIN_SHADER_PARAMETER_STRUCT).
// The parameter NAMES must match the .usf bindings exactly (SlabTypes, SweepDir,
// SweepAxis, OutQuads).
// ---------------------------------------------------------------------------
class FVoxelGreedyMeshCS : public FGlobalShader
{
public:
	DECLARE_GLOBAL_SHADER(FVoxelGreedyMeshCS);
	SHADER_USE_PARAMETER_STRUCT(FVoxelGreedyMeshCS, FGlobalShader);

	BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
		// Input slab type bytes (34^3), as a byte-address buffer SRV.
		SHADER_PARAMETER_RDG_BUFFER_SRV(ByteAddressBuffer, SlabTypes)
		SHADER_PARAMETER(int32, SweepDir)
		SHADER_PARAMETER(int32, SweepAxis)
		// Output append buffer of FQuad records (UAV).
		SHADER_PARAMETER_RDG_BUFFER_UAV(AppendStructuredBuffer<FQuad>, OutQuads)
	END_SHADER_PARAMETER_STRUCT()

	static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters)
	{
		// VERIFY: gate to SM5+ platforms (compute + structured buffers). Standard 5.7 check.
		return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
	}

	// Note: 'FQuad' referenced in the param struct is an HLSL struct in the .usf. The
	// C++ side here only needs the buffer to be a structured buffer of the right
	// stride; the readback/RMC code defines the matching C++ POD. VERIFY the UAV
	// template spelling compiles — if the macro rejects the templated append type,
	// declare it as SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<FQuad>, OutQuads)
	// plus a separate count buffer (append semantics via an explicit counter).
};

// Registering the shader binds the C++ class to the .usf entry point. VERIFY the
// virtual path resolves via the "/MiraVoxel" mapping done in module startup.
IMPLEMENT_GLOBAL_SHADER(FVoxelGreedyMeshCS, "/MiraVoxel/VoxelGreedyMesh.usf", "MainCS", SF_Compute);

void FVoxelGpuMeshPass::AddPass(FRDGBuilder& GraphBuilder,
                               const MiraVoxelGPU::FGpuMeshInput& Input,
                               MiraVoxelGPU::FGpuMeshOutput& OutOutput)
{
	// =====================================================================
	// SCAFFOLD STUB — NO DISPATCH. Pending GPU verification + the .usf merge loop.
	// =====================================================================
	//
	// What this WILL do (M8 bring-up):
	//   1. Validate Input.Slab (side == MESH_SLAB_SIDE == 34).
	//   2. Upload the slab's type bytes into a byte-address buffer.
	//   3. Create the OutQuads append buffer (+ its count buffer) sized to a safe
	//      upper bound (worst case 6 * 32*32 quads per slab before merging).
	//   4. For each of the 6 face directions, set FParameters (SlabTypes SRV,
	//      SweepDir, SweepAxis, OutQuads UAV) and FComputeShaderUtils::AddPass with
	//      a (1,1,1) group of [32,32,1] threads (one workgroup per slab/slice loop).
	//   5. Return QuadBuffer / QuadCountBuffer for readback (parity test) or RMC upload.
	//
	// Sketch (commented — VERIFY each 5.7 signature):
	//
	//   TShaderMapRef<FVoxelGreedyMeshCS> CS(GetGlobalShaderMap(GMaxRHIFeatureLevel));
	//   for (int32 Dir = 0; Dir < 6; ++Dir)
	//   {
	//       FVoxelGreedyMeshCS::FParameters* P =
	//           GraphBuilder.AllocParameters<FVoxelGreedyMeshCS::FParameters>();
	//       P->SlabTypes = GraphBuilder.CreateSRV(SlabBuffer);
	//       P->SweepDir = Dir;
	//       P->SweepAxis = Dir / 2;                 // -X/+X->0, -Y/+Y->1, -Z/+Z->2
	//       P->OutQuads = GraphBuilder.CreateUAV(QuadBuffer);
	//       FComputeShaderUtils::AddPass(GraphBuilder,
	//           RDG_EVENT_NAME("MiraVoxel.GpuGreedyMesh.Dir%d", Dir),
	//           CS, P, FIntVector(1, 1, 1));
	//   }
	//
	// Until the .usf merge loop is implemented + parity-verified, this is a no-op.
	(void)GraphBuilder;
	(void)Input;
	OutOutput.QuadBuffer = nullptr;
	OutOutput.QuadCountBuffer = nullptr;
}
