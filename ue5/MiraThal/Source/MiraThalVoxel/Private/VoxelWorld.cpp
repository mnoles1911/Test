// VoxelWorld.cpp — M2 multi-chunk world: generate + carve + re-mesh.
//                  M3 adds an imported-EXR terrain source (see ConfigureGenerator).
#include "VoxelWorld.h"
#include "VoxelGenParams.h"           // FGenParams / BuildGen / SnapshotGenParams (shared with the
                                      // Nanite bake module so both build BYTE-IDENTICAL generators)
#include "VoxelChunkActor.h"
#include "HeightmapImport.h"          // MiraHeightmapImport::LoadHeightmapImage
#include "WorldEditPersistence.h"     // region delta-file I/O (P2)
#include "Core/RegionFormat.h"        // encode/decode_delta_log (P2)
#include "Engine/World.h"
#include "ProceduralMeshComponent.h"  // sea-plane quad (M-water, flag-gated)
#include "Materials/MaterialInterface.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"          // perf telemetry CSV (TOOL 3)
#include "Kismet/GameplayStatics.h"   // GetPlayerPawn (streaming focus)
#include "GameFramework/Pawn.h"
#include "GameFramework/Controller.h"          // AController::GetControlRotation (view forward)
#include "GameFramework/PlayerController.h"    // APlayerController::PlayerCameraManager fallback
#include "Camera/PlayerCameraManager.h"        // PlayerCameraManager::GetCameraRotation
#include "Async/Async.h"              // Async(EAsyncExecution::ThreadPool, ...) — P1 worker jobs
#include <climits>                    // INT_MAX / INT_MIN

// Engine-agnostic Core (no Unreal types below this line's logic).
#include "Core/MiraVec.h"            // Vec3i, Vec3
#include "Core/ChunkCoords.h"        // coords::CHUNK, floor_div, chunk_origin_voxel
#include "Core/VoxelChunk.h"         // DenseGrid, APRON
#include "Core/Brickmap.h"           // Brickmap (authoritative store)
#include "Core/BrickmapMeshing.h"    // extract_mesh_slab, apply_writes, affected_chunks
#include "Core/HeightmapGenerator.h" // HeightmapGenerator, ColumnInfo
#include "Core/CoarseColumnGen.h"    // coarsegen::fill_column — column-fill math (coarse far-gen)
#include "Core/MaterialIds.h"        // mat::*
#include "Core/WaterByteCodec.h"     // WaterByteCodec::SOURCE_BYTE
#include "Core/MiningCarve.h"        // mining::compute_carve_box / compute_carve, VoxelWrite
#include "Core/FiniteWaterCore.h"    // FiniteWaterCore — the dynamic water sim (M3b)
#include "Core/VoxelGravity.h"       // analyze_bubble — gravity-on-dig (M3c)
#include "Core/LodDownsample.h"      // lod::downsample_to_lod — P3 voxel LOD
#include "Core/LodTier.h"            // lodtier::lod_for_distance — P3 distance->tier
#include "Core/LodFade.h"            // lodfade::fade_alpha / should_start_fade — LOD cross-fade math
#include "Core/SuperChunk.h"         // superchunk::* — far-band aggregation LOD math
#include "Core/StreamShell.h"        // streamshell::* — 3D/spherical surface-shell streaming math
#include "Core/ViewPriority.h"       // viewpriority::view_priority_key — view-prioritized streaming order
#include "Core/MeshTypes.h"         // mira::MeshBuffers — async-mesh job payload
#include "Core/VoxelColor.h"        // mira::lod_debug_color — DIAGNOSTIC per-LOD debug tint
#include "VoxelChunkActor.h"        // AVoxelChunkActor::BuildMeshBuffers (worker mesh)
#include "HAL/IConsoleManager.h"    // TAutoConsoleVariable — the mira.LodDebug diagnostic toggle

// ===========================================================================
// DIAGNOSTIC: LOD debug-color mode (TOOL 1). Console variable the tester types live
// in the PIE console: `mira.LodDebug 1` colors the SURFACE terrain by LOD LEVEL
// (concentric rings) instead of material color; `mira.LodDebug 0` restores normal
// colors. This is a RENDER + MEASURE override ONLY — it never changes streaming,
// meshing, budgets, or voxel/brick data. When it's 0 (default) every code path below
// is byte-for-byte what it was before.
//   0 = off (default, normal material colors)
//   1 = color PER-CHUNK terrain by LOD (supers keep their normal color)
//   2 = also color SUPER-CHUNKS by their super-LOD (cool/blue ramp)
// The change-sink (registered in AVoxelWorld::BeginPlay) re-colors ALREADY-loaded
// chunks the instant the value flips, by re-uploading each loaded actor's cached mesh
// with the debug tint — a brief one-time hitch on toggle, fine for a debug tool.
// ===========================================================================
static TAutoConsoleVariable<int32> CVarMiraLodDebug(
	TEXT("mira.LodDebug"),
	0,
	TEXT("DIAGNOSTIC: color terrain by LOD level. 0=off (normal colors), 1=per-chunk LODs, 2=also super-chunks. Render-only; no streaming/voxel change."),
	ECVF_Default);

// ===========================================================================
// P1 async generation — a column's terrain is PURE (reads only the immutable
// EXR + scalar knobs), so it can be generated on a worker thread. These
// file-scope helpers carry no Unreal-actor state: a snapshot of the generator
// knobs (FGenParams) + the read-only heightmap pointer is all a worker needs.
//
// NOTE: FGenParams + BuildGen + SnapshotGenParams were PROMOTED to the shared
// Public header VoxelGenParams.h (included above) so the Nanite cold-bake module
// builds a BYTE-IDENTICAL generator and the baked far crust lines up with these
// near voxels at the seam. The definitions there are identical to the ones that
// used to live in this anonymous namespace — pure refactor, no behaviour change.
// ===========================================================================
namespace
{

	// Generate ONE XZ chunk-column's voxels into a flat write list (terrain + water +
	// flora), recording the vertical voxel span. PURE — no brickmap, no edits, no
	// Unreal actor state. Thin ADAPTER over mira::coarsegen::fill_column (the column-
	// fill MATH lives in Core/CoarseColumnGen.h so the headless harness can test it).
	//
	// P.GenLod 0 (the default, and ALWAYS when bCoarseFarGen is off) reproduces the
	// legacy fine fill loop voxel-for-voxel, so sync + async + flag-off coarse share
	// ONE code path. P.GenLod L>0 generates the column directly at LOD L's resolution
	// (coarse far-generation), landing on the same voxels a downsample would produce.
	void GenerateColumnWritesPure(int ccx, int ccz, const FGenParams& P,
	                              AVoxelWorld::FColumnGenResult& Out)
	{
		using namespace mira;
		HeightmapGenerator Gen;
		BuildGen(P, Gen);

		// Gate the coarse resolution on the master flag: with bCoarseFarGen off we
		// always feed gen_lod 0, so fill_column takes the full-res branch (unchanged).
		const int EffGenLod = P.bCoarseFarGen ? P.GenLod : 0;

		std::vector<coarsegen::ColWrite> Writes;
		int YLo = 0, YHi = 0;
		coarsegen::fill_column(ccx, ccz, EffGenLod, Gen, P.ChunkDepthBelow, Writes, YLo, YHi);

		Out.Writes.Reserve(Out.Writes.Num() + static_cast<int32>(Writes.size()));
		for (const coarsegen::ColWrite& W : Writes)
		{
			Out.Writes.Add({ W.x, W.y, W.z, W.value, W.water });
		}
		Out.YLo = YLo;
		Out.YHi = YHi;
	}
} // namespace

AVoxelWorld::AVoxelWorld()
{
	// Tickable so streaming can page columns around the focus; the tick is only
	// actually enabled in BeginPlay when bEnableStreaming is set.
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = false;
}

// Out-of-line dtor: TUniquePtr<FiniteWaterCore> needs the complete type to destruct,
// and it's only forward-declared in the header (kept light).
AVoxelWorld::~AVoxelWorld() = default;

void AVoxelWorld::BeginPlay()
{
	Super::BeginPlay();

	// DIAGNOSTIC (TOOL 1): register the mira.LodDebug change-sink so the instant the tester
	// flips the cvar in the PIE console, ALL already-loaded chunks/supers recolor (or revert)
	// without moving. Captured weakly via TWeakObjectPtr so a torn-down world is a safe no-op.
	{
		TWeakObjectPtr<AVoxelWorld> WeakThis(this);
		CVarMiraLodDebug.AsVariable()->SetOnChangedCallback(
			FConsoleVariableDelegate::CreateLambda([WeakThis](IConsoleVariable*)
			{
				if (AVoxelWorld* Self = WeakThis.Get())
				{
					Self->ApplyLodDebugRecolor();
				}
			}));
	}

	if (bEnableStreaming)
	{
		// Streaming owns generation: load the heightmap once, then the tick pages
		// columns in around the focus. Don't pre-build the fixed region.
		LoadHeightmapIfNeeded();
		SetActorTickEnabled(true);
		EnsureSeaPlane(); // spawn the open-ocean plane now if the flag is on (no-op if off)
		return;
	}

	// Non-streaming: auto-build the fixed region when play starts if empty.
	if (ChunkActors.Num() == 0)
	{
		GenerateWorld();
	}

	// The water sim also needs ticking (independently of streaming).
	if (bEnableWaterSim)
	{
		EnsureWaterSim();
		SetActorTickEnabled(true);
	}

	// Open-ocean plane (non-streaming path): spawn it now, and tick so it follows the
	// focus. No-op when the flag is off, so the non-streaming build stays unchanged.
	if (bEnableSeaPlane)
	{
		EnsureSeaPlane();
		SetActorTickEnabled(true);
	}
}

void AVoxelWorld::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (bEnableStreaming)
	{
		TickStreaming();
	}
	// DIAGNOSTIC (TOOL 2): fold this frame's delta into the rolling worst-frame window AFTER
	// TickStreaming has set this tick's op counts, so the "worst-while-loading" classification
	// sees whether work was uploaded this tick. Pure measurement — changes no streaming state.
	UpdateProfilerFrameWindow(DeltaSeconds);
	// DIAGNOSTIC (TOOL 3): perf telemetry CSV. Track the worst frame THIS interval (so a spike
	// between rows is never missed), then append a stats row every PerfCsvIntervalSeconds when
	// the toggle is on. Pure measurement — reads existing state, never changes streaming.
	if (bWritePerfCsv)
	{
		const float FrameMs = DeltaSeconds * 1000.0f;
		PerfCsvWorstMsInterval = FMath::Max(PerfCsvWorstMsInterval, FrameMs);
		PerfCsvAccum += DeltaSeconds;
		if (PerfCsvAccum >= FMath::Max(0.1f, PerfCsvIntervalSeconds))
		{
			WritePerfCsvRow();
			PerfCsvAccum = 0.0f;
			PerfCsvWorstMsInterval = 0.0f;
		}
	}
	else if (bPerfCsvStarted)
	{
		// Toggle flipped off: reset so the next enable starts a brand-new file (fresh header).
		bPerfCsvStarted = false;
	}
	// DIAGNOSTIC (TOOL 4): periodic hole scan — logs near columns that are generated but have no
	// mesh on screen, with the reason each is stuck. Off by default; pure measurement.
	if (bLogHoleDiagnostics)
	{
		HoleScanAccum += DeltaSeconds;
		if (HoleScanAccum >= FMath::Max(0.25f, HoleScanIntervalSeconds))
		{
			ScanForHoles();
			HoleScanAccum = 0.0f;
		}
	}
	// Advance any in-flight LOD cross-fades (drives both meshes' dither FadeAlpha and
	// retires finished fades). No-op when bEnableLodFade is off (ActiveFades is empty).
	TickFades(DeltaSeconds);
	// Keep the open-ocean plane centred under the focus at live sea level (no-op when
	// bEnableSeaPlane is off — it just hides/destroys any existing plane and returns).
	EnsureSeaPlane();
	if (bEnableWaterSim && WaterSim.IsValid())
	{
		// Fire the sim at WaterSimHz regardless of frame rate (deterministic ticks).
		WaterSimAccum += DeltaSeconds;
		const float Period = 1.0f / FMath::Max(1.0f, WaterSimHz);
		const int MaxSteps = FMath::Max(1, WaterMaxStepsPerTick); // formalised catch-up cap
		int Steps = 0;
		while (WaterSimAccum >= Period && Steps < MaxSteps) // cap catch-up to avoid spirals
		{
			WaterSimAccum -= Period;
			++Steps;
		}
		if (Steps > 0)
		{
			StepWaterSim(Steps, WaterStepBudget);
		}
	}
}

void AVoxelWorld::EndPlay(const EEndPlayReason::Type Reason)
{
	// DIAGNOSTIC (TOOL 1): drop our mira.LodDebug change-sink so this torn-down world's lambda
	// isn't left registered on the global cvar. (Re-PIE re-registers a fresh one in BeginPlay.)
	if (IConsoleVariable* CVar = CVarMiraLodDebug.AsVariable())
	{
		CVar->SetOnChangedCallback(FConsoleVariableDelegate());
	}
	SaveEdits(); // flush the player's journalled edits before tearing down
	ClearWorld();
	Super::EndPlay(Reason);
}

// ---------------------------------------------------------------------------
// Generation: fill the brickmap from the Core generator, then mesh each chunk.
// ---------------------------------------------------------------------------
void AVoxelWorld::GenerateWorld()
{
	ClearWorld();
	LoadHeightmapIfNeeded();
	GenerateRegion();
}

// ---------------------------------------------------------------------------
// Terrain source plumbing (M3): load the EXR + build a configured generator.
// ---------------------------------------------------------------------------
bool AVoxelWorld::LoadHeightmapIfNeeded()
{
	ImportedHeightmap = mira::ImageHeightmap(); // reset to invalid each (re)generate
	if (HeightSource != EVoxelHeightSource::HeightmapEXR)
	{
		return true; // procedural path needs no image
	}

	// Resolve the path (allow project-relative entries for convenience).
	FString Path = HeightmapFile.FilePath;
	if (!Path.IsEmpty() && FPaths::IsRelative(Path))
	{
		Path = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir(), Path);
	}

	FString LoadError;
	if (Path.IsEmpty() || !MiraHeightmapImport::LoadHeightmapImage(Path, ImportedHeightmap, LoadError))
	{
		UE_LOG(LogTemp, Error,
			TEXT("[MiraThal] EXR heightmap load failed (%s) — falling back to procedural."),
			Path.IsEmpty() ? TEXT("no file set") : *LoadError);
		ImportedHeightmap = mira::ImageHeightmap();
		return false;
	}

	// VERTICAL EXAGGERATION (designer choice, 2026-06-18): normalize the EXR values so
	// the tallest peak stretches up to the full HeightmapAltitudeMeters ceiling (2500 m).
	// This Gaea map's true peak is only ~31% of the ceiling (~775 m), which read as flat;
	// normalizing rescales the whole relief into 0..1 so peaks reach ~2500 m and valleys
	// drop to the base. This is deliberate exaggeration past the artist's literal heights
	// (the designer asked to "scale up to 2500 m"). Remove this call to restore true
	// fraction-of-ceiling heights. The far vista normalizes identically so they match.
	ImportedHeightmap.normalize_to_unit();

	// Apply georeferencing from the designer knobs. 10 voxels per metre is the
	// world scale (VoxelScale single source of truth). A 5 km map => 50,000 voxels.
	constexpr double VoxelsPerMetre = 10.0;
	const double SpanVoxels = static_cast<double>(MapSpanMeters) * VoxelsPerMetre;
	ImportedHeightmap.set_centered_extent(SpanVoxels, SpanVoxels);
	ImportedHeightmap.vertical_scale_voxels = static_cast<double>(HeightmapAltitudeMeters) * VoxelsPerMetre;
	ImportedHeightmap.vertical_base_voxels  = static_cast<double>(HeightmapBaseMeters) * VoxelsPerMetre;
	ImportedHeightmap.flip_z = bFlipHeightmapZ;

	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] EXR heightmap loaded: %dx%d px over %.0f m (%.1f vox/px), "
		     "altitude %.0f m, base %.0f m, SEA %.0f m (%d vox)."),
		ImportedHeightmap.width, ImportedHeightmap.height, MapSpanMeters,
		ImportedHeightmap.voxels_per_pixel, HeightmapAltitudeMeters, HeightmapBaseMeters,
		SeaLevelMeters, FMath::RoundToInt(SeaLevelMeters * 10.0f));
	return true;
}

void AVoxelWorld::ConfigureGenerator(mira::HeightmapGenerator& Gen) const
{
	Gen.set_seed(static_cast<int64_t>(Seed));
	Gen.height_range_voxels  = MacroRangeVoxels;
	Gen.mid_amplitude_voxels = MidAmplitudeVoxels;
	Gen.height_offset_voxels = HeightOffsetVoxels;
	Gen.macro_frequency      = MacroFrequency;
	Gen.sea_level_voxels     = FMath::RoundToInt(SeaLevelMeters * 10.0f);

	// Attach the imported surface when in EXR mode and it loaded successfully.
	// compute_ground_y then reads the EXR and the banding/water/flora follow.
	if (HeightSource == EVoxelHeightSource::HeightmapEXR && ImportedHeightmap.valid())
	{
		Gen.set_height_source(&ImportedHeightmap);
	}
}

void AVoxelWorld::GenerateRegion()
{
	// Build the fixed preview region. Fill the radius PLUS a one-column skirt so
	// every meshed chunk's 1-voxel apron has real neighbour data (seamless), then
	// mesh only the inner radius.
	const int R = ChunkRadiusXZ;
	for (int ccx = -R - 1; ccx <= R + 1; ++ccx)
	for (int ccz = -R - 1; ccz <= R + 1; ++ccz)
	{
		FillChunkColumn(ccx, ccz);
	}
	for (int ccx = -R; ccx <= R; ++ccx)
	for (int ccz = -R; ccz <= R; ++ccz)
	{
		MeshChunkColumn(ccx, ccz);
	}
}

// ---------------------------------------------------------------------------
// Per-column generation primitives (shared by the fixed region + streaming).
// ---------------------------------------------------------------------------
// (SnapshotGenParams was promoted to VoxelGenParams.h — the bake module shares it.
//  It now reads the world's knobs directly, so callers pass only GenLod + bCoarseFarGen.)

void AVoxelWorld::FillChunkColumn(int32 ccx, int32 ccz, int32 GenLod)
{
	const FIntPoint Key(ccx, ccz);
	if (FilledColumns.Contains(Key))
	{
		return; // already generated
	}

	// Generate this column's voxels (pure), then apply on the spot (synchronous path).
	const FGenParams P = SnapshotGenParams(*this, GenLod, bCoarseFarGen);

	FColumnGenResult R;
	R.Key = Key;
	R.Epoch = GenEpoch;
	R.GenLod = GenLod;
	GenerateColumnWritesPure(ccx, ccz, P, R);
	ApplyColumnResult(R);
}

// Apply a finished column (sync fill OR async harvest): write its voxels into the
// authoritative store, replay the player's saved edits on top (P2), and record the
// column's vertical chunk span + filled state. Game thread only.
void AVoxelWorld::ApplyColumnResult(const FColumnGenResult& R)
{
	using namespace mira;
	if (FilledColumns.Contains(R.Key))
	{
		return; // a duplicate job slipped through — keep the first result
	}

	for (const FColumnGenResult::FWrite& W : R.Writes)
	{
		const Vec3i V(W.X, W.Y, W.Z);
		if (W.bWater) { WorldStore.set_water(V, static_cast<uint8_t>(W.Value)); }
		else          { WorldStore.set_type (V, static_cast<uint8_t>(W.Value)); }
	}

	// P2: replay the player's saved edits for this column on top of generated terrain
	// (load-on-demand from disk), so a previously-dug hole comes back. Game-thread only
	// (touches the edit journal + disk), which is exactly where we are.
	if (bPersistEdits)
	{
		ApplyEditsToColumn(R.Key.X, R.Key.Y);
	}

	const int ChunkYLo = coords::floor_div(R.YLo, coords::CHUNK);
	const int ChunkYHi = coords::floor_div(R.YHi, coords::CHUNK);
	ColumnYRange.Add(R.Key, FIntPoint(ChunkYLo, ChunkYHi));
	FilledColumns.Add(R.Key);
	// Record the gen-LOD this column was filled at, so the approach-invalidation in
	// TickStreaming can re-gen FINER when the player nears (coarse far-gen, flag-gated).
	ColumnGenLod.Add(R.Key, R.GenLod);

	// BUG-1: if this column was ALREADY meshed (its old coarse mesh was KEPT live by the now
	// non-destructive InvalidateColumnFill, and we just overwrote its voxels with finer ones),
	// flag it so the mesh sweep re-meshes IN PLACE — otherwise the sweep would see "still
	// meshed, same LOD, same span" and never show the finer detail. A brand-new column isn't
	// in MeshedColumns, so this is a no-op for the normal first-load path.
	if (MeshedColumns.Contains(R.Key))
	{
		DirtyRemeshColumns.Add(R.Key);
	}

	// RE-ACTIVATE ON STREAM-IN (flag-gated). This column was treated as a SOLID wall
	// by the water sim's SolidFn while it was unloaded, so any pool against the
	// formerly-unloaded edge went dormant. Now that the column is filled, poke awake
	// any water cell sitting on the column's OUTER XZ ring whose neighbour lies in an
	// already-filled column: activate() re-arms it (and its ledger neighbours), so a
	// pool clamped against the old frontier wakes and flows in. We only scan the 1-
	// voxel border ring (the seam), not the whole column, so the cost is O(perimeter).
	if (bEnableWaterSim && WaterSim.IsValid())
	{
		ActivateColumnSeamWater(R.Key, ChunkYLo, ChunkYHi);
	}
}

// ---------------------------------------------------------------------------
// P1: async column generation — launch, harvest, drain.
// ---------------------------------------------------------------------------
void AVoxelWorld::EnqueueColumnGen(const FIntPoint& Col, int32 GenLod)
{
	if (FilledColumns.Contains(Col) || InFlightColumns.Contains(Col))
	{
		return; // already done or in flight
	}
	if (PendingGen.Num() >= MaxColumnJobsInFlight)
	{
		return; // worker pressure cap — try again next tick
	}

	const FGenParams P = SnapshotGenParams(*this, GenLod, bCoarseFarGen);
	const int32 cx = Col.X, cz = Col.Y;
	const uint32 Epoch = GenEpoch;
	const int32 JobGenLod = GenLod;

	// The worker reads only P (a value copy) and *P.Heightmap (immutable until
	// ClearWorld drains us), so there is no shared mutable state and no lock needed.
	TFuture<FColumnGenResult> Fut = Async(EAsyncExecution::ThreadPool, [cx, cz, P, Epoch, JobGenLod]()
	{
		FColumnGenResult R;
		R.Key = FIntPoint(cx, cz);
		R.Epoch = Epoch;
		R.GenLod = JobGenLod;
		GenerateColumnWritesPure(cx, cz, P, R);
		return R;
	});

	PendingGen.Add(FPendingGen{ Col, Epoch, MoveTemp(Fut) });
	InFlightColumns.Add(Col);
}

int32 AVoxelWorld::HarvestColumnGen(int32 Budget)
{
	if (Budget <= 0 || PendingGen.Num() == 0) { return 0; }

	// NEAREST-FIRST harvest (player-centered streaming). Columns are ENQUEUED nearest-first,
	// but a plain back-to-front drain applies the FARTHEST ready jobs first — so when more jobs
	// finish than this tick's budget (the spawn / big-radius case), the columns under the player
	// at the FRONT of the list keep getting deferred ("far loads first, near comes back later /
	// never"). Instead: gather the READY jobs, order them by chebyshev chunk-distance to the
	// TRUE player focus, and apply the nearest `Budget` of them. Re-read every tick, so the
	// priority follows the player as they move. PendingGen is bounded by MaxColumnJobsInFlight,
	// so this little sort is cheap.
	FIntPoint Focus;
	const bool bHaveFocus = GetFocusChunkXZ(Focus);

	TArray<int32> Ready;
	Ready.Reserve(PendingGen.Num());
	for (int32 i = 0; i < PendingGen.Num(); ++i)
	{
		if (PendingGen[i].Future.IsReady()) { Ready.Add(i); }
	}
	if (bHaveFocus)
	{
		Ready.Sort([this, Focus](int32 A, int32 B)
		{
			const FIntPoint& Ka = PendingGen[A].Key;
			const FIntPoint& Kb = PendingGen[B].Key;
			const int32 da = FMath::Max(FMath::Abs(Ka.X - Focus.X), FMath::Abs(Ka.Y - Focus.Y));
			const int32 db = FMath::Max(FMath::Abs(Kb.X - Focus.X), FMath::Abs(Kb.Y - Focus.Y));
			return da < db;
		});
	}

	int32 Applied = 0;
	TArray<int32> ToRemove;
	for (int32 idx : Ready)
	{
		if (Applied >= Budget) { break; }
		FColumnGenResult R = PendingGen[idx].Future.Get();
		InFlightColumns.Remove(PendingGen[idx].Key);
		ToRemove.Add(idx);
		if (R.Epoch == GenEpoch) // drop results from a world that's since been cleared
		{
			ApplyColumnResult(R);
			++Applied;
		}
	}
	// Remove harvested entries high-index-first so each RemoveAt can't shift a not-yet-removed index.
	ToRemove.Sort([](int32 A, int32 B) { return A > B; });
	for (int32 idx : ToRemove) { PendingGen.RemoveAt(idx); }
	return Applied;
}

void AVoxelWorld::DrainColumnGen()
{
	// Block until every worker finishes so none outlives the immutable inputs it
	// captured (the EXR pointer). Results are discarded — the world is being cleared.
	for (FPendingGen& Pending : PendingGen)
	{
		Pending.Future.Wait();
	}
	PendingGen.Empty();
	InFlightColumns.Empty();
}

// ---------------------------------------------------------------------------
// Surface-shell streaming: the chunk-Y span a column SHOULD mesh right now.
// With b3DShellStreaming OFF this ALWAYS returns the full ColumnYRange — so every
// mesh/evict path below behaves byte-for-byte as today. With it ON, a FAR column's
// span is clamped to a thin surface shell (Core/StreamShell.h), and a NEAR column
// keeps full depth. The deep voxels stay generated in WorldStore regardless; this
// only governs how many chunk ROWS get meshed into actors.
// ---------------------------------------------------------------------------
bool AVoxelWorld::DesiredMeshYRange(const FIntPoint& Col, int32 DistChunks, FIntPoint& OutRange) const
{
	const FIntPoint* Range = ColumnYRange.Find(Col);
	if (!Range)
	{
		return false; // not filled yet
	}

	// Flag OFF -> the full generated span, exactly as today (no shell restriction).
	if (!b3DShellStreaming)
	{
		OutRange = *Range;
		return true;
	}

	// Flag ON: sample the surface voxel-Y at the column centre (same generator the fill
	// path uses), then ask StreamShell for the shell-restricted chunk-Y span. The full
	// ColumnYRange supplies the floor (bedrock row) + ceil (top generated row) limits, so
	// a NEAR column resolves back to exactly [floor, surface+up] == its full span.
	mira::HeightmapGenerator Gen;
	ConfigureGenerator(Gen);

	const mira::Vec3i ChunkOrigin = mira::coords::chunk_origin_voxel(mira::Vec3i(Col.X, 0, Col.Y));
	const int CenterX = ChunkOrigin.x + mira::coords::CHUNK / 2;
	const int CenterZ = ChunkOrigin.z + mira::coords::CHUNK / 2;
	const int GroundVy = Gen.compute_ground_y(CenterX, CenterZ);

	const mira::streamshell::ShellRange Sh = mira::streamshell::shell_for_column(
		GroundVy, DistChunks, NearFullDepthRadiusChunks,
		ShellUpChunks, ShellDownChunks,
		/*floor_y_chunk=*/Range->X, /*ceil_y_chunk=*/Range->Y);

	OutRange = FIntPoint(Sh.y_lo_chunk, Sh.y_hi_chunk);
	return true;
}

void AVoxelWorld::MeshChunkColumn(int32 ccx, int32 ccz, int32 Lod, int32 DistChunks)
{
	const FIntPoint Key(ccx, ccz);
	const FIntPoint* Range = ColumnYRange.Find(Key);
	if (!Range)
	{
		return; // not filled yet — caller must FillChunkColumn first
	}

	// Surface-shell streaming: the chunk-Y span to ACTUALLY mesh (flag-off -> full span).
	FIntPoint Span;
	if (!DesiredMeshYRange(Key, DistChunks, Span))
	{
		return;
	}

	// Already meshed at this exact LOD AND this exact span? Nothing to do. (The caller
	// gates re-meshing on a tier change; we ALSO re-mesh when the shell span changed —
	// deeper-on-approach grows it, retreat shrinks it.) Meshing re-renders the span.
	if (MeshedColumns.Contains(Key))
	{
		const int32* Cur = ColumnLod.Find(Key);
		const FIntPoint* CurSpan = ColumnMeshedYRange.Find(Key);
		// BUG-1: a column flagged DirtyRemeshColumns had its voxels overwritten by a finer
		// re-gen while keeping its old mesh — it MUST re-mesh even though LOD + span are
		// unchanged, so skip the no-op early-out for it (the caller clears the flag after).
		if (Cur && *Cur == Lod && CurSpan && *CurSpan == Span && !DirtyRemeshColumns.Contains(Key))
		{
			return;
		}
		// The span may have SHRUNK (column retreated): destroy any rows that were meshed
		// before but fall outside the new span, so the shell doesn't leak deep actors.
		// MESH-THEN-SWAP (Bug-2): a swap-HOLD owns the old actors (already detached) and
		// destroys them at hold-completion, so DEFER the out-of-span destroy when holding.
		if (CurSpan && !IsColumnSwapHolding(Key))
		{
			for (int32 ccy = CurSpan->X; ccy <= CurSpan->Y; ++ccy)
			{
				if (ccy < Span.X || ccy > Span.Y)
				{
					DestroyChunkActor(FIntVector(ccx, ccy, ccz));
				}
			}
		}
	}
	for (int32 ccy = Span.X; ccy <= Span.Y; ++ccy)
	{
		RemeshChunk(FIntVector(ccx, ccy, ccz), Lod);
	}
	MeshedColumns.Add(Key);
	ColumnLod.Add(Key, Lod);
	ColumnMeshedYRange.Add(Key, Span);
}

void AVoxelWorld::UnmeshChunkColumn(int32 ccx, int32 ccz)
{
	const FIntPoint Key(ccx, ccz);
	if (!MeshedColumns.Contains(Key))
	{
		// Even if the column isn't (still) in MeshedColumns, it may have a lingering
		// cross-fade record (edge case): clean its Outgoing actors so none leak. No-op
		// when the flag is off (ActiveFades is empty).
		CancelColumnFade(Key);
		return;
	}
	// Edge case (a): a column EVICTED mid-fade. CancelColumnFade destroys this column's
	// OUTGOING (fading-out) actors and drops the record + any deferred LOD; the loop below
	// destroys the column's PRIMARY (incoming/normal) actors. Together both are freed with
	// no double-free (they're disjoint sets — Outgoing was detached from ChunkActors when
	// the fade began). No-op when the flag is off.
	CancelColumnFade(Key);
	// Destroy across the FULL generated span (a safe superset of whatever shell span was
	// meshed) so no actor leaks regardless of the shell restriction. DestroyChunkActor is
	// idempotent on a chunk that has no actor.
	const FIntPoint* Range = ColumnYRange.Find(Key);
	if (Range)
	{
		for (int32 ccy = Range->X; ccy <= Range->Y; ++ccy)
		{
			DestroyChunkActor(FIntVector(ccx, ccy, ccz));
		}
	}
	MeshedColumns.Remove(Key);
	ColumnLod.Remove(Key);
	ColumnMeshedYRange.Remove(Key);

	// Cancel any in-flight async-mesh job for this column so a late harvest doesn't
	// re-create the actors we just evicted. (The worker holds slab COPIES, so dropping
	// the future is safe — it finishes and its result is discarded.)
	InFlightMeshColumns.Remove(Key);
	PendingMesh.RemoveAll([&Key](const FPendingMesh& P) { return P.Key == Key; });
}

// ===========================================================================
// Async meshing — the sibling of async generation for the heavy greedy-mesh step.
// Game thread: extract each chunk's slab (a cheap brick copy) and hand the column to
// a worker. Worker: greedy-mesh (+ LOD downsample) every chunk into MeshBuffers.
// Game thread: upload finished buffers, budgeted per frame. The worker reads ONLY the
// copied slabs, so it never races the brickmap. Edits stay synchronous (RemeshChunk).
// ===========================================================================

// One chunk's finished mesh (worker output).
struct FMiraChunkMeshOut
{
	FIntVector Coord = FIntVector::ZeroValue;
	bool   bHasContent = false;
	int32  Lod = 0;
	float  PositionScale = 1.0f;
	mira::MeshBuffers Mb;
};
// A whole column's mesh result — the TSharedPtr payload the future returns.
struct FMiraColumnMeshResult
{
	FIntPoint Key = FIntPoint(0, 0);
	int32  Lod = 0;
	uint32 Epoch = 0;
	TArray<FMiraChunkMeshOut> Chunks;
};

namespace
{
	// PURE worker: build every chunk's mesh from the column's extracted fine slabs.
	// Mirrors AVoxelWorld::RemeshChunk's LOD0 / downsample logic, off the game thread.
	TSharedPtr<FMiraColumnMeshResult> MeshColumnPure(
		FIntPoint Key, int32 Lod, uint32 Epoch,
		TArray<TPair<FIntVector, mira::DenseGrid>> Slabs)
	{
		using namespace mira;
		TSharedPtr<FMiraColumnMeshResult> R = MakeShared<FMiraColumnMeshResult>();
		R->Key = Key; R->Lod = Lod; R->Epoch = Epoch;

		for (TPair<FIntVector, DenseGrid>& Pair : Slabs)
		{
			FMiraChunkMeshOut Out;
			Out.Coord = Pair.Key;
			Out.Lod = Lod;
			const DenseGrid& Slab = Pair.Value;

			// Inner (non-apron) content check — empty chunks become "destroy the actor".
			bool bContent = false;
			for (int z = APRON; z < APRON + coords::CHUNK && !bContent; ++z)
			for (int y = APRON; y < APRON + coords::CHUNK && !bContent; ++y)
			for (int x = APRON; x < APRON + coords::CHUNK && !bContent; ++x)
			{
				if (Slab.type_at(x, y, z) != mat::AIR || Slab.water_at(x, y, z) != 0)
				{
					bContent = true;
				}
			}
			Out.bHasContent = bContent;
			if (!bContent) { R->Chunks.Add(MoveTemp(Out)); continue; }

			if (Lod <= 0)
			{
				Out.Mb = AVoxelChunkActor::BuildMeshBuffers(Slab, /*bSolidsOnly=*/false);
				Out.PositionScale = 1.0f;
			}
			else
			{
				// Downsample the inner 32^3 into a coarse grid, mesh that (solids only).
				DenseGrid Fine(coords::CHUNK);
				for (int z = 0; z < coords::CHUNK; ++z)
				for (int y = 0; y < coords::CHUNK; ++y)
				for (int x = 0; x < coords::CHUNK; ++x)
				{
					Fine.set_type(x, y, z, Slab.type_at(x + APRON, y + APRON, z + APRON));
				}
				const DenseGrid Coarse = lod::downsample_to_lod(Fine, Lod);
				if (Coarse.side <= 0)
				{
					Out.Mb = AVoxelChunkActor::BuildMeshBuffers(Slab, false); // defensive full-detail
					Out.PositionScale = 1.0f;
					Out.Lod = 0;
				}
				else
				{
					DenseGrid CoarseSlab = make_mesh_slab();
					for (int z = 0; z < Coarse.side; ++z)
					for (int y = 0; y < Coarse.side; ++y)
					for (int x = 0; x < Coarse.side; ++x)
					{
						CoarseSlab.set_type(x + APRON, y + APRON, z + APRON, Coarse.type_at(x, y, z));
					}
					Out.Mb = AVoxelChunkActor::BuildMeshBuffers(CoarseSlab, /*bSolidsOnly=*/true);
					Out.PositionScale = static_cast<float>(1 << Lod);
				}
			}
			// Cull chunks with NO visible faces (fully-interior underground / all-air
			// after downsample): no actor, no draw call. This is the big "no underground
			// unless you dig" + draw-call win. Safe because a later carve re-meshes the
			// chunk via the apron-aware affected_chunks, so the face appears when exposed.
			if (Out.Mb.total_quads() == 0)
			{
				Out.bHasContent = false;
			}
			R->Chunks.Add(MoveTemp(Out));
		}
		return R;
	}
} // namespace

// ===========================================================================
// Super-chunk aggregation (far-band clipmap LOD) — flag-gated bEnableSuperChunks.
//
// A super-chunk covers an N×N×N block of chunks (N*32 fine voxels per axis). We
// render the FAR band (beyond the per-chunk StreamRadius) as ONE coarse mesh per
// super-chunk so terrain reaches ~1.5 km without N^3 draw calls. OPTION B: the
// coarse cells are sampled straight from the heightmap (compute_ground_y), NOT from
// a brick fill — so the worker is PURE (carries only an FGenParams snapshot + the
// immutable EXR pointer, exactly like the column-gen worker) and the brickmap is
// never touched. The coarse grid side is <= CHUNK (32), so the existing 34^3
// mesh-slab + greedy-mesher renders it unchanged. The math is harness-locked
// (Core/SuperChunk.h). All of this is dead code when bEnableSuperChunks is false.
// ===========================================================================
struct FMiraSuperMeshResult
{
	FIntVector Key = FIntVector::ZeroValue;
	int32  SuperLod = 0;
	int32  Stride = 1;
	uint32 Epoch = 0;
	bool   bHasContent = false;
	mira::MeshBuffers Mb;
};

namespace
{
	// PURE worker: sample the heightmap into a coarse slab for one super-chunk and
	// greedy-mesh it (solids only). N = super edge in chunks, L = super-LOD, Stride =
	// fine voxels per coarse cell. Reads only the FGenParams snapshot (+ immutable EXR),
	// so it's safe on a thread-pool worker and never races the brickmap.
	TSharedPtr<FMiraSuperMeshResult> MeshSuperPure(
		FIntVector Super, int N, int L, int Stride, uint32 Epoch, FGenParams P)
	{
		using namespace mira;
		TSharedPtr<FMiraSuperMeshResult> R = MakeShared<FMiraSuperMeshResult>();
		R->Key = Super; R->SuperLod = L; R->Stride = Stride; R->Epoch = Epoch;

		HeightmapGenerator Gen;
		BuildGen(P, Gen);

		const int cs = superchunk::coarse_side(N, L); // coarse grid side (<= 32)
		// Origin of this super-chunk in FINE voxels (the min corner).
		const Vec3i superOriginChunk = superchunk::super_origin_chunk(
			Vec3i(Super.X, Super.Y, Super.Z), N);
		const Vec3i superOriginVoxel(superOriginChunk.x * coords::CHUNK,
		                             superOriginChunk.y * coords::CHUNK,
		                             superOriginChunk.z * coords::CHUNK);

		// Fill an apron'd mesh slab: the inner [APRON .. APRON+cs) cube holds the coarse
		// cells; the 1-cell apron shell stays air (the far band has no neighbour data to
		// stitch against, and a coarse super-chunk seam is below the noise floor at range).
		DenseGrid CoarseSlab = make_mesh_slab(); // 34^3, all AIR
		for (int cz = 0; cz < cs; ++cz)
		for (int cx = 0; cx < cs; ++cx)
		{
			// Sample the surface at the CENTRE of this coarse column's footprint.
			const int worldX = superOriginVoxel.x + cx * Stride + Stride / 2;
			const int worldZ = superOriginVoxel.z + cz * Stride + Stride / 2;
			const int ground_y = Gen.compute_ground_y(worldX, worldZ);
			const uint8 top_id = static_cast<uint8>(Gen.resolve_column(worldX, worldZ).top_id);

			for (int cy = 0; cy < cs; ++cy)
			{
				// A coarse cell is solid if its BOTTOM fine-Y is at/below the surface.
				const int cellBottomFineY = superOriginVoxel.y + cy * Stride;
				if (cellBottomFineY <= ground_y)
				{
					CoarseSlab.set_type(cx + APRON, cy + APRON, cz + APRON, top_id);
				}
			}
		}

		R->Mb = AVoxelChunkActor::BuildMeshBuffers(CoarseSlab, /*bSolidsOnly=*/true);
		R->bHasContent = (R->Mb.total_quads() > 0);
		return R;
	}
} // namespace

void AVoxelWorld::EnqueueColumnMesh(const FIntPoint& Col, int32 Lod, int32 DistChunks)
{
	using namespace mira;
	if (!ColumnYRange.Find(Col)) { return; }           // not filled yet
	if (InFlightMeshColumns.Contains(Col)) { return; } // already meshing
	// IN-FLIGHT CAP (mirrors EnqueueColumnGen @~418 and EnqueueSuperMesh): the mesh ENQUEUE side
	// had NO ceiling while uploads drain at only MaxColumnMeshUploadsPerTick/tick, so the backlog
	// avalanched to 15k+ jobs and only a trickle ever became actors -> "swiss cheese". Bounding the
	// in-flight mesh set keeps the budgeted nearest-first sweep walking outward so every column
	// meshes COMPLETELY (the small backlog drains in ~2 ticks). Just try again next tick.
	if (PendingMesh.Num() >= MaxColumnJobsInFlight) { return; }

	// Surface-shell streaming: the chunk-Y span to ACTUALLY mesh (flag-off -> full span).
	FIntPoint Span;
	if (!DesiredMeshYRange(Col, DistChunks, Span)) { return; }

	// If this column was meshed before over a WIDER span (it retreated -> shell shrank),
	// destroy the rows that fall outside the new span now — the worker job below won't
	// touch them (we only extract slabs for the new span), so they'd otherwise leak.
	// MESH-THEN-SWAP (Bug-2): when a swap-HOLD is active for this column the old actors are
	// already detached into the hold record (NOT in ChunkActors), and the hold owns their
	// teardown at completion — so we DEFER the out-of-span destroy to hold-completion and
	// skip it here (DestroyChunkActor would be a no-op on the held rows anyway, but skipping
	// keeps the hold the single owner of the old mesh's lifetime).
	if (!IsColumnSwapHolding(Col))
	{
		if (const FIntPoint* CurSpan = ColumnMeshedYRange.Find(Col))
		{
			for (int32 ccy = CurSpan->X; ccy <= CurSpan->Y; ++ccy)
			{
				if (ccy < Span.X || ccy > Span.Y)
				{
					DestroyChunkActor(FIntVector(Col.X, ccy, Col.Y));
				}
			}
		}
	}

	// Extract each chunk's slab on the game thread (safe brickmap read) into the job.
	TArray<TPair<FIntVector, DenseGrid>> Slabs;
	Slabs.Reserve(Span.Y - Span.X + 1);
	for (int32 ccy = Span.X; ccy <= Span.Y; ++ccy)
	{
		const FIntVector Coord(Col.X, ccy, Col.Y);
		DenseGrid Slab = extract_mesh_slab(WorldStore, Vec3i(Coord.X, Coord.Y, Coord.Z));
		Slabs.Add(TPair<FIntVector, DenseGrid>(Coord, MoveTemp(Slab)));
	}

	const int32 ClampedLod = FMath::Clamp(Lod, 0, lodtier::MAX_LOD);
	const uint32 Epoch = GenEpoch;
	const FIntPoint Key = Col;
	FPendingMesh P;
	P.Key = Key;
	P.Epoch = Epoch;
	P.Span = Span;
	P.Future = Async(EAsyncExecution::ThreadPool,
		[Key, ClampedLod, Epoch, Slabs = MoveTemp(Slabs)]() mutable
		{
			return MeshColumnPure(Key, ClampedLod, Epoch, MoveTemp(Slabs));
		});
	PendingMesh.Add(MoveTemp(P));
	InFlightMeshColumns.Add(Col);
}

int32 AVoxelWorld::HarvestColumnMesh(int32 Budget)
{
	// THROUGHPUT time-slice (optional): bound the per-tick UPLOAD to a wall-clock ms budget
	// so a sudden burst of ready meshes can't blow a single frame. The COUNT cap (Budget) is
	// still the hard ceiling; this just stops early once MeshUploadBudgetMs has elapsed. With
	// bTimeSliceMeshUploads off, only the count cap applies (original fixed-count behaviour).
	const bool bSlice = bTimeSliceMeshUploads;
	const double SliceStart = bSlice ? FPlatformTime::Seconds() : 0.0;
	const double SliceLimitS = (double)MeshUploadBudgetMs * 0.001;

	// NEAREST-FIRST harvest (player-centered streaming). Same fix as HarvestColumnGen: the mesh
	// UPLOAD is the real FPS cost, so when more meshes finish than this tick's upload budget, a
	// back-to-front drain would push the farthest meshes to screen first and starve the ground
	// under the player. Order the READY meshes by chebyshev chunk-distance to the TRUE focus and
	// upload the nearest `Budget` first. Re-read each tick → priority tracks the moving player.
	FIntPoint Focus;
	const bool bHaveFocus = GetFocusChunkXZ(Focus);
	TArray<int32> Ready;
	Ready.Reserve(PendingMesh.Num());
	for (int32 i = 0; i < PendingMesh.Num(); ++i)
	{
		if (PendingMesh[i].Future.IsReady()) { Ready.Add(i); }
	}
	if (bHaveFocus)
	{
		Ready.Sort([this, Focus](int32 A, int32 B)
		{
			const FIntPoint& Ka = PendingMesh[A].Key;
			const FIntPoint& Kb = PendingMesh[B].Key;
			const int32 da = FMath::Max(FMath::Abs(Ka.X - Focus.X), FMath::Abs(Ka.Y - Focus.Y));
			const int32 db = FMath::Max(FMath::Abs(Kb.X - Focus.X), FMath::Abs(Kb.Y - Focus.Y));
			return da < db;
		});
	}

	int32 Applied = 0;
	TArray<int32> ToRemove;
	for (int32 idx : Ready)
	{
		if (Applied >= Budget) { break; }
		// Stop early if this tick's upload ms budget is spent (only after >=1 upload, so we
		// always make forward progress even if a single upload exceeds the slice).
		if (bSlice && Applied > 0 && (FPlatformTime::Seconds() - SliceStart) >= SliceLimitS)
		{
			break;
		}
		TSharedPtr<FMiraColumnMeshResult> R = PendingMesh[idx].Future.Get();
		const uint32 JobEpoch = PendingMesh[idx].Epoch;
		const FIntPoint Key = PendingMesh[idx].Key;
		const FIntPoint JobSpan = PendingMesh[idx].Span; // shell span this job covered
		ToRemove.Add(idx);
		InFlightMeshColumns.Remove(Key);

		if (!R.IsValid() || JobEpoch != GenEpoch) { continue; } // stale (world cleared/evicted)

		for (FMiraChunkMeshOut& Out : R->Chunks)
		{
			if (!Out.bHasContent)
			{
				DestroyChunkActor(Out.Coord);
				continue;
			}
			AVoxelChunkActor* Actor = EnsureChunkActor(Out.Coord);
			if (!Actor) { continue; }
			const int32 LodScale = (Out.Lod <= 0) ? 1 : (1 << Out.Lod);
			Actor->SetActorLocation(ChunkActorLocation(Out.Coord, LodScale));
			// DIAGNOSTIC (TOOL 1): if mira.LodDebug is on, color this chunk by its LOD; else null
			// (normal material color). Render override only — Out.Mb is untouched.
			FColor DbgCol;
			const bool bDbg = GetLodDebugColor(Out.Lod, /*bSuper=*/false, DbgCol);
			Actor->UploadMeshBuffers(Out.Mb, TerrainMaterial, WaterMaterial, FloraMaterial,
				/*bCollision=*/(Out.Lod <= 0) ? bCreateCollision : false,
				/*bReverse=*/false, Out.PositionScale, bDbg ? &DbgCol : nullptr);
		}
		MeshedColumns.Add(R->Key);
		ColumnLod.Add(R->Key, R->Lod);
		ColumnMeshedYRange.Add(R->Key, JobSpan); // record the shell span (deeper-on-approach tracking)
		++Applied;
	}
	// Remove harvested entries high-index-first so each RemoveAt can't shift a not-yet-removed
	// index (we switched from RemoveAtSwap to a batched RemoveAt to keep the nearest-first order
	// intact for entries left in flight this tick).
	ToRemove.Sort([](int32 A, int32 B) { return A > B; });
	for (int32 idx : ToRemove) { PendingMesh.RemoveAt(idx); }
	return Applied;
}

void AVoxelWorld::DrainColumnMesh()
{
	for (FPendingMesh& P : PendingMesh)
	{
		if (P.Future.IsValid()) { P.Future.Wait(); }
	}
	PendingMesh.Reset();
	InFlightMeshColumns.Reset();
}

// ===========================================================================
// Super-chunk aggregation — enqueue / harvest / drain / placement (flag-gated).
// Mirrors the async column-mesh path one-for-one (a super-chunk is just a wider,
// heightmap-sampled coarse mesh). No-ops when bEnableSuperChunks is off because the
// caller (TickStreaming) only ever invokes these inside the flag guard.
// ===========================================================================
void AVoxelWorld::EnqueueSuperMesh(const FIntVector& Super, int32 SuperLodLevel)
{
	if (InFlightSuperMeshes.Contains(Super)) { return; }       // already meshing
	if (PendingSuperMesh.Num() >= MaxSuperMeshJobsInFlight) { return; } // worker cap

	const int32 N = SuperChunkSizeChunks;
	const int32 L = SuperLodLevel;
	const int32 Stride = mira::superchunk::stride_for_lod(N, L);

	// Super-chunks always sample at their own super-LOD stride (not the column gen LOD),
	// so they pass GenLod 0 / coarse-gen off — this snapshot only feeds BuildGen here.
	const FGenParams P = SnapshotGenParams(*this, /*GenLod=*/0, /*bCoarseFarGen=*/false);
	const uint32 Epoch = GenEpoch;
	const FIntVector Key = Super;

	// The worker reads only P (a value copy) + *P.Heightmap (immutable until ClearWorld
	// drains us), so there's no shared mutable state and no lock needed.
	FPendingSuperMesh Job;
	Job.Key = Key;
	Job.Epoch = Epoch;
	Job.Future = Async(EAsyncExecution::ThreadPool, [Key, N, L, Stride, Epoch, P]()
	{
		return MeshSuperPure(Key, N, L, Stride, Epoch, P);
	});
	PendingSuperMesh.Add(MoveTemp(Job));
	InFlightSuperMeshes.Add(Super);
}

int32 AVoxelWorld::HarvestSuperMesh(int32 Budget)
{
	int32 Applied = 0;
	for (int32 i = PendingSuperMesh.Num() - 1; i >= 0 && Applied < Budget; --i)
	{
		if (!PendingSuperMesh[i].Future.IsReady()) { continue; }
		TSharedPtr<FMiraSuperMeshResult> R = PendingSuperMesh[i].Future.Get();
		const uint32 JobEpoch = PendingSuperMesh[i].Epoch;
		const FIntVector Key = PendingSuperMesh[i].Key;
		PendingSuperMesh.RemoveAtSwap(i);
		InFlightSuperMeshes.Remove(Key);

		if (!R.IsValid() || JobEpoch != GenEpoch) { continue; } // stale (world cleared/evicted)

		if (!R->bHasContent)
		{
			// All air at this super-chunk (e.g. above the surface) — no actor.
			DestroySuperActor(Key);
			MeshedSupers.Add(Key);          // record it so we don't re-enqueue forever
			SuperLod.Add(Key, R->SuperLod);
			++Applied;
			continue;
		}

		AVoxelChunkActor* Actor = EnsureSuperActor(Key);
		if (!Actor) { continue; }
		Actor->SetActorLocation(SuperChunkActorLocation(Key, R->Stride));
		// DIAGNOSTIC (TOOL 1): color a super-chunk by its super-LOD (cool/blue ramp) only when
		// mira.LodDebug == 2; else null (normal color). Render override only — R->Mb untouched.
		FColor DbgCol;
		const bool bDbg = GetLodDebugColor(R->SuperLod, /*bSuper=*/true, DbgCol);
		// Coarse mesh: positions are in coarse cells, so scale by Stride fine voxels.
		// No collision (far band), no reverse winding.
		Actor->UploadMeshBuffers(R->Mb, TerrainMaterial, WaterMaterial, FloraMaterial,
			/*bCollision=*/false, /*bReverse=*/false,
			/*PositionScale=*/static_cast<float>(R->Stride), bDbg ? &DbgCol : nullptr);
		MeshedSupers.Add(Key);
		SuperLod.Add(Key, R->SuperLod);
		++Applied;
	}
	return Applied;
}

void AVoxelWorld::DrainSuperMesh()
{
	for (FPendingSuperMesh& P : PendingSuperMesh)
	{
		if (P.Future.IsValid()) { P.Future.Wait(); }
	}
	PendingSuperMesh.Reset();
	InFlightSuperMeshes.Reset();
}

// Desired super-LOD (0..5) for a super-chunk at chunk distance DistChunks from the
// focus. Reuses the harness-locked LodTier hysteresis rule with a config built from
// the Super0..5MaxChunks knobs.
//
// The L0-L2 thresholds (Super0/1/2MaxChunks) are UNCHANGED from the original near-super
// build, so near super-chunks pick exactly the same band they did before. L3/L4/L5 ADD
// the far-horizon bands (coarse side 4/2/1 for N=8) the larger SuperRadius reaches:
//   <=Super0Max -> L0 .. <=Super4Max -> L4, beyond -> L5 (== MAX_LOD).
// Returns 0 when the feature is off.
int32 AVoxelWorld::DesiredSuperLod(int32 DistChunks, int32 CurrentLod) const
{
	if (!bEnableSuperChunks)
	{
		return 0;
	}
	mira::lodtier::LodTierConfig Cfg;
	Cfg.t0_max = Super0MaxChunks; // L0 outer edge (near-super, original behavior)
	Cfg.t1_max = Super1MaxChunks; // L1 outer edge (near-super, original behavior)
	Cfg.t2_max = Super2MaxChunks; // L2 outer edge (near-super, original behavior)
	Cfg.t3_max = Super3MaxChunks; // L3 outer edge (FAR horizon extension)
	Cfg.t4_max = Super4MaxChunks; // L4 outer edge; beyond -> L5 (== lodtier::MAX_LOD)
	// margin=2 matches the original near-super hysteresis (steady bands at boundaries).
	const int32 Raw = mira::lodtier::lod_for_distance_hys(DistChunks, CurrentLod, Cfg, /*margin=*/2);
	// Clamp to the valid super-LOD range [0..MAX_LOD]. This range is N-INDEPENDENT:
	// coarse_side(N, L) for L=0..5 is 32/16/8/4/2/1 at N=8 and at N=16 (both stay >=1
	// and <= CHUNK), so every level here meshes through the existing 34^3 slab path for
	// either super-chunk size. (Distance bands are also N-independent — they're chunk
	// distances, not voxel sizes — so this picker needs no change when N flips to 16.)
	return FMath::Clamp(Raw, 0, mira::lodtier::MAX_LOD);
}

// UE world location for a super-chunk's renderer actor. The coarse slab's cell (0,0,0)
// is fine voxel (super_origin - APRON*Stride); map that to UE via PositionToUE:
// (vx,vy,vz) -> (vx, vz, vy)*10. The +APRON shift the mesher bakes in (scaled by
// Stride, since a coarse cell is Stride fine voxels wide) is cancelled here so the
// super mesh lands on the same world grid as the per-chunk terrain.
FVector AVoxelWorld::SuperChunkActorLocation(const FIntVector& Super, int32 Stride) const
{
	const int32 N = SuperChunkSizeChunks;
	const mira::Vec3i originChunk = mira::superchunk::super_origin_chunk(
		mira::Vec3i(Super.X, Super.Y, Super.Z), N);
	const int32 A  = mira::APRON * FMath::Max(1, Stride);
	const int32 Ox = originChunk.x * mira::coords::CHUNK - A;
	const int32 Oy = originChunk.y * mira::coords::CHUNK - A;
	const int32 Oz = originChunk.z * mira::coords::CHUNK - A;
	const float U  = 10.0f; // 1 voxel = 10 UE units (10 cm)
	return GetActorLocation() + FVector(Ox * U, Oz * U, Oy * U);
}

AVoxelChunkActor* AVoxelWorld::EnsureSuperActor(const FIntVector& Super)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = SuperActors.Find(Super))
	{
		return *Found;
	}

	UWorld* W = GetWorld();
	if (!W)
	{
		return nullptr;
	}

	const FTransform Xform(SuperChunkActorLocation(Super, 1));
	AVoxelChunkActor* Actor = W->SpawnActorDeferred<AVoxelChunkActor>(
		AVoxelChunkActor::StaticClass(), Xform, this);
	if (!Actor)
	{
		return nullptr;
	}
	Actor->bWorldManaged = true;       // suppress the standalone self-build
	Actor->FinishSpawning(Xform);
#if WITH_EDITOR
	Actor->SetActorLabel(FString::Printf(TEXT("Super_%d_%d_%d"),
		Super.X, Super.Y, Super.Z));
#endif
	SuperActors.Add(Super, Actor);
	return Actor;
}

void AVoxelWorld::DestroySuperActor(const FIntVector& Super)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = SuperActors.Find(Super))
	{
		if (AVoxelChunkActor* Actor = *Found)
		{
			Actor->Destroy();
		}
		SuperActors.Remove(Super);
	}
}

void AVoxelWorld::UnmeshSuper(const FIntVector& Super)
{
	DestroySuperActor(Super);
	MeshedSupers.Remove(Super);
	SuperLod.Remove(Super);
	// Cancel any in-flight job so a late harvest doesn't re-create the actor.
	InFlightSuperMeshes.Remove(Super);
	PendingSuperMesh.RemoveAll([&Super](const FPendingSuperMesh& P) { return P.Key == Super; });
}

// ---------------------------------------------------------------------------
// Streaming (M4): page columns in/out around the focus, throttled per tick.
// ---------------------------------------------------------------------------
bool AVoxelWorld::GetFocusChunkXZ(FIntPoint& OutColumn) const
{
	FVector FocusWorld;
	if (StreamFocusActor)
	{
		FocusWorld = StreamFocusActor->GetActorLocation();
	}
	else if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		FocusWorld = Pawn->GetActorLocation();
	}
	else
	{
		return false; // no focus available yet
	}

	// UE world (cm) -> core voxel XZ. PositionToUE maps core (vx,vy,vz) ->
	// (vx, vz, vy)*10, so UE.X = core-x*10 and UE.Y = core-z*10.
	const FVector Local = FocusWorld - GetActorLocation();
	const int vx = FMath::FloorToInt(Local.X / 10.0f);
	const int vz = FMath::FloorToInt(Local.Y / 10.0f);
	OutColumn = FIntPoint(mira::coords::floor_div(vx, mira::coords::CHUNK),
	                      mira::coords::floor_div(vz, mira::coords::CHUNK));
	return true;
}

// Refresh FocusForwardXZ — the focus's VIEW forward direction projected onto the
// voxel-horizontal plane, in CORE (x,z) axes — for view-prioritized streaming.
//
// AXIS MAPPING (the load-bearing part). The mesher's PositionToUE maps core voxel
// (vx,vy,vz) -> UE (vx, vz, vy)*10, so:
//     UE.X  <->  core x   (a voxel-horizontal axis)
//     UE.Y  <->  core z   (the OTHER voxel-horizontal axis)
//     UE.Z  <->  core y   (HEIGHT — vertical, NOT part of the streaming plane)
// The streaming ring's chunk deltas are (dChunkX, dChunkZ) in CORE x/z, exactly the
// plane (UE.X, UE.Y). So we take the camera/control FORWARD vector, drop its UE.Z
// (height) component, and map (Fwd.X, Fwd.Y) straight to core (fwd_x, fwd_z). This is
// the SAME mapping GetFocusChunkXZ uses for position (UE.X->vx, UE.Y->vz), so the bias
// points where the player actually looks on the ground plane — not sideways.
//
// SOURCE PREFERENCE: a controlled pawn's CONTROL rotation (where the player is aiming
// the camera) is the truest "view", so we read that first; if the focus has no
// controller we fall back to the player camera manager's camera rotation; if neither
// exists (e.g. a bare StreamFocusActor with no controller/camera) we leave the forward
// ZERO, and view_priority_key degrades to pure distance order (today's behaviour).
void AVoxelWorld::UpdateFocusForwardXZ()
{
	FocusForwardXZ = FVector2D::ZeroVector; // default: no view -> pure-distance fallback

	// Resolve the focus actor (explicit override, else the first player pawn) — the
	// same resolution GetFocusChunkXZ uses, so the view matches the streaming centre.
	AActor* Focus = StreamFocusActor;
	if (!Focus)
	{
		Focus = UGameplayStatics::GetPlayerPawn(this, 0);
	}
	if (!Focus)
	{
		return; // no focus yet
	}

	// Prefer the controller's control rotation (the player's aim/look direction).
	FRotator ViewRot;
	bool bHaveView = false;
	if (const APawn* FocusPawn = Cast<APawn>(Focus))
	{
		if (const AController* Ctrl = FocusPawn->GetController())
		{
			ViewRot = Ctrl->GetControlRotation();
			bHaveView = true;
			// If this controller has a camera manager, its camera rotation is the most
			// accurate on-screen view (control rotation == camera for most pawns, but
			// this honours camera lag / custom view targets when present).
			if (const APlayerController* PC = Cast<APlayerController>(Ctrl))
			{
				if (PC->PlayerCameraManager)
				{
					ViewRot = PC->PlayerCameraManager->GetCameraRotation();
				}
			}
		}
	}
	if (!bHaveView)
	{
		// No controller on the focus -> no view direction available. Leave forward zero;
		// the streamer degrades to today's pure nearest-first order for this focus.
		return;
	}

	// Forward unit vector in UE world axes, then project to the voxel-horizontal plane:
	// drop UE.Z (height = core y) and map (UE.X, UE.Y) -> core (x, z). Normalise the 2D
	// projection so a steep look-up/down (small horizontal component) still yields a
	// stable heading; if the player looks DEAD vertical the projection is ~zero and we
	// leave forward zero (degrade to distance order) rather than bias a random way.
	const FVector Fwd = ViewRot.Vector();        // UE forward unit vector
	FVector2D PlaneFwd(Fwd.X, Fwd.Y);            // (core x, core z) — height (UE.Z) dropped
	if (PlaneFwd.IsNearlyZero())
	{
		return; // looking straight up/down: no horizontal heading -> pure distance order
	}
	PlaneFwd.Normalize();
	FocusForwardXZ = PlaneFwd; // cached for this tick's fill + mesh ordering
}

// Focus shifted along the focus's velocity by PrefetchLeadChunks, so the fill ring
// leads a moving player and generation keeps up with fast traversal (P1 prefetch).
bool AVoxelWorld::GetPrefetchFocusChunkXZ(FIntPoint& OutColumn) const
{
	FIntPoint Base;
	if (!GetFocusChunkXZ(Base))
	{
		return false;
	}
	if (PrefetchLeadChunks <= 0)
	{
		OutColumn = Base;
		return true;
	}

	// Velocity of whatever we're following (cm/s, UE axes).
	FVector Vel = FVector::ZeroVector;
	if (StreamFocusActor)
	{
		Vel = StreamFocusActor->GetVelocity();
	}
	else if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		Vel = Pawn->GetVelocity();
	}

	// UE.X -> voxel x, UE.Y -> voxel z (same mapping as GetFocusChunkXZ). Lead the
	// ring by PrefetchLeadChunks chunks in the normalised horizontal heading.
	FVector2D Heading(Vel.X, Vel.Y);
	if (Heading.IsNearlyZero())
	{
		OutColumn = Base; // standing still -> no lead
		return true;
	}
	Heading.Normalize();
	OutColumn = FIntPoint(
		Base.X + FMath::RoundToInt(Heading.X * PrefetchLeadChunks),
		Base.Y + FMath::RoundToInt(Heading.Y * PrefetchLeadChunks));
	return true;
}

// Desired LOD for a column at chunk distance Dist from the focus (P3). 0 when LOD
// is off, else the harness-locked LodTier threshold rule.
int32 AVoxelWorld::DesiredColumnLod(int32 DistChunks, int32 CurrentLod) const
{
	if (!bEnableLOD)
	{
		return 0;
	}
	mira::lodtier::LodTierConfig Cfg;
	Cfg.t0_max = Lod0MaxChunks;
	Cfg.t1_max = Lod1MaxChunks;
	Cfg.t2_max = Lod2MaxChunks;
	Cfg.t3_max = Lod3MaxChunks;
	Cfg.t4_max = Lod4MaxChunks;
	// Hysteresis margin of 2 chunks: a column must move 2 chunks PAST a tier boundary
	// before it changes LOD, so jitter at the edge doesn't thrash the mesher.
	return mira::lodtier::lod_for_distance_hys(DistChunks, CurrentLod, Cfg, /*margin=*/2);
}

// Desired GENERATION LOD for a column at chunk distance DistChunks from the TRUE
// focus (coarse far-generation, flag-gated bCoarseFarGen). Returns 0 unless BOTH
// bEnableLOD and bCoarseFarGen are on; then it's the PLAIN (no-hysteresis)
// lod_for_distance over the SAME tier thresholds DesiredColumnLod uses.
//
// WHY PLAIN (no hysteresis) + TRUE focus: we want the FINEST LOD this column will
// ever render at while it sits at this distance. Generating no coarser than the
// finest render LOD guarantees gen is never coarser than render -> the downsample
// always has the detail it needs and there are no LOD cracks. Hysteresis or the
// prefetch-led FillFocus could make gen momentarily coarser than render, so we
// deliberately avoid both here.
int32 AVoxelWorld::GenLodForDistance(int32 DistChunks) const
{
	if (!(bEnableLOD && bCoarseFarGen))
	{
		return 0;
	}
	mira::lodtier::LodTierConfig Cfg;
	Cfg.t0_max = Lod0MaxChunks;
	Cfg.t1_max = Lod1MaxChunks;
	Cfg.t2_max = Lod2MaxChunks;
	Cfg.t3_max = Lod3MaxChunks;
	Cfg.t4_max = Lod4MaxChunks;
	return mira::lodtier::lod_for_distance(DistChunks, Cfg);
}

// Invalidate a column's generated voxels so a later fill re-generates it (used by
// coarse far-gen's approach-invalidation: a too-coarse column near the player must
// be re-gen'd FINER). Drops the mesh, clears the column's voxels in WorldStore over
// its XZ footprint x ColumnYRange, removes the column from the filled/range/gen-LOD
// bookkeeping, and cancels any in-flight gen so a late coarse harvest can't overwrite
// a fresh finer request. Persistence edits are NOT touched — they live in EditStore
// and replay in ApplyColumnResult, so player digs survive the re-gen.
void AVoxelWorld::InvalidateColumnFill(const FIntPoint& Col)
{
	// BUG-1 FIX — KEEP-OLD-UNTIL-READY (non-destructive approach-invalidation).
	//
	// THE OLD BUG (plain English): when the player approached a coarse-generated column we
	// wanted to re-generate it FINER. The old code did the brutal thing: it (1) destroyed the
	// rendered actors, (2) WIPED the column's voxels to AIR in the authoritative store, and
	// (3) forgot the column — THEN queued the finer re-gen, which is async + budgeted (4/tick)
	// and lands many ticks later. In the gap the column was literally AIR: a hole you could
	// see through and (under spawn) fall into. If invalidations outpaced the budget the hole
	// was PERMANENT — chunks under spawn never loaded even standing still.
	//
	// THE FIX (same keep-old-until-ready discipline as Bug-2): do NOT wipe voxels and do NOT
	// unmesh. Leave the existing coarse voxels + their rendered actors LIVE. We ONLY drop the
	// column from FilledColumns + ColumnGenLod so the next ring sweep re-ENQUEUES it at the
	// finer gen-LOD. The finer gen's harvest (ApplyColumnResult) overwrites the voxels and the
	// mesh sweep re-meshes IN PLACE — so coarse-but-present terrain stays visible the whole
	// time and is replaced seamlessly when the fine fill lands. No hole, ever.
	//
	// NOTE we deliberately LEAVE ColumnYRange + MeshedColumns + ColumnMeshedYRange + the actors
	// intact. ApplyColumnResult re-adds ColumnYRange/FilledColumns/ColumnGenLod when the finer
	// fill arrives (its FilledColumns guard means our removal here is what lets it re-apply).

	// 1) Forget ONLY the fill bookkeeping so the ring sweep re-generates this column finer.
	//    The voxels and actors are intentionally left untouched (kept-old-until-ready).
	FilledColumns.Remove(Col);
	ColumnGenLod.Remove(Col);
	// ColumnYRange is intentionally KEPT: the live actors + the finer-gen harvest both rely on
	// the column's vertical span still being known (and the existing coarse mesh stays valid).

	// 2) Cancel any in-flight async gen for this column so a stale (coarser) harvest can't
	//    land after the finer re-gen we're about to enqueue. The worker holds a value copy,
	//    so dropping it is safe — it finishes and ApplyColumnResult's FilledColumns guard
	//    discards it. (We do NOT cancel the MESH job — the existing mesh must stay live.)
	InFlightColumns.Remove(Col);
	PendingGen.RemoveAll([&Col](const FPendingGen& Pg) { return Pg.Key == Col; });
}

void AVoxelWorld::TickStreaming()
{
	// DIAGNOSTIC (TOOL 2): reset this tick's op counters. They're set from the harvest
	// return values below and read by the profiler HUD / log. Pure measurement — a 0 here
	// (e.g. the no-focus early-return) just means "no load applied this tick".
	GenOpsThisTick  = 0;
	MeshOpsThisTick = 0;

	FIntPoint Focus;
	if (!GetFocusChunkXZ(Focus))
	{
		return;
	}

	// The fill ring leads the player along their velocity (P1 prefetch); meshing +
	// eviction + LOD all key off the TRUE focus so detail tiers track where you are.
	FIntPoint FillFocus = Focus;
	GetPrefetchFocusChunkXZ(FillFocus);

	// View-prioritized streaming (flag-gated): refresh the cached view-forward once per
	// tick so the fill + mesh ordering below can bias toward where the player looks. When
	// the flag is off we skip this entirely (FocusForwardXZ stays zero / unused).
	if (bViewPrioritizedStreaming)
	{
		UpdateFocusForwardXZ();
	}

	// Order the cells of ONE ring shell (chebyshev distance == ring around `Center`) for
	// processing. With view-priority OFF this emits the cells in EXACTLY the legacy order
	// (dx outer, dz inner, ascending) so the streaming order is byte-for-byte unchanged.
	// With it ON, the SAME set of cells is sorted by view_priority_key (nearest-ahead
	// first) — a REORDER ONLY: every cell of the ring is still emitted (no cell dropped),
	// and because outer rings are still processed strictly after inner rings, nearest-
	// first completeness is preserved. The bias only shuffles WITHIN this one ring's band.
	// `OutCells` is filled with {dx,dz} offsets relative to `Center`.
	auto CollectRing = [this](int ring, const FIntPoint& Center, TArray<FIntPoint>& OutCells)
	{
		OutCells.Reset();
		for (int dx = -ring; dx <= ring; ++dx)
		for (int dz = -ring; dz <= ring; ++dz)
		{
			if (FMath::Max(FMath::Abs(dx), FMath::Abs(dz)) != ring) { continue; } // shell only
			OutCells.Add(FIntPoint(dx, dz));
		}
		// BUG-1: SKIP the view-priority sort for the innermost rings (ring <= 1). Those rings
		// are already the nearest columns (the ones UNDER / right next to the player, incl.
		// the spawn-underneath columns); biasing their order only risks deprioritizing a column
		// the player is standing on in favour of a forward one — exactly the holed-spawn case.
		// We keep them in the byte-for-byte legacy order so spawn-adjacent columns always load
		// first. Outer rings still get the forward bias.
		if (bViewPrioritizedStreaming && ring > 1 &&
		    (FocusForwardXZ.X != 0.0f || FocusForwardXZ.Y != 0.0f))
		{
			// Sort load-soonest first by the harness-locked key. The chunk delta from the
			// streaming CENTER is (Center.X+dx - Focus.X, ...) but within a single ring the
			// distance ordering only depends on the offset's direction relative to the focus;
			// we key off the offset's own (dx,dz) so the forward cone of THIS ring loads first.
			const float bias = ViewBiasChunks;
			const FVector2D Fwd = FocusForwardXZ;
			OutCells.Sort([bias, Fwd](const FIntPoint& A, const FIntPoint& B)
			{
				const float ka = mira::viewpriority::view_priority_key(A.X, A.Y, Fwd.X, Fwd.Y, bias);
				const float kb = mira::viewpriority::view_priority_key(B.X, B.Y, Fwd.X, Fwd.Y, bias);
				if (ka != kb) { return ka < kb; }
				if (A.X != B.X) { return A.X < B.X; } // deterministic tiebreak
				return A.Y < B.Y;
			});
		}
	};

	const int R = StreamRadiusChunks;
	int Budget = MaxColumnOpsPerTick;

	// --- 3D / spherical surface-shell streaming (flag-gated) ---------------------------
	// Precompute the focus's SURFACE chunk-Y once, so the spherical cull can measure each
	// column's vertical offset (how far its surface sits above/below the player's surface)
	// and carve a true SPHERE/shell instead of a square column field. Everything here is
	// inert when b3DShellStreaming is off (KeepColumn falls back to the chebyshev square).
	int FocusSurfaceChunkY = 0;
	if (b3DShellStreaming)
	{
		mira::HeightmapGenerator FocusGen;
		ConfigureGenerator(FocusGen);
		const mira::Vec3i FocusOrigin = mira::coords::chunk_origin_voxel(mira::Vec3i(Focus.X, 0, Focus.Y));
		const int fgy = FocusGen.compute_ground_y(FocusOrigin.x + mira::coords::CHUNK / 2,
		                                           FocusOrigin.z + mira::coords::CHUNK / 2);
		FocusSurfaceChunkY = mira::streamshell::chunk_of_voxel_y(fgy);
	}

	// KeepColumn — should this column be loaded/kept, given the TRUE focus?
	//   * Flag OFF: the legacy SQUARE (chebyshev) test — byte-for-byte unchanged.
	//   * Flag ON : the NEAR full-depth core (within NearFullDepthRadiusChunks) stays a
	//     CYLINDER (always kept); BEYOND it, a true SPHERE using (dChunkX, dSurfaceY,
	//     dChunkZ) so distant high/low terrain falls outside the round radius.
	//   `radius` is the chebyshev/sphere radius in chunks (R for fill, R+pad for evict).
	//   `surfChunkY` is this column's surface chunk-Y (so dy is the round vertical term).
	auto KeepColumn = [&](int dxChunks, int dzChunks, int surfChunkY, int radius) -> bool
	{
		if (!b3DShellStreaming)
		{
			return FMath::Max(FMath::Abs(dxChunks), FMath::Abs(dzChunks)) <= radius;
		}
		// Near core: a cylinder (no vertical term) so digging straight down always loads.
		const int horiz = FMath::Max(FMath::Abs(dxChunks), FMath::Abs(dzChunks));
		if (horiz <= NearFullDepthRadiusChunks)
		{
			return horiz <= radius;
		}
		// Far: a true sphere/shell around the focus surface.
		const int dy = surfChunkY - FocusSurfaceChunkY;
		return mira::streamshell::within_sphere(dxChunks, dy, dzChunks, radius);
	};

	// Surface chunk-Y of an arbitrary column (for the spherical cull's vertical term).
	// Only called on the flag-ON path; samples the same generator the fill path uses.
	auto ColumnSurfaceChunkY = [&](const FIntPoint& Col) -> int
	{
		mira::HeightmapGenerator G;
		ConfigureGenerator(G);
		const mira::Vec3i O = mira::coords::chunk_origin_voxel(mira::Vec3i(Col.X, 0, Col.Y));
		const int g = G.compute_ground_y(O.x + mira::coords::CHUNK / 2, O.z + mira::coords::CHUNK / 2);
		return mira::streamshell::chunk_of_voxel_y(g);
	};

	// 1) FILL the radius + 1-column skirt (nearest-first), so meshed aprons are
	//    satisfied. Async path generates on worker threads; sync path fills inline.
	if (bAsyncStreaming)
	{
		// Apply finished worker jobs first (counts against this frame's budget), then
		// queue new columns. EnqueueColumnGen self-skips filled/in-flight columns and
		// caps the number of jobs in flight, so the ring sweep below is cheap.
		const int32 GenApplied = HarvestColumnGen(Budget);
		Budget -= GenApplied;
		GenOpsThisTick += GenApplied; // TOOL 2: gen columns applied this tick
		TArray<FIntPoint> RingCells;
		for (int ring = 0; ring <= R + 1; ++ring)
		{
		CollectRing(ring, FillFocus, RingCells); // legacy order when flag off; view-ordered when on
		for (const FIntPoint& Cell : RingCells)
		{
			const int dx = Cell.X, dz = Cell.Y;
			const FIntPoint Col(FillFocus.X + dx, FillFocus.Y + dz);
			// Spherical cull (flag-gated): skip columns outside the sphere/shell around the
			// TRUE focus (the +1 skirt is preserved by widening the radius by 1, so every
			// kept column's apron neighbours are still filled). Flag-off -> square, unchanged.
			if (b3DShellStreaming &&
			    !KeepColumn(Col.X - Focus.X, Col.Y - Focus.Y, ColumnSurfaceChunkY(Col), R + 1))
			{
				continue;
			}
			// Coarse far-gen: desired GEN-LOD from the chebyshev distance to the TRUE
			// focus (NOT the prefetch-led FillFocus), using the PLAIN tier rule — that's
			// the finest the column will ever render at here, so gen is never coarser
			// than render (no cracks). When the flag is off this is always 0.
			const int32 dTrue = FMath::Max(FMath::Abs(Col.X - Focus.X), FMath::Abs(Col.Y - Focus.Y));
			const int32 GenLod = GenLodForDistance(dTrue);
			// Approach-invalidation: if this column was already generated COARSER than we
			// now want, re-gen it FINER. Only ever toward finer (a column moving away keeps
			// its too-fine fill, which downsamples cleanly) — this halves re-gen thrash.
			const int32* Have = ColumnGenLod.Find(Col);
			if (Have && *Have > GenLod)
			{
				InvalidateColumnFill(Col);
			}
			EnqueueColumnGen(Col, GenLod);
		}
		} // for ring
	}
	else
	{
		TArray<FIntPoint> RingCells;
		for (int ring = 0; ring <= R + 1 && Budget > 0; ++ring)
		{
		CollectRing(ring, FillFocus, RingCells); // legacy order when flag off; view-ordered when on
		for (const FIntPoint& Cell : RingCells)
		{
			if (Budget <= 0) { break; } // per-tick budget spent
			const int dx = Cell.X, dz = Cell.Y;
			const FIntPoint Col(FillFocus.X + dx, FillFocus.Y + dz);
			// Spherical cull (flag-gated): skip columns outside the sphere/shell (see async).
			if (b3DShellStreaming &&
			    !KeepColumn(Col.X - Focus.X, Col.Y - Focus.Y, ColumnSurfaceChunkY(Col), R + 1))
			{
				continue;
			}
			// Coarse far-gen: gen-LOD from distance to the TRUE focus (see async branch).
			const int32 dTrue = FMath::Max(FMath::Abs(Col.X - Focus.X), FMath::Abs(Col.Y - Focus.Y));
			const int32 GenLod = GenLodForDistance(dTrue);
			const int32* Have = ColumnGenLod.Find(Col);
			if (Have && *Have > GenLod)
			{
				InvalidateColumnFill(Col);
			}
			if (!FilledColumns.Contains(Col))
			{
				FillChunkColumn(Col.X, Col.Y, GenLod);
				--Budget;
			}
		}
		} // for ring
	}

	// 2) MESH the inner radius (nearest-first) for columns whose skirt is filled.
	//    Each column picks its LOD from its chunk distance to the focus (P3); a column
	//    already meshed at a different tier is re-meshed when it crosses a boundary.
	//    Async path: upload finished worker meshes first (counts against budget), then
	//    enqueue new ones. Sync path: mesh inline on the game thread.
	// Meshing gets its OWN per-tick budget (not the leftover from fill) so a big gen
	// backlog can't starve it — otherwise at a large radius the world stays empty until
	// generation fully catches up. Both apply/upload steps are cheap game-thread work.
	// THROUGHPUT: the mesh HARVEST (game-thread UPLOAD of finished worker meshes — the real
	// streaming bottleneck) gets its OWN dedicated budget (MaxColumnMeshUploadsPerTick),
	// separate from the ENQUEUE sweep budget (MeshBudget = MaxColumnOpsPerTick) below. The
	// upload is the FPS cost; the enqueue is cheap worker-launch. Keeping them separate lets
	// the designer drain a big BUILT-mesh backlog fast (many small coarse meshes/tick) while
	// the enqueue sweep independently keeps the workers fed. The optional ms time-slice caps
	// the per-tick upload's frame cost so a sudden burst can't tank one frame.
	int MeshBudget = MaxColumnOpsPerTick;
	if (bAsyncMeshing)
	{
		const int32 MeshApplied = HarvestColumnMesh(MaxColumnMeshUploadsPerTick);
		MeshOpsThisTick += MeshApplied; // TOOL 2: chunk meshes uploaded this tick
	}
	TArray<FIntPoint> MeshRingCells;
	for (int ring = 0; ring <= R && MeshBudget > 0; ++ring)
	{
		// Ordered cells of this ring: legacy order when the flag is off (byte-for-byte),
		// view-prioritized (nearest-ahead first) when on. The ring index itself is still
		// the chebyshev distance for LOD/shell decisions below (constant across the shell).
		CollectRing(ring, Focus, MeshRingCells);
		for (const FIntPoint& Cell : MeshRingCells)
		{
			if (MeshBudget <= 0) { break; } // per-tick mesh budget spent
			const int dx = Cell.X, dz = Cell.Y;
			const FIntPoint Col(Focus.X + dx, Focus.Y + dz);
			if (!FilledColumns.Contains(Col))
			{
				continue; // skirt not generated yet (async still working) — try later
			}
			const int32* CurLod = ColumnLod.Find(Col);
			// ring == chebyshev chunk distance; pass the column's current LOD so the
			// tier choice is sticky at boundaries (hysteresis).
			const int32 Lod = DesiredColumnLod(ring, CurLod ? *CurLod : 0);
			// Is this an ALREADY-meshed column whose LOD tier actually changed? That's the
			// one case the dither cross-fade cares about (a first-time mesh has nothing to
			// fade FROM; a span-only change keeps the same LOD). Captured before the remesh
			// so we can keep the OLD actors as the fading-out mesh.
			const bool bLodTierChanged = MeshedColumns.Contains(Col) && CurLod && (*CurLod != Lod);
			bool bNeedsMesh = !MeshedColumns.Contains(Col) || (CurLod && *CurLod != Lod);
			// BUG-1: a column whose voxels were just overwritten by a finer re-gen (its old
			// coarse mesh kept live) needs an in-place re-mesh even though LOD/span are the
			// same. The DirtyRemeshColumns flag forces it; we clear it once we (re)mesh.
			const bool bDirtyRemesh = DirtyRemeshColumns.Contains(Col);
			if (bDirtyRemesh) { bNeedsMesh = true; }
			// Surface-shell streaming: also (re)mesh when the column's desired shell SPAN
			// changed — deeper-on-approach (a far column that became near grows its span
			// toward full depth) and shallower-on-retreat. Flag-off: DesiredMeshYRange
			// returns the full span every time, so the span never changes -> no extra work.
			if (!bNeedsMesh && b3DShellStreaming && MeshedColumns.Contains(Col))
			{
				FIntPoint WantSpan;
				const FIntPoint* HaveSpan = ColumnMeshedYRange.Find(Col);
				if (DesiredMeshYRange(Col, ring, WantSpan) && HaveSpan && *HaveSpan != WantSpan)
				{
					bNeedsMesh = true;
				}
			}
			if (bAsyncMeshing && InFlightMeshColumns.Contains(Col))
			{
				bNeedsMesh = false; // a worker is already meshing this column — wait for it
			}
			if (bNeedsMesh)
			{
				// --- LOD cross-fade hook (flag-gated; OFF == original hard-swap path) ---
				// When the flag is OFF, bEnableLodFade short-circuits this whole block and
				// the remesh below runs EXACTLY as before (single reused actor, hard swap).
				if (bEnableLodFade && bLodTierChanged)
				{
					if (mira::lodfade::should_start_fade(*CurLod, Lod, IsColumnFading(Col)))
					{
						// Genuine change, not already fading: detach the old-LOD actors as
						// the fading-out mesh, then fall through to remesh fresh new-LOD
						// actors as the primary. If there were no old actors to fade from
						// (shouldn't happen for a meshed column), BeginColumnFade returns
						// false and we just remesh normally (hard path).
						BeginColumnFade(Col, *CurLod, Lod);
					}
					else
					{
						// Already mid-fade on this column: DEFER the new target and do NOT
						// remesh this tick (remeshing now would clobber the in-flight
						// incoming primary). Apply it when the current fade finishes.
						PendingLodAfterFade.Add(Col, Lod);
						continue;
					}
				}
				// --- MESH-THEN-SWAP hold (Bug-2 fix; flag-gated bKeepOldLodUntilReady) -------
				// When the LOD TIER changed and the dither cross-fade is NOT handling it, do a
				// dither-free swap-HOLD instead of the immediate-destroy remesh: keep the OLD
				// (coarser) mesh on screen as a backstop until the new finer mesh actually
				// uploads (TickFades + should_destroy_outgoing), so there's never a hole in
				// front of the player. We compute the TARGET span the incoming mesh will commit
				// to (DesiredMeshYRange for this ring) so the hold knows when "ready" is reached.
				else if (bKeepOldLodUntilReady && bLodTierChanged &&
				         !IsColumnFading(Col)) // not already holding/fading this column
				{
					FIntPoint TargetSpan;
					if (DesiredMeshYRange(Col, ring, TargetSpan))
					{
						// Detach the old actors as the held backstop (no destroy up front).
						// If there were none to hold (shouldn't happen for a meshed column),
						// this returns false and we just remesh normally (hard path).
						BeginColumnSwapHold(Col, *CurLod, Lod, TargetSpan);
					}
				}
				if (bAsyncMeshing) { EnqueueColumnMesh(Col, Lod, ring); }
				else               { MeshChunkColumn(Col.X, Col.Y, Lod, ring); }
				DirtyRemeshColumns.Remove(Col); // BUG-1: re-mesh queued; clear the dirty flag
				--MeshBudget;
			}
		}
	}

	// 2c) NEAR-BAND MUST-MESH (Bug-1): a small UNBUDGETED pass that guarantees first-time
	//     (never-meshed) columns RIGHT UNDER / next to the player always get meshed, so a
	//     saturated MeshBudget can never leave the spawn (or the ground the player stands on)
	//     a hole. We only ever mesh NEVER-meshed columns within NearFullDepthRadiusChunks here
	//     (a tiny set — the innermost core), and only when their fill is present. Re-mesh /
	//     LOD-swap / shell-shrink are all still budgeted above; this is purely a floor that
	//     keeps the nearest first-loads from being starved. It's intentionally distinct from
	//     the budgeted sweep so a budget set low for far-ring smoothness can't hole the core.
	{
		const int NearBand = FMath::Min(NearFullDepthRadiusChunks, R);
		for (int ddx = -NearBand; ddx <= NearBand; ++ddx)
		for (int ddz = -NearBand; ddz <= NearBand; ++ddz)
		{
			const int dist = FMath::Max(FMath::Abs(ddx), FMath::Abs(ddz));
			if (dist > NearBand) { continue; }
			const FIntPoint Col(Focus.X + ddx, Focus.Y + ddz);
			// Only NEVER-meshed columns (first load). Re-mesh/LOD churn stays budgeted above.
			if (MeshedColumns.Contains(Col)) { continue; }
			if (!FilledColumns.Contains(Col)) { continue; }      // fill not ready yet — try later
			if (bAsyncMeshing && InFlightMeshColumns.Contains(Col)) { continue; } // already meshing
			const int32* CurLod = ColumnLod.Find(Col);
			const int32 Lod = DesiredColumnLod(dist, CurLod ? *CurLod : 0);
			if (bAsyncMeshing) { EnqueueColumnMesh(Col, Lod, dist); }
			else               { MeshChunkColumn(Col.X, Col.Y, Lod, dist); }
		}
	}

	// 2b) SUPER-CHUNKS (far-band aggregation, flag-gated). Render the band BEYOND the
	//     per-chunk StreamRadius — out to SuperRadiusChunks — as coarse super-chunks
	//     (one mesh per N×N×N block of chunks). Heightmap-sampled on workers, mirroring
	//     the column-mesh path. Entirely skipped (no cost) when the flag is off.
	//     MUTUALLY EXCLUSIVE with the Nanite crust: when bEnableNaniteCrust is on, the
	//     baked crust supersedes this band, so we gate the super-chunk DRIVER off here
	//     (the super-chunk code stays intact as a fallback; the eviction block below
	//     still runs so any leftover supers get cleaned up if the crust is toggled on).
	if (bEnableSuperChunks && !bEnableNaniteCrust)
	{
		using namespace mira;
		const int N = SuperChunkSizeChunks;
		// Which super-XZ the focus sits in (floor_div so negatives work).
		const FIntPoint FocusSuperXZ(coords::floor_div(Focus.X, N), coords::floor_div(Focus.Y, N));

		// THROUGHPUT: super UPLOAD (game-thread) gets its own dedicated budget
		// (MaxSuperMeshUploadsPerTick), separate from the ENQUEUE sweep budget (SuperBudget =
		// MaxSuperOpsPerTick). The old code shared one budget, so few supers committed/tick and
		// super-L5 took minutes; draining the built backlog at the upload budget fixes that.
		int SuperBudget = MaxSuperOpsPerTick;
		// Upload finished super meshes first (separate upload budget, not the enqueue budget).
		const int32 SuperApplied = HarvestSuperMesh(MaxSuperMeshUploadsPerTick);
		MeshOpsThisTick += SuperApplied; // TOOL 2: super meshes uploaded this tick

		// A temp generator (game-thread, mirrors the gen path) to find each super-region's
		// vertical extent from the heightmap, so we only mesh the super-Y bands that hold
		// terrain instead of a full column of empty supers.
		HeightmapGenerator FocusGen;
		ConfigureGenerator(FocusGen);

		// Ring sweep over super-XZ from the near edge out to the super radius (in supers).
		const int SuperRingMax = (SuperRadiusChunks + N - 1) / N; // ceil(radius / N)
		for (int sring = 0; sring <= SuperRingMax && SuperBudget > 0; ++sring)
		for (int sdx = -sring; sdx <= sring && SuperBudget > 0; ++sdx)
		for (int sdz = -sring; sdz <= sring && SuperBudget > 0; ++sdz)
		{
			if (FMath::Max(FMath::Abs(sdx), FMath::Abs(sdz)) != sring) { continue; } // shell only

			const FIntPoint S(FocusSuperXZ.X + sdx, FocusSuperXZ.Y + sdz);

			// Chunk distance from the focus to this super-region (its nearest covered chunk).
			const int superMinChunkX = S.X * N;
			const int superMinChunkZ = S.Y * N;
			const int superMaxChunkX = superMinChunkX + N - 1;
			const int superMaxChunkZ = superMinChunkZ + N - 1;
			auto AxisDist = [](int focus, int lo, int hi) -> int
			{
				if (focus < lo) { return lo - focus; }
				if (focus > hi) { return focus - hi; }
				return 0;
			};
			const int superDistChunks = FMath::Max(
				AxisDist(Focus.X, superMinChunkX, superMaxChunkX),
				AxisDist(Focus.Y, superMinChunkZ, superMaxChunkZ));

			// Skip super-regions entirely inside the per-chunk near band (rendered fine).
			if (superDistChunks <= StreamRadiusChunks) { continue; }

			// Skip if ANY covered column is already per-chunk meshed (no double-render).
			bool bAnyNearMeshed = false;
			for (int ccx = superMinChunkX; ccx <= superMaxChunkX && !bAnyNearMeshed; ++ccx)
			for (int ccz = superMinChunkZ; ccz <= superMaxChunkZ && !bAnyNearMeshed; ++ccz)
			{
				if (MeshedColumns.Contains(FIntPoint(ccx, ccz))) { bAnyNearMeshed = true; }
			}
			if (bAnyNearMeshed) { continue; }

			// Vertical extent: sample compute_ground_y at the super-region's 4 corners +
			// centre (in fine voxels), take min/max ground, derive the super-Y band.
			const int v0x = superMinChunkX * coords::CHUNK;
			const int v1x = (superMaxChunkX + 1) * coords::CHUNK - 1;
			const int v0z = superMinChunkZ * coords::CHUNK;
			const int v1z = (superMaxChunkZ + 1) * coords::CHUNK - 1;
			const int vcx = (v0x + v1x) / 2;
			const int vcz = (v0z + v1z) / 2;
			int minGround = INT_MAX, maxGround = INT_MIN;
			const int sampleX[5] = { v0x, v1x, v0x, v1x, vcx };
			const int sampleZ[5] = { v0z, v0z, v1z, v1z, vcz };
			for (int s = 0; s < 5; ++s)
			{
				const int g = FocusGen.compute_ground_y(sampleX[s], sampleZ[s]);
				minGround = FMath::Min(minGround, g);
				maxGround = FMath::Max(maxGround, g);
			}
			const int superSpanVoxels = N * coords::CHUNK;
			const int syLo = coords::floor_div(minGround - coords::CHUNK, superSpanVoxels);
			const int syHi = coords::floor_div(maxGround, superSpanVoxels);

			for (int sy = syLo; sy <= syHi && SuperBudget > 0; ++sy)
			{
				const FIntVector Sc(S.X, sy, S.Y);
				const int32* CurSL = SuperLod.Find(Sc);
				const int32 L = DesiredSuperLod(superDistChunks, CurSL ? *CurSL : 0);
				bool bNeeds = !MeshedSupers.Contains(Sc) || (CurSL && *CurSL != L);
				if (InFlightSuperMeshes.Contains(Sc)) { bNeeds = false; } // worker busy — wait
				if (bNeeds)
				{
					EnqueueSuperMesh(Sc, L);
					--SuperBudget;
				}
			}
		}
	}

	// 3) EVICT meshed columns that drifted beyond radius + hysteresis. (Brick data
	//    is kept for now; CPU-store eviction is a follow-up — see UE5_TECH_STACK.)
	const int EvictDist = R + StreamEvictPaddingChunks;
	TArray<FIntPoint> ToEvict;
	for (const FIntPoint& Col : MeshedColumns)
	{
		// Spherical eviction (flag-gated): a column is KEPT only while it's inside the
		// sphere/shell (radius = R + hysteresis); outside -> evict. KeepColumn falls back
		// to the legacy chebyshev square when the flag is off (unchanged). The cull stays
		// SYMMETRIC with the fill ring (same KeepColumn) so a column that's filled is the
		// same column that's kept — and one that becomes near grows its shell on the next
		// mesh sweep (deeper-on-approach) rather than being evicted then re-filled.
		const int dxC = Col.X - Focus.X, dzC = Col.Y - Focus.Y;
		bool bKeep;
		if (b3DShellStreaming)
		{
			bKeep = KeepColumn(dxC, dzC, ColumnSurfaceChunkY(Col), EvictDist);
		}
		else
		{
			bKeep = FMath::Max(FMath::Abs(dxC), FMath::Abs(dzC)) <= EvictDist;
		}
		if (!bKeep)
		{
			ToEvict.Add(Col);
		}
	}
	// BUDGET TEARDOWN (Bug-2 defense-in-depth): cap how many columns we evict this tick at
	// MaxEvictOpsPerTick. Teardown used to be instant + unbudgeted, so a single frame could
	// drop FAR more geometry than the (budgeted, 4/tick) mesher can rebuild — the root cause
	// of the holes. Capping eviction means a frame can never out-tear-down the mesher. A
	// column still out-of-range that we skip this tick is simply re-collected next tick (it
	// stays in MeshedColumns), so nothing is leaked — eviction just spreads over a few frames.
	int32 EvictBudget = MaxEvictOpsPerTick;
	for (const FIntPoint& Col : ToEvict)
	{
		if (EvictBudget <= 0) { break; } // teardown budget spent — finish next tick
		// WATER EVICTION PRUNE (flag-gated): before dropping the column's mesh,
		// release the live water ledger over the column's voxel AABB so the sim
		// stays bounded to the near band. The projected water bytes already in
		// WorldStore stay (they ride along with the kept brick data); only the
		// ACTIVE sim forgets this region. Must run BEFORE UnmeshChunkColumn — that
		// leaves ColumnYRange intact, so the span is still available here.
		if (bEnableWaterSim && WaterSim.IsValid())
		{
			if (const FIntPoint* Range = ColumnYRange.Find(Col))
			{
				const mira::Vec3i Origin =
					mira::coords::chunk_origin_voxel(mira::Vec3i(Col.X, 0, Col.Y));
				const int YLoVox = Range->X * mira::coords::CHUNK;
				const int YHiVox = (Range->Y + 1) * mira::coords::CHUNK - 1;
				WaterSim->forget_region(
					mira::Vec3i(Origin.x, YLoVox, Origin.z),
					mira::Vec3i(Origin.x + mira::coords::CHUNK - 1, YHiVox,
					            Origin.z + mira::coords::CHUNK - 1));
			}
		}
		UnmeshChunkColumn(Col.X, Col.Y);
		--EvictBudget;
	}

	// 3b) EVICT super-chunks (flag-gated): drop any that drifted past the super radius
	//     + padding, OR whose covered near terrain has FULLY replaced it. No cost when off.
	if (bEnableSuperChunks)
	{
		const int N = SuperChunkSizeChunks;
		const int SuperEvictDist = SuperRadiusChunks + StreamEvictPaddingChunks;
		TArray<FIntVector> SupersToEvict;
		for (const FIntVector& Sc : MeshedSupers)
		{
			const int superMinChunkX = Sc.X * N;
			const int superMinChunkZ = Sc.Z * N;
			const int superMaxChunkX = superMinChunkX + N - 1;
			const int superMaxChunkZ = superMinChunkZ + N - 1;
			auto AxisDist = [](int focus, int lo, int hi) -> int
			{
				if (focus < lo) { return lo - focus; }
				if (focus > hi) { return focus - hi; }
				return 0;
			};
			const int superDistChunks = FMath::Max(
				AxisDist(Focus.X, superMinChunkX, superMaxChunkX),
				AxisDist(Focus.Y, superMinChunkZ, superMaxChunkZ));

			// Past the super radius -> evict outright (it's beyond what we draw at all).
			bool bEvict = (superDistChunks > SuperEvictDist);
			if (!bEvict)
			{
				// MESH-THEN-SWAP (Bug-2): the OLD code evicted the super the instant ANY ONE
				// of its N*N covered columns became per-chunk meshed — while the other ~N*N-1
				// were still un-meshed, leaving a big gap until the fine terrain caught up.
				// FIX: evict only when EVERY covered column that's IN the per-chunk band (i.e.
				// within StreamRadiusChunks of the focus, where fine terrain is supposed to
				// take over) is actually in MeshedColumns. Until then the coarse super stays as
				// a backstop UNDER the still-loading fine terrain (no double-render artifact —
				// fine terrain draws opaque on top). Columns OUTSIDE the radius aren't the
				// super's concern (it legitimately still renders that far band).
				bool bAnyInRangeUnmeshed = false;
				for (int ccx = superMinChunkX; ccx <= superMaxChunkX && !bAnyInRangeUnmeshed; ++ccx)
				for (int ccz = superMinChunkZ; ccz <= superMaxChunkZ && !bAnyInRangeUnmeshed; ++ccz)
				{
					const FIntPoint Col(ccx, ccz);
					const int dCol = FMath::Max(FMath::Abs(ccx - Focus.X), FMath::Abs(ccz - Focus.Y));
					if (dCol <= StreamRadiusChunks && !MeshedColumns.Contains(Col))
					{
						bAnyInRangeUnmeshed = true; // fine terrain not fully in yet -> KEEP super
					}
				}
				// Evict only if at least one covered column is in the near band AND all such
				// near-band columns are now meshed (fine terrain has fully replaced the super).
				bool bAnyInRange = false;
				for (int ccx = superMinChunkX; ccx <= superMaxChunkX && !bAnyInRange; ++ccx)
				for (int ccz = superMinChunkZ; ccz <= superMaxChunkZ && !bAnyInRange; ++ccz)
				{
					const int dCol = FMath::Max(FMath::Abs(ccx - Focus.X), FMath::Abs(ccz - Focus.Y));
					if (dCol <= StreamRadiusChunks) { bAnyInRange = true; }
				}
				if (bAnyInRange && !bAnyInRangeUnmeshed) { bEvict = true; }
			}
			if (bEvict) { SupersToEvict.Add(Sc); }
		}
		// BUDGET TEARDOWN (Bug-2 defense-in-depth): cap super eviction at MaxEvictOpsPerTick
		// per tick too, so a frame can't tear down a wall of supers faster than the near
		// mesher rebuilds. Skipped supers stay in MeshedSupers and are re-collected next tick.
		int32 SuperEvictBudget = MaxEvictOpsPerTick;
		for (const FIntVector& Sc : SupersToEvict)
		{
			if (SuperEvictBudget <= 0) { break; }
			UnmeshSuper(Sc);
			--SuperEvictBudget;
		}
	}
}

// ---------------------------------------------------------------------------
// Editing: carve writes -> brickmap -> re-mesh only the touched chunks.
// ---------------------------------------------------------------------------
void AVoxelWorld::CarveTestHole()
{
	using namespace mira;

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int GroundCentre = Gen.compute_ground_y(0, 0);

	// Dig a Full (5^3) box straight down into the surface at the world centre.
	const Vec3i Centre(0, GroundCentre, 0);
	const Vec3  Down(0.0f, 1.0f, 0.0f); // surface normal points up (Core Y-up)
	const mining::CarveBox Box =
		mining::compute_carve_box(Centre, Down, mining::DEFAULT_FULL_SIZE, mining::MiningAnchor::DepthBiased);

	std::vector<VoxelWrite> Writes = mining::compute_carve(Box);
	apply_writes(WorldStore, Writes);

	// Journal each carved voxel's final state so the dig survives reload (P2).
	if (bPersistEdits)
	{
		for (const VoxelWrite& W : Writes) { RecordEdit(W.pos); }
	}

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}

	// If the dig opened space next to water, let the parent volume flood in.
	FloodCarveFromNeighbours(Writes);

	// Drop any loose material that lost its support.
	ApplyGravityAfterCarve(Centre);
}

// Snap an aimed voxel onto the true SURFACE voxel. The collision impact + floor() can
// land the centre either in the AIR cell just outside the surface OR a cell or two
// BURIED below it, depending on collision skin — and that one-voxel error is why the
// carve box's top layer kept missing the surface. We resolve it from the brickmap:
// the surface voxel is the OUTERMOST solid cell along the hit normal (its outward
// neighbour is air). From the aimed cell, if we're solid we climb OUTWARD to that
// cell; if we're in air we step INWARD until solid. Robust to either-direction error.
static mira::Vec3i SnapCentreToSurface(const mira::Brickmap& Store,
	mira::Vec3i Centre, const mira::Vec3& Normal)
{
	using namespace mira;
	auto step = [](float n) -> int { return n > 0.5f ? 1 : (n < -0.5f ? -1 : 0); };
	const Vec3i Out(step(Normal.x), step(Normal.y), step(Normal.z)); // outward (toward player)
	if (Out.x == 0 && Out.y == 0 && Out.z == 0) { return Centre; }
	auto solid = [&Store](const Vec3i& p) { return Store.type_at(p) != mat::AIR; };

	if (solid(Centre))
	{
		// On/under the surface: climb outward to the topmost solid (outward nbr = air).
		for (int i = 0; i < 8 && solid(Centre + Out); ++i) { Centre = Centre + Out; }
		return Centre;
	}
	// In the air just outside the surface: step inward until solid.
	for (int i = 0; i < 8; ++i)
	{
		Centre = Centre - Out;
		if (solid(Centre)) { return Centre; }
	}
	return Centre; // nothing solid nearby; leave as aimed
}

void AVoxelWorld::CarveAtWorld(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels)
{
	using namespace mira;

	// UE world (cm) -> Core voxel. Inverse of MiraVoxelMesh::PositionToUE
	// (px,py,pz) -> FVector(px, pz, py) * 10:  px = X/10, py = Z/10, pz = Y/10.
	const FVector Local = WorldPos - GetActorLocation();
	Vec3i CentreVoxel(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));
	// Normal swaps the same way (Y/Z) but isn't scaled.
	const Vec3 CoreNormal(HitNormal.X, HitNormal.Z, HitNormal.Y);

	// Anchor the carve on the true surface voxel (fixes the surface layer surviving when
	// the aimed point lands in air above OR buried below the surface).
	const Vec3i RawCentre = CentreVoxel;
	CentreVoxel = SnapCentreToSurface(WorldStore, CentreVoxel, CoreNormal);

	const mining::CarveBox Box =
		mining::compute_carve_box(CentreVoxel, CoreNormal, SideVoxels, mining::MiningAnchor::Centered);

	std::vector<VoxelWrite> Writes = mining::compute_carve(Box);

	// Count how many box voxels were actually SOLID before the carve (= what should
	// visibly disappear). box-total vs solid tells us if a "partial" dig is just the box
	// straddling a slope (lots of air cells) or a real bug (solids left behind).
	int SolidInBox = 0;
	for (const VoxelWrite& W : Writes)
	{
		if (WorldStore.type_at(W.pos) != mat::AIR) { ++SolidInBox; }
	}
	apply_writes(WorldStore, Writes);
	const int NumChunks = static_cast<int>(affected_chunks(Writes).size());

	// Diagnostic (one line per dig): aim/surface/box + solids-removed + chunks remeshed.
	UE_LOG(LogTemp, Warning,
		TEXT("[MiraDig] aim=(%d,%d,%d) surf=(%d,%d,%d) box=[(%d,%d,%d)..(%d,%d,%d)] n=(%.1f,%.1f,%.1f) solid=%d/%d chunks=%d"),
		RawCentre.x, RawCentre.y, RawCentre.z, CentreVoxel.x, CentreVoxel.y, CentreVoxel.z,
		Box.vmin.x, Box.vmin.y, Box.vmin.z, Box.vmax.x, Box.vmax.y, Box.vmax.z,
		CoreNormal.x, CoreNormal.y, CoreNormal.z,
		SolidInBox, static_cast<int>(Writes.size()), NumChunks);

	// Journal each carved voxel's final state so the dig survives reload (P2).
	if (bPersistEdits)
	{
		for (const VoxelWrite& W : Writes) { RecordEdit(W.pos); }
	}

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}

	// If the dig opened space next to water, let the parent volume flood in.
	FloodCarveFromNeighbours(Writes);

	// Drop any loose material that lost its support.
	ApplyGravityAfterCarve(CentreVoxel);
}

bool AVoxelWorld::ComputeCarvePreviewWorld(const FVector& WorldPos, const FVector& HitNormal,
	int32 SideVoxels, FVector& OutCenter, FVector& OutExtent) const
{
	using namespace mira;

	// SAME aimed-voxel + carve-box math CarveAtWorld uses, so the outline matches the
	// real carve exactly (centre voxel = floor(local / 10), Y/Z swapped from UE).
	const FVector Local = WorldPos - GetActorLocation();
	Vec3i CentreVoxel(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));
	const Vec3 CoreNormal(HitNormal.X, HitNormal.Z, HitNormal.Y);

	// Same surface snap as CarveAtWorld so the outline == the voxels actually removed.
	CentreVoxel = SnapCentreToSurface(WorldStore, CentreVoxel, CoreNormal);

	const mining::CarveBox Box =
		mining::compute_carve_box(CentreVoxel, CoreNormal, SideVoxels, mining::MiningAnchor::Centered);

	// The box covers voxels [vmin..vmax] INCLUSIVE; voxel c occupies [c, c+1) in voxel
	// units, so the solid span is vmin .. vmax+1. Convert both corners back to UE world
	// space (Core x->UE X, Core y->UE Z, Core z->UE Y, scaled by 10 cm/voxel).
	auto VoxelCornerToUE = [&](int cx, int cy, int cz)
	{
		return GetActorLocation() + FVector(cx * 10.0f, cz * 10.0f, cy * 10.0f);
	};
	const FVector A = VoxelCornerToUE(Box.vmin.x, Box.vmin.y, Box.vmin.z);
	const FVector B = VoxelCornerToUE(Box.vmax.x + 1, Box.vmax.y + 1, Box.vmax.z + 1);

	const FVector Min(FMath::Min(A.X, B.X), FMath::Min(A.Y, B.Y), FMath::Min(A.Z, B.Z));
	const FVector Max(FMath::Max(A.X, B.X), FMath::Max(A.Y, B.Y), FMath::Max(A.Z, B.Z));
	OutCenter = (Min + Max) * 0.5f;
	OutExtent = (Max - Min) * 0.5f;
	return true;
}

float AVoxelWorld::SurfaceWorldZAt(double WorldX, double WorldY)
{
	using namespace mira;
	LoadHeightmapIfNeeded(); // idempotent; makes this valid even before the world's BeginPlay

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);

	// UE world (cm) -> Core column. Inverse of PositionToUE (px,py,pz)->(px,pz,py)*10:
	//   core x = X/10, core z (= world Y) = Y/10.  (core y is up, i.e. UE Z.)
	const FVector ActorLoc = GetActorLocation();
	const int Cx = FMath::FloorToInt((WorldX - ActorLoc.X) / 10.0f);
	const int Cz = FMath::FloorToInt((WorldY - ActorLoc.Y) / 10.0f);

	// Topmost solid voxel for that column. Its WALKABLE surface is the top face, at
	// (groundY + 1) voxels -> *10 cm, offset by the actor origin.
	const int GroundVoxelY = Gen.compute_ground_y(Cx, Cz);
	return ActorLoc.Z + static_cast<float>((GroundVoxelY + 1) * 10);
}

// Topmost solid voxel Y in column (x,z), searching a band around RefY so sloped/cliff
// neighbours of the aim column are found. INT_MIN if the column is all air in the band.
static int ColumnTopSolidY(const mira::Brickmap& Store, int x, int z, int RefY, int Band)
{
	using namespace mira;
	for (int y = RefY + Band; y >= RefY - Band; --y)
	{
		if (Store.type_at(Vec3i(x, y, z)) != mat::AIR) { return y; }
	}
	return INT_MIN;
}

void AVoxelWorld::CarveColumnConforming(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels)
{
	using namespace mira;
	const int N = FMath::Max(1, SideVoxels);

	const FVector Local = WorldPos - GetActorLocation();
	Vec3i Centre(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));
	const Vec3 CoreNormal(HitNormal.X, HitNormal.Z, HitNormal.Y);
	Centre = SnapCentreToSurface(WorldStore, Centre, CoreNormal);

	const int half_lo = (N - 1) / 2;
	const int half_hi = N / 2;
	const int Band = 32; // ± window per column to find that column's own surface

	std::vector<VoxelWrite> Writes;
	Writes.reserve(static_cast<size_t>(N) * N * N);
	for (int dx = -half_lo; dx <= half_hi; ++dx)
	for (int dz = -half_lo; dz <= half_hi; ++dz)
	{
		const int x = Centre.x + dx;
		const int z = Centre.z + dz;
		const int topY = ColumnTopSolidY(WorldStore, x, z, Centre.y, Band);
		if (topY == INT_MIN) { continue; } // nothing solid under this column
		for (int k = 0; k < N; ++k)
		{
			Writes.push_back(VoxelWrite{ Vec3i(x, topY - k, z), mining::AIR_VOXEL });
		}
	}

	apply_writes(WorldStore, Writes);
	if (bPersistEdits)
	{
		for (const VoxelWrite& W : Writes) { RecordEdit(W.pos); }
	}
	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}
	FloodCarveFromNeighbours(Writes);
	ApplyGravityAfterCarve(Centre);
}

bool AVoxelWorld::ComputeColumnPreview(const FVector& WorldPos, const FVector& HitNormal,
	int32 SideVoxels, TArray<FVector>& OutColumnCenters, FVector& OutExtent) const
{
	using namespace mira;
	const int N = FMath::Max(1, SideVoxels);

	const FVector Local = WorldPos - GetActorLocation();
	Vec3i Centre(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));
	const Vec3 CoreNormal(HitNormal.X, HitNormal.Z, HitNormal.Y);
	Centre = SnapCentreToSurface(WorldStore, Centre, CoreNormal);

	const int half_lo = (N - 1) / 2;
	const int half_hi = N / 2;
	const int Band = 32;
	const FVector ActorLoc = GetActorLocation();

	OutColumnCenters.Reset();
	for (int dx = -half_lo; dx <= half_hi; ++dx)
	for (int dz = -half_lo; dz <= half_hi; ++dz)
	{
		const int x = Centre.x + dx;
		const int z = Centre.z + dz;
		const int topY = ColumnTopSolidY(WorldStore, x, z, Centre.y, Band);
		if (topY == INT_MIN) { continue; }
		// Voxels [topY-N+1 .. topY]; AABB corners (core x->UE X, z->UE Y, y->UE Z) × 10 cm.
		const FVector A = ActorLoc + FVector(x * 10.0f, z * 10.0f, (topY - N + 1) * 10.0f);
		const FVector B = ActorLoc + FVector((x + 1) * 10.0f, (z + 1) * 10.0f, (topY + 1) * 10.0f);
		OutColumnCenters.Add((A + B) * 0.5f);
	}
	// Each per-column box is 1 wide (UE X), 1 deep (UE Y), N tall (UE Z) -> half-sizes.
	OutExtent = FVector(5.0f, 5.0f, N * 5.0f);
	return OutColumnCenters.Num() > 0;
}

// ---------------------------------------------------------------------------
// Per-chunk render: extract the apron'd slab, skip if empty, else hand to actor.
// ---------------------------------------------------------------------------
void AVoxelWorld::RemeshChunk(const FIntVector& ChunkCoord, int32 Lod)
{
	using namespace mira;

	// Clamp to the meshed LOD range (0..3); CHUNK=32 stays divisible by 2^Lod.
	Lod = FMath::Clamp(Lod, 0, lodtier::MAX_LOD);

	const Vec3i Coord(ChunkCoord.X, ChunkCoord.Y, ChunkCoord.Z);
	DenseGrid Slab = extract_mesh_slab(WorldStore, Coord);

	// Is the inner (non-apron) region empty? If so, no mesh — drop any old actor.
	bool bHasContent = false;
	for (int z = APRON; z < APRON + coords::CHUNK && !bHasContent; ++z)
	for (int y = APRON; y < APRON + coords::CHUNK && !bHasContent; ++y)
	for (int x = APRON; x < APRON + coords::CHUNK && !bHasContent; ++x)
	{
		if (Slab.type_at(x, y, z) != mat::AIR || Slab.water_at(x, y, z) != 0)
		{
			bHasContent = true;
		}
	}

	if (!bHasContent)
	{
		DestroyChunkActor(ChunkCoord);
		return;
	}

	AVoxelChunkActor* Actor = EnsureChunkActor(ChunkCoord);
	if (!Actor)
	{
		return;
	}

	if (Lod <= 0)
	{
		// Full-detail near band: mesh the fine slab as-is (water + flora included),
		// at the LOD-0 actor location (apron = 1 fine voxel).
		Actor->SetActorLocation(ChunkActorLocation(ChunkCoord, 1));
		Actor->RenderManaged(Slab, TerrainMaterial, WaterMaterial, FloraMaterial,
		                     bCreateCollision, /*bReverse=*/false, /*PositionScale=*/1.0f,
		                     /*bSolidsOnly=*/false);
		return;
	}

	// --- Mid/far band (P3): downsample the chunk's voxels, mesh the coarse grid. ---
	const int32 S = 1 << Lod; // 2^Lod fine voxels per coarse voxel

	// Copy the slab's inner 32^3 into a plain (apron-less) grid for the downsampler
	// (downsample_to_lod takes a plain DenseGrid, not an apron'd mesh slab).
	DenseGrid Fine(coords::CHUNK);
	for (int z = 0; z < coords::CHUNK; ++z)
	for (int y = 0; y < coords::CHUNK; ++y)
	for (int x = 0; x < coords::CHUNK; ++x)
	{
		Fine.set_type(x, y, z, Slab.type_at(x + APRON, y + APRON, z + APRON));
	}

	const DenseGrid Coarse = lod::downsample_to_lod(Fine, Lod);
	if (Coarse.side <= 0)
	{
		// Defensive: divisibility violated (shouldn't happen for CHUNK=32, Lod<=3) —
		// fall back to a full-detail render so the chunk is never invisible.
		Actor->SetActorLocation(ChunkActorLocation(ChunkCoord, 1));
		Actor->RenderManaged(Slab, TerrainMaterial, WaterMaterial, FloraMaterial,
		                     bCreateCollision, false, 1.0f, false);
		return;
	}

	// Copy the coarse grid into a fresh apron'd mesh slab (shell left AIR) so the
	// greedy mesher can run on it (it expects a MESH_SLAB_SIDE slab). This mirrors the
	// harness-locked LOD-mesh path (test_lodmesh).
	DenseGrid CoarseSlab = make_mesh_slab();
	for (int z = 0; z < Coarse.side; ++z)
	for (int y = 0; y < Coarse.side; ++y)
	for (int x = 0; x < Coarse.side; ++x)
	{
		CoarseSlab.set_type(x + APRON, y + APRON, z + APRON, Coarse.type_at(x, y, z));
	}

	// Coarse mesh: positions in coarse-voxel units, scaled by S to true world size;
	// no collision (only the near band is walkable); solids only (no water/flora at LOD).
	Actor->SetActorLocation(ChunkActorLocation(ChunkCoord, S));
	Actor->RenderManaged(CoarseSlab, TerrainMaterial, WaterMaterial, FloraMaterial,
	                     /*bCollision=*/false, /*bReverse=*/false,
	                     /*PositionScale=*/static_cast<float>(S), /*bSolidsOnly=*/true);
}

// ---------------------------------------------------------------------------
// Chunk actor lifecycle + placement.
// ---------------------------------------------------------------------------
FVector AVoxelWorld::ChunkActorLocation(const FIntVector& ChunkCoord, int32 LodScale) const
{
	// The slab's cell (0,0,0) is world voxel (chunk_origin - APRON*LodScale). Map that
	// voxel to UE via PositionToUE: (vx,vy,vz) -> (vx, vz, vy) * 10. So neighbours tile
	// seamlessly (the +APRON shift the mesher bakes in is cancelled here). At LOD>0 the
	// apron is LodScale (=2^Lod) fine voxels wide, so the origin shifts by APRON*LodScale
	// and the coarse mesh (positions scaled by LodScale) lands on the same world grid.
	const int32 A  = mira::APRON * FMath::Max(1, LodScale);
	const int32 Ox = ChunkCoord.X * mira::coords::CHUNK - A;
	const int32 Oy = ChunkCoord.Y * mira::coords::CHUNK - A;
	const int32 Oz = ChunkCoord.Z * mira::coords::CHUNK - A;
	const float U  = 10.0f; // 1 voxel = 10 UE units (10 cm)
	return GetActorLocation() + FVector(Ox * U, Oz * U, Oy * U);
}

AVoxelChunkActor* AVoxelWorld::EnsureChunkActor(const FIntVector& ChunkCoord)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(ChunkCoord))
	{
		return *Found;
	}

	UWorld* W = GetWorld();
	if (!W)
	{
		return nullptr;
	}

	const FTransform Xform(ChunkActorLocation(ChunkCoord));
	AVoxelChunkActor* Actor = W->SpawnActorDeferred<AVoxelChunkActor>(
		AVoxelChunkActor::StaticClass(), Xform, this);
	if (!Actor)
	{
		return nullptr;
	}
	Actor->bWorldManaged = true;       // suppress the standalone self-build
	Actor->FinishSpawning(Xform);
#if WITH_EDITOR
	Actor->SetActorLabel(FString::Printf(TEXT("Chunk_%d_%d_%d"),
		ChunkCoord.X, ChunkCoord.Y, ChunkCoord.Z));
#endif
	ChunkActors.Add(ChunkCoord, Actor);
	return Actor;
}

void AVoxelWorld::DestroyChunkActor(const FIntVector& ChunkCoord)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(ChunkCoord))
	{
		if (AVoxelChunkActor* Actor = *Found)
		{
			Actor->Destroy();
		}
		ChunkActors.Remove(ChunkCoord);
	}
}

// ---------------------------------------------------------------------------
// LOD-transition dither cross-fade (flag-gated bEnableLodFade). The state machine:
//
//   * A column commits a LOD change (TickStreaming sees *CurLod != Lod). If the flag
//     is on and the column ISN'T already fading, BeginColumnFade detaches the column's
//     CURRENT (old-LOD) chunk actors out of ChunkActors into an FFadeRecord (Outgoing),
//     so the remesh that follows spawns FRESH new-LOD actors as the column's primary.
//   * If the column IS already fading, the caller stores the wanted LOD in
//     PendingLodAfterFade (defer — never two fades on one column).
//   * TickFades (from Tick) drives both meshes' "FadeAlpha" each frame; when the new
//     mesh is fully in it destroys the outgoing actors and applies any deferred LOD.
//   * Eviction / unmesh / clear call CancelColumnFade so an outgoing mesh never leaks.
//
// All of this is dead code paths when the flag is off: BeginColumnFade is only reached
// from the flag-gated branch, and ActiveFades/PendingLodAfterFade stay empty so TickFades
// and the cleanup hooks are O(0) no-ops.
// ---------------------------------------------------------------------------
bool AVoxelWorld::IsColumnFading(const FIntPoint& Col) const
{
	for (const FFadeRecord& F : ActiveFades)
	{
		if (F.Col == Col) { return true; }
	}
	return false;
}

bool AVoxelWorld::BeginColumnFade(const FIntPoint& Col, int32 OldLod, int32 NewLod)
{
	// Detach EVERY currently-spawned actor for this column (one per chunk-Y row) out of
	// ChunkActors and into the fade record as Outgoing. We enumerate the column's actor
	// coords from its meshed span (falling back to the full generated span), then sweep
	// any stragglers directly. Detaching (not destroying) keeps the old mesh on screen to
	// fade out while the remesh builds the new mesh fresh.
	FFadeRecord Rec;
	Rec.Col = Col;
	Rec.IncomingLod = NewLod;

	auto DetachRow = [this, &Rec, &Col](int32 ccy)
	{
		const FIntVector Coord(Col.X, ccy, Col.Y);
		if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(Coord))
		{
			if (AVoxelChunkActor* Actor = *Found)
			{
				Rec.Outgoing.Add(Actor); // keep alive as the fading-out mesh
			}
			ChunkActors.Remove(Coord); // free the coord so the remesh spawns a NEW actor
		}
	};

	if (const FIntPoint* MeshedSpan = ColumnMeshedYRange.Find(Col))
	{
		for (int32 ccy = MeshedSpan->X; ccy <= MeshedSpan->Y; ++ccy) { DetachRow(ccy); }
	}
	else if (const FIntPoint* FullSpan = ColumnYRange.Find(Col))
	{
		for (int32 ccy = FullSpan->X; ccy <= FullSpan->Y; ++ccy) { DetachRow(ccy); }
	}

	if (Rec.Outgoing.Num() == 0)
	{
		// Nothing to fade FROM (brand-new column, or its old actors were already gone).
		// The caller falls back to the plain remesh (no cross-fade needed).
		return false;
	}

	// Show the outgoing mesh at full strength to start (FadeAlpha drives the dither; the
	// outgoing actor is driven with 1-a, which is 1 at a=0). Defensive: if SetFadeAlpha
	// can't bind a MID (no terrain section) it's a harmless no-op.
	for (const TObjectPtr<AVoxelChunkActor>& A : Rec.Outgoing)
	{
		if (A) { A->SetFadeAlpha(0.0f); } // outgoing starts fully visible (1 - 0)
	}

	Rec.StartTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
	Rec.Duration  = FMath::Max(0.0f, LodFadeSeconds);
	ActiveFades.Add(MoveTemp(Rec));
	(void)OldLod; // OldLod is informational; the gate already decided this is a real change
	return true;
}

bool AVoxelWorld::IsColumnSwapHolding(const FIntPoint& Col) const
{
	for (const FFadeRecord& F : ActiveFades)
	{
		if (F.Col == Col && F.bHoldOnly) { return true; }
	}
	return false;
}

bool AVoxelWorld::BeginColumnSwapHold(const FIntPoint& Col, int32 OldLod, int32 NewLod,
	const FIntPoint& TargetSpan)
{
	// MESH-THEN-SWAP (Bug-2): same DETACH machinery as BeginColumnFade — pull the column's
	// current (old-LOD) actors out of ChunkActors into a record's Outgoing so the remesh the
	// caller runs next spawns FRESH new-LOD primary actors — but mark the record bHoldOnly so
	// TickFades does the dither-FREE backstop instead of an alpha cross-fade. The old mesh
	// simply stays drawn (unchanged) until the new one uploads, then is destroyed in one step.
	FFadeRecord Rec;
	Rec.Col = Col;
	Rec.IncomingLod = NewLod;
	Rec.bHoldOnly = true;            // dither-free swap-hold (NOT a cross-fade)
	Rec.TargetSpan = TargetSpan;     // the committed span the incoming mesh must reach

	auto DetachRow = [this, &Rec, &Col](int32 ccy)
	{
		const FIntVector Coord(Col.X, ccy, Col.Y);
		if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(Coord))
		{
			if (AVoxelChunkActor* Actor = *Found)
			{
				Rec.Outgoing.Add(Actor); // keep alive as the held backstop mesh
			}
			ChunkActors.Remove(Coord);   // free the coord so the remesh spawns a NEW actor
		}
	};

	if (const FIntPoint* MeshedSpan = ColumnMeshedYRange.Find(Col))
	{
		for (int32 ccy = MeshedSpan->X; ccy <= MeshedSpan->Y; ++ccy) { DetachRow(ccy); }
	}
	else if (const FIntPoint* FullSpan = ColumnYRange.Find(Col))
	{
		for (int32 ccy = FullSpan->X; ccy <= FullSpan->Y; ++ccy) { DetachRow(ccy); }
	}

	if (Rec.Outgoing.Num() == 0)
	{
		// Nothing to hold FROM (brand-new column, or its actors were already gone). The
		// caller falls back to the plain remesh — there is no old mesh to protect.
		return false;
	}

	// IMPORTANT: do NOT touch FadeAlpha here. A swap-hold leaves the old mesh exactly as it
	// was drawn (fully opaque) — it is only a deferred destroy, not a visual fade.
	Rec.StartTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
	Rec.Duration  = FMath::Max(0.0f, LodFadeSeconds); // unused by the hold path, kept for parity
	ActiveFades.Add(MoveTemp(Rec));
	(void)OldLod; // informational; the caller already decided this is a real tier change
	return true;
}

void AVoxelWorld::TickFades(float Dt)
{
	(void)Dt; // we use absolute world time vs StartTime, not the frame delta
	if (ActiveFades.Num() == 0)
	{
		return; // flag off (or nothing fading) — zero cost
	}

	const double Now = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;

	// Walk back-to-front so we can RemoveAtSwap finished fades without skipping any.
	for (int32 i = ActiveFades.Num() - 1; i >= 0; --i)
	{
		FFadeRecord& F = ActiveFades[i];

		// --- MESH-THEN-SWAP HOLD (Bug-2): dither-free backstop branch. ---------------------
		// A hold record NEVER touches FadeAlpha — the old mesh stays drawn exactly as it was.
		// We just wait until the incoming primary mesh is GENUINELY ready, then destroy the
		// held old actors in one step. "Ready" == the column is meshed, NOT still meshing on a
		// worker, and its committed span matches the target span we recorded at hold start.
		if (F.bHoldOnly)
		{
			// "Ready" == the incoming primary mesh is genuinely up: the column is meshed,
			// no worker is still meshing it, and its committed span == the target span we
			// recorded at hold start (so a deeper-on-approach span change can't be mistaken
			// for the swap being done). Until all three hold, KEEP the old mesh (no hole).
			const FIntPoint* HaveSpan = ColumnMeshedYRange.Find(F.Col);
			const bool bIncomingReady =
				MeshedColumns.Contains(F.Col) &&
				!InFlightMeshColumns.Contains(F.Col) &&
				HaveSpan != nullptr && *HaveSpan == F.TargetSpan;

			if (mira::lodfade::should_destroy_outgoing(bIncomingReady))
			{
				// New mesh is fully up: drop the held old mesh now (seamless swap, no hole).
				for (const TObjectPtr<AVoxelChunkActor>& A : F.Outgoing)
				{
					if (A) { A->Destroy(); }
				}
				const FIntPoint DoneCol = F.Col;
				ActiveFades.RemoveAtSwap(i);

				// A LOD change requested for this column WHILE we were holding gets applied now.
				if (int32* Pending = PendingLodAfterFade.Find(DoneCol))
				{
					const int32 WantLod = *Pending;
					PendingLodAfterFade.Remove(DoneCol);
					ApplyDeferredColumnLod(DoneCol, WantLod);
				}
			}
			continue; // hold records never run the alpha-fade code below
		}

		const float a = mira::lodfade::fade_alpha(Now - F.StartTime, F.Duration);

		// Drive the OUTGOING (old-LOD) actors: fade out as 1 - a.
		for (const TObjectPtr<AVoxelChunkActor>& A : F.Outgoing)
		{
			if (A) { A->SetFadeAlpha(1.0f - a); }
		}

		// Drive the INCOMING (new-LOD) primary actors: fade in as a. The primary actors
		// are whatever currently sits in ChunkActors for this column's rows.
		if (const FIntPoint* MeshedSpan = ColumnMeshedYRange.Find(F.Col))
		{
			for (int32 ccy = MeshedSpan->X; ccy <= MeshedSpan->Y; ++ccy)
			{
				const FIntVector Coord(F.Col.X, ccy, F.Col.Y);
				if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(Coord))
				{
					if (*Found) { (*Found)->SetFadeAlpha(a); }
				}
			}
		}

		if (a >= 1.0f)
		{
			// Fade complete: the new mesh is fully in. Destroy the outgoing actors and
			// drop the record. (The incoming actors stay as the column's plain primary; at
			// a==1 their dither is fully opaque, indistinguishable from an un-faded chunk.)
			for (const TObjectPtr<AVoxelChunkActor>& A : F.Outgoing)
			{
				if (A) { A->Destroy(); }
			}
			const FIntPoint DoneCol = F.Col;
			ActiveFades.RemoveAtSwap(i);

			// If another LOD change was requested for this column mid-fade, apply it now —
			// which may kick off a fresh fade for the same column.
			if (int32* Pending = PendingLodAfterFade.Find(DoneCol))
			{
				const int32 WantLod = *Pending;
				PendingLodAfterFade.Remove(DoneCol);
				ApplyDeferredColumnLod(DoneCol, WantLod);
			}
		}
	}
}

bool AVoxelWorld::CancelColumnFade(const FIntPoint& Col)
{
	bool bFound = false;
	for (int32 i = ActiveFades.Num() - 1; i >= 0; --i)
	{
		if (ActiveFades[i].Col == Col)
		{
			// Destroy ONLY the outgoing actors (the primary actors are handled by the
			// caller's own teardown — eviction destroys them via UnmeshChunkColumn, clear
			// via ClearWorld). This prevents an outgoing-mesh leak without double-freeing
			// the primary.
			for (const TObjectPtr<AVoxelChunkActor>& A : ActiveFades[i].Outgoing)
			{
				if (A) { A->Destroy(); }
			}
			ActiveFades.RemoveAtSwap(i);
			bFound = true;
		}
	}
	PendingLodAfterFade.Remove(Col);
	return bFound;
}

// Apply a LOD change that was deferred because the column was mid-fade. Mirrors the
// TickStreaming commit branch for a single column: start a fresh fade (if old actors
// exist) then remesh. Distance is recovered from the focus so the remesh uses the right
// shell span. Safe to call when the column is no longer meshed (it just no-ops).
void AVoxelWorld::ApplyDeferredColumnLod(const FIntPoint& Col, int32 WantLod)
{
	if (!MeshedColumns.Contains(Col))
	{
		return; // column was evicted/cleared while deferred — nothing to do
	}
	const int32* CurLod = ColumnLod.Find(Col);
	const int32 OldLod = CurLod ? *CurLod : 0;
	if (OldLod == WantLod)
	{
		return; // already where we wanted (a redundant deferral) — nothing to do
	}

	FIntPoint Focus;
	const int32 Dist = GetFocusChunkXZ(Focus)
		? FMath::Max(FMath::Abs(Col.X - Focus.X), FMath::Abs(Col.Y - Focus.Y))
		: 0;

	// Begin a fresh cross-fade from the current (now-old) actors, then remesh to the
	// wanted LOD. If there were no old actors, just remesh (hard path).
	BeginColumnFade(Col, OldLod, WantLod);
	if (bAsyncMeshing) { EnqueueColumnMesh(Col, WantLod, Dist); }
	else               { MeshChunkColumn(Col.X, Col.Y, WantLod, Dist); }
}

// ---------------------------------------------------------------------------
// Open-ocean sea plane (M-water) — flag-gated bEnableSeaPlane (DEFAULT OFF).
//
// WHAT THIS DOES (plain English): the near voxel band meshes real water surfaces,
// but FAR away the world is solids-only — so past that band there'd be no water at
// all, just a hard edge. This drops ONE big flat sheet of water at sea level and
// slides it to stay under the player, so the ocean reaches the horizon. It's a
// single 2-triangle quad (cheap), uses WaterMaterial, has NO collision, and lives
// as a component on this actor (so it follows/ tears down with the world).
//
// PLACEMENT MATH:
//   * Z (height): world sea level. Sea level = SeaLevelMeters metres; at 10 vox/m
//     that's sea_level_voxels = round(SeaLevelMeters*10) voxels; at 10 UE units per
//     voxel (10 cm cubes) that's Z = sea_level_voxels * 10 UE units. For the default
//     140 m -> 1400 vox -> Z = 14000. Read LIVE every call so the editor knob tracks.
//   * XY (centre): the streaming focus's world XY (the same focus the chunk ring
//     follows), so the plane is always under the player. We only re-centre (move),
//     not rebuild, when just the focus changed.
//   * Size: half-extent. If SeaPlaneHalfExtentMeters > 0 use it; else derive from
//     StreamRadiusChunks (chunks * 32 vox * 10 UE units) plus a margin so it always
//     covers the visible near band and a bit beyond.
// ---------------------------------------------------------------------------
void AVoxelWorld::EnsureSeaPlane()
{
	// Flag OFF (or no world yet): make sure no plane is showing, then bail. This is
	// the "zero behaviour change" path — nothing is ever spawned with the flag off.
	if (!bEnableSeaPlane)
	{
		if (SeaPlaneMesh)
		{
			SeaPlaneMesh->DestroyComponent();
			SeaPlaneMesh = nullptr;
		}
		return;
	}

	UWorld* W = GetWorld();
	if (!W)
	{
		return;
	}

	// --- Resolve the live placement values ---
	// Sea-level Z in UE units. SeaLevelMeters is the LIVE editor knob (NOT the stale
	// VoxelGenParams.SeaLevel fallback). 1 voxel = 10 UE units (10 cm cubes).
	const int32  SeaLevelVoxels = FMath::RoundToInt(SeaLevelMeters * 10.0f);
	const double VoxelToUU      = 10.0;
	const double SeaZ           = static_cast<double>(SeaLevelVoxels) * VoxelToUU;

	// Half-extent in UE units. 0 -> derive from the stream radius (a generous cover).
	double HalfExtentUU;
	if (SeaPlaneHalfExtentMeters > 0.0f)
	{
		HalfExtentUU = static_cast<double>(SeaPlaneHalfExtentMeters) * 10.0 /*m->vox*/ * VoxelToUU;
	}
	else
	{
		// StreamRadiusChunks chunks, 32 voxels/chunk, *10 UE units/voxel, +50% margin.
		const double RadiusUU = static_cast<double>(StreamRadiusChunks)
		                      * static_cast<double>(mira::coords::CHUNK) * VoxelToUU;
		HalfExtentUU = RadiusUU * 1.5;
	}

	// --- Focus XY (world cm) to centre the plane on. Mirror GetFocusChunkXZ's source
	//     (StreamFocusActor, else player pawn). If there's no focus yet, centre on this
	//     actor so the plane still appears (it just won't follow until a focus exists). ---
	FVector FocusWorld = GetActorLocation();
	if (StreamFocusActor)
	{
		FocusWorld = StreamFocusActor->GetActorLocation();
	}
	else if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		FocusWorld = Pawn->GetActorLocation();
	}

	// --- Spawn the component on first use ---
	if (!SeaPlaneMesh)
	{
		SeaPlaneMesh = NewObject<UProceduralMeshComponent>(this, TEXT("SeaPlaneMesh"));
		SeaPlaneMesh->SetupAttachment(GetRootComponent());
		SeaPlaneMesh->RegisterComponent();
		SeaPlaneMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision); // water: no collision
		SeaPlaneMesh->SetMobility(EComponentMobility::Movable);            // it re-centres each tick
		SeaPlaneBuiltZ = 0.0;                  // force a geometry build below
		SeaPlaneBuiltHalfExtentUU = 0.0;
	}

	// --- (Re)build the quad geometry only when Z or size actually changed. The quad is
	//     LOCAL to the component (centred on origin), so a focus move is just a SetWorld
	//     Location — no rebuild. We bake the sea-level Z into the LOCAL geometry and keep
	//     the component's own Z at the actor, so the plane sits at absolute world SeaZ. ---
	const bool bNeedRebuild =
		!FMath::IsNearlyEqual(SeaPlaneBuiltZ, SeaZ) ||
		!FMath::IsNearlyEqual(SeaPlaneBuiltHalfExtentUU, HalfExtentUU);
	if (bNeedRebuild)
	{
		const float H = static_cast<float>(HalfExtentUU);

		// Four corners of a flat quad in the XY plane, local Z = 0 (the component is
		// positioned at world Z = SeaZ below). Wound CCW seen from above (+Z up) so the
		// +Z normal faces the sky.
		TArray<FVector> Positions;
		Positions.Add(FVector(-H, -H, 0.0f));
		Positions.Add(FVector( H, -H, 0.0f));
		Positions.Add(FVector( H,  H, 0.0f));
		Positions.Add(FVector(-H,  H, 0.0f));

		TArray<int32> Triangles;
		Triangles.Add(0); Triangles.Add(1); Triangles.Add(2);
		Triangles.Add(0); Triangles.Add(2); Triangles.Add(3);

		TArray<FVector> Normals;
		for (int i = 0; i < 4; ++i) { Normals.Add(FVector(0, 0, 1)); }

		// UV0 spans 0..1 across the whole plane (a material can tile it as it likes).
		TArray<FVector2D> UV0;
		UV0.Add(FVector2D(0, 0));
		UV0.Add(FVector2D(1, 0));
		UV0.Add(FVector2D(1, 1));
		UV0.Add(FVector2D(0, 1));

		TArray<FColor> Colors; // tint = base water colour (matches the near water verts)
		const FColor WaterTint(51, 102, 153, 255);
		for (int i = 0; i < 4; ++i) { Colors.Add(WaterTint); }

		TArray<FProcMeshTangent> Tangents; // empty — PMC derives

		SeaPlaneMesh->ClearAllMeshSections();
		SeaPlaneMesh->CreateMeshSection(0, Positions, Triangles, Normals, UV0,
		                                Colors, Tangents, /*bCreateCollision=*/false);
		if (WaterMaterial)
		{
			SeaPlaneMesh->SetMaterial(0, WaterMaterial);
		}

		SeaPlaneBuiltZ = SeaZ;
		SeaPlaneBuiltHalfExtentUU = HalfExtentUU;
	}

	// --- Re-centre under the focus XY at sea-level Z (every call; cheap move). ---
	SeaPlaneMesh->SetWorldLocation(FVector(FocusWorld.X, FocusWorld.Y, SeaZ));
}

void AVoxelWorld::ClearWorld()
{
	// Edge case (b): GenEpoch invalidation / ClearWorld mid-fade. The OUTGOING actors of
	// any in-flight cross-fade were DETACHED from ChunkActors when their fade began, so the
	// ChunkActors sweep below would miss them and leak them. Destroy every outgoing actor
	// and wipe the fade state first. No-op when the flag is off (ActiveFades is empty).
	for (FFadeRecord& F : ActiveFades)
	{
		for (const TObjectPtr<AVoxelChunkActor>& A : F.Outgoing)
		{
			if (A) { A->Destroy(); }
		}
	}
	ActiveFades.Empty();
	PendingLodAfterFade.Empty();

	for (TPair<FIntVector, TObjectPtr<AVoxelChunkActor>>& Pair : ChunkActors)
	{
		if (AVoxelChunkActor* Actor = Pair.Value)
		{
			Actor->Destroy();
		}
	}
	ChunkActors.Empty();

	// Super-chunk renderer actors (flag-gated feature; empty when off — a no-op loop).
	for (TPair<FIntVector, TObjectPtr<AVoxelChunkActor>>& Pair : SuperActors)
	{
		if (AVoxelChunkActor* Actor = Pair.Value)
		{
			Actor->Destroy();
		}
	}
	SuperActors.Empty();

	// P1: invalidate then wait out any in-flight async generation jobs BEFORE we
	// reset the inputs they read (the EXR), so no worker touches freed/changed data.
	// Bumping the epoch first means a job that finishes mid-drain is discarded.
	++GenEpoch;
	DrainColumnGen();
	DrainColumnMesh(); // same: wait out in-flight mesh workers (they hold slab copies)
	DrainSuperMesh();  // same: wait out in-flight super-chunk mesh workers (heightmap-pure)

	// Reset the authoritative store (default-constructed brickmap = empty) and the
	// streaming bookkeeping so a regenerate starts from a clean slate.
	WorldStore = mira::Brickmap();
	FilledColumns.Empty();
	MeshedColumns.Empty();
	ColumnYRange.Empty();
	ColumnMeshedYRange.Empty(); // surface-shell streaming: per-column meshed span tracking
	ColumnLod.Empty();
	ColumnGenLod.Empty();
	DirtyRemeshColumns.Empty(); // BUG-1: drop any pending finer-re-gen re-mesh flags
	MeshedSupers.Empty();
	SuperLod.Empty();

	// Drop the water sim — it captured the old brickmap; a fresh one binds lazily.
	WaterSim.Reset();
	WaterSimAccum = 0.0f;
}

// ===========================================================================
// DIAGNOSTIC TOOL 1 — LOD debug-color helpers.
// ===========================================================================

// Decide the debug color for a chunk/super at `Lod` given the live mira.LodDebug value.
// Returns false (keep normal material color) when the mode is off, or when the actor is a
// super-chunk but the mode is only coloring per-chunk (mode 1). Pure: reads the cvar + the
// Core palette; changes nothing.
bool AVoxelWorld::GetLodDebugColor(int32 Lod, bool bSuper, FColor& OutColor) const
{
	const int32 Mode = CVarMiraLodDebug.GetValueOnGameThread();
	if (Mode <= 0)
	{
		return false; // off — normal material colors
	}
	if (bSuper && Mode < 2)
	{
		return false; // mode 1 colors per-chunk only; supers stay normal until mode 2
	}
	const mira::Rgb8 C = mira::lod_debug_color(Lod, bSuper);
	OutColor = FColor(C.r, C.g, C.b, 255); // alpha unused (the mesh keeps its own AO alpha)
	return true;
}

// Re-color EVERY loaded chunk + super actor to match the CURRENT mira.LodDebug value. Each
// actor re-uploads its cached mesh with the new tint (or none). The per-actor LOD comes from
// the authoritative streaming maps (ColumnLod for chunks, SuperLod for supers). Render-only:
// no voxel/brick data, no streaming/budget state is touched. This is what the cvar change-sink
// calls so already-loaded terrain recolors the instant the tester flips the cvar.
void AVoxelWorld::ApplyLodDebugRecolor()
{
	// Per-chunk actors: look up the column's current LOD (ColumnLod is keyed by XZ).
	for (const TPair<FIntVector, TObjectPtr<AVoxelChunkActor>>& Pair : ChunkActors)
	{
		AVoxelChunkActor* Actor = Pair.Value;
		if (!Actor || !Actor->HasMeshForRecolor()) { continue; }
		const int32* Lod = ColumnLod.Find(FIntPoint(Pair.Key.X, Pair.Key.Z));
		FColor DbgCol;
		const bool bDbg = GetLodDebugColor(Lod ? *Lod : 0, /*bSuper=*/false, DbgCol);
		Actor->RecolorDebug(bDbg ? &DbgCol : nullptr);
	}
	// Super-chunk actors: look up the super's current super-LOD (SuperLod keyed by super coord).
	for (const TPair<FIntVector, TObjectPtr<AVoxelChunkActor>>& Pair : SuperActors)
	{
		AVoxelChunkActor* Actor = Pair.Value;
		if (!Actor || !Actor->HasMeshForRecolor()) { continue; }
		const int32* Lod = SuperLod.Find(Pair.Key);
		FColor DbgCol;
		const bool bDbg = GetLodDebugColor(Lod ? *Lod : 0, /*bSuper=*/true, DbgCol);
		Actor->RecolorDebug(bDbg ? &DbgCol : nullptr);
	}
}

// ===========================================================================
// DIAGNOSTIC TOOL 2 — chunk-loading profiler frame-window tracker.
// ===========================================================================

// Fold this frame's delta into the rolling worst-frame window (~2 s). We track the worst
// frame seen overall AND the worst on a "loading" tick (mesh/gen ops > 0 this tick), so a
// 150 ms spike stays visible after it passes and the tester can see it correlated to loading.
// The window resets every WorstFrameWindowSeconds so old spikes don't pin the readout forever.
// Pure measurement: reads FApp delta + this tick's op counts; changes no streaming state.
void AVoxelWorld::UpdateProfilerFrameWindow(float DeltaSeconds)
{
	const float FrameMs = DeltaSeconds * 1000.0f;
	const bool bLoadingThisTick = (GenOpsThisTick > 0 || MeshOpsThisTick > 0);

	WorstFrameMsWindow = FMath::Max(WorstFrameMsWindow, FrameMs);
	if (bLoadingThisTick)
	{
		WorstLoadFrameMsWindow = FMath::Max(WorstLoadFrameMsWindow, FrameMs);
	}

	// Age the window: once ~2 s have passed, restart so the worst-frame numbers reflect
	// RECENT load, not a spike from a minute ago. Seed the fresh window with this frame.
	WorstFrameWindowAccum += DeltaSeconds;
	if (WorstFrameWindowAccum >= WorstFrameWindowSeconds)
	{
		WorstFrameWindowAccum  = 0.0f;
		WorstFrameMsWindow     = FrameMs;
		WorstLoadFrameMsWindow = bLoadingThisTick ? FrameMs : 0.0f;
	}
}

// Read-only snapshot of the FAR-render load, built from the existing streaming maps.
// Pure instrumentation: it ONLY counts existing state — it never writes any map, spawns
// or destroys an actor, or touches any streaming/meshing/eviction/budget logic.
FMiraFarRenderStats AVoxelWorld::GetFarRenderStats() const
{
	FMiraFarRenderStats S;

	// Near per-chunk renderer actors and far super-chunk renderer actors, live right now.
	S.NearChunkActors  = ChunkActors.Num();
	S.SuperActorsTotal = SuperActors.Num();

	// Per-super-LOD histogram. SuperLod maps each super-chunk coord -> its current
	// super-LOD (0=finest .. 5=coarsest far-horizon tile). MeshedSupers is the set of
	// supers that actually have a mesh; SuperLod is the authoritative per-super LOD, so
	// we iterate SuperLod and bucket by value (clamped to the 0..5 band range).
	for (const TPair<FIntVector, int32>& Pair : SuperLod)
	{
		const int32 L = FMath::Clamp(Pair.Value, 0, 5);
		++S.SuperByLod[L];
	}

	// Columns generated at a COARSE gen-LOD (coarse far-gen). ColumnGenLod records the
	// gen-LOD each filled column was generated at; value > 0 means it was generated
	// coarser than full detail (i.e. a far column the coarse far-gen path handled).
	for (const TPair<FIntPoint, int32>& Pair : ColumnGenLod)
	{
		if (Pair.Value > 0)
		{
			++S.CoarseGenColumns;
		}
	}

	// Columns the 3D surface-shell streaming trimmed: their EFFECTIVE meshed Y span
	// (ColumnMeshedYRange) is SHORTER than the full generated span (ColumnYRange). Only
	// meaningful while b3DShellStreaming is on (with it off, the meshed span always
	// equals the full span, so this is naturally 0). We compare span LENGTHS per column.
	if (b3DShellStreaming)
	{
		for (const TPair<FIntPoint, FIntPoint>& Pair : ColumnMeshedYRange)
		{
			const FIntPoint* Full = ColumnYRange.Find(Pair.Key);
			if (Full == nullptr)
			{
				continue; // no full-span record to compare against — skip
			}
			// Span height = hi - lo (X=loChunkY, Y=hiChunkY). Trimmed if meshed < full.
			const int32 MeshedSpan = Pair.Value.Y - Pair.Value.X;
			const int32 FullSpan   = Full->Y - Full->X;
			if (MeshedSpan < FullSpan)
			{
				++S.ShellCulledColumns;
			}
		}
	}

	// LOD cross-fades currently in progress, and the far-ring radius knob (for context).
	S.ActiveFades       = ActiveFades.Num();
	S.SuperRadiusChunks = SuperRadiusChunks;

	// --- Chunk-loading profiler (TOOL 2): per-tick load + queue depth + worst-frame window.
	// All read from existing counters — no streaming/budget state is changed by reading them.
	S.GenOpsThisTick   = GenOpsThisTick;
	S.MeshOpsThisTick  = MeshOpsThisTick;
	// Worker jobs LAUNCHED but not yet applied (gen + column-mesh + super-mesh), and queued
	// results WAITING to be applied. "InFlight" = the worker is still chewing; "Pending" =
	// finished/queued payloads (the same arrays the harvest loops drain). These together show
	// how deep the backlog is when a hitch happens.
	S.JobsInFlight = InFlightColumns.Num() + InFlightMeshColumns.Num() + InFlightSuperMeshes.Num();
	S.Pending      = PendingGen.Num() + PendingMesh.Num() + PendingSuperMesh.Num();
	// Rolling worst-frame window (~2 s): worst frame overall + worst on a loading tick.
	S.WorstFrameMs     = WorstFrameMsWindow;
	S.WorstLoadFrameMs = WorstLoadFrameMsWindow;

	return S;
}

void AVoxelWorld::LogStreamingStats()
{
	// Per-LOD column histogram (objective P3 check). ColumnLod holds the LOD each
	// meshed column is currently rendered at; with bEnableLOD on, columns farther
	// from the focus should appear at LOD 1/2/3.
	int LodHist[4] = { 0, 0, 0, 0 };
	for (const TPair<FIntPoint, int32>& Pair : ColumnLod)
	{
		const int32 L = FMath::Clamp(Pair.Value, 0, 3);
		++LodHist[L];
	}
	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] STREAM STATS: filled=%d meshed=%d chunkActors=%d | LOD0=%d LOD1=%d LOD2=%d LOD3=%d | jobsInFlight=%d pending=%d async=%d lod=%d"),
		FilledColumns.Num(), MeshedColumns.Num(), ChunkActors.Num(),
		LodHist[0], LodHist[1], LodHist[2], LodHist[3],
		InFlightColumns.Num(), PendingGen.Num(),
		bAsyncStreaming ? 1 : 0, bEnableLOD ? 1 : 0);

	// Far-render load (super-chunks per LOD band, coarse far-gen, 3D-shell trim, fades).
	// Same numbers the debug HUD shows — logged so the designer can tune the far ring
	// from the output log too. Read-only snapshot; no behaviour change.
	const FMiraFarRenderStats Far = GetFarRenderStats();
	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] STREAM STATS: | SUPER total=%d L0..L5=%d/%d/%d/%d/%d/%d radius=%d | coarseGen=%d shellCulled=%d fades=%d ")
		TEXT("| PROFILER genOps=%d meshOps=%d inFlight=%d pending=%d worstMs=%.1f worstLoadMs=%.1f"),
		Far.SuperActorsTotal,
		Far.SuperByLod[0], Far.SuperByLod[1], Far.SuperByLod[2],
		Far.SuperByLod[3], Far.SuperByLod[4], Far.SuperByLod[5],
		Far.SuperRadiusChunks,
		Far.CoarseGenColumns, Far.ShellCulledColumns, Far.ActiveFades,
		Far.GenOpsThisTick, Far.MeshOpsThisTick, Far.JobsInFlight, Far.Pending,
		Far.WorstFrameMs, Far.WorstLoadFrameMs);

	// Water-sim load (only meaningful with bEnableWaterSim). `active` = cells the next
	// step will look at — the near-band size to watch when tuning WaterSimRadiusChunks;
	// `forgotten` = units the streaming gate/eviction released (audited). No-op-ish when
	// the sim was never built.
	if (bEnableWaterSim && WaterSim.IsValid())
	{
		const mira::FiniteWaterCore::Stats WS = WaterSim->stats();
		UE_LOG(LogTemp, Display,
			TEXT("[MiraThal] WATER STATS: active=%d units=%d placed=%d forgotten=%d radiusChunks=%d delta=%d"),
			WS.active, WS.units, WS.placed, WS.forgotten,
			WaterSimRadiusChunks, WaterSim->conservation_delta());
	}
}

// ---------------------------------------------------------------------------
// Perf telemetry CSV (TOOL 3). Append one row of streaming/perf/water stats to
// <Project>/Saved/MiraThalPerf.csv. Designed to be opened/read directly (by the
// designer or by Claude) so terrain + water perf problems can be diagnosed from
// DATA over time — FPS, worst-frame spikes, queue depth, and the LOD-transition
// churn (cross-fades vs swap-holds) that causes visible holes. Pure measurement:
// every value here is READ from existing streaming state; nothing is mutated.
// ---------------------------------------------------------------------------
void AVoxelWorld::WritePerfCsvRow()
{
	const FString Path = FPaths::ProjectSavedDir() / TEXT("MiraThalPerf.csv");

	// Header (written once, truncating any old file) the first time we log after enabling.
	if (!bPerfCsvStarted)
	{
		const FString Header = TEXT(
			"timeSec,fps,worstMs,worstLoadMs,filled,meshed,chunkActors,"
			"lod0,lod1,lod2,lod3,superTotal,superL0,superL1,superL2,superL3,superL4,superL5,"
			"coarseGen,shellCulled,fades,holds,genOps,meshOps,jobsInFlight,pending,"
			"pendGen,pendMesh,pendSuper,inFlightGen,inFlightMesh,inFlightSuper,"
			"streamRadius,superRadius,uploadsCap,uploadMs,"
			"waterActive,waterUnits,waterPlaced,waterForgotten,waterDelta\n");
		FFileHelper::SaveStringToFile(Header, *Path); // overwrite: fresh file
		bPerfCsvStarted = true;
	}

	// Per-LOD column histogram (same buckets as LogStreamingStats).
	int32 LodHist[4] = { 0, 0, 0, 0 };
	for (const TPair<FIntPoint, int32>& Pair : ColumnLod)
	{
		++LodHist[FMath::Clamp(Pair.Value, 0, 3)];
	}

	// Cross-fades vs swap-holds in progress — the LOD-transition health signal. A hole on a
	// LOD swap shows up here as a hold (bHoldOnly) that lingers because its incoming mesh is
	// slow to upload, or as a cross-fade when bEnableLodFade is on.
	int32 Holds = 0, Fades = 0;
	for (const FFadeRecord& F : ActiveFades)
	{
		if (F.bHoldOnly) { ++Holds; } else { ++Fades; }
	}

	const FMiraFarRenderStats Far = GetFarRenderStats();
	const double NowS = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
	const float  Fps  = (PerfCsvWorstMsInterval > 0.0f)
		? (1000.0f / FMath::Max(0.001f, PerfCsvWorstMsInterval)) // FPS at this interval's WORST frame (the honest floor)
		: 0.0f;

	// Water sim load (zeros when the sim isn't built/enabled).
	int32 WActive = 0, WUnits = 0, WPlaced = 0, WForgot = 0, WDelta = 0;
	if (bEnableWaterSim && WaterSim.IsValid())
	{
		const mira::FiniteWaterCore::Stats WS = WaterSim->stats();
		WActive = WS.active; WUnits = WS.units; WPlaced = WS.placed;
		WForgot = WS.forgotten; WDelta = WaterSim->conservation_delta();
	}

	const FString Row = FString::Printf(
		TEXT("%.1f,%.0f,%.1f,%.1f,%d,%d,%d,")
		TEXT("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,")
		TEXT("%d,%d,%d,%d,%d,%d,%d,%d,")
		TEXT("%d,%d,%d,%d,%d,%d,")
		TEXT("%d,%d,%d,%.1f,")
		TEXT("%d,%d,%d,%d,%d\n"),
		NowS, Fps, PerfCsvWorstMsInterval, Far.WorstLoadFrameMs,
		FilledColumns.Num(), MeshedColumns.Num(), ChunkActors.Num(),
		LodHist[0], LodHist[1], LodHist[2], LodHist[3],
		Far.SuperActorsTotal, Far.SuperByLod[0], Far.SuperByLod[1], Far.SuperByLod[2],
		Far.SuperByLod[3], Far.SuperByLod[4], Far.SuperByLod[5],
		Far.CoarseGenColumns, Far.ShellCulledColumns, Fades, Holds,
		Far.GenOpsThisTick, Far.MeshOpsThisTick, Far.JobsInFlight, Far.Pending,
		PendingGen.Num(), PendingMesh.Num(), PendingSuperMesh.Num(),
		InFlightColumns.Num(), InFlightMeshColumns.Num(), InFlightSuperMeshes.Num(),
		StreamRadiusChunks, SuperRadiusChunks, MaxColumnMeshUploadsPerTick, MeshUploadBudgetMs,
		WActive, WUnits, WPlaced, WForgot, WDelta);

	FFileHelper::SaveStringToFile(Row, *Path, FFileHelper::EEncodingOptions::AutoDetect,
		&IFileManager::Get(), EFileWrite::FILEWRITE_Append);
}

// ---------------------------------------------------------------------------
// Hole detector (TOOL 4). Scan the near band for columns that SHOULD be on screen
// (in-radius AND their voxels are generated) but have NO mesh — the "random holes".
// For each, log the REASON it's stuck so the cause is captured the next time one
// appears, instead of us guessing. Read-only: inspects existing streaming state only.
// ---------------------------------------------------------------------------
void AVoxelWorld::ScanForHoles()
{
	FIntPoint Focus;
	if (!GetFocusChunkXZ(Focus)) { return; }
	const int32 Radius = (HoleScanRadiusChunks > 0) ? HoleScanRadiusChunks
	                                                 : NearFullDepthRadiusChunks;

	// Columns whose worker mesh is FINISHED and is only waiting for the upload harvest
	// (distinguish "the GPU upload is backed up" from "a worker is still building it").
	TSet<FIntPoint> ReadyWaiting;
	for (const FPendingMesh& P : PendingMesh)
	{
		if (P.Future.IsReady()) { ReadyWaiting.Add(P.Key); }
	}

	int32 Holes = 0, Logged = 0;
	const int32 MaxLog = 12; // cap per-scan lines so the log can't flood
	for (int32 dx = -Radius; dx <= Radius; ++dx)
	for (int32 dz = -Radius; dz <= Radius; ++dz)
	{
		const int32 dist = FMath::Max(FMath::Abs(dx), FMath::Abs(dz));
		if (dist > Radius) { continue; }
		const FIntPoint Col(Focus.X + dx, Focus.Y + dz);
		if (!FilledColumns.Contains(Col)) { continue; } // not generated yet — a fill backlog, not a hole
		if (MeshedColumns.Contains(Col))  { continue; } // has a mesh — not a hole
		++Holes;
		if (Logged >= MaxLog) { continue; }
		const TCHAR* Why;
		if (ReadyWaiting.Contains(Col))             { Why = TEXT("ready-waiting-upload(harvest backlog)"); }
		else if (InFlightMeshColumns.Contains(Col)) { Why = TEXT("meshing-on-worker"); }
		else                                        { Why = TEXT("NOT-QUEUED(starved/evicted/never-enqueued)"); }
		const int32* GenL = ColumnGenLod.Find(Col);
		UE_LOG(LogTemp, Warning,
			TEXT("[MiraThal] HOLE? col=(%d,%d) dist=%d genLod=%d reason=%s"),
			Col.X, Col.Y, dist, GenL ? *GenL : -1, Why);
		++Logged;
	}
	if (Holes > 0)
	{
		UE_LOG(LogTemp, Warning,
			TEXT("[MiraThal] HOLE SCAN: %d filled-but-unmeshed columns within %d chunks of focus (logged %d) | pendMesh=%d inFlightMesh=%d uploadsCap=%d"),
			Holes, Radius, FMath::Min(Holes, MaxLog),
			PendingMesh.Num(), InFlightMeshColumns.Num(), MaxColumnMeshUploadsPerTick);
	}
}

// ===========================================================================
// Dynamic water (M3b) — FiniteWaterCore pour-and-settle.
//
// The ledger-based sim flows water DOWN first, then sideways toward lower
// neighbours, conserving every unit. The mesher draws a cell's level (1..8) as a
// partial-height cubic water voxel, so a settling pool reads as discrete water
// cubes filling bottom-up — the look in the reference screenshots. The generated
// ocean is the infinite SOURCE; carving next to it seeds finite water so the
// parent volume floods the opening (FloodCarveFromNeighbours).
// ===========================================================================
void AVoxelWorld::EnsureWaterSim()
{
	if (WaterSim.IsValid())
	{
		return;
	}
	using namespace mira;
	const Brickmap* BM = &WorldStore;
	// solid = any non-air terrain blocks water; source = ocean SOURCE bytes.
	//
	// UNLOADED-AS-SOLID CLAMP (the load-bearing streaming fix). A voxel whose XZ
	// column has NOT been streamed in (not in FilledColumns) reads as SOLID, never
	// AIR. Without this, water poured/flowing toward the loaded-world edge would
	// see the ungenerated void as open air and pour into it, silently LOSING volume
	// (the void brick reads type 0 == AIR by default). Treating unloaded columns as
	// a wall makes the sim pool against the frontier exactly as it would against
	// real terrain — and when that column later streams in, ApplyColumnResult wakes
	// the boundary cells so the pool flows onward. We capture `this` (the sim's
	// lifetime is owned by this actor), and the loaded-voxel behaviour
	// (type_at(p) != AIR) is unchanged for any column that IS filled.
	auto SolidFn  = [this, BM](const Vec3i& p) -> bool
	{
		const FIntPoint Col(coords::floor_div(p.x, coords::CHUNK),
		                    coords::floor_div(p.z, coords::CHUNK));
		if (!FilledColumns.Contains(Col))
		{
			return true; // ungenerated/unloaded column — treat as solid wall
		}
		return BM->type_at(p) != mat::AIR;
	};
	auto SourceFn = [BM](const Vec3i& p) { return WaterByteCodec::is_source(BM->water_at(p)); };
	WaterSim = MakeUnique<FiniteWaterCore>(SolidFn, SourceFn);
}

void AVoxelWorld::ActivateColumnSeamWater(const FIntPoint& Col, int32 ChunkYLo, int32 ChunkYHi)
{
	using namespace mira;
	if (!bEnableWaterSim || !WaterSim.IsValid())
	{
		return;
	}

	const Vec3i Origin = coords::chunk_origin_voxel(Vec3i(Col.X, 0, Col.Y));
	const int x0 = Origin.x, x1 = Origin.x + coords::CHUNK - 1; // inclusive XZ box
	const int z0 = Origin.z, z1 = Origin.z + coords::CHUNK - 1;
	const int y0 = ChunkYLo * coords::CHUNK;
	const int y1 = (ChunkYHi + 1) * coords::CHUNK - 1;

	// Outward face-normals for the 4 horizontal sides; only those reach a neighbour
	// column. (Up/down neighbours are in THIS column, already coherent.)
	auto neighbour_loaded = [this](int wx, int wz) -> bool
	{
		return FilledColumns.Contains(FIntPoint(coords::floor_div(wx, coords::CHUNK),
		                                        coords::floor_div(wz, coords::CHUNK)));
	};

	// Walk the 1-voxel OUTER ring of the column at every y in span. When this seam
	// voxel holds water AND its outward neighbour now lies in a filled column, wake
	// BOTH sides: activate() the seam cell here AND the neighbour cell across the
	// seam. The neighbour side is the load-bearing one — a pool in the ALREADY-loaded
	// column that went dormant clamped against THIS column (which used to read as a
	// SOLID wall) is a ledger cell there; activate() re-arms it + its ledger
	// neighbours so it flows into the freshly-opened column. activate() is a safe
	// no-op on any cell that isn't a tracked ledger cell, so waking the local seam
	// cell too costs nothing when it isn't sim-tracked.
	auto consider = [&](int wx, int wy, int wz, int nx, int nz)
	{
		const Vec3i P(wx, wy, wz);
		const Vec3i N(nx, wy, nz);
		const bool bHereWater = WaterByteCodec::is_water(WorldStore.water_at(P));
		const bool bNbrWater  = WaterByteCodec::is_water(WorldStore.water_at(N));
		if (!bHereWater && !bNbrWater)
		{
			return; // no water on either side of this seam voxel — nothing to wake
		}
		if (neighbour_loaded(nx, nz))
		{
			WaterSim->activate(P); // re-arm this cell + its ledger neighbours
			WaterSim->activate(N); // re-arm the across-seam pool (the clamped side)
		}
	};

	for (int wy = y0; wy <= y1; ++wy)
	{
		// -X and +X edges
		for (int wz = z0; wz <= z1; ++wz)
		{
			consider(x0, wy, wz, x0 - 1, wz);
			consider(x1, wy, wz, x1 + 1, wz);
		}
		// -Z and +Z edges
		for (int wx = x0; wx <= x1; ++wx)
		{
			consider(wx, wy, z0, wx, z0 - 1);
			consider(wx, wy, z1, wx, z1 + 1);
		}
	}
}

int AVoxelWorld::StepWaterSim(int32 steps, int32 budget)
{
	using namespace mira;
	if (!WaterSim.IsValid() || steps <= 0)
	{
		return 0;
	}

	// (a) Settled-world early-out: if there are no active cells the sim has nothing
	//     to do, so a fully-settled world costs ~nothing per tick (no step, no
	//     iteration). This is what keeps the always-on Tick cheap once water rests.
	if (WaterSim->is_settled())
	{
		return 0;
	}

	// (b) STREAMING-RADIUS GATE. Work out the focus chunk-XZ so we can keep the sim
	//     bounded to a NEAR BAND: a change whose chunk-XZ is farther than
	//     WaterSimRadiusChunks from the focus is NOT applied/re-meshed, and those
	//     cells are forgotten from the live ledger so the active set can't grow
	//     past the band (e.g. a long waterfall marching off toward the horizon).
	//     If no focus is available (editor/no pawn) the gate is disabled — the
	//     editor pour buttons settle the whole sim as before.
	FIntPoint Focus;
	const bool bHaveFocus = GetFocusChunkXZ(Focus);
	const int32 GateR = FMath::Max(1, WaterSimRadiusChunks);

	// Collect the chunks any change touched across all the steps, then re-mesh
	// each once (a cell can change several times; we only need one re-mesh).
	TSet<FIntVector> Dirty;
	for (int32 s = 0; s < steps; ++s)
	{
		FiniteWaterCore::StepResult R = WaterSim->step(budget);
		for (const FiniteWaterCore::Change& C : R.changes)
		{
			// Outside the near band? Forget the cell (so the ledger stays bounded)
			// and skip its world-write + re-mesh. forget_region tallies the dropped
			// units into `forgotten` so conservation still balances.
			if (bHaveFocus)
			{
				const int32 ccx = coords::floor_div(C.pos.x, coords::CHUNK);
				const int32 ccz = coords::floor_div(C.pos.z, coords::CHUNK);
				if (FMath::Max(FMath::Abs(ccx - Focus.X), FMath::Abs(ccz - Focus.Y)) > GateR)
				{
					WaterSim->forget_region(C.pos, C.pos);
					continue;
				}
			}
			// Write the projected byte into the authoritative store.
			WorldStore.set_water(C.pos, static_cast<uint8_t>(C.byte));
			// Every chunk this voxel borders (apron-aware) needs a re-mesh.
			std::vector<Vec3i> Touched;
			chunks_touched_by_voxel(C.pos, Touched);
			for (const Vec3i& T : Touched)
			{
				Dirty.Add(FIntVector(T.x, T.y, T.z));
			}
		}
		if (R.changes.empty())
		{
			break; // settled — nothing left to do
		}
	}

	for (const FIntVector& C : Dirty)
	{
		RemeshChunk(C);
	}
	return Dirty.Num();
}

void AVoxelWorld::PourWaterAtWorld(const FVector& WorldPos, int32 Units)
{
	using namespace mira;
	EnsureWaterSim();

	// UE world (cm) -> core voxel (same mapping as CarveAtWorld).
	const FVector Local = WorldPos - GetActorLocation();
	const Vec3i Cell(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));

	WaterSim->place(Cell, FMath::Max(1, Units));

	// PERSISTENCE (seed only). Journal the cells this POUR seeded so a player's pour
	// survives reload. place() fills `Cell` then stacks any excess straight up, so we
	// walk that same upward column and, for each cell the sim now tracks, write its
	// projected byte into the world store and RecordEdit it. Only the SEED is
	// journalled — the transient FLOW the sim then runs is NOT recorded (that would
	// bloat the EditStore every tick; StepWaterSim deliberately leaves flow
	// un-journalled). On reload these seeds replay and the sim re-flows from them.
	if (bPersistEdits)
	{
		for (int32 k = 0; k < 256; ++k)
		{
			const Vec3i P = Cell + Vec3i(0, k, 0);
			if (!WaterSim->has_cell(P))
			{
				break; // top of the seeded column reached
			}
			WorldStore.set_water(P, static_cast<uint8_t>(WaterSim->projected_byte(P)));
			RecordEdit(P);
		}
	}

	// In the editor (no play tick) settle synchronously so it's visible at once.
	if (!GetWorld() || !GetWorld()->IsGameWorld())
	{
		StepWaterSim(120, WaterStepBudget);
	}
}

void AVoxelWorld::PourTestWater()
{
	using namespace mira;
	EnsureWaterSim();

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int GroundCentre = Gen.compute_ground_y(0, 0);

	// Drop a column a few voxels above the centre surface; it collapses + spreads.
	const Vec3i Top(0, GroundCentre + 6, 0);
	WaterSim->place(Top, FMath::Max(1, TestPourUnits));

	// Settle synchronously so the editor button shows the result immediately.
	StepWaterSim(160, WaterStepBudget);
}

void AVoxelWorld::FloodCarveFromNeighbours(const std::vector<mira::VoxelWrite>& Writes)
{
	using namespace mira;
	if (!bEnableWaterSim)
	{
		return; // water flooding is opt-in
	}
	EnsureWaterSim();

	// Sea level from the configured generator (cheap; defaults to 120 = 12 m).
	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int SeaY = Gen.sea_level_voxels;

	static const Vec3i N6[6] = {
		{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}
	};

	bool bSeeded = false;
	for (const VoxelWrite& W : Writes)
	{
		if (W.value != mat::AIR)
		{
			continue; // only newly-opened air can take water
		}
		const Vec3i P = W.pos;
		if (P.y > SeaY)
		{
			continue; // never flood above sea level
		}
		if (WorldStore.type_at(P) != mat::AIR || WaterByteCodec::is_water(WorldStore.water_at(P)))
		{
			continue; // still solid, or already water
		}
		// Any face-neighbour that already holds water? Then the parent volume can
		// feed this opening — seed it full and let the sim flow it down + level.
		bool bWaterAdjacent = false;
		for (const Vec3i& D : N6)
		{
			if (WaterByteCodec::is_water(WorldStore.water_at(P + D)))
			{
				bWaterAdjacent = true;
				break;
			}
		}
		if (bWaterAdjacent)
		{
			WaterSim->place(P, WaterByteCodec::MAX_LEVEL);
			bSeeded = true;
		}
	}

	if (bSeeded && (!GetWorld() || !GetWorld()->IsGameWorld()))
	{
		// Editor (no tick): settle now so the flood is visible from the button.
		StepWaterSim(160, WaterStepBudget);
	}
}

// ===========================================================================
// Persistence (P2) — journal the player's edits, replay them on load.
// ===========================================================================
void AVoxelWorld::RecordEdit(const mira::Vec3i& Voxel)
{
	// Store the voxel's FINAL state (post-carve/place) so replay reproduces it.
	EditStore.record(Voxel, WorldStore.type_at(Voxel), WorldStore.water_at(Voxel));
}

void AVoxelWorld::EnsureEditRegionLoaded(const FIntPoint& Region)
{
	using namespace mira;
	if (LoadedEditRegions.Contains(Region))
	{
		return; // already attempted this session
	}
	LoadedEditRegions.Add(Region);

	std::vector<uint8_t> Bytes;
	if (!MiraWorldPersist::LoadRegion(WorldSaveName, Region, Bytes))
	{
		return; // no file = never-edited region (normal)
	}
	std::vector<region::VoxelEdit> Edits;
	if (region::decode_delta_log(Bytes, Edits))
	{
		EditStore.load_region(Vec3i(Region.X, 0, Region.Y), Edits);
	}
	else
	{
		UE_LOG(LogTemp, Warning,
			TEXT("[MiraThal] corrupt region delta r_%d_%d.delta — ignored"),
			Region.X, Region.Y);
	}
}

void AVoxelWorld::ApplyEditsToColumn(int32 ccx, int32 ccz)
{
	using namespace mira;
	const Vec3i Origin = coords::chunk_origin_voxel(Vec3i(ccx, 0, ccz));
	const int x0 = Origin.x, x1 = Origin.x + coords::CHUNK;
	const int z0 = Origin.z, z1 = Origin.z + coords::CHUNK;

	// Make sure every region tile overlapping this column has been read from disk.
	const int RS = WorldEditStore::REGION_SIZE;
	const int rx0 = coords::floor_div(x0, RS), rx1 = coords::floor_div(x1 - 1, RS);
	const int rz0 = coords::floor_div(z0, RS), rz1 = coords::floor_div(z1 - 1, RS);
	for (int rx = rx0; rx <= rx1; ++rx)
	for (int rz = rz0; rz <= rz1; ++rz)
	{
		EnsureEditRegionLoaded(FIntPoint(rx, rz));
	}

	// Replay exactly the edits in this column's footprint onto the brickmap.
	EditStore.apply_xz_box(x0, x1, z0, z1, WorldStore);
}

void AVoxelWorld::SaveEdits()
{
	using namespace mira;
	if (!bPersistEdits)
	{
		return;
	}
	int Saved = 0;
	for (const Vec3i& R : EditStore.dirty_regions())
	{
		const std::vector<region::VoxelEdit> List = EditStore.region_edit_list(R);
		const std::vector<uint8_t> Bytes = region::encode_delta_log(List);
		if (MiraWorldPersist::SaveRegion(WorldSaveName, FIntPoint(R.x, R.z), Bytes))
		{
			EditStore.mark_clean(R);
			++Saved;
		}
	}
	if (Saved > 0)
	{
		UE_LOG(LogTemp, Display, TEXT("[MiraThal] saved %d edited region(s) -> %s"),
			Saved, *MiraWorldPersist::WorldDir(WorldSaveName));
	}
}

// ===========================================================================
// Gravity-on-dig (M3c) — loose material slides down when its support is gone.
// ===========================================================================
void AVoxelWorld::ApplyGravityAfterCarve(const mira::Vec3i& CarveCenterVoxel)
{
	using namespace mira;
	if (!bEnableGravity)
	{
		return;
	}

	// Analyse a cube around the dig. Anchor seed is the bubble's bottom face (y==0),
	// so place the bubble with solid ground below the carve: the carve sits ~3/4 up.
	constexpr int kSide = 32;
	const Vec3i Origin(CarveCenterVoxel.x - kSide / 2,
	                   CarveCenterVoxel.y - (kSide * 3) / 4,
	                   CarveCenterVoxel.z - kSide / 2);

	auto get_packed = [this, Origin](const Vec3i& local) -> int32_t {
		return static_cast<int32_t>(WorldStore.type_at(Origin + local));
	};
	auto fall_of = [](int id) -> int {
		// Only sand + gravel are loose; everything else holds (no rigid collapse v1).
		if (id == mat::SAND || id == 7 /*gravel*/) return FALL_LOOSE;
		return FALL_NEVER;
	};

	const GravityResult Res = analyze_bubble(kSide, get_packed, fall_of);
	if (Res.loose.empty())
	{
		return; // nothing slid
	}

	// Apply the slides into the brickmap: clear every source, then write every
	// destination (two passes so a cell that is both source and dest resolves).
	std::vector<Vec3i> Touched;
	Touched.reserve(Res.loose.size() * 2);
	for (const LooseMove& m : Res.loose)
	{
		const Vec3i From = Origin + m.from;
		WorldStore.set_type(From, static_cast<uint8_t>(mat::AIR));
		Touched.push_back(From);
		if (bPersistEdits) { RecordEdit(From); }
	}
	for (const LooseMove& m : Res.loose)
	{
		const Vec3i To = Origin + m.to;
		WorldStore.set_type(To, static_cast<uint8_t>(m.packed & 0xFF));
		Touched.push_back(To);
		if (bPersistEdits) { RecordEdit(To); }
	}

	// Re-mesh every chunk the moved voxels border (apron-aware), de-duplicated.
	TSet<FIntVector> Dirty;
	for (const Vec3i& V : Touched)
	{
		std::vector<Vec3i> Chunks;
		chunks_touched_by_voxel(V, Chunks);
		for (const Vec3i& C : Chunks) { Dirty.Add(FIntVector(C.x, C.y, C.z)); }
	}
	for (const FIntVector& C : Dirty)
	{
		RemeshChunk(C);
	}
}
