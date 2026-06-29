// MiraVoxelMesh.cpp — MeshBuffers -> ProceduralMeshComponent.
#include "MiraVoxelMesh.h"
#include "ProceduralMeshComponent.h"

// The Core headers (engine-agnostic, no Unreal types) drop straight in.
#include "Core/MeshTypes.h"

void MiraVoxelMesh::ApplyMeshBuffers(UProceduralMeshComponent* Pmc,
                                     const mira::MeshBuffers& Mb,
                                     bool bReverseWinding,
                                     bool bCreateCollision,
                                     float PositionScale,
                                     const FColor* DebugColor)
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
		TArray<FVector2D>        UV1; // WATER FLOW vector (flow_x, flow_z); 0 elsewhere
		TArray<FVector2D>        UV2; // unused (empty) — kept so we can use the 4-UV overload
		TArray<FVector2D>        UV3; // unused (empty)
		TArray<FColor>           Colors;
		TArray<int32>            Triangles;
		TArray<FProcMeshTangent> Tangents; // left empty — PMC derives tangents

		Positions.Reserve(NumVerts);
		Normals.Reserve(NumVerts);
		UV0.Reserve(NumVerts);
		UV1.Reserve(NumVerts);
		Colors.Reserve(NumVerts);

		for (const MeshVertex& V : Sec.vertices)
		{
			Positions.Add(PositionToUE(V.px, V.py, V.pz) * PositionScale);
			Normals.Add(NormalToUE(V.nx, V.ny, V.nz));
			UV0.Add(FVector2D(V.u, V.v));

			// UV1 = the per-vertex WATER FLOW direction (world-XZ) the mesher baked in.
			// For the Water section these are the scroll vector a Single Layer Water
			// material reads to drift its normals/foam downstream; for every other
			// section (solids/flora/leaves) the mesher left flow at its default (0,0),
			// so UV1 is all-zero there and changes NOTHING about how solids render.
			// We keep UV0 exactly as before — this is a NEW, additive channel only.
			UV1.Add(FVector2D(V.flow_x, V.flow_z));

			// Vertex color carries TWO things the material reads separately:
			//   rgb = baked solid albedo (base_color × per-face shade, from the mesher)
			//   a   = ambient occlusion (0..1 -> 0..255)
			// So the material does albedo (rgb) × AO (alpha) at shade time.
			const uint8 AoA = static_cast<uint8>(FMath::Clamp(V.ao * 255.0f, 0.0f, 255.0f));
			if (DebugColor)
			{
				// DIAGNOSTIC LOD-color mode: swap the real albedo (rgb) for the flat per-LOD
				// debug tint, but KEEP this vertex's AO in alpha so the form still reads. The
				// Core MeshBuffers is unchanged — this only rewrites the GPU-bound color here.
				Colors.Add(FColor(DebugColor->R, DebugColor->G, DebugColor->B, AoA));
			}
			else
			{
				Colors.Add(FColor(V.cr, V.cg, V.cb, AoA));
			}
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

		// Use the 4-UV-channel overload so UV1 (water flow) reaches the GPU. UV2/UV3
		// stay empty (cost nothing when empty). UV0 + every other argument is identical
		// to the previous single-UV call — solids are byte-for-byte unchanged.
		Pmc->CreateMeshSection(s, Positions, Triangles, Normals, UV0, UV1, UV2, UV3,
		                       Colors, Tangents, bCreateCollision);
	}
}
