<#
  Rebake-Terrain.ps1 - whole-map Nanite crust bake, optionally across N parallel processes.

  Each process bakes a shard of the tile grid (flat index mod N) into the shared folder and
  writes a text manifest-shard; a final -Merge pass builds the real Manifest.uasset. This is
  how a 10cm global drops from ~15h (single) to ~1-2h (many cores).

  USAGE (normally launched from Bake-Terrain-Menu.bat / Rebake-Terrain.bat):
    powershell -ExecutionPolicy Bypass -File Rebake-Terrain.ps1 -CubeCm 80 [-Name x] [-Jobs n] [-Skirt v]

  Close the GUI editor first. Jobs defaults to (logical cores - 2).
#>
param(
  [int]$CubeCm = 80,
  [string]$Name = "",
  [int]$Jobs = 0,
  [int]$Skirt = 0,
  [int]$Region = -1,  # tiles/side packed into one file; -1 = auto (on for fine res), 0 = off
  [int]$Nanite = -1,  # 1=Nanite, 0=plain (faster build, coarse tiers); -1 = auto (off for >=1.6m)
  [switch]$GeoMerge,  # FUSE each region's tiles into ONE mesh + ONE manifest entry (shipping-scale
                      # asset-count reduction; coarser streaming). Forces region packing on. Default off.
  [int]$ShardTiles = 2000  # tiles per parallel shard. Peak RAM/shard scales with this (region-pack +
                           # geo-merge hold a shard's meshes resident until save). Lower it for HEAVY
                           # bakes (fine cubes mesh ~10x bigger): ~500 keeps 4 jobs safe on this box.
)
$ErrorActionPreference = "Stop"
$Root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$UECmd = "D:\UE5\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$Proj  = Join-Path $Root "ue5\MiraThal\MiraThal.uproject"
$Map   = "/Game/Maps/MiraStreamTest"
$Saved = Join-Path $Root "ue5\MiraThal\Saved"
$ShardDir = Join-Path $Saved "BakeShards"
$LogDir   = Join-Path $Saved "Logs"

if (-not (Test-Path $UECmd)) { Write-Error "UnrealEditor-Cmd not found at $UECmd"; exit 1 }

# --- derive bake params from the cube size (10 voxels / metre => 10cm voxels) ---
if ($Name -eq "")   { $Name   = "MiraStreamTest_${CubeCm}cm" }
$Stride   = [Math]::Max(1, [int]($CubeCm / 10))
$TileSpan = 96 * $Stride                       # coarse_side 96 -> fewest files
$Radius   = [int](25000 / $TileSpan) + 2       # 2500m half-map = 25000 voxels; clip trims overflow
if ($Skirt -le 0) { $Skirt = [Math]::Max(8, 4 * $Stride) }  # ~4 cubes deep, scales with resolution

# --- GUARD: bake output lives under Content\VoxelBake, which is a JUNCTION to D:\MiraThalVoxelBake
#     (keeps the multi-GB bakes off the small C: drive). If that D: target ever gets deleted, the
#     junction dangles and EVERY mesh save fails silently with "path not found" (Error Code 3) - the
#     bake runs for hours and produces NOTHING. So heal the simple case (target exists, subdir doesn't)
#     and HARD-FAIL with a clear message if the junction itself is broken, instead of wasting the run. ---
$OutDir = Join-Path $Root "ue5\MiraThal\Content\VoxelBake\$Name"
try { New-Item -ItemType Directory -Force -Path $OutDir -ErrorAction Stop | Out-Null } catch {}
if (-not (Test-Path $OutDir)) {
  Write-Error ("Cannot create bake output '$OutDir'. Content\VoxelBake is a junction to " +
    "D:\MiraThalVoxelBake and that target is MISSING. Recreate it first:`n" +
    "    New-Item -ItemType Directory -Force -Path D:\MiraThalVoxelBake`n" +
    "then re-run this bake.")
  exit 1
}

# --- did the user explicitly pass -Jobs / -ShardTiles? If so we NEVER override their numbers below.
#     ($Jobs=0 is the "auto" sentinel; ShardTiles defaults to 2000 but we treat any explicit value as
#      an override even if it equals 2000.) ---
$JobsAuto       = (-not $PSBoundParameters.ContainsKey('Jobs'))       -or ($Jobs -le 0)
$ShardTilesAuto = (-not $PSBoundParameters.ContainsKey('ShardTiles'))

# --- MEMORY-SAFE AUTO-TUNING (jobs + shard size), by BAKE TYPE ---------------------------------------
# The RAM a single shard peaks at depends HEAVILY on WHAT it bakes, not just on tile count:
#   * GEO-MERGE fuses each region's tiles into one giant Nanite mesh (~1.6M verts) during its flush -
#     very RAM-heavy. Empirical anchor: geo-merge @ 40cm peaked ~9.5GB/shard at 400 tiles (~4 jobs
#     safe on a 64GB box; 6 jobs THRASHED).
#   * A normal (non-geo-merge) bake is far lighter per shard.
#   * After the mesher fix, FINE cubes (small -CubeCm) build ~10x heavier meshes than coarse ones, so
#     finer = more memory. We scale by how fine the cube is relative to the 40cm anchor.
# A big Windows pagefile raises the COMMIT limit (stops the hard crash) but adds NO physical RAM, so we
# size jobs against PHYSICAL RAM, the real ceiling for these heavy merged-mesh builds.
$cores      = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$physBytes  = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$physGB     = [math]::Round($physBytes / 1GB, 0)
$OS_HEADROOM_GB = 16  # Windows + merge pass + the transient init/RHI spikes that overlap the resident
                      # set (the proven figure: this is what kept the old 64GB tuning safe).

# Per-shard peak RAM model:  perShardGB = base + perTileMB/1024 * shardTiles, where per-tile cost is
# scaled by bake type (geo-merge ~5x heavier) and by fineness (finer cube => heavier mesh, vs 40cm).
# 'base' is the per-process floor EVERY job holds: editor + RHI + DDC/file cache (~3.5-5GB, and it
# ALSO spikes ~10-11GB transiently at init - that's why launches are staggered). The mesh term is the
# resident built geometry on top of that.
# Anchor: geo-merge @ 40cm, 400 tiles peaked ~9.5GB/shard and 4 jobs was safe on 64GB (6 thrashed).
#   base 5.0 + (12MB * 400 / 1024) = ~9.7GB/shard -> floor((64-16)/9.7) = 4 jobs. Matches reality.
$fineScale = [Math]::Max(1.0, 40.0 / [Math]::Max(10, $CubeCm))   # 40cm=1.0, 20cm=2.0, 10cm=4.0 heavier
$baseGB    = if ($GeoMerge) { 5.0 } else { 4.0 }                 # editor+RHI+cache floor per process
$perTileMB = if ($GeoMerge) { 12.0 } else { 3.0 }               # geo-merge holds fused meshes resident
$perTileMB = $perTileMB * $fineScale

function Get-ShardGB([int]$tiles) { return $baseGB + ($perTileMB * $tiles / 1024.0) }

# Auto-pick ShardTiles first (smaller shards = less resident memory) for HEAVY bakes, so jobs can stay
# parallel without OOM. Only when the user didn't pass -ShardTiles.
if ($ShardTilesAuto) {
  if ($GeoMerge)        { $ShardTiles = 400 }   # fused-mesh builds are the heaviest; keep shards small
  elseif ($CubeCm -le 20) { $ShardTiles = 800 } # fine non-merge: ~10x meshes, shrink the resident set
  else                  { $ShardTiles = 2000 }  # coarse normal bake: the old safe default
}

if ($JobsAuto) {
  $estShardGB = Get-ShardGB $ShardTiles
  # Jobs = how many shards fit in PHYSICAL RAM after OS headroom; clamp to [1, cores-2].
  $ramJobs = [math]::Floor(($physGB - $OS_HEADROOM_GB) / $estShardGB)
  $Jobs    = [Math]::Max(1, [Math]::Min($cores - 2, $ramJobs))
  $bakeKind = if ($GeoMerge) { "geo-merge" } elseif ($CubeCm -le 20) { "fine" } else { "normal" }
  Write-Host ("  auto-tune: jobs={0}  shardTiles={1}  ({2} bake, ~{3}GB/shard est; phys={4}GB, headroom={5}GB, cores-2={6})" -f `
              $Jobs,$ShardTiles,$bakeKind,[math]::Round($estShardGB,1),$physGB,$OS_HEADROOM_GB,($cores-2))
} else {
  Write-Host ("  jobs={0} (explicit)  shardTiles={1} ({2})" -f $Jobs,$ShardTiles,(if ($ShardTilesAuto) { "auto" } else { "explicit" }))
}
# Region packing: auto-ON (8x8 tiles/file) for fine resolutions that would blow the file wall.
if ($Region -lt 0) { if ($CubeCm -le 20) { $Region = 8 } else { $Region = 0 } }
# Geometry merge NEEDS region packing (it fuses a region's tiles) — force a region size on if asked
# for without one. The pass-through switch is added to each bake process's args (not the pre-warm).
if ($GeoMerge -and $Region -le 0) { $Region = 8 }
$GeoArg = if ($GeoMerge) { "-GeoMerge" } else { $null }
# Nanite auto: ON for fine/near tiers (lots of geometry to LOD), OFF for coarse far tiers (>=1.6m,
# few triangles) where a plain static mesh builds far faster and needs no sub-pixel LOD.
if ($Nanite -lt 0) { if ($CubeCm -ge 160) { $Nanite = 0 } else { $Nanite = 1 } }
$Side  = 2 * $Radius + 1
$Tiles = $Side * $Side

Write-Host ""
Write-Host "==================== PARALLEL TERRAIN BAKE ===================="
Write-Host ("  cube={0}cm  stride={1}  tileSpan={2}  radius={3}  skirt={4}" -f $CubeCm,$Stride,$TileSpan,$Radius,$Skirt)
$regionMsg = if ($Region -gt 0) { "$Region x $Region tiles/file" } else { "one file per tile" }
Write-Host ("  name={0}   jobs={1}   ~maxTiles={2}   region-pack: {3}" -f $Name,$Jobs,$Tiles,$regionMsg)
Write-Host "==============================================================="
Write-Host ""

New-Item -ItemType Directory -Force -Path $ShardDir | Out-Null
Get-ChildItem -Path $ShardDir -Filter "${Name}_shard*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$sw = [System.Diagnostics.Stopwatch]::StartNew()

if ($Jobs -le 1) {
  # Single process: direct bake (writes the manifest itself, no shards/merge).
  Write-Host "  Single-process bake..."
  $a = @("`"$Proj`"","-run=VoxelCrustBake","-Map=$Map","-WorldSaveName=$Name",
         "-Tile=$TileSpan","-Stride=$Stride","-Skirt=$Skirt","-Radius=$Radius","-Region=$Region","-Nanite=$Nanite","-AllowCommandletRendering",
         "-unattended","-nopause","-nosplash","-abslog=`"$LogDir\bake_$Name.log`"")
  if ($GeoArg) { $a += $GeoArg }
  $p = Start-Process -FilePath $UECmd -ArgumentList $a -PassThru -WindowStyle Hidden -Wait
  Write-Host ("  done in {0}s  (exit {1})  -> /Game/VoxelBake/{2}" -f [int]$sw.Elapsed.TotalSeconds,$p.ExitCode,$Name)
  exit $p.ExitCode
}

# --- PRE-WARM the shader cache with ONE process before fanning out, so the N parallel processes
#     reuse the warm DDC instead of each compiling shaders simultaneously (the big startup tax + a
#     CPU/DDC contention + memory-spike risk). Builds 1 real tile near origin into a throwaway layer
#     (compiles the Nanite-build shaders into the shared DDC), then deletes it. One-time after a code
#     rebuild / cold cache; later bakes find the DDC already warm and skip the heavy compile. ---
Write-Host "  pre-warming shader cache (1 process; one-time after a rebuild / cold cache)..."
$warmName = "__warmup_$Name"
$wa = @("`"$Proj`"","-run=VoxelCrustBake","-Map=$Map","-WorldSaveName=$warmName",
        "-Tile=$TileSpan","-Stride=$Stride","-Skirt=$Skirt","-Radius=2","-MaxTiles=1","-Region=0",
        "-AllowCommandletRendering","-unattended","-nopause","-nosplash",
        "-abslog=`"$LogDir\bake_${Name}_warmup.log`"")
Start-Process -FilePath $UECmd -ArgumentList $wa -WindowStyle Hidden -Wait | Out-Null
$warmDir = Join-Path $Root "ue5\MiraThal\Content\VoxelBake\$warmName"
if (Test-Path $warmDir) { Remove-Item -Recurse -Force $warmDir -ErrorAction SilentlyContinue }
Write-Host ("  pre-warm done ({0}s); launching {1} warm shards..." -f [int]$sw.Elapsed.TotalSeconds,$Jobs)

# --- BATCHED sharding: split into MANY SMALL shards run only $Jobs CONCURRENTLY. Each shard exits
#     and frees its memory before the next batch, so the 270k+ tiles of a 10cm bake never pile up
#     resident. SHARD SIZE IS MEMORY-CRITICAL: region-packing holds ALL of a shard's built meshes
#     resident until its end-of-loop save, so peak-RAM-per-shard scales with tiles-per-shard. The
#     80cm bake ran fine at ~1200 tiles/shard (4700 tiles / 4 jobs); a first 10cm attempt at 6000
#     tiles/shard x 4 concurrent blew the 64GB+small-pagefile commit limit. So we cap per-shard at
#     ~2000 tiles (4 lanes x ~2000 stays well under the limit; coarse bakes have few tiles so they
#     just become one small shard, no penalty). Raise SHARD_TILES only with a big pagefile / more RAM. ---
$SHARD_TILES = [Math]::Max(100, $ShardTiles)
$concurrent  = $Jobs
$estTiles    = (2*$Radius+1)*(2*$Radius+1)
$TotalShards = [Math]::Max($concurrent, [int][Math]::Ceiling($estTiles / [double]$SHARD_TILES))
$perShard    = [int][Math]::Ceiling($estTiles / $TotalShards)
Write-Host ("  batched sharding: {0} shards (~{1} tiles each), {2} concurrent" -f $TotalShards,$perShard,$concurrent)

$shard = 0
$batchNo = 0
while ($shard -lt $TotalShards) {
  $batchNo++
  $batch = @()
  for ($k = 0; ($k -lt $concurrent) -and ($shard -lt $TotalShards); $k++) {
    $a = @("`"$Proj`"","-run=VoxelCrustBake","-Map=$Map","-WorldSaveName=$Name",
           "-Tile=$TileSpan","-Stride=$Stride","-Skirt=$Skirt","-Radius=$Radius","-Region=$Region","-Nanite=$Nanite","-AllowCommandletRendering",
           "-Shards=$TotalShards","-Shard=$shard",
           "-unattended","-nopause","-nosplash","-abslog=`"$LogDir\bake_${Name}_shard$shard.log`"")
    if ($GeoArg) { $a += $GeoArg }
    $p = Start-Process -FilePath $UECmd -ArgumentList $a -PassThru -WindowStyle Hidden
    $batch += $p
    $shard++
    # STAGGER: editor+RHI init spikes ~10-11GB transiently; launching all at once aligns the spikes
    # and exhausts the commit limit. Space launches so each finishes its init before the next spikes.
    if (($k -lt ($concurrent - 1)) -and ($shard -lt $TotalShards)) { Start-Sleep -Seconds 12 }
  }
  $batch | Wait-Process
  Write-Host ("  batch {0} done: {1}/{2} shards finished ({3}s elapsed)" -f $batchNo,$shard,$TotalShards,[int]$sw.Elapsed.TotalSeconds)
}
$bakeSecs = [int]$sw.Elapsed.TotalSeconds
# Success judged by OUTPUT (shard files / merge log), not the spurious commandlet exit codes.
$shardCount = (Get-ChildItem -Path $ShardDir -Filter "${Name}_shard*.txt" -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host ("  all {0} shards finished in {1}s; {2} shard files written. Merging..." -f $TotalShards,$bakeSecs,$shardCount)
if ($shardCount -eq 0) { Write-Host "  ERROR: no shard files written - see Saved\Logs\bake_${Name}_shard*.log"; exit 1 }

$mergeLog = Join-Path $LogDir "bake_${Name}_merge.log"
$ma = @("`"$Proj`"","-run=VoxelCrustBake","-WorldSaveName=$Name","-Merge",
        "-unattended","-nopause","-nosplash","-abslog=`"$mergeLog`"")
Start-Process -FilePath $UECmd -ArgumentList $ma -WindowStyle Hidden -Wait | Out-Null

# Success = the merge logged a saved manifest.
$ok = (Test-Path $mergeLog) -and (Select-String -Path $mergeLog -Pattern "MergeShards:.*saved=1" -Quiet)
Write-Host ""
if ($ok) {
  $m = Select-String -Path $mergeLog -Pattern "MergeShards: \d+ shards -> (\d+) tiles"
  $tiles = if ($m) { $m.Matches[0].Groups[1].Value } else { "?" }
  Write-Host ("  SUCCESS in {0}s  ->  {1} tiles  ->  /Game/VoxelBake/{2}" -f [int]$sw.Elapsed.TotalSeconds,$tiles,$Name)
  Write-Host "  (Point a VoxelNaniteCrust actor's Manifest at it to stream the layer.)"
  exit 0
} else {
  Write-Host ("  MERGE FAILED - see {0}" -f $mergeLog)
  exit 1
}
