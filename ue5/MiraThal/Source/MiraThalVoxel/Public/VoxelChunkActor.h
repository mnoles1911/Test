// VoxelChunkActor.h — M1: generate ONE chunk, mesh it with the Core, render it.
//
// Drop this actor into an empty Lumen level and it builds a 32^3 voxel chunk on
// construction (and on BeginPlay): fill a slab -> greedy_mesh + water + flora ->
// ProceduralMesh. This is the first proof the engine-agnostic Core renders, and
// the perf "Baseline" the later milestones measure against.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/MeshTypes.h" // mira::MeshBuffers — returned BY VALUE from the crust sampler
                            // (must precede the .generated.h, which UHT requires be last)
#include "VoxelChunkActor.generated.h"

class UProceduralMeshComponent;
class UMaterialInterface;
struct FGenParams; // VoxelGenParams.h — the shared generator-knob snapshot

// Engine-agnostic Core slab types (pure C++; real includes live in the .cpp).
namespace mira { struct DenseGrid; }

// One baked crust tile's PURE result: the greedy mesh (by value) + the placement
// bookkeeping the editor baker needs. Lives here (not in the bake module) because the
// GENERATOR sampling must happen inside MiraThalVoxel — HeightmapGenerator's
// compute_ground_y/resolve_column are defined in this module's Core .cpp and are NOT
// exported across the module boundary (calling them from the bake module is an
// unresolved-external link error). So the bake module asks THIS module to sample+mesh a
// tile, exactly like it already asks for BuildMeshBuffers.
struct FCrustTileMesh
{
	mira::MeshBuffers Mb;            // greedy mesh (solids only)
	int32 BaseFineY = 0;            // fine-voxel Y the mesh's coarse row 0 sits at (shell anchor)
	int32 MinVoxelX = 0, MinVoxelZ = 0, MaxVoxelX = 0, MaxVoxelZ = 0; // tile world-voxel bounds
	int32 Stride = 1;              // fine voxels per coarse cell (the bake downsample)
	bool  bHasContent = false;     // false -> all air (no mesh produced)
};

UCLASS()
class MIRATHALVOXEL_API AVoxelChunkActor : public AActor
{
	GENERATED_BODY()

public:
	AVoxelChunkActor();

	// The mesh this actor builds into.
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Voxel")
	UProceduralMeshComponent* Mesh = nullptr;

	// Default OFF: the Y/Z basis swap turned out NOT to need a winding flip
	// (verified visually). Tick this only if a chunk ever renders inside-out.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	bool bReverseWinding = false;

	// false = a hand-built test pattern (flat ground + pillar + water pool + flora,
	// the safest first-light shape). true = sample the real Core HeightmapGenerator
	// for ChunkCoord.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	bool bUseGenerator = false;

	// Which chunk to generate (only used when bUseGenerator). Y=3 puts the chunk's
	// 32-voxel band around the generator's ~y100-120 ground so you see a surface.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	FIntVector ChunkCoord = FIntVector(0, 3, 0);

	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	int32 Seed = 1337;

	// When true, this chunk is driven by AVoxelWorld: it does NOT auto-rebuild on
	// construction/BeginPlay; the world calls RenderManaged() directly with a slab
	// it extracted from the authoritative brickmap. (M2 multi-chunk world.)
	UPROPERTY()
	bool bWorldManaged = false;

	// Rebuild from the editor without PIE (button in the Details panel). Standalone
	// (non-world-managed) path only — builds from test pattern or the generator.
	UFUNCTION(CallInEditor, Category = "MiraThal|Voxel")
	void Rebuild();

	// World-managed render entry: greedy-mesh a pre-filled apron'd slab (the world
	// extracted it from the brickmap), upload it, and assign per-FaceClass materials.
	// Opaque/Cutout share the terrain material; Water/Flora get their own.
	//   PositionScale — multiply mesh positions by this (2^Lod for a downsampled LOD
	//                   chunk so a coarse voxel renders at its true world size; 1 at LOD 0).
	//   bSolidsOnly   — skip the water + flora meshers (LOD chunks carry no water/flora;
	//                   the downsample drops those channels — see LodDownsample contract).
	void RenderManaged(const mira::DenseGrid& Slab,
	                   UMaterialInterface* OpaqueMat,
	                   UMaterialInterface* WaterMat,
	                   UMaterialInterface* FloraMat,
	                   bool bCollision,
	                   bool bReverse,
	                   float PositionScale = 1.0f,
	                   bool bSolidsOnly = false);

	// --- Async-meshing split (RenderManaged = Build then Upload) ---
	// BuildMeshBuffers is PURE Core (greedy mesh + optional water/flora) — touches no
	// UE objects, so AVoxelWorld runs it on a WORKER THREAD off a slab copy. STATIC on
	// purpose: no actor state is read. UploadMeshBuffers takes the finished buffers and
	// pushes them into the ProceduralMesh — that part MUST run on the game thread.
	static mira::MeshBuffers BuildMeshBuffers(const mira::DenseGrid& Slab, bool bSolidsOnly);

	// PURE crust-tile sampler+mesher for the editor Nanite cold-bake. Builds a generator
	// from the shared FGenParams snapshot, samples ONE tile's surface shell
	// (mira::nanitebake::sample_crust_slab, generator-backed), and greedy-meshes it
	// (solids only). STATIC + worker-safe: reads only the snapshot (+ its immutable
	// heightmap), touches no actor/brickmap state — so the baker fans this out across
	// threads exactly like MeshSuperPure. Returns the mesh by value + placement info.
	//   TileX/TileZ — the tile to sample (tile units).
	//   TileSpan    — tile edge in voxels (e.g. 512).
	//   Stride      — fine voxels per coarse cell (TileSpan/Stride <= 32).
	//   SkirtDepth  — fine voxels below the surface the shell stays solid.
	static FCrustTileMesh SampleAndMeshCrustTile(const FGenParams& P,
	                                              int32 TileX, int32 TileZ,
	                                              int32 TileSpan, int32 Stride, int32 SkirtDepth);

	//   DebugColor (DIAGNOSTIC, default null): when non-null, this chunk's vertex RGB is
	//   replaced by the flat per-LOD debug tint (mira::lod_debug_color) while AO is kept —
	//   the LOD-color debug mode (cvar mira.LodDebug). Render override only; the voxel/brick
	//   data and the Core MeshBuffers are untouched. Null = normal material colors.
	void UploadMeshBuffers(const mira::MeshBuffers& Mb,
	                       UMaterialInterface* OpaqueMat,
	                       UMaterialInterface* WaterMat,
	                       UMaterialInterface* FloraMat,
	                       bool bCollision,
	                       bool bReverse,
	                       float PositionScale = 1.0f,
	                       const FColor* DebugColor = nullptr);

	// --- LOD debug-color recolor pass (DIAGNOSTIC; cvar mira.LodDebug) ---
	// Re-upload the LAST mesh buffers this actor received, with the debug color override
	// applied (DebugColor non-null) or removed (DebugColor null = restore real albedo).
	// This is how a LIVE cvar toggle recolors ALREADY-loaded chunks WITHOUT regenerating
	// any voxels: we cached the finished MeshBuffers + its upload params at upload time, so
	// this just re-runs the GPU upload with a different vertex color. NO-OP (safe) if this
	// actor never received a mesh (nothing cached). Touches no voxel/brick data.
	void RecolorDebug(const FColor* DebugColor);

	// True once this actor has cached mesh buffers (i.e. RecolorDebug can do something).
	bool HasMeshForRecolor() const { return bHasCachedMesh; }

	// --- LOD-transition dither cross-fade (flag-gated by AVoxelWorld) ---
	// Drive the dither mask on this chunk's TERRAIN section(s) (Opaque + Cutout, which
	// share TerrainMaterial). A is the 0..1 fade fraction the streamer computes
	// (mira::lodfade::fade_alpha): an INCOMING new-LOD actor is driven 0->1 (fades in),
	// an OUTGOING old-LOD actor is driven 1->0 (fades out). The FIRST call lazily makes a
	// UMaterialInstanceDynamic over TerrainMaterial on those sections so we can push a
	// scalar without disturbing the shared asset; subsequent calls just set the scalar.
	// The scalar param is named exactly "FadeAlpha" (the in-editor M_VoxelTerrainV2 Dither
	// node reads it). NO-OP and safe if this actor has no terrain section (e.g. a chunk
	// that meshed only water/flora) or no mesh. Water/Flora sections are never touched.
	void SetFadeAlpha(float A);

protected:
	virtual void BeginPlay() override;
	virtual void OnConstruction(const FTransform& Transform) override;

private:
	// Lazily-created dynamic material instance over TerrainMaterial, used ONLY to push
	// the per-chunk "FadeAlpha" dither scalar during a LOD cross-fade (see SetFadeAlpha).
	// Null until the first SetFadeAlpha call. Held as a UPROPERTY so the GC keeps it alive
	// while it's assigned to the mesh's terrain section(s). Re-uploading the mesh
	// (UploadMeshBuffers) re-assigns the plain TerrainMaterial, so this is rebound on the
	// next SetFadeAlpha — which is exactly what we want (a fresh mesh starts un-faded).
	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> TerrainFadeMID = nullptr;

	// --- Cached upload state for the DIAGNOSTIC LOD debug-color recolor pass ---
	// At each UploadMeshBuffers we stash the finished Core mesh + the exact params it was
	// uploaded with, so RecolorDebug can re-upload the SAME geometry with a different vertex
	// color (debug tint on/off) when the tester flips mira.LodDebug — no voxel regen needed.
	// Held by value (MeshTypes.h is included above, so MeshBuffers is a complete type here).
	// These are pure render bookkeeping; they never feed back into the voxel/brick store.
	bool bHasCachedMesh = false;          // false until the first UploadMeshBuffers
	mira::MeshBuffers CachedMesh;         // last buffers uploaded (geometry + real colors)
	TObjectPtr<UMaterialInterface> CachedOpaqueMat = nullptr;
	TObjectPtr<UMaterialInterface> CachedWaterMat  = nullptr;
	TObjectPtr<UMaterialInterface> CachedFloraMat  = nullptr;
	bool  CachedCollision   = false;
	bool  CachedReverse     = false;
	float CachedPositionScale = 1.0f;
};
