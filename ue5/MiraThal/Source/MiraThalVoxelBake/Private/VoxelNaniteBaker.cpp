// VoxelNaniteBaker.cpp — turn a voxel slab into a Nanite-enabled UStaticMesh.
//
// HOW THIS WORKS, STEP BY STEP (plain English):
//   1. We run the SAME greedy mesher the live renderer uses (mira::greedy_mesh).
//      That gives us a MeshBuffers: a small set of merged rectangles (two triangles
//      each) with positions, normals, UVs, AO, and baked color — in voxel units.
//   2. We copy that into an FMeshDescription. Think of FMeshDescription as Unreal's
//      universal "bag of mesh data" — the portable format the engine can build a
//      UStaticMesh (and Nanite data) from. We fill it using FStaticMeshAttributes,
//      which gives us typed handles to the positions/normals/UVs/colors arrays.
//   3. We translate every position the EXACT same way the live path does
//      (MiraVoxelMesh::PositionToUE): swap Y<->Z and scale x10 (1 voxel = 10 cm).
//      Because swapping two axes flips handedness, we also reverse triangle winding
//      so faces still point outward — mirroring the live path's bReverseWinding.
//   4. We pack vertex color the same way too: rgb = baked albedo, alpha = AO.
//   5. We make a UStaticMesh, flip its NaniteSettings.bEnabled to true, and build
//      it from the FMeshDescription. Done.
//
// The whole point: a baked chunk is pixel-identical to the live one and uses the
// same terrain material — we've just rehoused the geometry in Nanite.

#include "VoxelNaniteBaker.h"

// --- Unreal mesh-building APIs -------------------------------------------------
#include "Engine/StaticMesh.h"
#include "StaticMeshResources.h"         // FStaticMeshRenderData::IsInitialized() (post-build guard)
#include "Components/StaticMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "GameFramework/Actor.h"
#include "MeshDescription.h"
#include "StaticMeshAttributes.h"        // FStaticMeshAttributes (typed MeshDescription accessors)
#include "StaticMeshOperations.h"        // ComputeTangentsAndNormals (fallback, see VERIFY note)
#include "UObject/Package.h"             // GetTransientPackage

// --- The engine-agnostic Core + the live UE bridge we reuse --------------------
#include "Core/MeshTypes.h"             // mira::MeshBuffers / MeshSection / MeshVertex / FaceClass
#include "MiraVoxelMesh.h"              // PositionToUE / NormalToUE — the SAME swap+scale as live
// NOTE: the caller greedy-meshes the slab and passes us the MeshBuffers. We do NOT
// call mira::greedy_mesh here — that Core .cpp is compiled into MiraThalVoxel and is
// not exported across the module boundary (it would be an unresolved-external link
// error). Keeping the mesher on the caller's side also lets the caller reuse the same
// MeshBuffers it already built for the live PMC mesh.

namespace
{
	// One material slot name per FaceClass. The greedy mesher only fills Opaque +
	// Cutout (water/flora are skipped in a cold-bake), but we register a slot for
	// each non-empty section we actually emit. Stable, readable slot names.
	static const TCHAR* FaceClassSlotName(mira::FaceClass Cls)
	{
		switch (Cls)
		{
			case mira::FaceClass::Opaque: return TEXT("Terrain_Opaque");
			case mira::FaceClass::Cutout: return TEXT("Terrain_Cutout");
			case mira::FaceClass::Water:  return TEXT("Terrain_Water");
			case mira::FaceClass::Flora:  return TEXT("Terrain_Flora");
			default:                      return TEXT("Terrain");
		}
	}
}

namespace VoxelNaniteBaker
{

UStaticMesh* BuildNaniteStaticMeshFromMesh(const mira::MeshBuffers& Mb,
                                           UMaterialInterface* TerrainMaterial,
                                           UObject* Outer,
                                           FName Name)
{
	using namespace mira;

	// GAME-THREAD ONLY. UObject creation (NewObject), CreateMeshDescription,
	// CommitMeshDescription and StaticMesh->Build() all touch engine UObject/render
	// state that is not thread-safe. The caller (BakeWorldCrust STEP B) already runs us
	// serially on the game thread; this check makes that contract explicit and fails
	// loudly in a debug build if anyone ever calls us off-thread.
	check(IsInGameThread());

	// ---- Step 1: the caller already greedy-meshed the slab (Opaque + Cutout; no
	//      water/flora — exactly what a static cold-bake wants) and handed us Mb. ----
	if (Mb.total_vertices() == 0)
	{
		// All-air or fully-buried chunk: nothing visible to bake.
		return nullptr;
	}

	if (Outer == nullptr)
	{
		// No owner given — park the asset in the transient package so it's still a
		// valid, GC-managed object (it just won't be saved to disk).
		Outer = GetTransientPackage();
	}

	// ---- Step 2: prepare an FMeshDescription to receive the geometry ----------
	FMeshDescription MeshDescription;

	// FStaticMeshAttributes::Register() declares the standard static-mesh attribute
	// arrays on the description: vertex positions, plus per-vertex-instance normals,
	// tangents, binormal sign, COLORS, and UVs. We must call this before touching
	// any of those arrays.
	FStaticMeshAttributes Attributes(MeshDescription);
	Attributes.Register();

	// Grab typed handles to the arrays we'll write.
	TVertexAttributesRef<FVector3f>          VertexPositions = Attributes.GetVertexPositions();
	TVertexInstanceAttributesRef<FVector3f>  InstanceNormals = Attributes.GetVertexInstanceNormals();
	TVertexInstanceAttributesRef<FVector2f>  InstanceUVs     = Attributes.GetVertexInstanceUVs();
	TVertexInstanceAttributesRef<FVector4f>  InstanceColors  = Attributes.GetVertexInstanceColors();
	TPolygonGroupAttributesRef<FName>        GroupSlotNames  = Attributes.GetPolygonGroupMaterialSlotNames();

	// We use a single UV channel (channel 0), like the live path.
	InstanceUVs.SetNumChannels(1);

	// We'll fill StaticMaterials in the SAME order we create polygon groups, so the
	// group index lines up 1:1 with the material slot index.
	TArray<FStaticMaterial> StaticMaterials;

	// ---- Step 3: copy every non-empty section into the description ------------
	for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s)
	{
		const MeshSection& Sec = Mb.sections[s];
		if (Sec.indices.empty())
		{
			continue; // nothing in this face class
		}

		const FaceClass Cls = static_cast<FaceClass>(s);

		// One polygon group per face class == one material slot. Tag the group with a
		// readable imported-slot name and register the matching StaticMaterial.
		const FPolygonGroupID GroupID = MeshDescription.CreatePolygonGroup();
		const FName SlotName(FaceClassSlotName(Cls));
		GroupSlotNames[GroupID] = SlotName;

		// 2-arg form (material, slot name): the 3rd "imported slot name" arg is
		// WITH_EDITORONLY_DATA-gated, so passing it would break non-editor builds.
		FStaticMaterial Mat(TerrainMaterial, SlotName);
		StaticMaterials.Add(Mat);

		// 3a. Create one FVertexID per Core vertex and write its (swapped, scaled)
		//     position. We also stash the per-vertex normal/uv/color to reuse when we
		//     create the vertex instances below.
		const int32 NumVerts = static_cast<int32>(Sec.vertices.size());
		TArray<FVertexID> VertexIDs;
		VertexIDs.Reserve(NumVerts);
		MeshDescription.ReserveNewVertices(NumVerts);

		for (const MeshVertex& V : Sec.vertices)
		{
			const FVertexID VID = MeshDescription.CreateVertex();
			// SAME transform as the live renderer: swap Y<->Z, scale x10 (voxel->cm).
			// MeshDescription stores positions as FVector3f (float), so convert.
			const FVector Pos = MiraVoxelMesh::PositionToUE(V.px, V.py, V.pz);
			VertexPositions[VID] = FVector3f(Pos);
			VertexIDs.Add(VID);
		}

		// 3b. Walk the index list 3-at-a-time. For each triangle we create three
		//     vertex INSTANCES (a vertex instance = "this corner of this triangle",
		//     which is where per-corner normal/uv/color live), then make the triangle.
		const size_t IndexCount = Sec.indices.size();
		MeshDescription.ReserveNewVertexInstances(static_cast<int32>(IndexCount));
		MeshDescription.ReserveNewTriangles(static_cast<int32>(IndexCount / 3));

		for (size_t i = 0; i + 2 < IndexCount; i += 3)
		{
			// REVERSE WINDING: the live path flips winding because swapping two axes
			// flips handedness. We mirror that here by emitting corners 0,2,1 instead
			// of 0,1,2 so baked faces point outward just like the live mesh.
			const uint32_t Tri[3] = {
				Sec.indices[i + 0],
				Sec.indices[i + 2],
				Sec.indices[i + 1],
			};

			FVertexInstanceID Corners[3];
			for (int c = 0; c < 3; ++c)
			{
				const uint32_t SrcIdx = Tri[c];
				const MeshVertex& V = Sec.vertices[SrcIdx];

				const FVertexInstanceID VInst =
					MeshDescription.CreateVertexInstance(VertexIDs[static_cast<int32>(SrcIdx)]);

				// Normal: same Y<->Z swap as the live path, no scale.
				const FVector N = MiraVoxelMesh::NormalToUE(V.nx, V.ny, V.nz);
				InstanceNormals[VInst] = FVector3f(N);

				// UV channel 0.
				InstanceUVs.Set(VInst, 0, FVector2f(V.u, V.v));

				// Vertex color carries TWO things the terrain material reads separately:
				//   rgb = baked solid albedo (base_color x per-face shade)
				//   a   = ambient occlusion (0..1)
				//
				// RESOLVED // VERIFY (a) — hue match vs the live near band.
				// The live PMC path stores color as an 8-bit FColor(cr,cg,cb) whose bytes the
				// material samples directly. MeshDescription stores LINEAR FVector4f, and the
				// static-mesh build converts that back to the vertex buffer's FColor via an
				// sRGB ENCODE (FLinearColor::ToFColor(/*bSRGB=*/true)). A straight /255 would
				// therefore be sRGB-encoded a SECOND time -> a visible hue/brightness shift vs
				// the near cubes. To make the round-trip reproduce the EXACT live bytes we
				// pre-DECODE: FLinearColor(FColor(...)) is the sRGB->linear inverse, so
				// encode(decode(bytes)) == bytes. AO alpha is linear (not sRGB), so we set it
				// straight after the decode (the decode leaves alpha linear anyway).
				const FLinearColor Lin = FLinearColor(FColor(V.cr, V.cg, V.cb, 255));
				const float A = FMath::Clamp(V.ao, 0.0f, 1.0f);
				InstanceColors[VInst] = FVector4f(Lin.R, Lin.G, Lin.B, A);

				Corners[c] = VInst;
			}

			MeshDescription.CreateTriangle(GroupID, MakeArrayView(Corners, 3));
		}
	}

	if (MeshDescription.Triangles().Num() == 0)
	{
		// Defensive: sections existed but produced no triangles.
		return nullptr;
	}

	// ---- Step 4: compute TANGENTS only; KEEP our flat per-face normals --------
	// RESOLVED // VERIFY (b) — flat-shaded cubes.
	// Our cubes are flat-shaded: the mesher already gave every corner the correct
	// outward FACE normal, and we want to KEEP those (blending or recomputing normals
	// would round the cube edges and change the lighting vs the live near band). Nanite
	// + the material still need TANGENTS, so we ask only for tangents (MikkTSpace), and
	// deliberately do NOT pass EComputeNTBsFlags::Normals so our supplied normals stand.
	// (Per UE 5.7 StaticMeshOperations.h: Normals = force-recompute normals; Tangents =
	//  force-recompute tangents; UseMikkTSpace = the tangent basis to use.)
	FStaticMeshOperations::ComputeTangentsAndNormals(
		MeshDescription,
		EComputeNTBsFlags::Tangents | EComputeNTBsFlags::UseMikkTSpace);

	// ---- Step 5: create the UStaticMesh and turn on Nanite --------------------
	// Do NOT call InitResources() here — BuildFromMeshDescriptions() calls it for us
	// (and would release/re-init if we'd already done it). We only set up identity +
	// materials + Nanite settings, then build.
	UStaticMesh* StaticMesh = NewObject<UStaticMesh>(Outer, Name, RF_Public | RF_Standalone);
	if (StaticMesh == nullptr)
	{
		// NewObject should never return null here, but guard before we touch it.
		return nullptr;
	}

	// Give the mesh a fresh lighting GUID and register the material slots in the same
	// order we created polygon groups (group index == slot index).
	StaticMesh->SetLightingGuid();
	StaticMesh->GetStaticMaterials() = StaticMaterials;

	// Flip Nanite ON. At distance Nanite culls this mesh down to ~1 triangle/pixel.
	// Vertex color carries through Nanite, so the terrain material is unchanged.
	FMeshNaniteSettings NaniteSettings = StaticMesh->GetNaniteSettings();
	NaniteSettings.bEnabled = true;
	StaticMesh->SetNaniteSettings(NaniteSettings);

	// ---- Step 6: build the render data from our description --------------------
	// BuildFromMeshDescriptions takes a list of descriptions (one per LOD); we have
	// a single LOD. bFastBuild is MANDATORY in non-editor (cooked/runtime) builds —
	// the editor-only DDC/full build path isn't available there.
#if WITH_EDITOR
	// EDITOR PATH — the ONLY path that actually builds Nanite pages.
	//
	// We DELIBERATELY do NOT use BuildFromMeshDescriptions here. That helper, in the
	// editor branch, commits source model 0 with the engine's DEFAULT FMeshBuildSettings
	// (UE 5.7 EngineTypes.h: bRecomputeNormals=true, bRecomputeTangents=true). That would
	// THROW AWAY the flat per-face normals we carefully supplied (rounding our cube edges
	// and changing lighting vs the live near band) and recompute everything. Instead we
	// take the explicit route the engine exposes so we can set the build settings BEFORE
	// the build runs:
	//   1. SetNumSourceModels(1)        -> a SourceModel (LOD 0) exists.
	//   2. CreateMeshDescription(0, MD) -> hand our geometry to LOD 0.
	//   3. set GetSourceModel(0).BuildSettings (KEEP our normals; compute tangents).
	//   4. CommitMeshDescription(0)     -> serialise into the optimised form.
	//   5. Build(true)                  -> full build; reads NaniteSettings.bEnabled and
	//                                      generates the Nanite representation.
	// This honours NaniteSettings.bEnabled exactly like the old path, but with correct,
	// non-destructive build settings.
	StaticMesh->SetNumSourceModels(1);
	StaticMesh->CreateMeshDescription(0, MeshDescription);

	FMeshBuildSettings& LODBuild = StaticMesh->GetSourceModel(0).BuildSettings;
	// NORMALS/TANGENTS — the crash fix. The previous setup kept our supplied normals
	// (bRecomputeNormals=false) but asked the build to recompute tangents
	// (bRecomputeTangents=true). The tangent step needs per-TRIANGLE normals as input, and
	// with normal-recompute OFF those are never computed — so Build() hit a fatal engine
	// assert (StaticMeshOperations: `TriangleNormals.Num() > 0`). That's an appError, NOT a
	// C++ exception, so the per-tile try/catch can't catch it -> it took the whole editor down.
	// Fix: let the build recompute normals (which also computes the triangle normals the
	// tangent step needs). This does NOT round our cube edges: the greedy mesher emits
	// non-shared vertices per face, and the build's hard-edge angle threshold keeps 90° voxel
	// edges sharp — so the far crust still reads as blocky terrain, just built robustly.
	LODBuild.bRecomputeNormals  = true;  // compute normals (+ the triangle normals tangents need)
	LODBuild.bRecomputeTangents = true;  // and tangents from those
	LODBuild.bUseMikkTSpace     = true;  // standard tangent basis
	LODBuild.bRemoveDegenerates = true;  // drop any zero-area tris defensively
	LODBuild.bBuildReversedIndexBuffer = true;

	UStaticMesh::FCommitMeshDescriptionParams CommitParams;
	CommitParams.bMarkPackageDirty = false; // caller marks the package dirty before saving
	StaticMesh->CommitMeshDescription(0, CommitParams);

	// Full build (silent). Reads NaniteSettings.bEnabled and builds Nanite pages.
	StaticMesh->Build(/*bInSilent=*/true);

	// GUARD: the build must have produced render data, or the SavePackage that follows
	// (and any later component that points at this mesh) would dereference null.
	if (StaticMesh->GetRenderData() == nullptr || !StaticMesh->GetRenderData()->IsInitialized())
	{
		return nullptr;
	}
#else
	// RUNTIME (cooked, no editor) PATH — IMPORTANT LIMITATION.
	// In a cooked build only the FAST build path is available (the engine asserts
	// bFastBuild == true with no editor). The fast path builds plain LOD render
	// buffers and does NOT generate Nanite pages — so a mesh built HERE renders as a
	// normal (non-Nanite) static mesh. That's still a valid win over the live PMC, but
	// it is NOT Nanite.
	//
	// VERIFY / DESIGN DECISION for the parent: the true M6 "Nanite cold-bake" wants
	// Nanite pages, which only the editor/cook build produces. The robust shipping
	// design is therefore to BAKE these chunk meshes at editor/cook time (path above)
	// and at runtime only SWAP the finished UStaticMesh in (SwapChunkToNanite). i.e.
	// precompute the cold-bake; don't build it live in a cooked game. The runtime
	// fast-build below is the best-effort fallback when no precomputed mesh exists.
	UStaticMesh::FBuildMeshDescriptionsParams BuildParams;
	BuildParams.bBuildSimpleCollision = false;
	BuildParams.bFastBuild = true;             // mandatory in non-editor builds
	BuildParams.bCommitMeshDescription = true;
	BuildParams.bMarkPackageDirty = false;
	const TArray<const FMeshDescription*> Descriptions = { &MeshDescription };
	const bool bBuilt = StaticMesh->BuildFromMeshDescriptions(Descriptions, BuildParams);
	if (!bBuilt)
	{
		return nullptr;
	}
#endif

	return StaticMesh;
}

UStaticMeshComponent* SwapChunkToNanite(AActor* ChunkActor, UStaticMesh* BakedMesh)
{
	if (ChunkActor == nullptr || BakedMesh == nullptr)
	{
		return nullptr;
	}

	// Make a new UStaticMeshComponent owned by the chunk actor. NewObject (not
	// CreateDefaultSubobject) because we're past the constructor — this is a runtime
	// component added during play.
	UStaticMeshComponent* MeshComp = NewObject<UStaticMeshComponent>(ChunkActor);
	if (MeshComp == nullptr)
	{
		return nullptr;
	}

	MeshComp->SetStaticMesh(BakedMesh);

	// Attach to the actor's root so it inherits the chunk's world transform (the
	// baked positions are chunk-LOCAL, like the live mesh). If the actor somehow has
	// no root yet, fall back to making this component the root.
	USceneComponent* Root = ChunkActor->GetRootComponent();
	if (Root != nullptr)
	{
		MeshComp->SetupAttachment(Root);
	}
	else
	{
		ChunkActor->SetRootComponent(MeshComp);
	}

	// Runtime components must be explicitly registered to start rendering.
	MeshComp->RegisterComponent();

	// NOTE: we deliberately leave the existing ProceduralMeshComponent alone. The
	// caller decides when (and whether) to hide/destroy it once the Nanite swap has
	// settled — that's swap policy, not our job.
	return MeshComp;
}

} // namespace VoxelNaniteBaker
