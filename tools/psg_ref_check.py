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

Independent measurements, because they fail independently:
  pitch     per-window autocorrelation pitch, agreeing within a semitone. Catches
            wrong notes, wrong octaves, detuned oscillators, scrambled phase.
  level     per-window RMS ratio. Catches a missing voice, a stuck envelope, or a
            channel mask that is off - all of which can leave pitch intact.
  spectrum  per-window log-magnitude cosine distance. Catches a wrong WAVEFORM at
            the right pitch and level, which the other two both pass.
  bands     absolute candidate/reference level in four frequency bands, over the
            whole track and the quietest reference windows. Catches spectral
            tilt and a noise floor that fails to recede during quiet passages.
On an UNPITCHED reference (noise, percussion) pitch and lock cannot succeed even
for a perfect render, so they are withheld and contour is reported instead.

--spectrogram adds the picture those numbers summarise: the panels drawn side by
side, same axes, same dB scale, so a missing voice or a wrong harmonic series is
visible rather than inferred from a cosine. Frequency runs across and time runs
UP, so the same instant sits at the same height in every panel and a note is a
horizontal bar you can follow from one to the next; a long track then costs
lines, which a terminal has, rather than columns, which it does not.
--spectrogram-file writes the same panels to an image at full STFT resolution,
which is where vibrato and one-frame dropouts show up.

Given ONE wav there is nothing to compare, so the spectrogram is the whole
report and is drawn without being asked for. `-` reads a wav from stdin.
With candidates, exit status 0 means every applicable gate passed, 1 means at
least one comparison failed, and 2 means the invocation was invalid.

Usage:
  psg_ref_check.py ref.wav cand.wav
  psg_ref_check.py ref.wav cand.wav --spectrogram
  psg_ref_check.py ref.wav cand.wav --spectrogram-file build/diff.png
  psg_ref_check.py ref.wav cand.wav --spectrogram --spectrogram-range 12:16
  psg_ref_check.py ref.wav hw.wav pv.wav --labels hardware,preview --verbose
  psg_ref_check.py one.wav                      # just look at it
  build/obj_dir/console --audio-wav - | psg_ref_check.py -
"""
from __future__ import annotations

import argparse
import io
import os
import shutil
import sys
import wave
from dataclasses import dataclass

import numpy as np

RATE = 22050
WINDOW = 2205           # 0.1 s, as in tools/psg_preview_check.py
VOICED = 0.30           # normalised autocorrelation floor for "has a pitch"
TOLERANCE = 1.0         # semitones
LO_HZ, HI_HZ = 70.0, 1200.0
# Below this share of voiced reference windows the material is noise or
# percussion, and pitch and lock stop meaning anything - see contour().
PITCHED_MIN = 0.25

# A cosine says whether two spectra have a similar SHAPE, but is deliberately
# insensitive to a small, systematic excess spread over thousands of bins.
# Celeste music 30 exposed that blind spot: total RMS and cosine passed while
# 4..8 kHz energy stayed visibly and audibly high in every quiet passage.
#
# One-second windows reduce random-realisation variance; a half-second hop keeps
# fades localized. "Quiet" is selected from the reference, never the candidate,
# so a noisy candidate cannot move the goalposts by making itself look active.
BAND_WINDOW = RATE
BAND_HOP = RATE // 2
BANDS = ((55.0, 250.0, "55-250 Hz"),
         (250.0, 1000.0, "250 Hz-1 kHz"),
         (1000.0, 4000.0, "1-4 kHz"),
         (4000.0, 8000.0, "4-8 kHz"))
BAND_MIN_SHARE = 0.005
BAND_LIVE_POWER_FLOOR = 1e-6  # ignore true silence, 60 dB below the loudest window
BAND_TOL_DB = 1.5             # 41% power: broad enough for RNG, below a 2x excess
QUIET_QUANTILE = 0.35
MIN_QUIET_WINDOWS = 3

# Noise has no stable sample correlation. Align its smoothed power envelope
# instead, at 5 ms resolution, before calculating windows or drawing panels.
ENVELOPE_HOP = RATE // 200

SPEC_FFT = 1024         # 46 ms, ~21.5 Hz bins: resolves a bass note's harmonics
SPEC_LO_HZ, SPEC_HI_HZ = 55.0, 8000.0
SPEC_DYNAMIC_DB = 60.0  # everything this far under the loudest cell reads as floor
SPEC_LINES_PER_SEC = 2  # text lines per second of audio; each holds two slices
SPEC_MAX_LINES = 120    # a minute of scrollback per panel is already a lot
SPEC_GAP = 3            # blank columns between panels
SPEC_GUTTER = 6         # "12.5s" plus the axis glyph
# Black -> blue -> purple -> red -> orange -> yellow -> white, monotone in
# luminance so the ramp still reads as "louder" on a terminal that renders the
# 256-colour cube badly. 16 steps quantises 60 dB to ~4 dB; SPEC_RGB is the same
# ramp at 24-bit, used when the terminal says it can take it.
SPEC_RAMP = [16, 17, 18, 53, 54, 90, 91, 127, 162, 197, 203, 209, 215, 221, 227, 231]
SPEC_RGB = [(0, 0, 4), (24, 15, 62), (68, 15, 118), (114, 31, 129), (158, 47, 127),
            (205, 64, 113), (240, 96, 93), (251, 151, 106), (254, 201, 141),
            (252, 253, 191)]
SPEC_ASCII = " .:-=+*#%@"
# All 16 ways to split a 2x2 cell into foreground and background, indexed by
# bits (upper-left 1, upper-right 2, lower-left 4, lower-right 8).
SPEC_QUADRANTS = " ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█"
TOO_SHORT = ("    spectrogram: less than %.0f ms of audio, nothing to draw"
             % (SPEC_FFT / RATE * 1000))


# ----------------------------------------------------------------- input ----

def load(path):
    """16-bit PCM at RATE as float64, mono. `-` reads stdin.

    stdin is buffered into memory first: the wave module seeks, a pipe does not,
    and a track is a few megabytes.
    """
    source = io.BytesIO(sys.stdin.buffer.read()) if path == "-" else path
    with wave.open(source) as w:
        if w.getsampwidth() != 2:
            raise SystemExit(f"{path}: expected 16-bit PCM")
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
        if w.getnchannels() == 2:
            pcm = pcm.reshape(-1, 2).mean(axis=1)
        rate = w.getframerate()
    if rate != RATE:
        raise SystemExit(f"{path}: {rate} Hz, expected {RATE}")
    return pcm.astype(np.float64)


def name(path):
    return "stdin" if path == "-" else path.split("/")[-1]


def describe(path, samples, indent=""):
    print(f"{indent}{path}: {len(samples) / RATE:.2f}s, "
          f"peak {np.abs(samples).max():.0f}, "
          f"rms {np.sqrt(np.mean(samples ** 2)):.0f}")


# --------------------------------------------------------------- metrics ----

def correlation_lag(reference, candidate, span):
    """Lag L with reference[i] ~ candidate[i + L] for arbitrary 1-D series."""
    n = min(len(reference), len(candidate))
    if n < 2:
        return 0
    a = reference[:n] - reference[:n].mean()
    b = candidate[:n] - candidate[:n].mean()
    size = 1 << int(np.ceil(np.log2(2 * n)))
    span = min(span, size // 2)
    corr = np.fft.irfft(np.fft.rfft(b, size) * np.conj(np.fft.rfft(a, size)), size)
    lags = np.concatenate([np.arange(0, span + 1), np.arange(-span, 0)])
    return int(lags[np.argmax(corr[lags])])


def align(reference, candidate, span=RATE // 2):
    """Lag L with reference[i] ~ candidate[i + L], for shift() below.

    Sign matters and is easy to get backwards: getting it wrong shifts the
    candidate the wrong way, which turns a render correlating at 0.97 into one
    correlating at -0.10 and reads as total corruption.
    """
    n = min(len(reference), len(candidate), RATE * 8)
    if n < 2:
        return 0
    return correlation_lag(reference[:n], candidate[:n], span)


def power_envelope(samples, window=WINDOW, hop=ENVELOPE_HOP):
    """Windowed RMS envelope, sampled every `hop` samples."""
    if len(samples) < window:
        return np.zeros(0)
    squared = samples.astype(np.float64) ** 2
    summed = np.concatenate(([0.0], np.cumsum(squared)))
    power = (summed[window:] - summed[:-window]) / window
    return np.sqrt(np.maximum(power, 0.0))[::hop]


def align_envelope(reference, candidate, span=RATE // 2):
    """Align unpitched material by its deterministic loudness trajectory."""
    a, b = power_envelope(reference), power_envelope(candidate)
    lag = correlation_lag(a, b, max(1, span // ENVELOPE_HOP))
    return lag * ENVELOPE_HOP


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


def contour(reference, candidate, window=WINDOW):
    """Correlation of the loudness and timbre TRAJECTORIES.

    The metric for unpitched material. Noise has no period to measure, and two
    correct noise renders share no samples unless they share a random number
    generator - so pitch and lock both read as total failure on a render that is
    right. What can be compared is the shape over time: a swept noise voice gets
    louder and brighter on a trajectory, and reproducing that trajectory IS
    reproducing the sound.
    """
    n = min(len(reference), len(candidate)) // window
    if n < 4:
        return None

    def traj(x):
        rms, cen = [], []
        for i in range(n):
            seg = x[i * window:(i + 1) * window]
            mag = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
            freqs = np.fft.rfftfreq(len(seg), 1 / RATE)
            rms.append(np.sqrt((seg ** 2).mean()))
            cen.append((mag * freqs).sum() / max(mag.sum(), 1e-9))
        return np.array(rms), np.array(cen)

    a_rms, a_cen = traj(reference)
    b_rms, b_cen = traj(candidate)
    if a_rms.std() == 0 or b_rms.std() == 0:
        return None
    return (float(np.corrcoef(a_rms, b_rms)[0, 1]),
            float(np.corrcoef(a_cen, b_cen)[0, 1]))


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


def reference_pitchiness(samples):
    """Fraction of complete analysis windows with a stable reference period."""
    windows = len(samples) // WINDOW
    if not windows:
        return 0.0
    voiced = sum(pitch(samples[i * WINDOW:(i + 1) * WINDOW])[1] >= VOICED
                 for i in range(windows))
    return voiced / windows


def db_ratio(candidate_power, reference_power):
    """Power ratio in dB, retaining infinities as an honest hard failure."""
    if reference_power <= 0:
        return None
    if candidate_power <= 0:
        return float("-inf")
    return float(10.0 * np.log10(candidate_power / reference_power))


@dataclass(frozen=True)
class BandBalance:
    label: str
    whole_db: float | None
    local_db: float | None
    quiet_db: float | None
    windows: int
    quiet_windows: int

    def failures(self, tolerance=BAND_TOL_DB):
        failed = []
        if self.whole_db is not None and abs(self.whole_db) > tolerance:
            failed.append("whole")
        if self.quiet_db is not None and abs(self.quiet_db) > tolerance:
            failed.append("quiet")
        return failed


def band_balance(reference, candidate):
    """Absolute spectral-level comparison, including reference-selected troughs.

    Each row is measured independently before robust aggregation. A band must
    carry at least BAND_MIN_SHARE of reference power in a window to participate;
    this prevents near-empty harmonic bands from producing enormous meaningless
    ratios. Whole-track values sum power, while local and quiet values are
    medians so a single transition cannot dominate the verdict.
    """
    n = min(len(reference), len(candidate))
    if n < BAND_WINDOW:
        return []

    window = np.hanning(BAND_WINDOW)
    freqs = np.fft.rfftfreq(BAND_WINDOW, 1 / RATE)
    rows = []
    for start in range(0, n - BAND_WINDOW + 1, BAND_HOP):
        ref = reference[start:start + BAND_WINDOW]
        cand = candidate[start:start + BAND_WINDOW]
        ref_power = np.abs(np.fft.rfft((ref - ref.mean()) * window)) ** 2
        cand_power = np.abs(np.fft.rfft((cand - cand.mean()) * window)) ** 2
        full = (freqs >= BANDS[0][0]) & (freqs < BANDS[-1][1])
        total = float(ref_power[full].sum())
        powers = []
        for lo_hz, hi_hz, _ in BANDS:
            mask = (freqs >= lo_hz) & (freqs < hi_hz)
            powers.append((float(ref_power[mask].sum()),
                           float(cand_power[mask].sum())))
        rows.append((total, powers))

    totals = np.array([row[0] for row in rows])
    live = totals > max(float(totals.max()) * BAND_LIVE_POWER_FLOOR, 1e-9)
    if not live.any():
        return []
    quiet_ceiling = float(np.quantile(totals[live], QUIET_QUANTILE))
    quiet = live & (totals <= quiet_ceiling)

    results = []
    for band_index, (_, _, label) in enumerate(BANDS):
        active = np.array(
            [is_live and powers[band_index][0] >= BAND_MIN_SHARE * total
             for is_live, (total, powers) in zip(live, rows)])
        local = []
        quiet_local = []
        ref_sum = cand_sum = 0.0
        for index, (_, powers) in enumerate(rows):
            if not active[index]:
                continue
            ref_power, cand_power = powers[band_index]
            value = db_ratio(cand_power, ref_power)
            ref_sum += ref_power
            cand_sum += cand_power
            local.append(value)
            if quiet[index]:
                quiet_local.append(value)
        quiet_value = (float(np.median(quiet_local))
                       if len(quiet_local) >= MIN_QUIET_WINDOWS else None)
        results.append(BandBalance(
            label=label,
            whole_db=db_ratio(cand_sum, ref_sum) if local else None,
            local_db=float(np.median(local)) if local else None,
            quiet_db=quiet_value,
            windows=len(local),
            quiet_windows=len(quiet_local),
        ))
    return results


def note(hz):
    if hz <= 0:
        return "-"
    midi = 69 + 12 * np.log2(hz / 440.0)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[int(round(midi)) % 12], int(round(midi)) // 12 - 1)


# ----------------------------------------------------- spectrogram data ----

def stft(samples, size=SPEC_FFT):
    """(frames, bins) magnitude spectra, hop = size/2."""
    hop = size // 2
    if len(samples) < size:
        return np.zeros((0, size // 2 + 1))
    frames = 1 + (len(samples) - size) // hop
    idx = np.arange(size)[None, :] + hop * np.arange(frames)[:, None]
    return np.abs(np.fft.rfft(samples[idx] * np.hanning(size), axis=1))


def spectrogram(samples, times, bands):
    """(bands, times) dB, band 0 = lowest, averaged - not sampled.

    Each time slice spans total/times seconds, which is far longer than one FFT
    frame, so a slice shows the MEAN of every frame inside it. Sampling one
    frame per slice instead would make a correct render look intermittent: at
    30 s over 50 slices each frame would represent 8% of its slice, and which
    8% it lands on is arbitrary.
    """
    mag = stft(samples)
    if not len(mag) or times < 1 or bands < 1:
        return None

    # Log-spaced bands, because a wrong octave has to be as visible in the bass
    # as it is at the top - linear rows would give the bottom three octaves one
    # row between them.
    edges = np.geomspace(SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2), bands + 1)
    bins = np.arange(mag.shape[1]) * RATE / SPEC_FFT
    # PEAK within the band, not the mean: the top band spans ~90 bins, and a
    # single strong harmonic averaged against its 89 empty neighbours reads as
    # silence.
    band = np.empty((bands, len(mag)))
    for r in range(bands):
        sel = (bins >= edges[r]) & (bins < edges[r + 1])
        if not sel.any():   # band narrower than a bin (the bottom bands)
            sel = np.zeros(len(bins), bool)
            sel[int(np.argmin(np.abs(bins - np.sqrt(edges[r] * edges[r + 1]))))] = True
        band[r] = mag[:, sel].max(axis=1)

    group = np.zeros((len(mag), times))
    cut = np.linspace(0, len(mag), times + 1).astype(int)
    for c in range(times):
        lo, hi = cut[c], min(max(cut[c] + 1, cut[c + 1]), len(mag))
        group[lo:hi, c] = 1.0 / (hi - lo)

    return 20 * np.log10(band @ group + 1e-9), edges


def scale(panels):
    """(floor, ceiling) dB shared by every panel.

    ONE scale for all of them. Normalising each panel to its own peak would hide
    exactly the fault the level metric exists to catch: a render at half the
    reference's amplitude would draw identically to a correct one.
    """
    ceiling = max(float(db.max()) for db in panels)
    # Averaging frames into slices lifts the floor, so a fixed 60 dB window
    # leaves a third of the ramp unused and flattens the picture. Take the
    # quietest cell any panel actually has, bounded by that window.
    quietest = float(np.percentile(np.concatenate([db.ravel() for db in panels]), 1))
    return max(ceiling - SPEC_DYNAMIC_DB, quietest), ceiling


# ------------------------------------------------------ terminal drawing ----

def truecolor():
    """Does the terminal advertise 24-bit colour? Force with COLORTERM=truecolor."""
    return os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit")


def rgb(values):
    """Interpolate SPEC_RGB at `values` in 0..1; (..., 3) of ints."""
    table = np.array(SPEC_RGB, dtype=float)
    at = np.clip(values, 0.0, 1.0) * (len(table) - 1)
    lo = np.floor(at).astype(int)
    hi = np.minimum(lo + 1, len(table) - 1)
    frac = (at - lo)[..., None]
    return np.rint(table[lo] * (1 - frac) + table[hi] * frac).astype(int)


def two_tone(quad):
    """Best two-colour approximation of each 2x2 cell.

    A character cell carries four subcells but only two colours, so each cell is
    partitioned into a bright group (foreground) and a dark one (background).
    Sorting the four values makes the optimum one of three splits - a partition
    minimising within-group spread is always contiguous in sorted order - so the
    exhaustive answer costs three vectorised passes, not a search.

    Returns (glyph pattern bits, foreground level, background level).
    """
    order = np.sort(quad, axis=-1)
    total = np.cumsum(order, axis=-1)
    square = np.cumsum(order ** 2, axis=-1)
    best_sse, best_k = None, None
    for k in (1, 2, 3):                     # k values in the dark group
        dark_sum, dark_sq = total[..., k - 1], square[..., k - 1]
        light_sum = total[..., 3] - dark_sum
        light_sq = square[..., 3] - dark_sq
        sse = (dark_sq - dark_sum ** 2 / k) + (light_sq - light_sum ** 2 / (4 - k))
        if best_sse is None:
            best_sse, best_k = sse, np.full(sse.shape, k)
        else:
            better = sse < best_sse
            best_sse, best_k = np.where(better, sse, best_sse), \
                np.where(better, k, best_k)

    k = best_k[..., None]
    cut = (np.take_along_axis(order, k - 1, -1)
           + np.take_along_axis(order, k, -1)) / 2
    light = quad >= cut
    lit = light.sum(-1)
    fore = (quad * light).sum(-1) / np.maximum(lit, 1)
    back = (quad * ~light).sum(-1) / np.maximum(4 - lit, 1)
    return (light * np.array([1, 2, 4, 8])).sum(-1), fore, back


def panel(db, floor, ceiling, color):
    """One spectrogram as db.shape[0]/2 text lines.

    `db` is time-major and latest-first: row 0 is the newest slice, drawn on the
    top line, because time runs UP the page. In colour each character is a 2x2
    quadrant cell - two time slices by two frequency bands - so a panel of N
    columns carries 2N bands; in ASCII it is one band per column.
    """
    # max(): two silent files put ceiling on the floor, and a flat panel is the
    # right answer for silence - not a division by zero.
    norm = np.clip((db - floor) / max(ceiling - floor, 1e-9), 0.0, 1.0)
    rows, bands = db.shape
    lines = rows // 2

    if not color:
        idx = np.rint(norm.reshape(lines, 2, bands).mean(axis=1)
                      * (len(SPEC_ASCII) - 1)).astype(int)
        return ["".join(SPEC_ASCII[v] for v in row) for row in idx]

    cols = bands // 2
    # (line, time half, column, band half) -> (line, column, [UL, UR, LL, LR]),
    # matching the bit weights in SPEC_QUADRANTS. Time half 0 is the later slice
    # (rows are latest-first) and band half 0 is the lower frequency.
    quad = norm.reshape(lines, 2, cols, 2).transpose(0, 2, 1, 3).reshape(lines, cols, 4)
    pattern, fore, back = two_tone(quad)

    if truecolor():
        escape = "\x1b[38;2;%d;%d;%d;48;2;%d;%d;%dm"
        fore, back = rgb(fore), rgb(back)
    else:
        escape = "\x1b[38;5;%d;48;5;%dm"
        steps = np.array(SPEC_RAMP)
        fore, back = (steps[np.rint(v * (len(SPEC_RAMP) - 1)).astype(int)][..., None]
                      for v in (fore, back))

    out_lines = []
    for i in range(lines):
        out, held = [], None
        for c in range(cols):
            pair = (*fore[i, c], *back[i, c])
            if pair != held:
                out.append(escape % pair)
                held = pair
            out.append(SPEC_QUADRANTS[pattern[i, c]])
        out_lines.append("".join(out) + "\x1b[0m")
    return out_lines


def hz_label(hz):
    if hz >= 9950:
        return "%dk" % round(hz / 1000)
    if hz >= 995:
        return "%.1fk" % (hz / 1000)
    return "%d" % round(hz)


def ruler(edges, cols):
    """(axis line, label line) for the frequency axis, cols wide.

    Octaves of A, dropped where two labels would collide, so a wrong octave is
    read off the axis rather than counted in decades.
    """
    marks, axis = [" "] * cols, ["─"] * cols
    span = np.log(edges[-1] / edges[0])
    used = -1
    for hz in (55 * 2 ** k for k in range(9)):
        if not edges[0] <= hz < edges[-1]:
            continue
        at = int(np.log(hz / edges[0]) / span * cols)
        text = hz_label(hz)
        if at <= used or at + len(text) > cols:
            continue
        marks[at:at + len(text)] = list(text)
        axis[at] = "┬"
        used = at + len(text)
    return "".join(axis), "".join(marks)


def legend(color):
    if color and truecolor():
        steps = rgb(np.linspace(0.0, 1.0, 24))
        return "".join("\x1b[38;2;%d;%d;%dm█" % tuple(c) for c in steps) + "\x1b[0m"
    if color:
        return "".join("\x1b[38;5;%dm█" % c for c in SPEC_RAMP) + "\x1b[0m"
    return SPEC_ASCII


def draw(panels, start, seconds, color, out=sys.stdout):
    """Spectrograms side by side: frequency across, time UP the page.

    `panels` is [(label, samples)] - one panel when there is nothing to compare
    against, two for a diff, more if several renders are being judged at once.

    Rotated because the comparison is BETWEEN panels, and the eye compares two
    things at the same height far better than two at the same horizontal offset.
    It also lifts the length limit: a long track gets more LINES, and a terminal
    has unlimited scrollback but a fixed width.
    """
    width = shutil.get_terminal_size((100, 24)).columns
    n = len(panels)
    cols = (width - 4 - SPEC_GAP * (n - 1) - SPEC_GUTTER * n) // n
    cols = max(16, min(110, cols))
    lines = int(min(SPEC_MAX_LINES, max(6, round(seconds * SPEC_LINES_PER_SEC))))
    bands = cols * 2 if color else cols          # quadrants split each column

    grids = [spectrogram(samples, lines * 2, bands) for _, samples in panels]
    if any(g is None for g in grids):
        print(TOO_SHORT, file=out)
        return
    # (bands, times) -> (times, bands), newest slice first so it lands on top.
    decibels = [g[0].T[::-1] for g in grids]
    edges = grids[0][1]

    floor, ceiling = scale(decibels)
    drawn = [panel(db, floor, ceiling, color) for db in decibels]
    gap = " " * SPEC_GAP

    def row(cells, gutter):
        return "    " + gap.join(gutter(i) + cell for i, cell in enumerate(cells))

    titles = [(label if len(label) <= cols else label[:cols - 1] + "…").center(cols)
              for label, _ in panels]
    print(row(titles, lambda i: " " * SPEC_GUTTER), file=out)

    # A time label every ~10 lines: one per line is unreadable on a long track.
    every = max(1, round(lines / 10))
    for i in range(lines):
        # Line i holds slices 2i and 2i+1 counted back from the end, so its top
        # edge is at (lines - i) / lines of the way through.
        tick = ("%.1fs" % (start + seconds * (lines - i) / lines)
                if i % every == 0 else "")
        print(row([d[i] for d in drawn], lambda _: "%5s┤" % tick), file=out)

    axis, marks = ruler(edges, cols)
    # The corner sits UNDER THE GUTTER, in the column the data lines spend on
    # the axis glyph - it is not one of the `cols` cells. Folding it into the
    # axis instead costs the last cell and puts every tick one column left of
    # its label. The gutter labels the TOP edge of each line, so the bottom
    # edge - the start of the range - belongs here, or the axis has no origin.
    print(row([axis] * n, lambda _: "%5s└" % ("%.1fs" % start)), file=out)
    print(row([marks] * n, lambda _: " " * SPEC_GUTTER), file=out)
    print("    %s%s %+.0f dB .. %+.0f dB (Hz across, time up%s)"
          % (" " * SPEC_GUTTER, legend(color), floor - ceiling, 0.0,
             ", scale shared by all panels" if n > 1 else ""), file=out)


# --------------------------------------------------------- image drawing ----

def draw_file(panels, start, path, out=sys.stdout):
    """The same panels as draw(), at full STFT resolution, into a file.

    Same data, same shared dB scale, different medium: a dozen text lines cannot
    show a vibrato or a one-frame dropout, and 43 columns per second can.
    Matplotlib is imported here rather than at module scope so the terminal
    panels, the metrics and the exit code all still work without it installed.
    """
    try:
        import matplotlib
        matplotlib.use("Agg")           # no display, and none wanted
        import matplotlib.pyplot as plt
    except ImportError:
        raise SystemExit("--spectrogram-file needs matplotlib "
                         "(pip install matplotlib), or use --spectrogram")

    mags = [stft(samples) for _, samples in panels]
    if any(not len(m) for m in mags):
        print(TOO_SHORT, file=out)
        return
    # Drop the DC bin: it carries no pitch and a log frequency axis cannot plot 0.
    freqs = (np.arange(mags[0].shape[1]) * RATE / SPEC_FFT)[1:]
    # At full resolution nothing averages the floor up, so the quiet cells are
    # really that quiet and the fixed dynamic window is the honest one.
    decibels = [20 * np.log10(m[:, 1:] + 1e-9) for m in mags]
    ceiling = max(float(db.max()) for db in decibels)
    floor = ceiling - SPEC_DYNAMIC_DB

    # Same orientation as the terminal panels: frequency across, time up. The
    # figure grows with the track instead of squeezing a minute of music into a
    # fixed height, and the panels stay comparable line by line.
    seconds = len(mags[0]) * (SPEC_FFT // 2) / RATE
    roles = ("reference", "render") if len(panels) == 2 else ("",) * len(panels)
    fig, axes = plt.subplots(1, len(panels), squeeze=False, sharex=True, sharey=True,
                             constrained_layout=True,
                             figsize=(5.0 + 4.5 * len(panels),
                                      min(40.0, max(4.5, seconds * 0.5))))
    for ax, db, (label, _), mag, role in zip(axes[0], decibels, panels, mags, roles):
        when = start + (np.arange(len(mag)) * (SPEC_FFT // 2) + SPEC_FFT / 2) / RATE
        # Plot relative to the shared ceiling: an absolute dB axis on int16
        # magnitudes is a number nobody can act on.
        mesh = ax.pcolormesh(freqs, when, db - ceiling, vmin=floor - ceiling,
                             vmax=0.0, cmap="magma", shading="nearest",
                             rasterized=True)
        ax.set_xscale("log")
        ax.set_xlim(SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2))
        ticks = [55 * 2 ** k for k in range(8)
                 if SPEC_LO_HZ <= 55 * 2 ** k <= min(SPEC_HI_HZ, RATE / 2)]
        ax.set_xticks(ticks)
        ax.set_xticklabels([hz_label(t) for t in ticks])
        ax.set_title(f"{role}: {label}" if role else label, fontsize=10)
        ax.set_xlabel("Hz")
    axes[0][0].set_ylabel("seconds")
    fig.colorbar(mesh, ax=axes, label="dB below the loudest cell drawn")
    fig.savefig(path)
    plt.close(fig)
    print(f"    spectrogram written to {path}", file=out)


# ------------------------------------------------------------- the views ----

@dataclass
class View:
    """Where the spectrogram goes, so the report takes one argument, not four."""
    terminal: bool = False
    path: str | None = None
    window: tuple[float, float | None] | None = None
    color: bool = True

    def wanted(self):
        return self.terminal or bool(self.path)

    def show(self, panels):
        """Draw `panels` wherever this view asks, over its time window."""
        total = min(len(samples) for _, samples in panels)
        lo, hi = 0, total
        if self.window is not None:
            lo = min(max(int(self.window[0] * RATE), 0), total)
            hi = total if self.window[1] is None else min(int(self.window[1] * RATE),
                                                          total)
        if hi - lo < SPEC_FFT:
            print("    spectrogram: range holds %d samples, need %d"
                  % (max(hi - lo, 0), SPEC_FFT))
            return
        clipped = [(label, samples[lo:hi]) for label, samples in panels]
        if self.terminal:
            draw(clipped, lo / RATE, (hi - lo) / RATE, self.color)
        if self.path:
            draw_file(clipped, lo / RATE, self.path)


# ---------------------------------------------------------- the report ----

def compare(reference, candidate, label, verbose, view, ref_label="reference"):
    pitchiness = reference_pitchiness(reference)
    pitched = pitchiness >= PITCHED_MIN
    lag = (align(reference, candidate) if pitched
           else align_envelope(reference, candidate))
    shifted = shift(candidate, lag)
    windows = min(len(reference), len(shifted)) // WINDOW
    if windows < 1:
        # Every metric below reduces over the windows, and reducing over none of
        # them is a median of an empty array, not a verdict.
        print(f"  {label}: {min(len(reference), len(shifted)) / RATE:.3f}s of "
              f"overlap is under one {WINDOW / RATE:.1f} s window - "
              f"nothing to compare")
        return 0.0

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

    # Is the REFERENCE pitched at all? On noise or percussion, waveform
    # correlation follows the random realization rather than sequencer time.
    # Use the smoothed power envelope selected above for both metrics and views.
    shape = None if pitched else contour(reference, shifted)

    alignment = "sample" if pitched else "envelope"
    print(f"  {label}: {alignment} lag {lag:+d} samples "
          f"({lag / RATE * 1000:+.1f} ms), "
          f"{windows} windows of 0.1 s")
    if not pitched:
        print(f"    UNPITCHED reference: only {compared}/{windows} windows have "
              f"a period, so this is noise or percussion.")
        print( "             pitch and lock are NOT REPORTED - neither can "
               "succeed here.")
        print( "             Pitch needs a period to measure; lock needs our "
               "samples to equal")
        print( "             PICO-8's, which needs its RNG and that RNG's "
               "cross-voice draw order.")
        if shape is not None:
            print(f"    contour  loudness {shape[0]:.3f}, timbre {shape[1]:.3f} "
                  f"(1.000 is the ceiling; this is the metric that applies)")
    elif compared:
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

    balance = band_balance(reference, shifted)
    band_failures = []
    if balance:
        print(f"    band level, dB render/reference (guard +/-{BAND_TOL_DB:.1f} dB; "
              f"quiet = lowest {100 * QUIET_QUANTILE:.0f}% of reference windows)")
        print("      band            whole   local   quiet")
        for result in balance:
            failed = result.failures()
            band_failures.extend(f"{result.label} {scope}" for scope in failed)

            def value(number):
                return "   n/a" if number is None else f"{number:+6.2f}"

            verdict = "" if not failed else f"   FAIL ({', '.join(failed)})"
            print(f"      {result.label:<14} {value(result.whole_db)} "
                  f"{value(result.local_db)} {value(result.quiet_db)}{verdict}")

    locks = lock(reference, candidate) if pitched else []
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
    if bad and compared and pitched:
        print(f"    first mismatch at {bad[0][0] * 0.1:.1f}s "
              f"(reference {note(bad[0][1])}, render {note(bad[0][2])})")
    if view.wanted():
        # The SHIFTED candidate, so the panels share a timebase: drawing the raw
        # candidate would smear every difference by the reported lag and read as
        # a sequencer slip on a render that is merely late.
        view.show([(ref_label, reference), (label, shifted)])

    if verbose:
        print("      t/s     ref      render   err/st  rms ref/cand   cos")
        for i, rhz, chz, rr, cr, c, ok in rows:
            mark = "     " if ok is None else ("  ok " if ok else " BAD ")
            err = ("%6.2f" % abs(12 * np.log2(rhz / chz))
                   if rhz > 0 and chz > 0 else "   inf")
            print(f"    {i * 0.1:6.1f} {note(rhz):>6}({rhz:6.1f}) "
                  f"{note(chz):>6}({chz:6.1f}) {err} "
                  f"{rr:7.0f}/{cr:7.0f} {c:5.3f} {mark}")
    if not pitched:
        # Score the trajectory, so an unpitched track can still pass or fail on
        # something real rather than being scored 0 by a metric that never applied.
        score = min(shape) if shape is not None else 0.0
    else:
        score = (agreed / compared) if compared else 0.0
    return 0.0 if band_failures else score


# ------------------------------------------------------------------- CLI ----

def parse_range(text):
    """'12:16' -> (12.0, 16.0); '12:' -> (12.0, None); ':4' -> (0.0, 4.0)."""
    if not text:
        return None
    lo, sep, hi = text.partition(":")
    if not sep:
        raise SystemExit("--spectrogram-range wants LO:HI in seconds")
    try:
        start = float(lo) if lo else 0.0
        end = float(hi) if hi else None
    except ValueError:
        raise SystemExit(f"--spectrogram-range: not a number in {text!r}")
    if start < 0 or (end is not None and end <= start):
        raise SystemExit(f"--spectrogram-range: empty range {text!r}")
    return start, end


def image_path(base, label, many):
    """One image per candidate, so renders do not overwrite each other."""
    if not base or not many:
        return base
    stem, ext = os.path.splitext(base)
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in label)
    return f"{stem}-{safe}{ext}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="wav recorded from real PICO-8, or `-` for "
                                      "stdin. Alone, it is just drawn")
    ap.add_argument("candidate", nargs="*", help="renders to judge against it")
    ap.add_argument("--labels", help="comma-separated names for the candidates")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--spectrogram", action="store_true",
                    help="draw the panels side by side, shared dB scale")
    ap.add_argument("--spectrogram-file", metavar="PATH",
                    help="write the same panels to an image (png/pdf/svg by "
                         "extension) at full resolution; needs matplotlib. With "
                         "several candidates the label is inserted into the name")
    ap.add_argument("--spectrogram-range", metavar="LO:HI",
                    help="seconds to draw, e.g. 12:16, 12: or :4 (default all)")
    ap.add_argument("--color", choices=("auto", "always", "never"), default="auto",
                    help="auto: colour only on a terminal without NO_COLOR. "
                         "Colour draws 2x2 quadrant cells (double the frequency "
                         "bands) and uses 24-bit when COLORTERM says truecolor, "
                         "otherwise 16 steps of the 256-colour cube")
    args = ap.parse_args()

    paths = [args.reference] + args.candidate
    if paths.count("-") > 1:
        raise SystemExit("only one input can come from stdin")
    view = View(terminal=args.spectrogram, path=args.spectrogram_file,
                window=parse_range(args.spectrogram_range),
                color=(args.color == "always"
                       or (args.color == "auto" and sys.stdout.isatty()
                           and not os.environ.get("NO_COLOR"))))

    reference = load(args.reference)
    if not args.candidate:
        # Nothing to compare against, so the picture IS the report: draw it even
        # though --spectrogram was not asked for, since there is nothing else to
        # print. An explicit --spectrogram-file alone still just writes the file.
        describe(args.reference, reference)
        view.terminal = view.terminal or not view.path
        view.show([(name(args.reference), reference)])
        return 0

    labels = (args.labels.split(",") if args.labels
              else [name(c) for c in args.candidate])
    describe(args.reference, reference, indent="reference ")
    worst = 1.0
    for path, label in zip(args.candidate, labels):
        cand = load(path)
        describe(path, cand, indent=f"  {label} ")
        view.path = image_path(args.spectrogram_file, label,
                               len(args.candidate) > 1)
        worst = min(worst, compare(reference, cand, label, args.verbose, view,
                                   ref_label=name(args.reference)))
    return 0 if worst >= 0.85 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # `psg_ref_check.py long.wav | head` closes the pipe under us. Die like a
        # unix tool instead of dumping a traceback the shell then hides anyway.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(141)
    except KeyboardInterrupt:
        sys.exit(130)
