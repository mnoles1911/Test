#pragma once

// CubicHeightmapGeneratorCpp — FastNoiseLite-based heightmap generator
// for World3D (Mira). All tier rules + chunk loop live in
// HeightmapGeneratorBase; this class adds only:
//   * The three noise layers (macro / mid / detail) + their amplitude
//     and frequency multiplier params
//   * Optional 8-meter quantization toggle
//   * The compute_ground_y override that ties them together
//
// Adapter pattern unchanged (`scripts/_dev/CubicHeightmapGeneratorAdapter.gd`
// extends VoxelGeneratorScript and forwards _generate_block here).

#include "heightmap_generator_base.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>

class CubicHeightmapGeneratorCpp : public HeightmapGeneratorBase {
    GDCLASS(CubicHeightmapGeneratorCpp, HeightmapGeneratorBase)

public:
    CubicHeightmapGeneratorCpp();
    ~CubicHeightmapGeneratorCpp();

    // --- FastNoiseLite + height-noise properties ---
    void set_noise(const godot::Ref<godot::FastNoiseLite> &p_noise);
    godot::Ref<godot::FastNoiseLite> get_noise() const;

    void set_height_range_voxels(double p_value);
    double get_height_range_voxels() const;

    void set_height_offset_voxels(int p_value);
    int get_height_offset_voxels() const;

    void set_quantize_to_meters(bool p_value);
    bool get_quantize_to_meters() const;

    void set_mid_amplitude_voxels(int p_value);
    int get_mid_amplitude_voxels() const;

    void set_mid_frequency_multiplier(double p_value);
    double get_mid_frequency_multiplier() const;

    void set_detail_amplitude_voxels(int p_value);
    int get_detail_amplitude_voxels() const;

    void set_detail_frequency_multiplier(double p_value);
    double get_detail_frequency_multiplier() const;

    // Override of HeightmapGeneratorBase::compute_ground_y. Samples three
    // FastNoiseLite layers (macro/mid/detail), adds the configured offset,
    // optionally quantizes to 8-meter steps. Pure function of instance
    // config + the FastNoiseLite resource — worker-thread safe.
    int compute_ground_y(int world_x, int world_z) const override;

protected:
    static void _bind_methods();

private:
    godot::Ref<godot::FastNoiseLite> _noise;
    // Amplitudes are in VOXELS. Rescaled 2026-06-12 for the 10 vox/m
    // pivot (x5/3 from the 6 vox/m values 900/60/10/2) so the terrain
    // keeps the same WORLD-metre shape. Frequency multipliers are
    // ratios relative to the macro noise — scale-independent.
    double _height_range_voxels = 1500.0;
    int _height_offset_voxels = 100;
    bool _quantize_to_meters = false;
    int _mid_amplitude_voxels = 17;
    double _mid_frequency_multiplier = 3.0;
    int _detail_amplitude_voxels = 3;
    double _detail_frequency_multiplier = 12.0;
};
