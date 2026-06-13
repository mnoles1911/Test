#!/usr/bin/env python3
"""
asset_pipeline.py — prompt → Gemini image → fal image-to-3D → .glb

Chains the two tools. Mirrors design/ASSET_PIPELINE_AI.md's first two steps
(concept image → AI 3D), leaving Blender voxelize/Remesh + rigging downstream.

  GEMINI_API_KEY=... FAL_KEY=... \
    python3 tools/aigen/asset_pipeline.py "a mossy granite boulder, white bg" boulder.glb
  ...  --keep-image boulder_concept.png --fal-model fal-ai/hunyuan3d/v2
  ...  --dry-run
"""
import os, sys, subprocess, tempfile, argparse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("out", nargs="?", default="asset.glb")
    ap.add_argument("--keep-image", default=None, help="save the concept image here (else a temp file)")
    ap.add_argument("--fal-model", default="fal-ai/trellis")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    img = a.keep_image or os.path.join(tempfile.gettempdir(), "aigen_concept.png")
    dry = ["--dry-run"] if a.dry_run else []

    print("== [1/2] Gemini concept image ==")
    subprocess.run([sys.executable, os.path.join(here, "gemini_image.py"), a.prompt, img] + dry, check=True)
    print("== [2/2] fal image → 3D ==")
    subprocess.run([sys.executable, os.path.join(here, "fal_image_to_3d.py"), a.out,
                    "--image", img, "--model", a.fal_model] + dry, check=True)
    print("done →", a.out, "(next: tools/blender import/remesh + Mixamo rig per ASSET_PIPELINE_AI.md)")


if __name__ == "__main__":
    main()
