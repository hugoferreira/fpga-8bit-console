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

--spectrogram adds the picture those three numbers summarise: the reference and
the render drawn side by side, same axes, same dB scale, so a missing voice or a
wrong harmonic series is visible rather than inferred from a cosine. Frequency
runs across and time runs UP, so the same instant sits at the same height in
both panels and a note is a horizontal bar you can follow from one to the other;
a long track then costs lines, which a terminal has, rather than columns, which
it does not. It draws in the terminal; --spectrogram-file writes the same pair
to an image at full STFT resolution, which is where vibrato and one-frame
dropouts show up.

Usage:
  psg_ref_check.py ref.wav cand.wav
  psg_ref_check.py ref.wav cand.wav --spectrogram
  psg_ref_check.py ref.wav cand.wav --spectrogram-file build/diff.png
  psg_ref_check.py ref.wav cand.wav --spectrogram --spectrogram-range 12:16
  psg_ref_check.py ref.wav hw.wav pv.wav --labels hardware,preview --verbose
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import wave

import numpy as np

RATE = 22050
WINDOW = 2205           # 0.1 s, as in tools/psg_preview_check.py
VOICED = 0.30           # normalised autocorrelation floor for "has a pitch"
TOLERANCE = 1.0         # semitones
LO_HZ, HI_HZ = 70.0, 1200.0

SPEC_FFT = 1024         # 46 ms, ~21.5 Hz bins: resolves a bass note's harmonics
SPEC_LO_HZ, SPEC_HI_HZ = 55.0, 8000.0
SPEC_DYNAMIC_DB = 60.0  # everything this far under the loudest cell reads as floor
SPEC_LINES_PER_SEC = 2  # text lines per second of audio; each holds two slices
SPEC_MAX_LINES = 120    # a minute of scrollback per panel is already a lot
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


# Below this share of voiced reference windows the material is noise or
# percussion, and pitch and lock stop meaning anything - see contour().
PITCHED_MIN = 0.25


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


def split(quad):
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
    pattern, fore, back = split(quad)

    if truecolor():
        paint = rgb
        escape = "\x1b[38;2;%d;%d;%d;48;2;%d;%d;%dm"
    else:
        ramp = np.array(SPEC_RAMP)
        paint = lambda v: ramp[np.rint(v * (len(SPEC_RAMP) - 1)).astype(int)][..., None]
        escape = "\x1b[38;5;%d;48;5;%dm"
    fore, back = paint(fore), paint(back)

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


def draw(left, right, labels, start, seconds, color, out=sys.stdout):
    """Two spectrograms side by side: frequency across, time UP the page.

    Rotated because the comparison is between the two panels, and the eye
    compares two things that sit at the same height far better than two things
    that sit at the same horizontal offset. It also lifts the length limit: a
    long track gets more LINES, and a terminal has unlimited scrollback but a
    fixed width.
    """
    width = shutil.get_terminal_size((100, 24)).columns
    # 4 indent + two panels of (5-char time label + axis + cells) + 3 gap.
    cols = max(16, min(90, (width - 19) // 2))          # characters per panel
    lines = int(min(SPEC_MAX_LINES, max(6, round(seconds * SPEC_LINES_PER_SEC))))
    bands = cols * 2 if color else cols                 # quadrants split columns

    a = spectrogram(left, lines * 2, bands)
    b = spectrogram(right, lines * 2, bands)
    if a is None or b is None:
        print("    spectrogram: less than %.0f ms of overlap, nothing to draw"
              % (SPEC_FFT / RATE * 1000), file=out)
        return
    # (bands, times) -> (times, bands), newest slice first so it lands on top.
    (adb, edges), (bdb, _) = (a[0].T[::-1], a[1]), (b[0].T[::-1], b[1])

    # ONE scale for both panels. Normalising each panel to its own peak would
    # hide exactly the fault the level metric exists to catch: a render at half
    # the reference's amplitude would draw identically to a correct one.
    ceiling = max(adb.max(), bdb.max())
    # Averaging frames into columns lifts the floor, so a fixed 60 dB window
    # leaves a third of the ramp unused and flattens the picture. Take the
    # quietest cell either panel actually has, bounded by that window.
    floor = max(ceiling - SPEC_DYNAMIC_DB,
                float(np.percentile(np.concatenate([adb.ravel(), bdb.ravel()]), 1)))
    left_lines = panel(adb, floor, ceiling, color)
    right_lines = panel(bdb, floor, ceiling, color)

    def title(text):
        text = text if len(text) <= cols else text[:cols - 1] + "…"
        return text.center(cols)

    print("    %s   %s" % (" " * 6 + title(labels[0]), " " * 6 + title(labels[1])),
          file=out)
    # A time label every ~5 lines: one per line is unreadable on a long track.
    every = max(1, round(lines / 10))
    for i, (l, r) in enumerate(zip(left_lines, right_lines)):
        # Line i holds slices 2i and 2i+1 counted back from the end, so its top
        # edge is at (lines - i) / lines of the way through.
        tick = ("%.1fs" % (start + seconds * (lines - i) / lines)
                if i % every == 0 else "")
        gutter = "%5s┤" % tick
        print("    %s%s   %s%s" % (gutter, l, gutter, r), file=out)

    # Frequency ruler: octaves of A, dropped where two labels would collide.
    marks, ruler = [" "] * cols, ["─"] * cols
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
        ruler[at] = "┬"
        used = at + len(text)
    # The corner sits UNDER THE GUTTER, in the column the data lines spend on
    # the axis glyph - it is not one of the `cols` cells. Folding it into the
    # ruler instead cost the last cell, put every tick one column left of its
    # label, and shifted the right panel's axis off its own panel.
    # The gutter labels the TOP edge of each line, so the bottom edge - the
    # start of the range - belongs here, or the axis has no origin.
    origin = "%.1fs" % start
    print("    %5s└%s   %5s└%s"
          % (origin, "".join(ruler), origin, "".join(ruler)), file=out)
    print("    %6s%s   %6s%s" % ("", "".join(marks), "", "".join(marks)), file=out)

    if color and truecolor():
        steps = rgb(np.linspace(0.0, 1.0, 24))
        bar = "".join("\x1b[38;2;%d;%d;%dm█" % tuple(c) for c in steps) + "\x1b[0m"
    elif color:
        bar = "".join("\x1b[38;5;%dm█" % c for c in SPEC_RAMP) + "\x1b[0m"
    else:
        bar = SPEC_ASCII
    print("    %6s%s %+.0f dB .. %+.0f dB (Hz across, time up, scale shared "
          "by both panels)" % ("", bar, floor - ceiling, 0.0), file=out)


def draw_file(left, right, labels, start, path, out=sys.stdout):
    """The same two panels as draw(), at full STFT resolution, into a file.

    Same data, same shared dB scale, different medium: 12 text lines cannot show
    a vibrato or a one-frame dropout, and 43 columns per second can. Matplotlib
    is imported here rather than at module scope so the terminal panels, the
    metrics and the exit code all still work without it installed.
    """
    try:
        import matplotlib
        matplotlib.use("Agg")           # no display, and none wanted
        import matplotlib.pyplot as plt
    except ImportError:
        raise SystemExit("--spectrogram-file needs matplotlib "
                         "(pip install matplotlib), or use --spectrogram")

    panels = [stft(left), stft(right)]
    if any(not len(m) for m in panels):
        print("    spectrogram: less than %.0f ms of overlap, nothing to draw"
              % (SPEC_FFT / RATE * 1000), file=out)
        return
    # Drop the DC bin: it carries no pitch and a log frequency axis cannot plot 0.
    freqs = (np.arange(panels[0].shape[1]) * RATE / SPEC_FFT)[1:]
    decibels = [20 * np.log10(m[:, 1:].T + 1e-9) for m in panels]

    # One scale, and here the fixed window is right: at full resolution nothing
    # averages the floor up, so the quiet cells are really that quiet.
    ceiling = max(float(db.max()) for db in decibels)
    floor = ceiling - SPEC_DYNAMIC_DB

    # Same orientation as the terminal panels: frequency across, time up. The
    # figure grows with the track instead of squeezing a minute of music into a
    # fixed width, and the two panels stay comparable line by line.
    duration = (len(panels[0]) * (SPEC_FFT // 2)) / RATE
    fig, axes = plt.subplots(1, 2, figsize=(9.5, min(40.0, max(4.5, duration * 0.5))),
                             sharex=True, sharey=True, constrained_layout=True)
    for ax, db, label, mag, role in zip(axes, decibels, labels, panels,
                                        ("reference", "render")):
        seconds = start + (np.arange(len(mag)) * (SPEC_FFT // 2)
                           + SPEC_FFT / 2) / RATE
        # Plot relative to the shared ceiling: an absolute dB axis on int16
        # magnitudes is a number nobody can act on.
        mesh = ax.pcolormesh(freqs, seconds, (db - ceiling).T,
                             vmin=floor - ceiling, vmax=0.0, cmap="magma",
                             shading="nearest", rasterized=True)
        ax.set_xscale("log")
        ax.set_xlim(SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2))
        # Octaves of A, so a wrong octave is read off the axis rather than
        # counted in decades.
        ticks = [55 * 2 ** k for k in range(8)
                 if SPEC_LO_HZ <= 55 * 2 ** k <= min(SPEC_HI_HZ, RATE / 2)]
        ax.set_xticks(ticks)
        ax.set_xticklabels([hz_label(t) for t in ticks])
        ax.set_title(f"{role}: {label}", fontsize=10)
        ax.set_xlabel("Hz")
    axes[0].set_ylabel("seconds")
    fig.colorbar(mesh, ax=axes,
                 label="dB below the loudest cell of either panel")
    fig.savefig(path)
    plt.close(fig)
    print(f"    spectrogram written to {path}", file=out)


def note(hz):
    if hz <= 0:
        return "-"
    midi = 69 + 12 * np.log2(hz / 440.0)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[int(round(midi)) % 12], int(round(midi)) // 12 - 1)


def compare(reference, candidate, label, verbose, spec=False, spec_range=None,
            ref_label="reference", color=True, spec_file=None):
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

    # Is the REFERENCE pitched at all? On a noise or percussion track neither
    # pitch nor lock can succeed even for a perfect render, and printing them
    # anyway hands the reader a red verdict with no way to know it is vacuous.
    # That happened: Celeste's track 30 is one swept noise voice, and a render
    # tracking its contour at 0.99 reported "33% pitch" and "LOST LOCK".
    pitched = windows > 0 and (compared / windows) >= PITCHED_MIN

    print(f"  {label}: lag {lag:+d} samples ({lag / RATE * 1000:+.1f} ms)"
          f"{'' if pitched else ' - MEANINGLESS here, see below'}, "
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
        # The RAW candidate: `lag` came from cross-correlating waveforms, and on
        # noise that is an arbitrary peak (-6233 samples on track 30). Shifting
        # by it smears the trajectory and scored a 0.99 contour as 0.55.
        shape = contour(reference, candidate)
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
    if spec or spec_file:
        # The SHIFTED candidate, so the two panels share a timebase: drawing the
        # raw candidate would smear every difference by the reported lag and
        # read as a sequencer slip on a render that is merely late.
        n = min(len(reference), len(shifted))
        lo, hi = 0, n
        if spec_range is not None:
            lo = min(max(int(spec_range[0] * RATE), 0), n)
            hi = n if spec_range[1] is None else min(int(spec_range[1] * RATE), n)
        if hi - lo < SPEC_FFT:
            print("    spectrogram: range holds %d samples, need %d"
                  % (max(hi - lo, 0), SPEC_FFT))
        else:
            if spec:
                draw(reference[lo:hi], shifted[lo:hi], (ref_label, label),
                     lo / RATE, (hi - lo) / RATE, color)
            if spec_file:
                draw_file(reference[lo:hi], shifted[lo:hi], (ref_label, label),
                          lo / RATE, spec_file)

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
        # The RAW candidate: `lag` came from cross-correlating waveforms, and on
        # noise that is an arbitrary peak (-6233 samples on track 30). Shifting
        # by it smears the trajectory and scored a 0.99 contour as 0.55.
        shape = contour(reference, candidate)
        return min(shape) if shape is not None else 0.0
    return (agreed / compared) if compared else 0.0


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


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="wav recorded from real PICO-8")
    ap.add_argument("candidate", nargs="+")
    ap.add_argument("--labels", help="comma-separated names for the candidates")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--spectrogram", action="store_true",
                    help="draw reference and render side by side, shared dB scale")
    ap.add_argument("--spectrogram-file", metavar="PATH",
                    help="write the same pair to an image (png/pdf/svg by "
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

    spec_range = parse_range(args.spectrogram_range)
    color = (args.color == "always"
             or (args.color == "auto" and sys.stdout.isatty()
                 and not os.environ.get("NO_COLOR")))

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
        # One image per candidate, so a three-way comparison does not have each
        # render silently overwrite the last one's picture.
        spec_file = args.spectrogram_file
        if spec_file and len(args.candidate) > 1:
            stem, ext = os.path.splitext(spec_file)
            safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in label)
            spec_file = f"{stem}-{safe}{ext}"
        worst = min(worst, compare(reference, cand, label, args.verbose,
                                   spec=args.spectrogram, spec_range=spec_range,
                                   ref_label=args.reference.split("/")[-1],
                                   color=color, spec_file=spec_file))
    return 0 if worst >= 0.85 else 1


if __name__ == "__main__":
    sys.exit(main())
