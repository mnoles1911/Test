// Laplacian.h - faithful header-only C++17 port of terrain-diffusion's
// laplacian_encoder.py (the pieces world_pipeline._compute_elev actually uses).
//
// COPIED + REFACTORED from the public repo
// (terrain_diffusion/data/laplacian_encoder.py). The terrain model stores
// elevation as a "Laplacian pyramid": a low-frequency coarse map (lowres) plus a
// high-frequency residual. To turn that back into real elevation you have to:
//   1. up-sample the coarse map to the residual's resolution (bilinear), and
//   2. add the residual on top (laplacian_decode), with an optional denoise pass
//      (laplacian_denoise) that re-derives a clean coarse map from the decoded
//      surface so seams between tiles line up.
//
// THE HARD PART is that the Python code resizes with torchvision's
// TF.resize(..., InterpolationMode.BILINEAR). torchvision's *default* bilinear is
// align_corners=False AND antialias=True. Our world generation must match that
// pixel-for-pixel or the C++ runtime terrain will drift away from the reference
// model. So bilinearResize() below implements PyTorch's antialiased bilinear
// sampler exactly:
//   * sampling maps output pixel -> input coord as src = (dst+0.5)*scale - 0.5
//     (that is the align_corners=False rule, baked into the weight centres);
//   * when DOWN-sampling (scale > 1) the triangle filter is widened to "scale"
//     so it averages a whole neighbourhood (this is the antialias part);
//   * when UP-sampling (scale < 1) the widened filter collapses back to the plain
//     2-tap bilinear, which is exactly what torchvision does, so one code path
//     covers both directions.
//
// Verified against a golden captured from the REAL repo functions in
// tests/standalone/test_tdiff_laplacian.cpp (max|diff| ~1e-5, tolerance 1e-4).
//
// Pure C++17, no engine headers -> lives in Core/ so the standalone clang harness
// can test it. Everything works on flat row-major float buffers with explicit
// width/height; multi-channel callers just loop one channel at a time.
#pragma once

#include <cstddef>
#include <cmath>
#include <vector>

namespace mira {
namespace tdiff {

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// torchvision/PyTorch round its size math with Python's round(), which is
// round-half-to-EVEN (banker's rounding), not round-half-away-from-zero. std::rint
// uses the current rounding mode, which is round-to-nearest-even by default, so it
// reproduces Python's round() for the values we feed it.
inline int roundHalfEven(double v)
{
	return static_cast<int>(std::rint(v));
}

// Gaussian blur kernel size from sigma, copied from the repo:
//   kernel_size = (int(sigma*2)//2)*2 + 1   (always odd). For sigma=5 -> 11.
inline int gaussianKernelSize(double sigma)
{
	const int twoSigma = static_cast<int>(sigma * 2.0); // truncation == Python int()
	return (twoSigma / 2) * 2 + 1;
}

// torchvision's "resize to a single int = match the SHORTER edge, keep aspect"
// rule (functional._compute_resized_output_size). The longer edge is truncated,
// not rounded. For a square input this just returns (size, size). Used by the
// encode step inside laplacian_denoise, where downsample_size = lowres width.
inline void intResizeTarget(int h, int w, int size, int& outH, int& outW)
{
	const int shortEdge = (w <= h) ? w : h;
	const int longEdge  = (w <= h) ? h : w;
	const int newShort  = size;
	const int newLong   = static_cast<int>(static_cast<double>(size) * longEdge / shortEdge);
	if (w <= h) { outW = newShort; outH = newLong; }
	else        { outH = newShort; outW = newLong; }
}

// ---------------------------------------------------------------------------
// Bilinear resize matching torchvision (align_corners=False, antialias=True)
// ---------------------------------------------------------------------------

// For one axis, work out where each output sample reads from in the input and the
// weights to use. This is PyTorch's antialias index/weight computation
// (aten compute_indices_weights_aa) for the bilinear (triangle) filter.
//
//   scale    = inSize / outSize           (>1 = down-sampling, <1 = up-sampling)
//   support  = scale when down-sampling, else 1   (filter half-width)
//   center   = scale * (out + 0.5)        (== (out+0.5)*scale; align_corners=False)
//   weight   = triangle((tap - center + 0.5) * invscale)
//
// `starts[o]` is the first input index read for output o; `weights[o]` are the
// (already normalised) taps starting at that index.
inline void computeBilinearWeightsAA(int inSize, int outSize,
	std::vector<int>& starts, std::vector<std::vector<double>>& weights)
{
	const double scale    = static_cast<double>(inSize) / static_cast<double>(outSize);
	const double support  = (scale >= 1.0) ? scale : 1.0;
	const double invscale = (scale >= 1.0) ? (1.0 / scale) : 1.0;

	starts.resize(outSize);
	weights.resize(outSize);

	for (int o = 0; o < outSize; ++o)
	{
		const double center = scale * (static_cast<double>(o) + 0.5);

		// Window of input taps that the filter touches. int() truncates toward
		// zero, matching PyTorch's static_cast<int64_t>; then clamp to bounds.
		int xmin = static_cast<int>(center - support + 0.5);
		if (xmin < 0) xmin = 0;
		int xmax = static_cast<int>(center + support + 0.5);
		if (xmax > inSize) xmax = inSize;
		const int xsize = xmax - xmin;

		std::vector<double> ws(static_cast<size_t>(xsize));
		double total = 0.0;
		for (int k = 0; k < xsize; ++k)
		{
			const double t = (static_cast<double>(k + xmin) - center + 0.5) * invscale;
			const double a = std::fabs(t);
			const double w = (a < 1.0) ? (1.0 - a) : 0.0; // triangle (bilinear) filter
			ws[static_cast<size_t>(k)] = w;
			total += w;
		}
		// Normalise so the taps sum to 1 (keeps brightness constant).
		if (total != 0.0)
		{
			for (int k = 0; k < xsize; ++k) ws[static_cast<size_t>(k)] /= total;
		}
		starts[o] = xmin;
		weights[o] = std::move(ws);
	}
}

// Resize a single-channel row-major image src(hIn x wIn) into dst(hOut x wOut)
// using the antialiased bilinear sampler above. Separable: first along width into
// a temporary, then along height. All accumulation is in double for precision; the
// final store truncates to float (torchvision works in float32, and double-then-
// store stays well inside our 1e-4 parity budget).
inline void bilinearResize(const float* src, int hIn, int wIn,
	float* dst, int hOut, int wOut)
{
	std::vector<int> wStart, hStart;
	std::vector<std::vector<double>> wWeights, hWeights;
	computeBilinearWeightsAA(wIn, wOut, wStart, wWeights);
	computeBilinearWeightsAA(hIn, hOut, hStart, hWeights);

	// Pass 1: horizontal resize -> tmp(hIn x wOut).
	std::vector<double> tmp(static_cast<size_t>(hIn) * static_cast<size_t>(wOut));
	for (int r = 0; r < hIn; ++r)
	{
		const float* srow = src + static_cast<size_t>(r) * wIn;
		for (int c = 0; c < wOut; ++c)
		{
			const int xm = wStart[c];
			const std::vector<double>& ws = wWeights[c];
			double acc = 0.0;
			for (size_t k = 0; k < ws.size(); ++k)
				acc += static_cast<double>(srow[xm + static_cast<int>(k)]) * ws[k];
			tmp[static_cast<size_t>(r) * wOut + c] = acc;
		}
	}

	// Pass 2: vertical resize -> dst(hOut x wOut).
	for (int r = 0; r < hOut; ++r)
	{
		const int ym = hStart[r];
		const std::vector<double>& ws = hWeights[r];
		for (int c = 0; c < wOut; ++c)
		{
			double acc = 0.0;
			for (size_t k = 0; k < ws.size(); ++k)
				acc += tmp[static_cast<size_t>(ym + static_cast<int>(k)) * wOut + c] * ws[k];
			dst[static_cast<size_t>(r) * wOut + c] = static_cast<float>(acc);
		}
	}
}

// ---------------------------------------------------------------------------
// pad_linear_extrapolation
// ---------------------------------------------------------------------------

// Pad src(h x w) by ONE pixel on every side into dst((h+2) x (w+2)) by LINEAR
// extrapolation: the new border = 2*edge - next-in (mirrors the slope outward
// instead of clamping). Matches the repo exactly: it pads rows (H) first, then
// columns (W), so the corner cells are extrapolated from the already-row-padded
// data - the same order torch.cat uses. (If a dimension is length 1 the repo just
// duplicates the single line; handled below.)
inline void padLinearExtrapolation(const float* src, int h, int w, float* dst)
{
	const int W = w + 2;

	// Stage 1: pad rows (top/bottom) into a (h+2) x w temporary.
	std::vector<float> t(static_cast<size_t>(h + 2) * static_cast<size_t>(w));
	for (int r = 0; r < h; ++r)
		for (int c = 0; c < w; ++c)
			t[static_cast<size_t>(r + 1) * w + c] = src[static_cast<size_t>(r) * w + c];
	for (int c = 0; c < w; ++c)
	{
		if (h > 1)
		{
			t[static_cast<size_t>(0) * w + c]
				= 2.0f * src[static_cast<size_t>(0) * w + c] - src[static_cast<size_t>(1) * w + c];
			t[static_cast<size_t>(h + 1) * w + c]
				= 2.0f * src[static_cast<size_t>(h - 1) * w + c] - src[static_cast<size_t>(h - 2) * w + c];
		}
		else
		{
			t[static_cast<size_t>(0) * w + c]     = src[c];
			t[static_cast<size_t>(h + 1) * w + c] = src[c];
		}
	}

	// Stage 2: pad columns (left/right) of the row-padded temp into dst.
	const int H = h + 2;
	for (int r = 0; r < H; ++r)
	{
		const float* trow = t.data() + static_cast<size_t>(r) * w;
		float* drow = dst + static_cast<size_t>(r) * W;
		for (int c = 0; c < w; ++c) drow[c + 1] = trow[c];
		if (w > 1)
		{
			drow[0]     = 2.0f * trow[0] - trow[1];
			drow[w + 1] = 2.0f * trow[w - 1] - trow[w - 2];
		}
		else
		{
			drow[0]     = trow[0];
			drow[w + 1] = trow[0];
		}
	}
}

// ---------------------------------------------------------------------------
// resize_extrapolated
// ---------------------------------------------------------------------------

// Resize src(h x w) up to (targetH x targetW) but pad with linear extrapolation
// first, then crop the padding back off, so the result has no edge-clamping
// artefacts at tile boundaries. Faithful to resize_extrapolated() in the repo.
inline void resizeExtrapolated(const float* src, int h, int w,
	float* dst, int targetH, int targetW)
{
	const double scaleH = static_cast<double>(targetH) / static_cast<double>(h);
	const double scaleW = static_cast<double>(targetW) / static_cast<double>(w);

	std::vector<float> padded(static_cast<size_t>(h + 2) * static_cast<size_t>(w + 2));
	padLinearExtrapolation(src, h, w, padded.data());

	const int newH = roundHalfEven(targetH + 2.0 * scaleH);
	const int newW = roundHalfEven(targetW + 2.0 * scaleW);

	std::vector<float> up(static_cast<size_t>(newH) * static_cast<size_t>(newW));
	bilinearResize(padded.data(), h + 2, w + 2, up.data(), newH, newW);

	const int padH = roundHalfEven(scaleH);
	const int padW = roundHalfEven(scaleW);

	// Crop the [padH : padH+targetH, padW : padW+targetW] window.
	for (int r = 0; r < targetH; ++r)
		for (int c = 0; c < targetW; ++c)
			dst[static_cast<size_t>(r) * targetW + c]
				= up[static_cast<size_t>(r + padH) * newW + (c + padW)];
}

// ---------------------------------------------------------------------------
// gaussian_blur (torchvision)
// ---------------------------------------------------------------------------

// Separable Gaussian blur with REFLECT padding, matching TF.gaussian_blur. The
// 1-D kernel is exactly torchvision's: x = linspace(-(k-1)/2, (k-1)/2, k),
// pdf = exp(-0.5 (x/sigma)^2), normalised to sum 1. Reflect padding mirrors the
// signal WITHOUT repeating the edge sample (period 2*(n-1)), like torch's
// mode="reflect". Used by the denoise step.
inline void gaussianBlur(const float* src, int h, int w, float* dst, double sigma)
{
	const int ks = gaussianKernelSize(sigma);
	const int p  = ks / 2;

	// Build + normalise the 1-D kernel.
	std::vector<double> k(static_cast<size_t>(ks));
	const double half = (ks - 1) * 0.5;
	double sum = 0.0;
	for (int i = 0; i < ks; ++i)
	{
		const double x = (ks > 1) ? (-half + (2.0 * half) * i / (ks - 1)) : 0.0;
		const double v = std::exp(-0.5 * (x / sigma) * (x / sigma));
		k[static_cast<size_t>(i)] = v;
		sum += v;
	}
	for (int i = 0; i < ks; ++i) k[static_cast<size_t>(i)] /= sum;

	// Reflect index helper (no edge repeat), period 2*(n-1).
	auto reflect = [](int i, int n) -> int
	{
		if (n == 1) return 0;
		const int per = 2 * (n - 1);
		i %= per;
		if (i < 0) i += per;
		return (i < n) ? i : (per - i);
	};

	// Pass 1: horizontal.
	std::vector<double> tmp(static_cast<size_t>(h) * static_cast<size_t>(w));
	for (int r = 0; r < h; ++r)
		for (int c = 0; c < w; ++c)
		{
			double acc = 0.0;
			for (int t = 0; t < ks; ++t)
				acc += static_cast<double>(src[static_cast<size_t>(r) * w + reflect(c - p + t, w)])
					 * k[static_cast<size_t>(t)];
			tmp[static_cast<size_t>(r) * w + c] = acc;
		}

	// Pass 2: vertical.
	for (int c = 0; c < w; ++c)
		for (int r = 0; r < h; ++r)
		{
			double acc = 0.0;
			for (int t = 0; t < ks; ++t)
				acc += tmp[static_cast<size_t>(reflect(r - p + t, h)) * w + c]
					 * k[static_cast<size_t>(t)];
			dst[static_cast<size_t>(r) * w + c] = static_cast<float>(acc);
		}
}

// ---------------------------------------------------------------------------
// laplacian_decode  (single channel)
// ---------------------------------------------------------------------------

// Reconstruct: up-sample lowres(lh x lw) to the residual's size (h x w) and add
// the residual. extrapolate selects plain bilinear vs the linear-extrapolated
// resize. out must hold h*w floats. (Multi-channel callers loop this per channel,
// which is exactly what the repo's 4-D resize does internally.)
inline void laplacianDecode(const float* residual, int h, int w,
	const float* lowres, int lh, int lw, float* out, bool extrapolate)
{
	std::vector<float> up(static_cast<size_t>(h) * static_cast<size_t>(w));
	if (extrapolate)
		resizeExtrapolated(lowres, lh, lw, up.data(), h, w);
	else
		bilinearResize(lowres, lh, lw, up.data(), h, w);

	const size_t n = static_cast<size_t>(h) * static_cast<size_t>(w);
	for (size_t i = 0; i < n; ++i) out[i] = residual[i] + up[i];
}

// Output dimensions produced by laplacianDenoise for a given residual size and
// lowres width. (The denoise re-encode down-samples to the lowres WIDTH, so for
// the usual square case the new coarse map is lw x lw - which may differ from the
// original lh x lw.) Callers use this to size the newLowres buffer.
inline void laplacianDenoiseLowresDims(int h, int w, int lw, int& outLh, int& outLw)
{
	intResizeTarget(h, w, lw, outLh, outLw);
}

// ---------------------------------------------------------------------------
// laplacian_denoise  (single channel)
// ---------------------------------------------------------------------------

// Re-derive a clean coarse map from residual+lowres: first decode WITH
// extrapolation to a full-res surface, then re-encode it (down-sample to the
// lowres width + gaussian blur) to get a fresh low-frequency map. Mirrors
// laplacian_denoise -> laplacian_encode in the repo; the residual is returned
// unchanged (so we only output the new coarse map here).
//
// newLowres must hold outLh*outLw floats (see laplacianDenoiseLowresDims). The
// produced dimensions are written back into newLh/newLw.
inline void laplacianDenoise(const float* residual, int h, int w,
	const float* lowres, int lh, int lw, double sigma,
	float* newLowres, int& newLh, int& newLw)
{
	// Step 1: full-res decode with extrapolation.
	std::vector<float> decoded(static_cast<size_t>(h) * static_cast<size_t>(w));
	laplacianDecode(residual, h, w, lowres, lh, lw, decoded.data(), /*extrapolate=*/true);

	// Step 2: re-encode -> down-sample decoded to the lowres width (int-size rule),
	// then gaussian blur. That blurred down-sample IS the new coarse map.
	int oh = 0, ow = 0;
	intResizeTarget(h, w, lw, oh, ow);
	std::vector<float> down(static_cast<size_t>(oh) * static_cast<size_t>(ow));
	bilinearResize(decoded.data(), h, w, down.data(), oh, ow);
	gaussianBlur(down.data(), oh, ow, newLowres, sigma);

	newLh = oh;
	newLw = ow;
}

} // namespace tdiff
} // namespace mira
