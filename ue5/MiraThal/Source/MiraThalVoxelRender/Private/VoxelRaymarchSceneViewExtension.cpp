// VoxelRaymarchSceneViewExtension.cpp — render-thread hook implementation (scaffold).
//
// REAL: the class wiring + the override bodies that compile against UE 5.7.
// STUB: the actual march dispatch (the FGlobalShader pass that runs VoxelRaymarch.usf)
//       is a documented TODO — no GPU work happens yet.

#include "VoxelRaymarchSceneViewExtension.h"
#include "VoxelBrickGPUMirror.h"

#include "RenderGraphBuilder.h"
#include "SceneView.h"

FVoxelRaymarchSceneViewExtension::FVoxelRaymarchSceneViewExtension(const FAutoRegister& AutoRegister)
	: FSceneViewExtensionBase(AutoRegister)
{
	// Nothing to construct yet. The brick mirror is bound later via SetBrickMirror.
}

bool FVoxelRaymarchSceneViewExtension::IsActiveThisFrame_Internal(
	const FSceneViewExtensionContext& Context) const
{
	// SCAFFOLD: stay inactive until a real GPU mirror is bound AND a "far-field
	// march enabled" toggle is on. With BrickMirror null (the scaffold default) this
	// is false, so the renderer never calls our hook and we add zero overhead.
	//
	// Real version will also check: the view is a 3D game/editor view (not a thumbnail
	// or scene-capture), and the far-field band is enabled in the voxel settings.
	(void)Context;
	return BrickMirror != nullptr; // false in the scaffold (mirror never set live yet)
}

void FVoxelRaymarchSceneViewExtension::PostRenderBasePassDeferred_RenderThread(
	FRDGBuilder& GraphBuilder,
	FSceneView& InView,
	const FRenderTargetBindingSlots& RenderTargets,
	TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures)
{
	// =====================================================================
	// SCAFFOLD STUB — NO DISPATCH. Pending GPU verification.
	// =====================================================================
	//
	// What this WILL do (M7 bring-up):
	//   1. Early-out if !BrickMirror or its GPU buffers aren't uploaded.
	//   2. Build the shader parameter struct for VoxelRaymarch.usf:
	//        - BrickIndex SRV  + VoxelTypes SRV   (from BrickMirror)
	//        - RegionMinBrick / RegionDimBricks   (march bounds in brick space)
	//        - inverse view-projection + camera origin (to make a world-space ray
	//          per pixel), MaxMarchDistance (the CPU oracle's max_dist analogue)
	//        - scene depth SRV (from SceneTextures) so we only shade horizon pixels
	//          farther than the already-drawn near geometry
	//        - the output color target (from RenderTargets)
	//   3. Add a compute (or full-screen pixel) pass via FComputeShaderUtils::AddPass
	//      / FPixelShaderUtils::AddFullscreenPass that runs the .usf march, shading
	//      first-solid with base_color x face_shade (matching VoxelColor.h).
	//
	// Sketch (left commented — VERIFY signatures on this 5.7 build):
	//
	//   if (!BrickMirror || !BrickMirror->GetBrickIndexBuffer()) return;
	//   FVoxelRaymarchPS::FParameters* P =
	//       GraphBuilder.AllocParameters<FVoxelRaymarchPS::FParameters>();
	//   P->BrickIndex = GraphBuilder.CreateSRV(BrickMirror->GetBrickIndexBuffer());
	//   P->VoxelTypes = GraphBuilder.CreateSRV(BrickMirror->GetVoxelTypeBuffer());
	//   P->SceneTextures = SceneTextures;
	//   P->RenderTargets[0] = RenderTargets.Output ... ;  // VERIFY binding
	//   TShaderMapRef<FVoxelRaymarchPS> PixelShader(GetGlobalShaderMap(FeatureLevel));
	//   FPixelShaderUtils::AddFullscreenPass(GraphBuilder, ShaderMap,
	//       RDG_EVENT_NAME("MiraVoxel.FarFieldRaymarch"), PixelShader, P, Viewport);
	//
	// VERIFY: PostRenderBasePassDeferred_RenderThread is the right stage for a depth-
	//         aware horizon march on 5.7 (an alternative is SubscribeToPostProcessingPass
	//         at EPostProcessingPass::Tonemap if we want it post-Lumen — decide at bring-up).
	// VERIFY: FGlobalShader param struct + AddFullscreenPass remain the 5.7 idiom.
	(void)GraphBuilder;
	(void)InView;
	(void)RenderTargets;
	(void)SceneTextures;
	(void)BrickMirror;
}
