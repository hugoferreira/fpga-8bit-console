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

`--all-channels` is the soundtrack gate. It checks the combined mix, then makes
four private copies of the audio image with all but one music-pattern byte disabled.
The PSG's `$21` mask is advisory reservation state and does not select channels;
sweeping `--mask` therefore renders the same tune repeatedly and proves nothing
about a dropped channel. Each active isolated channel gates pitch, RMS and active
sample occupancy; a source-inactive channel must remain silent in preview.

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
import subprocess
import sys
from pathlib import Path

import audio_analysis
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HARDWARE_CLK = 28_125_000
RATE = audio_analysis.RATE
AUDIO_BYTES = 4608


def render(binary: Path, audio: Path, out: Path, *, clk: int,
           music: int | None, sfx: int | None, mask: int, seconds: float) -> None:
    cmd = [str(binary), "--audio", str(audio), "--mask", str(mask),
           "--seconds", str(seconds), "--clk", str(clk), "--out", str(out)]
    cmd += ["--sfx", str(sfx)] if sfx is not None else ["--music", str(music or 0)]
    subprocess.run(cmd, cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def isolate_music_channel(source: Path, out: Path, channel: int) -> Path:
    """Disable the other three pattern bytes in every PICO-8 music row."""
    image = bytearray(source.read_bytes())
    if len(image) != AUDIO_BYTES:
        raise ValueError(f"{source} is {len(image)} bytes, expected {AUDIO_BYTES}")
    for pattern in range(64):
        for other in range(4):
            if other != channel:
                image[pattern * 4 + other] |= 0x40
    out.write_bytes(image)
    return out


def activity(samples, floor: int = 64) -> float:
    """Share of samples above a deliberately low non-silence floor."""
    if len(samples) == 0:
        return 0.0
    wide = np.asarray(samples, dtype=np.int32)
    return float(np.count_nonzero(np.abs(wide) >= floor) / len(wide))


def check_render(*, args, image: Path, out: Path, hardware: Path,
                 label: str, require_pitch: bool) -> bool:
    slug = label.replace(" ", "-")
    hw_wav = out / f"hardware-{slug}.wav"
    pv_wav = out / f"preview-{slug}.wav"
    render(hardware, image, hw_wav, clk=HARDWARE_CLK, music=args.music,
           sfx=args.sfx, mask=args.mask, seconds=args.seconds)
    render(args.preview, image, pv_wav, clk=args.preview_clk, music=args.music,
           sfx=args.sfx, mask=args.mask, seconds=args.seconds)

    hardware_audio = audio_analysis.load_wav(hw_wav)
    preview_audio = audio_analysis.load_wav(pv_wav)
    print(f"  {label}:")
    if not np.any(hardware_audio):
        if require_pitch:
            print("    FAIL: the hardware render is silent - this is not a "
                  "preview bug")
            return False
        if np.any(preview_audio):
            print("    FAIL: hardware says this music channel is inactive, "
                  "but preview emits audio")
            return False
        print("    SKIP: inactive in both hardware and preview")
        return True
    if not np.any(preview_audio):
        print("    FAIL: hardware channel is active but preview is silent")
        return False

    clock_label = "preview @%d clk/sample" % (args.preview_clk // RATE)
    pitch = audio_analysis.pitch_agreement(hardware_audio, preview_audio)
    if pitch.compared:
        pitch_ok = audio_analysis.report_pitch_agreement(
            hardware_audio, preview_audio, label=clock_label,
            min_agreement=args.min_agreement, verbose=args.verbose)
    else:
        print("    pitch: no stable voiced windows; checking level/activity")
        pitch_ok = not require_pitch

    hw_rms = audio_analysis.rms(hardware_audio)
    pv_rms = audio_analysis.rms(preview_audio)
    rms_ratio = pv_rms / hw_rms
    hw_active = activity(hardware_audio)
    pv_active = activity(preview_audio)
    active_ratio = pv_active / hw_active if hw_active else 1.0
    rms_ok = args.min_rms_ratio <= rms_ratio <= args.max_rms_ratio
    active_ok = active_ratio >= args.min_active_ratio
    print("    level: RMS %.0f -> %.0f (%.1f%%, need %.0f%%..%.0f%%); "
          "activity %.1f%% -> %.1f%% (%.1f%%, need >=%.0f%%) %s"
          % (hw_rms, pv_rms, 100 * rms_ratio,
             100 * args.min_rms_ratio, 100 * args.max_rms_ratio,
             100 * hw_active, 100 * pv_active, 100 * active_ratio,
             100 * args.min_active_ratio,
             "PASS" if rms_ok and active_ok else "FAIL"))
    return pitch_ok and rms_ok and active_ok


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
    parser.add_argument("--mask", type=int, default=7,
                        help="advisory reservation mask; it does not isolate "
                             "music channels")
    channels = parser.add_mutually_exclusive_group()
    channels.add_argument("--solo-channel", type=int, choices=range(4),
                          help="disable the other three pattern channels")
    channels.add_argument("--all-channels", action="store_true",
                          help="check the combined mix and each isolated "
                               "pattern channel")
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--min-agreement", type=float, default=0.85)
    parser.add_argument("--min-rms-ratio", type=float, default=0.5)
    parser.add_argument("--max-rms-ratio", type=float, default=2.0)
    parser.add_argument("--min-active-ratio", type=float, default=0.5)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if args.sfx is not None and (args.solo_channel is not None
                                 or args.all_channels):
        parser.error("music-channel isolation cannot be used with --sfx")

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

    what = (("sfx %d" % args.sfx) if args.sfx is not None
            else ("music %d" % args.music))
    print("cart %s, %s, reservation mask %d, %.1fs"
          % (args.cart.name, what, args.mask, args.seconds))

    jobs = []
    if args.solo_channel is not None:
        isolated = isolate_music_channel(
            image, out / f"audio-channel-{args.solo_channel}.bin",
            args.solo_channel)
        jobs.append((f"channel {args.solo_channel}", isolated, False))
    else:
        jobs.append(("combined", image, True))
        if args.all_channels:
            for channel in range(4):
                isolated = isolate_music_channel(
                    image, out / f"audio-channel-{channel}.bin", channel)
                jobs.append((f"channel {channel}", isolated, False))

    ok = True
    for label, job_image, require_pitch in jobs:
        ok = check_render(args=args, image=job_image, out=out,
                          hardware=args.hardware, label=label,
                          require_pitch=require_pitch) and ok
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
