// VoxelWorld.h — M2: the multi-chunk world manager.
//
// AVoxelWorld owns the single authoritative voxel store (a sparse mira::Brickmap)
// and a grid of AVoxelChunkActor renderers. It:
//   * GENERATES a region of terrain from the Core HeightmapGenerator (10 vox/m,
//     10cm cubes) into the brickmap, then meshes every non-empty chunk.
//   * EDITS the world (CarveTestHole / CarveAtWorld): apply Core MiningCarve
//     writes to the brickmap, then re-mesh only the chunks the edit touched
//     (including apron-neighbours) — the M2 "dig under Lumen" loop.
//
// The brickmap is the single source of truth; chunk actors are pure renderers
// that read apron'd slabs out of it (Core/BrickmapMeshing). This is the data
// model the docs describe and the foundation M4 streaming / M7 GPU mirror build on.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Async/Future.h"          // TFuture — async column-generation jobs (P1)
#include "Core/Brickmap.h"        // mira::Brickmap — the authoritative store, held directly
#include "Core/ImageHeightmap.h"  // mira::ImageHeightmap — imported EXR surface (held directly)
#include "Core/FiniteWaterCore.h" // mira::FiniteWaterCore — full type (TUniquePtr in a UCLASS
                                  // needs the complete type for UHT's vtable-helper ctor)
#include "Core/WorldEditStore.h"  // mira::WorldEditStore — the player-edit journal (P2)
#include "VoxelWorld.generated.h"

class UMaterialInterface;
class AVoxelChunkActor;
class UProceduralMeshComponent;
namespace mira { class HeightmapGenerator; struct VoxelWrite; }

// The generator-knob snapshot lives in VoxelGenParams.h (promoted out of VoxelWorld.cpp
// so the bake module shares it). Forward-declared here only to friend SnapshotGenParams
// for its private read of ImportedHeightmap; the actual definitions are in that header.
struct FGenParams;
class AVoxelWorld;
FGenParams SnapshotGenParams(const AVoxelWorld& W, int32 GenLod, bool bCoarseFarGen);

// Async-mesh job payload — a whole column's finished mesh buffers, built on a worker
// thread. Defined in VoxelWorld.cpp (it holds Core mira::MeshBuffers by value, kept out
// of this header). Held via TSharedPtr so the header needs only this forward decl.
struct FMiraColumnMeshResult;

// Async super-chunk mesh job payload (clipmap far-band aggregation). Like the column
// result it holds Core mira::MeshBuffers by value, so it's defined in VoxelWorld.cpp
// and the header needs only this forward decl. (Flag-gated: bEnableSuperChunks.)
struct FMiraSuperMeshResult;

// Where the terrain SHAPE comes from. Procedural = the built-in noise/biome
// generator; HeightmapEXR = an imported Gaea (or other) .exr the artist crafted.
UENUM(BlueprintType)
enum class EVoxelHeightSource : uint8
{
	Procedural    UMETA(DisplayName = "Procedural Noise"),
	HeightmapEXR  UMETA(DisplayName = "Imported EXR Heightmap"),
	// DiffusionAI (TerrainDiffusion runtime DEM): the height comes from an
	// ImageHeightmap that a SEPARATE module (MiraThalTerrainAI) builds at runtime
	// from an AI elevation model and INSTALLS via SetDiffusionHeightmap(). From this
	// actor's point of view it is IDENTICAL to the EXR path — just a different SOURCE
	// for the same immutable mira::ImageHeightmap surface. MiraThalVoxel holds NO
	// dependency on the AI module: the AI module pushes the finished image in to us.
	DiffusionAI   UMETA(DisplayName = "AI Diffusion DEM (runtime)"),
};

// Read-only snapshot of the FAR-render load (super-chunks, coarse far-gen, 3D-shell
// trimming, LOD cross-fades) for diagnostics: surfaced in LogStreamingStats() and the
// on-screen debug HUD so the designer can SEE + tune how heavy the far ring is. This is
// pure instrumentation — filled from existing maps, changes no streaming/render state.
struct FMiraFarRenderStats
{
	int32 NearChunkActors   = 0; // ChunkActors.Num() — near per-chunk renderer actors live now
	int32 SuperActorsTotal  = 0; // SuperActors.Num() — far super-chunk renderer actors live now
	int32 SuperByLod[6]     = { 0, 0, 0, 0, 0, 0 }; // super-chunks per super-LOD band (L0=finest..L5=coarsest)
	int32 CoarseGenColumns  = 0; // columns generated at a COARSE gen-LOD (ColumnGenLod value > 0)
	int32 ShellCulledColumns= 0; // columns whose meshed Y-span is SHORTER than full (3D-shell trimmed); 0 if shell off
	int32 ActiveFades       = 0; // ActiveFades.Num() — LOD cross-fades in progress now
	int32 SuperRadiusChunks = 0; // the far-ring radius knob (chunks from focus), for context

	// --- Chunk-loading profiler (TOOL 2) — per-tick load load + hitch correlation. ---
	// These let the tester SEE why frames spike while chunks load: how much work the last
	// streaming tick uploaded, how deep the worker queues are, and a rolling worst-frame
	// window so a 150 ms spike stays visible after it passes. Pure instrumentation — every
	// field is read from existing counters; nothing here changes budgets or streaming.
	int32 GenOpsThisTick    = 0; // columns whose generation was APPLIED to the brickmap last tick
	int32 MeshOpsThisTick   = 0; // chunk/super meshes UPLOADED last tick (the visible-work count)
	int32 JobsInFlight      = 0; // worker jobs launched, not yet applied (gen + mesh + super)
	int32 Pending           = 0; // queued worker results waiting to be applied (gen + mesh + super)
	float WorstFrameMs      = 0.0f; // worst frame time (ms) over the last ~2 s (any frame)
	float WorstLoadFrameMs  = 0.0f; // worst frame time (ms) over the last ~2 s on a LOADING tick
};

UCLASS()
class MIRATHALVOXEL_API AVoxelWorld : public AActor
{
	GENERATED_BODY()

	// The shared generator-knob snapshot (VoxelGenParams.h) reads the world's private
	// heightmap + knobs to build a worker-/bake-safe FGenParams. Friending the free
	// function keeps that snapshot a pure read with no new public API surface, and lets
	// the live streaming path AND the Nanite cold-bake share ONE generator definition
	// (byte-identical generators = seam alignment). Forward-declared just below.
	friend FGenParams SnapshotGenParams(const AVoxelWorld& W, int32 GenLod, bool bCoarseFarGen);

public:
	AVoxelWorld();
	virtual ~AVoxelWorld(); // out-of-line so TUniquePtr<FiniteWaterCore> (fwd-declared) destructs

	// World generation seed (fed to the Core HeightmapGenerator).
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	int32 Seed = 1337;

	// --- Terrain source (M3): procedural noise, or an imported EXR heightmap. ---

	// Procedural noise (default) or an imported hand-crafted EXR heightmap.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap")
	EVoxelHeightSource HeightSource = EVoxelHeightSource::Procedural;

	// The .exr (or .png/.hdr) file to import when HeightSource = HeightmapEXR.
	// A 5 km Gaea export goes here. Absolute path, or relative to the project dir.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap", meta = (FilePathFilter = "exr"))
	FFilePath HeightmapFile;

	// Real-world span the EXR covers, in metres (square map). 5000 = a 5 km map.
	// At 10 voxels/m this stretches the image across 5000*10 = 50,000 voxels.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap", meta = (ClampMin = "10", ClampMax = "50000"))
	float MapSpanMeters = 5000.0f;

	// Elevation (metres) that an EXR value of 1.0 represents — the height of the
	// tallest white pixel above the base. 700 = peaks rise 700 m over the floor.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap", meta = (ClampMin = "1", ClampMax = "9000"))
	float HeightmapAltitudeMeters = 700.0f;

	// Elevation (metres) that an EXR value of 0.0 sits at — the map floor. 12 m
	// puts the darkest pixels right at sea level (sea level = 12 m at 10 vox/m).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap", meta = (ClampMin = "0", ClampMax = "1000"))
	float HeightmapBaseMeters = 12.0f;

	// Global water level in metres: every column whose ground is below this floods up to
	// it (ocean/lakes generated at fill time). 140 m = world Z 14000. At 10 vox/m this is
	// `sea_level_voxels = SeaLevelMeters × 10`, fed into the generator. NOTE: on a tall
	// mountainous map the sea is only VISIBLE where local ground dips below it — raise
	// this toward the spawn elevation if you want water near where you start.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap", meta = (ClampMin = "0", ClampMax = "2500"))
	float SeaLevelMeters = 140.0f;

	// Gaea rows usually run top→down; flip so the imported terrain faces the same
	// way it looked in Gaea. Toggle if the map comes out mirrored north/south.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Heightmap")
	bool bFlipHeightmapZ = true;

	// --- Terrain shape (legacy generator knobs). The raw generator defaults swing
	//     ±75 m (height_range 1500) which makes vertical spires; these gentle values
	//     give rolling ~8 m hills with lakes at sea level. Tune to taste in editor. ---

	// Macro layer total range in voxels (the ± swing is half this). 140 -> ±7 m.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "20", ClampMax = "2000"))
	float MacroRangeVoxels = 140.0f;

	// Mid-detail amplitude in voxels (smaller bumps on top of the macro relief).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0", ClampMax = "200"))
	int32 MidAmplitudeVoxels = 14;

	// Base ground height in voxels. Sea level is 120, so 110 puts valleys underwater.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0", ClampMax = "400"))
	int32 HeightOffsetVoxels = 110;

	// Macro noise frequency (per voxel). Higher = hills repeat over a shorter
	// distance. 0.005/voxel ≈ a hill every ~20 m at 10 vox/m.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0.0005", ClampMax = "0.05"))
	float MacroFrequency = 0.005f;

	// Horizontal extent: chunks each way from centre in X and Z. 3 -> a 7x7 grid
	// of columns (7*32 = 224 voxels = 22.4 m across). Keep modest until streaming.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World", meta = (ClampMin = "0", ClampMax = "16"))
	int32 ChunkRadiusXZ = 3;

	// Vertical extent below the surface chunk, in chunks. 2 -> ~64 voxels (6.4 m)
	// of dug-able depth meshed under the surface; deeper rock is generated on dig.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World", meta = (ClampMin = "1", ClampMax = "8"))
	int32 ChunkDepthBelow = 2;

	// Chaos collision on the chunk meshes (so the player/physics interact + we can
	// line-trace for the dig cursor). On by default for M2.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	bool bCreateCollision = true;

	// --- Streaming (M4): page chunk columns in/out around a moving focus so a
	//     huge map (e.g. the 5 km EXR) is explorable without all 50k^2 voxels
	//     resident. Off by default — the editor GenerateWorld button still builds
	//     a fixed ChunkRadiusXZ region for previewing. Streaming runs in play. ---

	// Turn on focus-following chunk streaming (play-mode). When off, the world is
	// the fixed ChunkRadiusXZ region built by GenerateWorld. DEFAULT ON — the world
	// streams around the player in play with no setup (the editor preview button still
	// builds a fixed region via GenerateWorld regardless of this flag).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bEnableStreaming = true;

	// How many chunks each way from the focus stay meshed (the visible radius).
	// 1 chunk = 3.2 m. 24 -> ~77 m each way; 48 -> ~154 m ("as far as the eye can see"
	// once LOD makes the far rings cheap). Big radius needs async meshing (below) on.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "192"))
	int32 StreamRadiusChunks = 64;

	// Extra chunks beyond the radius a column may drift before it's evicted
	// (hysteresis, so a column straddling the edge doesn't thrash load/unload).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "16"))
	int32 StreamEvictPaddingChunks = 2;

	// Max column fill/mesh ENQUEUE operations per tick — caps how many new columns we
	// START generating + START meshing (worker-thread work, cheap) and how many we sweep
	// per frame. Raised 4 -> 40: generation + mesh BUILD are async (worker pools, see the
	// JobsInFlight caps), so enqueuing more per tick just keeps more cores busy and feeds
	// the upload pipeline faster — it is NOT the game-thread cost. The actual game-thread
	// cost (the mesh UPLOAD / CreateMeshSection) is governed by MaxColumnMeshUploadsPerTick
	// below, which is the real FPS-vs-load knob. THROUGHPUT: this is why coarse LODs used to
	// trickle in over minutes — the old budget of 4 starved the enqueue + harvest pipeline.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "256"))
	int32 MaxColumnOpsPerTick = 40;

	// Max FINISHED column meshes UPLOADED to the GPU per tick (HarvestColumnMesh). This is
	// the REAL streaming-throughput bottleneck: meshes are BUILT on workers (many in flight)
	// but each must be committed on the GAME THREAD via UploadMeshBuffers/CreateMeshSection,
	// which is the per-frame FPS cost. The old code shared MaxColumnOpsPerTick (4) for this,
	// so only ~4 built meshes drained per tick while 16 sat ready — coarse LOD2-5 + supers
	// took MINUTES. Raised to 28: coarse-LOD meshes are TINY (LOD5 = 1 cube), so committing
	// many small meshes per tick is cheap and drains the backlog in SECONDS.
	// FPS-vs-LOAD TRADEOFF: a bigger value loads faster but costs more game-thread time
	// DURING the load (a brief FPS dip while the backlog drains), then returns to normal once
	// caught up. Lower it if the load-time frame dip is too harsh; raise it to load even
	// faster. The smarter MILLISECOND budget below (bTimeSliceMeshUploads) bounds the dip.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "256"))
	int32 MaxColumnMeshUploadsPerTick = 28;

	// Time-slice the per-tick mesh UPLOAD instead of relying on a fixed count. When ON, the
	// harvest keeps uploading finished meshes until EITHER MaxColumnMeshUploadsPerTick is hit
	// OR MeshUploadBudgetMs of wall-clock has elapsed this tick — so a sudden burst of ready
	// meshes can't blow a single frame's budget, while a normal backlog still drains fast.
	// DEFAULT ON (it only ever makes the count budget SAFER — it caps the frame cost; with it
	// off the behaviour is exactly the fixed-count harvest). Independent of the streaming-fix.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bTimeSliceMeshUploads = true; // DEFAULT ON — bound the per-tick upload to a ms budget

	// Wall-clock millisecond budget for the per-tick mesh upload when bTimeSliceMeshUploads is
	// on. 5 ms/tick keeps the load-time FPS dip modest (a 60 fps frame is ~16 ms) while still
	// draining the backlog quickly. Bigger = faster load + deeper dip; smaller = gentler dip +
	// slower load. The count cap (MaxColumnMeshUploadsPerTick) is still the hard ceiling.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0.5", ClampMax = "16.0"))
	float MeshUploadBudgetMs = 5.0f;

	// Time-slice the GEN harvest too. The apply side of HarvestColumnGen writes a column's
	// generated voxels AND replays the player's saved edits from DISK (ApplyEditsToColumn) —
	// synchronous game-thread work that, unlike the mesh upload above, had NO ms budget. A
	// burst of ready columns could therefore blow a frame on disk replay alone, independent of
	// the upload cap. When ON, HarvestColumnGen stops once GenHarvestBudgetMs of wall-clock has
	// elapsed this tick (always applying >=1 so streaming never stalls). DEFAULT ON — it only
	// ever caps the loading dip; with it off the behaviour is the original fixed-count harvest.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bTimeSliceGenHarvest = true; // DEFAULT ON — bound the per-tick gen-apply cost

	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0.5", ClampMax = "16.0"))
	float GenHarvestBudgetMs = 4.0f;

	// --- LOD0 HERO-COLUMN priority (Step 1: the "ground under your feet is always sharp" fix) ---
	// The column(s) directly under and immediately around the player must reach full detail
	// (LOD0) RIGHT NOW and never wait behind the general async mesh queue. When the far-band
	// pipeline is busy, a coarse tile you just walked onto would otherwise sit at LOD1/2/3 for a
	// long time (mesh-apply starved). This pass force-meshes the nearest HeroRadiusChunks rings
	// at LOD0 every frame with a SMALL reserved budget, SYNCHRONOUSLY (bypassing the async queue
	// entirely) so the tile under you is guaranteed sharp. Kept tiny so the frame cost is bounded.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming")
	bool bHeroColumnPriority = true; // ON: never let the column under the player lag at coarse LOD
	// Chebyshev ring radius of the hero band (2 = a 5×5 area around you). With view-bias on, the
	// budget below is spent forward-first within this band, so "under you + a step ahead" stays
	// sharp while moving. Cheap because surface-volume makes each column a thin shell.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming", meta = (ClampMin = "0", ClampMax = "4"))
	int32 HeroRadiusChunks = 2;
	// Max hero columns force-meshed (sync, LOD0) per frame — the cap on guaranteed-sharp work.
	// Spent nearest-then-forward, so it covers what's under you and just ahead of you first.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "49"))
	int32 HeroColumnBudget = 12;

	// HERO ALTITUDE GATE (fixes the high-altitude stall). The hero pass SYNCHRONOUSLY generates +
	// LOD0-meshes the column(s) under the player on the game thread — great at ground level (keeps
	// the dirt under your feet sharp), but when the player is far ABOVE the surface (flying / the
	// debug spectator / falling) that 10 cm detail is sub-pixel AND the sync gen+mesh spikes the
	// frame (the uninstrumented ~390 ms we diagnosed). Skip the hero pass when the focus is more
	// than this many METRES above the ground beneath it. 0 = never gate (always run hero).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming", meta = (ClampMin = "0"))
	float HeroMaxAltitudeMeters = 40.0f;

	// --- SUPER-CHUNK sweep CADENCE cap (Step 1: stop the idle-frame far-band cost) ---
	// The super-chunk ENQUEUE ring sweep scans the whole far field (thousands of cells, each an
	// N×N neighbour check) and most cells skip without spending budget — so it used to run IN FULL
	// every frame, a constant game-thread cost that pinned FPS even when the world was idle. Supers
	// are far + coarse and change slowly, so we only re-run the sweep this often (the cheap super
	// UPLOAD harvest still runs every frame). 0.25s = 4×/sec, invisible for the far band.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|SuperChunks", meta = (ClampMin = "0.0", ClampMax = "2.0"))
	float SuperSweepIntervalSeconds = 0.25f;

	// What the streaming ring centres on. If empty, the first player pawn is used.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	TObjectPtr<AActor> StreamFocusActor;

	// --- VIEW-PRIORITIZED streaming. When ON, the per-tick FILL + MESH candidate
	//     processing is REORDERED so chunks in the player's VIEW (forward) direction
	//     are loaded/meshed a touch SOONER than chunks behind them — look-ahead
	//     terrain appears before behind-you terrain, a perceived-loading win in the
	//     now-1.23 km-deep world. It only ever REORDERS within the existing radius:
	//     every in-radius chunk still loads (no holes behind the player), nearest
	//     chunks still beat far ones (the ring is still walked nearest-first), the
	//     bias just sorts WITHIN each ring's band. The ordering math is harness-
	//     locked (Core/ViewPriority.h). DEFAULT OFF — with the flag off the fill +
	//     mesh selection is byte-for-byte today's order. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bViewPrioritizedStreaming = true; // ON: load/mesh what you're looking at first (forward-biased)

	// Strength of the forward bias, in CHUNKS: the most a perfectly-forward chunk's
	// effective distance is discounted (and a perfectly-behind chunk penalised). Keep
	// it MODEST — it only reorders chunks within a ~2*ViewBiasChunks-wide band, never
	// excludes far/behind chunks. 4 chunks (~12.8 m) gives a noticeable look-ahead
	// head-start without ever starving the terrain behind you.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0", ClampMax = "32"))
	float ViewBiasChunks = 4.0f;

	// --- P1: async streaming. When ON, column GENERATION (the per-voxel EXR/noise
	//     sampling + banding — the heavy CPU) runs on worker threads; the game thread
	//     only applies finished columns and meshes them, budgeted per frame, so a
	//     fast-moving player never hitches on a wall of new terrain. The synchronous
	//     path (below, OFF) stays the default + fallback. Generation reads only the
	//     immutable EXR + scalar knobs, so it is safe to run in parallel; ClearWorld
	//     waits for all in-flight jobs before teardown so none outlives the world. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bAsyncStreaming = true; // DEFAULT ON — generation runs on worker threads

	// How many async column-generation jobs may be in flight at once (caps worker
	// pressure + memory). Each finished job is applied on the game thread.
	// THROUGHPUT: raised 8 -> 48 so MANY cores generate concurrently and keep the mesh +
	// upload pipeline fed (the old cap of 8 throttled gen to a trickle on an 8+ core box).
	// Generation is pure worker-thread work (reads the immutable EXR + scalars), so a deep
	// in-flight queue just saturates the cores — it costs the game thread nothing. The
	// ClampMax was widened to 192 to allow a generous cap on high-core machines.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "192"))
	int32 MaxColumnJobsInFlight = 48;

	// Predictive prefetch: shift the streaming centre this many chunks along the
	// focus's velocity so terrain is generated slightly AHEAD of a moving player
	// (mounts/vehicles/flight outrun a reactive streamer). 0 = reactive only.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0", ClampMax = "16"))
	int32 PrefetchLeadChunks = 2;

	// --- P3: voxel LOD. When ON, columns past the near band mesh at a COARSER voxel
	//     size (LOD 1/2/3 = 20/40/80 cm) so mid-distance terrain costs a fraction of
	//     the triangles and the view distance can grow. Near columns stay full 10 cm.
	//     EXPERIMENTAL — leave OFF for the known-good preview; the designer flips it
	//     on to tune the tier distances. (Selection math is harness-locked: LodTier.) ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD")
	bool bEnableLOD = true; // DEFAULT ON — mid/far columns mesh at coarser voxel sizes

	// Chunk distance (from focus) at which each LOD tier begins. Columns within
	// Lod0MaxChunks render full 10 cm; out to Lod1MaxChunks render at 20 cm; etc.
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "1", ClampMax = "256"))
	int32 Lod0MaxChunks = 8;
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "2", ClampMax = "256"))
	int32 Lod1MaxChunks = 16;
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "3", ClampMax = "512"))
	int32 Lod2MaxChunks = 32;
	// LOD 3 = 80 cm voxels, LOD 4 = 160 cm, beyond Lod4MaxChunks = LOD 5 (320 cm). The
	// coarse far tiers are what let the render radius reach hundreds of metres cheaply.
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "4", ClampMax = "512"))
	int32 Lod3MaxChunks = 64;
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "5", ClampMax = "512"))
	int32 Lod4MaxChunks = 120;

	// --- LOD-transition cross-fade (dither). When ON, a column that swaps LOD level
	//     doesn't HARD-swap its mesh (which "pops" on screen — the two LODs are
	//     independent greedy meshes with no shared vertices, so no geomorph is possible).
	//     Instead we briefly keep BOTH the old-LOD mesh and the new-LOD mesh, and DITHER
	//     cross-fade between them over LodFadeSeconds: the new mesh fades IN (a 0->1) while
	//     the old fades OUT (1-a). Both meshes stay OPAQUE (masked, not blended) so Lumen +
	//     VSM + Nanite are unaffected. The fade fraction is the harness-locked smoothstep
	//     in Core/LodFade.h; the material's Dither node reads a per-chunk "FadeAlpha" scalar
	//     (wired in-editor on M_VoxelTerrainV2 — NOT part of this code). DEFAULT OFF: with
	//     the flag off the LOD-change path is the original single-actor hard swap, byte-for-
	//     byte, with zero extra allocation or iteration. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD")
	bool bEnableLodFade = false; // DEFAULT OFF — LOD swaps hard-swap exactly as today

	// How long a LOD cross-fade lasts, in seconds. ~0.35 s reads as a soft dissolve
	// without the two meshes lingering long enough to double the chunk's draw cost.
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD", meta = (ClampMin = "0.05", ClampMax = "2.0"))
	float LodFadeSeconds = 0.35f;

	// --- MESH-THEN-SWAP: keep the OLD LOD mesh until the NEW one is actually ready.
	//     (Bug-2 correctness fix.) When a column swaps LOD tier, the naive path destroys
	//     the old mesh THE INSTANT the swap is decided, but the replacement mesh is async +
	//     budgeted (MaxColumnOpsPerTick/tick) and lands MANY ticks later — leaving a visible
	//     HOLE in front of the player for that window. With this ON, the old (coarser) mesh
	//     is HELD on screen as a backstop (no dither, no alpha — it is the SAME mesh, just
	//     not destroyed yet) and is torn down only once the finer mesh is genuinely uploaded
	//     (Core/LodFade.h should_destroy_outgoing). This reuses the LOD-fade dual-actor
	//     machinery WITHOUT the fade. DEFAULT ON (it's a correctness fix), but flag-gated so
	//     it can be reverted to the old instant-destroy behaviour. Independent of
	//     bEnableLodFade — the swap-hold works whether or not the dither cross-fade is on. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD")
	bool bKeepOldLodUntilReady = true; // DEFAULT ON — old mesh held until the new one uploads

	// Max teardown ops (column + super eviction) per tick. Teardown was previously instant +
	// unbudgeted, so a single frame could tear down FAR more geometry than the (budgeted, 4/
	// tick) mesher can rebuild — the root cause of the visible holes. Capping eviction at this
	// many ops/tick is defense-in-depth: a frame can never out-tear-down the mesher. 8 is a
	// little more than the mesh budget so eviction keeps pace without ever racing ahead.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "256"))
	int32 MaxEvictOpsPerTick = 8;

	// CATCH-UP for fast roaming. The base MaxEvictOpsPerTick keeps pace with WALKING, but when the
	// player sprints / flies / teleports, columns fall out of range far faster than 8/tick can drop
	// them, so the out-of-range backlog grows unbounded — old terrain lingers as a "distant square
	// that never unloads", memory climbs, and the per-tick evict SCAN gets O(huge).
	//
	// *** FAST-FLIGHT FIX (root cause) ***
	// The OLD code capped the catch-up budget at EvictCatchupMultiplier x MaxEvictOpsPerTick = 8x8
	// = 64 columns/tick, an ABSOLUTE ceiling that did NOT scale with the actual backlog. But during
	// sustained flight the keep-square's trailing edge sheds ~133 columns for every chunk the focus
	// advances — well above 64/tick — so the backlog GREW every frame and never converged WHILE
	// MOVING. That is exactly the reported "square of terrain around the old spawn that never goes
	// away": unloading simply could not keep pace with loading.
	//
	// THE FIX: this multiplier is no longer a hard ceiling on ops — it is the minimum head-room the
	// catch-up grants over the base budget. When the backlog is large the teardown budget is allowed
	// to DRAIN THE WHOLE BACKLOG in one tick (bounded only by ToEvict.Num()), so eviction CONVERGES
	// no matter how fast you fly. The per-frame COST is instead bounded by EvictBudgetMs (a wall-clock
	// time-slice, below) so a huge drain can never spike a single frame. Safe: these columns are all
	// already beyond the keep radius (behind/away, not pending a re-mesh) and are torn down
	// FARTHEST-FIRST, so faster teardown can't open a transition hole near the player. 1 = off.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "64"))
	int32 EvictCatchupMultiplier = 8;

	// Wall-clock millisecond budget for the per-tick column EVICTION teardown. This is what makes the
	// "drain the whole backlog" catch-up above SAFE: instead of a fixed op-count ceiling that could
	// either stall (too low -> terrain lingers) or spike a frame (too high -> hitch), the teardown
	// keeps dropping farthest-first columns until EITHER the backlog is empty OR this much wall-clock
	// has elapsed this tick (always dropping >=1 so eviction never fully stalls). 3 ms/tick keeps the
	// catch-up frame cost modest (a 60 fps frame is ~16 ms) while still clearing a fast-flight backlog
	// in a handful of frames. Bigger = clears lingering terrain faster but a deeper dip; smaller =
	// gentler dip but the trailing square fades a touch slower. Mirrors MeshUploadBudgetMs.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0.5", ClampMax = "16.0"))
	float EvictBudgetMs = 3.0f;

	// Hard cap on how many columns the per-tick eviction will ORDER (sort) farthest-first.
	//
	// *** FAST-FLIGHT SORT FIX (perf) ***
	// The eviction teardown is bounded (by EvictBudgetMs, above) but the SORT that picks which
	// columns to tear down first was NOT. Each tick we collect every out-of-range column into a
	// backlog (ToEvict) and used to sort the WHOLE backlog farthest-first — an O(M log M) cost
	// that runs in full EVERY tick even though the time-slice only tears down a handful. During
	// fast flight at a large radius the backlog can be thousands of columns, so re-sorting it all
	// each frame is itself the hitch the eviction time-slice was meant to remove.
	//
	// THE FIX: we only need the FARTHEST columns we'll actually tear down this tick to be in order.
	// When the backlog exceeds this cap we PARTIAL-select (std::nth_element) the farthest `cap`
	// columns — O(M) — then sort just those `cap` — O(cap log cap). The rest stay in the backlog
	// and are re-collected (and re-selected) next tick, so nothing leaks and farthest-first is still
	// guaranteed for every column we evict. When the backlog is <= this cap we keep the simple full
	// sort. Set generously: a tick will never tear down more than EvictBudgetMs allows anyway, so
	// this just needs to comfortably exceed the most columns one tick could possibly drop.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "16", ClampMax = "8192"))
	int32 MaxEvictTeardownsPerTick = 512;

	// --- Coarse far-generation. When ON, DISTANT columns are GENERATED directly at
	//     their render resolution (stride 2^L sampling) instead of full-res-then-
	//     downsample, slashing worker-thread generation cost (the loading bottleneck).
	//     The coarse fill lands on EXACTLY the voxels a downsample would produce
	//     (harness-locked: Core/CoarseColumnGen.h vs Core/LodDownsample.h). As the
	//     player nears, a too-coarse column is re-gen'd finer. EXPERIMENTAL — DEFAULT
	//     OFF; with the flag off the gen LOD is always 0, so the fill is byte-for-byte
	//     unchanged. Requires bEnableLOD (uses the same LodN tier thresholds). ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|LOD")
	bool bCoarseFarGen = false; // DEFAULT OFF — far columns generate full-res then downsample

	// --- 3D / spherical surface-shell streaming. When ON, DISTANT columns stream only
	//     a THIN SHELL of chunks hugging the surface (no underground meshed far away —
	//     mining is too slow for it to matter), while NEAR columns still stream FULL
	//     DEPTH so the player can mine straight down. The horizontal+vertical cull also
	//     becomes a TRUE ROUND (spherical) test instead of a square, so the loaded set is
	//     a sphere/shell around the player. EXPERIMENTAL — DEFAULT OFF; with the flag off
	//     the streamed extent + cull are byte-for-byte unchanged. The shell math is
	//     harness-locked (Core/StreamShell.h). Runs ALONGSIDE coarse far-gen + super-
	//     chunks (orthogonal: coarse-gen sets gen RESOLUTION by distance, super-chunks
	//     own the far band, this sets the NEAR/MID per-chunk band's VERTICAL extent). ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool b3DShellStreaming = false; // DEFAULT OFF — far columns stream full depth as today

	// Within this chunk-distance of the player a column streams FULL DEPTH (mine straight
	// down). Beyond it, only the thin surface shell. 10 -> ~32 m of full-depth core.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "1", ClampMax = "192"))
	int32 NearFullDepthRadiusChunks = 10;

	// Far columns: how many chunk rows ABOVE the surface row the shell keeps (overhang /
	// air headroom). 1 is plenty for blocky terrain.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0", ClampMax = "8"))
	int32 ShellUpChunks = 1;

	// Far columns: how many chunk rows BELOW the surface row the shell keeps (so cliff
	// faces aren't see-through). 2 keeps just enough below-surface; bigger = more depth.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming", meta = (ClampMin = "0", ClampMax = "8"))
	int32 ShellDownChunks = 2;

	// --- SURFACE-VOLUME mode (Step 1b: "only build a volume around the surface"). When ON,
	//     EVERY column meshes only the thin surface shell (ShellUp/ShellDown around its surface
	//     row) — there is NO full-depth near core at all (NearFullDepthRadiusChunks is ignored).
	//     This is the big meshing cut: the player walks on a surface slab, not a solid volume.
	//     Voxel DATA is still generated full-depth (cheap, no actors), so a dig anywhere hits
	//     real voxels with no promotion delay; DIG-SPAN GROWTH (below) then keeps the meshed
	//     span following any dig downward so the hole always renders, even a deep shaft. Implies
	//     the shell path regardless of b3DShellStreaming, so this one flag enables the mode. ---
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Streaming")
	bool bSurfaceVolumeOnly = true; // ON: thin surface slab everywhere + dig-grown depth

	// --- Super-chunk aggregation (far-band clipmap LOD). When ON, the FAR ring
	//     (beyond StreamRadius, out to SuperRadiusChunks) is rendered as coarse
	//     "super-chunks": one mesh covers an N×N×N block of chunks, replacing up to
	//     N^3 per-chunk actors with a single draw call so terrain reaches ~1.5 km
	//     cheaply. Built from the heightmap sampler (no brick fill) on worker threads,
	//     mirroring the async column-mesh path. EXPERIMENTAL — DEFAULT OFF; the default
	//     build is byte-for-byte unchanged. The super-chunk math is harness-locked
	//     (Core/SuperChunk.h). The designer flips this on to tune the tier distances. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks")
	bool bEnableSuperChunks = false; // DEFAULT OFF — far band stays per-chunk

	// Super-chunk edge in CHUNKS (N). 8 (DEFAULT) -> a 256-voxel (25.6 m) cube per super-chunk.
	//
	// VALID VALUES: powers of two that keep the coarse grid within CHUNK (32) so the existing
	// 34^3 mesh-slab path renders every super-LOD unchanged — i.e. coarse_side(N,L5) >= 1 and
	// coarse_side(N,L0) <= 32. That holds for **8 and 16** (both harness-locked in
	// test_superchunk.cpp). 16 makes each super-chunk a 512-voxel (51.2 m) cube covering a
	// 16x16 chunk block instead of 8x8, so the far ring spawns ~4x FEWER super actors — a big
	// draw-call / actor-count cut that offsets the ~1.23 km extended super render.
	//
	// TRADEOFF (designer's call): N=16 makes the NEAR super-chunks coarser too (the finest super
	// band L0 is now a 16-voxel stride = 1.6 m cells instead of 0.8 m), so the just-past-stream
	// horizon reads blockier up close. It's a GLOBAL detail-vs-actor-count knob: 16 = far cheaper
	// far ring, slightly chunkier mid-far silhouette. The whole super-chunk system stays gated by
	// bEnableSuperChunks; changing N only matters when that flag is on.
	//
	// The DEFAULT stays 8 — shipped far-band behavior is byte-for-byte unchanged. The Core math
	// (Core/SuperChunk.h) takes N as a parameter and the whole super path reads this single
	// property (no hardcoded 8), so flipping this to 16 is safe with no other change.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "2", ClampMax = "16"))
	int32 SuperChunkSizeChunks = 8;

	// How far (in CHUNKS from the focus) super-chunks are rendered. Must be >= the
	// per-chunk StreamRadius (super-chunks fill the band BEYOND it) and can reach far.
	// 384 chunks ≈ 384 * 32 voxels * 10 cm = 122,880 UU ≈ 1.23 km horizon — the
	// "as far as the eye can see" far band fed by the coarse L3-L5 super-LODs below.
	//
	// *** LWC PRECISION CEILING — do NOT push past ~512 chunks (~1.6 km). ***
	// Super-chunk renderer actors are placed at ABSOLUTE world positions (see
	// SuperChunkActorLocation). UE single-precision float mesh/transform math degrades a
	// few km from the world origin (Large World Coordinates only widens the AUTHORITATIVE
	// double transform — the per-vertex float mesh data is still 32-bit), so a super-chunk
	// placed past a couple of km from origin starts to JITTER/shimmer. 384 keeps the whole
	// far ring well inside that safe envelope; 512 is the hard ceiling. To see truly
	// further than ~1.6 km, the Nanite cold-bake crust (origin-rebased tiles) is the path,
	// not a bigger super radius.
	//
	// FAR HORIZONS: this is already a live knob here; it can ALSO be pushed from the console
	// via `MiraThal.SuperRadiusChunks <n>` (see CVarMiraSuperRadiusChunks in VoxelWorld.cpp,
	// clamped to this same [64,512] range). IMPORTANT: for the extended band to show REAL AI
	// terrain (not the sea-level fallback / all-air), the AI streaming source must keep the far
	// coarse DEM tiles resident — that only happens on the wide ASYNC ring (kSuperTileRequestRing
	// in TdiffStreaming.cpp), i.e. with `MiraThal.Tdiff.AsyncTiles 1`. Pushing this radius on the
	// SYNC path just extends the far band into empty air.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "64", ClampMax = "512"))
	int32 SuperRadiusChunks = 384;

	// Chunk distance (from focus) at which each super-LOD BAND ENDS (its outer edge). N=8
	// coarse strides: L0/1/2 = 8/16/32, L3/4/5 = 64/128/256 (coarse side 32/16/8/4/2/1).
	// Bands tile from the near super edge (just past StreamRadius) out to SuperRadius:
	//   <=Super0Max -> L0 (finest super), <=Super1Max -> L1, ... beyond Super4Max -> L5.
	// The L0-L2 thresholds (96/144/192) are the original, verified near-super behavior and
	// are PRESERVED byte-for-byte; L3/L4/L5 ADD the farther horizon bands. Keep them
	// non-decreasing (Super0 <= Super1 <= ... <= Super5) and Super5 ~= SuperRadiusChunks.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super0MaxChunks = 96;
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super1MaxChunks = 144;
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super2MaxChunks = 192;
	// --- FAR horizon bands (the additive extension). Coarse side 4/2/1 for N=8. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super3MaxChunks = 240;
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super4MaxChunks = 312;
	// Beyond Super4Max (out to SuperRadiusChunks) renders at super-LOD 5 (side=1: a whole
	// 25.6 m super-chunk is ONE cube — the cheapest possible far-horizon tile).
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "8", ClampMax = "512"))
	int32 Super5MaxChunks = 384;

	// Max super-chunk mesh-ops (harvest + enqueue) per tick — caps per-frame cost. Bumped
	// from 1 to 2 so the LARGER far ring (radius 384 + 6 LOD bands) fills in a reasonable
	// time WITHOUT starving near streaming: this budget is SEPARATE from the near per-chunk
	// MeshBudget/gen budget (different code paths, different async pools), and the near work
	// runs FIRST each tick, so super work never cannibalizes near streaming. The actual
	// mesh build is async (MaxSuperMeshJobsInFlight), so this only bounds enqueue+harvest.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxSuperOpsPerTick = 10; // THROUGHPUT: 2 -> 10 (supers are few + cheap; was minutes-slow)

	// How many async super-chunk mesh jobs may be in flight at once.
	// THROUGHPUT: 4 -> 16 so the far super-LOD bands build concurrently instead of trickling.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxSuperMeshJobsInFlight = 16;

	// Max FINISHED super-chunk meshes UPLOADED to the GPU per tick (HarvestSuperMesh) — the
	// game-thread commit budget for supers, the analogue of MaxColumnMeshUploadsPerTick. The
	// old code shared MaxSuperOpsPerTick (2) for this, so the tester saw super-L5 take minutes.
	// Supers are FEW and each is one coarse mesh, so uploading 12/tick drains them in seconds.
	// FPS-vs-LOAD: same tradeoff as the column upload budget — bigger = faster but a deeper dip.
	UPROPERTY(EditAnywhere, Category = "MiraThal|SuperChunks", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxSuperMeshUploadsPerTick = 12;

	// --- Nanite cold-bake "crust" (M6). EXPERIMENTAL — DEFAULT OFF. When ON, the FAR
	//     band (beyond the near voxels, out to NaniteOuterChunks) is drawn from a
	//     PRE-BAKED set of Nanite static-mesh tiles (one .uasset per 512-voxel tile)
	//     instead of live super-chunks. The bake itself is an editor button on the
	//     separate MiraThalVoxelBake utility (NOT on this actor — avoids a circular
	//     module dependency); this runtime side just streams the finished tiles in/out.
	//     When this is ON the super-chunk driver is GATED OFF (the crust supersedes that
	//     band); the super-chunk code stays intact as a fallback. With this OFF and no
	//     manifest, the crust component does nothing — the build is behaviour-unchanged. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|NaniteCrust")
	bool bEnableNaniteCrust = false; // DEFAULT OFF — far band stays per-chunk / super-chunk

	// Inner edge of the crust band, in CHUNKS from the focus. The crust starts where the
	// near live voxels end, so this defaults to the near StreamRadius. (Tiles nearer than
	// this are covered by real voxels; the crust fills the band beyond.)
	UPROPERTY(EditAnywhere, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "8", ClampMax = "1024"))
	int32 NaniteInnerChunks = 64;

	// Outer edge of the crust band, in CHUNKS from the focus — how far the baked crust
	// reaches. Beyond it, nothing is drawn (or the far vista mesh takes over).
	UPROPERTY(EditAnywhere, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "64", ClampMax = "4096"))
	int32 NaniteOuterChunks = 512;

	// --- Async MESHING. When ON, the heavy greedy-mesh (and LOD downsample) for STREAMED
	//     columns runs on worker threads; the game thread only extracts the slab (a cheap
	//     copy) and uploads finished buffers, budgeted per frame. This is what makes a big
	//     StreamRadius playable — meshing no longer hitches the frame. Edits (carve/water)
	//     still mesh synchronously for instant feedback. Generation async is separate
	//     (bAsyncStreaming). ClearWorld drains in-flight mesh jobs (they hold slab copies,
	//     so they never touch the freed world). ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Streaming")
	bool bAsyncMeshing = true; // DEFAULT ON — streamed columns mesh on worker threads

	// --- Persistence (P2): the player's edits survive reload. Carves/places are
	//     journalled into region files under Saved/Worlds/<WorldSaveName>/ and
	//     replayed on top of the generated terrain when a column loads. Only edits
	//     are stored — unedited terrain is always regenerated from the EXR. ---

	UPROPERTY(EditAnywhere, Category = "MiraThal|Persistence")
	bool bPersistEdits = true;

	// Save slot name (the folder under Saved/Worlds/). Different names = different saves.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Persistence")
	FString WorldSaveName = TEXT("DefaultWorld");

	// Flush every dirty region's edits to disk now. CallInEditor button + EndPlay.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|Persistence")
	void SaveEdits();

	// --- Dynamic water (M3b): a finite, volume-conserving pour-and-settle sim
	//     (Core `FiniteWaterCore`). Player-poured water flows downhill, pools, and
	//     merges into the generated ocean (which acts as an infinite source). Off
	//     by default; the PourTestWater button works in-editor without it. ---

	// Run the water sim every tick in play (water keeps settling/flowing live).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water")
	bool bEnableWaterSim = false;

	// How many sim ticks per second (the sim is deterministic per tick). 4 Hz
	// matches the Godot cadence; higher = faster settling, more cost.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "1", ClampMax = "30"))
	float WaterSimHz = 4.0f;

	// Active cells processed per sim step (0 = no cap). Caps per-step cost.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "0", ClampMax = "100000"))
	int32 WaterStepBudget = 4096;

	// --- Streaming coupling (only meaningful when bEnableWaterSim is ON) ---
	// The water sim is bounded to a NEAR BAND around the streaming focus: a sim
	// change whose chunk-XZ is farther than this many chunks from the focus is
	// NOT applied/re-meshed, and those cells are forgotten from the live ledger so
	// the active set can't grow past the band. 10 chunks = ~32 m. Keep it <= the
	// near full-depth radius so water only simulates where the player can reach it.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "1", ClampMax = "192"))
	int32 WaterSimRadiusChunks = 10;

	// Formalises the Tick fixed-timestep CATCH-UP cap: at most this many sim steps
	// run in a single frame (so a long hitch / huge DeltaSeconds can't spiral into
	// a wall of catch-up steps). Matches the previously-hardcoded cap of 4.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "1", ClampMax = "30"))
	int32 WaterMaxStepsPerTick = 4;

	// How many units (1 unit = 1/8 of a full voxel) the test-pour drops.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "1", ClampMax = "100000"))
	int32 TestPourUnits = 2000;

	// --- Open-ocean sea plane (M-water). When ON, ONE large flat quad is spawned at
	//     world sea level and kept centred on the streaming focus, so beyond the near
	//     water band (which is solids-only far away) there is still a water SURFACE to
	//     the horizon. It uses WaterMaterial, has NO collision, and is parented under
	//     this actor. DEFAULT OFF — with the flag off no plane is spawned and the build
	//     is behaviour-unchanged. The plane's Z reads SeaLevelMeters LIVE (tracks the
	//     editor knob): world Z = SeaLevelMeters * 10 (1 vox = 10 cm) * 10 cm... i.e.
	//     sea_level_voxels * 10 UE units. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water")
	bool bEnableSeaPlane = false; // DEFAULT OFF — no open-ocean plane spawned

	// Half-extent of the sea plane in METRES from its centre (so the plane spans
	// 2× this each way). 0 = derive from the stream radius (StreamRadiusChunks chunks
	// × 3.2 m, with margin) so it always covers what the player can see. Override to
	// pin a fixed size (e.g. a few km) if you want the ocean to reach the far vista.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Water", meta = (ClampMin = "0", ClampMax = "50000"))
	float SeaPlaneHalfExtentMeters = 0.0f;

	// --- Gravity-on-dig (M3c): when you carve out the support under LOOSE material
	//     (sand/gravel), it slides down to rest. Solid terrain (stone/grass) does
	//     NOT collapse (no rigid-body sim yet) — only loose materials fall. Opt-in. ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|Gravity")
	bool bEnableGravity = true; // DEFAULT ON — loose material (sand/gravel) slides on dig

	// Solid-colour terrain material (vertex-colour albedo + AO in alpha). Opaque
	// and cutout faces use this; water and flora get their own.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> TerrainMaterial;

	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> WaterMaterial;

	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> FloraMaterial;

	// Decode HeightmapFile into ImportedHeightmap and apply the georef/vertical knobs.
	// Returns false (and logs) on any load failure. No-op + true when HeightSource is
	// Procedural. Idempotent — safe to call repeatedly. PUBLIC so the editor-time Nanite
	// crust baker can ensure the EXR is loaded before snapshotting the generator (the
	// runtime path calls it itself in BeginPlay).
	bool LoadHeightmapIfNeeded();

	// --- AI diffusion DEM install seam (Phase 1) -------------------------------
	// Hand this world a runtime-built elevation surface to use as its height source.
	// The MiraThalTerrainAI module (which DEPENDS on this module — never the reverse)
	// produces a mira::ImageHeightmap from the AI DEM and calls this to install it.
	// We COPY the image in (the actor then owns the resident surface, mirroring how
	// ImportedHeightmap holds the EXR), record the seed it was generated from (for the
	// generator fingerprint), and switch HeightSource to DiffusionAI so the existing
	// EXR plumbing (ConfigureGenerator / SnapshotGenParams / BuildGen) renders it. The
	// supplied image must be valid(); on an invalid image this is a no-op that returns
	// false and leaves the current source untouched. NOT a UFUNCTION on purpose — it
	// takes a Core type (mira::ImageHeightmap) that Blueprint cannot see; the AI module
	// triggers it from C++ (e.g. the MiraThal.Tdiff.FillRegion console command).
	bool SetDiffusionHeightmap(const mira::ImageHeightmap& Hm, int64 GeneratedFromSeed);

	// --- Phase 2: streaming AI height source (infinite world) ---------------------
	// MiraThalTerrainAI installs a STREAMING IHeightSource (a resident region-tile cache
	// that fills in as the player explores) plus two game-thread callbacks, so THIS module
	// never references the AI module (the one-way dep root is preserved):
	//   * EnsureFn(focusChunk): called once per TickStreaming with the focus column. The AI
	//     module makes the tiles around the player resident (synchronous + budgeted on the
	//     game thread — inference never runs on a column worker).
	//   * ColumnReadyFn(column): true iff the column's covering tile (+ ring) is resident, so
	//     it is safe to gen now; not-ready columns are DEFERRED and retried a later tick.
	// When a valid streaming source is installed it takes precedence over DiffusionHeightmap.
	// Pointer is NON-OWNING (the AI module owns it + keeps it alive across generation).
	void SetStreamingHeightSource(const mira::IHeightSource* Src,
	                              TFunction<void(FIntPoint)> EnsureFn,
	                              TFunction<bool(FIntPoint)> ColumnReadyFn);
	void ClearStreamingHeightSource();

	// Build (or rebuild) the whole region from the generator. CallInEditor button.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void GenerateWorld();

	// Destroy all chunk actors and clear the brickmap.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void ClearWorld();

	// Log streaming/LOD stats to the output log (filled + meshed column counts, the
	// per-LOD column histogram, and async jobs in flight). Lets us OBJECTIVELY confirm
	// P3 LOD is engaging (columns at distance pick LOD 1/2/3) without reading a screenshot.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|Streaming")
	void LogStreamingStats();

	// Read-only snapshot of the far-render load (super-chunks per LOD, coarse far-gen
	// column count, 3D-shell-trimmed column count, active LOD cross-fades). Filled from
	// the existing streaming maps; called by LogStreamingStats() and the debug HUD so the
	// designer can see + tune the far ring. Changes no state — pure instrumentation.
	FMiraFarRenderStats GetFarRenderStats() const;

	// HANDOFF READINESS (Nanite crust): is the LIVE voxel terrain ready to take over the area a
	// crust tile covers? Returns true only if every live column in the chunk rectangle
	// [MinCx..MaxCx] x [MinCz..MaxCz] that lies WITHIN the live StreamRadius of the focus is
	// already MESHED. The crust streamer calls this before RELEASING a tile, so the tile is kept
	// (a harmless overlap — the crust is sunk below the surface) until the voxels that replace it
	// actually exist. That overlap is what kills the transition HOLES. Columns beyond the stream
	// radius are ignored (the crust, not the live terrain, owns those) so a tile can never linger
	// forever. Pure read of MeshedColumns + the focus; changes no state.
	UFUNCTION(BlueprintCallable, Category = "MiraThal|NaniteCrust")
	bool AreCoveredColumnsReady(int32 MinCx, int32 MaxCx, int32 MinCz, int32 MaxCz) const;

	// --- DIAGNOSTIC LOD debug-color mode (TOOL 1; cvar mira.LodDebug) ---
	// Re-color EVERY currently-loaded chunk + super actor to match the live cvar value:
	// re-uploads each actor's cached mesh with the per-LOD debug tint (or removes it when
	// the cvar is 0). Called by the cvar change-sink the instant the tester flips the value,
	// so already-loaded terrain recolors without moving. Render override only — no voxel/
	// brick data, streaming, or budget is touched. Safe to call any time (no-op if nothing
	// is loaded). Public so the file-scope cvar sink lambda can reach it.
	void ApplyLodDebugRecolor();

	// The debug color a chunk/super at LOD `Lod` should get for the CURRENT cvar value, or
	// null (returns false) when this actor must keep its normal material color. `bSuper`
	// picks the cool super ramp. Pure helper around the Core palette + the cvar mode.
	bool GetLodDebugColor(int32 Lod, bool bSuper, FColor& OutColor) const;

	// Editor convenience: dig a Full (5^3) box straight down into the surface at
	// the world centre, so the dig loop is visible from the Details panel with no
	// gameplay input. Demonstrates the M2 carve->re-mesh path.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void CarveTestHole();

	// Programmatic carve at a UE world-space hit point (cm) with a surface normal,
	// removing an N^3 box (depth-biased into terrain). Applies to the brickmap and
	// re-meshes affected chunks. This is the entry a player tool / RPC will call.
	void CarveAtWorld(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels);

	// Preview ONLY: given the same (WorldPos, HitNormal, SideVoxels) a CarveAtWorld
	// call would use, return the world-space (cm) centre + half-extent of the exact
	// box that would be carved, so a HUD can outline it before the player digs. Uses
	// the identical compute_carve_box math, so the outline == the actual carve.
	// Returns false only on a degenerate input.
	bool ComputeCarvePreviewWorld(const FVector& WorldPos, const FVector& HitNormal,
		int32 SideVoxels, FVector& OutCenter, FVector& OutExtent) const;

	// Surface world-Z (UE cm) at a world XY, computed straight from the heightmap
	// generator (no meshing/collision needed, so it's valid the instant play starts).
	// Used to spawn the player exactly on the terrain for ANY heightmap/altitude, so a
	// height change never leaves the fixed spawn buried or floating. Loads the EXR
	// on demand if it isn't loaded yet.
	float SurfaceWorldZAt(double WorldX, double WorldY);

	// --- Surface-conforming dig (for top-down digs on slopes) ---
	// Remove the top SideVoxels solid voxels of EACH column in the SideVoxels×SideVoxels
	// XZ footprint around the aim, so a hillside dig follows the terrain and leaves no
	// uphill tops behind. (Use CarveAtWorld's centered box for wall/side digs instead.)
	void CarveColumnConforming(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels);

	// Preview for the above: OutColumnCenters gets the world-space (cm) centre of each
	// per-column carve stack (a 1-wide × SideVoxels-tall × 1-deep box), OutExtent the
	// shared half-size. Same column logic as the carve, so the outline == what's removed.
	// Returns false if nothing solid sits under the footprint.
	bool ComputeColumnPreview(const FVector& WorldPos, const FVector& HitNormal,
		int32 SideVoxels, TArray<FVector>& OutColumnCenters, FVector& OutExtent) const;

	// Pour finite water at a UE world-space point (cm): adds units to the sim,
	// which then flows downhill and pools. The entry a bucket/hose tool calls.
	void PourWaterAtWorld(const FVector& WorldPos, int32 Units);

	// After a carve, drop LOOSE material (sand/gravel) that lost its support within
	// a bubble around the dig. Applies the slides to the brickmap, journals them,
	// and re-meshes affected chunks. No-op unless bEnableGravity.
	void ApplyGravityAfterCarve(const mira::Vec3i& CarveCenterVoxel);

	// Editor convenience: pour TestPourUnits of water just above the centre
	// surface and run the sim to settle, so the dynamic water is visible from the
	// Details panel with no play session. Demonstrates the M3b pour-and-settle path.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|Water")
	void PourTestWater();

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void Tick(float DeltaSeconds) override;

	// The spawned chunk renderers, keyed by chunk coord.
	UPROPERTY(Transient)
	TMap<FIntVector, TObjectPtr<AVoxelChunkActor>> ChunkActors;

private:
	// --- Chunk-loading profiler (TOOL 2) bookkeeping ---
	// Per-tick op counts (set at the END of each TickStreaming) + a rolling worst-frame
	// window so a 150 ms spike stays on the HUD for ~2 s after it happens. All read-only
	// instrumentation: these counters never feed back into any streaming/budget decision.
	int32 GenOpsThisTick  = 0;       // gen columns applied last tick
	int32 MeshOpsThisTick = 0;       // chunk + super meshes uploaded last tick
	// Rolling worst-frame window: we keep the worst frame-ms seen in the last ~2 s, and the
	// worst frame-ms on a tick where mesh/gen ops > 0 (a "loading" frame). Reset when the
	// window ages out so old spikes don't pin the readout forever.
	float WorstFrameMsWindow     = 0.0f;
	float WorstLoadFrameMsWindow = 0.0f;
	float WorstFrameWindowAccum  = 0.0f; // seconds accumulated into the current window
	static constexpr float WorstFrameWindowSeconds = 2.0f;
	// TOOL 6 (per-phase loading attribution): worst single-tick wall-clock ms spent in each
	// game-thread streaming PHASE over the SAME ~2 s window as the frame timers above. These
	// answer "WHAT inside a 400 ms loading frame is the cost" — the gen apply (writing voxels +
	// replaying saved edits from disk), the mesh UPLOAD (CreateMeshSection), or the eviction
	// teardown. Surfaced in the perf CSV + STREAM STATS. Pure measurement; reset with the window.
	float WorstGenMsWindow   = 0.0f; // HarvestColumnGen   — apply voxels + disk edit-replay
	float WorstMeshMsWindow  = 0.0f; // HarvestColumnMesh  — game-thread mesh upload
	float WorstEvictMsWindow = 0.0f; // column + super eviction teardown
	float WorstHeroMsWindow  = 0.0f; // hero-column pass — SYNCHRONOUS LOD0 gen+mesh under the player
	// Update the rolling worst-frame window from this frame's delta + whether it loaded.
	// Called once per Tick. Pure measurement.
	void UpdateProfilerFrameWindow(float DeltaSeconds);

public:
	// --- Perf telemetry CSV (TOOL 3) -------------------------------------------------------
	// When ON, append one row of streaming/perf/water stats to <Project>/Saved/MiraThalPerf.csv
	// every PerfCsvIntervalSeconds. This is a designer/diagnostic file Claude (or you) can open
	// and read to see FPS, worst-frame spikes, queue depth, LOD-hole churn (fades/holds), and
	// water load OVER TIME — so problems get diagnosed from data instead of guesses. Pure
	// instrumentation: it only READS existing streaming state, never changes any of it.
	// Live-flippable in the Details panel (no rebuild) once this build lands.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics")
	bool bWritePerfCsv = false;
	// Seconds between CSV rows. Smaller = finer detail (more rows). 1s is a good default.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "0.1"))
	float PerfCsvIntervalSeconds = 1.0f;

	// --- Hole detector (TOOL 4) ------------------------------------------------------------
	// When ON, every HoleScanIntervalSeconds we scan the near band for columns that SHOULD be
	// visible (in-radius + their voxels are generated) but have NO mesh on screen — i.e. the
	// "random holes with no rhyme or reason". For each, we log WHY it's stuck: is a worker still
	// meshing it (inFlight), is a finished mesh waiting to upload (pending), or was it never even
	// queued (starved/evicted)? That single line is usually enough to pin the cause next time a
	// hole appears. Read-only: it only inspects existing streaming state.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics")
	bool bLogHoleDiagnostics = false;
	// How often to run the hole scan (seconds). 2s avoids log spam while still catching holes.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "0.25"))
	float HoleScanIntervalSeconds = 2.0f;
	// Only scan columns within this chunk-radius of the player (the band where a hole is visible
	// and inexcusable). 0 = use NearFullDepthRadiusChunks. Kept small so the scan is cheap.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "0"))
	int32 HoleScanRadiusChunks = 0;

	// --- Per-column lifecycle + HANG tracker (TOOL 5) --------------------------------------
	// The piece the older tools were missing: TIME. TOOL 4 can say a column is stuck, but not
	// for how long. This tracker reconciles EVERY active column's lifecycle phase
	// (queued-gen -> filled -> queued-mesh -> meshed) from the live streaming sets and stamps
	// the moment each one ENTERS its phase. A column sitting in a non-final phase longer than
	// ColumnHangSeconds is "HANGING" — genuinely stuck, not just mid-load. We log the worst
	// offenders (oldest first) with phase, age, distance, LOD and the REASON each is stuck, and
	// write per-phase counts + the worst hang age into the perf CSV. This is what turns
	// "terrain isn't loading" into "column (x,z) has been FILLED-but-unmeshed for 94 s because
	// the mesh budget is starved". Read-only — it never changes streaming state, and the
	// reconcile runs at ColumnLifeIntervalSeconds (≈1 Hz), NOT every frame, so it stays cheap.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics")
	bool bTrackColumnLifecycle = false;
	// Seconds between lifecycle reconciles. 1s matches the CSV cadence; bigger = cheaper.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "0.25"))
	float ColumnLifeIntervalSeconds = 1.0f;
	// A column stuck in one non-final phase longer than this (seconds) is reported as hanging.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "0.5"))
	float ColumnHangSeconds = 5.0f;
	// Cap on how many of the worst-hanging columns to log per report (so the log can't flood).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Diagnostics", meta = (ClampMin = "1"))
	int32 ColumnHangLogCount = 10;

private:
	// Append one stats row to the perf CSV (writes the header first if the file is fresh).
	void WritePerfCsvRow();
	float PerfCsvAccum            = 0.0f;   // seconds since the last row was written
	float PerfCsvWorstMsInterval  = 0.0f;   // worst frame-ms seen SINCE the last row (catches spikes between rows)
	bool  bPerfCsvStarted         = false;  // header written? (reset when the toggle flips off so re-enabling starts fresh)
	// Scan the near band for filled-but-unmeshed columns and log why each is stuck. Read-only.
	void ScanForHoles();
	float HoleScanAccum           = 0.0f;   // seconds since the last hole scan

	// --- Per-column lifecycle + hang tracker (TOOL 5) internals ---
	// The lifecycle phase a column can be in. The values double as indices into LifeCount[]
	// (so keep None=0 first and the rest contiguous). Meshed is the only "done" phase: a
	// meshed column that's re-meshing a LOD tier still reads as Meshed (that's a fast in-place
	// swap, not a load stall), so we never false-flag a tier change as a hang.
	enum class EColPhase : uint8 { None = 0, QueuedGen, Filled, QueuedMesh, Meshed };
	// Per tracked column: its current phase + the world-time (s) it entered that phase.
	struct FColLife { EColPhase Phase = EColPhase::None; double EnteredSec = 0.0; };
	TMap<FIntPoint, FColLife> ColumnLife;
	// Reconcile every active column's phase from the live sets, stamp phase-entry times, drop
	// evicted columns, refresh the cached histogram below, and log the worst hangs. ≈1 Hz.
	void UpdateColumnLifecycle();
	// The phase a single column is in RIGHT NOW, derived from the streaming sets (read-only).
	EColPhase DeriveColumnPhase(const FIntPoint& Col) const;
	// Human-readable phase name for logs + the CSV.
	static const TCHAR* ColPhaseName(EColPhase P);
	float  ColumnLifeAccum   = 0.0f;          // seconds since the last reconcile
	// Cached results of the last reconcile, so WritePerfCsvRow can emit them without redoing
	// the pass. LifeCount is indexed by EColPhase (None..Meshed).
	int32     LifeCount[5]   = { 0, 0, 0, 0, 0 };
	int32     HangingColumns = 0;             // non-final columns older than ColumnHangSeconds
	double    WorstHangSec   = 0.0;           // age of the single oldest hanging column
	EColPhase WorstHangPhase = EColPhase::None;
	// The single authoritative voxel store, held directly (pure C++; not a UPROPERTY
	// — it's not a UObject, just the sparse brick hash the renderers read from).
	// Named WorldStore (not "Brickmap") to avoid colliding with the mira::Brickmap type.
	mira::Brickmap WorldStore;

	// The imported EXR surface, held directly. Empty (invalid) until a successful
	// load; the generator only consults it when HeightSource = HeightmapEXR.
	mira::ImageHeightmap ImportedHeightmap;

	// The runtime AI-diffusion surface, held directly (mirrors ImportedHeightmap).
	// Empty (invalid) until SetDiffusionHeightmap() installs one; the generator only
	// consults it when HeightSource = DiffusionAI. Populated by the MiraThalTerrainAI
	// module — this module never reaches OUT to that one (preserves the dep root).
	mira::ImageHeightmap DiffusionHeightmap;
	// Seed the resident DiffusionHeightmap was generated from, folded into the
	// generator fingerprint so a stale baked crust is detected if the seed changes.
	int64 DiffusionSeed = 0;

	// --- Phase 2 streaming source (non-owning; owned by MiraThalTerrainAI) ---------
	// When set + valid(), ConfigureGenerator installs THIS as the height source (in place
	// of the bounded DiffusionHeightmap) and TickStreaming drives the ensure/ready
	// callbacks below. All default-null = no streaming (Phase-1 bounded path unchanged).
	const mira::IHeightSource*  StreamHeightSrc = nullptr;     // resident tile-cache source
	TFunction<void(FIntPoint)>  StreamEnsureFn;               // make tiles around focus resident
	TFunction<bool(FIntPoint)>  StreamColumnReadyFn;          // is this column's tile resident?

	// The authoritative player-edit journal (P2). Persists across regenerate; only
	// reset on an explicit new-world. Region files load on demand, save on flush.
	mira::WorldEditStore EditStore;
	// Region tiles whose disk file we've already tried to load this session (so we
	// don't hit disk repeatedly for the same region as its columns stream in).
	TSet<FIntPoint> LoadedEditRegions;

	// Record one carve/place edit (the voxel's FINAL state) into the journal.
	void RecordEdit(const mira::Vec3i& Voxel);
	// Ensure a region tile's saved edits are loaded from disk into EditStore.
	void EnsureEditRegionLoaded(const FIntPoint& Region);
	// Replay the journal's edits for a chunk-column's XZ footprint onto the brickmap.
	void ApplyEditsToColumn(int32 ccx, int32 ccz);

	// Build a HeightmapGenerator configured from the current knobs, with the EXR
	// override attached when in HeightmapEXR mode. Shared by generate + carve so
	// the dig digs into exactly the terrain that was generated.
	void ConfigureGenerator(mira::HeightmapGenerator& Gen) const;

	// Fill the brickmap from the generator across the configured region.
	void GenerateRegion();

	// --- Per-column generation primitives (shared by GenerateRegion + streaming) ---
	// Fill ONE XZ chunk-column's voxels into the brickmap (terrain + water + flora),
	// recording its vertical chunk span. No meshing. Idempotent (skips if filled).
	// GenLod (coarse far-gen, flag-gated) is the resolution to GENERATE at: 0 = full
	// 10 cm (legacy/default); >0 generates the column directly at LOD GenLod's stride.
	void FillChunkColumn(int32 ccx, int32 ccz, int32 GenLod = 0);
	// Mesh the vertical chunks of an already-filled column at the given LOD (0 = full
	// 10 cm detail; >0 = downsampled, P3). The 1-voxel mesh apron is satisfied because
	// callers fill a +1 column skirt first. Re-call with a new Lod to change tier.
	// DistChunks is the column's chunk distance to the focus, used ONLY by surface-shell
	// streaming to pick the meshed vertical extent (flag-gated; 0 == near == full depth,
	// which is also what every non-streaming caller passes so they always mesh full depth).
	void MeshChunkColumn(int32 ccx, int32 ccz, int32 Lod = 0, int32 DistChunks = 0);
	// Destroy the chunk actors of a column (drops its mesh; brick data is kept).
	void UnmeshChunkColumn(int32 ccx, int32 ccz);

	// --- Streaming (M4) ---
	void TickStreaming();
	bool GetFocusChunkXZ(FIntPoint& OutColumn) const;

	// --- View-prioritized streaming (flag-gated bViewPrioritizedStreaming) -----------
	// The focus's VIEW forward direction projected onto the voxel-horizontal plane,
	// in CORE (x,z) axes (the same axes the streaming chunk deltas use). Refreshed at
	// the top of each TickStreaming from the focus pawn's controller control-rotation
	// (or camera-manager forward). ZERO when no view is available (a focus actor with
	// no controller/camera) — view_priority_key then degrades to pure distance order,
	// so the ordering safely falls back to today's nearest-first. Only ever READ inside
	// the bViewPrioritizedStreaming branch, so it has no effect when the flag is off.
	FVector2D FocusForwardXZ = FVector2D::ZeroVector;
	// Recompute FocusForwardXZ from the current focus's view. Called once per stream
	// tick (cheap: one rotation->vector). Leaves it zero if no view source exists.
	void UpdateFocusForwardXZ();
	// Focus chunk shifted along the focus's velocity by PrefetchLeadChunks, so the
	// fill ring leads a moving player. Falls back to the plain focus when still.
	bool GetPrefetchFocusChunkXZ(FIntPoint& OutColumn) const;

	// --- P1: async column generation ----------------------------------------
public:
	// One generated column's result, produced on a worker thread (pure: terrain +
	// water + flora writes + the vertical chunk span). Applied on the game thread.
	// Public so the file-scope worker helper (GenerateColumnWritesPure) can fill it.
	struct FColumnGenResult
	{
		FIntPoint Key = FIntPoint(0, 0);
		// Flat write list: each entry sets one voxel's type OR water in the brickmap.
		// (bWater=false -> set_type(Type); bWater=true -> set_water(Water).)
		struct FWrite { int32 X, Y, Z; uint8 Value; bool bWater; };
		TArray<FWrite> Writes;
		int32 YLo = 0, YHi = 0;       // voxel Y span (pre-floor_div)
		uint32 Epoch = 0;             // generation epoch this job was launched under
		int32 GenLod = 0;             // resolution this column was generated at (coarse far-gen)
	};
private:
	// Apply a finished column's generated writes to the brickmap + bookkeeping
	// (shared by the sync fill path and the async harvest path). Game thread only.
	void ApplyColumnResult(const FColumnGenResult& R);
	// Launch (or skip if already filled/in-flight) an async generation job for a column.
	// GenLod (coarse far-gen, flag-gated) is the gen resolution; 0 = full-res (default).
	void EnqueueColumnGen(const FIntPoint& Col, int32 GenLod = 0);
	// Apply up to Budget finished jobs to the brickmap on the game thread; returns
	// how many were applied (so the caller can spend the rest of its budget meshing).
	int32 HarvestColumnGen(int32 Budget);
	// Block until every in-flight job finishes (called from ClearWorld so no worker
	// outlives the world's immutable inputs). Discards their results.
	void DrainColumnGen();

	// Columns whose async generation job is currently launched but not yet applied.
	TSet<FIntPoint> InFlightColumns;
	// In-flight jobs (future + the column + the epoch it was launched under).
	struct FPendingGen { FIntPoint Key; uint32 Epoch; TFuture<AVoxelWorld::FColumnGenResult> Future; };
	TArray<FPendingGen> PendingGen;
	// Bumped on ClearWorld; a harvested job from a stale epoch is discarded.
	uint32 GenEpoch = 0;

	// --- Async meshing (P1 sibling): worker greedy-mesh, game-thread upload ----------
	// Extract a column's chunk slabs on the game thread (cheap copies), mesh them all on
	// a worker, and upload finished buffers on the game thread. Shares GenEpoch so a
	// ClearWorld invalidates in-flight mesh jobs too.
	// DistChunks: see MeshChunkColumn — drives the surface-shell vertical extent (flag-gated).
	void EnqueueColumnMesh(const FIntPoint& Col, int32 Lod, int32 DistChunks = 0);  // GT: extract slabs + launch
	int32 HarvestColumnMesh(int32 Budget);                    // GT: upload up to Budget finished columns
	void DrainColumnMesh();                                   // GT: wait for + discard all in-flight
	TSet<FIntPoint> InFlightMeshColumns;                      // columns with a mesh job launched, not yet applied
	// Span = the chunk-Y span this job covers (the shell-restricted span when surface-shell
	// streaming is on; the full ColumnYRange otherwise) — recorded into ColumnMeshedYRange
	// on harvest so the next tick knows whether the span changed (deeper-on-approach).
	struct FPendingMesh { FIntPoint Key; uint32 Epoch; FIntPoint Span; TFuture<TSharedPtr<FMiraColumnMeshResult>> Future; };
	TArray<FPendingMesh> PendingMesh;

	// --- Super-chunk aggregation (far-band clipmap LOD) — flag-gated bEnableSuperChunks.
	//     Mirrors the async column-mesh path: a worker samples the heightmap into a coarse
	//     slab, the game thread uploads it. Keyed by SUPER coord (FIntVector: super-X, super-Y,
	//     super-Z, each = floor_div(chunkCoord, N)). All bookkeeping below is empty/no-op
	//     when the feature is off, so the default build is unaffected.
	void EnqueueSuperMesh(const FIntVector& Super, int32 SuperLodLevel);  // GT: snapshot + launch worker
	int32 HarvestSuperMesh(int32 Budget);                            // GT: upload up to Budget finished supers
	void DrainSuperMesh();                                           // GT: wait for + discard all in-flight
	// Desired super-LOD (0..5) for a super-chunk at chunk distance DistChunks; 0 if off.
	// L0-L2 are the original near-super bands; L3-L5 are the far-horizon extension.
	int32 DesiredSuperLod(int32 DistChunks, int32 CurrentLod) const;
	// UE world location for a super-chunk's renderer actor (apron offset folded in; Stride
	// = the fine-voxels-per-coarse-cell so the coarse mesh lands on the world grid).
	FVector SuperChunkActorLocation(const FIntVector& Super, int32 Stride) const;
	AVoxelChunkActor* EnsureSuperActor(const FIntVector& Super);
	void DestroySuperActor(const FIntVector& Super);
	void UnmeshSuper(const FIntVector& Super);

	// Super-chunks currently meshed (have a super actor) + the super-LOD each renders at.
	TSet<FIntVector> MeshedSupers;
	TMap<FIntVector, int32> SuperLod;
	// The spawned super-chunk renderer actors, keyed by super coord.
	UPROPERTY(Transient)
	TMap<FIntVector, TObjectPtr<AVoxelChunkActor>> SuperActors;
	// Super-chunks with a mesh job launched, not yet applied.
	TSet<FIntVector> InFlightSuperMeshes;
	struct FPendingSuperMesh { FIntVector Key; uint32 Epoch; TFuture<TSharedPtr<FMiraSuperMeshResult>> Future; };
	TArray<FPendingSuperMesh> PendingSuperMesh;

	// --- Dynamic water (M3b) ---
	// Lazily build the FiniteWaterCore bound to WorldStore (solid = non-air terrain,
	// source = ocean SOURCE bytes). Safe to call repeatedly.
	void EnsureWaterSim();
	// Advance the water sim by `steps` ticks, write projected bytes into the
	// brickmap, and re-mesh every chunk a change touched. Returns chunks re-meshed.
	int  StepWaterSim(int32 steps, int32 budget);
	// After a carve, seed finite water into newly-opened air cells that sit at/below
	// sea level next to existing water, so the parent volume floods the hole (the
	// sim then fills it bottom-up). No-op unless the water sim is enabled.
	void FloodCarveFromNeighbours(const std::vector<mira::VoxelWrite>& Writes);
	// STREAM-IN RE-ACTIVATE (flag-gated). When a column streams in, wake any water
	// voxel on its 1-voxel OUTER XZ border whose face-neighbour lies in an already-
	// filled column, so a pool that was clamped against the formerly-unloaded edge
	// (which read as SOLID) flows onward. ChunkYLo/Hi bound the column's vertical
	// span. Scans only the seam ring (O(perimeter)); only meaningful with the sim on.
	void ActivateColumnSeamWater(const FIntPoint& Col, int32 ChunkYLo, int32 ChunkYHi);
	// The finite water sim; null until the first pour/EnsureWaterSim. Pointer (not
	// value) because FiniteWaterCore has no default ctor (predicates injected).
	TUniquePtr<mira::FiniteWaterCore> WaterSim;
	// Real-seconds accumulator so the play-mode tick fires the sim at WaterSimHz.
	float WaterSimAccum = 0.0f;

	// --- Open-ocean sea plane (M-water, flag-gated bEnableSeaPlane) ---
	// Spawn (once) / reposition the single sea-level water quad and keep it centred on
	// the focus XY at world sea-level Z. No-op (and the plane is hidden/destroyed) when
	// the flag is OFF. Called each stream tick (cheap: just a move once spawned). Reads
	// SeaLevelMeters LIVE so the plane tracks the editor knob.
	void EnsureSeaPlane();
	// The lone sea-plane renderer component (a flat 2-tri quad in WaterMaterial). Null
	// until the flag is first ON in play. Parented under this actor's root.
	UPROPERTY(Transient)
	TObjectPtr<UProceduralMeshComponent> SeaPlaneMesh;
	// World Z (UE cm) the sea plane was last built at, so we only rebuild its geometry
	// when SeaLevelMeters or the size actually changes (a plain re-centre just moves it).
	double SeaPlaneBuiltZ = 0.0;
	double SeaPlaneBuiltHalfExtentUU = 0.0;

	// XZ columns whose brick voxels are generated (the fill skirt is a superset of
	// the meshed set so every meshed chunk's apron has neighbour data).
	TSet<FIntPoint> FilledColumns;
	// XZ columns currently meshed (have chunk actors).
	TSet<FIntPoint> MeshedColumns;
	// Per filled column: the [min,max] vertical CHUNK indices that hold voxels,
	// so meshing/eviction knows how tall the column is. (X=loChunkY, Y=hiChunkY.)
	// This is the FULL generated span (always full depth — gen is unchanged). Surface-
	// shell streaming (below) RESTRICTS how much of it a far column actually meshes.
	TMap<FIntPoint, FIntPoint> ColumnYRange;

	// --- 3D / spherical surface-shell streaming (flag-gated b3DShellStreaming) ---
	// The EFFECTIVE meshed chunk-Y span per meshed column (X=lo, Y=hi). With the shell
	// flag OFF this always equals the full ColumnYRange (behaviour unchanged); with it
	// ON, a FAR column's span is clamped to the surface shell, so it meshes far fewer
	// chunk actors. Re-meshing is triggered when this span CHANGES (deeper-on-approach:
	// a far column that becomes near grows its span back toward full depth).
	TMap<FIntPoint, FIntPoint> ColumnMeshedYRange;

	// PERF: memoized surface chunk-Y per column for the 3D-shell cull. A column's surface
	// height comes ONLY from the immutable heightmap, so it never changes for the life of the
	// world — yet the shell cull used to recompute it (build a generator + sample the EXR) for
	// every column in the fill field AND every meshed column, EVERY frame. At a 64-chunk radius
	// that's ~16k generator builds per frame — it was pinning the game thread at ~333 ms (≈3 FPS)
	// even when nothing was streaming. Computing each column ONCE and caching it here turns that
	// into a hash lookup. Cleared on ClearWorld (a regen can change the generator inputs).
	TMap<FIntPoint, int32> ColumnSurfaceYCache;

	// Step 1: real-seconds accumulator gating the super-chunk enqueue sweep (cadence cap above).
	float SuperSweepAccum = 0.0f;

	// Step 1b: DIG-SPAN GROWTH. Per XZ column, the [min,max] chunk-Y rows a DIG has touched
	// (X=lowest, Y=highest). DesiredMeshYRange unions this into the surface shell so a dig —
	// especially a shaft dug below the thin slab — stays meshed (the hole renders) instead of
	// vanishing under the surface-volume cull. Grows only (never shrinks) so nothing pops out.
	// Cleared on ClearWorld. Empty for any column that's never been dug.
	TMap<FIntPoint, FIntPoint> ColumnDugSpanChunkY;
	// Step 1b: memoized surface VOXEL-Y per column for DesiredMeshYRange (which is const and
	// runs per meshed column per frame in the span-change check). Same idea as ColumnSurfaceYCache
	// but voxel-Y (shell math needs the surface voxel row), and mutable so the const method can
	// fill it. Heightmap-derived = constant for the world's life; cleared on ClearWorld.
	mutable TMap<FIntPoint, int32> ColumnSurfaceVoxelYCache;

	// The chunk-Y span a column SHOULD mesh right now, given the shell flag + the
	// column's distance to the focus. With the flag off (or NEAR), returns the full
	// ColumnYRange. With it on + FAR, returns the surface-shell-clamped span. Returns
	// false if the column isn't filled (no ColumnYRange entry). DistChunks is the
	// column's chunk distance to the TRUE focus.
	bool DesiredMeshYRange(const FIntPoint& Col, int32 DistChunks, FIntPoint& OutRange) const;

	// Extract the chunk's slab from the brickmap and (re)render it; skips/destroys
	// the actor when the chunk is fully empty. Lod 0 = full 10 cm detail; Lod>0
	// downsamples the slab (2^Lod fine voxels per coarse voxel) and renders the
	// coarse mesh at the matching scale (P3). Lod is clamped to keep a chunk
	// divisible (CHUNK=32 -> max LOD 3 = 4^3 coarse cells).
	void RemeshChunk(const FIntVector& ChunkCoord, int32 Lod = 0);

	// Desired LOD for a column at chunk distance Dist from the focus (P3). Uses the
	// harness-locked LodTier thresholds with HYSTERESIS (CurrentLod = the column's
	// existing LOD) so a column sitting on a tier boundary doesn't flip every frame.
	// Returns 0 when bEnableLOD is off.
	int32 DesiredColumnLod(int32 DistChunks, int32 CurrentLod) const;
	// Current LOD a meshed column is rendered at, so we only re-mesh on a tier change.
	TMap<FIntPoint, int32> ColumnLod;

	// --- LOD-transition dither cross-fade (flag-gated bEnableLodFade) -----------------
	// One in-progress cross-fade for a column. When a column commits a LOD change we keep
	// its OLD-LOD chunk actors alive as `Outgoing` (a column spans several chunk-Y rows,
	// so this is an ARRAY of the old actors, not one), let the normal remesh build FRESH
	// new-LOD actors into ChunkActors as the column's primary, and tick both meshes' dither
	// FadeAlpha until the new mesh is fully in — then destroy the outgoing actors. All of
	// this only ever exists while the flag is on; ActiveFades/PendingLodAfterFade stay empty
	// (no allocation, no iteration cost) when it's off.
	struct FFadeRecord
	{
		FIntPoint Col = FIntPoint(0, 0);                          // which column is fading
		TArray<TObjectPtr<AVoxelChunkActor>> Outgoing;           // the OLD-LOD actors (one per chunk-Y row)
		double StartTime = 0.0;                                   // World->GetTimeSeconds() at fade start
		float  Duration  = 0.35f;                                 // seconds the fade lasts (LodFadeSeconds)
		int32  IncomingLod = 0;                                   // the new LOD the primary actors carry
		FIntPoint TargetSpan = FIntPoint(0, 0);                  // committed meshed span the incoming mesh must match (hold-only)
		// MESH-THEN-SWAP HOLD (Bug-2): when true this record is a dither-FREE "swap-hold"
		// (bKeepOldLodUntilReady), NOT a cross-fade. TickFades then must NOT touch FadeAlpha;
		// it instead destroys Outgoing the instant the incoming primary mesh is genuinely
		// ready (in MeshedColumns, not in-flight, and its committed span == TargetSpan —
		// the should_destroy_outgoing predicate). With false it's the original alpha fade.
		bool bHoldOnly = false;
	};
	TArray<FFadeRecord> ActiveFades;
	// A column already mid-fade that wanted ANOTHER LOD change: we defer it here and apply
	// it when the current fade finishes (one fade per column at a time — never stack two).
	TMap<FIntPoint, int32> PendingLodAfterFade;

	// True if this column currently has an in-flight cross-fade (an ActiveFades entry).
	bool IsColumnFading(const FIntPoint& Col) const;
	// Begin a cross-fade for a column whose LOD just changed: detach the column's CURRENT
	// (old-LOD) actors from ChunkActors into a new FFadeRecord as Outgoing, so the remesh
	// the caller is about to run spawns FRESH new-LOD actors as the primary. Returns true
	// if a fade was started (the caller should then remesh the column normally). Returns
	// false if no old actors existed to fade (caller falls back to the plain remesh — a
	// brand-new column has nothing to cross-fade FROM). Flag-gated by the caller.
	bool BeginColumnFade(const FIntPoint& Col, int32 OldLod, int32 NewLod);
	// MESH-THEN-SWAP (Bug-2): the bHoldOnly=true variant of BeginColumnFade. Detaches the
	// column's CURRENT (old-LOD) actors into Outgoing EXACTLY like BeginColumnFade, but marks
	// the record as a dither-free swap-HOLD: the old mesh is kept on screen as a backstop (no
	// alpha touched) until the new mesh genuinely uploads, then destroyed in one step (see
	// TickFades + Core/LodFade.h should_destroy_outgoing). TargetSpan is the meshed span the
	// incoming mesh must match before the hold releases. Returns false if there were no old
	// actors to hold (caller falls back to the plain remesh). Flag-gated by the caller.
	bool BeginColumnSwapHold(const FIntPoint& Col, int32 OldLod, int32 NewLod, const FIntPoint& TargetSpan);
	// True if this column currently has a swap-HOLD record (bHoldOnly), as opposed to a
	// dither cross-fade. Used to gate the deferred out-of-span destroy in the mesh paths.
	bool IsColumnSwapHolding(const FIntPoint& Col) const;
	// Advance every active cross-fade by Dt (called from Tick): set the incoming primary
	// actors' FadeAlpha to a and the outgoing actors' to (1-a); when a >= 1 finish the
	// fade (destroy the outgoing actors, drop the record) and apply any deferred LOD change.
	void TickFades(float Dt);
	// Tear down a column's cross-fade record WITHOUT touching its primary actors: destroy
	// only the Outgoing actors and drop the record + any deferred LOD. Used by the eviction
	// / unmesh / clear paths so an outgoing mesh never leaks when its column goes away.
	// Returns true if a record existed for the column.
	bool CancelColumnFade(const FIntPoint& Col);
	// Apply a LOD change that was DEFERRED (the column was mid-fade when it was wanted):
	// start a fresh fade from the current actors and remesh to WantLod. Called by TickFades
	// when a fade finishes and PendingLodAfterFade had an entry for that column.
	void ApplyDeferredColumnLod(const FIntPoint& Col, int32 WantLod);

	// Desired GENERATION LOD for a column at chunk distance DistChunks from the TRUE
	// focus (coarse far-gen). 0 unless bEnableLOD && bCoarseFarGen; then the PLAIN
	// (no-hysteresis) LodTier rule, so gen is never coarser than the finest render LOD.
	int32 GenLodForDistance(int32 DistChunks) const;
	// Drop + clear a generated column so the next ring sweep re-generates it (coarse
	// far-gen approach-invalidation: re-gen FINER as the player nears). Player edits
	// survive (they replay from EditStore in ApplyColumnResult).
	void InvalidateColumnFill(const FIntPoint& Col);
	// Per filled column: the gen-LOD it was generated at (so approach-invalidation
	// only re-gens columns that are currently COARSER than now wanted).
	TMap<FIntPoint, int32> ColumnGenLod;

	// BUG-1: columns whose voxels were just OVERWRITTEN by a finer re-gen while their old
	// (coarser) mesh is still live (non-destructive approach-invalidation kept the old mesh
	// + actors). The mesh sweep must re-mesh these IN PLACE even though their render-LOD /
	// shell span didn't change, so the finer detail actually shows. Marked in ApplyColumnResult,
	// consumed (and cleared) by the TickStreaming mesh sweep. Empty in the common case.
	TSet<FIntPoint> DirtyRemeshColumns;

	// Find or spawn the renderer actor for a chunk coord, positioned so its slab
	// tiles seamlessly with neighbours (apron offset folded into the transform).
	AVoxelChunkActor* EnsureChunkActor(const FIntVector& ChunkCoord);
	void DestroyChunkActor(const FIntVector& ChunkCoord);

	// --- AVoxelChunkActor pooling (free-list) ---------------------------------------
	// Spawning a chunk actor is ~0.5 ms (a frame profile showed 3.75 ms for 8 spawns as
	// the player moved). Instead of Spawn/Destroy we RECYCLE actors through a free-list:
	// a chunk leaving the world is parked (hidden, collision off) and pushed here; a chunk
	// entering the world pops one and remeshes into it. Chunk actors and super actors are
	// the SAME UClass (they differ only in mesh content, which PrepareForReuse wipes), so
	// both share this one pool.
	//
	// Held as a UPROPERTY of TObjectPtr so the GC keeps the parked actors alive while
	// they sit idle (they are real UObjects, just hidden).
	UPROPERTY(Transient)
	TArray<TObjectPtr<AVoxelChunkActor>> ActorPool;

	// Pool size cap. 0 turns pooling OFF entirely (Acquire always spawns, Recycle always
	// Destroys) — kept as a safety escape hatch in case pooling ever misbehaves. When the
	// pool is full, extra recycled actors are Destroy()'d rather than hoarded.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel|Streaming")
	int32 MaxPooledChunkActors = 256;

	// Get a chunk renderer actor for Coord at Xform: pop a parked one from the pool and
	// reset it (fast path), or SpawnActorDeferred a fresh one (pool empty / pooling off).
	// The returned actor is positioned, unhidden, collision-on, world-managed, and has an
	// EMPTY mesh — the caller remeshes into it. Does NOT add to any map; callers store it.
	AVoxelChunkActor* AcquireChunkActor(const FIntVector& Coord, const FTransform& Xform);

	// Return a chunk renderer actor to the world: if pooling is on and the pool has room,
	// park it (hide + collision off) and push it onto the free-list for reuse; otherwise
	// Destroy() it. This replaces the bare Actor->Destroy() at every chunk-actor teardown
	// site (eviction, fade-outgoing, clear). Safe with a null actor (no-op).
	void RecycleChunkActor(AVoxelChunkActor* Actor);

	// UE world location for a chunk's renderer actor. LodScale = 2^Lod (1 at LOD 0);
	// a coarse LOD chunk's apron is LodScale fine voxels wide, so its origin shifts
	// accordingly to keep the coarse mesh aligned with the full-detail neighbours.
	FVector ChunkActorLocation(const FIntVector& ChunkCoord, int32 LodScale = 1) const;
};
