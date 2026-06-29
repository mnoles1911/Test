// HeightmapImportTest.cpp — headless automation test that loads the REAL project
// EXR (Content/Heightmaps/Export.exr) through the actual import path and reports
// whether it decodes into sane voxel terrain. Runs with NO editor GUI:
//
//   UnrealEditor-Cmd <project> -ExecCmds="Automation RunTests MiraThal.Heightmap.ImportRealFile; Quit" \
//     -unattended -nullrhi -nosplash -log
//
// This is the headless gate for the EXR import (M3a): it proves the engine can
// decode the designer's Gaea export and that the georef + vertical mapping
// produce believable ground heights, without anyone opening the editor.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "HeightmapImport.h"
#include "Core/ImageHeightmap.h"
#include "Core/HeightmapGenerator.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"

#include <limits>

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
	FMiraThalHeightmapImportRealFileTest,
	"MiraThal.Heightmap.ImportRealFile",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FMiraThalHeightmapImportRealFileTest::RunTest(const FString& /*Parameters*/)
{
	// The file the designer dropped in (Content/Heightmaps/Export.exr).
	const FString Path = FPaths::ProjectContentDir() / TEXT("Heightmaps/Export.exr");
	AddInfo(FString::Printf(TEXT("Heightmap path: %s"), *Path));

	if (!FPaths::FileExists(Path))
	{
		AddError(FString::Printf(TEXT("EXR not found at %s"), *Path));
		return false;
	}

	// --- Decode through the real import path. ---
	mira::ImageHeightmap HM;
	FString LoadError;
	const bool bLoaded = MiraHeightmapImport::LoadHeightmapImage(Path, HM, LoadError);
	TestTrue(TEXT("EXR decoded without error"), bLoaded);
	if (!bLoaded)
	{
		AddError(FString::Printf(TEXT("decode failed: %s"), *LoadError));
		return false;
	}

	TestTrue(TEXT("ImageHeightmap is valid (size matches data)"), HM.valid());
	AddInfo(FString::Printf(TEXT("Decoded %d x %d pixels (%lld values)"),
		HM.width, HM.height, static_cast<long long>(HM.data.size())));

	// --- Scan the raw value range so we know what Gaea exported (0..1? metres?). ---
	float vmin = std::numeric_limits<float>::max();
	float vmax = -std::numeric_limits<float>::max();
	double vsum = 0.0;
	for (float v : HM.data)
	{
		vmin = FMath::Min(vmin, v);
		vmax = FMath::Max(vmax, v);
		vsum += v;
	}
	const double vavg = HM.data.empty() ? 0.0 : vsum / static_cast<double>(HM.data.size());
	AddInfo(FString::Printf(TEXT("Raw value range: min=%.5f max=%.5f avg=%.5f"), vmin, vmax, vavg));
	TestTrue(TEXT("value range is non-degenerate (max > min)"), vmax > vmin);

	// --- Apply the same georef AVoxelWorld uses for a 5 km map at 10 vox/m. ---
	constexpr double VoxelsPerMetre = 10.0;
	constexpr double MapSpanMeters  = 5000.0;
	constexpr double AltitudeMeters = 700.0;
	constexpr double BaseMeters     = 12.0;
	const double SpanVoxels = MapSpanMeters * VoxelsPerMetre;
	HM.set_centered_extent(SpanVoxels, SpanVoxels);
	HM.vertical_scale_voxels = AltitudeMeters * VoxelsPerMetre;
	HM.vertical_base_voxels  = BaseMeters * VoxelsPerMetre;

	AddInfo(FString::Printf(TEXT("Georef: %.3f vox/px, origin (%.0f, %.0f), scale %.0f vox, base %.0f vox"),
		HM.voxels_per_pixel, HM.origin_voxel_x, HM.origin_voxel_z,
		HM.vertical_scale_voxels, HM.vertical_base_voxels));

	// Ground height at the map centre and a few offsets — should be sane voxel Ys.
	const int gC  = HM.height_voxels_at(0, 0);
	const int gN  = HM.height_voxels_at(0,  10000);   // +1 km
	const int gE  = HM.height_voxels_at(10000, 0);
	AddInfo(FString::Printf(TEXT("Ground-Y (voxels): centre=%d, +1km Z=%d, +1km X=%d (sea level=120)"),
		gC, gN, gE));

	// Expected vertical voxel span across the map: base..(base+scale).
	const int gLo = FMath::FloorToInt(static_cast<float>(HM.vertical_base_voxels + vmin * HM.vertical_scale_voxels));
	const int gHi = FMath::FloorToInt(static_cast<float>(HM.vertical_base_voxels + vmax * HM.vertical_scale_voxels));
	AddInfo(FString::Printf(TEXT("Terrain ground-Y span: %d .. %d voxels (%.0f .. %.0f m)"),
		gLo, gHi, gLo / VoxelsPerMetre, gHi / VoxelsPerMetre));
	TestTrue(TEXT("centre ground-Y within the map's vertical span"), gC >= gLo && gC <= gHi);

	// --- Drive the real generator off it: banding must re-derive on imported height. ---
	mira::HeightmapGenerator Gen;
	Gen.set_seed(1337);
	Gen.set_height_source(&HM);
	TestTrue(TEXT("generator reports the height source active"), Gen.height_source_active());

	const int genGround = Gen.compute_ground_y(0, 0);
	TestEqual(TEXT("generator ground-Y matches the heightmap sample at centre"), genGround, gC);

	const mira::ColumnInfo col = Gen.resolve_column(0, 0);
	TestEqual(TEXT("resolved column uses the imported ground-Y"), col.ground_y, gC);
	// The surface voxel is solid (some real material), the one above is air.
	const int surfMat = Gen.material_at(0, col.ground_y, 0, col);
	const int airMat  = Gen.material_at(0, col.ground_y + 1, 0, col);
	TestTrue(TEXT("surface voxel is solid (non-air)"), surfMat != mira::mat::AIR);
	TestEqual(TEXT("voxel above the surface is air"), airMat, static_cast<int>(mira::mat::AIR));

	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
