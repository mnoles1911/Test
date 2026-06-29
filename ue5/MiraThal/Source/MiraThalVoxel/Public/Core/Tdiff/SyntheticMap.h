// SyntheticMap.h - faithful C++17 port of terrain-diffusion's synthetic_map.py.
//
// WHAT THIS IS (plain English):
// The coarse terrain-diffusion model does not start from nothing. Before it generates a
// tile of world it is handed a "synthetic map" - a cheap, deterministic guess at the
// region's geography (elevation, temperature, temperature variability, precipitation,
// precipitation variability). Those five fields are the model's CONDITIONING: they steer
// the diffusion so a desert stays a desert and a mountain stays a mountain. The orchestration
// spine currently feeds the coarse model ZEROS for this conditioning (a stub); this header is
// the real generator that will eventually replace those zeros so the world matches the
// reference pipeline.
//
// HOW THE PYTHON BUILDS IT (synthetic_map.py -> make_synthetic_map_factory):
//   1. Five independent fractal-Perlin noise fields (one per channel), each with its own seed
//      derived from the world seed, and its own frequency/octaves.
//   2. Each raw noise value is "histogram-matched" onto a real-world distribution via a pair of
//      quantile tables (noise quantiles -> base-image quantiles) loaded from synthetic_map_stats.json.
//      This is the np.interp transform in perlin_transform.py (transform_perlin).
//   3. finalize_synthetic_map() couples the channels with simple physics (lapse rate, a
//      temperature-variability model, a precipitation-variability model) using four scalar
//      stats (a_temp_std, b_temp_std, temp_std_p1, temp_std_p99) also loaded from the stats JSON.
//   4. sample_full_synthetic_map() finally applies sign(x)*sqrt(|x|) to the elevation channel.
//
// CONDITIONING CHANNEL LAYOUT (what the coarse model consumes):
//   The model's 11-channel "x" input is [6 noisy-sample channels] ++ [5 conditioning channels].
//   THOSE 5 CONDITIONING CHANNELS ARE EXACTLY THIS SYNTHETIC MAP, in order:
//     ch0 = elevation (after sign*sqrt), ch1 = temperature, ch2 = temperature_std,
//     ch3 = precipitation,               ch4 = precipitation_std.
//   Downstream the spine normalizes them by coarse_means/coarse_stds[[0,2,3,4,5]] and trig-mixes
//   them with seed noise (cos*synthetic + sin*noise). The separate scalar cond_0..cond_4 the
//   capture showed are SNR/timestep labels (cond_inputs), NOT this map - they are unrelated.
//   This header produces only the 5-channel synthetic map; the normalize + trig-mix + label
//   plumbing stays in the spine and is intentionally out of scope here.
//
// NOISE LIBRARY / PARITY:
//   synthetic_map.py uses pyfastnoiselite, a Cython binding that wraps the upstream Auburn
//   FastNoiseLite C++ single header (it #includes ext/FastNoise/Cpp/FastNoiseLite.h and calls
//   GetNoise(float,float) with FNfloat=float - i.e. single precision). We VENDOR that exact
//   upstream header (ThirdParty/FastNoiseLite.h, MIT) and drive it through its public API with
//   the identical parameters, so the noise is bit-for-bit what pyfastnoiselite produces. Verified
//   bit-exact in tests/standalone/test_tdiff_synthmap.cpp.
//
// Pure C++17, engine-free, header-only -> lives in Core/ so the standalone clang harness tests it.
#pragma once

#include "Core/Tdiff/ThirdParty/FastNoiseLite.h"

#include <array>
#include <vector>
#include <string>
#include <cstdint>
#include <cmath>
#include <cstddef>
#include <fstream>
#include <sstream>

namespace mira {
namespace tdiff {

// ---------------------------------------------------------------------------
// Stats loaded from synthetic_map_stats.json (we LOAD them, never hardcode).
// ---------------------------------------------------------------------------
struct SyntheticMapStats
{
	double aTempStd = 0.0;   // a_temp_std  : slope of temp-std vs temp linear fit
	double bTempStd = 0.0;   // b_temp_std  : intercept of that fit
	double tempStdP1 = 0.0;  // temp_std_p1 : 0.1th percentile of residual temp-std
	double tempStdP99 = 0.0; // temp_std_p99: 99.9th percentile of residual temp-std
	int    nQuantiles = 0;   // knots per quantile table (64 in the shipped stats)

	// Per-channel quantile tables (5 channels). noiseQuantiles == "source" (xp),
	// baseQuantiles == "target" (fp) for the np.interp histogram match.
	std::array<std::vector<double>, 5> noiseQuantiles; // noise_quantile_tables[i]
	std::array<std::vector<double>, 5> baseQuantiles;  // data_quantile_tables[i]

	bool IsValid() const
	{
		if (nQuantiles <= 0) return false;
		for (int i = 0; i < 5; ++i)
		{
			if ((int)noiseQuantiles[i].size() != nQuantiles) return false;
			if ((int)baseQuantiles[i].size() != nQuantiles) return false;
		}
		return true;
	}
};

// ---------------------------------------------------------------------------
// Minimal JSON reader (just enough for synthetic_map_stats.json).
//
// We avoid any third-party JSON dependency to keep this header engine-free and
// self-contained. The stats file is a flat object of scalars + arrays-of-arrays
// of numbers; this tiny recursive-descent parser handles exactly that shape
// (objects, arrays, numbers, strings, true/false/null). It is NOT a general
// hardened JSON library - it is purpose-built for this one well-formed file.
// ---------------------------------------------------------------------------
namespace detail {

class JsonParser
{
public:
	explicit JsonParser(const std::string& text) : s(text), p(0) {}

	// Find the value following a top-level (or any-level) key by scanning the
	// flat object. For this file every key is unique, so a forward scan is fine.
	// Returns true and sets [outStart,outEnd) to the raw value span.
	bool ok = true;

	// Public entry points -------------------------------------------------
	// Parse the whole document into a tiny tree is overkill; instead we expose
	// targeted extractors keyed by name from the top-level object.

	// Read a scalar number for "key": e.g. a_temp_std.
	bool GetNumber(const std::string& key, double& out)
	{
		size_t at;
		if (!FindKey(key, at)) return false;
		p = at;
		SkipWs();
		out = ParseNumber();
		return ok;
	}

	bool GetInt(const std::string& key, int& out)
	{
		double d;
		if (!GetNumber(key, d)) return false;
		out = (int)d;
		return true;
	}

	// Read an array-of-arrays-of-numbers for "key" into dst (resized to 5 here
	// by caller pattern, but we fill exactly what is present).
	bool GetArrayOfArrays(const std::string& key, std::vector<std::vector<double>>& dst)
	{
		size_t at;
		if (!FindKey(key, at)) return false;
		p = at;
		SkipWs();
		if (Peek() != '[') return Fail();
		Next(); // consume outer '['
		dst.clear();
		SkipWs();
		while (Peek() != ']')
		{
			std::vector<double> row;
			if (!ParseNumberArray(row)) return false;
			dst.push_back(std::move(row));
			SkipWs();
			if (Peek() == ',') { Next(); SkipWs(); }
		}
		Next(); // consume outer ']'
		return ok;
	}

private:
	const std::string& s;
	size_t p;

	bool Fail() { ok = false; return false; }
	char Peek() const { return p < s.size() ? s[p] : '\0'; }
	char Next() { return p < s.size() ? s[p++] : '\0'; }
	void SkipWs() { while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) ++p; }

	// Locate "key" and return the index just AFTER the following ':'.
	bool FindKey(const std::string& key, size_t& valuePos)
	{
		const std::string needle = "\"" + key + "\"";
		size_t k = s.find(needle, 0);
		if (k == std::string::npos) return false;
		size_t c = s.find(':', k + needle.size());
		if (c == std::string::npos) return false;
		valuePos = c + 1;
		return true;
	}

	double ParseNumber()
	{
		SkipWs();
		size_t start = p;
		while (p < s.size())
		{
			char ch = s[p];
			if ((ch >= '0' && ch <= '9') || ch == '+' || ch == '-' || ch == '.' || ch == 'e' || ch == 'E')
				++p;
			else
				break;
		}
		if (p == start) { Fail(); return 0.0; }
		// strtod parses the exact same decimal text Python's json wrote.
		return std::strtod(s.c_str() + start, nullptr);
	}

	bool ParseNumberArray(std::vector<double>& row)
	{
		SkipWs();
		if (Peek() != '[') return Fail();
		Next();
		SkipWs();
		while (Peek() != ']')
		{
			row.push_back(ParseNumber());
			if (!ok) return false;
			SkipWs();
			if (Peek() == ',') { Next(); SkipWs(); }
		}
		Next(); // consume ']'
		return true;
	}
};

} // namespace detail

// Parse stats from an in-memory JSON string. Returns true on success.
inline bool ParseSyntheticMapStats(const std::string& json, SyntheticMapStats& out)
{
	detail::JsonParser jp(json);
	bool good = true;
	good &= jp.GetNumber("a_temp_std", out.aTempStd);
	good &= jp.GetNumber("b_temp_std", out.bTempStd);
	good &= jp.GetNumber("temp_std_p1", out.tempStdP1);
	good &= jp.GetNumber("temp_std_p99", out.tempStdP99);
	jp.GetInt("n_quantiles", out.nQuantiles); // optional; we re-derive below if absent

	std::vector<std::vector<double>> noiseTables, dataTables;
	good &= jp.GetArrayOfArrays("noise_quantile_tables", noiseTables);
	good &= jp.GetArrayOfArrays("data_quantile_tables", dataTables);
	if (!good) return false;
	if (noiseTables.size() < 5 || dataTables.size() < 5) return false;

	for (int i = 0; i < 5; ++i)
	{
		out.noiseQuantiles[i] = noiseTables[i];
		out.baseQuantiles[i] = dataTables[i];
	}
	if (out.nQuantiles <= 0 && !out.noiseQuantiles[0].empty())
		out.nQuantiles = (int)out.noiseQuantiles[0].size();
	return out.IsValid();
}

// Load + parse stats from a file path.
inline bool LoadSyntheticMapStats(const std::string& path, SyntheticMapStats& out)
{
	std::ifstream f(path, std::ios::binary);
	if (!f) return false;
	std::ostringstream ss;
	ss << f.rdbuf();
	return ParseSyntheticMapStats(ss.str(), out);
}

// ---------------------------------------------------------------------------
// transform_perlin == numpy.interp(v, xp, fp, left=fp[0], right=fp[-1]).
//
// Histogram-matches a raw noise value onto the target distribution. Mirrors
// numpy's compiled interp exactly (binary search + float64 slope), including the
// left/right clamping the Python wires up. xp must be strictly increasing (the
// stats builder guarantees that).
// ---------------------------------------------------------------------------
inline double InterpPerlin(double v, const std::vector<double>& xp, const std::vector<double>& fp)
{
	const size_t n = xp.size();
	if (n == 0) return 0.0;
	if (v != v) return v;                 // NaN passthrough (numpy behaviour)
	if (v < xp[0]) return fp[0];          // left  = target_quantiles[0]
	if (v >= xp[n - 1]) return fp[n - 1]; // right = target_quantiles[-1]; also covers v==last

	// Largest j with xp[j] <= v < xp[j+1]  (numpy's binary_search_with_guess).
	size_t lo = 0, hi = n - 1;            // invariant: xp[lo] <= v < xp[hi]
	while (hi - lo > 1)
	{
		size_t mid = lo + ((hi - lo) >> 1);
		if (xp[mid] <= v) lo = mid; else hi = mid;
	}
	const size_t j = lo;
	if (xp[j] == v) return fp[j];

	const double slope = (fp[j + 1] - fp[j]) / (xp[j + 1] - xp[j]);
	double res = slope * (v - xp[j]) + fp[j];
	if (res != res) // numpy's NaN fix-up for infinities at the knots
	{
		res = slope * (v - xp[j + 1]) + fp[j + 1];
		if (res != res && fp[j] == fp[j + 1]) res = fp[j];
	}
	return res;
}

// ---------------------------------------------------------------------------
// The generator. Construct with stats + world seed; sample windows on demand.
// ---------------------------------------------------------------------------
class SyntheticMap
{
public:
	// Mirrors make_synthetic_map_factory(frequency_mult, seed, drop_water_pct).
	// drop_water_pct only affects STATS COMPUTATION (which we load, not compute),
	// so it is irrelevant to sampling and intentionally omitted here.
	SyntheticMap(const SyntheticMapStats& stats,
	             int64_t seed,
	             const std::array<float, 5>& frequencyMult = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f})
		: mStats(stats)
	{
		// actual_seeds = [((seed) + i + 1) & 0x7FFFFFFF for i in range(5)]
		// (the Python "seed or random" wall-clock branch is the non-deterministic
		//  path and is never used on the generation path - we require a real seed.)
		for (int i = 0; i < 5; ++i)
			mSeeds[i] = (int)(((seed + i + 1) & 0x7FFFFFFFLL));

		// map_configs: (frequency, octaves, lacunarity, gain). Note channel 1 (temp)
		// uses 2 octaves; all others use 4. lacunarity 2.0 / gain 0.5 everywhere.
		const int octaves[5]    = {4, 2, 4, 4, 4};
		for (int i = 0; i < 5; ++i)
		{
			mNoise[i].SetSeed(mSeeds[i]);
			mNoise[i].SetNoiseType(FastNoiseLite::NoiseType_Perlin);
			mNoise[i].SetFractalType(FastNoiseLite::FractalType_FBm);
			mNoise[i].SetFractalOctaves(octaves[i]);
			mNoise[i].SetFractalLacunarity(2.0f);
			mNoise[i].SetFractalGain(0.5f);
			mNoise[i].SetFrequency(0.05f * frequencyMult[i]);
		}
	}

	const std::array<int, 5>& Seeds() const { return mSeeds; }

	// Raw 5-channel stack for window [i1,i2) x [j1,j2), histogram-matched but
	// BEFORE finalize. Mirrors sample_raw_synthetic_map. Each output vector has
	// length (i2-i1)*(j2-j1) in numpy C-order flatten of the reshaped (W,H) array
	// (i.e. index k -> column c=k%W, row r=k/W, sampled at (i1+c, j1+r)).
	void SampleRaw(int i1, int j1, int i2, int j2, std::array<std::vector<float>, 5>& out) const
	{
		const int W = i2 - i1;
		const int H = j2 - j1;
		const size_t N = (W > 0 && H > 0) ? (size_t)W * (size_t)H : 0;
		for (int ch = 0; ch < 5; ++ch)
		{
			out[ch].resize(N);
			const std::vector<double>& xp = mStats.noiseQuantiles[ch];
			const std::vector<double>& fp = mStats.baseQuantiles[ch];
			for (size_t k = 0; k < N; ++k)
			{
				const int c = (int)(k % (size_t)W);
				const int r = (int)(k / (size_t)W);
				const float x = (float)(i1 + c);
				const float y = (float)(j1 + r);
				const float nv = mNoise[ch].GetNoise(x, y); // float32, bit-exact vs pyfastnoiselite
				// np.interp upcasts the float32 query to float64 (exact), interps in
				// float64, then finalize casts back to float32 -> we mirror that here.
				out[ch][k] = (float)InterpPerlin((double)nv, xp, fp);
			}
		}
	}

	// In-place finalize. Mirrors finalize_synthetic_map (elementwise; all float32).
	// chans[0..4] = elev, temp, temp_std, precip, precip_std.
	void Finalize(std::array<std::vector<float>, 5>& chans) const
	{
		const float a = (float)mStats.aTempStd;
		const float b = (float)mStats.bTempStd;
		const float p1 = (float)mStats.tempStdP1;
		const float p99 = (float)mStats.tempStdP99;
		// NEP50 detail: (temp_std_p99 - temp_std_p1) is a scalar-scalar op that numpy
		// evaluates in float64, THEN narrows to float32 when divided into the array.
		// So compute the span in double and cast once (matches the Python bit-for-bit).
		const float denom = (float)(mStats.tempStdP99 - mStats.tempStdP1);
		const size_t N = chans[0].size();
		for (size_t k = 0; k < N; ++k)
		{
			const float elev = chans[0][k];
			float temp = chans[1][k];
			float tempStd = chans[2][k];
			const float precip = chans[3][k];
			float precipStd = chans[4][k];

			// lapse_rate = clip(-6.5 + 0.0015*precip, -9.8, -4.0) / 1000
			float lapse = -6.5f + 0.0015f * precip;
			lapse = Clampf(lapse, -9.8f, -4.0f) / 1000.0f;
			// temp += lapse_rate * max(0, elev)
			temp = temp + lapse * Maxf(0.0f, elev);
			temp = Clampf(temp, -10.0f, 40.0f);
			// stretch sub-20C values: where temp>20 keep, else (temp-20)*1.25+20
			temp = (temp > 20.0f) ? temp : (temp - 20.0f) * 1.25f + 20.0f;

			// temp_std model
			const float t = (tempStd - p1) / denom;
			const float baseline = Maxf(p1, -(a * temp + b));
			tempStd = t * (p99 - baseline) + baseline;
			tempStd = tempStd + (a * temp + b);
			tempStd = Maxf(tempStd, 20.0f);

			// precip_std model
			precipStd = precipStd * Maxf(0.0f, (185.0f - 0.04111f * precip) / 185.0f);

			chans[1][k] = temp;
			chans[2][k] = tempStd;
			chans[4][k] = precipStd;
			// chans[0] (elev) and chans[3] (precip) pass through unchanged.
		}
	}

	// Full pipeline: SampleRaw -> Finalize -> sign(x)*sqrt(|x|) on elevation.
	// Mirrors sample_full_synthetic_map (the torch tensor it returns is just this
	// float32 stack). Output layout matches SampleRaw.
	void SampleFull(int i1, int j1, int i2, int j2, std::array<std::vector<float>, 5>& out) const
	{
		SampleRaw(i1, j1, i2, j2, out);
		Finalize(out);
		for (float& e : out[0])
			e = std::copysign(std::sqrt(std::fabs(e)), e); // == sign(e)*sqrt(|e|)
	}

private:
	static float Clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
	static float Maxf(float a, float b) { return a > b ? a : b; }

	SyntheticMapStats mStats;
	std::array<int, 5> mSeeds{};
	FastNoiseLite mNoise[5];
};

} // namespace tdiff
} // namespace mira
