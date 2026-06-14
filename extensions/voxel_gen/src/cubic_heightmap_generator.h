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
    // 10 vox/m migration (2026-06-14): voxel-coordinate amplitude/offset defaults
    // scaled x10/6 from the old 6 vox/m values so terrain keeps the SAME physical
    // height in metres at terrain.transform.scale = 0.1. Frequency multipliers are
    // dimensionless and unchanged; the per-voxel noise frequency lives on the
    // FastNoiseLite resource (scaled x6/10 there). height_range is overridden per
    // scene (.tscn), but offset/amplitudes fall through to these defaults.
    //   height_range  900 -> 1500   offset 60 -> 100
    //   mid_amplitude  10 -> 17      detail_amplitude 2 -> 3
    godot::Ref<godot::FastNoiseLite> _noise;
    double _height_range_voxels = 1500.0;
    int _height_offset_voxels = 100;
    bool _quantize_to_meters = false;
    int _mid_amplitude_voxels = 17;
    double _mid_frequency_multiplier = 3.0;
    int _detail_amplitude_voxels = 3;
    double _detail_frequency_multiplier = 12.0;
};
