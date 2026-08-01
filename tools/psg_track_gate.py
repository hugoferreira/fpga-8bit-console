#!/usr/bin/env python3
"""Render current PSG RTL and gate one full track against real PICO-8.

Unlike invoking audio_analysis.py on an existing candidate WAV, this command
owns candidate provenance: it rebuilds the hardware-schedule renderer when any
PSG source changes, renders the requested track on every invocation, and writes
a JSON sidecar containing source, cart-audio, and reference fingerprints.

Exit status 0 means every applicable comparison passed, 1 means fidelity
failed, and 2 means the invocation was invalid.

Examples:
  psg_track_gate.py --cart celeste.p8.png --music 30 --reference pico8-30.wav
  psg_track_gate.py --cart celeste.p8.png --music 30 --reference pico8-30.wav --spectrogram-file build/music30.png
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from p8_audio import rom_from_png
import psg_oracle_render
import audio_analysis

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CLOCK = 28_125_000


def digest(data: bytes) -> str:
    """Compatibility name for the shared provenance helper."""
    return audio_analysis.sha256_bytes(data)


def source_fingerprint() -> tuple[str, list[Path]]:
    sources = (ROOT / "sim/psg_wav.cpp", *sorted(ROOT.glob("rtl/psg*.sv")),
               *sorted(ROOT.glob("rtl/psg*.svh")))
    sha = hashlib.sha256()
    for source in sources:
        relative = source.relative_to(ROOT).as_posix().encode("utf-8")
        sha.update(len(relative).to_bytes(4, "big"))
        sha.update(relative)
        content = source.read_bytes()
        sha.update(len(content).to_bytes(8, "big"))
        sha.update(content)
    return sha.hexdigest(), list(sources)


def write_manifest(path: Path, *, source_sha: str, sources: list[Path],
                   audio: bytes, reference: Path, candidate: Path,
                   music: int, mask: int, clock: int, samples: int,
                   policy=None) -> None:
    policy = audio_analysis.comparison_policy(policy)
    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_sha256": source_sha,
        "sources": [source.relative_to(ROOT).as_posix() for source in sources],
        "audio_sha256": digest(audio),
        "reference": str(reference.resolve()),
        "reference_sha256": audio_analysis.sha256_file(reference),
        "candidate": str(candidate.resolve()),
        "candidate_sha256": audio_analysis.sha256_file(candidate),
        "comparison_policy": policy.as_dict(),
        "music": music,
        "mask": mask,
        "clock_hz": clock,
        "samples": samples,
    }
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cart", type=Path, required=True,
                        help="PICO-8 .p8.png cartridge supplying the audio image")
    parser.add_argument("--reference", type=Path, required=True,
                        help="WAV recorded from real PICO-8")
    parser.add_argument("--music", type=int, required=True,
                        help="track-head pattern to render")
    parser.add_argument("--mask", type=int, default=7,
                        help="music reservation mask (default: 7)")
    parser.add_argument("--clock", type=int, default=DEFAULT_CLOCK,
                        help=f"RTL clock in Hz (default: {DEFAULT_CLOCK})")
    parser.add_argument("--candidate-out", type=Path,
                        default=ROOT / "build/psg_track_gate/current-rtl.wav",
                        help="render destination; provenance uses the same stem")
    parser.add_argument("--spectrogram-file",
                        help="optional PNG/PDF/SVG side-by-side spectrogram")
    args = parser.parse_args()

    if not args.cart.is_file():
        parser.error(f"cart does not exist: {args.cart}")
    if not args.reference.is_file():
        parser.error(f"reference does not exist: {args.reference}")
    if not 0 <= args.music < 64:
        parser.error("--music must be in 0..63")
    if not 0 <= args.mask < 16:
        parser.error("--mask must be in 0..15")
    if args.clock <= 0:
        parser.error("--clock must be positive")

    reference = audio_analysis.load_wav(args.reference)
    policy = audio_analysis.DEFAULT_POLICY
    audio = bytes(rom_from_png(args.cart)[0x3100:0x4300])
    work = args.candidate_out.parent
    work.mkdir(parents=True, exist_ok=True)
    audio_path = work / "audio.bin"
    audio_path.write_bytes(audio)

    binary = psg_oracle_render.build(args.clock, ROOT / "build/psg_oracle", 8)
    subprocess.run([
        str(binary), "--audio", str(audio_path.resolve()),
        "--music", str(args.music), "--mask", str(args.mask),
        "--samples", str(len(reference)), "--clk", str(args.clock),
        "--out", str(args.candidate_out.resolve()),
    ], cwd=ROOT, check=True)

    source_sha, sources = source_fingerprint()
    manifest_path = args.candidate_out.with_suffix(".json")
    write_manifest(
        manifest_path, source_sha=source_sha, sources=sources, audio=audio,
        reference=args.reference, candidate=args.candidate_out,
        music=args.music, mask=args.mask, clock=args.clock,
        samples=len(reference), policy=policy)
    print(f"current RTL source sha256: {source_sha}")
    print(f"provenance: {manifest_path}")

    candidate = audio_analysis.load_wav(args.candidate_out)
    audio_analysis.describe_wav(args.reference, reference, indent="reference ")
    audio_analysis.describe_wav(args.candidate_out, candidate,
                                indent="  current RTL ")
    view = audio_analysis.SpectrogramView(path=args.spectrogram_file)
    result = audio_analysis.analyze_comparison(
        reference, candidate, "current RTL", policy=policy)
    audio_analysis.report_comparison(
        result, view=view,
        reference_label=audio_analysis.display_name(args.reference))
    return 0 if result.passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
