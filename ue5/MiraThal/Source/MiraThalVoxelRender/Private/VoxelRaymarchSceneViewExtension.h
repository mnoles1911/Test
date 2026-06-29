// VoxelRaymarchSceneViewExtension.h — the render-thread hook that (eventually)
// dispatches the M7 far-field voxel ray-march.
//
// WHAT A SceneViewExtension IS (plain English):
//   It's the engine's official "let me inject my own rendering at a specific point
//   in the frame" interface. You subclass FSceneViewExtensionBase, override the
//   hook for the stage you care about, and the renderer calls you every frame. We
//   want the POST-OPAQUE stage: after the world's solid geometry (the meshed near
//   chunks) has drawn its depth, so the far-field march can read scene depth and
//   only shade pixels the near geometry didn't already cover (the horizon).
//
//   We use PostRenderBasePassDeferred_RenderThread — it runs after the deferred
//   base pass (opaque), gives us the FRDGBuilder, the view, the render-target
//   bindings, and the scene-texture uniform buffer (depth/gbuffer). That's exactly
//   what a screen-space march needs.
//
//   SCAFFOLD STATUS: the class, its base, and the override SIGNATURES are REAL and
//   compile against UE 5.7. The body of the hook is a STUB — it does NOT dispatch
//   the shader yet (the GPU brick mirror isn't fed in live). Clearly commented.

#pragma once

#include "CoreMinimal.h"
#include "SceneViewExtension.h"   // FSceneViewExtensionBase + override signatures

class FVoxelBrickGPUMirror;

class FVoxelRaymarchSceneViewExtension : public FSceneViewExtensionBase
{
public:
	// The first ctor arg MUST be FAutoRegister and be forwarded to the base — that's
	// how FSceneViewExtensions::NewExtension<T>() self-registers the extension.
	// VERIFY: this is the documented 5.7 pattern (SceneViewExtension.h header comment).
	FVoxelRaymarchSceneViewExtension(const FAutoRegister& AutoRegister);

	// ---- ISceneViewExtension overrides (signatures copied verbatim from 5.7) ----

	// Game-thread setup hooks. We don't need them yet; declared so the override set
	// is explicit and so the parent sees where per-frame view config would go.
	virtual void SetupViewFamily(FSceneViewFamily& InViewFamily) override {}
	virtual void SetupView(FSceneViewFamily& InViewFamily, FSceneView& InView) override {}
	virtual void BeginRenderViewFamily(FSceneViewFamily& InViewFamily) override {}

	// THE hook we care about: runs on the render thread after the deferred opaque
	// base pass. This is where the far-field march would be dispatched into the RDG.
	// Signature is verbatim from SceneViewExtension.h (5.7):
	virtual void PostRenderBasePassDeferred_RenderThread(
		FRDGBuilder& GraphBuilder,
		FSceneView& InView,
		const FRenderTargetBindingSlots& RenderTargets,
		TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures) override;

	// Gate: only run when the far-field march is enabled + a mirror is bound. For
	// the scaffold this returns false so the (unwired) extension never does work.
	// VERIFY: IsActiveThisFrame_Internal is the correct protected override point in
	// 5.7 (the public IsActiveThisFrame is final on the base and calls this).
	virtual bool IsActiveThisFrame_Internal(const FSceneViewExtensionContext& Context) const override;

	// Wire-in point for the GPU brick mirror (game thread sets it; render thread
	// reads it). Raw pointer for the scaffold; real wiring will use a thread-safe
	// hand-off (the mirror outlives the frame, owned by the voxel-world subsystem).
	void SetBrickMirror(FVoxelBrickGPUMirror* InMirror) { BrickMirror = InMirror; }

private:
	// Not owned. Null in the scaffold => IsActiveThisFrame_Internal stays false.
	FVoxelBrickGPUMirror* BrickMirror = nullptr;
};
