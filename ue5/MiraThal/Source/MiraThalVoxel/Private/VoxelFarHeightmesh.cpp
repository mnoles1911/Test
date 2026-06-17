// VoxelFarHeightmesh.cpp — build + upload the whole-map vista mesh.
#include "VoxelFarHeightmesh.h"
#include "HeightmapImport.h"            // MiraHeightmapImport::LoadHeightmapImage
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Misc/Paths.h"

// Engine-agnostic Core.
#include "Core/FarHeightmesh.h"        // build_far_heightmesh, FarHeightmesh
#include "Core/HeightmapGenerator.h"   // compute_ground_y + resolve_column (color/height)
#include "Core/VoxelColor.h"           // base_color
#include "Core/MaterialIds.h"

AVoxelFarHeightmesh::AVoxelFarHeightmesh()
{
	PrimaryActorTick.bCanEverTick = false;
	Mesh = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("FarMesh"));
	RootComponent = Mesh;
	Mesh->SetMobility(EComponentMobility::Static);
	// The vista is purely visual — no collision (the player walks on the voxels).
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
}

void AVoxelFarHeightmesh::BeginPlay()
{
	Super::BeginPlay();
	if (bBuildOnBeginPlay)
	{
		BuildFarMesh();
	}
}

bool AVoxelFarHeightmesh::LoadHeightmap()
{
	Heightmap = mira::ImageHeightmap(); // reset

	FString Path = HeightmapFile.FilePath;
	if (!Path.IsEmpty() && FPaths::IsRelative(Path))
	{
		Path = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir(), Path);
	}

	FString LoadError;
	if (Path.IsEmpty() || !MiraHeightmapImport::LoadHeightmapImage(Path, Heightmap, LoadError))
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThal] FarMesh EXR load failed (%s)"),
			Path.IsEmpty() ? TEXT("no file set") : *LoadError);
		return false;
	}

	constexpr double VoxelsPerMetre = 10.0;
	const double SpanVoxels = static_cast<double>(MapSpanMeters) * VoxelsPerMetre;
	Heightmap.set_centered_extent(SpanVoxels, SpanVoxels);
	Heightmap.vertical_scale_voxels = static_cast<double>(HeightmapAltitudeMeters) * VoxelsPerMetre;
	Heightmap.vertical_base_voxels  = static_cast<double>(HeightmapBaseMeters) * VoxelsPerMetre;
	Heightmap.flip_z = bFlipHeightmapZ;
	return true;
}

void AVoxelFarHeightmesh::BuildFarMesh()
{
	using namespace mira;

	if (!LoadHeightmap())
	{
		return;
	}

	// Generator over the same EXR so far heights/colors match the near voxels.
	HeightmapGenerator Gen;
	Gen.set_seed(static_cast<int64_t>(Seed));
	Gen.set_height_source(&Heightmap);

	const int Bias = VerticalBiasVoxels;
	auto HeightAt = [&Gen, Bias](int wx, int wz) { return Gen.compute_ground_y(wx, wz) - Bias; };
	auto ColorAt  = [&Gen](int wx, int wz) {
		const ColumnInfo Col = Gen.resolve_column(wx, wz);
		return base_color(Col.top_id);
	};

	const FarHeightmesh FM = build_far_heightmesh(Heightmap, GridResolution, HeightAt, ColorAt);
	if (!FM.valid())
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThal] FarMesh build produced an empty mesh"));
		return;
	}

	// --- Convert Core (voxel space) -> UE arrays. PositionToUE: (vx,vy,vz)->(vx,vz,vy)*10. ---
	const int NumV = FM.vertex_count();
	TArray<FVector> Positions; Positions.Reserve(NumV);
	TArray<FVector> Normals;   Normals.Reserve(NumV);
	TArray<FColor>  Colors;    Colors.Reserve(NumV);
	TArray<FVector2D> UVs;     UVs.Reserve(NumV);
	const float U = 10.0f;

	for (const FarMeshVertex& v : FM.vertices)
	{
		Positions.Add(FVector(v.px * U, v.pz * U, v.py * U));
		Normals.Add(FVector(v.nx, v.nz, v.ny)); // same axis swap, unit length preserved
		Colors.Add(FColor(v.r, v.g, v.b, 255)); // RGB = sRGB palette, A = AO (none -> 255)
		UVs.Add(FVector2D(v.px, v.pz));         // world-ish UVs (unused by the vertex-color mat)
	}

	TArray<int32> Tris; Tris.Reserve(FM.indices.size());
	if (bReverseWinding)
	{
		for (size_t i = 0; i + 2 < FM.indices.size(); i += 3)
		{
			Tris.Add(static_cast<int32>(FM.indices[i + 0]));
			Tris.Add(static_cast<int32>(FM.indices[i + 2]));
			Tris.Add(static_cast<int32>(FM.indices[i + 1]));
		}
	}
	else
	{
		for (uint32 idx : FM.indices)
		{
			Tris.Add(static_cast<int32>(idx));
		}
	}

	Mesh->ClearAllMeshSections();
	Mesh->CreateMeshSection(0, Positions, Tris, Normals, UVs, Colors,
		TArray<FProcMeshTangent>(), /*bCreateCollision=*/false);
	if (Material)
	{
		Mesh->SetMaterial(0, Material);
	}

	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] FarMesh built: %d verts, %d tris (grid %d, span %.0f m)."),
		NumV, FM.triangle_count(), FM.grid_n, MapSpanMeters);
}

void AVoxelFarHeightmesh::ClearFarMesh()
{
	if (Mesh)
	{
		Mesh->ClearAllMeshSections();
	}
}
