// MiraThalVoxelRender.cpp — module bootstrap for the GPU voxel render module.
//
// Two jobs at startup:
//   1. IMPLEMENT_MODULE so the engine can load us.
//   2. Map the virtual shader path "/MiraVoxel" to this module's Shaders/ folder so
//      our .usf files (VoxelRaymarch.usf, VoxelGreedyMesh.usf) resolve when the
//      shader compiler #includes them as "/MiraVoxel/VoxelRaymarch.usf".
//
// SCAFFOLD STATUS: the module loads and maps shaders for real. It does NOT yet
// register the SceneViewExtension or create any GPU resources — that wiring is
// commented below and left to the parent once the GPU path is being brought up.

#include "Modules/ModuleManager.h"
#include "Misc/Paths.h"
#include "ShaderCore.h"                 // AddShaderSourceDirectoryMapping
#include "Interfaces/IPluginManager.h"  // (only needed if we lived in a plugin)

// We deliberately keep the module class concrete (not FDefaultModuleImpl) so we
// have a StartupModule hook to register the shader directory.
class FMiraThalVoxelRenderModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		// ---------------------------------------------------------------------
		// Map the virtual shader directory "/MiraVoxel" -> <ThisModule>/Shaders.
		//
		// The .usf files live next to this module under Shaders/. The shader system
		// only understands VIRTUAL paths, so we register the mapping here, once, at
		// startup. After this, any global shader that does
		//   #include "/MiraVoxel/VoxelRaymarch.usf"
		// resolves to Source/MiraThalVoxelRender/Shaders/VoxelRaymarch.usf.
		//
		// VERIFY (UE 5.7 API): the canonical way to find a Source-tree module's dir
		// is FPaths::Combine(FPaths::ProjectDir(), TEXT("Source/MiraThalVoxelRender"))
		// or, more robustly, FModuleManager::Get().GetModuleFilename + parent dirs.
		// For an in-PROJECT module (this is one), ProjectDir()/Source/<Module> is
		// stable. If this ever becomes a plugin, switch to
		// IPluginManager::Get().FindPlugin(...)->GetBaseDir() / "Shaders".
		// ---------------------------------------------------------------------
		const FString ShaderDir = FPaths::Combine(
			FPaths::ProjectDir(),
			TEXT("Source"), TEXT("MiraThalVoxelRender"), TEXT("Shaders"));

		// AddShaderSourceDirectoryMapping is idempotent-safe to call once at startup.
		// VERIFY: signature is AddShaderSourceDirectoryMapping(const FString& VirtualPath,
		// const FString& RealPath) in UE 5.7 (ShaderCore.h). Stable since UE4.17-ish.
		if (!AllShaderSourceDirectoryMappings().Contains(TEXT("/MiraVoxel")))
		{
			AddShaderSourceDirectoryMapping(TEXT("/MiraVoxel"), ShaderDir);
		}

		// ---------------------------------------------------------------------
		// SCAFFOLD TODO (M7 bring-up): register the far-field ray-march view
		// extension here so the renderer calls our post-opaque hook each frame:
		//
		//   RaymarchSceneViewExtension =
		//       FSceneViewExtensions::NewExtension<FVoxelRaymarchSceneViewExtension>();
		//
		// Left commented because (a) nothing yet feeds it a GPU brick mirror, and
		// (b) registering a no-op extension that dispatches nothing only adds render-
		// thread overhead. The class exists and compiles (see
		// VoxelRaymarchSceneViewExtension.h) — it just isn't wired live yet.
		// VERIFY: FSceneViewExtensions::NewExtension<T>(Args...) is the 5.7 factory;
		// it returns a TSharedRef<T, ESPMode::ThreadSafe> and self-registers.
		// ---------------------------------------------------------------------
	}

	virtual void ShutdownModule() override
	{
		// SCAFFOLD: when the view extension is registered for real, drop our shared
		// ref here so it unregisters:  RaymarchSceneViewExtension.Reset();
		// The shader directory mapping does not need manual teardown.
	}

	// SCAFFOLD: holds the live view extension once M7 is wired (kept as a shared ref
	// so the renderer's weak list can co-own it). Unused until registration above.
	// TSharedPtr<class FVoxelRaymarchSceneViewExtension, ESPMode::ThreadSafe> RaymarchSceneViewExtension;
};

IMPLEMENT_MODULE(FMiraThalVoxelRenderModule, MiraThalVoxelRender);
