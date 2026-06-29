// TdiffRunnerAdapter.h - bridges the TWO "run a UNet" interfaces that live, by design,
// on opposite sides of the engine boundary.
//
// PLAIN ENGLISH (for the designer):
// We have one neural-net runner that actually works on the GPU - FNNEUNetRunner. It speaks
// the ENGINE dialect: tensors are Unreal TArrays (FTensorData), and the "which net" enum is
// EUNetModel. It implements the interface mira::tdiff::ITdiffUNetRunner.
//
// We also have the ported orchestration brain - WorldPipeline / InfiniteTiler - which lives
// in the engine-agnostic Core so the headless clang harness can unit-test it with NO Unreal
// headers. That brain therefore speaks a PURE-C++ dialect: tensors are std::vectors
// (mira::tdiff::NetTensor), the enum is mira::tdiff::ENet, and it calls into the interface
// mira::tdiff::IUNetRunner.
//
// Same shape of contract, two different vocabularies. THIS file is the translator: a thin
// IUNetRunner that forwards every call to an ITdiffUNetRunner, converting
//   NetTensor  <-> FTensorData     (std::vector<float>/<int>  <->  TArray<float>/<int32>)
//   ENet       <-> EUNetModel
// and supplying the ExpectedOutputShapes the engine runner needs (our ONNX models export
// with dynamic axes, so the caller must declare the concrete output shape - see
// NNEUNetRunner.cpp step 3). For our three nets the output shape is fully determined by the
// "x" input's spatial dims plus a fixed channel count, so we derive it here.
//
// Header-only: the conversions are tiny and want to inline. Both included headers declare
// the SAME namespace (mira::tdiff) but DISTINCT type names, so there is no clash.
//
// clang-LSP note: the standalone harness never sees this file (it includes CoreMinimal.h);
// any squiggles your editor shows for the engine types here are LSP false positives - it
// compiles under UBT.
#pragma once

#include "TdiffUNetRunner.h"            // mira::tdiff::ITdiffUNetRunner / FTensorData / EUNetModel
#include "Core/Tdiff/WorldPipeline.h"   // mira::tdiff::IUNetRunner / NetTensor / ENet

#include <vector>

namespace mira
{
namespace tdiff
{
	/**
	 * FTdiffRunnerAdapter - a pure-C++ IUNetRunner that delegates to an engine ITdiffUNetRunner.
	 *
	 * Lifetime: holds a REFERENCE to the inner runner; the owner must keep the inner runner
	 * alive for as long as the adapter is used (FDiffusionCoarseProvider owns both).
	 *
	 * Threading: not thread-safe (mirrors FNNEUNetRunner, whose RunSync is game-thread).
	 */
	class FTdiffRunnerAdapter : public IUNetRunner
	{
	public:
		explicit FTdiffRunnerAdapter(ITdiffUNetRunner& InInner)
			: Inner(InInner) {}

		// Set false before a batch of Run()s (e.g. before each region) and read afterwards:
		// because WorldPipeline IGNORES Run()'s bool return, this latch is how the caller
		// learns that some inference call failed (we still hand WorldPipeline a correctly
		// sized ZERO output so it never reads out of bounds).
		bool bRunFailed = false;

		virtual bool Run(ENet Model,
		                 const std::vector<NetTensor>& Inputs,
		                 std::vector<NetTensor>& Outputs) override
		{
			Outputs.clear();

			// The expected output shape (one output for every one of our nets). We need it both
			// to size the engine call AND to build a safe zero-output if the call fails.
			const std::vector<int> ExpShape = ExpectedOutputShape(Model, Inputs);

			// --- Convert NetTensor inputs -> FTensorData (engine dialect) ---
			TArray<FTensorData> EngineInputs;
			EngineInputs.Reserve(static_cast<int32>(Inputs.size()));
			for (const NetTensor& T : Inputs)
			{
				FTensorData FD;
				FD.Shape.Reserve(static_cast<int32>(T.shape.size()));
				for (int D : T.shape)
				{
					FD.Shape.Add(static_cast<int32>(D));
				}
				if (!T.data.empty())
				{
					FD.Values.Append(T.data.data(), static_cast<int32>(T.data.size()));
				}
				EngineInputs.Add(MoveTemp(FD));
			}

			// --- Expected output shape, in the engine container (one per output). ---
			TArray<TArray<int32>> EngineExpectedShapes;
			{
				TArray<int32> S;
				S.Reserve(static_cast<int32>(ExpShape.size()));
				for (int D : ExpShape)
				{
					S.Add(static_cast<int32>(D));
				}
				EngineExpectedShapes.Add(MoveTemp(S));
			}

			// --- Run the real net. ---
			TArray<FTensorData> EngineOutputs;
			const bool bOk = Inner.Run(ToEngineModel(Model), EngineInputs,
			                           EngineExpectedShapes, EngineOutputs);

			if (!bOk || EngineOutputs.Num() == 0)
			{
				// Failure: latch it and hand back a correctly-sized ZERO output so the pipeline's
				// outputs[0].data[...] reads stay in bounds (it would otherwise crash). Terrain
				// from a failed region is meaningless, but the provider checks bRunFailed and
				// rejects the region cleanly.
				bRunFailed = true;
				Outputs.emplace_back(ExpShape); // NetTensor(shape) zero-fills to the right size
				return false;
			}

			// --- Convert FTensorData outputs -> NetTensor (pure dialect). ---
			Outputs.reserve(static_cast<size_t>(EngineOutputs.Num()));
			for (const FTensorData& FD : EngineOutputs)
			{
				std::vector<int> Shape;
				Shape.reserve(static_cast<size_t>(FD.Shape.Num()));
				for (int32 D : FD.Shape)
				{
					Shape.push_back(static_cast<int>(D));
				}

				std::vector<float> Data;
				Data.resize(static_cast<size_t>(FD.Values.Num()));
				if (FD.Values.Num() > 0)
				{
					FMemory::Memcpy(Data.data(), FD.Values.GetData(),
					                static_cast<size_t>(FD.Values.Num()) * sizeof(float));
				}
				Outputs.emplace_back(std::move(Shape), std::move(Data));
			}
			return true;
		}

	private:
		ITdiffUNetRunner& Inner;

		// ENet (pure) -> EUNetModel (engine). Values match (Coarse=0/Base=1/Decoder=2) but map
		// explicitly so the bridge survives either enum being reordered.
		static EUNetModel ToEngineModel(ENet Model)
		{
			switch (Model)
			{
			case ENet::Coarse:  return EUNetModel::Coarse;
			case ENet::Base:    return EUNetModel::Base;
			case ENet::Decoder: return EUNetModel::Decoder;
			default:            return EUNetModel::Coarse;
			}
		}

		// The concrete output shape for a net, derived from the "x" input (Inputs[0], shape
		// {1, Cin, H, W}). Output is always batch 1, H x W, with a fixed channel count:
		//   Coarse  -> 6 channels   (WorldPipeline::coarseTile  expects (1,6,H,W))
		//   Base    -> 5 channels   (WorldPipeline::latentTile  expects (1,5,H,W))
		//   Decoder -> 1 channel    (WorldPipeline::decoderTile expects (1,1,H,W))
		static std::vector<int> ExpectedOutputShape(ENet Model, const std::vector<NetTensor>& Inputs)
		{
			int OutC = 6;
			switch (Model)
			{
			case ENet::Coarse:  OutC = 6; break;
			case ENet::Base:    OutC = 5; break;
			case ENet::Decoder: OutC = 1; break;
			}

			int H = 0, W = 0;
			if (!Inputs.empty() && Inputs[0].shape.size() >= 4)
			{
				H = Inputs[0].shape[2];
				W = Inputs[0].shape[3];
			}
			return std::vector<int>{ 1, OutC, H, W };
		}
	};

} // namespace tdiff
} // namespace mira
