// TdiffUNetRunner.h - the ABSTRACT "run a terrain-diffusion UNet" interface.
//
// PLAIN ENGLISH:
// The AI terrain brain is three small neural networks ("UNets") exported to the ONNX
// format. Something has to actually FEED numbers into a network and read numbers back
// out. That "something" is a *runner*. This file describes WHAT a runner must be able to
// do (the contract) WITHOUT saying HOW it does it.
//
// Why split it this way? The real runner (NNEUNetRunner) talks to Unreal's Neural Network
// Engine (NNE) + DirectML on the GPU - heavy, GPU-only, editor/runtime code. But the pure
// orchestration logic (the diffusion sampling loop, the deterministic RNG - the future
// namespace mira::tdiff in the engine-agnostic Core) wants to be unit-testable on a plain
// CPU in the standalone clang harness, with NO GPU and NO NNE headers. So that logic will
// depend ONLY on this lightweight interface. A test can hand it a fake runner; the game
// hands it the real NNE one. Classic "depend on an interface, not an implementation".
//
// This header is deliberately UE-LIGHT: it uses TArray (from Core) for convenience, but it
// pulls in ZERO NNE / RHI / Render headers. A tensor here is just a flat list of floats
// plus its shape - the simplest thing that can describe an N-dimensional block of numbers.
#pragma once

#include "CoreMinimal.h"

namespace mira
{
namespace tdiff
{
	/**
	 * Which of the three exported diffusion networks we mean.
	 *
	 * The trilogy's terrain pipeline runs them in this conceptual order:
	 *   Coarse   -> rough, low-res "lay of the land" latent.
	 *   Base     -> refines that into the detailed latent.
	 *   Decoder  -> turns the final latent into the actual high-res elevation image.
	 * (Gate 1 just proves each one runs correctly in isolation; the orchestration that
	 *  chains them comes later in mira::tdiff.)
	 */
	enum class EUNetModel : uint8
	{
		Coarse = 0,   // coarse_model.onnx
		Base,         // base_model.onnx
		Decoder       // decoder_model.onnx
	};

	/**
	 * A single N-dimensional tensor, stored the simplest possible way:
	 *   - Values: a flat array of 32-bit floats in row-major (C / NCHW) order - exactly how
	 *             numpy's .tofile() and ONNX Runtime lay memory out, so the golden .f32.bin
	 *             files drop straight in with no reshuffling.
	 *   - Shape:  the dimensions, e.g. {1, 11, 64, 64} for a 1x11x64x64 tensor.
	 *
	 * "Volume" (the product of the shape) must always equal Values.Num().
	 */
	struct FTensorData
	{
		TArray<float> Values;   // flat, row-major
		TArray<int32> Shape;    // e.g. {1, 6, 64, 64}

		FTensorData() = default;

		FTensorData(TArray<int32> InShape)
			: Shape(MoveTemp(InShape))
		{
			Values.SetNumZeroed(static_cast<int32>(Volume()));
		}

		/** Product of all dimensions = how many floats this tensor holds. 1 for an empty shape. */
		int64 Volume() const
		{
			int64 V = 1;
			for (int32 Dim : Shape)
			{
				V *= Dim;
			}
			return Shape.Num() == 0 ? 0 : V;
		}

		/** True when the flat data length matches the declared shape. */
		bool IsConsistent() const
		{
			return static_cast<int64>(Values.Num()) == Volume();
		}
	};

	/**
	 * THE CONTRACT. Anything that can run our diffusion UNets implements this.
	 *
	 * The single generic Run() takes the inputs IN THE MODEL'S DECLARED INPUT ORDER and
	 * fills OutOutputs with the results. For our exported models that input order is:
	 *   Coarse : x, noise_labels, cond_0, cond_1, cond_2, cond_3, cond_4   (7 inputs)
	 *   Base   : x, noise_labels, cond_0                                   (3 inputs)
	 *   Decoder: x, noise_labels                                          (2 inputs)
	 * and each produces a single "output" tensor.
	 *
	 * Returns true on success; on any failure it logs the reason and returns false.
	 */
	class ITdiffUNetRunner
	{
	public:
		virtual ~ITdiffUNetRunner() = default;

		/**
		 * Run one UNet once.
		 *
		 * WHY THIS ALSO TAKES EXPECTED OUTPUT SHAPES:
		 * The ONNX models were exported with DYNAMIC axes (a symbolic batch dim). With ONNX
		 * Runtime that means the output shape is NOT known until the network has actually run,
		 * so the runner cannot size the output buffer up front from the model alone. The caller
		 * normally DOES know the concrete output shape (here: from the golden capture, or from
		 * the input batch), so it hands the expected shape(s) in. The runner allocates + binds
		 * the output buffer from them, runs, then sets each output's Shape to the TRUE shape the
		 * runtime reports after the run. If a model resolves its output shapes statically you may
		 * pass an empty ExpectedOutputShapes and the model's own shapes are used.
		 *
		 * @param Model                Which network to run.
		 * @param Inputs               Input tensors, in the model's declared input order (see above).
		 * @param ExpectedOutputShapes One shape per model output, used to size/bind the output buffer(s)
		 *                             when the model's output shapes are dynamic. May be empty ONLY if the
		 *                             model resolves its output shapes statically.
		 * @param OutOutputs           Filled by the runner with the model's output tensor(s). Cleared first.
		 * @return                     true on success, false (with a log line) on any error.
		 */
		virtual bool Run(EUNetModel Model,
		                 TConstArrayView<FTensorData> Inputs,
		                 TConstArrayView<TArray<int32>> ExpectedOutputShapes,
		                 TArray<FTensorData>& OutOutputs) = 0;

		/** Human-readable name of the backend that actually executed (e.g. "NNE ORT DirectML (GPU)"). */
		virtual const TCHAR* GetBackendName() const = 0;
	};

	/** Maps the enum to the on-disk file stem / golden-file prefix, e.g. Coarse -> "coarse_model". */
	inline const TCHAR* GetModelStem(EUNetModel Model)
	{
		switch (Model)
		{
		case EUNetModel::Coarse:  return TEXT("coarse_model");
		case EUNetModel::Base:    return TEXT("base_model");
		case EUNetModel::Decoder: return TEXT("decoder_model");
		default:                  return TEXT("unknown_model");
		}
	}

} // namespace tdiff
} // namespace mira
