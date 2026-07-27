#!/usr/bin/env python3
"""Derive minimal RTL widths from the binary-exact PSG model.

Two sources, clearly separated in the output:

- OBSERVED: psg_binary_model's probe() hook records min/max at every
  load-bearing intermediate while the full deterministic oracle matrix
  renders through render_case. Observed ranges are evidence of what the
  cases exercise, not bounds.
- ANALYTIC: the wave layer is exhaustively evaluated over its whole
  16-bit phase domain (and the amplitude ladder over its whole legal
  input set), so those rows are true bounds a synthesis width can be
  sized from.

The render is byte-verified against a captured reference set while the
recorder is installed (pass --reference; default is the adopt-exact
capture), proving the instrumentation cannot perturb the model it
measures. Widths are two's-complement bits.

Usage:
  psg_width_report.py [--cases DIR] [--reference DIR] [--only NAME ...]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import psg_binary_model as M


def width(lo: int, hi: int) -> int:
    w = 1
    while lo < -(1 << (w - 1)) or hi > (1 << (w - 1)) - 1:
        w += 1
    return w


def row(site: str, lo: int, hi: int, note: str = "") -> str:
    return (f"  {site:22s} [{lo:>13,d} .. {hi:>13,d}]  "
            f"{width(lo, hi):2d} bits  {note}")


def analytic_wave_rows() -> list[str]:
    """Exhaustive bounds for every wave primitive and composed z."""
    prim = {
        "tri_raw": M.tri_raw,
        "tri_alt": M.tri_alt,
        "tilt.57344": lambda x: M.tilt(x, 57344),
        "tilt.61440": lambda x: M.tilt(x, 61440),
        "saw": M.saw,
        "saw_alt": M.saw_alt,
        "organ": M.organ,
    }
    lines = ["wave primitives (exhaustive over the 16-bit phase domain):"]
    bounds: dict[str, tuple[int, int]] = {}
    for name, fn in prim.items():
        vals = [fn(x) for x in range(65536)]
        bounds[name] = (min(vals), max(vals))
        lines.append(row(name, *bounds[name]))
    lines.append(row("square/pulse", -6143, 6143, "constant levels"))

    lines.append("composed z = f(p) + tz(g(q)/k) (separable bounds):")

    def compose(name, main, sec, k):
        lo = main[0] + M.tz(sec[0], k)
        hi = main[1] + M.tz(sec[1], k)
        lines.append(row(name, lo, hi))
        return lo, hi

    zb: list[tuple[int, int]] = []
    tri4 = tuple(M.tz(v, 4) for v in bounds["tri_raw"])
    zb.append(compose("z.w0 triangle", tri4, bounds["tri_raw"], 8))
    tri_a4 = tuple(M.tz(v, 4) for v in bounds["tri_alt"])
    zb.append(compose("z.w0 buzz", tri_a4, bounds["tri_alt"], 8))
    zb.append(compose("z.w1", bounds["tilt.57344"], bounds["tilt.57344"], 2))
    zb.append(compose("z.w1 buzz", bounds["tilt.61440"],
                      bounds["tilt.61440"], 2))
    zb.append(compose("z.w2", bounds["saw"], bounds["saw"], 2))
    zb.append(compose("z.w2 buzz", bounds["saw_alt"], bounds["saw_alt"], 2))
    zb.append(compose("z.w3/w4", (-6143, 6143), (-6143, 6143), 2))
    zb.append(compose("z.w5", bounds["organ"], bounds["organ"], 2))
    zb.append(compose("z.w5 buzz", bounds["organ"], (-3071, 3071), 1))
    wt = (-128 << M.CUSTOM_SHIFT, 127 << M.CUSTOM_SHIFT)
    zb.append(compose("z.w8 wavetable", wt, wt, 2))

    z_lo = min(b[0] for b in zb)
    z_hi = max(b[1] for b in zb)
    lines.append(row("z (any wave)", z_lo, z_hi))

    lines.append("amplitude ladder (exhaustive over legal volumes):")
    amps = set()
    for vol in range(8):
        a0 = vol << 8
        for iv in range(8):
            for a in (a0, M.tz(a0 * iv, 7)):
                amps.add(a)
                amps.add(M.tz(5 * a, 4))       # detune boost
    gs = sorted(M.tz(3 * a, 2) for a in amps)
    lines.append(row("amp.G", gs[0], gs[-1], "= tz(3a/2), boost included"))
    lines.append(row("scale.prod", gs[-1] * z_lo, gs[-1] * z_hi,
                     "G_max * z bound"))
    out_lo, out_hi = M.tz(gs[-1] * z_lo, 3072), M.tz(gs[-1] * z_hi, 3072)
    lines.append(row("scale.out", out_lo, out_hi, "one voice, pre-mix"))
    lines.append("phase increments (clamp / worst dq map entry):")
    lines.append(row("pinc.dp", 8, 32768, "dx_clamped bounds"))
    lines.append(row("pinc.dq", M.tz(8 * 193, 256), M.tz(32768 * 508, 256),
                     "K in 193..508"))
    return lines


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=Path,
                    default=Path("build/psg_oracle/cases"))
    ap.add_argument("--reference", dest="ref_dir", type=Path,
                    default=Path("build/psg_oracle/adopt-exact/reference"))
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()

    ranges: dict[str, list[int]] = {}

    def rec(site: str, v: int) -> None:
        r = ranges.get(site)
        if r is None:
            ranges[site] = [v, v, 1]
        else:
            if v < r[0]:
                r[0] = v
            if v > r[1]:
                r[1] = v
            r[2] += 1

    M.probe = rec

    manifest = json.loads(
        (args.cases / "manifest.json").read_text())["cases"]
    rendered = verified = 0
    unverified: list[str] = []
    for case in manifest:
        if args.only and case["name"] not in args.only:
            continue
        if case["long"] or case["stochastic"]:
            continue
        model = M.render_case(args.cases / case["audio"],
                              case["expected_ticks"])
        rendered += 1
        ref_path = args.ref_dir / f"{case['name']}.wav"
        if ref_path.exists():
            s, mism, n, _ = M.aligned_diff(model, M.read_wav(ref_path))
            if mism:
                print(f"NOT BYTE-EXACT under instrumentation: "
                      f"{case['name']} ({mism} mismatches)")
                return 1
            verified += 1
        else:
            unverified.append(case["name"])

    print(f"observed ranges over {rendered} deterministic cases "
          f"({verified} byte-verified against {args.ref_dir}"
          + (f"; no reference for: {', '.join(unverified)}" if unverified
             else "") + "):")
    for site in sorted(ranges):
        lo, hi, n = ranges[site]
        print(row(site, lo, hi, f"n={n:,d}"))
    print()
    for line in analytic_wave_rows():
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
