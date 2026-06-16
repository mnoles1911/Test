// VoxelChunkActor.cpp — M1 chunk generation + meshing.
#include "VoxelChunkActor.h"
#include "ProceduralMeshComponent.h"
#include "MiraVoxelMesh.h"

// Engine-agnostic Core (no Unreal types).
#include "Core/VoxelChunk.h"        // DenseGrid, make_mesh_slab, APRON
#include "Core/ChunkCoords.h"       // coords::CHUNK, chunk_origin_voxel, Vec3i
#include "Core/MaterialIds.h"       // mat::*
#include "Core/WaterByteCodec.h"    // WaterByteCodec::SOURCE_BYTE
#include "Core/GreedyMesher.h"      // greedy_mesh
#include "Core/WaterSurfaceMesher.h"// append_water_surface
#include "Core/FloraMesher.h"       // append_flora
#include "Core/HeightmapGenerator.h"// HeightmapGenerator (generator path)

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
		FillFromGenerator(Slab, ChunkCoord, Seed);
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

void AVoxelChunkActor::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	Rebuild(); // builds in-editor when placed/moved, no PIE needed
}

void AVoxelChunkActor::BeginPlay()
{
	Super::BeginPlay();
	Rebuild();
}
