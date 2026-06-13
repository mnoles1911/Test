# tools/aigen — AI asset-generation CLIs

REST CLIs (stdlib only, no pip installs) that wire **Gemini "Nano Banana"
image generation** and **fal.ai image→3D** into the toolchain. They mirror the
first two steps of `design/ASSET_PIPELINE_AI.md` (concept image → AI 3D),
leaving Blender voxelize/Remesh + Mixamo rigging downstream.

## Setup (API keys)

```bash
export GEMINI_API_KEY=...   # Google AI Studio  (or GOOGLE_API_KEY)
export FAL_KEY=...          # fal.ai            (or FAL_API_KEY)
```
For Claude Code sessions, add them to `.claude/settings.json` → `env`, or a
shell profile. Every tool supports `--dry-run` to print the exact request
without a key (so you can verify before spending credits). Outbound to
`generativelanguage.googleapis.com` and `queue.fal.run` must be allowed by the
environment's network policy.

## Tools

| Tool | What |
|---|---|
| `gemini_image.py` | Generate or edit an image with **Gemini 2.5 Flash Image** (Nano Banana). Text→image, or `--image ref.png` for image+text editing. Writes the first returned image. |
| `fal_image_to_3d.py` | Image → **`.glb`** via fal.ai queue API (default `fal-ai/trellis`; `--model fal-ai/hunyuan3d/v2` etc.). Local `--image` is sent as a data URI; `--image-url` for a hosted URL. `--set k=v` passes extra model inputs. |
| `asset_pipeline.py` | Chains both: prompt → image → `.glb`. |

## Examples

```bash
# concept image
python3 tools/aigen/gemini_image.py "a mossy granite boulder, white background, studio lighting" boulder.png

# image -> 3D mesh
python3 tools/aigen/fal_image_to_3d.py boulder.glb --image boulder.png --set mesh_simplify=0.9 --set texture_size=2048

# one shot
python3 tools/aigen/asset_pipeline.py "T-pose goblin warrior, white bg, full body" goblin.glb --keep-image goblin_concept.png
```

Models: Gemini `gemini-2.5-flash-image` (override `--model`); fal default
`fal-ai/trellis` (alternatives: `fal-ai/hunyuan3d/v2`, `fal-ai/hunyuan3d-v3/image-to-3d`).
Note: some fal models reject data-URI inputs — if a local `--image` fails, host
the image and pass `--image-url`.
