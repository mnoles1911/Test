// NNEUNetRunner.cpp - GPU (DirectML) inference for the diffusion UNets, via Unreal's NNE.
//
// See NNEUNetRunner.h for the high-level "what / why". This file is the nuts and bolts:
// how we load an .onnx, pick the runtime, bind buffers, and call RunSync.
//
// API REFERENCE (all verified against the engine source in this build, UE 5.7):
//   Engine/Source/Runtime/NNE/Public/NNE.h ............. UE::NNE::GetRuntime<T>(Name)
//   .../NNERuntimeGPU.h ................................ INNERuntimeGPU::CreateModelGPU,
//                                                       IModelGPU::CreateModelInstanceGPU
//   .../NNERuntimeCPU.h ............................... INNERuntimeCPU::CreateModelCPU,
//                                                       IModelCPU::CreateModelInstanceCPU
//   .../NNERuntimeRunSync.h ........................... IModelInstanceRunSync (GetInput/OutputTensorDescs,
//                                                       SetInputTensorShapes, RunSync), FTensorBindingCPU
//   .../NNETypes.h ................................... FTensorShape, FTensorDesc, ENNETensorDataType
//   .../NNEModelData.h ............................... UNNEModelData::Init("onnx", bytes)
//   .../NNEStatus.h ................................. UE::NNE::EResultStatus { Ok, Fail }
//   Plugins/NNE/NNERuntimeORT/Source/.../NNERuntimeORT.cpp confirms the registered runtime
//     NAMES: GPU/DirectML = "NNERuntimeORTDml", CPU = "NNERuntimeORTCpu", and that the
//     accepted file-type string for Init() is "onnx" (case-insensitive).

#include "NNEUNetRunner.h"

// NNE public API
#include "NNE.h"
#include "NNEModelData.h"
#include "NNERuntimeGPU.h"
#include "NNERuntimeCPU.h"
#include "NNERuntimeRunSync.h"
#include "NNETypes.h"
#include "NNEStatus.h"

// Engine helpers
#include "UObject/WeakInterfacePtr.h"
#include "UObject/UObjectGlobals.h"   // NewObject
#include "HAL/FileManager.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"

// The shared log category for the AI-terrain inference path (declared extern in the header).
DEFINE_LOG_CATEGORY(LogMiraTerrainNNE);

namespace mira
{
namespace tdiff
{

// Registered runtime name strings (see NNERuntimeORT.cpp GetRuntimeName()).
static const TCHAR* GRuntimeNameDml = TEXT("NNERuntimeORTDml");
static const TCHAR* GRuntimeNameCpu = TEXT("NNERuntimeORTCpu");

// ---------------------------------------------------------------------------------------------
// Small file helper: read a whole file into a 64-bit-indexed byte array.
// We deliberately use TArray64 (not FFileHelper::LoadFileToArray, which is 32-bit indexed)
// because base_model.onnx is ~1.9 GB - dangerously close to the 2^31 byte ceiling of a normal
// TArray. A 64-bit buffer removes that cliff entirely.
// ---------------------------------------------------------------------------------------------
static bool LoadWholeFile64(const FString& Path, TArray64<uint8>& Out)
{
	TUniquePtr<FArchive> Reader(IFileManager::Get().CreateFileReader(*Path));
	if (!Reader)
	{
		return false;
	}
	const int64 Size = Reader->TotalSize();
	if (Size <= 0)
	{
		return false;
	}
	Out.SetNumUninitialized(Size);
	Reader->Serialize(Out.GetData(), Size);
	const bool bClosedOk = Reader->Close();
	return bClosedOk && (Out.Num() == Size);
}

// ---------------------------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------------------------
FNNEUNetRunner::FNNEUNetRunner(const FString& InOnnxDir)
	: OnnxDir(InOnnxDir)
{
	UE_LOG(LogMiraTerrainNNE, Log, TEXT("[NNEUNetRunner] created. ONNX dir: %s"), *OnnxDir);
}

FNNEUNetRunner::~FNNEUNetRunner()
{
	// TSharedPtr members release the NNE model instances automatically.
}

FString FNNEUNetRunner::GetOnnxPath(EUNetModel Model) const
{
	return FPaths::Combine(OnnxDir, FString::Printf(TEXT("%s.onnx"), GetModelStem(Model)));
}

const TCHAR* FNNEUNetRunner::GetBackendName() const
{
	switch (LastBackend)
	{
	case EBackend::GpuDirectML: return TEXT("NNE ORT DirectML (GPU)");
	case EBackend::CpuOrt:      return TEXT("NNE ORT (CPU fallback)");
	default:                    return TEXT("none");
	}
}

// ---------------------------------------------------------------------------------------------
// Model loading: bytes -> UNNEModelData -> runtime -> model -> instance.
// Tries the DirectML GPU runtime first, then falls back to the CPU runtime.
// ---------------------------------------------------------------------------------------------
bool FNNEUNetRunner::LoadModel(EUNetModel Model, FLoadedModel& OutLoaded)
{
	const FString Path = GetOnnxPath(Model);
	const TCHAR* Stem = GetModelStem(Model);

	if (!IFileManager::Get().FileExists(*Path))
	{
		UE_LOG(LogMiraTerrainNNE, Error, TEXT("[NNEUNetRunner] '%s': ONNX file not found: %s"), Stem, *Path);
		return false;
	}

	// 1) Read the raw .onnx bytes.
	TArray64<uint8> FileBytes;
	if (!LoadWholeFile64(Path, FileBytes))
	{
		UE_LOG(LogMiraTerrainNNE, Error, TEXT("[NNEUNetRunner] '%s': failed to read ONNX bytes: %s"), Stem, *Path);
		return false;
	}
	UE_LOG(LogMiraTerrainNNE, Log, TEXT("[NNEUNetRunner] '%s': read %lld bytes from %s"),
		Stem, (long long)FileBytes.Num(), *Path);

	// 2) Build a UNNEModelData at runtime from those bytes (headless - no pre-imported asset).
	//    Keep it rooted (TStrongObjectPtr) for the duration of model creation so GC can't eat it.
	TStrongObjectPtr<UNNEModelData> ModelData(NewObject<UNNEModelData>());
	if (!ModelData.IsValid())
	{
		UE_LOG(LogMiraTerrainNNE, Error, TEXT("[NNEUNetRunner] '%s': NewObject<UNNEModelData> failed"), Stem);
		return false;
	}
	ModelData->Init(TEXT("onnx"), FileBytes);

	// 3) Try the GPU / DirectML runtime first.
	{
		TWeakInterfacePtr<INNERuntimeGPU> RtGpu = UE::NNE::GetRuntime<INNERuntimeGPU>(GRuntimeNameDml);
		if (RtGpu.IsValid())
		{
			INNERuntimeGPU* Rt = RtGpu.Get();
			if (Rt->CanCreateModelGPU(ModelData.Get()) == UE::NNE::EResultStatus::Ok)
			{
				TSharedPtr<UE::NNE::IModelGPU> ModelGpu = Rt->CreateModelGPU(ModelData.Get());
				if (ModelGpu.IsValid())
				{
					TSharedPtr<UE::NNE::IModelInstanceGPU> Inst = ModelGpu->CreateModelInstanceGPU();
					if (Inst.IsValid())
					{
						OutLoaded.ModelGpu = ModelGpu;
						OutLoaded.Instance = Inst;   // upcast IModelInstanceGPU -> IModelInstanceRunSync
						OutLoaded.Backend  = EBackend::GpuDirectML;
						UE_LOG(LogMiraTerrainNNE, Log,
							TEXT("[NNEUNetRunner] '%s': loaded on GPU via %s (DirectML)."), Stem, GRuntimeNameDml);
						return true;
					}
				}
			}
			UE_LOG(LogMiraTerrainNNE, Warning,
				TEXT("[NNEUNetRunner] '%s': '%s' present but could not create a GPU model - trying CPU."),
				Stem, GRuntimeNameDml);
		}
		else
		{
			UE_LOG(LogMiraTerrainNNE, Warning,
				TEXT("[NNEUNetRunner] '%s': GPU runtime '%s' not available - trying CPU. "
				     "(Is the NNERuntimeORT plugin enabled and DirectML.dll present?)"),
				Stem, GRuntimeNameDml);
		}
	}

	// 4) Fall back to the CPU / ORT runtime (still correct numbers, just slower).
	{
		TWeakInterfacePtr<INNERuntimeCPU> RtCpu = UE::NNE::GetRuntime<INNERuntimeCPU>(GRuntimeNameCpu);
		if (RtCpu.IsValid())
		{
			INNERuntimeCPU* Rt = RtCpu.Get();
			if (Rt->CanCreateModelCPU(ModelData.Get()) == UE::NNE::EResultStatus::Ok)
			{
				TSharedPtr<UE::NNE::IModelCPU> ModelCpu = Rt->CreateModelCPU(ModelData.Get());
				if (ModelCpu.IsValid())
				{
					TSharedPtr<UE::NNE::IModelInstanceCPU> Inst = ModelCpu->CreateModelInstanceCPU();
					if (Inst.IsValid())
					{
						OutLoaded.ModelCpu = ModelCpu;
						OutLoaded.Instance = Inst;   // upcast IModelInstanceCPU -> IModelInstanceRunSync
						OutLoaded.Backend  = EBackend::CpuOrt;
						UE_LOG(LogMiraTerrainNNE, Warning,
							TEXT("[NNEUNetRunner] '%s': loaded on CPU via %s (DirectML GPU unavailable)."),
							Stem, GRuntimeNameCpu);
						return true;
					}
				}
			}
		}
	}

	UE_LOG(LogMiraTerrainNNE, Error,
		TEXT("[NNEUNetRunner] '%s': could not create a model on ANY NNE runtime."), Stem);
	// List what IS registered, to make diagnosis easy.
	for (const FString& Name : UE::NNE::GetAllRuntimeNames())
	{
		UE_LOG(LogMiraTerrainNNE, Log, TEXT("[NNEUNetRunner]   registered runtime: %s"), *Name);
	}
	return false;
}

bool FNNEUNetRunner::EnsureModelLoaded(EUNetModel Model)
{
	const int32 Idx = static_cast<int32>(Model);
	if (Loaded[Idx].IsValid())
	{
		return true;
	}
	return LoadModel(Model, Loaded[Idx]);
}

// ---------------------------------------------------------------------------------------------
// Inference.
// ---------------------------------------------------------------------------------------------
bool FNNEUNetRunner::Run(EUNetModel Model,
                         TConstArrayView<FTensorData> Inputs,
                         TConstArrayView<TArray<int32>> ExpectedOutputShapes,
                         TArray<FTensorData>& OutOutputs)
{
	OutOutputs.Reset();

	if (!EnsureModelLoaded(Model))
	{
		return false;
	}

	const int32 Idx = static_cast<int32>(Model);
	FLoadedModel& LM = Loaded[Idx];
	LastBackend = LM.Backend;
	const TCHAR* Stem = GetModelStem(Model);

	UE::NNE::IModelInstanceRunSync* Inst = LM.Instance.Get();
	check(Inst);

	// --- 1) Sanity-check input count against what the model declares. ---
	TConstArrayView<UE::NNE::FTensorDesc> InDescs = Inst->GetInputTensorDescs();
	if (Inputs.Num() != InDescs.Num())
	{
		UE_LOG(LogMiraTerrainNNE, Error,
			TEXT("[NNEUNetRunner] '%s': input count mismatch - model expects %d, caller gave %d."),
			Stem, InDescs.Num(), Inputs.Num());
		return false;
	}

	// --- 2) Tell the model the concrete input shapes (mandatory before RunSync). ---
	TArray<UE::NNE::FTensorShape> InputShapes;
	InputShapes.Reserve(Inputs.Num());
	for (int32 i = 0; i < Inputs.Num(); ++i)
	{
		const FTensorData& In = Inputs[i];
		if (!In.IsConsistent())
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[NNEUNetRunner] '%s': input %d ('%s') has %d floats but shape volume %lld."),
				Stem, i, *InDescs[i].GetName(), In.Values.Num(), (long long)In.Volume());
			return false;
		}
		// FTensorShape dims are uint32; our POD shape is int32.
		TArray<uint32> Dims;
		Dims.Reserve(In.Shape.Num());
		for (int32 D : In.Shape)
		{
			Dims.Add(static_cast<uint32>(D));
		}
		InputShapes.Add(UE::NNE::FTensorShape::Make(Dims));
	}

	if (Inst->SetInputTensorShapes(InputShapes) != UE::NNE::EResultStatus::Ok)
	{
		UE_LOG(LogMiraTerrainNNE, Error, TEXT("[NNEUNetRunner] '%s': SetInputTensorShapes failed."), Stem);
		return false;
	}

	// --- 3) Decide the output shapes to ALLOCATE + BIND.
	//
	// Our ONNX models were exported with dynamic axes, so after SetInputTensorShapes the ORT
	// runtime usually CANNOT resolve the output shape yet: GetOutputTensorShapes() returns an
	// EMPTY array (verified in NNERuntimeORTModel.cpp::SetInputTensorShapes - it only fills the
	// output shapes when every output is statically concrete). The true shape only becomes known
	// once the graph has actually run.
	//
	// That's fine: ORT's RunSync still works if we hand it an output binding whose buffer is at
	// least as big as the real output - it allocates internally, runs, then memcpy's the result
	// into our buffer (NNERuntimeORTModel.cpp::RunSync, lines ~456-475). So we size the buffer
	// from the *expected* output shapes the caller passes in (it knows them: golden capture /
	// input batch). If the model DID resolve concrete shapes, we trust those instead.
	const int32 NumOut = Inst->GetOutputTensorDescs().Num();

	// Are the runtime-reported output shapes already concrete & usable?
	TConstArrayView<UE::NNE::FTensorShape> ResolvedShapes = Inst->GetOutputTensorShapes();
	bool bModelResolvedShapes = (ResolvedShapes.Num() == NumOut);
	if (bModelResolvedShapes)
	{
		for (const UE::NNE::FTensorShape& S : ResolvedShapes)
		{
			if (S.Volume() == 0)   // 0 means a dim was 0/unresolved -> not usable
			{
				bModelResolvedShapes = false;
				break;
			}
		}
	}

	// Build the per-output shapes we will allocate from.
	TArray<TArray<int32>> AllocShapes;
	AllocShapes.SetNum(NumOut);

	if (bModelResolvedShapes)
	{
		for (int32 o = 0; o < NumOut; ++o)
		{
			for (uint32 D : ResolvedShapes[o].GetData())
			{
				AllocShapes[o].Add(static_cast<int32>(D));
			}
		}
		UE_LOG(LogMiraTerrainNNE, Verbose,
			TEXT("[NNEUNetRunner] '%s': model resolved %d concrete output shape(s)."), Stem, NumOut);
	}
	else
	{
		// Dynamic outputs - we MUST have caller-supplied expected shapes to size the buffers.
		if (ExpectedOutputShapes.Num() != NumOut)
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[NNEUNetRunner] '%s': output shapes are dynamic (unresolved) and ExpectedOutputShapes "
				     "count (%d) does not match model output count (%d). Pass one expected shape per output."),
				Stem, ExpectedOutputShapes.Num(), NumOut);
			return false;
		}
		for (int32 o = 0; o < NumOut; ++o)
		{
			AllocShapes[o] = ExpectedOutputShapes[o];
		}
		UE_LOG(LogMiraTerrainNNE, Verbose,
			TEXT("[NNEUNetRunner] '%s': dynamic output shapes - sizing %d output(s) from caller-supplied expected shapes."),
			Stem, NumOut);
	}

	// Allocate output tensors from AllocShapes.
	OutOutputs.SetNum(NumOut);
	for (int32 o = 0; o < NumOut; ++o)
	{
		FTensorData& Out = OutOutputs[o];
		Out.Shape = AllocShapes[o];
		const int64 Vol = Out.Volume();
		if (Vol <= 0)
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[NNEUNetRunner] '%s': output %d has non-positive volume (%lld) - bad shape."),
				Stem, o, (long long)Vol);
			return false;
		}
		Out.Values.SetNumZeroed(static_cast<int32>(Vol));
	}

	// --- 4) Build the CPU bindings (caller-owned memory; NNE copies to/from the GPU for us). ---
	TArray<UE::NNE::FTensorBindingCPU> InputBindings;
	InputBindings.Reserve(Inputs.Num());
	for (const FTensorData& In : Inputs)
	{
		UE::NNE::FTensorBindingCPU B;
		// ORT does not modify the input memory, but the binding API wants a non-const void*.
		B.Data        = const_cast<void*>(static_cast<const void*>(In.Values.GetData()));
		B.SizeInBytes = static_cast<uint64>(In.Values.Num()) * sizeof(float);
		InputBindings.Add(B);
	}

	TArray<UE::NNE::FTensorBindingCPU> OutputBindings;
	OutputBindings.Reserve(OutOutputs.Num());
	for (FTensorData& Out : OutOutputs)
	{
		UE::NNE::FTensorBindingCPU B;
		B.Data        = static_cast<void*>(Out.Values.GetData());
		B.SizeInBytes = static_cast<uint64>(Out.Values.Num()) * sizeof(float);
		OutputBindings.Add(B);
	}

	// --- 5) Run (blocks until done). ---
	const double T0 = FPlatformTime::Seconds();
	if (Inst->RunSync(InputBindings, OutputBindings) != UE::NNE::EResultStatus::Ok)
	{
		UE_LOG(LogMiraTerrainNNE, Error, TEXT("[NNEUNetRunner] '%s': RunSync failed."), Stem);
		return false;
	}
	const double Ms = (FPlatformTime::Seconds() - T0) * 1000.0;

	// --- 6) Reconcile with the TRUE output shapes (now known post-run) and verify our buffer
	//        was actually big enough. ORT only memcpy's into our buffer when it's >= the real
	//        output size; otherwise it silently leaves our buffer untouched (zeros). So if the
	//        true volume exceeds what we allocated, the result was NOT written -> hard fail.
	TConstArrayView<UE::NNE::FTensorShape> FinalShapes = Inst->GetOutputTensorShapes();
	if (FinalShapes.Num() == OutOutputs.Num())
	{
		for (int32 o = 0; o < OutOutputs.Num(); ++o)
		{
			const int64 TrueVol  = static_cast<int64>(FinalShapes[o].Volume());
			const int64 AllocVol = static_cast<int64>(OutOutputs[o].Values.Num());

			if (TrueVol > AllocVol)
			{
				UE_LOG(LogMiraTerrainNNE, Error,
					TEXT("[NNEUNetRunner] '%s': output %d true volume %lld exceeds allocated %lld - "
					     "expected output shape was too small, result NOT written. Check ExpectedOutputShapes."),
					Stem, o, (long long)TrueVol, (long long)AllocVol);
				return false;
			}

			// Adopt the authoritative shape; truncate the buffer if we over-allocated.
			OutOutputs[o].Shape.Reset();
			for (uint32 D : FinalShapes[o].GetData())
			{
				OutOutputs[o].Shape.Add(static_cast<int32>(D));
			}
			if (TrueVol != AllocVol)
			{
				OutOutputs[o].Values.SetNum(static_cast<int32>(TrueVol));
			}
		}
	}

	UE_LOG(LogMiraTerrainNNE, Log,
		TEXT("[NNEUNetRunner] '%s': RunSync OK on %s in %.1f ms (%d input(s) -> %d output(s))."),
		Stem, GetBackendName(), Ms, Inputs.Num(), OutOutputs.Num());

	return true;
}

} // namespace tdiff
} // namespace mira
