#!/usr/bin/env python3
"""Generate and compare small PICO-8 PSG fidelity probes.

The old RTL is deliberately not an oracle.  ``generate`` emits one-assumption
PICO-8 cartridges plus the exact 4608-byte audio image consumed by rtl/psg.sv.
Export the carts with tools/p8_music_export.py, render the .bin with
sim/psg_wav.cpp, then use ``compare`` for aligned diagnostics.

Examples:
  tools/psg_oracle.py generate build/psg_oracle/cases
  tools/psg_oracle.py compare ref.wav rtl.wav --expected-samples 11712
  tools/psg_oracle.py compare ref.wav rtl.wav --stochastic
"""

from __future__ import annotations

import argparse
import array
import json
import math
import statistics
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path

RATE = 22_050
SAMPLES_PER_TICK = 183
MUSIC_BYTES = 256
SFX_BYTES = 64 * 68
EMPTY_PATTERN = bytes((0x41, 0x42, 0x43, 0x44))


@dataclass
class Probe:
    name: str
    description: str
    records: dict[int, bytes]
    patterns: list[tuple[list[int | None], bool, bool, bool]]
    expected_ticks: int
    stochastic: bool = False
    long: bool = False


def note(pitch: int, waveform: int, volume: int, effect: int = 0,
         custom: bool = False) -> int:
    if not 0 <= pitch < 64:
        raise ValueError(f"pitch out of range: {pitch}")
    return (pitch | (waveform << 6) | (volume << 9) | (effect << 12)
            | (int(custom) << 15))


def sfx(notes: list[int], *, speed: int = 2, length: int = 16,
        filt: int = 0, loop_start: int | None = None,
        loop_end: int = 0) -> bytes:
    if len(notes) > 32:
        raise ValueError("an SFX has at most 32 notes")
    words = notes + [0] * (32 - len(notes))
    raw = bytearray()
    for value in words:
        raw += struct.pack("<H", value)
    length_meta = 0 if length >= 32 else length
    raw += bytes((filt, speed,
                  length_meta if loop_start is None else loop_start, loop_end))
    return bytes(raw)


def wavetable(values: list[int], *, bass: bool = False) -> bytes:
    if len(values) != 64 or any(not -128 <= x <= 127 for x in values):
        raise ValueError("wavetable must contain 64 signed bytes")
    return bytes(x & 0xFF for x in values) + bytes((0, int(bass), 0x80, 0))


def constant(pitch: int, waveform: int, volume: int = 7, effect: int = 0,
             *, speed: int = 1, length: int = 32, filt: int = 0,
             custom: bool = False) -> bytes:
    return sfx([note(pitch, waveform, volume, effect, custom)] * length,
               speed=speed, length=length, filt=filt)


def probes() -> list[Probe]:
    out: list[Probe] = []
    wave_names = ("triangle", "tilted-saw", "saw", "square", "pulse",
                  "organ", "noise", "phaser")
    for waveform, name in enumerate(wave_names):
        ticks = 32
        out.append(Probe(
            f"wave-{waveform}-{name}",
            f"built-in {name}, C-2, volume 7, 32 rows",
            {0: constant(24, waveform)},
            [([0, None, None, None], False, False, True)],
            ticks,
            stochastic=(waveform == 6),
        ))

    for pitch in (0, 12, 24, 36, 48, 60, 63):
        out.append(Probe(
            f"pitch-{pitch:02d}", f"triangle pitch {pitch}",
            {0: constant(pitch, 0)},
            [([0, None, None, None], False, False, True)],
            32,
        ))

    effects = {
        1: [note(24, 0, 7)] * 4 + [note(36, 0, 7, 1)] * 12,
        2: [note(36, 0, 7, 2)] * 16,
        3: [note(36, 0, 7, 3)] * 16,
        4: [note(36, 0, 7, 4)] * 16,
        5: [note(36, 0, 7, 5)] * 16,
        6: ([note(24, 0, 7, 6), note(28, 0, 7, 6),
             note(31, 0, 7, 6)] * 6)[:16],
        7: ([note(24, 0, 7, 7), note(28, 0, 7, 7),
             note(31, 0, 7, 7)] * 6)[:16],
    }
    effect_names = ("", "slide", "vibrato", "drop", "fade-in",
                    "fade-out", "arp-fast", "arp-slow")
    for effect, rows in effects.items():
        rows = (rows * 2)[:32]
        out.append(Probe(
            f"effect-{effect}-{effect_names[effect]}",
            f"note effect {effect}: {effect_names[effect]}",
            {0: sfx(rows, speed=2, length=32)},
            [([0, None, None, None], False, False, True)],
            64,
        ))

    out.append(Probe(
        "mix-two", "triangle C-2 volume 7 plus square G-2 volume 4",
        {0: constant(24, 0, 7), 1: constant(31, 3, 4)},
        [([0, 1, None, None], False, False, True)],
        32,
    ))
    out.append(Probe(
        "mix-four", "four unequal deterministic channels",
        {0: constant(24, 0, 7), 1: constant(28, 2, 5),
         2: constant(31, 3, 3), 3: constant(36, 5, 1)},
        [([0, 1, 2, 3], False, False, True)],
        32,
    ))

    for name, filt in (("noiz", 2), ("buzz", 4), ("detune-1", 8),
                       ("reverb-1", 24), ("dampen-1", 72)):
        out.append(Probe(
            f"filter-{name}", f"filter byte {filt}: {name}",
            {0: constant(30, 3, filt=filt)},
            [([0, None, None, None], False, False, True)],
            32,
            stochastic=(name == "noiz"),
        ))

    instrument_rows = (
        [note(24, 0, 7)] * 4 + [note(31, 5, 3)] * 4
        + [note(36, 3, 1, 5)] * 8
    )
    out.append(Probe(
        "sfx-instrument", "held custom SFX instrument with pitch/volume shape",
        {0: sfx(instrument_rows * 2, speed=1, length=32),
         8: constant(30, 0, 7, custom=True)},
        [([8, None, None, None], False, False, True)],
        32,
    ))

    ramp = [max(-128, min(127, i * 4 - 128)) for i in range(64)]
    out.append(Probe(
        "waveform-instrument", "64-sample ramp waveform instrument",
        {1: wavetable(ramp),
         8: constant(30, 1, 7, custom=True)},
        [([8, None, None, None], False, False, True)],
        32,
    ))

    out.append(Probe(
        "pattern-chain", "two bounded patterns with distinct pitches",
        {0: constant(24, 0, speed=1, length=8),
         1: constant(36, 0, speed=1, length=8)},
        [([0, None, None, None], False, False, False),
         ([1, None, None, None], False, False, True)],
        16,
    ))

    out.append(Probe(
        "length-only", "length-only metadata 16 with 32 audible source rows",
        {0: sfx([note(30, 3, 7)] * 32, speed=2, length=16)},
        [([0, None, None, None], False, False, True)],
        32,
    ))

    # PICO-8 deliberately caps an infinite music export at 32768 music ticks.
    # Keep this case generated but out of the default fast matrix.
    out.append(Probe(
        "pattern-loop-cap", "loop-start/back reaches PICO-8 export ceiling",
        {0: constant(24, 0, speed=1, length=1),
         1: constant(36, 0, speed=1, length=1)},
        [([0, None, None, None], True, False, False),
         ([1, None, None, None], False, True, False)],
        32768,
        long=True,
    ))
    return out


def make_image(probe: Probe) -> bytes:
    music = bytearray(EMPTY_PATTERN * 64)
    for index, (channels, loop_start, loop_back, stop) in enumerate(
            probe.patterns):
        row = bytearray(EMPTY_PATTERN)
        for channel, sfx_id in enumerate(channels):
            if sfx_id is not None:
                row[channel] = sfx_id
        if loop_start:
            row[0] |= 0x80
        if loop_back:
            row[1] |= 0x80
        if stop:
            row[2] |= 0x80
        music[index * 4:index * 4 + 4] = row
    records = bytearray(SFX_BYTES)
    for index, record in probe.records.items():
        if len(record) != 68 or not 0 <= index < 64:
            raise ValueError(f"bad SFX record {index}")
        records[index * 68:index * 68 + 68] = record
    return bytes(music + records)


def sfx_text(record: bytes) -> str:
    result = record[64:68].hex()
    for offset in range(0, 64, 2):
        value = record[offset] | record[offset + 1] << 8
        pitch = value & 0x3F
        waveform = (value >> 6) & 7
        volume = (value >> 9) & 7
        effect = (value >> 12) & 7
        custom = (value >> 15) & 1
        result += f"{pitch:02x}{waveform | custom << 3:x}{volume:x}{effect:x}"
    return result


def music_text(image: bytes) -> list[str]:
    rows = []
    for index in range(64):
        row = image[index * 4:index * 4 + 4]
        flags = ((row[0] >> 7) | ((row[1] >> 7) << 1)
                 | ((row[2] >> 7) << 2))
        rows.append(f"{flags:02x} " + "".join(f"{x & 0x7f:02x}" for x in row))
    return rows


def p8_text(probe: Probe, image: bytes) -> str:
    records = image[MUSIC_BYTES:]
    sfx_rows = [sfx_text(records[i * 68:i * 68 + 68]) for i in range(64)]
    return (
        "pico-8 cartridge // http://www.pico-8.com\n"
        "version 42\n"
        "__lua__\n"
        "-- generated PSG oracle probe; audio lives below\n"
        "__sfx__\n" + "\n".join(sfx_rows) + "\n"
        "__music__\n" + "\n".join(music_text(image)) + "\n"
    )


def generate(out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"rate": RATE, "samples_per_tick": SAMPLES_PER_TICK, "cases": []}
    for probe in probes():
        image = make_image(probe)
        (out_dir / f"{probe.name}.bin").write_bytes(image)
        (out_dir / f"{probe.name}.p8").write_text(
            p8_text(probe, image), encoding="ascii")
        manifest["cases"].append({
            "name": probe.name,
            "description": probe.description,
            "cart": f"{probe.name}.p8",
            "audio": f"{probe.name}.bin",
            "expected_ticks": probe.expected_ticks,
            "expected_samples": probe.expected_ticks * SAMPLES_PER_TICK,
            "stochastic": probe.stochastic,
            "long": probe.long,
        })
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def read_wav(path: Path) -> list[int]:
    with wave.open(str(path), "rb") as wav:
        fmt = (wav.getnchannels(), wav.getsampwidth(), wav.getframerate())
        if fmt != (1, 2, RATE):
            raise ValueError(
                f"{path}: expected mono 16-bit {RATE} Hz WAV, got {fmt}")
        data = array.array("h")
        data.frombytes(wav.readframes(wav.getnframes()))
        if sys.byteorder != "little":
            data.byteswap()
        return list(data)


def correlation(a: list[float] | list[int],
                b: list[float] | list[int]) -> float:
    if not a or len(a) != len(b):
        return 0.0
    ma, mb = statistics.fmean(a), statistics.fmean(b)
    aa = sum((x - ma) ** 2 for x in a)
    bb = sum((x - mb) ** 2 for x in b)
    if not aa or not bb:
        return 1.0 if a == b else 0.0
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / math.sqrt(aa * bb)


def align(reference: list[int], candidate: list[int], max_shift: int = 1024,
          window: int = 4096) -> tuple[list[int], list[int], int, float]:
    best = (float("-inf"), 0)
    search_window = min(window, 1024)
    for shift in range(-max_shift, max_shift + 1):
        r0, c0 = max(0, shift), max(0, -shift)
        count = min(search_window, len(reference) - r0, len(candidate) - c0)
        if count < 256:
            continue
        score = correlation(reference[r0:r0 + count],
                            candidate[c0:c0 + count])
        if score > best[0]:
            best = score, shift
    shift = best[1]
    r0, c0 = max(0, shift), max(0, -shift)
    count = min(len(reference) - r0, len(candidate) - c0)
    return reference[r0:r0 + count], candidate[c0:c0 + count], shift, best[0]


def fit(reference: list[int], candidate: list[int]) -> tuple[float, float]:
    mc = statistics.fmean(candidate)
    mr = statistics.fmean(reference)
    denom = sum((x - mc) ** 2 for x in candidate)
    gain = (sum((x - mc) * (y - mr)
                for x, y in zip(candidate, reference)) / denom
            if denom else 0.0)
    return gain, mr - gain * mc


def deterministic_metrics(reference: list[int], candidate: list[int],
                          expected_samples: int | None) -> dict:
    ref, cand, shift, align_corr = align(reference, candidate)
    gain, offset = fit(ref, cand)
    adjusted = [gain * x + offset for x in cand]
    errors = [x - y for x, y in zip(ref, adjusted)]
    ref_rms = math.sqrt(statistics.fmean(x * x for x in ref)) or 1.0
    ref_peak = max((abs(x) for x in ref), default=1) or 1
    return {
        "reference_samples": len(reference),
        "candidate_samples": len(candidate),
        "expected_samples": expected_samples,
        "reference_sample_error": (None if expected_samples is None
                                   else len(reference) - expected_samples),
        "candidate_sample_error": (None if expected_samples is None
                                   else len(candidate) - expected_samples),
        "alignment_samples": shift,
        "alignment_correlation": align_corr,
        "fitted_gain": gain,
        "fitted_dc": offset,
        "correlation": correlation(ref, cand),
        "nrmse": math.sqrt(statistics.fmean(x * x for x in errors)) / ref_rms,
        "normalised_peak_error": max((abs(x) for x in errors),
                                     default=0) / ref_peak,
        "reference_rms": ref_rms,
        "candidate_rms": math.sqrt(
            statistics.fmean(x * x for x in cand)) if cand else 0.0,
    }


def block_values(samples: list[int], size: int = 1024) -> tuple[list[float],
                                                                list[int]]:
    rms, peaks = [], []
    for start in range(0, len(samples) - size + 1, size):
        block = samples[start:start + size]
        rms.append(math.sqrt(statistics.fmean(x * x for x in block)))
        peaks.append(max(abs(x) for x in block))
    return rms, peaks


def zero_crossing_density(samples: list[int]) -> float:
    if len(samples) < 2:
        return 0.0
    return sum((a < 0) != (b < 0) for a, b in zip(samples, samples[1:])) / (
        len(samples) - 1)


def autocorrelation(samples: list[int], lag: int) -> float:
    if len(samples) <= lag:
        return 0.0
    return correlation(samples[:-lag], samples[lag:])


def stochastic_summary(samples: list[int]) -> dict:
    rms, peaks = block_values(samples)
    return {
        "samples": len(samples),
        "rms_mean": statistics.fmean(rms) if rms else 0.0,
        "rms_stdev": statistics.pstdev(rms) if len(rms) > 1 else 0.0,
        "peak_mean": statistics.fmean(peaks) if peaks else 0.0,
        "peak_max": max(peaks, default=0),
        "zero_crossing_density": zero_crossing_density(samples),
        "autocorrelation": {
            str(lag): autocorrelation(samples, lag)
            for lag in (1, 2, 8, 32)
        },
    }


def stochastic_metrics(reference: list[int], candidate: list[int],
                       expected_samples: int | None) -> dict:
    ref, cand = stochastic_summary(reference), stochastic_summary(candidate)
    def relative(a: float, b: float) -> float:
        return abs(a - b) / max(abs(a), 1.0)
    return {
        "reference": ref,
        "candidate": cand,
        "expected_samples": expected_samples,
        "reference_sample_error": (None if expected_samples is None
                                   else len(reference) - expected_samples),
        "candidate_sample_error": (None if expected_samples is None
                                   else len(candidate) - expected_samples),
        "relative_error": {
            "rms_mean": relative(ref["rms_mean"], cand["rms_mean"]),
            "rms_stdev": relative(ref["rms_stdev"], cand["rms_stdev"]),
            "peak_mean": relative(ref["peak_mean"], cand["peak_mean"]),
            "zero_crossing_density": relative(
                ref["zero_crossing_density"],
                cand["zero_crossing_density"]),
            "autocorrelation": {
                lag: abs(ref["autocorrelation"][lag]
                         - cand["autocorrelation"][lag])
                for lag in ref["autocorrelation"]
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("out_dir", type=Path)
    cmp = sub.add_parser("compare")
    cmp.add_argument("reference", type=Path)
    cmp.add_argument("candidate", type=Path)
    cmp.add_argument("--expected-samples", type=int)
    cmp.add_argument("--stochastic", action="store_true")
    cmp.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.command == "generate":
        manifest = generate(args.out_dir)
        fast = sum(not case["long"] for case in manifest["cases"])
        print(f"generated {len(manifest['cases'])} probes "
              f"({fast} in the default matrix) in {args.out_dir}")
        return 0

    reference = read_wav(args.reference)
    candidate = read_wav(args.candidate)
    metrics = (stochastic_metrics(reference, candidate, args.expected_samples)
               if args.stochastic else
               deterministic_metrics(reference, candidate,
                                     args.expected_samples))
    print(json.dumps(metrics, indent=2) if args.json else metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
