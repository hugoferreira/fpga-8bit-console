"""Independent, composable terminal visualizations for audio analysis.

Each renderer returns a rectangular :class:`TerminalPanel` over the same
newest-at-top time grid.  Composition is deliberately separate: a panel works
alone, and rows/columns only arrange those unchanged panels.
"""
from __future__ import annotations

from dataclasses import dataclass
import re

import numpy as np

from audio_analysis import (
    BANDS,
    HI_HZ,
    LO_HZ,
    RATE,
    SPEC_FFT,
    SPEC_HI_HZ,
    SPEC_LO_HZ,
    VOICED,
    WINDOW,
    note_name,
    panel as spectral_cells,
    pitch,
    ruler,
    scale as spectral_scale,
    spectral_centroid,
    spectrogram,
)


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
TIME_GUTTER = 8
PANEL_GAP = 3
SPECTRAL_CHANGE_WINDOW = 1024
SPECTRAL_CHANGE_HOP = 512
MODULATION_ENVELOPE_WINDOW = 110
MODULATION_ENVELOPE_HOP = 55
MODULATION_FFT = 512
MODULATION_FFT_HOP = 256
MODULATION_LO_HZ = 1.0
MODULATION_HI_HZ = 100.0
MODULATION_MIN_DB = -60.0
MODULATION_MAX_DB = 0.0
LOW_FREQUENCY_FFT = 16384
LOW_FREQUENCY_HOP = 8192
LOW_FREQUENCY_LO_HZ = 1.0
LOW_FREQUENCY_HI_HZ = 250.0
LOW_FREQUENCY_MIN_DBFS = -96.0
LOW_FREQUENCY_MAX_DBFS = 0.0
STEREO_DELAY_MAX_MILLISECONDS = 5.0
STEREO_DELAY_MAX_SAMPLES = round(RATE * STEREO_DELAY_MAX_MILLISECONDS / 1000.0)
STEREO_DELAY_MIN_CORRELATION = 0.50
STEREO_DELAY_MIN_MARGIN = 0.05
INTERSAMPLE_FACTOR = 4
INTERSAMPLE_HALF_TAPS = 16
INTERSAMPLE_TAP_COUNT = 2 * INTERSAMPLE_HALF_TAPS + 1
INTERSAMPLE_MIN_DBFS = -12.0
INTERSAMPLE_MAX_DBFS = 6.0
PHASE_COHERENCE_MINIMUM = 0.80
PHASE_DYNAMIC_DB = 60.0
PHASE_NEUTRAL_DEGREES = 5.0


def _intersample_kernels():
    taps = np.arange(-INTERSAMPLE_HALF_TAPS,
                     INTERSAMPLE_HALF_TAPS + 1, dtype=np.float64)
    window = np.hanning(INTERSAMPLE_TAP_COUNT)
    kernels = []
    for phase in range(INTERSAMPLE_FACTOR):
        fraction = phase / INTERSAMPLE_FACTOR
        kernel = np.sinc(fraction - taps) * window
        kernels.append(kernel / kernel.sum())
    return np.column_stack(kernels)


INTERSAMPLE_KERNELS = _intersample_kernels()


@dataclass(frozen=True)
class TerminalGeometry:
    """Deterministic geometry shared by every terminal renderer."""

    start_seconds: float
    seconds: float
    lines: int
    width: int
    layout: str
    axis: str
    color: bool


@dataclass(frozen=True)
class TerminalPanel:
    """One independently useful fixed-width panel."""

    title: str
    rows: tuple[str, ...]
    footer: tuple[str, ...] = ()
    x_axis: str | None = None


@dataclass(frozen=True)
class StereoDelayObservation:
    """Best inter-channel lag plus the evidence needed to trust it."""

    lag_samples: int
    peak_correlation: float
    peak_margin: float

    @property
    def accepted(self):
        return (self.peak_correlation >= STEREO_DELAY_MIN_CORRELATION
                and self.peak_margin >= STEREO_DELAY_MIN_MARGIN)


def visible_width(text):
    return len(ANSI_RE.sub("", text))


def pad(text, width):
    """Pad an ANSI-decorated cell to a stable visible width."""
    return text + " " * max(0, width - visible_width(text))


def fit(text, width):
    """Fit plain text to a panel without changing its declared width."""
    if len(text) > width:
        text = text[:width]
    return text.ljust(width)


def style(text, color, code):
    return f"\x1b[{code}m{text}\x1b[0m" if color else text


def row_interval(geometry, row):
    """Absolute seconds covered by one newest-first display row."""
    high = (geometry.start_seconds
            + geometry.seconds * (geometry.lines - row) / geometry.lines)
    low = (geometry.start_seconds
           + geometry.seconds * (geometry.lines - row - 1) / geometry.lines)
    return low, high


def time_gutter(geometry, row):
    every = max(1, round(geometry.lines / 10))
    _, high = row_interval(geometry, row)
    label = f"{high:5.1f}s" if row % every == 0 else ""
    return f"{label:>7}┤"


def bottom_gutter(geometry):
    label = f"{geometry.start_seconds:5.1f}s"
    return f"{label:>7}└"


def resolved_axis(geometry):
    if geometry.axis != "auto":
        return geometry.axis
    return "first" if geometry.layout == "columns" else "each"


def compose(panels, geometry):
    """Compose panels without changing any renderer's rows or width.

    Every plot gets a structural x-axis row between its data and prose footer.
    A renderer can supply tick marks through ``TerminalPanel.x_axis``; the
    default is an unlabelled horizontal rule.  Keeping that boundary separate
    prevents the first footer sentence from visually cutting the plot axis.
    """
    if not panels:
        return []
    axis = resolved_axis(geometry)
    gap = " " * PANEL_GAP
    output = []

    def title(panel):
        return fit(panel.title, geometry.width)

    if geometry.layout == "columns":
        if axis == "each":
            output.append(gap.join(" " * TIME_GUTTER + title(item)
                                   for item in panels))
        else:
            prefix = " " * TIME_GUTTER if axis == "first" else ""
            output.append(prefix + gap.join(title(item) for item in panels))
        for row in range(geometry.lines):
            cells = [pad(item.rows[row], geometry.width) for item in panels]
            if axis == "each":
                output.append(gap.join(time_gutter(geometry, row) + cell
                                       for cell in cells))
            else:
                prefix = time_gutter(geometry, row) if axis == "first" else ""
                output.append(prefix + gap.join(cells))
        axes = [fit(item.x_axis or "─" * geometry.width, geometry.width)
                for item in panels]
        if axis == "each":
            output.append(gap.join(bottom_gutter(geometry) + cell
                                   for cell in axes))
        else:
            prefix = bottom_gutter(geometry) if axis == "first" else ""
            output.append(prefix + gap.join(axes))
        footer_lines = max((len(item.footer) for item in panels), default=0)
        for line in range(footer_lines):
            cells = [fit(item.footer[line] if line < len(item.footer) else "",
                         geometry.width)
                     for item in panels]
            if axis == "each":
                output.append(gap.join(" " * TIME_GUTTER + cell
                                       for cell in cells))
            else:
                prefix = " " * TIME_GUTTER if axis == "first" else ""
                output.append(prefix + gap.join(cells))
        return output

    for index, item in enumerate(panels):
        show_axis = axis == "each" or (axis == "first" and index == 0)
        prefix = " " * TIME_GUTTER if show_axis else ""
        output.append(prefix + title(item))
        for row, cell in enumerate(item.rows):
            gutter = time_gutter(geometry, row) if show_axis else ""
            output.append(gutter + pad(cell, geometry.width))
        gutter = bottom_gutter(geometry) if show_axis else ""
        output.append(gutter + fit(item.x_axis or "─" * geometry.width,
                                   geometry.width))
        for footer in item.footer:
            gutter = " " * TIME_GUTTER if show_axis else ""
            output.append(gutter + fit(footer, geometry.width))
        if index + 1 < len(panels):
            output.append("")
    return output


def render_spectrograms(panels, geometry):
    """One independent spectrogram panel per input, with a shared dB scale."""
    bands = geometry.width * 2 if geometry.color else geometry.width
    grids = [spectrogram(samples, geometry.lines * 2, bands)
             for _, samples in panels]
    if any(grid is None for grid in grids):
        message = "range too short for 1024-sample STFT"
        return [TerminalPanel(
            f"spectrogram: {label}", tuple(fit(message, geometry.width)
                                           for _ in range(geometry.lines)))
                for label, _ in panels]
    decibels = [grid[0].T[::-1] for grid in grids]
    floor, ceiling = spectral_scale(decibels)
    edges = grids[0][1]
    axis, marks = ruler(edges, geometry.width)
    footer = (marks,
              fit(f"{floor - ceiling:+.0f}..0 dB shared", geometry.width).rstrip())
    return [TerminalPanel(
        f"spectrogram: {label}", tuple(spectral_cells(
            db, floor, ceiling, geometry.color)), footer, axis)
            for (label, _), db in zip(panels, decibels)]


def rms_envelope(samples):
    """Return 110-sample RMS observations at a fixed 55-sample hop.

    The explicit sample counts make the modulation estimator reproducible at
    the CLI's fixed 22,050 Hz rate: approximately 5 ms integration and 2.5 ms
    spacing, or a 400.909091 Hz envelope sample rate.
    """
    values = np.asarray(samples, dtype=np.float64)
    if len(values) < MODULATION_ENVELOPE_WINDOW:
        return np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.float64)
    starts = np.arange(
        0, len(values) - MODULATION_ENVELOPE_WINDOW + 1,
        MODULATION_ENVELOPE_HOP, dtype=np.int64)
    power_sum = np.concatenate((
        np.zeros(1, dtype=np.float64),
        np.cumsum(values * values, dtype=np.float64),
    ))
    power = (power_sum[starts + MODULATION_ENVELOPE_WINDOW]
             - power_sum[starts]) / MODULATION_ENVELOPE_WINDOW
    return starts, np.sqrt(np.maximum(power, 0.0))


def modulation_depth_frames(samples):
    """Return normalized modulation depth spectra and their sample support."""
    envelope_starts, envelope = rms_envelope(samples)
    if len(envelope) < MODULATION_FFT:
        return None
    frame_starts = np.arange(
        0, len(envelope) - MODULATION_FFT + 1,
        MODULATION_FFT_HOP, dtype=np.int64)
    indices = (frame_starts[:, None]
               + np.arange(MODULATION_FFT, dtype=np.int64)[None, :])
    frames = envelope[indices]
    means = frames.mean(axis=1)
    window = np.hanning(MODULATION_FFT)
    magnitude = np.abs(np.fft.rfft(
        (frames - means[:, None]) * window, axis=1))
    depth = np.zeros_like(magnitude)
    live = means > np.finfo(np.float64).eps
    depth[live] = (2.0 * magnitude[live]
                   / window.sum() / means[live, None])
    envelope_rate = RATE / MODULATION_ENVELOPE_HOP
    frequencies = np.fft.rfftfreq(MODULATION_FFT, 1.0 / envelope_rate)
    sample_starts = envelope_starts[frame_starts]
    sample_ends = (envelope_starts[frame_starts + MODULATION_FFT - 1]
                   + MODULATION_ENVELOPE_WINDOW)
    return depth, frequencies, sample_starts, sample_ends


def modulation_peak(samples):
    """Strongest 1..100 Hz modulation FFT bin as ``(Hz, depth, dB)``."""
    measured = modulation_depth_frames(samples)
    if measured is None:
        return None
    depth, frequencies, _, _ = measured
    selected = ((frequencies >= MODULATION_LO_HZ)
                & (frequencies <= MODULATION_HI_HZ))
    if not selected.any():
        return None
    selected_depth = depth[:, selected]
    flat_index = int(np.argmax(selected_depth))
    _, selected_bin = np.unravel_index(flat_index, selected_depth.shape)
    value = float(selected_depth.flat[flat_index])
    frequency = float(frequencies[selected][selected_bin])
    decibels = -np.inf if value <= 0.0 else 20.0 * np.log10(value)
    return frequency, value, float(decibels)


def modulation_spectrogram(samples, times, bands):
    """Return fixed-depth envelope modulation dB over time/log frequency.

    Each 512-observation Hann FFT is normalized by that frame's mean RMS, so a
    sinusoidal envelope reports modulation depth rather than PCM amplitude.
    Output is ``(bands, times)`` on 1..100 Hz log-frequency edges. Empty,
    silent, or unobserved cells are retained below the fixed -60 dB display
    floor instead of being normalized into apparent structure.
    """
    values = np.asarray(samples, dtype=np.float64)
    measured = modulation_depth_frames(values)
    if measured is None or times < 1 or bands < 1:
        return None
    depth, frequencies, sample_starts, sample_ends = measured
    envelope_rate = RATE / MODULATION_ENVELOPE_HOP
    edges = np.geomspace(
        MODULATION_LO_HZ, min(MODULATION_HI_HZ, envelope_rate / 2.0),
        bands + 1)
    band_depth = np.zeros((bands, len(depth)), dtype=np.float64)
    for band in range(bands):
        selected = ((frequencies >= edges[band])
                    & (frequencies < edges[band + 1]))
        if not selected.any():
            selected = np.zeros(len(frequencies), dtype=bool)
            centre = np.sqrt(edges[band] * edges[band + 1])
            selected[int(np.argmin(np.abs(frequencies - centre)))] = True
        band_depth[band] = depth[:, selected].max(axis=1)

    # A modulation frame describes its full 1.277 s support. Average every
    # frame overlapping a requested time slice rather than sampling one frame;
    # this keeps sparse 0.639 s hops visible without inventing finer timing.
    time_edges = np.linspace(0, len(values), times + 1)
    grouped = np.zeros((bands, times), dtype=np.float64)
    for column in range(times):
        selected = ((sample_starts < time_edges[column + 1])
                    & (sample_ends > time_edges[column]))
        if selected.any():
            grouped[:, column] = band_depth[:, selected].mean(axis=1)
    return 20.0 * np.log10(np.maximum(grouped, 1e-12)), edges


def modulation_ruler(edges, width):
    """Log-frequency axis with stable diagnostic modulation-rate marks."""
    axis = ["─"] * width
    marks = [" "] * width
    occupied = []
    span = np.log(edges[-1] / edges[0])
    for frequency in (1.0, 5.0, 20.0, 50.0):
        if not edges[0] <= frequency < edges[-1]:
            continue
        label = f"{frequency:g}"
        position = int(round(
            np.log(frequency / edges[0]) / span * (width - 1)))
        start = min(max(position - len(label) // 2, 0), width - len(label))
        end = start + len(label)
        if any(start < used_end and end > used_start
               for used_start, used_end in occupied):
            continue
        axis[position] = "┬"
        marks[start:end] = label
        occupied.append((start, end))
    return "".join(axis), "".join(marks)


def render_modulation_spectra(panels, geometry):
    """RMS-envelope modulation depth on a fixed 1..100 Hz, -60..0 dB grid."""
    bands = geometry.width * 2 if geometry.color else geometry.width
    measured = [modulation_spectrogram(
        samples, geometry.lines * 2, bands) for _, samples in panels]
    if any(grid is None for grid in measured):
        message = "range too short for 512-sample modulation FFT"
        return [TerminalPanel(
            f"modulation-spectrum: {label}",
            tuple(fit(message, geometry.width)
                  for _ in range(geometry.lines)),
            ("needs 1.277 s RMS envelope", "diagnostic, not verdict"))
                for label, _ in panels]

    edges = measured[0][1]
    axis, marks = modulation_ruler(edges, geometry.width)
    output = []
    for (label, samples), (decibels, _) in zip(panels, measured):
        peak = modulation_peak(samples)
        if peak is None or peak[2] <= MODULATION_MIN_DB:
            peak_text = "peak below -60 dB depth"
        else:
            peak_text = f"peak {peak[0]:.3f} Hz {peak[2]:+.2f} dB"
        rows = spectral_cells(
            decibels.T[::-1], MODULATION_MIN_DB, MODULATION_MAX_DB,
            geometry.color)
        footer = (
            marks,
            "RMS-envelope modulation",
            "fixed -60..0 dB depth",
            "1..100 Hz log frequency",
            "110-sample (5 ms) RMS",
            "55-sample (2.5 ms) hop",
            "512 Hann / 256 hop",
            "FFT 1.277 s; bins 0.783 Hz",
            "depth / local mean RMS",
            "floor <=-60 dB",
            "beats/tremolo may be intended",
            "diagnostic, not verdict",
            peak_text,
        )
        output.append(TerminalPanel(
            f"modulation-spectrum: {label}", tuple(rows), footer, axis))
    return output


def low_frequency_frames(samples):
    """Return calibrated 16,384-sample spectra and their sample support.

    Magnitudes use the coherent gain of the Hann window and signed-16-bit
    full scale, so a bin-centred full-scale sine is 0 dBFS. Per-frame DC is
    removed because literal offset already has its own ``dc-offset`` view.
    """
    values = np.asarray(samples, dtype=np.float64)
    if len(values) < LOW_FREQUENCY_FFT:
        return None
    starts = np.arange(
        0, len(values) - LOW_FREQUENCY_FFT + 1,
        LOW_FREQUENCY_HOP, dtype=np.int64)
    indices = (starts[:, None]
               + np.arange(LOW_FREQUENCY_FFT, dtype=np.int64)[None, :])
    frames = values[indices]
    frames = frames - frames.mean(axis=1, keepdims=True)
    window = np.hanning(LOW_FREQUENCY_FFT)
    amplitude = (2.0 * np.abs(np.fft.rfft(frames * window, axis=1))
                 / window.sum() / 32768.0)
    frequencies = np.fft.rfftfreq(LOW_FREQUENCY_FFT, 1.0 / RATE)
    return amplitude, frequencies, starts, starts + LOW_FREQUENCY_FFT


def low_frequency_peak(samples):
    """Strongest 1..250 Hz FFT bin as ``(Hz, amplitude, dBFS)``."""
    measured = low_frequency_frames(samples)
    if measured is None:
        return None
    amplitude, frequencies, _, _ = measured
    selected = ((frequencies >= LOW_FREQUENCY_LO_HZ)
                & (frequencies <= LOW_FREQUENCY_HI_HZ))
    if not selected.any():
        return None
    selected_amplitude = amplitude[:, selected]
    flat_index = int(np.argmax(selected_amplitude))
    _, selected_bin = np.unravel_index(
        flat_index, selected_amplitude.shape)
    value = float(selected_amplitude.flat[flat_index])
    frequency = float(frequencies[selected][selected_bin])
    decibels = -np.inf if value <= 0.0 else 20.0 * np.log10(value)
    return frequency, value, float(decibels)


def low_frequency_spectrogram(samples, times, bands):
    """Return fixed-dBFS carrier energy over time and 1..250 linear Hz."""
    values = np.asarray(samples, dtype=np.float64)
    measured = low_frequency_frames(values)
    if measured is None or times < 1 or bands < 1:
        return None
    amplitude, frequencies, frame_starts, frame_ends = measured
    edges = np.linspace(
        LOW_FREQUENCY_LO_HZ, LOW_FREQUENCY_HI_HZ, bands + 1)
    band_amplitude = np.zeros((bands, len(amplitude)), dtype=np.float64)
    for band in range(bands):
        selected = ((frequencies >= edges[band])
                    & (frequencies < edges[band + 1]))
        if band + 1 == bands:
            selected |= frequencies == edges[band + 1]
        if not selected.any():
            selected = np.zeros(len(frequencies), dtype=bool)
            centre = (edges[band] + edges[band + 1]) / 2.0
            selected[int(np.argmin(np.abs(frequencies - centre)))] = True
        band_amplitude[band] = amplitude[:, selected].max(axis=1)

    time_edges = np.linspace(0, len(values), times + 1)
    grouped = np.zeros((bands, times), dtype=np.float64)
    for column in range(times):
        selected = ((frame_starts < time_edges[column + 1])
                    & (frame_ends > time_edges[column]))
        if selected.any():
            grouped[:, column] = band_amplitude[:, selected].mean(axis=1)
    return 20.0 * np.log10(np.maximum(grouped, 1e-12)), edges


def low_frequency_ruler(width):
    """Linear low-frequency axis with stable mains/harmonic landmarks."""
    return linear_ruler(
        LOW_FREQUENCY_LO_HZ, LOW_FREQUENCY_HI_HZ, width,
        ((1.0, "1"), (50.0, "50"), (100.0, "100"),
         (150.0, "150"), (200.0, "200"), (250.0, "250")))


def render_low_frequency_spectra(panels, geometry):
    """Calibrated 1..250 Hz carrier spectra on a fixed -96..0 dBFS grid."""
    bands = geometry.width * 2 if geometry.color else geometry.width
    measured = [low_frequency_spectrogram(
        samples, geometry.lines * 2, bands) for _, samples in panels]
    if any(grid is None for grid in measured):
        message = "range too short for 16384-sample low-frequency FFT"
        return [TerminalPanel(
            f"low-frequency-spectrum: {label}",
            tuple(fit(message, geometry.width)
                  for _ in range(geometry.lines)),
            ("needs 0.743 s of audio", "diagnostic, not verdict"))
                for label, _ in panels]

    axis, marks = low_frequency_ruler(geometry.width)
    output = []
    for (label, samples), (decibels, _) in zip(panels, measured):
        peak = low_frequency_peak(samples)
        if peak is None or peak[2] <= LOW_FREQUENCY_MIN_DBFS:
            peak_text = "peak below -96 dBFS"
        else:
            peak_text = f"peak {peak[0]:.3f} Hz {peak[2]:+.2f} dBFS"
        rows = spectral_cells(
            decibels.T[::-1], LOW_FREQUENCY_MIN_DBFS,
            LOW_FREQUENCY_MAX_DBFS, geometry.color)
        footer = (
            marks,
            "carrier spectrum; DC removed",
            "fixed -96..0 dBFS amplitude",
            "1..250 Hz linear frequency",
            "16384 Hann / 8192 hop",
            "FFT 0.743 s; bins 1.346 Hz",
            "hop 0.372 s",
            "overlap-mean time cells",
            "floor <=-96 dBFS",
            "carrier Hz, not envelope rate",
            "bass/rumble may be intended",
            "diagnostic, not verdict",
            peak_text,
        )
        output.append(TerminalPanel(
            f"low-frequency-spectrum: {label}", tuple(rows), footer, axis))
    return output


def span_row(low, high, scale, geometry, *, color_code="36"):
    """One signed min/max span with an explicit zero marker."""
    centre = geometry.width // 2

    def position(value):
        if value == 0:
            return centre
        return int(round((np.clip(value / scale, -1, 1) + 1)
                         * (geometry.width - 1) / 2))

    left, right = position(low), position(high)
    if left > right:
        left, right = right, left
    cells = [" "] * geometry.width
    cells[centre] = "│"
    if left == right:
        cells[left] = "•"
    else:
        for index in range(left, right + 1):
            cells[index] = "─"
        cells[left], cells[right] = "├", "┤"
        if left <= centre <= right:
            cells[centre] = "┼"
    return style("".join(cells), geometry.color, color_code)


def positive_bar_row(value, scale, geometry, *, color_code="36"):
    """One non-negative value on an explicit zero-to-scale bar."""
    if value <= 0:
        return style("•" + " " * (geometry.width - 1),
                     geometry.color, color_code)
    clipped = min(value, scale)
    length = max(1, int(round(clipped / scale * geometry.width)))
    cells = ["━"] * length + [" "] * (geometry.width - length)
    cells[length - 1] = ">" if value >= scale else "●"
    return style("".join(cells), geometry.color, color_code)


def range_bar_row(value, minimum, maximum, geometry, *, color_code="36"):
    """One value on an explicit minimum-to-maximum horizontal bar."""
    if value <= minimum:
        return style("<" + " " * (geometry.width - 1),
                     geometry.color, color_code)
    if value >= maximum:
        return style("━" * (geometry.width - 1) + ">",
                     geometry.color, color_code)
    length = max(1, int(round(
        (value - minimum) / (maximum - minimum) * geometry.width)))
    cells = ["━"] * length + [" "] * (geometry.width - length)
    cells[length - 1] = "●"
    return style("".join(cells), geometry.color, color_code)


def range_span_row(low, high, minimum, maximum, geometry, *, color_code="36"):
    """One min/max span on a fixed unsigned range."""
    def position(value):
        clipped = np.clip(value, minimum, maximum)
        return int(round((clipped - minimum) / (maximum - minimum)
                         * (geometry.width - 1)))

    left, right = position(low), position(high)
    if left > right:
        left, right = right, left
    cells = [" "] * geometry.width
    if left == right:
        cells[left] = "•"
    else:
        for index in range(left, right + 1):
            cells[index] = "─"
        cells[left], cells[right] = "├", "┤"
    return style("".join(cells), geometry.color, color_code)


def linear_ruler(minimum, maximum, width, labels):
    """Return a fixed-width linear axis and non-overlapping label row."""
    axis = ["─"] * width
    marks = [" "] * width
    occupied = []
    for value, label in labels:
        position = int(round((np.clip(value, minimum, maximum) - minimum)
                             / (maximum - minimum) * (width - 1)))
        start = min(max(position - len(label) // 2, 0), width - len(label))
        end = start + len(label)
        if any(start < used_end and end > used_start
               for used_start, used_end in occupied):
            continue
        axis[position] = "┬"
        marks[start:end] = label
        occupied.append((start, end))
    return "".join(axis), "".join(marks)


def pitch_track_series(samples):
    """Non-overlapping 100 ms pitch observations using the core estimator."""
    values = np.asarray(samples, dtype=np.float64)
    windows = len(values) // WINDOW
    positions = ((np.arange(windows, dtype=np.float64) + 0.5) * WINDOW)
    frequencies = np.full(windows, np.nan, dtype=np.float64)
    for index in range(windows):
        start = index * WINDOW
        hz, confidence = pitch(values[start:start + WINDOW])
        if confidence >= VOICED:
            frequencies[index] = hz
    return positions, frequencies


def render_pitch_tracks(panels, geometry):
    """Absolute voiced-pitch spans on the estimator's fixed log-Hz range."""
    minimum, maximum = np.log2(LO_HZ), np.log2(HI_HZ)
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        positions, frequencies = pitch_track_series(values)
        cuts = np.linspace(0, len(values), geometry.lines + 1)
        chronological = []
        for row in range(geometry.lines):
            selected = frequencies[
                (positions >= cuts[row]) & (positions < cuts[row + 1])]
            selected = selected[np.isfinite(selected)]
            chronological.append(selected)
        rows = []
        for display_row in range(geometry.lines):
            selected = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if not len(selected) else
                range_span_row(
                    np.log2(float(selected.min())),
                    np.log2(float(selected.max())), minimum, maximum, geometry))
        observed = frequencies[np.isfinite(frequencies)]
        if len(observed):
            median = float(np.median(observed))
            median_text = f"median {median:.1f} Hz {note_name(median)}"
            range_text = f"range {observed.min():.1f}..{observed.max():.1f} Hz"
        else:
            median_text = "median n/a"
            range_text = "range n/a"
        footer = ("autocorr pitch / 100 ms", "fixed log 70..1200 Hz",
                  "voiced confidence ≥0.30", "span=min..max per row",
                  "blank=unvoiced/short", "windows anchor at range",
                  "diagnostic, not verdict",
                  f"voiced {len(observed)}/{len(frequencies)} windows",
                  median_text, range_text)
        output.append(TerminalPanel(
            f"pitch-track: {label}", tuple(rows), footer))
    return output


def spectral_centroid_series(samples):
    """Non-overlapping 100 ms DC-removed spectral-centroid observations."""
    values = np.asarray(samples, dtype=np.float64)
    windows = len(values) // WINDOW
    positions = ((np.arange(windows, dtype=np.float64) + 0.5) * WINDOW)
    centroids = np.full(windows, np.nan, dtype=np.float64)
    for index in range(windows):
        start = index * WINDOW
        frame = values[start:start + WINDOW]
        ac = frame - frame.mean()
        if float(ac @ ac) > np.finfo(np.float64).eps:
            centroids[index] = spectral_centroid(frame)
    return positions, centroids


def render_spectral_centroids(panels, geometry):
    """Absolute spectral-centroid spans on a fixed log-Hz range."""
    lower, upper = 55.0, RATE / 2.0
    minimum, maximum = np.log2(lower), np.log2(upper)
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        positions, centroids = spectral_centroid_series(values)
        cuts = np.linspace(0, len(values), geometry.lines + 1)
        chronological = []
        for row in range(geometry.lines):
            selected = centroids[
                (positions >= cuts[row]) & (positions < cuts[row + 1])]
            selected = selected[np.isfinite(selected)]
            chronological.append(selected)
        rows = []
        for display_row in range(geometry.lines):
            selected = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if not len(selected) else
                range_span_row(
                    np.log2(max(float(selected.min()), lower)),
                    np.log2(max(float(selected.max()), lower)),
                    minimum, maximum, geometry, color_code="35"))
        observed = centroids[np.isfinite(centroids)]
        if len(observed):
            median_text = f"median {np.median(observed):.1f} Hz"
            range_text = f"range {observed.min():.1f}..{observed.max():.1f} Hz"
        else:
            median_text = "median n/a"
            range_text = "range n/a"
        footer = ("magnitude centroid / 100ms", "fixed log 55..11025 Hz",
                  "DC removed", "span=min..max per row",
                  "blank=flat/short", "windows anchor at range",
                  "diagnostic, not verdict",
                  f"active {len(observed)}/{len(centroids)} windows",
                  median_text, range_text)
        output.append(TerminalPanel(
            f"spectral-centroid: {label}", tuple(rows), footer))
    return output


def spectral_flatness_series(samples):
    """Non-overlapping 100 ms band-limited power-spectrum flatness."""
    values = np.asarray(samples, dtype=np.float64)
    windows = len(values) // WINDOW
    positions = ((np.arange(windows, dtype=np.float64) + 0.5) * WINDOW)
    flatness = np.full(windows, np.nan, dtype=np.float64)
    hann = np.hanning(WINDOW)
    frequencies = np.fft.rfftfreq(WINDOW, 1.0 / RATE)
    audible = (frequencies >= 55.0) & (frequencies <= 8000.0)
    for index in range(windows):
        start = index * WINDOW
        frame = values[start:start + WINDOW]
        ac = frame - frame.mean()
        power = np.abs(np.fft.rfft(ac * hann))[audible] ** 2
        arithmetic = float(power.mean())
        if arithmetic <= np.finfo(np.float64).eps:
            continue
        # A floor relative to frame energy makes exact empty bins finite while
        # retaining the many-orders-of-magnitude separation of a tonal frame.
        floor = arithmetic * 1e-12
        geometric = float(np.exp(np.mean(np.log(np.maximum(power, floor)))))
        flatness[index] = float(np.clip(geometric / arithmetic, 0.0, 1.0))
    return positions, flatness


def render_spectral_flatness(panels, geometry):
    """Absolute spectral-flatness spans on the fixed zero-to-one scale."""
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        positions, flatness = spectral_flatness_series(values)
        cuts = np.linspace(0, len(values), geometry.lines + 1)
        chronological = []
        for row in range(geometry.lines):
            selected = flatness[
                (positions >= cuts[row]) & (positions < cuts[row + 1])]
            selected = selected[np.isfinite(selected)]
            chronological.append(selected)
        rows = []
        for display_row in range(geometry.lines):
            selected = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if not len(selected) else
                range_span_row(float(selected.min()), float(selected.max()),
                               0.0, 1.0, geometry, color_code="35"))
        observed = flatness[np.isfinite(flatness)]
        if len(observed):
            median_text = f"median {np.median(observed):.3f}"
            range_text = f"range {observed.min():.3f}..{observed.max():.3f}"
        else:
            median_text = "median n/a"
            range_text = "range n/a"
        footer = ("power flatness / 100 ms", "fixed scale 0..1",
                  "0 tonal  1 flat/noisy", "55..8000 Hz Hann",
                  "span=min..max per row", "blank=silent/short",
                  "windows anchor at range", "diagnostic, not verdict",
                  f"active {len(observed)}/{len(flatness)} windows",
                  median_text, range_text)
        output.append(TerminalPanel(
            f"spectral-flatness: {label}", tuple(rows), footer))
    return output


def render_waveforms(panels, geometry):
    """Min/max PCM envelopes with one shared amplitude scale."""
    peak = max((float(np.max(np.abs(samples))) if len(samples) else 0.0
                for _, samples in panels), default=0.0)
    amplitude = max(peak, 1.0)
    output = []
    shared = len(panels) > 1
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        rows = []
        for display_row in range(geometry.lines):
            chronological = geometry.lines - display_row - 1
            lo, hi = cuts[chronological], cuts[chronological + 1]
            segment = values[lo:hi]
            low = float(segment.min()) if len(segment) else 0.0
            high = float(segment.max()) if len(segment) else 0.0
            on_rail = bool(len(segment) and
                           ((segment <= -32768).any()
                            or (segment >= 32767).any()))
            rows.append(span_row(
                low, high, amplitude, geometry,
                color_code="1;31" if on_rail else "36"))
        rail_samples = int(np.count_nonzero(
            (values <= -32768) | (values >= 32767)))
        footer = ("min/max PCM", f"scale ±{amplitude:.0f} PCM",
                  "shared across WAVs" if shared else "scaled to peak",
                  f"rail samples {rail_samples}")
        output.append(TerminalPanel(
            f"waveform: {label}", tuple(rows), footer))
    return output


def intersample_peak_estimate(samples, start=0, end=None):
    """Four-phase windowed-sinc peak estimate with range edges omitted.

    Sixteen decoded samples at either selected-range edge are excluded because
    they do not have the full 33-sample reconstruction context. Internal display
    row boundaries use real neighbouring samples and therefore add no padding or
    row-local discontinuity.
    """
    values = np.asarray(samples, dtype=np.float64)
    end = len(values) if end is None else min(end, len(values))
    valid_start = max(start, INTERSAMPLE_HALF_TAPS)
    valid_end = min(end, len(values) - INTERSAMPLE_HALF_TAPS)
    if valid_end <= valid_start:
        return None
    context = values[
        valid_start - INTERSAMPLE_HALF_TAPS:
        valid_end + INTERSAMPLE_HALF_TAPS]
    windows = np.lib.stride_tricks.sliding_window_view(
        context, INTERSAMPLE_TAP_COUNT)
    reconstructed = windows @ INTERSAMPLE_KERNELS
    return float(np.max(np.abs(reconstructed)))


def intersample_peak_dbfs(samples, start=0, end=None):
    """Estimated reconstructed peak in dBFS, or ``None`` for silence/short."""
    peak = intersample_peak_estimate(samples, start, end)
    if peak is None or peak <= np.finfo(np.float64).eps:
        return None
    return float(20.0 * np.log10(peak / 32768.0))


def render_intersample_peaks(panels, geometry):
    """Four-times reconstructed peaks on a fixed -12..+6 dBFS scale."""
    axis, marks = linear_ruler(
        INTERSAMPLE_MIN_DBFS, INTERSAMPLE_MAX_DBFS, geometry.width,
        ((-12.0, "-12"), (0.0, "0"), (6.0, "+6")))
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            intersample_peak_dbfs(values, cuts[row], cuts[row + 1])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                range_span_row(
                    value, value, INTERSAMPLE_MIN_DBFS,
                    INTERSAMPLE_MAX_DBFS, geometry,
                    color_code="1;31" if value > 0.0 else "36"))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):+.2f} dBFS")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):+.2f} dBFS")
        estimated = intersample_peak_dbfs(values)
        estimated_text = ("recon peak n/a" if estimated is None else
                          f"recon peak {estimated:+.2f} dBFS")
        sample_peak = (None if not len(values) else
                       float(np.max(np.abs(values))))
        if sample_peak is None or sample_peak <= 0.0:
            sample_text = "sample peak n/a"
        else:
            sample_dbfs = 20.0 * np.log10(sample_peak / 32768.0)
            sample_text = f"sample peak {sample_dbfs:+.2f} dBFS"
        footer = (marks, "4x / 33-tap Hann sinc", "fixed -12..+6 dBFS",
                  "0 = reconstructed FS", "red >0 possible over",
                  "not a standards meter", "16 range-edge samples omitted",
                  "diagnostic, not verdict", median_text, max_text,
                  sample_text, estimated_text)
        output.append(TerminalPanel(
            f"intersample-peak: {label}", tuple(rows), footer, axis))
    return output


def rms_level_dbfs(samples):
    """RMS level relative to signed-16-bit full scale, including ``-inf``."""
    values = np.asarray(samples, dtype=np.float64)
    if not len(values):
        return None
    rms_value = float(np.sqrt(np.mean(values * values)))
    if rms_value <= 0:
        return -np.inf
    return 20.0 * np.log10(rms_value / 32768.0)


def format_dbfs(value):
    if value is None:
        return "n/a"
    if np.isneginf(value):
        return "-inf"
    return f"{value:+.2f}"


def render_rms_levels(panels, geometry):
    """Absolute per-row RMS on a fixed -96..0 dBFS scale."""
    minimum, maximum = -96.0, 0.0
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            rms_level_dbfs(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                range_bar_row(value, minimum, maximum, geometry))
        observed = [value for value in chronological if value is not None]
        min_text = ("row min n/a" if not observed else
                    f"row min {format_dbfs(min(observed))} dBFS")
        median_text = ("row median n/a" if not observed else
                       f"row median {format_dbfs(float(np.median(observed)))} dBFS")
        max_text = ("row max n/a" if not observed else
                    f"row max {format_dbfs(max(observed))} dBFS")
        selected = rms_level_dbfs(values)
        selected_text = ("selected RMS n/a" if selected is None else
                         f"selected RMS {format_dbfs(selected)} dBFS")
        footer = ("RMS per time row", "fixed -96..0 dBFS",
                  "left=silent right=loud", "< means ≤-96 dBFS",
                  "diagnostic, not verdict", min_text, median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"rms-level: {label}", tuple(rows), footer))
    return output


def rail_ratio_percent(samples):
    """Percentage of decoded samples exactly on a signed-16-bit PCM rail."""
    values = np.asarray(samples)
    if not len(values):
        return None
    count = np.count_nonzero((values <= -32768) | (values >= 32767))
    return 100.0 * float(count) / len(values)


def render_rail_ratios(panels, geometry):
    """Exact rail occupancy on a fixed logarithmic 1 ppm..100% scale."""
    minimum, maximum = -4.0, 2.0  # log10(percent): 1 ppm through 100%.
    output = []
    for label, samples in panels:
        values = np.asarray(samples)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            rail_ratio_percent(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            if value is None:
                rows.append(" " * geometry.width)
            elif value <= 0:
                rows.append(style(
                    "•" + " " * (geometry.width - 1), geometry.color, "36"))
            else:
                rows.append(range_bar_row(
                    np.log10(value), minimum, maximum, geometry,
                    color_code="1;31"))
        observed = [value for value in chronological if value is not None]
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):.4f}%")
        selected = rail_ratio_percent(values)
        if selected is None:
            count_text = "selected rails n/a"
            ratio_text = "selected ratio n/a"
        else:
            count = int(np.count_nonzero(
                (values <= -32768) | (values >= 32767)))
            count_text = f"selected rails {count}/{len(values)}"
            ratio_text = f"selected ratio {selected:.4f}%"
        footer = ("exact full-scale samples", "log scale 1 ppm..100%",
                  "• none  < ≤1 ppm", "red = rail present",
                  "diagnostic, not verdict", max_text, count_text, ratio_text)
        output.append(TerminalPanel(
            f"rail-ratio: {label}", tuple(rows), footer))
    return output


def peak_occupancy_percent(samples):
    """Percentage of samples within one percent of the local absolute peak."""
    values = np.asarray(samples, dtype=np.float64)
    if len(values) < 2:
        return None
    magnitude = np.abs(values)
    peak = float(magnitude.max())
    if peak <= 0:
        return None
    return 100.0 * float(np.count_nonzero(magnitude >= 0.99 * peak)) / len(values)


def render_peak_occupancy(panels, geometry):
    """Near-peak sample occupancy per row on a fixed 0..100% scale."""
    scale = 100.0
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            peak_occupancy_percent(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                positive_bar_row(value, scale, geometry, color_code="35"))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):.2f}%")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):.2f}%")
        selected = peak_occupancy_percent(values)
        selected_text = ("whole-range occ n/a" if selected is None else
                         f"whole-range occ {selected:.2f}%")
        peak_text = ("whole peak n/a" if not len(values) else
                     f"whole peak {np.max(np.abs(values)):.0f} PCM")
        footer = ("samples within 1% peak", "row-local |x| ≥.99 peak",
                  "fixed scale 0..100%", "right=more peak-stuck",
                  "blank=<2/silence", "diagnostic, not verdict",
                  "compare waveform/crest", median_text, max_text,
                  peak_text, selected_text)
        output.append(TerminalPanel(
            f"peak-occupancy: {label}", tuple(rows), footer))
    return output


def quantization_step_pcm(samples):
    """GCD of gaps between occupied non-rail integer PCM levels."""
    values = np.asarray(samples)
    if len(values) < 2:
        return None
    integer = np.rint(values).astype(np.int64)
    interior = integer[(integer > -32768) & (integer < 32767)]
    levels = np.unique(interior)
    if len(levels) < 2:
        return None
    step = int(np.gcd.reduce(np.diff(levels)))
    return step if step > 0 else None


def render_quantization_steps(panels, geometry):
    """Per-row occupied PCM lattice step on a fixed logarithmic scale."""
    minimum, maximum = 0.0, 15.0  # log2(1 PCM) through log2(32768 PCM).
    output = []
    for label, samples in panels:
        values = np.asarray(samples)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            quantization_step_pcm(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            if value is None:
                rows.append(" " * geometry.width)
            elif value <= 1:
                rows.append(style(
                    "•" + " " * (geometry.width - 1), geometry.color, "36"))
            else:
                rows.append(range_bar_row(
                    np.log2(value), minimum, maximum, geometry,
                    color_code="1;35"))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):.1f} PCM")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed)} PCM")
        selected = quantization_step_pcm(values)
        selected_text = ("selected step n/a" if selected is None else
                         f"selected step {selected} PCM")
        footer = ("GCD of occupied levels", "log2 scale 1..32768 PCM",
                  "• = 1 PCM step", "right edge ≥32768 PCM",
                  "blank=<2 interior levels", "exact rails excluded",
                  "diagnostic, not verdict", median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"quantization-step: {label}", tuple(rows), footer))
    return output


def flatline_ratio(samples):
    """Percentage of adjacent decoded PCM samples which are exactly equal."""
    values = np.asarray(samples)
    if len(values) < 2:
        return None
    return 100.0 * float(np.count_nonzero(np.diff(values) == 0)) / (len(values) - 1)


def render_flatline_ratios(panels, geometry):
    """Exact adjacent-sample equality per row on a fixed 0..100% scale."""
    scale = 100.0
    output = []
    for label, samples in panels:
        values = np.asarray(samples)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            flatline_ratio(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                positive_bar_row(value, scale, geometry))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):.2f}%")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):.2f}%")
        selected = flatline_ratio(values)
        selected_text = ("selected flat n/a" if selected is None else
                         f"selected flat {selected:.2f}%")
        footer = ("equal adjacent samples", "fixed scale 0..100%",
                  "right=more flat/repeated", "blank=<2 samples",
                  "diagnostic, not verdict", median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"flatline-ratio: {label}", tuple(rows), footer))
    return output


def crest_factor_db(samples):
    """Return peak-to-RMS ratio in decibels, or ``None`` for silence."""
    values = np.asarray(samples, dtype=np.float64)
    if not len(values):
        return None
    peak = float(np.max(np.abs(values)))
    rms_value = float(np.sqrt(np.mean(values * values)))
    if peak <= 0 or rms_value <= 0:
        return None
    return max(0.0, 20.0 * np.log10(peak / rms_value))


def render_crest_factors(panels, geometry):
    """Peak/RMS dynamics per display row on a fixed 0..24 dB scale."""
    scale = 24.0
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            crest_factor_db(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                positive_bar_row(value, scale, geometry,
                                 color_code="1;35" if value >= scale else "36"))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):.2f} dB")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):.2f} dB")
        selected = crest_factor_db(values)
        selected_text = ("selected crest n/a" if selected is None else
                         f"selected crest {selected:.2f} dB")
        footer = ("peak/RMS per time row", "fixed scale 0..24 dB",
                  "right edge means ≥24 dB", "blank=silence",
                  "diagnostic, not verdict", median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"crest-factor: {label}", tuple(rows), footer))
    return output


def derivative_ratio_db(samples):
    """First-difference RMS divided by mean-removed sample RMS in dB."""
    values = np.asarray(samples, dtype=np.float64)
    if len(values) < 2:
        return None
    ac = values - values.mean()
    signal_rms = float(np.sqrt(np.mean(ac * ac)))
    derivative = np.diff(values)
    derivative_rms = float(np.sqrt(np.mean(derivative * derivative)))
    if signal_rms <= 0 or derivative_rms <= 0:
        return None
    return 20.0 * np.log10(derivative_rms / signal_rms)


def render_derivative_ratios(panels, geometry):
    """Time-local first-difference/AC RMS ratio on a fixed dB scale."""
    minimum, maximum = -48.0, 6.0
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [
            derivative_ratio_db(values[cuts[row]:cuts[row + 1]])
            for row in range(geometry.lines)
        ]
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                range_bar_row(value, minimum, maximum, geometry))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):+.2f} dB")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):+.2f} dB")
        selected = derivative_ratio_db(values)
        selected_text = ("selected ratio n/a" if selected is None else
                         f"selected ratio {selected:+.2f} dB")
        footer = ("diff RMS / AC RMS", "fixed -48..+6 dB",
                  "left=smooth right=rough", "blank=constant/silence",
                  "diagnostic, not verdict", median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"derivative-ratio: {label}", tuple(rows), footer))
    return output


def spectral_change_series(samples):
    """Midpoint samples and cosine changes between normalized Hann spectra."""
    values = np.asarray(samples, dtype=np.float64)
    if len(values) < SPECTRAL_CHANGE_WINDOW + SPECTRAL_CHANGE_HOP:
        return np.array([], dtype=np.float64), np.array([], dtype=np.float64)
    starts = np.arange(
        0, len(values) - SPECTRAL_CHANGE_WINDOW + 1,
        SPECTRAL_CHANGE_HOP, dtype=np.int64)
    window = np.hanning(SPECTRAL_CHANGE_WINDOW)
    spectra = []
    active = []
    for start in starts:
        frame = values[start:start + SPECTRAL_CHANGE_WINDOW]
        frame = (frame - frame.mean()) * window
        magnitude = np.abs(np.fft.rfft(frame))[1:]
        norm = float(np.linalg.norm(magnitude))
        is_active = norm > np.finfo(np.float64).eps
        active.append(is_active)
        spectra.append(magnitude / norm if is_active else np.zeros_like(magnitude))
    changes = []
    for index in range(1, len(spectra)):
        if not active[index - 1] and not active[index]:
            changes.append(np.nan)
        elif active[index - 1] != active[index]:
            changes.append(1.0)
        else:
            similarity = float(np.dot(spectra[index - 1], spectra[index]))
            changes.append(float(np.clip(1.0 - similarity, 0.0, 1.0)))
    midpoints = ((starts[:-1] + starts[1:] + SPECTRAL_CHANGE_WINDOW)
                 / 2.0)
    return midpoints, np.asarray(changes, dtype=np.float64)


def render_spectral_changes(panels, geometry):
    """Maximum adjacent-frame normalized spectral change per displayed row."""
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        positions, changes = spectral_change_series(values)
        cuts = np.linspace(0, len(values), geometry.lines + 1)
        chronological = []
        for row in range(geometry.lines):
            selected = changes[
                (positions >= cuts[row]) & (positions < cuts[row + 1])]
            selected = selected[np.isfinite(selected)]
            chronological.append(
                float(selected.max()) if len(selected) else None)
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                positive_bar_row(value, 1.0, geometry, color_code="35"))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):.3f}")
        max_text = ("row max n/a" if not observed else
                    f"row max {max(observed):.3f}")
        selected_text = ("selected max n/a" if not observed else
                         f"selected max {max(observed):.3f}")
        footer = ("max 1-cos spectrum/row", "1024 Hann / 512 hop",
                  "fixed scale 0..1", "0 same  1 disjoint",
                  "DC removed; level norm", "blank=no frame pair",
                  "diagnostic, not verdict", median_text, max_text,
                  selected_text)
        output.append(TerminalPanel(
            f"spectral-change: {label}", tuple(rows), footer))
    return output


def sample_density_row(samples, geometry):
    """Render one time slice as an absolute signed-16-bit amplitude histogram."""
    values = np.asarray(samples, dtype=np.float64)
    if not len(values):
        return " " * geometry.width
    counts, _ = np.histogram(
        np.clip(values, -32768.0, 32767.0),
        bins=np.linspace(-32768.0, 32768.0, geometry.width + 1))
    maximum = int(counts.max())
    glyphs = (" ", "░", "▒", "▓", "█")
    cells = []
    for count in counts:
        if count == 0 or maximum == 0:
            cells.append(" ")
            continue
        # Square-root compression retains sparse quantized levels without
        # letting a single dominant bin hide every other occupied amplitude.
        strength = np.sqrt(count / maximum)
        level = max(1, min(4, int(np.ceil(strength * 4))))
        cells.append(style(
            glyphs[level], geometry.color,
            "1;36" if level >= 3 else "36"))
    centre = geometry.width // 2
    if cells[centre] == " ":
        cells[centre] = style("│", geometry.color, "2")
    if np.any(values <= -32768):
        cells[0] = style("█", geometry.color, "1;31")
    if np.any(values >= 32767):
        cells[-1] = style("█", geometry.color, "1;31")
    return "".join(cells)


def render_sample_density(panels, geometry):
    """Time-local amplitude histograms on the fixed signed-16-bit scale."""
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        rows = []
        for display_row in range(geometry.lines):
            chronological = geometry.lines - display_row - 1
            lo, hi = cuts[chronological], cuts[chronological + 1]
            rows.append(sample_density_row(values[lo:hi], geometry))
        rail_samples = int(np.count_nonzero(
            (values <= -32768) | (values >= 32767)))
        mean = float(values.mean()) if len(values) else 0.0
        footer = ("amplitude density / time", "fixed -32768..+32767 PCM",
                  "density normalized per row", "cyan low→high density",
                  "red edge = rail sample", f"mean {mean:+.1f} PCM",
                  f"rail samples {rail_samples}")
        output.append(TerminalPanel(
            f"sample-density: {label}", tuple(rows), footer))
    return output


def render_dc_offsets(panels, geometry):
    """Per-row signed sample mean, with one shared diagnostic scale."""
    observations = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = []
        for row in range(geometry.lines):
            segment = values[cuts[row]:cuts[row + 1]]
            chronological.append(
                float(segment.mean()) if len(segment) else 0.0)
        observations.append((label, values, chronological))
    scale = max(
        256.0,
        max((abs(value) for _, _, means in observations for value in means),
            default=0.0))
    shared = len(panels) > 1
    output = []
    for label, values, chronological in observations:
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(span_row(
                value, value, scale, geometry,
                color_code="1;31" if abs(value) >= 256.0 else "36"))
        selected_mean = float(values.mean()) if len(values) else 0.0
        footer = ("mean PCM per time row", f"scale ±{scale:.1f} PCM",
                  "shared across WAVs" if shared else "minimum scale ±256 PCM",
                  "red |mean| ≥256 PCM", "diagnostic, not verdict",
                  "right=positive", f"selected mean {selected_mean:+.1f} PCM")
        output.append(TerminalPanel(
            f"dc-offset: {label}", tuple(rows), footer))
    return output


def render_pitch_delta(result, geometry):
    """Signed candidate-minus-reference pitch error for voiced windows."""
    start = geometry.start_seconds
    end = start + geometry.seconds

    def observation(item):
        window_start = item.index * WINDOW / RATE
        window_end = (item.index + 1) * WINDOW / RATE
        if window_end <= start or window_start >= end:
            return None
        if item.pitch_agreed is None:
            return None
        if item.reference_hz <= 0 or item.candidate_hz <= 0:
            return None
        return 12.0 * np.log2(item.candidate_hz / item.reference_hz)

    observed = [(item, observation(item)) for item in result.windows]
    values = [value for _, value in observed if value is not None]
    scale = max(1.0, max((abs(value) for value in values), default=0.0))
    tolerance = result.data["policy"]["pitch"]["tolerance_semitones"]
    rows = []
    for row in range(geometry.lines):
        low_time, high_time = row_interval(geometry, row)
        selected = [value for item, value in observed
                    if value is not None
                    and item.index * WINDOW / RATE < high_time
                    and (item.index + 1) * WINDOW / RATE > low_time]
        if not selected:
            rows.append(" " * geometry.width)
            continue
        beyond = any(abs(value) > tolerance for value in selected)
        rows.append(span_row(
            min(selected), max(selected), scale, geometry,
            color_code="1;31" if beyond else "32"))
    footer = ("candidate-reference", f"scale ±{scale:.2f} st",
              f"guard ±{tolerance:.2f} st", "right=sharp blank=n/a")
    return TerminalPanel(
        f"pitch-delta: {result.data['label']}", tuple(rows), footer)


def status_span_row(low, high, scale, geometry, *, failed):
    """Prefix a signed span with a deterministic good/bad marker."""
    plot_geometry = TerminalGeometry(
        geometry.start_seconds, geometry.seconds, geometry.lines,
        geometry.width - 2, geometry.layout, geometry.axis, geometry.color)
    marker = style("!" if failed else "·", geometry.color,
                   "1;31" if failed else "32")
    return marker + " " + span_row(
        low, high, scale, plot_geometry,
        color_code="1;31" if failed else "32")


def render_level_delta(result, geometry):
    """Signed per-window candidate/reference RMS error in decibels."""
    policy = result.data["policy"]["level"]
    live_minimum = policy["live_rms_minimum"]
    start = geometry.start_seconds
    end = start + geometry.seconds

    def observation(item):
        window_start = item.index * WINDOW / RATE
        window_end = (item.index + 1) * WINDOW / RATE
        if window_end <= start or window_start >= end:
            return None
        if item.reference_rms <= live_minimum:
            return None
        ratio = max(item.candidate_rms, 1.0) / item.reference_rms
        return 20.0 * np.log10(ratio)

    observed = [(item, observation(item)) for item in result.windows]
    values = [value for _, value in observed if value is not None]
    scale = max(3.0, max((abs(value) for value in values), default=0.0))
    minimum = policy["median_ratio_minimum"]
    maximum = policy["median_ratio_maximum"]
    rows = []
    for row in range(geometry.lines):
        low_time, high_time = row_interval(geometry, row)
        selected = [(item, value) for item, value in observed
                    if value is not None
                    and item.index * WINDOW / RATE < high_time
                    and (item.index + 1) * WINDOW / RATE > low_time]
        if not selected:
            rows.append(" " * geometry.width)
            continue
        failed = any(
            (minimum is not None
             and item.candidate_rms / item.reference_rms < minimum)
            or (maximum is not None
                and item.candidate_rms / item.reference_rms > maximum)
            for item, _ in selected)
        row_values = [value for _, value in selected]
        rows.append(status_span_row(
            min(row_values), max(row_values), scale, geometry,
            failed=failed))
    if minimum is None and maximum is None:
        guard = "guard report-only"
    else:
        low_db = 20.0 * np.log10(minimum) if minimum is not None else -np.inf
        high_db = 20.0 * np.log10(maximum) if maximum is not None else np.inf
        guard = f"guard {low_db:+.2f}/{high_db:+.2f} dB"
    footer = ("candidate/reference RMS", f"scale ±{scale:.2f} dB", guard,
              "right=louder blank=n/a", "silence floor 1 PCM")
    return TerminalPanel(
        f"level-delta: {result.data['label']}", tuple(rows), footer)


def render_timing_drift(result, geometry):
    """Best-lag movement relative to the trusted modal lock lag."""
    observations = result.lock_observations
    lock_result = result.data.get("lock")
    modal = lock_result.get("modal_lag_samples") if lock_result else None
    trusted_mode = modal is not None
    if modal is None:
        modal = (int(round(np.median([item.lag_samples
                                     for item in observations])))
                 if observations else 0)
    policy = result.data["policy"]["lock"]
    correlation_minimum = policy["block_correlation_minimum"]
    lag_tolerance = policy["lag_tolerance_samples"]
    start = geometry.start_seconds
    end = start + geometry.seconds
    selected_range = [item for item in observations
                      if item.time_seconds < end
                      and item.time_seconds + item.duration_seconds > start]
    drift = [(item.lag_samples - modal) * 1000.0 / RATE
             for item in selected_range]
    scale = max(1.0, max((abs(value) for value in drift), default=0.0))
    rows = []
    for row in range(geometry.lines):
        low_time, high_time = row_interval(geometry, row)
        selected = [item for item in selected_range
                    if item.time_seconds < high_time
                    and item.time_seconds + item.duration_seconds > low_time]
        if not selected:
            rows.append(" " * geometry.width)
            continue
        values = [(item.lag_samples - modal) * 1000.0 / RATE
                  for item in selected]
        failed = (not trusted_mode or any(
            item.correlation <= correlation_minimum
            or abs(item.lag_samples - modal) > lag_tolerance
            for item in selected))
        rows.append(status_span_row(
            min(values), max(values), scale, geometry, failed=failed))
    guard_ms = lag_tolerance * 1000.0 / RATE
    base_kind = "mode" if trusted_mode else "visual median"
    footer = ("lag drift from base", f"scale ±{scale:.2f} ms",
              f"guard ±{guard_ms:.2f} ms", f"{base_kind} {modal:+d} samples",
              "! weak/outside guard", "right=later blank=n/a")
    return TerminalPanel(
        f"timing-drift: {result.data['label']}", tuple(rows), footer)


def paired_trajectory_row(reference, candidate, geometry):
    """Plot two normalized observations on one signed horizontal axis."""
    centre = geometry.width // 2

    def position(value):
        if value == 0:
            return centre
        return int(round((np.clip(value / 3.0, -1, 1) + 1)
                         * (geometry.width - 1) / 2))

    reference_at = position(reference)
    candidate_at = position(candidate)
    cells = [" "] * geometry.width
    cells[centre] = "│"
    if reference_at == candidate_at:
        cells[reference_at] = style("◆", geometry.color, "1;32")
    else:
        left, right = sorted((reference_at, candidate_at))
        for index in range(left + 1, right):
            cells[index] = "─"
        if left < centre < right:
            cells[centre] = "┼"
        cells[reference_at] = style("R", geometry.color, "1;34")
        cells[candidate_at] = style("C", geometry.color, "1;31")
    return "".join(cells)


def render_contour(result, geometry):
    """Normalized loudness/timbre trajectories for unpitched comparison."""
    titles = (f"contour-level: {result.data['label']}",
              f"contour-timbre: {result.data['label']}")
    if result.data["pitched_reference"]:
        footer = ("not applicable: pitched",)
        blank = tuple(" " * geometry.width for _ in range(geometry.lines))
        return [TerminalPanel(title, blank, footer) for title in titles]

    start = geometry.start_seconds
    end = start + geometry.seconds
    selected = [item for item in result.windows
                if item.index * WINDOW / RATE < end
                and (item.index + 1) * WINDOW / RATE > start]
    if len(selected) < 4:
        footer = ("need at least 4 windows",)
        blank = tuple(" " * geometry.width for _ in range(geometry.lines))
        return [TerminalPanel(title, blank, footer) for title in titles]

    series = (
        ([item.reference_rms for item in selected],
         [item.candidate_rms for item in selected]),
        ([item.reference_contour_centroid_hz for item in selected],
         [item.candidate_contour_centroid_hz for item in selected]),
    )
    correlations = result.data.get("contour") or {}
    correlation_values = (correlations.get("loudness_correlation"),
                          correlations.get("timbre_correlation"))
    panels = []
    for title, (reference_values, candidate_values), correlation in zip(
            titles, series, correlation_values):
        reference_values = np.asarray(reference_values, dtype=np.float64)
        candidate_values = np.asarray(candidate_values, dtype=np.float64)

        def normalize(values):
            deviation = float(values.std())
            return ((values - values.mean()) / deviation
                    if deviation > 0 else np.zeros_like(values))

        reference_z = normalize(reference_values)
        candidate_z = normalize(candidate_values)
        rows = []
        for row in range(geometry.lines):
            low_time, high_time = row_interval(geometry, row)
            indexes = [index for index, item in enumerate(selected)
                       if item.index * WINDOW / RATE < high_time
                       and (item.index + 1) * WINDOW / RATE > low_time]
            if not indexes:
                rows.append(" " * geometry.width)
                continue
            rows.append(paired_trajectory_row(
                float(reference_z[indexes].mean()),
                float(candidate_z[indexes].mean()), geometry))
        correlation_text = ("full corr n/a" if correlation is None
                            else f"full corr {correlation:+.3f}")
        footer = ("R reference C candidate", "selected-range z-score",
                  "scale ±3σ clipped", "◆ same display cell",
                  correlation_text)
        panels.append(TerminalPanel(title, tuple(rows), footer))
    return panels


def band_delta_glyph(value, tolerance, geometry):
    """Signed local band deviation with policy-boundary emphasis."""
    if value is None:
        return "-"
    if abs(value) <= 0.5:
        return style("·", geometry.color, "32")
    if value < -tolerance:
        return style("<", geometry.color, "1;34")
    if value > tolerance:
        return style(">", geometry.color, "1;31")
    if value < 0:
        return style(",", geometry.color, "34")
    return style(".", geometry.color, "31")


def render_band_delta(result, geometry):
    """Time-local four-band deviations plus verdict-scope aggregates."""
    observations = result.band_observations
    tolerance = result.data["policy"]["bands"]["tolerance_db"]
    start = geometry.start_seconds
    end = start + geometry.seconds
    selected_range = [item for item in observations
                      if item.time_seconds < end
                      and item.time_seconds + item.duration_seconds > start]
    short_names = ("B", "M", "H", "U")
    rows = []
    for row in range(geometry.lines):
        low_time, high_time = row_interval(geometry, row)
        selected = [item for item in selected_range
                    if item.time_seconds < high_time
                    and item.time_seconds + item.duration_seconds > low_time]
        if not selected:
            rows.append(" " * geometry.width)
            continue
        glyphs = []
        for band_index in range(len(BANDS)):
            values = [item.deltas_db[band_index] for item in selected
                      if item.deltas_db[band_index] is not None]
            worst = max(values, key=lambda value: abs(value)) if values else None
            glyphs.append(
                short_names[band_index]
                + band_delta_glyph(worst, tolerance, geometry))
        quiet = (style("q", geometry.color, "33")
                 if any(item.quiet_reference for item in selected) else " ")
        rows.append(pad(quiet + " " + " ".join(glyphs), geometry.width))

    def aggregate_value(value):
        if value is None:
            return "n/a"
        if not np.isfinite(value):
            return "-inf" if value < 0 else "+inf"
        return f"{value:+.1f}"

    aggregate_lines = tuple(
        f"{short} W{aggregate_value(band['whole_db'])} "
        f"Q{aggregate_value(band['quiet_db'])} dB"
        for short, band in zip(short_names, result.data["bands"]))
    footer = ("B 55-250  M 250-1k", "H 1-4k    U 4-8k",
              "< missing  > excess", ",/. inside guard",
              f"guard ±{tolerance:.2f} dB", "q reference-quiet",
              "W whole Q quiet", *aggregate_lines)
    return TerminalPanel(
        f"band-delta: {result.data['label']}", tuple(rows), footer)


def spectral_diff_cell(value, color):
    """Signed dB-difference cell; full-strength glyphs begin at 24 dB."""
    magnitude = abs(value)
    if magnitude < 3.0:
        return " "
    if value < 0:
        glyph = ("," if magnitude < 6 else "-" if magnitude < 12
                 else "=" if magnitude < 24 else "<")
        code = "34" if magnitude < 12 else "1;34"
    else:
        glyph = ("." if magnitude < 6 else "+" if magnitude < 12
                 else "*" if magnitude < 24 else ">")
        code = "31" if magnitude < 12 else "1;31"
    return style(glyph, color, code)


def _cross_spectral_grid(reference, candidate, times, bands):
    """Phase, normalized coherence, and powers by time/log frequency."""
    reference = np.asarray(reference, dtype=np.float64)
    candidate = np.asarray(candidate, dtype=np.float64)
    count = min(len(reference), len(candidate))
    if count < SPEC_FFT or times < 1 or bands < 1:
        return None
    hop = SPEC_FFT // 2
    frames = 1 + (count - SPEC_FFT) // hop
    indices = (np.arange(SPEC_FFT)[None, :]
               + hop * np.arange(frames)[:, None])
    window = np.hanning(SPEC_FFT)
    reference_spectrum = np.fft.rfft(
        reference[indices] * window, axis=1)
    candidate_spectrum = np.fft.rfft(
        candidate[indices] * window, axis=1)
    frequencies = np.arange(reference_spectrum.shape[1]) * RATE / SPEC_FFT
    edges = np.geomspace(
        SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2), bands + 1)
    cuts = np.linspace(0, frames, times + 1).astype(int)
    phase = np.full((bands, times), np.nan, dtype=np.float64)
    coherence = np.full_like(phase, np.nan)
    reference_power = np.zeros_like(phase)
    candidate_power = np.zeros_like(phase)

    for band in range(bands):
        selected_bins = ((frequencies >= edges[band])
                         & (frequencies < edges[band + 1]))
        if not selected_bins.any():
            selected_bins = np.zeros(len(frequencies), dtype=bool)
            centre = np.sqrt(edges[band] * edges[band + 1])
            selected_bins[int(np.argmin(np.abs(frequencies - centre)))] = True
        for column in range(times):
            low = cuts[column]
            high = min(max(low + 1, cuts[column + 1]), frames)
            reference_cell = reference_spectrum[low:high, selected_bins]
            candidate_cell = candidate_spectrum[low:high, selected_bins]
            ref_power = float(np.mean(np.abs(reference_cell) ** 2))
            cand_power = float(np.mean(np.abs(candidate_cell) ** 2))
            reference_power[band, column] = ref_power
            candidate_power[band, column] = cand_power
            denominator = np.sqrt(
                np.sum(np.abs(reference_cell) ** 2)
                * np.sum(np.abs(candidate_cell) ** 2))
            if denominator <= np.finfo(np.float64).eps:
                continue
            cross = np.sum(candidate_cell * np.conj(reference_cell))
            coherence[band, column] = abs(cross) / denominator
            phase[band, column] = np.degrees(np.angle(cross))

    return phase, coherence, reference_power, candidate_power, edges


def _shared_power_mask(reference_power, candidate_power):
    """Cells where both inputs are within the shared 60 dB power range."""
    shared_peak = max(float(reference_power.max()),
                      float(candidate_power.max()))
    if shared_peak <= np.finfo(np.float64).eps:
        return np.zeros(reference_power.shape, dtype=bool)
    power_floor = shared_peak * 10.0 ** (-PHASE_DYNAMIC_DB / 10.0)
    return ((reference_power >= power_floor)
            & (candidate_power >= power_floor))


def phase_difference_grid(reference, candidate, times, bands):
    """Wrapped candidate-minus-reference phase by time and log frequency.

    A cell is usable only when both inputs are within 60 dB of the shared
    cell-power peak and normalized cross-spectrum coherence is at least 0.80.
    This prevents arbitrary phase from weak or internally inconsistent energy
    from looking like a measured phase offset.
    """
    measured = _cross_spectral_grid(reference, candidate, times, bands)
    if measured is None:
        return None
    phase, coherence, reference_power, candidate_power, edges = measured
    usable = (_shared_power_mask(reference_power, candidate_power)
              & (coherence >= PHASE_COHERENCE_MINIMUM))
    phase = phase.copy()
    phase[~usable] = np.nan
    return phase, coherence, edges


def coherence_grid(reference, candidate, times, bands):
    """Normalized complex cross-spectrum coherence on a fixed 0..1 scale.

    This is the magnitude of the normalized complex inner product across all
    STFT coefficients in a time/frequency cell. It is not magnitude-squared
    coherence: stable phase and matching spectral shape approach one, while
    changing phase or nonmatching spectral coefficients approach zero.
    """
    measured = _cross_spectral_grid(reference, candidate, times, bands)
    if measured is None:
        return None
    _, coherence, reference_power, candidate_power, edges = measured
    coherence = coherence.copy()
    coherence[~_shared_power_mask(reference_power, candidate_power)] = np.nan
    return coherence, edges


def coherence_cell(value, color):
    """One fixed-threshold normalized-coherence cell."""
    if not np.isfinite(value):
        return " "
    if value < 0.25:
        return style("X", color, "1;31")
    if value < 0.50:
        return style("O", color, "1;35")
    if value < 0.75:
        return style("o", color, "34")
    if value < 0.90:
        return style(".", color, "36")
    return style("·", color, "2;32")


def phase_diff_cell(value, color):
    """One wrapped signed-phase cell on the fixed -180..+180 degree scale."""
    if not np.isfinite(value) or abs(value) < PHASE_NEUTRAL_DEGREES:
        return " "
    # Bin/window arithmetic can report 89.999... for an exact quarter-cycle.
    # Classify at the same one-decimal precision printed in the footer so the
    # glyph and numeric summary cannot contradict each other.
    magnitude = round(abs(value), 1)
    if value < 0:
        glyph = ("," if magnitude < 30.0 else "-" if magnitude < 90.0
                 else "=" if magnitude < 150.0 else "<")
        code = "34" if magnitude < 90.0 else "1;34"
    else:
        glyph = ("." if magnitude < 30.0 else "+" if magnitude < 90.0
                 else "*" if magnitude < 150.0 else ">")
        code = "31" if magnitude < 90.0 else "1;31"
    return style(glyph, color, code)


def _render_phase_panel(reference, candidate, geometry, *, title, relationship,
                        positive_text, scope=None):
    """Shared fixed-contract renderer for inter-file or inter-channel phase."""
    measured = phase_difference_grid(
        reference, candidate, geometry.lines, geometry.width)
    if measured is None:
        message = "range too short for 1024-sample STFT"
        return TerminalPanel(
            title, tuple(fit(message, geometry.width)
                         for _ in range(geometry.lines)),
            tuple(item for item in (scope, "wrapped; diagnostic only") if item))
    phase, coherence, edges = measured
    chronological = phase.T
    rows = tuple(
        "".join(phase_diff_cell(value, geometry.color) for value in row)
        for row in chronological[::-1])
    usable = phase[np.isfinite(phase)]
    coherent = coherence[np.isfinite(phase)]
    measured_text = f"measured {len(usable)}/{phase.size} cells"
    shifted_text = (
        f"shifted {np.count_nonzero(np.abs(usable) >= PHASE_NEUTRAL_DEGREES)}"
        f"/{phase.size} cells")
    max_text = ("max |phase| n/a" if not len(usable) else
                f"max |phase| {np.max(np.abs(usable)):.1f} deg")
    coherence_text = ("min coherence n/a" if not len(coherent) else
                      f"min coherence {np.min(coherent):.3f}")
    axis, marks = ruler(edges, geometry.width)
    footer = (marks, relationship, "fixed -180..+180 deg",
              "blue <0  red >0", "blank |phase| <5 deg",
              ",/. <30  -/+ <90", "=/* <150  </> >=150",
              "require coherence >=0.80", "both levels within 60 dB",
              "1024 Hann / 512 hop", positive_text,
              *(item for item in (scope,) if item),
              "wrapped; diagnostic only", measured_text, shifted_text, max_text,
              coherence_text)
    return TerminalPanel(title, rows, footer, axis)


def render_phase_diff(reference, candidate, geometry, *, label=None):
    """Frequency-resolved wrapped phase after comparison sample alignment."""
    title = f"phase-diff: {label}" if label else "phase-diff"
    return _render_phase_panel(
        reference, candidate, geometry, title=title,
        relationship="candidate-reference phase",
        positive_text="+ means candidate leads")


def render_stereo_phases(panels, geometry):
    """Frequency-resolved channel-2-minus-channel-1 phase for each input."""
    output = []
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        title = f"stereo-phase: {label}"
        if channel_count >= 2:
            output.append(_render_phase_panel(
                channels[:, 0], channels[:, 1], geometry, title=title,
                relationship="channel 2-channel 1 phase",
                positive_text="+ means channel 2 leads", scope=scope))
            continue
        edges = np.geomspace(
            SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2), geometry.width + 1)
        axis, marks = ruler(edges, geometry.width)
        footer = (marks, "channel 2-channel 1 phase",
                  "fixed -180..+180 deg", scope,
                  "wrapped; diagnostic only")
        output.append(TerminalPanel(
            title, tuple(" " * geometry.width
                         for _ in range(geometry.lines)), footer, axis))
    return output


def _render_coherence_panel(reference, candidate, geometry, *, title,
                            relationship, scope=None,
                            caution="low can be width/reverb/noise"):
    """Shared frequency-resolved normalized cross-spectrum coherence."""
    measured = coherence_grid(
        reference, candidate, geometry.lines, geometry.width)
    if measured is None:
        message = "range too short for 1024-sample STFT"
        return TerminalPanel(
            title, tuple(fit(message, geometry.width)
                         for _ in range(geometry.lines)),
            tuple(item for item in (
                scope, "normalized, not squared", "diagnostic, not verdict")
                  if item))
    coherence, edges = measured
    rows = tuple(
        "".join(coherence_cell(value, geometry.color) for value in row)
        for row in coherence.T[::-1])
    usable = coherence[np.isfinite(coherence)]
    measured_text = f"measured {len(usable)}/{coherence.size} cells"
    low_text = f"below .90 {np.count_nonzero(usable < 0.90)}/{len(usable)}"
    minimum_text = ("minimum n/a" if not len(usable) else
                    f"minimum {np.min(usable):.3f}")
    median_text = ("median n/a" if not len(usable) else
                   f"median {np.median(usable):.3f}")
    axis, marks = ruler(edges, geometry.width)
    footer = (marks, relationship, "fixed coherence 0..1",
              "X <.25  O <.50", "o <.75  . <.90", "· >=.90",
              "both levels within 60 dB", "1024 Hann / 512 hop",
              "normalized, not squared",
              *(item for item in (scope,) if item),
              caution, "diagnostic, not verdict",
              measured_text, low_text, minimum_text, median_text)
    return TerminalPanel(title, rows, footer, axis)


def render_stereo_coherences(panels, geometry):
    """Frequency-resolved channel-1/channel-2 spectral coherence."""
    output = []
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        title = f"stereo-coherence: {label}"
        if channel_count >= 2:
            output.append(_render_coherence_panel(
                channels[:, 0], channels[:, 1], geometry, title=title,
                relationship="channel 1/2 cross-spectrum", scope=scope))
            continue
        edges = np.geomspace(
            SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2), geometry.width + 1)
        axis, marks = ruler(edges, geometry.width)
        footer = (marks, "channel 1/2 cross-spectrum",
                  "fixed coherence 0..1", "normalized, not squared", scope,
                  "diagnostic, not verdict")
        output.append(TerminalPanel(
            title, tuple(" " * geometry.width
                         for _ in range(geometry.lines)), footer, axis))
    return output


def render_spectral_coherence(reference, candidate, geometry, *, label=None):
    """Frequency-resolved reference/candidate spectral coherence."""
    title = (f"spectral-coherence: {label}"
             if label else "spectral-coherence")
    return _render_coherence_panel(
        reference, candidate, geometry, title=title,
        relationship="reference/candidate cross-spectrum",
        caution="low may be intentional")


def _render_spectral_diff_panel(reference, candidate, geometry, *, title,
                                legend, scope=None):
    """Shared signed log-frequency level difference with one shared floor."""
    grids = [spectrogram(samples, geometry.lines * 2, geometry.width)
             for samples in (reference, candidate)]
    if any(grid is None for grid in grids):
        message = "range too short for 1024-sample STFT"
        return TerminalPanel(
            title, tuple(fit(message, geometry.width)
                         for _ in range(geometry.lines)),
            tuple(item for item in (scope,) if item))
    decibels = [grid[0].T[::-1] for grid in grids]
    floor, ceiling = spectral_scale(decibels)
    clipped = [np.clip(values, floor, ceiling) for values in decibels]
    delta = (clipped[1] - clipped[0]).reshape(
        geometry.lines, 2, geometry.width).mean(axis=1)
    rows = tuple("".join(spectral_diff_cell(value, geometry.color)
                         for value in row) for row in delta)
    axis, marks = ruler(grids[0][1], geometry.width)
    footer = (marks, legend, "blank |Δ| <3 dB", "full at ±24 dB",
              f"floor {floor - ceiling:+.0f} dB shared",
              *(item for item in (scope,) if item))
    return TerminalPanel(title, rows, footer, axis)


def render_spectral_diff(reference, candidate, geometry, *, label=None):
    """Signed candidate-minus-reference energy over log frequency and time."""
    title = f"spectral-diff: {label}" if label else "spectral-diff"
    return _render_spectral_diff_panel(
        reference, candidate, geometry, title=title,
        legend="< missing  > excess")


def render_stereo_level_diffs(panels, geometry):
    """Frequency-resolved channel-2-minus-channel-1 level difference."""
    output = []
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        title = f"stereo-level-diff: {label}"
        if channel_count >= 2:
            panel = _render_spectral_diff_panel(
                channels[:, 0], channels[:, 1], geometry, title=title,
                legend="< ch2 quieter > louder", scope=scope)
            output.append(TerminalPanel(
                panel.title, panel.rows,
                (*panel.footer, "diagnostic, not verdict"), panel.x_axis))
            continue
        edges = np.geomspace(
            SPEC_LO_HZ, min(SPEC_HI_HZ, RATE / 2), geometry.width + 1)
        axis, marks = ruler(edges, geometry.width)
        footer = (marks, "channel 2-channel 1 dB",
                  "< ch2 quieter > louder", "blank |Δ| <3 dB",
                  "full at ±24 dB", scope, "diagnostic, not verdict")
        output.append(TerminalPanel(
            title, tuple(" " * geometry.width
                         for _ in range(geometry.lines)), footer, axis))
    return output


def render_clicks(events, geometry, *, comparison=False, label=None):
    """Time-aligned click count and severity bars."""
    rows = []
    available = max(1, geometry.width - 4)
    for row in range(geometry.lines):
        low, high = row_interval(geometry, row)
        found = [event for event in events
                 if low <= event["time_seconds"] < high]
        if not found:
            rows.append(" " * geometry.width)
            continue
        severity = max(event["severity_ratio"] for event in found)
        length = max(1, min(available, round(available * min(severity, 64.0) / 64.0)))
        count = str(len(found)) if len(found) < 10 else "+"
        glyph = "█" if geometry.color else "!"
        bar = style(glyph * length, geometry.color, "1;31")
        rows.append(pad(f"!{count:<2}{bar}", geometry.width))
    total = len(events)
    kind = "candidate-only" if comparison else "detected"
    footer = ("!N event count", "bar=max severity", "full bar >=64x",
              f"{total} {kind} event(s)")
    title = f"clicks: {label}" if label else "clicks"
    return TerminalPanel(title, tuple(rows), footer)


def metric_glyph(level, geometry):
    glyphs = ("·", "o", "O", "X")
    glyph = glyphs[max(0, min(level, 3))]
    codes = ("2;32", "33", "1;33", "1;31")
    return style(glyph, geometry.color, codes[max(0, min(level, 3))])


def render_metrics(result, geometry):
    """Worst per-window pitch/level/spectrum/click state in each time row."""
    policy = result.data["policy"]
    windows = result.windows
    click_times = [event.time_seconds
                   for event in result.click_analysis.unmatched_events]
    rows = []
    for row in range(geometry.lines):
        low, high = row_interval(geometry, row)
        selected = [item for item in windows
                    if item.index * WINDOW / RATE < high
                    and (item.index + 1) * WINDOW / RATE > low]
        if not selected:
            rows.append(fit("P:- L:- S:- C:-", geometry.width))
            continue

        pitch_states = [item.pitch_agreed for item in selected]
        if any(value is not None and not bool(value) for value in pitch_states):
            pitch = metric_glyph(3, geometry)
        elif any(value is not None and bool(value) for value in pitch_states):
            pitch = metric_glyph(0, geometry)
        else:
            pitch = "-"

        level_state = 0
        level_min = policy["level"]["median_ratio_minimum"]
        level_max = policy["level"]["median_ratio_maximum"]
        for item in selected:
            if item.reference_rms <= policy["level"]["live_rms_minimum"]:
                continue
            ratio = item.candidate_rms / item.reference_rms
            if ((level_min is not None and ratio < level_min)
                    or (level_max is not None and ratio > level_max)):
                level_state = max(level_state, 3)
            elif not 0.90 <= ratio <= 1.10:
                level_state = max(level_state, 1)
        level = metric_glyph(level_state, geometry)

        median_min = policy["spectrum"]["cosine_median_minimum"]
        p10_min = policy["spectrum"]["cosine_p10_minimum"]
        spectrum_state = 0
        for item in selected:
            cosine = item.spectrum_cosine
            if p10_min is not None and cosine < p10_min:
                spectrum_state = max(spectrum_state, 3)
            elif median_min is not None and cosine < median_min:
                spectrum_state = max(spectrum_state, 2)
            elif cosine < 0.98:
                spectrum_state = max(spectrum_state, 1)
        spectrum_value = metric_glyph(spectrum_state, geometry)

        clicks = sum(low <= when < high for when in click_times)
        click_value = (metric_glyph(0, geometry) if clicks == 0
                       else style("+" if clicks >= 10 else str(clicks),
                                  geometry.color, "1;31"))
        rows.append(pad(
            f"P:{pitch} L:{level} S:{spectrum_value} C:{click_value}",
            geometry.width))
    footer = ("P pitch L level", "S spectrum C click", "· ok  o warning",
              "O bad  X beyond")
    return TerminalPanel(
        f"metrics: {result.data['label']}", tuple(rows), footer)


def render_residual(reference, candidate, geometry, *, label=None):
    """Min/max candidate-minus-reference envelope for each time row."""
    count = min(len(reference), len(candidate))
    residual = np.asarray(candidate[:count], dtype=np.float64) - np.asarray(
        reference[:count], dtype=np.float64)
    amplitude = max(float(np.max(np.abs(residual))) if len(residual) else 0.0, 1.0)
    cuts = np.linspace(0, len(residual), geometry.lines + 1).astype(int)
    rows = []
    for display_row in range(geometry.lines):
        chronological = geometry.lines - display_row - 1
        lo, hi = cuts[chronological], cuts[chronological + 1]
        segment = residual[lo:hi]
        low = float(segment.min()) if len(segment) else 0.0
        high = float(segment.max()) if len(segment) else 0.0
        rows.append(span_row(low, high, amplitude, geometry))
    footer = ("candidate-reference", f"scale ±{amplitude:.0f} PCM")
    title = f"residual: {label}" if label else "residual"
    return TerminalPanel(title, tuple(rows), footer)


def residual_ratio_db(reference, candidate):
    """Residual RMS relative to reference RMS in dB after alignment."""
    count = min(len(reference), len(candidate))
    if count < 2:
        return None
    reference = np.asarray(reference[:count], dtype=np.float64)
    candidate = np.asarray(candidate[:count], dtype=np.float64)
    reference_rms = float(np.sqrt(np.mean(reference * reference)))
    if reference_rms <= np.finfo(np.float64).eps:
        return None
    residual = candidate - reference
    residual_rms = float(np.sqrt(np.mean(residual * residual)))
    if residual_rms <= np.finfo(np.float64).eps:
        return -np.inf
    return 20.0 * np.log10(residual_rms / reference_rms)


def render_residual_ratio(reference, candidate, geometry, *, label=None):
    """Normalized residual severity per row on a fixed dB scale."""
    minimum, maximum = -60.0, 6.0
    count = min(len(reference), len(candidate))
    reference = np.asarray(reference[:count], dtype=np.float64)
    candidate = np.asarray(candidate[:count], dtype=np.float64)
    cuts = np.linspace(0, count, geometry.lines + 1).astype(int)
    chronological = [
        residual_ratio_db(reference[cuts[row]:cuts[row + 1]],
                          candidate[cuts[row]:cuts[row + 1]])
        for row in range(geometry.lines)
    ]
    rows = []
    for display_row in range(geometry.lines):
        value = chronological[geometry.lines - display_row - 1]
        rows.append(
            " " * geometry.width if value is None else
            range_bar_row(value, minimum, maximum, geometry, color_code="35"))
    finite = [value for value in chronological
              if value is not None and np.isfinite(value)]
    median_text = ("finite median n/a" if not finite else
                   f"finite median {np.median(finite):+.2f} dB")
    max_text = ("row max n/a" if not finite else
                f"row max {max(finite):+.2f} dB")
    selected = residual_ratio_db(reference, candidate)
    selected_text = ("whole ratio n/a" if selected is None else
                     f"whole ratio {format_dbfs(selected)} dB")
    footer = ("residual/reference RMS", "fixed -60..+6 dB",
              "0 = equal RMS", "< means ≤-60 dB",
              "blank=ref silent/short", "after alignment",
              "diagnostic, not verdict", median_text, max_text,
              selected_text)
    title = f"residual-ratio: {label}" if label else "residual-ratio"
    return TerminalPanel(title, tuple(rows), footer)


def waveform_correlation(reference, candidate):
    """Mean-removed normalized correlation, or ``None`` for flat input."""
    count = min(len(reference), len(candidate))
    if count < 2:
        return None
    reference = np.asarray(reference[:count], dtype=np.float64)
    candidate = np.asarray(candidate[:count], dtype=np.float64)
    reference = reference - reference.mean()
    candidate = candidate - candidate.mean()
    denominator = float(np.linalg.norm(reference) * np.linalg.norm(candidate))
    if denominator <= np.finfo(np.float64).eps:
        return None
    return float(np.clip(np.dot(reference, candidate) / denominator, -1.0, 1.0))


def render_wave_correlation(reference, candidate, geometry, *, label=None):
    """Signed per-row waveform correlation after comparison alignment."""
    count = min(len(reference), len(candidate))
    reference = np.asarray(reference[:count], dtype=np.float64)
    candidate = np.asarray(candidate[:count], dtype=np.float64)
    cuts = np.linspace(0, count, geometry.lines + 1).astype(int)
    rows = []
    for display_row in range(geometry.lines):
        chronological = geometry.lines - display_row - 1
        lo, hi = cuts[chronological], cuts[chronological + 1]
        value = waveform_correlation(reference[lo:hi], candidate[lo:hi])
        if value is None:
            rows.append(" " * geometry.width)
            continue
        color_code = "32" if value >= 0.95 else "33" if value >= 0.70 else "1;31"
        rows.append(span_row(
            value, value, 1.0, geometry, color_code=color_code))
    selected = waveform_correlation(reference, candidate)
    selected_text = ("selected corr n/a" if selected is None
                     else f"selected corr {selected:+.3f}")
    footer = ("Pearson corr per row", "fixed scale -1..+1",
              "+1 same  0 unrelated", "-1 polarity inverted",
              "green ≥.95 yellow ≥.70", "red <.70; diagnostic",
              selected_text)
    title = f"wave-correlation: {label}" if label else "wave-correlation"
    return TerminalPanel(title, tuple(rows), footer)


def render_stereo_correlations(panels, geometry):
    """Signed channel-1/channel-2 correlation for each original input.

    This deliberately consumes decoded channel context rather than the mono
    analysis signal.  It is presentation-only: callers retain their existing
    mono analysis, verdict, and machine-output contracts.
    """
    output = []
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]

        if channel_count >= 2:
            cuts = np.linspace(0, len(channels), geometry.lines + 1).astype(int)
            chronological = [
                waveform_correlation(channels[cuts[row]:cuts[row + 1], 0],
                                     channels[cuts[row]:cuts[row + 1], 1])
                for row in range(geometry.lines)
            ]
            values = chronological
            rows = []
            for display_row in range(geometry.lines):
                value = chronological[geometry.lines - display_row - 1]
                if value is None:
                    rows.append(" " * geometry.width)
                    continue
                color_code = ("32" if value >= 0.95 else
                              "33" if value >= 0 else "1;31")
                rows.append(span_row(
                    value, value, 1.0, geometry, color_code=color_code))
        else:
            rows = [" " * geometry.width for _ in range(geometry.lines)]

        selected = (None if channel_count < 2 else
                    waveform_correlation(channels[:, 0], channels[:, 1]))
        selected_text = ("selected corr n/a" if selected is None else
                         f"selected corr {selected:+.3f}")
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        footer = ("L/R Pearson per row", "fixed scale -1..+1",
                  "+1 in-phase 0 decorrelated", "-1 anti-phase; mono cancels",
                  "flat channels blank", scope,
                  "diagnostic, not verdict", selected_text)
        output.append(TerminalPanel(
            f"stereo-correlation: {label}", tuple(rows), footer))
    return output


def stereo_balance_db(left, right):
    """Return ``20*log10(RMS(right)/RMS(left))`` or ``None`` for silence."""
    count = min(len(left), len(right))
    if count < 1:
        return None
    left = np.asarray(left[:count], dtype=np.float64)
    right = np.asarray(right[:count], dtype=np.float64)
    left_rms = float(np.sqrt(np.mean(left * left)))
    right_rms = float(np.sqrt(np.mean(right * right)))
    epsilon = np.finfo(np.float64).eps
    if left_rms <= epsilon and right_rms <= epsilon:
        return None
    if left_rms <= epsilon:
        return np.inf
    if right_rms <= epsilon:
        return -np.inf
    return float(20.0 * np.log10(right_rms / left_rms))


def render_stereo_balances(panels, geometry):
    """Signed original-channel RMS balance on a fixed -24..+24 dB scale."""
    output = []
    scale = 24.0
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]

        if channel_count >= 2:
            cuts = np.linspace(0, len(channels), geometry.lines + 1).astype(int)
            chronological = [
                stereo_balance_db(channels[cuts[row]:cuts[row + 1], 0],
                                  channels[cuts[row]:cuts[row + 1], 1])
                for row in range(geometry.lines)
            ]
            rows = []
            for display_row in range(geometry.lines):
                value = chronological[geometry.lines - display_row - 1]
                if value is None:
                    rows.append(" " * geometry.width)
                    continue
                color_code = "1;31" if not np.isfinite(value) else "36"
                rows.append(span_row(
                    value, value, scale, geometry, color_code=color_code))
        else:
            rows = [" " * geometry.width for _ in range(geometry.lines)]

        selected = (None if channel_count < 2 else
                    stereo_balance_db(channels[:, 0], channels[:, 1]))
        if selected is None:
            selected_text = "selected balance n/a"
        elif not np.isfinite(selected):
            selected_text = ("selected balance +inf dB" if selected > 0 else
                             "selected balance -inf dB")
        else:
            selected_text = f"selected balance {selected:+.2f} dB"
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        footer = ("R/L RMS per row", "fixed -24..+24 dB",
                  "left=L louder right=R louder",
                  "one-sided silence red/edge", "both silent blank", scope,
                  "diagnostic, not verdict", selected_text)
        output.append(TerminalPanel(
            f"stereo-balance: {label}", tuple(rows), footer))
    return output


def stereo_delay_observation(left, right, *, max_lag=STEREO_DELAY_MAX_SAMPLES):
    """Find a unique strongest absolute Pearson lag, or ``None`` for flat data.

    Positive lag means channel 2 occurs later than channel 1. Confidence is the
    absolute-correlation margin over the next strongest local peak, which makes
    periodic ambiguity observable instead of silently choosing one period.
    """
    count = min(len(left), len(right))
    if count < max_lag + 2:
        return None
    left = np.asarray(left[:count], dtype=np.float64)
    right = np.asarray(right[:count], dtype=np.float64)
    lags = np.arange(-max_lag, max_lag + 1)
    correlations = []
    for lag in lags:
        if lag > 0:
            value = waveform_correlation(left[:-lag], right[lag:])
        elif lag < 0:
            value = waveform_correlation(left[-lag:], right[:lag])
        else:
            value = waveform_correlation(left, right)
        correlations.append(value)
    if all(value is None for value in correlations):
        return None
    magnitudes = np.array([
        -np.inf if value is None else abs(value) for value in correlations
    ])
    local_peaks = [
        index for index, value in enumerate(magnitudes)
        if np.isfinite(value)
        and (index == 0 or value >= magnitudes[index - 1])
        and (index + 1 == len(magnitudes) or value >= magnitudes[index + 1])
    ]
    if not local_peaks:
        return None
    ordered = sorted(local_peaks, key=lambda index: magnitudes[index],
                     reverse=True)
    best = ordered[0]
    runner_up = magnitudes[ordered[1]] if len(ordered) > 1 else 0.0
    return StereoDelayObservation(
        int(lags[best]), float(magnitudes[best]),
        float(magnitudes[best] - runner_up))


def render_stereo_delays(panels, geometry):
    """Unique inter-channel delay on a fixed signed +/-5 ms scale."""
    output = []
    max_lag = STEREO_DELAY_MAX_SAMPLES
    for label, channel_samples in panels:
        if channel_samples is None:
            channels = None
            channel_count = 0
        else:
            channels = np.asarray(channel_samples, dtype=np.float64)
            if channels.ndim == 1:
                channels = channels[:, None]
            channel_count = channels.shape[1]

        if channel_count >= 2:
            cuts = np.linspace(0, len(channels), geometry.lines + 1).astype(int)
            chronological = [
                stereo_delay_observation(
                    channels[cuts[row]:cuts[row + 1], 0],
                    channels[cuts[row]:cuts[row + 1], 1])
                for row in range(geometry.lines)
            ]
            rows = []
            for display_row in range(geometry.lines):
                value = chronological[geometry.lines - display_row - 1]
                if value is None or not value.accepted:
                    rows.append(" " * geometry.width)
                    continue
                color_code = ("1;31" if abs(value.lag_samples) == max_lag
                              else "36")
                rows.append(span_row(
                    value.lag_samples, value.lag_samples, max_lag, geometry,
                    color_code=color_code))
        else:
            rows = [" " * geometry.width for _ in range(geometry.lines)]

        selected = (None if channel_count < 2 else
                    stereo_delay_observation(channels[:, 0], channels[:, 1]))
        if selected is None:
            selected_text = ("selected delay n/a",)
        elif not selected.accepted:
            selected_text = (
                "selected delay ambiguous",
                f"selected |corr| {selected.peak_correlation:.3f}",
                f"selected margin {selected.peak_margin:.3f}",
            )
        else:
            milliseconds = selected.lag_samples / RATE * 1000.0
            selected_text = (
                f"selected delay {milliseconds:+.3f} ms",
                f"selected |corr| {selected.peak_correlation:.3f}",
                f"selected margin {selected.peak_margin:.3f}",
            )
        if channel_samples is None:
            scope = "not available: no channel context"
        elif channel_count == 1:
            scope = "not applicable: mono"
        elif channel_count == 2:
            scope = "channels 1/2"
        else:
            scope = f"using channels 1/2 of {channel_count}"
        footer = ("best |Pearson| lag/row", "fixed -5..+5 ms",
                  "left=ch1 later right=ch2 later",
                  "require |corr| >=0.50", "peak margin >=0.05",
                  "periodic/flat rows blank", "red edge=at/beyond 5 ms",
                  scope, "diagnostic, not verdict", *selected_text)
        output.append(TerminalPanel(
            f"stereo-delay: {label}", tuple(rows), footer))
    return output


def render_block_repeats(panels, geometry):
    """Correlation of each displayed time block with its immediate predecessor."""
    output = []
    for label, samples in panels:
        values = np.asarray(samples, dtype=np.float64)
        cuts = np.linspace(0, len(values), geometry.lines + 1).astype(int)
        chronological = [None]
        for row in range(1, geometry.lines):
            previous = values[cuts[row - 1]:cuts[row]]
            current = values[cuts[row]:cuts[row + 1]]
            chronological.append(waveform_correlation(previous, current))
        rows = []
        for display_row in range(geometry.lines):
            value = chronological[geometry.lines - display_row - 1]
            rows.append(
                " " * geometry.width if value is None else
                span_row(value, value, 1.0, geometry))
        observed = [value for value in chronological if value is not None]
        median_text = ("row median n/a" if not observed else
                       f"row median {np.median(observed):+.3f}")
        maximum_text = ("row max |corr| n/a" if not observed else
                        f"row max |corr| {max(abs(value) for value in observed):.3f}")
        footer = ("current vs prior row", "Pearson fixed -1..+1",
                  "+1 same  0 unrelated", "-1 inverted repeat",
                  "first/flat rows blank", "depends on row geometry",
                  "diagnostic, not verdict", median_text, maximum_text)
        output.append(TerminalPanel(
            f"block-repeat: {label}", tuple(rows), footer))
    return output


def render_inspection(views, label, samples, clicks, geometry, *,
                      channel_samples=None):
    panels = []
    for view in views:
        if view == "spectrogram":
            panels.extend(render_spectrograms([(label, samples)], geometry))
        elif view == "low-frequency-spectrum":
            panels.extend(render_low_frequency_spectra(
                [(label, samples)], geometry))
        elif view == "modulation-spectrum":
            panels.extend(render_modulation_spectra(
                [(label, samples)], geometry))
        elif view == "pitch-track":
            panels.extend(render_pitch_tracks([(label, samples)], geometry))
        elif view == "waveform":
            panels.extend(render_waveforms([(label, samples)], geometry))
        elif view == "intersample-peak":
            panels.extend(render_intersample_peaks([(label, samples)], geometry))
        elif view == "rms-level":
            panels.extend(render_rms_levels([(label, samples)], geometry))
        elif view == "rail-ratio":
            panels.extend(render_rail_ratios([(label, samples)], geometry))
        elif view == "peak-occupancy":
            panels.extend(render_peak_occupancy([(label, samples)], geometry))
        elif view == "quantization-step":
            panels.extend(render_quantization_steps([(label, samples)], geometry))
        elif view == "flatline-ratio":
            panels.extend(render_flatline_ratios([(label, samples)], geometry))
        elif view == "block-repeat":
            panels.extend(render_block_repeats([(label, samples)], geometry))
        elif view == "crest-factor":
            panels.extend(render_crest_factors([(label, samples)], geometry))
        elif view == "derivative-ratio":
            panels.extend(render_derivative_ratios([(label, samples)], geometry))
        elif view == "spectral-change":
            panels.extend(render_spectral_changes([(label, samples)], geometry))
        elif view == "spectral-centroid":
            panels.extend(render_spectral_centroids([(label, samples)], geometry))
        elif view == "spectral-flatness":
            panels.extend(render_spectral_flatness([(label, samples)], geometry))
        elif view == "sample-density":
            panels.extend(render_sample_density([(label, samples)], geometry))
        elif view == "dc-offset":
            panels.extend(render_dc_offsets([(label, samples)], geometry))
        elif view == "stereo-correlation":
            panels.extend(render_stereo_correlations(
                [(label, channel_samples)], geometry))
        elif view == "stereo-balance":
            panels.extend(render_stereo_balances(
                [(label, channel_samples)], geometry))
        elif view == "stereo-level-diff":
            panels.extend(render_stereo_level_diffs(
                [(label, channel_samples)], geometry))
        elif view == "stereo-delay":
            panels.extend(render_stereo_delays(
                [(label, channel_samples)], geometry))
        elif view == "stereo-phase":
            panels.extend(render_stereo_phases(
                [(label, channel_samples)], geometry))
        elif view == "stereo-coherence":
            panels.extend(render_stereo_coherences(
                [(label, channel_samples)], geometry))
        elif view == "clicks":
            panels.append(render_clicks(
                [event.as_dict() for event in clicks.events], geometry,
                label=label))
    suffix = f": {label}"
    panels = [TerminalPanel(
        panel.title[:-len(suffix)] if panel.title.endswith(suffix)
        else panel.title,
        panel.rows, panel.footer, panel.x_axis)
        for panel in panels]
    return [f"view input: {label}", *compose(panels, geometry)]


def render_comparison(views, result, reference_label, geometry, *,
                      channel_panels=None):
    if channel_panels is None:
        channel_panels = ((reference_label, None),
                          (result.data["label"], None))
    panels = []
    for view in views:
        if view == "spectrogram":
            panels.extend(render_spectrograms(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "low-frequency-spectrum":
            panels.extend(render_low_frequency_spectra(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "modulation-spectrum":
            panels.extend(render_modulation_spectra(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "pitch-track":
            panels.extend(render_pitch_tracks(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "waveform":
            panels.extend(render_waveforms(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "intersample-peak":
            panels.extend(render_intersample_peaks(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "rms-level":
            panels.extend(render_rms_levels(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "rail-ratio":
            panels.extend(render_rail_ratios(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "peak-occupancy":
            panels.extend(render_peak_occupancy(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "quantization-step":
            panels.extend(render_quantization_steps(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "flatline-ratio":
            panels.extend(render_flatline_ratios(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "block-repeat":
            panels.extend(render_block_repeats(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "crest-factor":
            panels.extend(render_crest_factors(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "derivative-ratio":
            panels.extend(render_derivative_ratios(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "spectral-change":
            panels.extend(render_spectral_changes(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "spectral-centroid":
            panels.extend(render_spectral_centroids(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "spectral-flatness":
            panels.extend(render_spectral_flatness(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "sample-density":
            panels.extend(render_sample_density(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "dc-offset":
            panels.extend(render_dc_offsets(
                [(reference_label, result.reference),
                 (result.data["label"], result.shifted_candidate)], geometry))
        elif view == "stereo-correlation":
            panels.extend(render_stereo_correlations(channel_panels, geometry))
        elif view == "stereo-balance":
            panels.extend(render_stereo_balances(channel_panels, geometry))
        elif view == "stereo-level-diff":
            panels.extend(render_stereo_level_diffs(channel_panels, geometry))
        elif view == "stereo-delay":
            panels.extend(render_stereo_delays(channel_panels, geometry))
        elif view == "stereo-phase":
            panels.extend(render_stereo_phases(channel_panels, geometry))
        elif view == "stereo-coherence":
            panels.extend(render_stereo_coherences(channel_panels, geometry))
        elif view == "wave-correlation":
            panels.append(render_wave_correlation(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
        elif view == "metrics":
            panels.append(render_metrics(result, geometry))
        elif view == "level-delta":
            panels.append(render_level_delta(result, geometry))
        elif view == "pitch-delta":
            panels.append(render_pitch_delta(result, geometry))
        elif view == "timing-drift":
            panels.append(render_timing_drift(result, geometry))
        elif view == "contour":
            panels.extend(render_contour(result, geometry))
        elif view == "band-delta":
            panels.append(render_band_delta(result, geometry))
        elif view == "spectral-diff":
            panels.append(render_spectral_diff(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
        elif view == "phase-diff":
            panels.append(render_phase_diff(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
        elif view == "spectral-coherence":
            panels.append(render_spectral_coherence(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
        elif view == "clicks":
            panels.append(render_clicks(
                [event.as_dict()
                 for event in result.click_analysis.unmatched_events],
                geometry, comparison=True, label=result.data["label"]))
        elif view == "residual":
            panels.append(render_residual(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
        elif view == "residual-ratio":
            panels.append(render_residual_ratio(
                result.reference, result.shifted_candidate, geometry,
                label=result.data["label"]))
    context = f"view comparison: {result.data['label']} vs {reference_label}"
    return [context, *compose(panels, geometry)]
