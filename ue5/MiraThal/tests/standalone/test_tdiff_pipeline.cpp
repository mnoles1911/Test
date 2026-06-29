// test_tdiff_pipeline.cpp - harness for the WorldPipeline spine
// (Core/Tdiff/WorldPipeline.h), the orchestration that turns seed+region into an
// elevation DEM by chaining the coarse/base/decoder nets through the already-ported
// scheduler / RNG / weight-window / laplacian pieces.
//
// Two modes:
//   (a) STRUCTURAL smoke test (always runs): drives WorldPipeline::get with a
//       deterministic STUB runner and asserts the nets are called the expected number
//       of times in the expected order, the per-call tensor shapes are right, the
//       output dims are right, and the result is deterministic (same seed -> same
//       output) and finite.
//   (b) PLAYBACK parity (runs only if a golden trace exists at
//       D:/terrain-diffusion/trace/trace.json): replays the recorded per-call net
//       outputs through a playback runner and compares the final elevation to the
//       recorded final_elev within tol. If the trace is absent it prints
//       "[pending trace]" and the structural test still decides PASS/FAIL.
//
// Trace schema (agreed with the capture task; see trace_FORMAT.md):
//   trace.json = { "seed": <int>, "region": [i1,j1,i2,j2],
//                  "calls": [ { "index":k, "model":"coarse_model|base_model|decoder_model",
//                               "inputs": {...},
//                               "output": {"file":"call_k_out.f32.bin","shape":[...]} }, ... ],
//                  "final_elev": {"file":"final_elev.f32.bin","shape":[H,W]} }
//   Raw little-endian float32 .bin files live alongside it in D:/terrain-diffusion/trace/.
//   The playback runner returns recorded outputs strictly by call index (it does not
//   need to inspect inputs), so only seed/region/outputs/final_elev are parsed here.
//
// Mirrors test_tdiff_rng.cpp's PASS/return convention. Discovered + run by build.sh.
#include "Core/Tdiff/WorldPipeline.h"

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <string>
#include <vector>
#include <fstream>

using mira::tdiff::WorldPipeline;
using mira::tdiff::WorldPipelineConfig;
using mira::tdiff::IUNetRunner;
using mira::tdiff::NetTensor;
using mira::tdiff::ENet;
using mira::tdiff::ElevTile;

// ---------------------------------------------------------------------------
// STUB runner: returns a fixed, deterministic, closed-form function of its input.
// out = 0.1 * (first OutChannels channels of x). This keeps values finite (no NaN /
// no zero weight channels downstream) while making the output depend on the input so
// determinism is meaningful. It also validates the per-model input contract and
// records every call so the structural test can inspect counts/order/shapes.
// ---------------------------------------------------------------------------
struct StubRunner : IUNetRunner
{
	int shapeFails = 0;
	int callIndex  = 0;

	// Expected per-model: (#inputs, x-channels, out-channels).
	bool Run(ENet model, const std::vector<NetTensor>& inputs,
	         std::vector<NetTensor>& outputs) override
	{
		++callIndex;
		int wantInputs = 0, xChan = 0, outChan = 0;
		switch (model)
		{
		case ENet::Coarse:  wantInputs = 7; xChan = 11; outChan = 6; break;
		case ENet::Base:    wantInputs = 3; xChan = 5;  outChan = 5; break;
		case ENet::Decoder: wantInputs = 2; xChan = 5;  outChan = 1; break;
		}

		// Validate input count.
		if (static_cast<int>(inputs.size()) != wantInputs)
		{
			std::printf("  stub: call %d wrong #inputs: got %zu want %d\n",
				callIndex, inputs.size(), wantInputs);
			++shapeFails;
		}

		// Validate the leading x tensor shape (1, xChan, H, W) and consistency.
		const NetTensor& x = inputs[0];
		if (x.shape.size() != 4 || x.shape[0] != 1 || x.shape[1] != xChan)
		{
			std::printf("  stub: call %d x shape wrong (want {1,%d,H,W})\n", callIndex, xChan);
			++shapeFails;
		}
		if (!x.consistent())
		{
			std::printf("  stub: call %d x not consistent (data %zu vs vol %lld)\n",
				callIndex, x.data.size(), x.volume());
			++shapeFails;
		}
		// noise_labels is always input[1], a 1-element tensor.
		if (inputs[1].data.size() != 1)
		{
			std::printf("  stub: call %d noise_labels not scalar\n", callIndex);
			++shapeFails;
		}

		const int H = x.shape[2];
		const int W = x.shape[3];
		const int N = H * W;

		// Produce (1, outChan, H, W) = 0.1 * first outChan channels of x.
		NetTensor out(std::vector<int>{1, outChan, H, W});
		for (int c = 0; c < outChan; ++c)
			for (int p = 0; p < N; ++p)
				out.data[static_cast<size_t>(c) * N + p] =
					0.1f * x.data[static_cast<size_t>(c) * N + p];

		outputs.clear();
		outputs.push_back(std::move(out));
		return true;
	}
};

// ---------------------------------------------------------------------------
// Structural smoke test.
// ---------------------------------------------------------------------------
static int structuralTest()
{
	int fails = 0;
	std::printf("-- structural smoke test --\n");

	WorldPipeline pipe; // default (shipping) config
	StubRunner stub;

	const uint64_t seed = 123456789ULL;
	const int i1 = 0, j1 = 0, i2 = 32, j2 = 32; // square, aligned region

	ElevTile t = pipe.get(seed, i1, j1, i2, j2, stub);

	// Shape validation inside the stub.
	if (stub.shapeFails != 0)
	{
		std::printf("  FAIL: %d shape violations from stub\n", stub.shapeFails);
		fails += stub.shapeFails;
	}

	// Call count + order: 20 Coarse, then 2 Base, then 1 Decoder = 23.
	const std::vector<ENet>& log = pipe.call_log();
	const int wantCoarse = 20, wantBase = 2, wantDecoder = 1;
	const int wantTotal = wantCoarse + wantBase + wantDecoder;
	if (static_cast<int>(log.size()) != wantTotal)
	{
		std::printf("  FAIL: call count %zu != %d\n", log.size(), wantTotal);
		++fails;
	}
	else
	{
		bool orderOk = true;
		for (int k = 0; k < wantCoarse; ++k)
			if (log[k] != ENet::Coarse) orderOk = false;
		for (int k = wantCoarse; k < wantCoarse + wantBase; ++k)
			if (log[k] != ENet::Base) orderOk = false;
		if (log[wantTotal - 1] != ENet::Decoder) orderOk = false;
		if (!orderOk)
		{
			std::printf("  FAIL: call order not [Coarse x20, Base x2, Decoder x1]\n");
			++fails;
		}
		else
		{
			std::printf("  ok: 23 calls in order (Coarse x20, Base x2, Decoder x1)\n");
		}
	}

	// Output dims.
	if (t.H != (i2 - i1) || t.W != (j2 - j1) ||
	    static_cast<int>(t.elev.size()) != t.H * t.W)
	{
		std::printf("  FAIL: output dims %dx%d (elev %zu) != %dx%d\n",
			t.H, t.W, t.elev.size(), i2 - i1, j2 - j1);
		++fails;
	}
	else
	{
		std::printf("  ok: output dims %dx%d\n", t.H, t.W);
	}

	// Finiteness.
	bool allFinite = true;
	for (float v : t.elev) if (!std::isfinite(v)) { allFinite = false; break; }
	if (!allFinite) { std::printf("  FAIL: non-finite elevation values\n"); ++fails; }
	else            std::printf("  ok: all elevation values finite\n");

	// Determinism: same seed -> bit-identical output.
	{
		StubRunner stub2;
		ElevTile t2 = pipe.get(seed, i1, j1, i2, j2, stub2);
		bool same = (t2.elev.size() == t.elev.size());
		for (size_t i = 0; same && i < t.elev.size(); ++i)
			if (t2.elev[i] != t.elev[i]) same = false;
		if (!same) { std::printf("  FAIL: same seed produced different output\n"); ++fails; }
		else        std::printf("  ok: deterministic (same seed -> identical output)\n");
	}

	// Different seed -> different output (sanity; warn-only so a fluke can't fail CI).
	{
		StubRunner stub3;
		ElevTile t3 = pipe.get(seed + 1, i1, j1, i2, j2, stub3);
		bool diff = false;
		for (size_t i = 0; i < t.elev.size() && i < t3.elev.size(); ++i)
			if (t3.elev[i] != t.elev[i]) { diff = true; break; }
		if (!diff) std::printf("  WARN: different seed produced identical output\n");
		else       std::printf("  ok: different seed -> different output\n");
	}

	return fails;
}

// ---------------------------------------------------------------------------
// Minimal JSON helpers for the fixed trace schema (no external libs).
// ---------------------------------------------------------------------------
// Gate 3 oracle: the ISOLATED single-tile spine (23 calls), captured by
// capture_singletile.py. This is exactly what WorldPipeline::getSingleTile replicates.
static const char* kTraceDir  = "D:/terrain-diffusion/trace_singletile/";
static const char* kTracePath = "D:/terrain-diffusion/trace_singletile/trace.json";

static bool readWholeFile(const std::string& path, std::string& out)
{
	std::ifstream f(path, std::ios::binary);
	if (!f) return false;
	out.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
	return true;
}

static bool readF32Bin(const std::string& path, std::vector<float>& out)
{
	std::ifstream f(path, std::ios::binary);
	if (!f) return false;
	f.seekg(0, std::ios::end);
	const std::streamoff bytes = f.tellg();
	f.seekg(0, std::ios::beg);
	out.resize(static_cast<size_t>(bytes / 4));
	f.read(reinterpret_cast<char*>(out.data()), static_cast<std::streamsize>(out.size() * 4));
	return true;
}

// Find the next integer following a key like "seed". Returns end-pos for chaining.
static bool jsonFindInt(const std::string& s, const std::string& key, size_t from,
                        long long& val, size_t& posOut)
{
	const size_t k = s.find("\"" + key + "\"", from);
	if (k == std::string::npos) return false;
	size_t i = s.find(':', k);
	if (i == std::string::npos) return false;
	++i;
	while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
	bool neg = false;
	if (i < s.size() && (s[i] == '-' || s[i] == '+')) { neg = (s[i] == '-'); ++i; }
	long long v = 0; bool any = false;
	while (i < s.size() && s[i] >= '0' && s[i] <= '9') { v = v * 10 + (s[i] - '0'); ++i; any = true; }
	if (!any) return false;
	val = neg ? -v : v;
	posOut = i;
	return true;
}

// Parse the string value following a key like "file" -> "call_0_out.f32.bin".
static bool jsonFindString(const std::string& s, const std::string& key, size_t from,
                           std::string& val, size_t& posOut)
{
	const size_t k = s.find("\"" + key + "\"", from);
	if (k == std::string::npos) return false;
	size_t i = s.find(':', k);
	if (i == std::string::npos) return false;
	i = s.find('"', i);
	if (i == std::string::npos) return false;
	++i;
	const size_t e = s.find('"', i);
	if (e == std::string::npos) return false;
	val = s.substr(i, e - i);
	posOut = e + 1;
	return true;
}

// ---------------------------------------------------------------------------
// Playback runner: returns recorded outputs strictly in call order.
// ---------------------------------------------------------------------------
struct PlaybackRunner : IUNetRunner
{
	std::vector<NetTensor> recorded; // one per call, in order
	size_t idx = 0;
	bool ok = true;

	bool Run(ENet, const std::vector<NetTensor>&, std::vector<NetTensor>& outputs) override
	{
		if (idx >= recorded.size()) { ok = false; return false; }
		outputs.clear();
		outputs.push_back(recorded[idx++]);
		return true;
	}
};

// Returns: 0 = pass, 1 = fail, 2 = pending (no trace).
static int playbackTest()
{
	std::printf("-- playback parity test --\n");

	std::string json;
	if (!readWholeFile(kTracePath, json))
	{
		std::printf("  [pending trace] %s not found; skipping playback parity.\n", kTracePath);
		return 2;
	}

	// seed (the single-tile trace has no "region"; it runs an origin-aligned unit).
	long long seedLL = 0; size_t pos = 0;
	if (!jsonFindInt(json, "seed", 0, seedLL, pos))
	{ std::printf("  FAIL: trace missing seed\n"); return 1; }

	// Collect per-call output files in order (each "output" object has a "file").
	std::vector<std::string> outFiles;
	{
		size_t p = 0;
		while (true)
		{
			const size_t o = json.find("\"output\"", p);
			if (o == std::string::npos) break;
			std::string file; size_t np = 0;
			if (!jsonFindString(json, "file", o, file, np)) break;
			outFiles.push_back(file);
			p = np;
		}
	}

	// final_elev file.
	std::string finalFile; size_t fpos = json.find("\"final_elev\"");
	if (fpos == std::string::npos) { std::printf("  FAIL: trace missing final_elev\n"); return 1; }
	{
		size_t np = 0;
		if (!jsonFindString(json, "file", fpos, finalFile, np))
		{ std::printf("  FAIL: final_elev missing file\n"); return 1; }
	}

	std::printf("  single-tile trace: seed=%lld recorded calls=%zu\n", seedLL, outFiles.size());

	// -----------------------------------------------------------------------
	// GOLDEN MICRO-PARITY (control-flow sanity): the very first coarse call is the
	// first coarse tile's first denoise step, whose noise label is ALWAYS
	// atan(sigma_max/sigma_data) (sigmas[0] of the 20-step Karras schedule = sigma_max).
	// A mismatch here is a genuine bug -> hard fail.
	// -----------------------------------------------------------------------
	bool microOk = true;
	{
		WorldPipelineConfig cfg;
		std::vector<float> nl;
		if (readF32Bin(std::string(kTraceDir) + "call_0_noise_labels.f32.bin", nl) && !nl.empty())
		{
			const double want = std::atan(cfg.sigma_max / cfg.sigma_data);
			if (std::fabs((double)nl[0] - want) <= 1e-4)
				std::printf("  ok: coarse step-0 noise label parity (got %.7f want %.7f)\n",
					(double)nl[0], want);
			else
			{
				std::printf("  FAIL: coarse step-0 noise label %.7f != golden %.7f\n",
					(double)nl[0], want);
				microOk = false;
			}
		}
	}

	// -----------------------------------------------------------------------
	// FULL single-tile playback parity (Gate 3). Feed the recorded per-call net OUTPUTS
	// through a playback runner; WorldPipeline::getSingleTile re-runs the EXACT isolated
	// per-tile denoise control flow capture_singletile.py recorded (20 coarse DPM steps,
	// 2 latent trigflow steps, 1 decoder step, no padding, [0:4,0:4] coarse crop). The
	// runner ignores model INPUTS (so unported conditioning is moot); the spine's own
	// portable-RNG noise draws (sample/latent/decoder) reproduce the capture's bit-for-
	// bit, and the orchestration math (scheduler, trigflow, weight window, laplacian,
	// sign*square) is what we validate against the recorded final_elev.
	// -----------------------------------------------------------------------
	PlaybackRunner pb;
	for (const std::string& f : outFiles)
	{
		std::vector<float> data;
		if (!readF32Bin(std::string(kTraceDir) + f, data))
		{ std::printf("  FAIL: cannot read %s\n", f.c_str()); return 1; }
		NetTensor t;
		t.data = std::move(data);
		t.shape = { static_cast<int>(t.data.size()) };
		pb.recorded.push_back(std::move(t));
	}

	std::vector<float> finalElev;
	if (!readF32Bin(std::string(kTraceDir) + finalFile, finalElev))
	{ std::printf("  FAIL: cannot read %s\n", finalFile.c_str()); return 1; }

	WorldPipeline pipe;
	const uint64_t seed = static_cast<uint64_t>(seedLL);
	ElevTile t = pipe.getSingleTile(seed, pb);

	// Control-flow checks: call count/order must match the recorded 23 (20+2+1).
	const std::vector<ENet>& log = pipe.call_log();
	if (log.size() != pb.recorded.size())
	{
		std::printf("  FAIL: spine issued %zu net calls but trace recorded %zu\n",
			log.size(), pb.recorded.size());
		return 1;
	}
	if (t.elev.size() != finalElev.size())
	{
		std::printf("  FAIL: elev size %zu != recorded %zu (want %d x %d)\n",
			t.elev.size(), finalElev.size(), t.H, t.W);
		return 1;
	}

	// Elevation parity. Values are ~hundreds-to-thousands of metres and elev=sign(x)*x^2
	// amplifies small float diffs, so we report both absolute and relative max error.
	double maxAbs = 0.0, maxRel = 0.0;
	for (size_t i = 0; i < t.elev.size(); ++i)
	{
		const double a = (double)t.elev[i], b = (double)finalElev[i];
		const double d = std::fabs(a - b);
		maxAbs = std::max(maxAbs, d);
		maxRel = std::max(maxRel, d / std::max(1.0, std::fabs(b)));
	}
	std::printf("  parity: max|diff|=%.4e  max relative=%.4e  (elev %dx%d)\n",
		maxAbs, maxRel, t.H, t.W);

	// Gate tolerance: relative 1e-3 (elev=sign*x^2 doubles the sqrt-space rounding, so a
	// 1e-3 relative budget is the realistic float32-vs-double parity bar at this 512^2 tile).
	const double relTol = 1e-3;
	if (maxRel <= relTol && microOk)
	{
		std::printf("  ok: single-tile playback parity within relative %.0e\n", relTol);
		return 0;
	}
	std::printf("  FAIL: single-tile playback parity max relative %.4e > %.0e\n", maxRel, relTol);
	return 1;
}

int main()
{
	int fails = structuralTest();

	const int pb = playbackTest();
	if (pb == 1) ++fails; // hard fail only when a trace exists and mismatches

	std::printf("====================\n");
	if (fails == 0)
	{
		std::printf("test_tdiff_pipeline: ALL PASS%s\n",
			pb == 2 ? " (structural green; full playback PENDING)" : " (structural + playback)");
		return 0;
	}
	std::printf("test_tdiff_pipeline: %d FAILURE(S)\n", fails);
	return 1;
}
