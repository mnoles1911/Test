// TdiffGate1Commandlet.cpp - replay golden tensors through the NNE runner and verify.
//
// See TdiffGate1Commandlet.h for the "what / why". This file:
//   1. Builds an FNNEUNetRunner pointing at the .onnx folder.
//   2. For each of the three models, loads the golden input tensors (raw float32 .bin files),
//      runs inference, loads the golden output, and compares.
//   3. Logs max|diff| and mean|diff| and a PASS/FAIL verdict per model and overall.
//
// Golden file naming convention (fixed-seed 12345 capture):
//   <GoldenDir>/<stem>__<inputname>.f32.bin   e.g. coarse_model__x.f32.bin
//   <GoldenDir>/<stem>__output.f32.bin
//
// The input NAMES and ORDER and the tensor SHAPES below were read directly from the exported
// ONNX graphs and the golden .npy headers, so they match the model's declared input order
// (which is the order RunSync binds by).

#include "TdiffGate1Commandlet.h"

#include "NNEUNetRunner.h"          // FNNEUNetRunner + LogMiraTerrainNNE
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/Parse.h"
#include "HAL/FileManager.h"

using namespace mira::tdiff;

namespace
{
	// Default artifact locations (overridable via -GoldenDir= / -OnnxDir=).
	static const TCHAR* GDefaultGoldenDir = TEXT("D:/terrain-diffusion/golden");
	static const TCHAR* GDefaultOnnxDir   = TEXT("D:/terrain-diffusion/onnx_export");
	// DirectML fp math diverges slightly from the PyTorch golden; allow a small tolerance.
	static const float  GDefaultTolerance = 5.0e-3f;

	// One model's full spec: which inputs (name + shape, in declared order) and the output shape.
	struct FInputSpec
	{
		const TCHAR* Name;
		TArray<int32> Shape;
	};
	struct FModelSpec
	{
		EUNetModel       Model;
		TArray<FInputSpec> Inputs;     // in the model's declared input order
		TArray<int32>    OutputShape;
	};

	// Load a raw float32 .bin into a flat float array. Returns false on any read error.
	bool LoadF32Bin(const FString& Path, TArray<float>& Out)
	{
		TArray<uint8> Raw;
		if (!FFileHelper::LoadFileToArray(Raw, *Path))
		{
			return false;
		}
		if (Raw.Num() % sizeof(float) != 0)
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[Gate1] '%s': size %d is not a multiple of 4 (not float32?)."), *Path, Raw.Num());
			return false;
		}
		Out.SetNumUninitialized(Raw.Num() / sizeof(float));
		FMemory::Memcpy(Out.GetData(), Raw.GetData(), Raw.Num());
		return true;
	}
}

UTdiffGate1Commandlet::UTdiffGate1Commandlet()
{
	IsClient    = false;
	IsServer    = false;
	IsEditor    = true;    // we need an editor process so NNE can optimize the model on the fly
	LogToConsole = true;
}

int32 UTdiffGate1Commandlet::Main(const FString& Params)
{
	// --- Parse switches (with the D:\terrain-diffusion defaults). ---
	FString GoldenDir = GDefaultGoldenDir;
	FString OnnxDir   = GDefaultOnnxDir;
	float   Tolerance = GDefaultTolerance;
	FParse::Value(*Params, TEXT("GoldenDir="), GoldenDir);
	FParse::Value(*Params, TEXT("OnnxDir="),   OnnxDir);
	FParse::Value(*Params, TEXT("Tolerance="), Tolerance);

	UE_LOG(LogMiraTerrainNNE, Display, TEXT("================ Tdiff Gate 1 ================"));
	UE_LOG(LogMiraTerrainNNE, Display, TEXT("[Gate1] OnnxDir   = %s"), *OnnxDir);
	UE_LOG(LogMiraTerrainNNE, Display, TEXT("[Gate1] GoldenDir = %s"), *GoldenDir);
	UE_LOG(LogMiraTerrainNNE, Display, TEXT("[Gate1] Tolerance = %g (max abs diff)"), Tolerance);

	// --- The three model specs (names/shapes verified from the ONNX graphs + golden .npy headers). ---
	TArray<FModelSpec> Specs;

	// coarse_model: x(1,11,64,64), noise_labels(1), cond_0..cond_4(1) -> output(1,6,64,64)
	{
		FModelSpec S;
		S.Model = EUNetModel::Coarse;
		S.Inputs.Add({ TEXT("x"),            { 1, 11, 64, 64 } });
		S.Inputs.Add({ TEXT("noise_labels"), { 1 } });
		S.Inputs.Add({ TEXT("cond_0"),       { 1 } });
		S.Inputs.Add({ TEXT("cond_1"),       { 1 } });
		S.Inputs.Add({ TEXT("cond_2"),       { 1 } });
		S.Inputs.Add({ TEXT("cond_3"),       { 1 } });
		S.Inputs.Add({ TEXT("cond_4"),       { 1 } });
		S.OutputShape = { 1, 6, 64, 64 };
		Specs.Add(MoveTemp(S));
	}
	// base_model: x(1,5,64,64), noise_labels(1), cond_0(1,58) -> output(1,5,64,64)
	{
		FModelSpec S;
		S.Model = EUNetModel::Base;
		S.Inputs.Add({ TEXT("x"),            { 1, 5, 64, 64 } });
		S.Inputs.Add({ TEXT("noise_labels"), { 1 } });
		S.Inputs.Add({ TEXT("cond_0"),       { 1, 58 } });
		S.OutputShape = { 1, 5, 64, 64 };
		Specs.Add(MoveTemp(S));
	}
	// decoder_model: x(1,5,512,512), noise_labels(1) -> output(1,1,512,512)
	{
		FModelSpec S;
		S.Model = EUNetModel::Decoder;
		S.Inputs.Add({ TEXT("x"),            { 1, 5, 512, 512 } });
		S.Inputs.Add({ TEXT("noise_labels"), { 1 } });
		S.OutputShape = { 1, 1, 512, 512 };
		Specs.Add(MoveTemp(S));
	}

	FNNEUNetRunner Runner(OnnxDir);

	int32 NumPassed = 0;
	int32 NumFailed = 0;

	for (const FModelSpec& Spec : Specs)
	{
		const TCHAR* Stem = GetModelStem(Spec.Model);
		UE_LOG(LogMiraTerrainNNE, Display, TEXT("---- model: %s ----"), Stem);

		// 1) Load the golden inputs (in declared order) into FTensorData.
		TArray<FTensorData> Inputs;
		bool bInputsOk = true;
		for (const FInputSpec& In : Spec.Inputs)
		{
			const FString Path = FPaths::Combine(GoldenDir, FString::Printf(TEXT("%s__%s.f32.bin"), Stem, In.Name));

			FTensorData T;
			T.Shape = In.Shape;
			if (!LoadF32Bin(Path, T.Values))
			{
				UE_LOG(LogMiraTerrainNNE, Error, TEXT("[Gate1] %s: missing/unreadable golden input: %s"), Stem, *Path);
				bInputsOk = false;
				break;
			}
			if (!T.IsConsistent())
			{
				UE_LOG(LogMiraTerrainNNE, Error,
					TEXT("[Gate1] %s: golden input '%s' has %d floats but expected shape volume %lld (%s)."),
					Stem, In.Name, T.Values.Num(), (long long)T.Volume(), *Path);
				bInputsOk = false;
				break;
			}
			Inputs.Add(MoveTemp(T));
		}
		if (!bInputsOk)
		{
			++NumFailed;
			continue;
		}

		// 2) Load the golden output FIRST. We need it both to compare against AND to tell the runner
		//    the expected output shape - the ONNX models have dynamic axes, so the runtime can't
		//    resolve the output shape until after it runs. The runner uses this expected shape to
		//    size + bind the output buffer (see ITdiffUNetRunner::Run docs).
		const FString GoldOutPath = FPaths::Combine(GoldenDir, FString::Printf(TEXT("%s__output.f32.bin"), Stem));
		TArray<float> Gold;
		if (!LoadF32Bin(GoldOutPath, Gold))
		{
			UE_LOG(LogMiraTerrainNNE, Error, TEXT("[Gate1] %s: missing/unreadable golden output: %s"), Stem, *GoldOutPath);
			++NumFailed;
			continue;
		}

		// Sanity-check our known output shape against the actual golden file element count, then
		// hand that shape to the runner as the expected output shape.
		FTensorData ExpectedOut;
		ExpectedOut.Shape = Spec.OutputShape;
		if (ExpectedOut.Volume() != Gold.Num())
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[Gate1] %s: expected output shape volume %lld != golden output element count %d (%s)."),
				Stem, (long long)ExpectedOut.Volume(), Gold.Num(), *GoldOutPath);
			++NumFailed;
			continue;
		}
		TArray<TArray<int32>> ExpectedOutputShapes;
		ExpectedOutputShapes.Add(Spec.OutputShape);

		// 3) Run inference (with the expected output shape so dynamic-axis outputs can be bound).
		TArray<FTensorData> Outputs;
		if (!Runner.Run(Spec.Model, Inputs, ExpectedOutputShapes, Outputs) || Outputs.Num() == 0)
		{
			UE_LOG(LogMiraTerrainNNE, Error, TEXT("[Gate1] %s: inference FAILED."), Stem);
			++NumFailed;
			continue;
		}
		const FTensorData& Got = Outputs[0];

		// 4) Compare.
		if (Got.Values.Num() != Gold.Num())
		{
			UE_LOG(LogMiraTerrainNNE, Error,
				TEXT("[Gate1] %s: output element count mismatch - got %d, golden %d. FAIL"),
				Stem, Got.Values.Num(), Gold.Num());
			++NumFailed;
			continue;
		}

		double MaxAbs = 0.0;
		double SumAbs = 0.0;
		for (int32 i = 0; i < Gold.Num(); ++i)
		{
			const double D = FMath::Abs(static_cast<double>(Got.Values[i]) - static_cast<double>(Gold[i]));
			MaxAbs = FMath::Max(MaxAbs, D);
			SumAbs += D;
		}
		const double MeanAbs = (Gold.Num() > 0) ? (SumAbs / Gold.Num()) : 0.0;
		const bool bPass = (MaxAbs <= Tolerance);

		UE_LOG(LogMiraTerrainNNE, Display,
			TEXT("[Gate1] %s: backend=%s  elems=%d  max|diff|=%.6g  mean|diff|=%.6g  tol=%g  => %s"),
			Stem, Runner.GetBackendName(), Gold.Num(), MaxAbs, MeanAbs, Tolerance,
			bPass ? TEXT("PASS") : TEXT("FAIL"));

		if (bPass) { ++NumPassed; } else { ++NumFailed; }
	}

	const bool bAllPassed = (NumFailed == 0 && NumPassed == Specs.Num());
	UE_LOG(LogMiraTerrainNNE, Display, TEXT("================ Gate 1 result: %s  (%d passed, %d failed) ================"),
		bAllPassed ? TEXT("PASS") : TEXT("FAIL"), NumPassed, NumFailed);

	// Non-zero exit code on failure so scripts (and the parent) can detect it.
	return bAllPassed ? 0 : 1;
}
