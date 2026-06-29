// test_tdiff_scheduler.cpp - parity gate for the EdmDpmScheduler C++ port vs the
// REAL terrain_diffusion EDMDPMSolverMultistepScheduler. Compares the C++ sigma /
// timestep schedules and a synthetic-denoise trajectory against the golden captured
// by tdiff/sched_reference.py. Discovered + run by build.sh. Regenerate golden:
//   set PYTHONPATH=D:\terrain-diffusion
//   D:\terrain-diffusion\.venv\Scripts\python.exe tdiff\sched_reference.py
#include "Core/Tdiff/EdmDpmScheduler.h"
#include "tdiff/sched_golden.inc"

#include <cstdio>
#include <cmath>
#include <vector>

// Tolerances: schedule values within 1e-5, trajectory checkpoints within 1e-4.
static const double kSchedTol = 1e-5;
static const double kTrajTol  = 1e-4;

// Same deterministic starting sample as sched_reference.py::initial_sample.
static void initial_sample(std::vector<float>& s, int count)
{
	s.resize((size_t)count);
	for (int j = 0; j < count; ++j)
	{
		s[(size_t)j] = (float)(0.5 * std::sin(0.3 * j) - 0.2 * std::cos(0.11 * j) + 0.01 * j);
	}
}

int main()
{
	using mira::tdiff::EdmDpmScheduler;
	using mira::tdiff::EdmDpmConfig;

	int fails = 0;

	for (int c = 0; c < kSchedGoldenCount; ++c)
	{
		const SchedGolden& g = kSchedGolden[c];

		EdmDpmConfig cfg; // defaults == the world_pipeline.py config
		EdmDpmScheduler sched(cfg);
		sched.set_timesteps(g.n);

		// 1) sigma schedule (n+1 values)
		const std::vector<double>& sig = sched.sigmas();
		if ((int)sig.size() != g.n + 1)
		{
			std::printf("n=%d sigmas size: got %d want %d\n",
				g.n, (int)sig.size(), g.n + 1);
			++fails;
		}
		else
		{
			for (int i = 0; i < g.n + 1; ++i)
			{
				const double d = std::fabs(sig[(size_t)i] - g.sigmas[i]);
				if (d > kSchedTol)
				{
					std::printf("n=%d sigma[%d]: got %.10g want %.10g (|d|=%.3g)\n",
						g.n, i, sig[(size_t)i], g.sigmas[i], d);
					++fails;
				}
			}
		}

		// 2) timestep schedule (n values)
		const std::vector<double>& ts = sched.timesteps();
		if ((int)ts.size() != g.n)
		{
			std::printf("n=%d timesteps size: got %d want %d\n",
				g.n, (int)ts.size(), g.n);
			++fails;
		}
		else
		{
			for (int i = 0; i < g.n; ++i)
			{
				const double d = std::fabs(ts[(size_t)i] - g.timesteps[i]);
				if (d > kSchedTol)
				{
					std::printf("n=%d timestep[%d]: got %.10g want %.10g (|d|=%.3g)\n",
						g.n, i, ts[(size_t)i], g.timesteps[i], d);
					++fails;
				}
			}
		}

		// 3) synthetic denoise trajectory - replicate the reference exactly.
		std::vector<float> sample;
		initial_sample(sample, kSchedCount);
		std::vector<float> model_output((size_t)kSchedCount);
		std::vector<float> prev((size_t)kSchedCount);

		for (int i = 0; i < g.n; ++i)
		{
			const double sigma = sched.sigmas()[(size_t)i];
			for (int j = 0; j < kSchedCount; ++j)
			{
				model_output[(size_t)j] = (float)(0.1 * (double)sample[(size_t)j] - 0.05 * sigma);
			}
			sched.step(model_output.data(), sample.data(), prev.data(), (size_t)kSchedCount);
			sample = prev;

			// summary stats in double over the float result
			double mean = 0.0, mn = sample[0], mx = sample[0], sumsq = 0.0;
			for (int j = 0; j < kSchedCount; ++j)
			{
				const double v = (double)sample[(size_t)j];
				mean += v;
				if (v < mn) mn = v;
				if (v > mx) mx = v;
				sumsq += v * v;
			}
			mean /= (double)kSchedCount;
			const double norm = std::sqrt(sumsq);

			const TrajPoint& tp = g.traj[i];
			for (int k = 0; k < kSchedNExact; ++k)
			{
				const double d = std::fabs((double)sample[(size_t)k] - tp.e[k]);
				if (d > kTrajTol)
				{
					std::printf("n=%d step %d e[%d]: got %.8g want %.8g (|d|=%.3g)\n",
						g.n, i, k, (double)sample[(size_t)k], tp.e[k], d);
					++fails;
				}
			}
			const double dmean = std::fabs(mean - tp.mean);
			const double dmn   = std::fabs(mn - tp.mn);
			const double dmx   = std::fabs(mx - tp.mx);
			const double dnorm = std::fabs(norm - tp.norm);
			if (dmean > kTrajTol || dmn > kTrajTol || dmx > kTrajTol || dnorm > kTrajTol)
			{
				std::printf("n=%d step %d stats: mean d=%.3g min d=%.3g max d=%.3g norm d=%.3g\n",
					g.n, i, dmean, dmn, dmx, dnorm);
				++fails;
			}
		}
	}

	if (fails == 0)
	{
		std::printf("test_tdiff_scheduler: ALL PASS (%d schedules, sigma/timestep tol %.0e, trajectory tol %.0e)\n",
			kSchedGoldenCount, kSchedTol, kTrajTol);
		return 0;
	}
	std::printf("test_tdiff_scheduler: %d FAILURE(S)\n", fails);
	return 1;
}
