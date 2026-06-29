// HeightmapImport.cpp — EXR/PNG/HDR decode into a Core ImageHeightmap.
#include "HeightmapImport.h"

#include "Core/ImageHeightmap.h"

#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"

namespace
{
	// Map a file extension to the engine's image-format enum. EXR is the one we
	// care about (Gaea export); the others are handy for quick tests.
	EImageFormat FormatFromExtension(const FString& Path)
	{
		const FString Ext = FPaths::GetExtension(Path).ToLower();
		if (Ext == TEXT("exr"))  return EImageFormat::EXR;
		if (Ext == TEXT("png"))  return EImageFormat::PNG;
		if (Ext == TEXT("hdr"))  return EImageFormat::HDR;
		if (Ext == TEXT("tif") || Ext == TEXT("tiff")) return EImageFormat::TIFF;
		return EImageFormat::Invalid;
	}
}

bool MiraHeightmapImport::LoadHeightmapImage(const FString& AbsolutePath,
                                             mira::ImageHeightmap& Out,
                                             FString& OutError)
{
	if (!FPaths::FileExists(AbsolutePath))
	{
		OutError = FString::Printf(TEXT("heightmap file not found: %s"), *AbsolutePath);
		return false;
	}

	const EImageFormat Format = FormatFromExtension(AbsolutePath);
	if (Format == EImageFormat::Invalid)
	{
		OutError = FString::Printf(TEXT("unsupported heightmap extension: %s"), *AbsolutePath);
		return false;
	}

	// Slurp the file bytes.
	TArray64<uint8> FileData;
	if (!FFileHelper::LoadFileToArray(FileData, *AbsolutePath))
	{
		OutError = FString::Printf(TEXT("could not read heightmap file: %s"), *AbsolutePath);
		return false;
	}

	IImageWrapperModule& Module =
		FModuleManager::LoadModuleChecked<IImageWrapperModule>(FName("ImageWrapper"));
	TSharedPtr<IImageWrapper> Wrapper = Module.CreateImageWrapper(Format);
	if (!Wrapper.IsValid() || !Wrapper->SetCompressed(FileData.GetData(), FileData.Num()))
	{
		OutError = TEXT("ImageWrapper could not parse the heightmap (corrupt or wrong format)");
		return false;
	}

	const int32 W = Wrapper->GetWidth();
	const int32 H = Wrapper->GetHeight();
	if (W <= 0 || H <= 0)
	{
		OutError = TEXT("heightmap reports zero size");
		return false;
	}

	// Decode to 32-bit float RGBA (gray EXRs expand so every channel == height).
	TArray64<uint8> Raw;
	if (!Wrapper->GetRaw(ERGBFormat::RGBAF, 32, Raw))
	{
		OutError = TEXT("ImageWrapper could not decode the heightmap to float RGBA");
		return false;
	}

	const int64 PixelCount = static_cast<int64>(W) * static_cast<int64>(H);
	const int64 ExpectedBytes = PixelCount * 4 /*RGBA*/ * 4 /*float*/;
	if (Raw.Num() < ExpectedBytes)
	{
		OutError = FString::Printf(
			TEXT("decoded heightmap smaller than expected (%lld < %lld bytes)"),
			static_cast<long long>(Raw.Num()), static_cast<long long>(ExpectedBytes));
		return false;
	}

	// Copy the RED channel out as the height value.
	const float* Floats = reinterpret_cast<const float*>(Raw.GetData());
	Out.width  = W;
	Out.height = H;
	Out.data.resize(static_cast<size_t>(PixelCount));
	for (int64 i = 0; i < PixelCount; ++i)
	{
		Out.data[static_cast<size_t>(i)] = Floats[i * 4 + 0]; // R = height
	}

	OutError.Reset();
	return true;
}
