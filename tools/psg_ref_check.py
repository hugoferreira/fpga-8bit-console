#!/usr/bin/env python3
"""Diff a render against a REAL PICO-8 recording of the same full music track.

tools/psg_preview_check.py compares our two renders against each other, and
tools/psg_oracle.py compares one assumption at a time over a few seconds. Neither
can answer "does a whole song come out right", which is the thing a listener
actually judges. This does: tools/p8_music_wav.py records the reference from
PICO-8 itself, and this aligns a render against it and localises the damage.

Alignment matters. PICO-8 starts recording a frame or so before music(), and our
render starts on sample 0, so a raw sample-by-sample diff of two CORRECT renders
still looks broken. The lag is estimated by cross-correlation and reported, so a
wild lag is itself a finding rather than a silent fudge.

Three numbers, because they fail independently:
  pitch     per-window autocorrelation pitch, agreeing within a semitone. Catches
            wrong notes, wrong octaves, detuned oscillators, scrambled phase.
  level     per-window RMS ratio. Catches a missing voice, a stuck envelope, or a
            channel mask that is off - all of which can leave pitch intact.
  spectrum  per-window log-magnitude cosine distance. Catches a wrong WAVEFORM at
            the right pitch and level, which the other two both pass.

Usage:
  psg_ref_check.py ref.wav cand.wav
  psg_ref_check.py ref.wav hw.wav pv.wav --labels hardware,preview --verbose
"""
from __future__ import annotations

import argparse
import sys
import wave

import numpy as np

RATE = 22050
WINDOW = 2205           # 0.1 s, as in tools/psg_preview_check.py
VOICED = 0.30           # normalised autocorrelation floor for "has a pitch"
TOLERANCE = 1.0         # semitones
LO_HZ, HI_HZ = 70.0, 1200.0


def load(path):
    with wave.open(path) as w:
        if w.getsampwidth() != 2:
            raise SystemExit(f"{path}: expected 16-bit PCM")
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
        if w.getnchannels() == 2:
            pcm = pcm.reshape(-1, 2).mean(axis=1)
        rate = w.getframerate()
    if rate != RATE:
        raise SystemExit(f"{path}: {rate} Hz, expected {RATE}")
    return pcm.astype(np.float64)


def align(reference, candidate, span=RATE // 2):
    """Lag L with reference[i] ~ candidate[i + L], for shift() below.

    Sign matters and is easy to get backwards: getting it wrong shifts the
    candidate the wrong way, which turns a render correlating at 0.97 into one
    correlating at -0.10 and reads as total corruption.
    """
    n = min(len(reference), len(candidate), RATE * 8)
    a = reference[:n] - reference[:n].mean()
    b = candidate[:n] - candidate[:n].mean()
    size = 1 << int(np.ceil(np.log2(2 * n)))
    corr = np.fft.irfft(np.fft.rfft(b, size) * np.conj(np.fft.rfft(a, size)), size)
    lags = np.concatenate([np.arange(0, span + 1), np.arange(-span, 0)])
    return int(lags[np.argmax(corr[lags])])


def shift(candidate, lag):
    """Candidate resampled onto the reference's timebase for `lag` from align()."""
    if lag > 0:
        return candidate[lag:]
    return np.concatenate([np.zeros(-lag), candidate])


def lock(reference, candidate, block=RATE // 2, span=8000):
    """Per-block (best lag, correlation): does the render track the reference?

    This is the sensitive test, and the one that found a real bug the pitch
    metric hid. Two renders of the same music correlate above ~0.85 at a single
    CONSTANT lag; a sequencer that slips shows a lag jump, and one that plays
    different notes shows correlation collapsing at every lag. Pitch agreement
    survives both, because a 0.1 s window of a three-voice mix reports whichever
    voice the autocorrelation locks onto.
    """
    # Drop the trailing partial block: a render one frame shorter than the
    # recording cannot fill it, and it reports as a lost lock on a good render.
    n = min(len(reference), len(candidate)) - block
    rows = []
    for s in range(max(0, n // block)):
        a = reference[s * block:(s + 1) * block]
        lo = max(0, s * block - span)
        b = candidate[lo:(s + 1) * block + span]
        if a.std() == 0 or b.std() == 0 or len(b) < len(a):
            continue
        a0, b0 = a - a.mean(), b - b.mean()
        size = 1 << int(np.ceil(np.log2(len(a0) + len(b0))))
        cc = np.fft.irfft(np.fft.rfft(b0, size) * np.conj(np.fft.rfft(a0, size)),
                          size)
        k = int(np.argmax(cc[:len(b0) - len(a0) + 1]))
        seg = candidate[k + lo:k + lo + len(a)]
        rows.append((s * block / RATE, k + lo - s * block,
                     float(np.corrcoef(a, seg)[0, 1])))
    return rows


def pitch(frame):
    """(hz, confidence) by autocorrelation; (0,0) when unvoiced.

    Autocorrelation, not an FFT peak: PICO-8 waveforms are harmonic-heavy and the
    strongest bin is routinely the second harmonic, which would report a
    consistent octave error and make a correct render look broken.
    """
    n = len(frame)
    x = frame - frame.mean()
    energy = float(x @ x)
    if energy < 1e6:
        return 0.0, 0.0
    size = 1 << int(np.ceil(np.log2(2 * n)))
    spec = np.fft.rfft(x, size)
    corr = np.fft.irfft(spec * np.conj(spec), size)[:n]
    lo, hi = max(1, int(RATE / HI_HZ)), min(int(RATE / LO_HZ), n // 2)
    if hi <= lo:
        return 0.0, 0.0
    lag = lo + int(np.argmax(corr[lo:hi]))
    # The argmax landing on an endpoint of the search range is not a period - it
    # is the correlation still climbing (or falling) as it leaves the window. A
    # noise/percussion window reports the floor lag this way, which reads as a
    # confident D#6 at exactly RATE/18 and made correct renders look wrong.
    if lag <= lo or lag >= hi - 1:
        return 0.0, 0.0
    if not (corr[lag] > corr[lag - 1] and corr[lag] > corr[lag + 1]):
        return 0.0, 0.0
    return RATE / lag, float(corr[lag] / energy)


def spectrum(frame):
    mag = np.abs(np.fft.rfft(frame * np.hanning(len(frame))))
    return np.log1p(mag)


def note(hz):
    if hz <= 0:
        return "-"
    midi = 69 + 12 * np.log2(hz / 440.0)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[int(round(midi)) % 12], int(round(midi)) // 12 - 1)


def compare(reference, candidate, label, verbose):
    lag = align(reference, candidate)
    shifted = shift(candidate, lag)
    windows = min(len(reference), len(shifted)) // WINDOW

    ref_hz, cand_hz = [], []
    rows, compared, agreed = [], 0, 0
    for i in range(windows):
        lo, hi = i * WINDOW, (i + 1) * WINDOW
        ref, cand = reference[lo:hi], shifted[lo:hi]
        rhz, rconf = pitch(ref)
        chz, _ = pitch(cand)
        ref_hz.append(rhz)
        cand_hz.append(chz)
        rrms = float(np.sqrt(np.mean(ref ** 2)))
        crms = float(np.sqrt(np.mean(cand ** 2)))
        rs, cs = spectrum(ref), spectrum(cand)
        cos = float(rs @ cs / (np.linalg.norm(rs) * np.linalg.norm(cs) + 1e-12))
        ok = None
        if rconf >= VOICED:
            err = abs(12 * np.log2(rhz / chz)) if chz > 0 else np.inf
            ok = err <= TOLERANCE
            compared += 1
            agreed += bool(ok)
        rows.append((i, rhz, chz, rrms, crms, cos, ok))

    # A window straddling a note change is a coin toss between the two notes, so
    # two CORRECT renders disagree there whenever their onsets land either side of
    # the boundary. That is window alignment, not a wrong note - it showed up as
    # ~10% "failure" on a render that is otherwise note-for-note exact. Forgive a
    # window whose pitch matches either neighbour of the reference; a genuinely
    # wrong note does not match its neighbours either.
    settled = 0
    for i in range(windows):
        if rows[i][6] is None:
            continue
        if cand_hz[i] <= 0:
            continue
        near = [ref_hz[j] for j in (i - 1, i, i + 1) if 0 <= j < windows]
        settled += any(h > 0 and abs(12 * np.log2(h / cand_hz[i])) <= TOLERANCE
                       for h in near)

    print(f"  {label}: lag {lag:+d} samples ({lag / RATE * 1000:+.1f} ms), "
          f"{windows} windows of 0.1 s")
    if compared:
        print(f"    pitch    {agreed}/{compared} voiced windows within "
              f"{TOLERANCE:.0f} semitone = {100 * agreed / compared:.1f}% "
              f"(forgiving one window of note-boundary slack: "
              f"{100 * settled / compared:.1f}%)")
    else:
        print("    pitch    no voiced windows in the REFERENCE - "
              "the reference itself is silent, nothing was compared")
    rrms = np.array([r[3] for r in rows])
    crms = np.array([r[4] for r in rows])
    live = rrms > 50
    if live.any():
        ratio = crms[live] / rrms[live]
        print(f"    level    rms ratio median {np.median(ratio):.2f} "
              f"(p10 {np.percentile(ratio, 10):.2f}, "
              f"p90 {np.percentile(ratio, 90):.2f}); "
              f"reference rms {rrms[live].mean():.0f}, render "
              f"{crms[live].mean():.0f}")
    cos = np.array([r[5] for r in rows])
    print(f"    spectrum cosine median {np.median(cos):.3f} "
          f"(p10 {np.percentile(cos, 10):.3f})")

    locks = lock(reference, candidate)
    if locks:
        held = [c for _, _, c in locks]
        modal = np.bincount([l + 20000 for _, l, c in locks if c > 0.70]).argmax() \
            - 20000 if any(c > 0.70 for _, _, c in locks) else None
        tracking = [abs(l - modal) <= 8 and c > 0.70 for _, l, c in locks] \
            if modal is not None else [False] * len(locks)
        print(f"    lock     correlation at best lag: median {np.median(held):.2f}; "
              f"tracks the reference in {sum(tracking)}/{len(locks)} half-second "
              f"blocks at a constant lag of {modal} samples")
        # The first block is the recording preamble; report where tracking is
        # lost for good, which is where a sequencer bug actually starts.
        last = len(tracking)
        while last > 0 and not tracking[last - 1]:
            last -= 1
        if last < len(tracking):
            print(f"    LOST LOCK for good after {last * 0.5:.1f}s of "
                  f"{len(locks) * 0.5:.1f}s")

    bad = [r for r in rows if r[6] is False]
    if bad and compared:
        print(f"    first mismatch at {bad[0][0] * 0.1:.1f}s "
              f"(reference {note(bad[0][1])}, render {note(bad[0][2])})")
    if verbose:
        print("      t/s     ref      render   err/st  rms ref/cand   cos")
        for i, rhz, chz, rr, cr, c, ok in rows:
            mark = "     " if ok is None else ("  ok " if ok else " BAD ")
            err = ("%6.2f" % abs(12 * np.log2(rhz / chz))
                   if rhz > 0 and chz > 0 else "   inf")
            print(f"    {i * 0.1:6.1f} {note(rhz):>6}({rhz:6.1f}) "
                  f"{note(chz):>6}({chz:6.1f}) {err} "
                  f"{rr:7.0f}/{cr:7.0f} {c:5.3f} {mark}")
    return (agreed / compared) if compared else 0.0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="wav recorded from real PICO-8")
    ap.add_argument("candidate", nargs="+")
    ap.add_argument("--labels", help="comma-separated names for the candidates")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    reference = load(args.reference)
    labels = (args.labels.split(",") if args.labels
              else [c.split("/")[-1] for c in args.candidate])
    print(f"reference {args.reference}: {len(reference) / RATE:.2f}s, "
          f"peak {np.abs(reference).max():.0f}, "
          f"rms {np.sqrt(np.mean(reference ** 2)):.0f}")
    worst = 1.0
    for path, label in zip(args.candidate, labels):
        cand = load(path)
        print(f"  {label} {path}: {len(cand) / RATE:.2f}s, "
              f"peak {np.abs(cand).max():.0f}, "
              f"rms {np.sqrt(np.mean(cand ** 2)):.0f}")
        worst = min(worst, compare(reference, cand, label, args.verbose))
    return 0 if worst >= 0.85 else 1


if __name__ == "__main__":
    sys.exit(main())
