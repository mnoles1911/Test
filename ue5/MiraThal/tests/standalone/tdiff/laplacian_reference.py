#!/usr/bin/env python3
"""laplacian_reference.py - golden generator for the Laplacian.h C++ port.

Runs the REAL terrain-diffusion functions (terrain_diffusion.data.laplacian_encoder:
laplacian_decode / laplacian_denoise - the ones world_pipeline._compute_elev calls)
on small fixed seeded tensors, and dumps the inputs + outputs as a C++ include
laplacian_golden.inc. test_tdiff_laplacian.cpp feeds the SAME inputs through the C++
ports and asserts max|diff| within tolerance.

These functions resize with torchvision TF.resize(BILINEAR) (default
align_corners=False, antialias=True) and TF.gaussian_blur, so this MUST run in the
repo venv with torchvision installed:

  pip install torchvision --index-url https://download.pytorch.org/whl/cpu   # torch CPU already present

Run:
  PYTHONPATH=D:/terrain-diffusion \
    D:/terrain-diffusion/.venv/Scripts/python.exe \
    tdiff/laplacian_reference.py
  # writes laplacian_golden.inc next to this file

Inputs are emitted as float32 BIT PATTERNS (uint32) so the C++ side reconstructs the
exact same floats; outputs are emitted as bit patterns too and compared with an
absolute tolerance on the decoded float values.
"""
import struct
import numpy as np
import torch
from pathlib import Path

# The REAL repo functions under test.
from terrain_diffusion.data.laplacian_encoder import laplacian_decode, laplacian_denoise

# sigma used by world_pipeline._compute_elev.
SIGMA = 5

# Mode tags shared with the C++ test.
MODE_DECODE_NOEXTRAP = 0   # laplacian_decode(residual, lowres)                 -> h x w
MODE_DECODE_EXTRAP   = 1   # laplacian_decode(residual, lowres, extrapolate=True)
MODE_DENOISE         = 2   # laplacian_denoise(residual, lowres, sigma)[1] (new coarse map)
MODE_ELEV            = 3   # the _compute_elev chain: denoise then decode -> elevation


def f32_bits(arr):
    """Flatten a float32 numpy array to a list of IEEE-754 uint32 bit patterns."""
    a = np.ascontiguousarray(arr, dtype=np.float32)
    return [struct.unpack("<I", struct.pack("<f", float(v)))[0] for v in a.ravel()]


def make_input(seed, shape, scale=1.0, offset=0.0):
    """Deterministic float32 tensor (channels, H, W)."""
    g = torch.Generator().manual_seed(seed)
    x = torch.randn(*shape, generator=g, dtype=torch.float32) * scale + offset
    return x.numpy().astype(np.float32)


def run_case(name, residual, lowres, mode):
    """Run a REAL repo function and return (out_array, outH, outW)."""
    if mode == MODE_DECODE_NOEXTRAP:
        out = laplacian_decode(residual, lowres)
    elif mode == MODE_DECODE_EXTRAP:
        out = laplacian_decode(residual, lowres, extrapolate=True)
    elif mode == MODE_DENOISE:
        _, out = laplacian_denoise(residual, lowres, sigma=SIGMA)
    elif mode == MODE_ELEV:
        # exactly what _compute_elev does (lines 1306-1307)
        res2, low2 = laplacian_denoise(residual, lowres, sigma=SIGMA)
        out = laplacian_decode(res2, low2)
    else:
        raise ValueError(mode)
    out = np.ascontiguousarray(out, dtype=np.float32)
    return out, out.shape[-2], out.shape[-1]


def main():
    # (name, residual seed/shape/scale/offset, lowres seed/shape/scale/offset, mode)
    # residual/lowres carry a couple of channels; shapes mirror the doc's 8x8 / 16x16
    # suggestion plus a non-square case to exercise the rounding/aspect paths.
    specs = [
        ("decode_noextrap_2c_8to16",
         (10, (2, 16, 16), 1.0, 0.0), (11, (2, 8, 8), 3.0, -31.0), MODE_DECODE_NOEXTRAP),
        ("decode_extrap_2c_8to16",
         (10, (2, 16, 16), 1.0, 0.0), (11, (2, 8, 8), 3.0, -31.0), MODE_DECODE_EXTRAP),
        ("decode_extrap_1c_nonsquare",
         (20, (1, 12, 20), 1.0, 0.0), (21, (1, 5, 8), 2.0, -10.0), MODE_DECODE_EXTRAP),
        ("denoise_2c_8to16",
         (10, (2, 16, 16), 1.0, 0.0), (11, (2, 8, 8), 3.0, -31.0), MODE_DENOISE),
        ("elev_2c_8to16",
         (10, (2, 16, 16), 1.0, 0.0), (11, (2, 8, 8), 3.0, -31.0), MODE_ELEV),
    ]

    blocks = []
    table = []
    for name, (rs, rshape, rsc, roff), (ls, lshape, lsc, loff), mode in specs:
        residual = make_input(rs, rshape, rsc, roff)
        lowres = make_input(ls, lshape, lsc, loff)
        out, outH, outW = run_case(name, residual, lowres, mode)

        C = rshape[0]
        h, w = rshape[1], rshape[2]
        lh, lw = lshape[1], lshape[2]

        res_bits = f32_bits(residual)
        low_bits = f32_bits(lowres)
        out_bits = f32_bits(out)

        rid = f"res_{name}"
        lid = f"low_{name}"
        oid = f"out_{name}"
        blocks.append(f"static const uint32_t {rid}[] = {{ " + ", ".join(f"{v}u" for v in res_bits) + " };")
        blocks.append(f"static const uint32_t {lid}[] = {{ " + ", ".join(f"{v}u" for v in low_bits) + " };")
        blocks.append(f"static const uint32_t {oid}[] = {{ " + ", ".join(f"{v}u" for v in out_bits) + " };")

        # name, channels, h, w, lh, lw, residual, lowres, mode, sigma, outH, outW, expected
        table.append(
            f'  {{ "{name}", {C}, {h}, {w}, {lh}, {lw}, {rid}, {lid}, {mode}, {float(SIGMA)}, {outH}, {outW}, {oid} }},'
        )

    lines = []
    lines.append("// AUTO-GENERATED by laplacian_reference.py - DO NOT EDIT.")
    lines.append("// Golden inputs/outputs from the REAL terrain-diffusion laplacian_decode/denoise.")
    lines.append("#pragma once")
    lines.append("#include <cstdint>")
    lines.append("")
    lines.extend(blocks)
    lines.append("")
    lines.append("struct LapCase {")
    lines.append("  const char* name;")
    lines.append("  int channels, h, w, lh, lw;")
    lines.append("  const uint32_t* residual;   // channels*h*w float32 bit patterns")
    lines.append("  const uint32_t* lowres;     // channels*lh*lw float32 bit patterns")
    lines.append("  int mode;                   // 0 decode, 1 decode-extrap, 2 denoise, 3 elev")
    lines.append("  double sigma;")
    lines.append("  int outH, outW;")
    lines.append("  const uint32_t* expected;   // channels*outH*outW float32 bit patterns")
    lines.append("};")
    lines.append("static const LapCase kLapCases[] = {")
    lines.extend(table)
    lines.append("};")
    lines.append(f"static const int kLapCaseCount = {len(specs)};")

    out_path = Path(__file__).with_name("laplacian_golden.inc")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {out_path} ({len(specs)} cases)")


if __name__ == "__main__":
    main()
