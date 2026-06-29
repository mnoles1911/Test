// MiraThalTerrainAI.cpp - module bootstrap for the LIVE-RUNTIME TerrainDiffusion system.
//
// Plain English: this is where the AI terrain brain will live. At runtime it will load the
// three diffusion neural nets (as ONNX, run via Unreal's NNE on the local GPU through
// DirectML), run the InfiniteDiffusion orchestration (ported to deterministic C++), and feed
// the resulting elevation heightmap (DEM) into the voxel world as a "height source" - exactly
// where imported EXR heightmaps plug in today. See design/TERRAIN_DIFFUSION_RUNTIME_PLAN.md.
//
// PHASE 1 SCAFFOLD: the module compiles, loads, and logs on startup. No inference is wired
// yet - this just establishes the module so the project links it and we can build on it.
#include "Modules/ModuleManager.h"
#include "Logging/LogMacros.h"

DEFINE_LOG_CATEGORY_STATIC(LogMiraTerrainAI, Log, All);

class FMiraThalTerrainAIModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		UE_LOG(LogMiraTerrainAI, Log,
			TEXT("[MiraThalTerrainAI] module loaded (scaffold - no inference wired yet)."));
	}

	virtual void ShutdownModule() override
	{
	}
};

IMPLEMENT_MODULE(FMiraThalTerrainAIModule, MiraThalTerrainAI);
