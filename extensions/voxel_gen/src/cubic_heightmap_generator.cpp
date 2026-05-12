#include "cubic_heightmap_generator.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

CubicHeightmapGeneratorCpp::CubicHeightmapGeneratorCpp() {}
CubicHeightmapGeneratorCpp::~CubicHeightmapGeneratorCpp() {}

// ----- Property setters / getters ----------------------------------------

void CubicHeightmapGeneratorCpp::set_noise(const Ref<FastNoiseLite> &p_noise) { _noise = p_noise; }
Ref<FastNoiseLite> CubicHeightmapGeneratorCpp::get_noise() const { return _noise; }

void CubicHeightmapGeneratorCpp::set_height_range_voxels(double p_value) { _height_range_voxels = p_value; }
double CubicHeightmapGeneratorCpp::get_height_range_voxels() const { return _height_range_voxels; }

void CubicHeightmapGeneratorCpp::set_height_offset_voxels(int p_value) { _height_offset_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_height_offset_voxels() const { return _height_offset_voxels; }

void CubicHeightmapGeneratorCpp::set_quantize_to_meters(bool p_value) { _quantize_to_meters = p_value; }
bool CubicHeightmapGeneratorCpp::get_quantize_to_meters() const { return _quantize_to_meters; }

void CubicHeightmapGeneratorCpp::set_mid_amplitude_voxels(int p_value) { _mid_amplitude_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_mid_amplitude_voxels() const { return _mid_amplitude_voxels; }

void CubicHeightmapGeneratorCpp::set_mid_frequency_multiplier(double p_value) { _mid_frequency_multiplier = p_value; }
double CubicHeightmapGeneratorCpp::get_mid_frequency_multiplier() const { return _mid_frequency_multiplier; }

void CubicHeightmapGeneratorCpp::set_detail_amplitude_voxels(int p_value) { _detail_amplitude_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_detail_amplitude_voxels() const { return _detail_amplitude_voxels; }

void CubicHeightmapGeneratorCpp::set_detail_frequency_multiplier(double p_value) { _detail_frequency_multiplier = p_value; }
double CubicHeightmapGeneratorCpp::get_detail_frequency_multiplier() const { return _detail_frequency_multiplier; }

// ----- Core: ground_y at a world (x, z) column ---------------------------
//
// Mirror of scripts/CubicHeightmapGenerator.gd _ground_y_at (line 572).
//
// Source GDScript (preserved here verbatim for cross-reference):
//
//   if noise == null:
//       return height_offset_voxels
//   var half_range: float = height_range_voxels * 0.5
//   var n_macro = noise.get_noise_2d(float(world_x), float(world_z))
//   var macro_y: int
//   if quantize_to_meters:
//       var macro_meters = roundi(n_macro * half_range / 8.0)
//       macro_y = macro_meters * 8
//   else:
//       macro_y = int(n_macro * half_range)
//   var n_mid = noise.get_noise_2d(world_x * mid_freq, world_z * mid_freq)
//   var mid_y = int(n_mid * mid_amplitude_voxels)
//   var n_detail = noise.get_noise_2d(world_x * detail_freq, world_z * detail_freq)
//   var detail_y = int(n_detail * detail_amplitude_voxels)
//   return macro_y + mid_y + detail_y + height_offset_voxels
//
// Parity gotchas:
//   * int(float) in GDScript truncates toward zero. static_cast<int>(double)
//     in C++ also truncates toward zero (C++ standard).
//   * roundi(float) in GDScript rounds half-away-from-zero. std::lround
//     (C++) matches.
//   * FastNoiseLite::get_noise_2d returns float (single precision). Store
//     the result in double immediately after sampling — mixed single/double
//     promotion in late accumulation produces a 1-ULP delta that can flip
//     an int truncation 0.01 % of the time.
int CubicHeightmapGeneratorCpp::compute_ground_y(int world_x, int world_z) const {
    if (_noise.is_null()) {
        return _height_offset_voxels;
    }

    const double half_range = _height_range_voxels * 0.5;

    const double n_macro = static_cast<double>(_noise->get_noise_2d(static_cast<double>(world_x),
                                                                   static_cast<double>(world_z)));
    int macro_y;
    if (_quantize_to_meters) {
        const long macro_meters = std::lround(n_macro * half_range / 8.0);
        macro_y = static_cast<int>(macro_meters * 8L);
    } else {
        macro_y = static_cast<int>(n_macro * half_range);
    }

    const double n_mid = static_cast<double>(_noise->get_noise_2d(
            static_cast<double>(world_x) * _mid_frequency_multiplier,
            static_cast<double>(world_z) * _mid_frequency_multiplier));
    const int mid_y = static_cast<int>(n_mid * static_cast<double>(_mid_amplitude_voxels));

    const double n_detail = static_cast<double>(_noise->get_noise_2d(
            static_cast<double>(world_x) * _detail_frequency_multiplier,
            static_cast<double>(world_z) * _detail_frequency_multiplier));
    const int detail_y = static_cast<int>(n_detail * static_cast<double>(_detail_amplitude_voxels));

    return macro_y + mid_y + detail_y + _height_offset_voxels;
}

// ----- ClassDB bindings --------------------------------------------------
//
// Only the FastNoiseLite-specific properties land here; everything else
// is inherited from HeightmapGeneratorBase::_bind_methods.

void CubicHeightmapGeneratorCpp::_bind_methods() {
    // noise
    ClassDB::bind_method(D_METHOD("set_noise", "noise"), &CubicHeightmapGeneratorCpp::set_noise);
    ClassDB::bind_method(D_METHOD("get_noise"), &CubicHeightmapGeneratorCpp::get_noise);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "noise", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite"),
                 "set_noise", "get_noise");

    // height_range_voxels
    ClassDB::bind_method(D_METHOD("set_height_range_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_height_range_voxels);
    ClassDB::bind_method(D_METHOD("get_height_range_voxels"),
                         &CubicHeightmapGeneratorCpp::get_height_range_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_range_voxels"),
                 "set_height_range_voxels", "get_height_range_voxels");

    // height_offset_voxels
    ClassDB::bind_method(D_METHOD("set_height_offset_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_height_offset_voxels);
    ClassDB::bind_method(D_METHOD("get_height_offset_voxels"),
                         &CubicHeightmapGeneratorCpp::get_height_offset_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "height_offset_voxels"),
                 "set_height_offset_voxels", "get_height_offset_voxels");

    // quantize_to_meters
    ClassDB::bind_method(D_METHOD("set_quantize_to_meters", "value"),
                         &CubicHeightmapGeneratorCpp::set_quantize_to_meters);
    ClassDB::bind_method(D_METHOD("get_quantize_to_meters"),
                         &CubicHeightmapGeneratorCpp::get_quantize_to_meters);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "quantize_to_meters"),
                 "set_quantize_to_meters", "get_quantize_to_meters");

    // mid_amplitude_voxels
    ClassDB::bind_method(D_METHOD("set_mid_amplitude_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_mid_amplitude_voxels);
    ClassDB::bind_method(D_METHOD("get_mid_amplitude_voxels"),
                         &CubicHeightmapGeneratorCpp::get_mid_amplitude_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "mid_amplitude_voxels"),
                 "set_mid_amplitude_voxels", "get_mid_amplitude_voxels");

    // mid_frequency_multiplier
    ClassDB::bind_method(D_METHOD("set_mid_frequency_multiplier", "value"),
                         &CubicHeightmapGeneratorCpp::set_mid_frequency_multiplier);
    ClassDB::bind_method(D_METHOD("get_mid_frequency_multiplier"),
                         &CubicHeightmapGeneratorCpp::get_mid_frequency_multiplier);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mid_frequency_multiplier"),
                 "set_mid_frequency_multiplier", "get_mid_frequency_multiplier");

    // detail_amplitude_voxels
    ClassDB::bind_method(D_METHOD("set_detail_amplitude_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_detail_amplitude_voxels);
    ClassDB::bind_method(D_METHOD("get_detail_amplitude_voxels"),
                         &CubicHeightmapGeneratorCpp::get_detail_amplitude_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "detail_amplitude_voxels"),
                 "set_detail_amplitude_voxels", "get_detail_amplitude_voxels");

    // detail_frequency_multiplier
    ClassDB::bind_method(D_METHOD("set_detail_frequency_multiplier", "value"),
                         &CubicHeightmapGeneratorCpp::set_detail_frequency_multiplier);
    ClassDB::bind_method(D_METHOD("get_detail_frequency_multiplier"),
                         &CubicHeightmapGeneratorCpp::get_detail_frequency_multiplier);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "detail_frequency_multiplier"),
                 "set_detail_frequency_multiplier", "get_detail_frequency_multiplier");
}
