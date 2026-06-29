// IHeightSource.h — the tiny abstract "where does the ground height come from?" interface.
//
// WHAT THIS IS (plain English):
// Every voxel column in the world asks the SAME question exactly once:
//   "at world voxel column (wx, wz), how high is the ground?"
// Today that question is answered by ONE of a few concrete things:
//   * the procedural noise field (HeightmapGenerator's own legacy/biome path), or
//   * an imported hand-crafted Gaea EXR  (mira::ImageHeightmap), or
//   * (Phase 2) a streaming AI diffusion surface that is invented on the fly as the
//     player explores  (mira::DiffusionHeightSource, lives in MiraThalTerrainAI).
//
// Right now HeightmapGenerator holds a `const ImageHeightmap*` — it is hard-wired to
// the ONE concrete override type. That works for a single bounded image, but a
// STREAMING world cannot be a single fixed image: the surface has to be assembled
// from many region tiles that come and go as the player moves. To let the generator
// talk to EITHER an image OR a streaming tile-cache without caring which, we hide the
// concrete type behind this minimal abstract base.
//
// THE CONTRACT (only three methods — deliberately the EXACT shape ImageHeightmap
// already exposes, so adopting this interface is a zero-behaviour-change refactor):
//   * valid()             — is this source ready to be sampled at all?
//   * sample_value()      — the raw, continuous source value at a world column
//                           (for an image: the bilinear-blended pixel value).
//   * height_voxels_at()  — that value mapped to an integer ground voxel-Y.
// compute_ground_y() only ever calls height_voxels_at(); sample_value() is kept in
// the contract because callers/tests that want the pre-vertical-map value rely on it,
// and it keeps the interface a faithful 1:1 of ImageHeightmap's public surface.
//
// INTENDED ADOPTION (NOT done in this header — see the Phase 2 design doc):
//   1. mira::ImageHeightmap  : public IHeightSource     (add the base + `override`s;
//      its three methods already match these signatures exactly, so this is purely
//      additive — no logic moves, no caller of ImageHeightmap changes).
//   2. HeightmapGenerator::height_src_  becomes `const IHeightSource*` and
//      set_height_source()/height_source() take/return `const IHeightSource*`.
//      compute_ground_y / resolve_column / material_at / column_is_cliff are
//      UNCHANGED — they only ever call through height_src_->height_voxels_at().
//   3. mira::DiffusionHeightSource (new, in MiraThalTerrainAI) implements this
//      interface over a resident region-tile cache (see the Phase 2 design).
//
// WHY A POINTER-TO-BASE IS SAFE HERE: HeightmapGenerator never OWNS the height
// source — set_height_source() documents that the caller keeps it alive across
// generation (the worker captures FGenParams by value, and *P.Heightmap is immutable
// until the world drains its column jobs). A non-owning `const IHeightSource*` keeps
// that exact lifetime contract; only the static type widens from one concrete class
// to the interface.
//
// PURE C++17, NO ENGINE HEADERS. Header-only, namespace mira. Must compile inside the
// Unreal module AND standalone under the clang harness (tests/standalone), exactly
// like ImageHeightmap.h / HeightmapGenerator.h sitting next to it.

#pragma once

namespace mira {

// =============================================================================
// IHeightSource — abstract "ground height provider" for HeightmapGenerator.
//
// A pure interface: no data members, no allocation, no engine types. Concrete
// implementations (ImageHeightmap today; DiffusionHeightSource in Phase 2) supply
// the three answers below. The generator holds only a `const IHeightSource*` and
// never deletes it (non-owning — the caller controls lifetime).
// =============================================================================
class IHeightSource {
public:
    virtual ~IHeightSource() = default;

    // Is this source ready to be sampled? A generator must treat a source that is
    // not valid() as "no override" and fall back to its procedural/biome path
    // (this mirrors HeightmapGenerator::height_source_active(), which already ANDs
    // a non-null pointer with valid()). For a streaming source, valid() means
    // "the cache is initialised and can answer" — NOT "every tile is resident";
    // a column whose tile is missing is handled by the service's defer-and-retry
    // BEFORE the worker ever samples (see the Phase 2 design), so by the time a
    // sample reaches here the covering tile is guaranteed resident.
    virtual bool valid() const = 0;

    // The raw, continuous source value at a world voxel column, BEFORE the vertical
    // (value -> voxel-Y) mapping. For an image this is the bilinear-blended pixel
    // value; for a streaming AI surface it is the detail-bridged continuous height
    // expressed in the source's own value units. Coordinates are world VOXELS and
    // are doubles so a caller can sample between columns if it wants. Off-domain
    // reads must not crash — clamp/extend rather than throw (ImageHeightmap clamps
    // to its border; a streaming source clamps within the resident tile).
    virtual float sample_value(double world_x, double world_z) const = 0;

    // The integer ground voxel-Y at a world column: sample_value() pushed through
    // this source's vertical mapping and floored to a whole voxel (so material
    // banding sits exactly on the surface). This is the ONLY method compute_ground_y
    // calls. World coordinates are ints here (a voxel column is integer-addressed),
    // matching the generator's per-column inner loop.
    virtual int height_voxels_at(int world_x, int world_z) const = 0;

protected:
    // Not meant to be sliced/copied through the base; concrete types manage their
    // own storage. Defaulted so derived classes stay trivially constructible.
    IHeightSource() = default;
    IHeightSource(const IHeightSource&) = default;
    IHeightSource& operator=(const IHeightSource&) = default;
};

} // namespace mira
