// MiraVoxelMesh.cpp — MeshBuffers -> ProceduralMeshComponent.
#include "MiraVoxelMesh.h"
#include "ProceduralMeshComponent.h"

// The Core headers (engine-agnostic, no Unreal types) drop straight in.
#include "Core/MeshTypes.h"

void MiraVoxelMesh::ApplyMeshBuffers(UProceduralMeshComponent* Pmc,
                                     const mira::MeshBuffers& Mb,
                                     bool bReverseWinding,
                                     bool bCreateCollision)
{
	using namespace mira;
	if (!Pmc)
	{
		return;
	}

	for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s)
	{
		const MeshSection& Sec = Mb.sections[s];
		if (Sec.indices.empty())
		{
			continue; // nothing in this transparency class
		}

		const int32 NumVerts = static_cast<int32>(Sec.vertices.size());

		TArray<FVector>          Positions;
		TArray<FVector>          Normals;
		TArray<FVector2D>        UV0;
		TArray<FColor>           Colors;
		TArray<int32>            Triangles;
		TArray<FProcMeshTangent> Tangents; // left empty — PMC derives tangents

		Positions.Reserve(NumVerts);
		Normals.Reserve(NumVerts);
		UV0.Reserve(NumVerts);
		Colors.Reserve(NumVerts);

		for (const MeshVertex& V : Sec.vertices)
		{
			Positions.Add(PositionToUE(V.px, V.py, V.pz));
			Normals.Add(NormalToUE(V.nx, V.ny, V.nz));
			UV0.Add(FVector2D(V.u, V.v));

			// Vertex color carries TWO things the material reads separately:
			//   rgb = baked solid albedo (base_color × per-face shade, from the mesher)
			//   a   = ambient occlusion (0..1 -> 0..255)
			// So the material does albedo (rgb) × AO (alpha) at shade time.
			const uint8 AoA = static_cast<uint8>(FMath::Clamp(V.ao * 255.0f, 0.0f, 255.0f));
			Colors.Add(FColor(V.cr, V.cg, V.cb, AoA));
		}

		Triangles.Reserve(static_cast<int32>(Sec.indices.size()));
		for (size_t i = 0; i + 2 < Sec.indices.size(); i += 3)
		{
			const int32 I0 = static_cast<int32>(Sec.indices[i + 0]);
			const int32 I1 = static_cast<int32>(Sec.indices[i + 1]);
			const int32 I2 = static_cast<int32>(Sec.indices[i + 2]);
			if (bReverseWinding)
			{
				Triangles.Add(I0); Triangles.Add(I2); Triangles.Add(I1);
			}
			else
			{
				Triangles.Add(I0); Triangles.Add(I1); Triangles.Add(I2);
			}
		}

		Pmc->CreateMeshSection(s, Positions, Triangles, Normals, UV0, Colors, Tangents, bCreateCollision);
	}
}
