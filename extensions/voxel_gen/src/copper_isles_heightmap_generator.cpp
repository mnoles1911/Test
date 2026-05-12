#include "copper_isles_heightmap_generator.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

CopperIslesHeightmapGeneratorCpp::CopperIslesHeightmapGeneratorCpp() {}
CopperIslesHeightmapGeneratorCpp::~CopperIslesHeightmapGeneratorCpp() {}

// ----- Heightmap cache --------------------------------------------------
//
// _ensure_image loads the EXR on first call and caches it. Mutex-protected
// because Zylann calls generate_block from many worker threads concurrently.
// Without the lock, two threads can both pass the load-attempted check,
// both run img.load(), and the second's assignment to _heightmap_image
// stomps the first's WHILE other worker threads are mid-flight reading
// _heightmap_w / _heightmap_h / dereferencing the Ref. The observable
// failure mode is _heightmap_w==0 (or stale) for one chunk's calls,
// sample_gray returns 0.0, ground_y collapses to 0, the chunk gets
// terrain at world Y=0 instead of the heightmap's true height — and
// shows up as a floating cubic block in midair. The GD original had the
// same race in principle but the interpreter's slower per-call cost
// rarely exposed it.

Ref<Image> CopperIslesHeightmapGeneratorCpp::_ensure_image() {
    std::lock_guard<std::mutex> lock(_heightmap_mutex);
    if (_heightmap_load_attempted) {
        return _heightmap_image;
    }
    if (_heightmap_path.is_empty()) {
        UtilityFunctions::push_error("[CopperIslesCpp] heightmap_path is empty.");
        _heightmap_load_attempted = true;
        return Ref<Image>();
    }
    Ref<Image> img;
    img.instantiate();
    const Error err = img->load(_heightmap_path);
    if (err != OK) {
        UtilityFunctions::push_error(
                String("[CopperIslesCpp] Failed to load heightmap '") + _heightmap_path
                + String("' (err=") + String::num_int64(err) + String(").")
        );
        _heightmap_load_attempted = true;
        return Ref<Image>();
    }
    // Populate w/h BEFORE flipping the load-attempted flag so any thread
    // that observes the flag as true sees fully-populated state.
    _heightmap_w = img->get_width();
    _heightmap_h = img->get_height();
    _heightmap_image = img;
    _heightmap_load_attempted = true;
    UtilityFunctions::print(String("[CopperIslesCpp] Loaded heightmap ")
            + String::num_int64(_heightmap_w) + String("x") + String::num_int64(_heightmap_h)
            + String(" from ") + _heightmap_path);
    return _heightmap_image;
}

Ref<Image> CopperIslesHeightmapGeneratorCpp::ensure_image_const() const {
    // Mutable cache state populated under const semantics — matches the
    // "lazy load" pattern in the GDScript generator. The actual mutating
    // happens via the mutable members declared in the header.
    return const_cast<CopperIslesHeightmapGeneratorCpp *>(this)->_ensure_image();
}

// ----- Sampling ---------------------------------------------------------

double CopperIslesHeightmapGeneratorCpp::sample_gray(int world_x, int world_z) const {
    Ref<Image> img = ensure_image_const();
    if (!img.is_valid() || _heightmap_w == 0 || _heightmap_h == 0) {
        return 0.5;  // flat-sea-level fallback (matches GD)
    }
    const double u = static_cast<double>(world_x - _origin_x_voxels) / static_cast<double>(_extent_x_voxels);
    const double v = static_cast<double>(world_z - _origin_z_voxels) / static_cast<double>(_extent_z_voxels);
    if (u < 0.0 || u >= 1.0 || v < 0.0 || v >= 1.0) {
        return 0.0;  // deep ocean outside the heightmap rectangle
    }
    if (!_bilinear_sampling) {
        int px = static_cast<int>(u * static_cast<double>(_heightmap_w));
        int pz = static_cast<int>(v * static_cast<double>(_heightmap_h));
        if (px < 0) px = 0;
        if (px > _heightmap_w - 1) px = _heightmap_w - 1;
        if (pz < 0) pz = 0;
        if (pz > _heightmap_h - 1) pz = _heightmap_h - 1;
        return static_cast<double>(img->get_pixel(px, pz).r);
    }
    // Bilinear: GD uses floori (toward -inf) for the integer floor of the
    // fractional coords; (int)std::floor matches on negatives + positives.
    const double fx = u * static_cast<double>(_heightmap_w) - 0.5;
    const double fz = v * static_cast<double>(_heightmap_h) - 0.5;
    int x0 = static_cast<int>(std::floor(fx));
    int z0 = static_cast<int>(std::floor(fz));
    if (x0 < 0) x0 = 0;
    if (x0 > _heightmap_w - 1) x0 = _heightmap_w - 1;
    if (z0 < 0) z0 = 0;
    if (z0 > _heightmap_h - 1) z0 = _heightmap_h - 1;
    int x1 = x0 + 1;
    int z1 = z0 + 1;
    if (x1 > _heightmap_w - 1) x1 = _heightmap_w - 1;
    if (z1 > _heightmap_h - 1) z1 = _heightmap_h - 1;
    double tx = fx - std::floor(fx);
    double tz = fz - std::floor(fz);
    if (tx < 0.0) tx = 0.0; else if (tx > 1.0) tx = 1.0;
    if (tz < 0.0) tz = 0.0; else if (tz > 1.0) tz = 1.0;
    // Sample as float (Color.r is float32 in Godot), promote to double for
    // the lerp accumulation. Mirrors the GD generator's lerp() which works
    // in double-precision since GDScript float == double.
    const double g00 = static_cast<double>(img->get_pixel(x0, z0).r);
    const double g10 = static_cast<double>(img->get_pixel(x1, z0).r);
    const double g01 = static_cast<double>(img->get_pixel(x0, z1).r);
    const double g11 = static_cast<double>(img->get_pixel(x1, z1).r);
    const double g0 = g00 + (g10 - g00) * tx;
    const double g1 = g01 + (g11 - g01) * tx;
    return g0 + (g1 - g0) * tz;
}

int CopperIslesHeightmapGeneratorCpp::gray_to_ground_y(double gray) const {
    // GD: int(round(g * float(elevation_above_at_white_voxels)))
    // C++: std::lround matches roundi() (half-away-from-zero on positives).
    double g = gray;
    if (g < 0.0) g = 0.0;
    if (g > 1.0) g = 1.0;
    return static_cast<int>(std::lround(g * static_cast<double>(_elevation_above_at_white_voxels)));
}

int CopperIslesHeightmapGeneratorCpp::compute_ground_y(int world_x, int world_z) const {
    return gray_to_ground_y(sample_gray(world_x, world_z));
}

// ----- Property setters/getters -----------------------------------------

void CopperIslesHeightmapGeneratorCpp::set_heightmap_path(const String &p_value) {
    _heightmap_path = p_value;
    // Drop cache so the new path is loaded on next access.
    std::lock_guard<std::mutex> lock(_heightmap_mutex);
    _heightmap_load_attempted = false;
    _heightmap_image = Ref<Image>();
    _heightmap_w = 0;
    _heightmap_h = 0;
}
String CopperIslesHeightmapGeneratorCpp::get_heightmap_path() const { return _heightmap_path; }

void CopperIslesHeightmapGeneratorCpp::set_extent_x_voxels(int p_value) { _extent_x_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_extent_x_voxels() const { return _extent_x_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_extent_z_voxels(int p_value) { _extent_z_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_extent_z_voxels() const { return _extent_z_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_origin_x_voxels(int p_value) { _origin_x_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_origin_x_voxels() const { return _origin_x_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_origin_z_voxels(int p_value) { _origin_z_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_origin_z_voxels() const { return _origin_z_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_elevation_above_at_white_voxels(int p_value) { _elevation_above_at_white_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_elevation_above_at_white_voxels() const { return _elevation_above_at_white_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_bilinear_sampling(bool p_value) { _bilinear_sampling = p_value; }
bool CopperIslesHeightmapGeneratorCpp::get_bilinear_sampling() const { return _bilinear_sampling; }

// ----- ClassDB bindings -------------------------------------------------
//
// Only the heightmap-specific properties land here; everything else is
// inherited from HeightmapGeneratorBase::_bind_methods.

void CopperIslesHeightmapGeneratorCpp::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_heightmap_path", "path"), &CopperIslesHeightmapGeneratorCpp::set_heightmap_path);
    ClassDB::bind_method(D_METHOD("get_heightmap_path"), &CopperIslesHeightmapGeneratorCpp::get_heightmap_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "heightmap_path"), "set_heightmap_path", "get_heightmap_path");

    ClassDB::bind_method(D_METHOD("set_extent_x_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_extent_x_voxels);
    ClassDB::bind_method(D_METHOD("get_extent_x_voxels"), &CopperIslesHeightmapGeneratorCpp::get_extent_x_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "extent_x_voxels"), "set_extent_x_voxels", "get_extent_x_voxels");

    ClassDB::bind_method(D_METHOD("set_extent_z_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_extent_z_voxels);
    ClassDB::bind_method(D_METHOD("get_extent_z_voxels"), &CopperIslesHeightmapGeneratorCpp::get_extent_z_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "extent_z_voxels"), "set_extent_z_voxels", "get_extent_z_voxels");

    ClassDB::bind_method(D_METHOD("set_origin_x_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_origin_x_voxels);
    ClassDB::bind_method(D_METHOD("get_origin_x_voxels"), &CopperIslesHeightmapGeneratorCpp::get_origin_x_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "origin_x_voxels"), "set_origin_x_voxels", "get_origin_x_voxels");

    ClassDB::bind_method(D_METHOD("set_origin_z_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_origin_z_voxels);
    ClassDB::bind_method(D_METHOD("get_origin_z_voxels"), &CopperIslesHeightmapGeneratorCpp::get_origin_z_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "origin_z_voxels"), "set_origin_z_voxels", "get_origin_z_voxels");

    ClassDB::bind_method(D_METHOD("set_elevation_above_at_white_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_elevation_above_at_white_voxels);
    ClassDB::bind_method(D_METHOD("get_elevation_above_at_white_voxels"), &CopperIslesHeightmapGeneratorCpp::get_elevation_above_at_white_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "elevation_above_at_white_voxels"), "set_elevation_above_at_white_voxels", "get_elevation_above_at_white_voxels");

    ClassDB::bind_method(D_METHOD("set_bilinear_sampling", "v"), &CopperIslesHeightmapGeneratorCpp::set_bilinear_sampling);
    ClassDB::bind_method(D_METHOD("get_bilinear_sampling"), &CopperIslesHeightmapGeneratorCpp::get_bilinear_sampling);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "bilinear_sampling"), "set_bilinear_sampling", "get_bilinear_sampling");

    // Heightmap-only helpers
    ClassDB::bind_method(D_METHOD("sample_gray", "world_x", "world_z"), &CopperIslesHeightmapGeneratorCpp::sample_gray);
    ClassDB::bind_method(D_METHOD("gray_to_ground_y", "gray"), &CopperIslesHeightmapGeneratorCpp::gray_to_ground_y);
}
