// EdmDpmScheduler.h - faithful C++17 port of terrain-diffusion's
// EDMDPMSolverMultistepScheduler (terrain_diffusion/scheduler/dpmsolver.py).
//
// COPIED + REFACTORED from the upstream HuggingFace/diffusers EDM DPM-Solver++.
// This ports EXACTLY the one configuration the game's world_pipeline.py uses:
//
//     EDMDPMSolverMultistepScheduler(sigma_min=0.002, sigma_max=80, sigma_data=0.5)
//   + class defaults: solver_order=2, algorithm_type="dpmsolver++",
//     solver_type="midpoint", sigma_schedule="karras", prediction_type="epsilon",
//     rho=7.0, final_sigmas_type="zero", lower_order_final=True, scaling_p=None.
//
// Everything OFF that path (thresholding, 3rd-order, sde-dpmsolver, exponential
// schedule, v_prediction) is intentionally NOT ported - those branches are dead
// for our config and porting them would only invite drift.
//
// Numerics note (the parity contract, see tests/standalone/test_tdiff_scheduler.cpp):
//   * "per-step state" (sigmas, timesteps, the solver scalars lambda/h/r0 and the
//     coefficients derived from them) is kept in DOUBLE for accuracy.
//   * "tensors" (the sample, the raw model output, the converted x0 prediction) are
//     flat float32 buffers - the same storage the real (float32) pipeline uses - so
//     accumulation rounding matches the reference. Coefficients are computed in
//     double then applied to / stored as float. This sits within ~1e-5 of the real
//     float32 torch scheduler, well inside the test tolerances (1e-5 schedule,
//     1e-4 trajectory).
//
// Pure C++17, no engine headers -> lives in Core/ so the standalone clang harness
// (tests/standalone/build.sh) can verify it headlessly.
#pragma once

#include <cstddef>
#include <cmath>
#include <vector>

namespace mira {
namespace tdiff {

// The frozen config we port. Defaults are the exact values world_pipeline.py uses.
// (The "fixed-path" choices - dpmsolver++/midpoint/karras/epsilon/zero - are not
// fields because only one branch is ported; changing them would be a no-op here.)
struct EdmDpmConfig
{
	double sigma_min  = 0.002;
	double sigma_max  = 80.0;
	double sigma_data = 0.5;
	double rho        = 7.0;
	int    solver_order = 2; // we only implement order 1 and 2 (order=2 path)
};

class EdmDpmScheduler
{
public:
	explicit EdmDpmScheduler(const EdmDpmConfig& cfg = EdmDpmConfig())
		: cfg_(cfg)
	{
	}

	// --- schedule accessors -------------------------------------------------

	// sigmas has length num_inference_steps + 1 (the Karras sigmas with the
	// final_sigmas_type="zero" 0.0 appended).
	const std::vector<double>& sigmas() const { return sigmas_; }
	// timesteps has length num_inference_steps (the preconditioned noise levels).
	const std::vector<double>& timesteps() const { return timesteps_; }

	int num_inference_steps() const { return num_inference_steps_; }
	// Mirrors Python's step_index property (None -> -1 here).
	int step_index() const { return step_index_; }

	// _compute_karras_sigmas(ramp): the Karras et al. (2022) noise schedule.
	// ramp = linspace(0,1,n); sigma = (max^(1/rho) + ramp*(min^(1/rho) - max^(1/rho)))^rho.
	// scaling_p is None in our config so the optional rescale block is skipped.
	//
	// PARITY: torch builds this in float32 - `ramp` is a float32 linspace and the
	// `base**rho` rounds to float32 before we ever see the sigmas. To stay within
	// the 1e-5 schedule tolerance we mirror that float32 path exactly (the
	// sigma_min/max^(1/rho) scalars are python doubles, so the (min-max) difference
	// is formed in double then cast to float32, matching torch's scalar*tensor
	// promotion). Results are widened back to double for storage.
	std::vector<double> compute_karras_sigmas(int n) const
	{
		std::vector<double> out((size_t)n);
		const double min_inv_rho_d = std::pow(cfg_.sigma_min, 1.0 / cfg_.rho);
		const double max_inv_rho_d = std::pow(cfg_.sigma_max, 1.0 / cfg_.rho);
		const float diff_f    = (float)(min_inv_rho_d - max_inv_rho_d); // (min-max) in double -> f32
		const float max_inv_f = (float)max_inv_rho_d;
		const float rho_f     = (float)cfg_.rho;

		// torch.linspace(0,1,n) in float32 uses a two-sided fill (start side counts
		// up, end side counts down) so endpoints land exactly. Mirror it.
		const float step    = (n <= 1) ? 0.0f : (1.0f / (float)(n - 1));
		const int   halfway = n / 2;
		for (int i = 0; i < n; ++i)
		{
			float ramp;
			if (n == 1)            ramp = 0.0f;
			else if (i < halfway)  ramp = step * (float)i;
			else                   ramp = 1.0f - step * (float)(n - 1 - i);

			const float base  = max_inv_f + ramp * diff_f; // float32
			const float sigma = std::pow(base, rho_f);     // float32 powf
			out[(size_t)i] = (double)sigma;
		}
		return out;
	}

	// precondition_noise(sigma): c_noise = 0.25 * log(sigma). Used to build timesteps.
	static double precondition_noise(double sigma)
	{
		return 0.25 * std::log(sigma);
	}

	// set_timesteps(num_inference_steps): build the sigma/timestep schedule and
	// reset the multistep bookkeeping. Mirrors the Python method for our config.
	void set_timesteps(int num_inference_steps)
	{
		num_inference_steps_ = num_inference_steps;

		std::vector<double> sig = compute_karras_sigmas(num_inference_steps);

		// timesteps = precondition_noise(sigmas) (over the n Karras sigmas).
		timesteps_.assign(sig.size(), 0.0);
		for (size_t i = 0; i < sig.size(); ++i)
		{
			timesteps_[i] = precondition_noise(sig[i]);
		}

		// final_sigmas_type == "zero" -> append a 0.0 sigma.
		sigmas_ = sig;
		sigmas_.push_back(0.0);

		// reset solver state
		model_outputs_.assign((size_t)cfg_.solver_order, std::vector<float>());
		lower_order_nums_ = 0;
		step_index_ = -1; // None
	}

	// --- preconditioning (EDM) ---------------------------------------------

	// precondition_inputs(sample, sigma): scale model input by c_in = 1/sqrt(sigma^2+sigma_data^2).
	// In-place over a flat float buffer.
	void precondition_inputs(float* sample, std::size_t count, double sigma) const
	{
		const double c_in = 1.0 / std::sqrt(sigma * sigma + cfg_.sigma_data * cfg_.sigma_data);
		for (std::size_t j = 0; j < count; ++j)
		{
			sample[j] = (float)((double)sample[j] * c_in);
		}
	}

	// scale_model_input(sample, ...): EDM input scaling at the current step.
	// Initializes step_index to 0 if not yet set (sequential, unique-timestep path).
	void scale_model_input(float* sample, std::size_t count)
	{
		if (step_index_ < 0)
		{
			step_index_ = 0; // _init_step_index for the sequential denoise path
		}
		precondition_inputs(sample, count, sigmas_[(size_t)step_index_]);
	}

	// precondition_outputs(sample, model_output, sigma) for prediction_type="epsilon":
	//   c_skip = sigma_data^2 / (sigma^2 + sigma_data^2)
	//   c_out  = sigma*sigma_data / sqrt(sigma^2 + sigma_data^2)
	//   denoised = c_skip*sample + c_out*model_output
	// Writes the x0 prediction into out (float buffer).
	void precondition_outputs(const float* sample, const float* model_output,
	                          std::size_t count, double sigma, float* out) const
	{
		const double sd2    = cfg_.sigma_data * cfg_.sigma_data;
		const double denom  = sigma * sigma + sd2;
		const double c_skip = sd2 / denom;
		const double c_out  = sigma * cfg_.sigma_data / std::sqrt(denom);
		for (std::size_t j = 0; j < count; ++j)
		{
			out[j] = (float)(c_skip * (double)sample[j] + c_out * (double)model_output[j]);
		}
	}

	// convert_model_output(model_output, sample): DPMSolver++ needs the data
	// prediction (x0). thresholding is False for our config, so this is just
	// precondition_outputs.
	void convert_model_output(const float* model_output, const float* sample,
	                          std::size_t count, float* out) const
	{
		precondition_outputs(sample, model_output, count, sigmas_[(size_t)step_index_], out);
	}

	// --- step ---------------------------------------------------------------
	//
	// step(model_output, sample, prev_sample): one DPM-Solver++ multistep update.
	// 'model_output' is the RAW model output (un-preconditioned), same shape as
	// 'sample'; 'prev_sample' (count elements) receives the result. Call once per
	// inference step in order; step_index auto-advances. Equivalent to Python's
	// step() for our config (sequential, unique timesteps, no SDE noise).
	void step(const float* model_output, const float* sample,
	          float* prev_sample, std::size_t count)
	{
		if (step_index_ < 0)
		{
			step_index_ = 0; // _init_step_index for the sequential denoise path
		}

		// lower_order_final: for final_sigmas_type=="zero" this is simply the last step.
		const bool lower_order_final = (step_index_ == num_inference_steps_ - 1);

		// convert model output to the x0 (data) prediction and push into the ring.
		std::vector<float> converted((size_t)count);
		convert_model_output(model_output, sample, count, converted.data());

		// model_outputs shift: outputs[i] = outputs[i+1]; outputs[-1] = converted.
		for (int i = 0; i < cfg_.solver_order - 1; ++i)
		{
			model_outputs_[(size_t)i] = model_outputs_[(size_t)(i + 1)];
		}
		model_outputs_[(size_t)(cfg_.solver_order - 1)] = converted;

		// Select solver order. solver_order==2 path:
		//   - first step (or forced final) -> first-order (DDIM-equivalent)
		//   - otherwise -> second-order midpoint multistep
		if (cfg_.solver_order == 1 || lower_order_nums_ < 1 || lower_order_final)
		{
			dpm_solver_first_order_update(
				model_outputs_[(size_t)(cfg_.solver_order - 1)].data(),
				sample, prev_sample, count);
		}
		else
		{
			multistep_dpm_solver_second_order_update(sample, prev_sample, count);
		}

		if (lower_order_nums_ < cfg_.solver_order)
		{
			++lower_order_nums_;
		}
		++step_index_;
	}

private:
	// alpha_t == 1 always (inputs are pre-scaled), so lambda = -log(sigma).
	// Faithful to _sigma_to_alpha_sigma_t + the log(alpha)-log(sigma) lambdas.
	static double lambda_of(double sigma)
	{
		// log(alpha_t) - log(sigma) with alpha_t = 1 -> -log(sigma).
		// For sigma==0 this is +inf, which makes the final step return x0 (see below).
		return std::log(1.0) - std::log(sigma);
	}

	// dpm_solver_first_order_update (DPMSolver++):
	//   x_t = (sigma_t/sigma_s)*sample - (alpha_t*(exp(-h)-1))*D0
	// where D0 is the (converted) x0 prediction. For the last step sigma_t=0:
	//   sigma_t/sigma_s = 0, h = +inf, exp(-h) = 0  ->  x_t = D0 (the denoised sample).
	void dpm_solver_first_order_update(const float* d0, const float* sample,
	                                   float* x_t, std::size_t count) const
	{
		const double sigma_t = sigmas_[(size_t)(step_index_ + 1)];
		const double sigma_s = sigmas_[(size_t)step_index_];
		const double alpha_t = 1.0;
		const double lambda_t = lambda_of(sigma_t);
		const double lambda_s = lambda_of(sigma_s);
		const double h = lambda_t - lambda_s;

		const double c_sample = sigma_t / sigma_s;
		const double c_d0     = -(alpha_t * (std::exp(-h) - 1.0));
		for (std::size_t j = 0; j < count; ++j)
		{
			x_t[j] = (float)(c_sample * (double)sample[j] + c_d0 * (double)d0[j]);
		}
	}

	// multistep_dpm_solver_second_order_update (DPMSolver++, solver_type="midpoint"):
	//   m0 = outputs[-1], m1 = outputs[-2]
	//   h  = lambda_t - lambda_s0,  h_0 = lambda_s0 - lambda_s1,  r0 = h_0/h
	//   D0 = m0,  D1 = (1/r0)*(m0 - m1)
	//   x_t = (sigma_t/sigma_s0)*sample
	//         - (alpha_t*(exp(-h)-1))*D0
	//         - 0.5*(alpha_t*(exp(-h)-1))*D1
	void multistep_dpm_solver_second_order_update(const float* sample,
	                                              float* x_t, std::size_t count) const
	{
		const double sigma_t  = sigmas_[(size_t)(step_index_ + 1)];
		const double sigma_s0 = sigmas_[(size_t)step_index_];
		const double sigma_s1 = sigmas_[(size_t)(step_index_ - 1)];
		const double alpha_t  = 1.0;

		const double lambda_t  = lambda_of(sigma_t);
		const double lambda_s0 = lambda_of(sigma_s0);
		const double lambda_s1 = lambda_of(sigma_s1);

		const double h   = lambda_t - lambda_s0;
		const double h_0 = lambda_s0 - lambda_s1;
		const double r0  = h_0 / h;
		const double inv_r0 = 1.0 / r0;

		const double em1      = std::exp(-h) - 1.0;
		const double c_sample = sigma_t / sigma_s0;
		const double c_d0     = -(alpha_t * em1);
		const double c_d1     = -0.5 * (alpha_t * em1);

		const float* m0 = model_outputs_[(size_t)(cfg_.solver_order - 1)].data();
		const float* m1 = model_outputs_[(size_t)(cfg_.solver_order - 2)].data();
		for (std::size_t j = 0; j < count; ++j)
		{
			const double d0 = (double)m0[j];
			const double d1 = inv_r0 * ((double)m0[j] - (double)m1[j]);
			x_t[j] = (float)(c_sample * (double)sample[j] + c_d0 * d0 + c_d1 * d1);
		}
	}

	EdmDpmConfig cfg_;
	int num_inference_steps_ = 0;
	std::vector<double> sigmas_;     // length n+1
	std::vector<double> timesteps_;  // length n
	std::vector<std::vector<float>> model_outputs_; // ring of solver_order x0 predictions
	int lower_order_nums_ = 0;
	int step_index_ = -1; // -1 == Python None
};

} // namespace tdiff
} // namespace mira
