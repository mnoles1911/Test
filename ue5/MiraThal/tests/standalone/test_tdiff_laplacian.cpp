// test_tdiff_laplacian.cpp - prove the C++ Laplacian port matches the REAL
// terrain-diffusion laplacian_decode / laplacian_denoise (torchvision bilinear +
// gaussian blur). Compares C++ output against a golden captured by
// tdiff/laplacian_reference.py. Discovered + run by build.sh (the green gate).
// Regenerate the golden with:
//   PYTHONPATH=D:/terrain-diffusion D:/terrain-diffusion/.venv/Scripts/python.exe \
//     tdiff/laplacian_reference.py
#include "Core/Tdiff/Laplacian.h"
#include "tdiff/laplacian_golden.inc"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>

// Reconstruct a float from its stored IEEE-754 bit pattern (exact input parity).
static float bitsToF32(uint32_t b)
{
	float f;
	std::memcpy(&f, &b, sizeof(f));
	return f;
}

// Mode tags - must match laplacian_reference.py.
enum { MODE_DECODE_NOEXTRAP = 0, MODE_DECODE_EXTRAP = 1, MODE_DENOISE = 2, MODE_ELEV = 3 };

// Tolerance: the C++ ports compute in double while torchvision runs in float32, so
// a small drift through the resize/blur chain is expected. Measured ~1e-5; budget 1e-4.
static const double kTol = 1e-4;

int main()
{
	using namespace mira::tdiff;

	int fails = 0;
	double worst = 0.0;
	const char* worstName = "(none)";

	for (int ci = 0; ci < kLapCaseCount; ++ci)
	{
		const LapCase& tc = kLapCases[ci];
		const int C = tc.channels;
		const int h = tc.h, w = tc.w, lh = tc.lh, lw = tc.lw;
		const size_t resPlane = static_cast<size_t>(h) * w;
		const size_t lowPlane = static_cast<size_t>(lh) * lw;
		const size_t outPlane = static_cast<size_t>(tc.outH) * tc.outW;

		double caseWorst = 0.0;

		for (int ch = 0; ch < C; ++ch)
		{
			// Rebuild this channel's exact float inputs from bit patterns.
			std::vector<float> residual(resPlane), lowres(lowPlane);
			for (size_t i = 0; i < resPlane; ++i)
				residual[i] = bitsToF32(tc.residual[static_cast<size_t>(ch) * resPlane + i]);
			for (size_t i = 0; i < lowPlane; ++i)
				lowres[i] = bitsToF32(tc.lowres[static_cast<size_t>(ch) * lowPlane + i]);

			std::vector<float> got(outPlane);

			if (tc.mode == MODE_DECODE_NOEXTRAP)
			{
				laplacianDecode(residual.data(), h, w, lowres.data(), lh, lw, got.data(), false);
			}
			else if (tc.mode == MODE_DECODE_EXTRAP)
			{
				laplacianDecode(residual.data(), h, w, lowres.data(), lh, lw, got.data(), true);
			}
			else if (tc.mode == MODE_DENOISE)
			{
				int nlh = 0, nlw = 0;
				laplacianDenoise(residual.data(), h, w, lowres.data(), lh, lw,
					tc.sigma, got.data(), nlh, nlw);
				if (nlh != tc.outH || nlw != tc.outW)
				{
					std::printf("case %s ch %d: denoise dims got %dx%d want %dx%d\n",
						tc.name, ch, nlh, nlw, tc.outH, tc.outW);
					++fails;
				}
			}
			else // MODE_ELEV: denoise -> decode, exactly like _compute_elev
			{
				int nlh = 0, nlw = 0;
				std::vector<float> newLow(outPlane); // denoise output is <= outPlane here
				laplacianDenoise(residual.data(), h, w, lowres.data(), lh, lw,
					tc.sigma, newLow.data(), nlh, nlw);
				laplacianDecode(residual.data(), h, w, newLow.data(), nlh, nlw, got.data(), false);
			}

			// Compare to golden.
			for (size_t i = 0; i < outPlane; ++i)
			{
				const float want = bitsToF32(tc.expected[static_cast<size_t>(ch) * outPlane + i]);
				const double d = std::fabs(static_cast<double>(got[i]) - static_cast<double>(want));
				if (d > caseWorst) caseWorst = d;
			}
		}

		if (caseWorst > worst) { worst = caseWorst; worstName = tc.name; }
		if (caseWorst > kTol)
		{
			std::printf("case %s: max|diff| %.3e exceeds tol %.1e\n", tc.name, caseWorst, kTol);
			++fails;
		}
	}

	if (fails == 0)
	{
		std::printf("test_tdiff_laplacian: ALL PASS (%d cases, worst max|diff| %.3e on %s, tol %.1e)\n",
			kLapCaseCount, worst, worstName, kTol);
		return 0;
	}
	std::printf("test_tdiff_laplacian: %d FAILURE(S) (worst max|diff| %.3e on %s)\n",
		fails, worst, worstName);
	return 1;
}
