// NNEUNetRunner.h - the REAL runner: runs the diffusion UNets on the local GPU via NNE.
//
// PLAIN ENGLISH:
// This is the concrete implementation of ITdiffUNetRunner (see TdiffUNetRunner.h). It uses
// Unreal's Neural Network Engine (NNE) with the ONNX Runtime backend and the DirectML
// execution provider - the inference path that runs on an AMD GPU (this box is an RX 7800
// XT, no CUDA). If the DirectML GPU runtime isn't available for some reason, it falls back
// to the ONNX Runtime CPU runtime so the pipeline still produces correct numbers (just
// slower) - and logs loudly which one ran.
//
// HOW IT FINDS / LOADS A MODEL (verified against the UE 5.7 NNE plugin source):
//   1. Read the raw .onnx file bytes off disk (FFileHelper / IFileManager).
//   2. Build a UNNEModelData at runtime via NewObject<UNNEModelData>() + ModelData->Init("onnx", Bytes).
//      This is the HEADLESS path: no pre-imported .uasset is required, which is exactly what a
//      commandlet needs. (In an *editor* process - which is what UnrealEditor-Cmd is - NNE
//      optimizes/caches the model on the fly via the DDC. In a cooked standalone game you would
//      instead ship a pre-imported UNNEModelData asset, because Init's file bytes are editor-only.)
//   3. Get the runtime by name: UE::NNE::GetRuntime<INNERuntimeGPU>("NNERuntimeORTDml").
//   4. runtime->CreateModelGPU(ModelData) -> model->CreateModelInstanceGPU() -> a run-able instance.
//
// The heavy NNE / UObject types stay OUT of this header (only forward declarations) so files
// that just want to *use* a runner don't drag in the whole engine.
#pragma once

#include "CoreMinimal.h"
#include "UObject/StrongObjectPtr.h"
#include "Templates/SharedPointer.h"
#include "TdiffUNetRunner.h"

// A dedicated log category for the AI-terrain INFERENCE path, shared by the runner and the
// Gate-1 commandlet. Defined in NNEUNetRunner.cpp.
//
// NOTE ON THE NAME: the brief asked for "LogMiraTerrainAI", but the module bootstrap
// (MiraThalTerrainAI.cpp - which is outside this task's file ownership) ALREADY defines a
// file-local `DEFINE_LOG_CATEGORY_STATIC(LogMiraTerrainAI)`. Because UnrealBuildTool compiles
// modules with "unity" builds (several .cpp files concatenated into one translation unit), a
// second module-wide `DEFINE_LOG_CATEGORY(LogMiraTerrainAI)` would land in the SAME TU as that
// static one and fail to compile (redefinition of the same category struct + variable). So this
// shared category is named `LogMiraTerrainNNE` to be collision-proof. Logs still clearly read as
// the terrain-AI/NNE path. (If the bootstrap's category is later promoted to a shared extern,
// this can be folded into it.)
DECLARE_LOG_CATEGORY_EXTERN(LogMiraTerrainNNE, Log, All);

// Forward declarations - keep NNE headers in the .cpp only.
class UNNEModelData;
namespace UE { namespace NNE {
	class IModelGPU;
	class IModelCPU;
	class IModelInstanceRunSync;
} }

namespace mira
{
namespace tdiff
{
	/**
	 * NNE-backed runner. Construct it once (pointing at the folder of .onnx files), then call
	 * Run() as many times as you like - models are loaded lazily on first use and cached.
	 *
	 * Threading note: create + use this on the game thread inside the commandlet. (RunSync
	 * blocks until inference finishes; that's fine for Gate 1.)
	 */
	class FNNEUNetRunner : public ITdiffUNetRunner
	{
	public:
		/**
		 * @param InOnnxDir Absolute path to the folder containing coarse_model.onnx /
		 *                  base_model.onnx / decoder_model.onnx.
		 */
		explicit FNNEUNetRunner(const FString& InOnnxDir);
		virtual ~FNNEUNetRunner();

		// --- ITdiffUNetRunner ---
		virtual bool Run(EUNetModel Model,
		                 TConstArrayView<FTensorData> Inputs,
		                 TConstArrayView<TArray<int32>> ExpectedOutputShapes,
		                 TArray<FTensorData>& OutOutputs) override;
		virtual const TCHAR* GetBackendName() const override;

		/** Force-load a model now (otherwise it loads lazily on first Run). Returns true on success. */
		bool EnsureModelLoaded(EUNetModel Model);

	private:
		/** Which backend a loaded model is actually running on. */
		enum class EBackend : uint8
		{
			None,
			GpuDirectML,   // NNERuntimeORTDml  - the AMD GPU path
			CpuOrt         // NNERuntimeORTCpu  - the CPU fallback
		};

		/** Everything we keep alive for one loaded model. */
		struct FLoadedModel
		{
			// We must keep the IModel* alive for as long as its instance lives (the instance can
			// share weights owned by the IModel). Only one of GPU/CPU is set, matching Backend.
			TSharedPtr<UE::NNE::IModelGPU>            ModelGpu;
			TSharedPtr<UE::NNE::IModelCPU>            ModelCpu;
			TSharedPtr<UE::NNE::IModelInstanceRunSync> Instance;   // the thing we actually RunSync() on
			EBackend                                  Backend = EBackend::None;

			bool IsValid() const { return Instance.IsValid(); }
		};

		/** Loads + caches one model. No-op if already loaded. */
		bool LoadModel(EUNetModel Model, FLoadedModel& OutLoaded);

		/** Absolute .onnx path for a model, e.g. <OnnxDir>/coarse_model.onnx. */
		FString GetOnnxPath(EUNetModel Model) const;

		FString OnnxDir;

		// Cache, indexed by (int)EUNetModel. 3 slots: Coarse, Base, Decoder.
		FLoadedModel Loaded[3];

		// Backend of the most recently RUN model - drives GetBackendName().
		mutable EBackend LastBackend = EBackend::None;
	};

} // namespace tdiff
} // namespace mira
