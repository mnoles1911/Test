// MiraThalTerrainAI.Build.cs - the LIVE-RUNTIME TerrainDiffusion module.
//
// WHAT THIS MODULE IS FOR (plain English):
// This is the "AI terrain brain." At runtime it loads three small diffusion neural
// networks (exported to ONNX) and runs them ON THE LOCAL GPU through Unreal's Neural
// Network Engine (NNE) using the ONNX Runtime + DirectML backend - the path that works
// on AMD cards with no CUDA. It runs the ported "InfiniteDiffusion" orchestration to
// turn (seed + region) into a realistic elevation heightmap (a DEM), then feeds that
// elevation into the voxel world as a "height source" - exactly the socket that imported
// Gaea/EXR heightmaps plug into today (mira::HeightmapGenerator::compute_ground_y).
//
// It is a RUNTIME module (terrain is generated live as the player explores). The pure,
// engine-agnostic orchestration + RNG live in the MiraThalVoxel Core (namespace
// mira::tdiff) so the standalone clang harness can unit-test them WITHOUT a GPU; this
// module supplies the real NNE-backed network runner and the async DEM service.
//
// See design/TERRAIN_DIFFUSION_RUNTIME_PLAN.md for the full phase plan.
using UnrealBuildTool;

public class MiraThalTerrainAI : ModuleRules
{
	public MiraThalTerrainAI(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"MiraThalVoxel",   // engine-agnostic Core: HeightmapGenerator / ImageHeightmap / FGenParams seam
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"NNE",             // Neural Network Engine public API: load ONNX -> run on GPU/CPU.
			                   // The concrete runtime (NNERuntimeORT + DirectML EP) is discovered
			                   // by name at runtime via UE::NNE::GetRuntime("NNERuntimeORT...").
			"RenderCore",      // RDG / render-data plumbing (used when we add the RDG path later)
			"RHI",             // GPU buffers / device queries (VRAM budgeting)
			"Renderer",        // RDG utilities
			"Projects",        // FPaths / plugin + content dirs for locating the model assets
		});
	}
}
