// VoxelChunkActor.cpp — M1 chunk generation + meshing.
#include "VoxelChunkActor.h"
#include "ProceduralMeshComponent.h"
#include "MiraVoxelMesh.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h" // UMaterialInstanceDynamic (LOD cross-fade scalar)

// Engine-agnostic Core (no Unreal types).
#include "Core/VoxelChunk.h"        // DenseGrid, make_mesh_slab, APRON
#include "Core/ChunkCoords.h"       // coords::CHUNK, chunk_origin_voxel, Vec3i
#include "Core/MaterialIds.h"       // mat::*
#include "Core/WaterByteCodec.h"    // WaterByteCodec::SOURCE_BYTE
#include "Core/MeshTypes.h"         // FaceClass (per-section material assignment)
#include "Core/GreedyMesher.h"      // greedy_mesh
#include "Core/WaterSurfaceMesher.h"// append_water_surface
#include "Core/FloraMesher.h"       // append_flora
#include "Core/HeightmapGenerator.h"// HeightmapGenerator (generator path)
#include "Core/NaniteBakeTiling.h"  // nanitebake::sample_crust_slab (editor crust bake)
#include "VoxelGenParams.h"         // FGenParams / BuildGen (shared generator snapshot)

AVoxelChunkActor::AVoxelChunkActor()
{
	PrimaryActorTick.bCanEverTick = false;

	Mesh = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("VoxelMesh"));
	Mesh->bUseAsyncCooking = true;
	SetRootComponent(Mesh);
}

// ---------------------------------------------------------------------------
// Hand-built first-light terrain inside the inner chunk [0..31]. Exercises every
// mesh section: opaque (stone/dirt/grass), water (a recessed pool), flora (a
// blade + a flower), and baked AO at the creases. Reached through the +APRON
// shift like everywhere else.
// ---------------------------------------------------------------------------
static void FillTestPattern(mira::DenseGrid& Slab)
{
	using namespace mira;
	auto SetT = [&](int x, int y, int z, uint8_t id) { Slab.set_type(x + APRON, y + APRON, z + APRON, id); };
	auto SetW = [&](int x, int y, int z, uint8_t b)  { Slab.set_water(x + APRON, y + APRON, z + APRON, b); };

	// Flat ground: stone, capped by dirt then a grass top at y=13.
	for (int x = 0; x < coords::CHUNK; ++x)
	for (int z = 0; z < coords::CHUNK; ++z)
	{
		for (int y = 0; y <= 13; ++y)
		{
			const uint8_t id = (y == 13) ? (uint8_t)mat::GRASS
			                  : (y >= 10) ? (uint8_t)mat::DIRT
			                              : (uint8_t)mat::STONE;
			SetT(x, y, z, id);
		}
	}

	// A little stone pillar so there's relief + AO to see.
	for (int y = 14; y < 19; ++y) SetT(8, y, 8, (uint8_t)mat::STONE);

	// A recessed water pool: carve the grass top and fill with full water.
	for (int x = 18; x < 24; ++x)
	for (int z = 18; z < 24; ++z)
	{
		SetT(x, 13, z, (uint8_t)mat::AIR);
		SetW(x, 13, z, (uint8_t)WaterByteCodec::SOURCE_BYTE);
	}

	// Flora sitting on the grass.
	SetT(4, 14, 4, (uint8_t)mat::GRASS_BLADE_ID);
	SetT(6, 14, 6, (uint8_t)mat::FLOWER_RED_ID);
}

// ---------------------------------------------------------------------------
// Fill the slab from the real Core generator for ChunkCoord. (The generator's
// ground sits around y~100-120, so use a chunk whose Y band straddles it.)
// ---------------------------------------------------------------------------
static void FillFromGenerator(mira::DenseGrid& Slab, const FIntVector& ChunkCoord, int32 Seed)
{
	using namespace mira;
	HeightmapGenerator Gen;
	Gen.set_seed((int64_t)Seed);

	const Vec3i Origin = coords::chunk_origin_voxel(Vec3i(ChunkCoord.X, ChunkCoord.Y, ChunkCoord.Z));

	for (int lz = -APRON; lz < coords::CHUNK + APRON; ++lz)
	for (int lx = -APRON; lx < coords::CHUNK + APRON; ++lx)
	{
		const int wx = Origin.x + lx;
		const int wz = Origin.z + lz;
		const ColumnInfo Col = Gen.resolve_column(wx, wz);

		for (int ly = -APRON; ly < coords::CHUNK + APRON; ++ly)
		{
			const int wy = Origin.y + ly;
			const int id = Gen.material_at(wx, wy, wz, Col);
			Slab.set_type(lx + APRON, ly + APRON, lz + APRON, (uint8_t)id);

			// Layer water into air cells below sea level.
			if (id == mat::AIR && Col.below_sea && wy <= Gen.sea_level_voxels)
			{
				Slab.set_water(lx + APRON, ly + APRON, lz + APRON, (uint8_t)WaterByteCodec::SOURCE_BYTE);
			}
		}

		// Drop the column's flora voxel just above the surface, if any.
		if (Col.flora_id != 0)
		{
			const int ly = (Col.ground_y + 1) - Origin.y;
			if (ly >= -APRON && ly < coords::CHUNK + APRON)
			{
				Slab.set_type(lx + APRON, ly + APRON, lz + APRON, (uint8_t)Col.flora_id);
			}
		}
	}
}

void AVoxelChunkActor::Rebuild()
{
	using namespace mira;

	DenseGrid Slab = make_mesh_slab(); // 34^3, apron 1
	if (bUseGenerator)
	{
		// The procedural ground sits at an unpredictable height (the legacy noise
		// has a big amplitude), so a fixed ChunkCoord.Y usually misses the surface
		// entirely -> the chunk is all-air (invisible) or all-solid (no exposed
		// faces, also invisible). Sample the ground at this chunk's centre column
		// and place the vertical band so the surface lands near the chunk's middle.
		HeightmapGenerator ProbeGen;
		ProbeGen.set_seed((int64_t)Seed);
		const Vec3i ColOrigin = coords::chunk_origin_voxel(Vec3i(ChunkCoord.X, 0, ChunkCoord.Z));
		const int GroundY = ProbeGen.compute_ground_y(ColOrigin.x + coords::CHUNK / 2,
		                                              ColOrigin.z + coords::CHUNK / 2);
		const int SurfaceChunkY = coords::floor_div(GroundY - coords::CHUNK / 2, coords::CHUNK);
		FillFromGenerator(Slab, FIntVector(ChunkCoord.X, SurfaceChunkY, ChunkCoord.Z), Seed);
	}
	else
	{
		FillTestPattern(Slab);
	}

	// Mesh it: solids (opaque + cutout, AO baked) + sloped water + billboard flora.
	MeshBuffers Mb = greedy_mesh(Slab);
	append_water_surface(Slab, Mb);
	append_flora(Slab, Mb);

	if (Mesh)
	{
		Mesh->ClearAllMeshSections();
		MiraVoxelMesh::ApplyMeshBuffers(Mesh, Mb, bReverseWinding, /*bCreateCollision=*/false);
	}
}

// ---------------------------------------------------------------------------
// World-managed render: AVoxelWorld extracted this slab from the authoritative
// brickmap and hands it to us. We just mesh + upload + assign materials. No
// generation here — the world owns the voxel data. (M2 multi-chunk path.)
// ---------------------------------------------------------------------------
// PURE Core mesh build — no UE objects touched, safe to run on a worker thread.
mira::MeshBuffers AVoxelChunkActor::BuildMeshBuffers(const mira::DenseGrid& Slab, bool bSolidsOnly)
{
	using namespace mira;
	MeshBuffers Mb = greedy_mesh(Slab);
	if (!bSolidsOnly)
	{
		// LOD chunks carry no water/flora (the downsample drops those channels), so
		// the mid/far bands mesh solids only; the near band still gets water + flora.
		append_water_surface(Slab, Mb);
		append_flora(Slab, Mb);
	}
	return Mb;
}

// PURE crust-tile sampler+mesher for the editor Nanite cold-bake (see header). Runs the
// generator INSIDE this module (where compute_ground_y/resolve_column are linked) so the
// bake module never references those unexported Core symbols. Mirrors MeshSuperPure.
FCrustTileMesh AVoxelChunkActor::SampleAndMeshCrustTile(const FGenParams& P,
                                                        int32 TileX, int32 TileZ,
                                                        int32 TileSpan, int32 Stride,
                                                        int32 SkirtDepth)
{
	using namespace mira;
	FCrustTileMesh Out;
	Out.Stride = Stride;

	HeightmapGenerator Gen;
	BuildGen(P, Gen);

	// Generator-backed callbacks bind the pure tiling math to this world's terrain — the
	// SAME compute_ground_y/resolve_column the live near voxels use (seam alignment).
	auto HeightAt = [&Gen](int wx, int wz) { return Gen.compute_ground_y(wx, wz); };
	auto TopIdAt  = [&Gen](int wx, int wz) -> uint8_t {
		return static_cast<uint8_t>(Gen.resolve_column(wx, wz).top_id);
	};

	const Vec2i Tile(TileX, TileZ);
	const nanitebake::CrustSlab Cr =
		nanitebake::sample_crust_slab(Tile, TileSpan, Stride, SkirtDepth, HeightAt, TopIdAt);

	Out.BaseFineY = Cr.base_fine_y;
	const nanitebake::TileBounds B = nanitebake::tile_bounds(Tile, TileSpan);
	Out.MinVoxelX = B.minX; Out.MinVoxelZ = B.minZ;
	Out.MaxVoxelX = B.maxX; Out.MaxVoxelZ = B.maxZ;

	if (!Cr.has_solid)
	{
		Out.bHasContent = false;
		return Out;
	}

	// Same greedy mesher the live + super-chunk paths use; solids only (no water/flora).
	Out.Mb = BuildMeshBuffers(Cr.slab, /*bSolidsOnly=*/true);
	Out.bHasContent = (Out.Mb.total_quads() > 0);
	return Out;
}

// Game-thread upload of finished buffers into the ProceduralMesh + per-FaceClass mats.
void AVoxelChunkActor::UploadMeshBuffers(const mira::MeshBuffers& Mb,
                                         UMaterialInterface* OpaqueMat,
                                         UMaterialInterface* WaterMat,
                                         UMaterialInterface* FloraMat,
                                         bool bCollision,
                                         bool bReverse,
                                         float PositionScale,
                                         const FColor* DebugColor)
{
	using namespace mira;
	if (!Mesh)
	{
		return;
	}

	// Cache the buffers + params so the DIAGNOSTIC RecolorDebug pass can re-upload the SAME
	// geometry with the debug tint toggled on/off when the tester flips mira.LodDebug — no
	// voxel regeneration. This is a render-side copy; it never touches the voxel/brick store.
	CachedMesh          = Mb;
	CachedOpaqueMat     = OpaqueMat;
	CachedWaterMat      = WaterMat;
	CachedFloraMat      = FloraMat;
	CachedCollision     = bCollision;
	CachedReverse       = bReverse;
	CachedPositionScale = PositionScale;
	bHasCachedMesh      = true;

	Mesh->ClearAllMeshSections();
	MiraVoxelMesh::ApplyMeshBuffers(Mesh, Mb, bReverse, bCollision, PositionScale, DebugColor);

	// Section index == FaceClass value (see MiraVoxelMesh::ApplyMeshBuffers).
	// Opaque + Cutout both draw atlas-free solid-colour terrain, so they share the
	// terrain material; water and flora get their own.
	if (OpaqueMat)
	{
		Mesh->SetMaterial(static_cast<int32>(FaceClass::Opaque), OpaqueMat);
		Mesh->SetMaterial(static_cast<int32>(FaceClass::Cutout), OpaqueMat);
	}
	if (WaterMat)
	{
		Mesh->SetMaterial(static_cast<int32>(FaceClass::Water), WaterMat);
	}
	if (FloraMat)
	{
		Mesh->SetMaterial(static_cast<int32>(FaceClass::Flora), FloraMat);
	}
}

// DIAGNOSTIC LOD debug-color recolor pass. Re-upload the LAST cached mesh with the debug
// tint applied (DebugColor != null) or removed (null = real albedo restored). Lets a LIVE
// `mira.LodDebug` toggle recolor already-loaded chunks WITHOUT regenerating voxels — we
// just re-run the GPU upload over the geometry we stashed at upload time. No-op if nothing
// was ever uploaded. Touches no voxel/brick data.
void AVoxelChunkActor::RecolorDebug(const FColor* DebugColor)
{
	if (!Mesh || !bHasCachedMesh)
	{
		return; // nothing meshed on this actor yet — nothing to recolor (safe no-op)
	}
	Mesh->ClearAllMeshSections();
	MiraVoxelMesh::ApplyMeshBuffers(Mesh, CachedMesh, CachedReverse, CachedCollision,
	                                CachedPositionScale, DebugColor);
	// Re-bind the per-FaceClass materials (ClearAllMeshSections dropped them). Mirror the
	// exact assignment UploadMeshBuffers does so the recolored mesh shades identically.
	if (CachedOpaqueMat)
	{
		Mesh->SetMaterial(static_cast<int32>(mira::FaceClass::Opaque), CachedOpaqueMat);
		Mesh->SetMaterial(static_cast<int32>(mira::FaceClass::Cutout), CachedOpaqueMat);
	}
	if (CachedWaterMat)
	{
		Mesh->SetMaterial(static_cast<int32>(mira::FaceClass::Water), CachedWaterMat);
	}
	if (CachedFloraMat)
	{
		Mesh->SetMaterial(static_cast<int32>(mira::FaceClass::Flora), CachedFloraMat);
	}
}

// ---------------------------------------------------------------------------
// LOD-transition dither cross-fade: push the per-chunk "FadeAlpha" scalar onto the
// TERRAIN section(s). See the header for the contract. This is the ONLY new render
// state the cross-fade adds, and it's only ever called from inside AVoxelWorld's
// flag-gated fade machine — when the flag is off this never runs, so a normal chunk's
// material binding is byte-for-byte what it was before.
// ---------------------------------------------------------------------------
void AVoxelChunkActor::SetFadeAlpha(float A)
{
	using namespace mira;
	if (!Mesh)
	{
		return; // no mesh component — nothing to fade (no-op safe)
	}

	// The terrain lives in the Opaque + Cutout sections (both share TerrainMaterial).
	// If neither section exists (e.g. this chunk meshed only water/flora, or is empty),
	// there's nothing to fade — bail without creating a MID.
	const int32 OpaqueIdx = static_cast<int32>(FaceClass::Opaque);
	const int32 CutoutIdx = static_cast<int32>(FaceClass::Cutout);
	const bool bHasOpaque = (Mesh->GetProcMeshSection(OpaqueIdx) != nullptr);
	const bool bHasCutout = (Mesh->GetProcMeshSection(CutoutIdx) != nullptr);
	if (!bHasOpaque && !bHasCutout)
	{
		return; // no terrain section on this actor — nothing to drive (no-op safe)
	}

	// Lazily create the dynamic material instance the FIRST time we fade. We base it on
	// whatever material is currently bound to a terrain section (that's TerrainMaterial,
	// assigned in UploadMeshBuffers); using the live binding means we don't need a
	// pointer back to the world's TerrainMaterial here. If that binding is somehow null
	// we can't build a MID, so we no-op (the fade just won't be visible — safe).
	if (!TerrainFadeMID)
	{
		const int32 BaseIdx = bHasOpaque ? OpaqueIdx : CutoutIdx;
		UMaterialInterface* Base = Mesh->GetMaterial(BaseIdx);
		if (!Base)
		{
			return; // no base material to instance — can't fade (no-op safe)
		}
		TerrainFadeMID = UMaterialInstanceDynamic::Create(Base, this);
		if (!TerrainFadeMID)
		{
			return; // creation failed (defensive) — no-op
		}
		// Bind the MID onto every terrain section that exists so both get the dither.
		if (bHasOpaque) { Mesh->SetMaterial(OpaqueIdx, TerrainFadeMID); }
		if (bHasCutout) { Mesh->SetMaterial(CutoutIdx, TerrainFadeMID); }
	}

	// Push the scalar the in-editor Dither node reads. Clamp defensively to [0,1].
	TerrainFadeMID->SetScalarParameterValue(TEXT("FadeAlpha"), FMath::Clamp(A, 0.0f, 1.0f));
}

// Synchronous convenience (unchanged behaviour): build then upload on the game thread.
void AVoxelChunkActor::RenderManaged(const mira::DenseGrid& Slab,
                                     UMaterialInterface* OpaqueMat,
                                     UMaterialInterface* WaterMat,
                                     UMaterialInterface* FloraMat,
                                     bool bCollision,
                                     bool bReverse,
                                     float PositionScale,
                                     bool bSolidsOnly)
{
	const mira::MeshBuffers Mb = BuildMeshBuffers(Slab, bSolidsOnly);
	UploadMeshBuffers(Mb, OpaqueMat, WaterMat, FloraMat, bCollision, bReverse, PositionScale);
}

void AVoxelChunkActor::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	// World-managed chunks are driven by AVoxelWorld::RenderManaged — never self-build.
	if (!bWorldManaged)
	{
		Rebuild(); // standalone: builds in-editor when placed/moved, no PIE needed
	}
}

void AVoxelChunkActor::BeginPlay()
{
	Super::BeginPlay();
	if (!bWorldManaged)
	{
		Rebuild();
	}
}
