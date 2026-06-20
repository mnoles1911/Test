// MiraThalVoxelRender.Build.cs — the render-thread GPU module for the voxel world.
//
// WHAT THIS MODULE IS (plain English):
//   This is the brand-new GPU-side companion to MiraThalVoxel. It owns the two
//   "move it to the GPU" milestones from design/UE5_GPU_PHASES.md:
//     * M7 — far-field ray-march: instead of building geometry for the distant
//       world, we hand the GPU a mirror of the brick data and a shader marches a
//       ray per pixel to find the first solid voxel (the horizon renderer).
//     * M8 — GPU greedy mesh: a compute shader that builds the same quads the CPU
//       GreedyMesher builds, so streaming a huge map doesn't bottleneck the CPU.
//
//   IMPORTANT: this is a SCAFFOLD. It is wired to COMPILE and to carry the REAL
//   HLSL shaders + the real buffer layouts + the real public API. The actual RHI
//   uploads and render-pass dispatches are STUBBED with clear TODOs — the GPU
//   runtime behaviour is verified later with the designer, NOT claimed working now.
//
//   The CPU Core in MiraThalVoxel stays the single source of truth and the parity
//   oracle: Brickmap::raycast_solid (test_raymarch.cpp) for M7, GreedyMesher
//   (test_mesher.cpp) for M8. See Public/GpuParityPlan.md for the readback test plan.

using UnrealBuildTool;

public class MiraThalVoxelRender : ModuleRules
{
	public MiraThalVoxelRender(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"MiraThalVoxel",   // the CPU Core: Brickmap, GreedyMesher, VoxelColor, etc.
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"RenderCore",      // FGlobalShader, SHADER_PARAMETER_STRUCT, RDG types
			"RHI",             // FRHIBuffer / buffer descriptors / pixel formats
			"Renderer",        // RDG render-pass utils (FPixelShaderUtils / scene textures)
			"Projects",        // IPluginManager / FPaths for the shader dir mapping
		});

		// NOTE on FSceneViewExtensionBase: it actually lives in the ENGINE module
		// (it's ENGINE_API in Runtime/Engine/Public/SceneViewExtension.h), which we
		// already depend on publicly — so the SVE subclass compiles WITHOUT "Renderer".
		// "Renderer" is kept here for the RDG dispatch helpers the (stubbed) passes use
		// at bring-up. VERIFY: if "Renderer" is rejected as a Runtime-module dependency
		// on this custom 5.7 build, the scaffold still compiles without it (the SVE base
		// and RDG buffer types come from Engine + RenderCore); drop it and re-add only
		// the specific pass helper headers when the dispatches are implemented.

		// ---------------------------------------------------------------------
		// LOADING PHASE — why this module must load EARLY.
		//
		// Two independent reasons push this module's LoadingPhase earlier than the
		// default ("Default", which loads after the engine is mostly up):
		//
		//   1. AddShaderSourceDirectoryMapping("/MiraVoxel", ...) must run BEFORE the
		//      shader compiler processes any .usf that references our virtual path.
		//      The conventional, safe phase for a shader-providing module is
		//      PostConfigInit — it loads before the shader system finishes init.
		//
		//   2. FSceneViewExtensions are normally registered at/after engine init,
		//      which "Default" supports — but because we ALSO map shaders, we set
		//      the whole module to PostConfigInit so both happen in one early pass.
		//
		// VERIFY: the .uproject (which the PARENT wires, not this scaffold) must list
		// this module with  "LoadingPhase": "PostConfigInit".  This .Build.cs cannot
		// set LoadingPhase itself — that field lives in the .uproject/.uplugin module
		// descriptor, NOT in ModuleRules. Documenting it here so the parent sets it.
		// VERIFY: confirm "Renderer" is an allowed dependency for a Runtime module on
		// this custom 5.7 source build (it is on stock 5.x; custom builds occasionally
		// gate it). If the linker rejects it, the SceneViewExtension base may need to
		// be reached via "RenderCore" + a minimal re-decl, but stock 5.7 exposes it.
		// ---------------------------------------------------------------------
	}
}
