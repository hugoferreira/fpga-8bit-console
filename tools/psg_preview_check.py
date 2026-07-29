#!/usr/bin/env python3
"""The PSG preview path's gate: does the simulator play the same TUNE as hardware?

`make run` is the ONLY consumer of the PSG's REALTIME_PREVIEW schedule, and the
59-render oracle cannot see that schedule at all - the oracle builds
REALTIME_PREVIEW=0, so every `if (REALTIME_PREVIEW)` arm is invisible to it by
construction. That blind spot is why the interactive console went out of tune
(5bdead3 left the preview oscillator store map on the pre-crossfade layout, so the
phase was scrambled every sample) and then silent (4658091 stopped deferring an
overrun sample boundary, so the walk restarted forever and never wrote dry16) with
every commit's gates green.

This compares the preview render against the HARDWARE render of the same cart.
The hardware render is the trustworthy reference: it is byte-exact against PICO-8
across all 59 oracle cases.

The assertion is PITCH AGREEMENT, not byte equality, and that is deliberate. The
preview schedule is an approximation on purpose - it skips the old-state crossfade
and folds fewer terms - so a byte gate would be false-red on every legitimate
preview change. "Plays the same notes as the hardware" is the property that
actually broke, twice, and it is what this measures.

Two clocks matter and must not be conflated:
  --preview-clk   the clock the preview MODEL was compiled for. Default 28.125 MHz,
                  i.e. generous, which answers "is the preview schedule CORRECT?"
  --console-clk   3,506,580, what `make run` actually supplies, which answers
                  "does it FIT?". A schedule can be correct and not fit; those are
                  separate failures with separate fixes.
"""

from __future__ import annotations

import argparse
import array
import math
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARDWARE_CLK = 28_125_000
RATE = 22050

# Windows of 0.1 s. Long enough for autocorrelation to lock onto a bass note
# (70 Hz needs ~315 samples), short enough that a note change is not smeared.
WINDOW = 2205
# Below this normalised autocorrelation peak the window is unvoiced/silent and is
# not compared - percussion and gaps must not count as disagreement.
VOICED = 0.30
# A window counts as agreeing if the two pitches are within this many semitones.
# One semitone: anything looser would pass a transposed melody.
TOLERANCE = 1.0


def render(binary: Path, audio: Path, out: Path, *, clk: int,
           music: int | None, sfx: int | None, mask: int, seconds: float) -> None:
    cmd = [str(binary), "--audio", str(audio), "--mask", str(mask),
           "--seconds", str(seconds), "--clk", str(clk), "--out", str(out)]
    cmd += ["--sfx", str(sfx)] if sfx is not None else ["--music", str(music or 0)]
    subprocess.run(cmd, cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load(path: Path) -> array.array:
    with wave.open(str(path)) as handle:
        pcm = array.array("h")
        pcm.frombytes(handle.readframes(handle.getnframes()))
    return pcm


def pitch(samples, lo_hz: float = 70.0, hi_hz: float = 1200.0):
    """Autocorrelation pitch. Returns (hz, confidence); (0, 0) when unvoiced.

    Autocorrelation rather than a spectral peak on purpose: the strongest FFT bin
    is often a harmonic, which reports an octave error and would make a correct
    render look broken.
    """
    n = len(samples)
    if n == 0:
        return 0.0, 0.0
    mean = sum(samples) / n
    centred = [v - mean for v in samples]
    energy = sum(v * v for v in centred)
    if energy < 1e6:                      # silence
        return 0.0, 0.0
    lo = max(1, int(RATE / hi_hz))
    hi = min(int(RATE / lo_hz), n // 2)
    best_lag, best = 0, 0.0
    for lag in range(lo, hi):
        acc = 0.0
        for i in range(n - lag):
            acc += centred[i] * centred[i + lag]
        norm = acc / energy
        if norm > best:
            best_lag, best = lag, norm
    return (RATE / best_lag if best_lag else 0.0), best


def semitones(a: float, b: float) -> float:
    if a <= 0 or b <= 0:
        return math.inf
    return abs(12.0 * math.log2(a / b))


def note_name(hz: float) -> str:
    if hz <= 0:
        return "-"
    midi = 69 + 12 * math.log2(hz / 440.0)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[int(round(midi)) % 12], int(round(midi)) // 12 - 1)


def compare(reference, candidate, *, label: str, min_agreement: float,
            verbose: bool) -> bool:
    windows = min(len(reference), len(candidate)) // WINDOW
    compared = agreed = 0
    rows = []
    for i in range(windows):
        lo, hi = i * WINDOW, (i + 1) * WINDOW
        ref_hz, ref_conf = pitch(reference[lo:hi])
        cand_hz, cand_conf = pitch(candidate[lo:hi])
        if ref_conf < VOICED:
            rows.append((i, ref_hz, cand_hz, None))
            continue
        compared += 1
        ok = semitones(ref_hz, cand_hz) <= TOLERANCE
        agreed += ok
        rows.append((i, ref_hz, cand_hz, ok))

    if verbose:
        print("    %-6s %-8s %-8s" % ("win", "hardware", label))
        for i, ref_hz, cand_hz, ok in rows:
            mark = "skip" if ok is None else ("ok" if ok else "MISMATCH")
            print("    %-6d %-8s %-8s %s"
                  % (i, note_name(ref_hz), note_name(cand_hz), mark))

    if compared == 0:
        print("    FAIL: no voiced windows in the hardware reference - "
              "the reference render is silent, so nothing was actually compared")
        return False

    ratio = agreed / compared
    print("    %s: %d/%d voiced windows agree within %.0f semitone (%.0f%%), "
          "need %.0f%%" % (label, agreed, compared, TOLERANCE,
                           100 * ratio, 100 * min_agreement))
    return ratio >= min_agreement


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cart", type=Path, required=True,
                        help="a .p8.png cart, or a raw 4608-byte audio image")
    parser.add_argument("--preview", type=Path,
                        default=ROOT / "build/obj_psg_pv/psg_wav")
    # NOT build/obj_psg/psg_wav: that one is compiled for psg.sv's DEFAULT CLK_HZ
    # (3,506,580). Driving it with --clk 28125000 detunes its sample divider and it
    # renders silence - the failure sim/psg_wav.cpp's header warns about ("The value
    # must match the model's -GCLK_HZ or the divider detunes"). Left None so we
    # build/reuse a clock-matched model via tools/psg_oracle_render.py instead.
    parser.add_argument("--hardware", type=Path, default=None,
                        help="clock-matched hardware model; built on demand")
    parser.add_argument("--preview-clk", type=int, default=HARDWARE_CLK,
                        help="clock the preview model was compiled for")
    parser.add_argument("--console-clk", type=int, default=3_506_580,
                        help="informational: what `make run` supplies")
    parser.add_argument("--music", type=int, default=0)
    parser.add_argument("--sfx", type=int)
    parser.add_argument("--mask", type=int, default=7)
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--min-agreement", type=float, default=0.85)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    out = ROOT / "build/psg_preview_check"
    out.mkdir(parents=True, exist_ok=True)

    if args.cart.suffix == ".png" or args.cart.name.endswith(".p8.png"):
        sys.path.insert(0, str(ROOT / "tools"))
        from p8_audio import rom_from_png
        image = out / "audio.bin"
        image.write_bytes(rom_from_png(str(args.cart))[0x3100:0x4300])
    else:
        image = args.cart

    if not args.preview.exists():
        print("missing preview model %s - run `make psg-wav-preview` first"
              % args.preview)
        return 1

    # Reuse the oracle renderer's builder: it already compiles psg.sv at a given
    # -GCLK_HZ into build/psg_oracle/obj_<hz>/ and caches on mtime.
    if args.hardware is None:
        sys.path.insert(0, str(ROOT / "tools"))
        import psg_oracle_render
        args.hardware = psg_oracle_render.build(
            HARDWARE_CLK, ROOT / "build/psg_oracle", 8)

    what = ("sfx %d" % args.sfx) if args.sfx is not None else ("music %d" % args.music)
    print("cart %s, %s, mask %d, %.1fs" % (args.cart.name, what, args.mask,
                                           args.seconds))

    hw_wav = out / "hardware.wav"
    pv_wav = out / "preview.wav"
    render(args.hardware, image, hw_wav, clk=HARDWARE_CLK, music=args.music,
           sfx=args.sfx, mask=args.mask, seconds=args.seconds)
    render(args.preview, image, pv_wav, clk=args.preview_clk, music=args.music,
           sfx=args.sfx, mask=args.mask, seconds=args.seconds)

    hardware, preview = load(hw_wav), load(pv_wav)
    if not any(hardware):
        print("    FAIL: the HARDWARE render is silent - that is not a preview bug")
        return 1
    if not any(preview):
        print("    FAIL: the preview render is silent (walk never completes, or "
              "dry16 is never written)")
        return 1

    label = "preview @%d clk/sample" % (args.preview_clk // RATE)
    ok = compare(hardware, preview, label=label,
                 min_agreement=args.min_agreement, verbose=args.verbose)
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
