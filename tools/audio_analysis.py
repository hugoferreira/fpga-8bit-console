#!/usr/bin/env python3
"""Unified WAV analysis for interactive diagnosis and regression gates.

This is both the repository's audio-analysis command and its reusable signal
analysis module. Keep WAV decoding, pitch/RMS/spectrum measurements, alignment,
comparison thresholds, spectrograms, and cart-aware SFX inspection here. Tools
which render or record audio remain separate and import this module to analyse
their result.

``wav compare`` aligns one or more candidate renders with a reference and reports
independent pitch, level, spectral-shape, absolute-band, and timing-lock
measurements. PICO-8 starts recording before ``music()``, while the RTL render
starts on sample zero, so alignment is part of the analysis rather than a
silent adjustment.

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
  clicks    isolated PCM discontinuities after suppressing periodic square,
            pulse, and saw edges. In comparison mode only candidate events not
            matched by a reference event are artifacts.
The default ``full-track-v2`` policy requires every applicable measurement to
pass, including zero unmatched candidate clicks. The numeric score is only
pitch agreement or contour correlation; it is not a substitute for the result
status. ``full-track-v1`` and ``pitch-band-v1`` are explicit compatibility
profiles, never implicit fallbacks.
On an UNPITCHED reference (noise, percussion) pitch and lock cannot succeed even
for a perfect render, so they are withheld and contour is reported instead.

``--spectrogram`` adds the picture those numbers summarise: panels drawn side by
side, same axes, same dB scale, so a missing voice or a wrong harmonic series is
visible rather than inferred from a cosine. Frequency runs across and time runs
UP, so the same instant sits at the same height in every panel and a note is a
horizontal bar you can follow from one to the next; a long track then costs
lines, which a terminal has, rather than columns, which it does not.
``--spectrogram-file`` writes the same panels at full STFT resolution,
which is where vibrato and one-frame dropouts show up.

``--view`` selects independent terminal panels. ``spectrogram``,
``low-frequency-spectrum``,
``modulation-spectrum``,
``pitch-track``, ``waveform``, ``intersample-peak``,
``rms-level``, ``rail-ratio``, ``peak-occupancy``, ``quantization-step``,
``flatline-ratio``,
``block-repeat``, ``crest-factor``, ``derivative-ratio``,
``spectral-change``, ``spectral-centroid``, ``spectral-flatness``,
``sample-density``, ``dc-offset``,
``stereo-balance``, ``stereo-level-diff``, ``stereo-correlation``, ``stereo-delay``,
``stereo-phase``, ``stereo-coherence``, and ``clicks``
apply to inspection;
comparisons additionally offer ``metrics``, ``level-delta``, ``pitch-delta``,
``timing-drift``, ``contour``, ``band-delta``, ``spectral-diff``,
``phase-diff``, ``spectral-coherence``, ``wave-correlation``,
``residual-ratio``, and ``residual``.
Repeating the option and choosing a row
or column layout composes the unchanged panels on one newest-at-top time grid.
Width, time density, range, axis placement, and colour policy are explicit CLI
inputs rather than hidden terminal-size heuristics.

``wav inspect`` reports one WAV, applies the standalone ``click-v1`` gate, and
draws a spectrogram only when explicitly requested. ``-`` reads a WAV from
stdin.

``sfx analyze`` annotates one render with the source cart's 32 note rows and
applies the same click gate. It combines the former row-energy and note-pitch
tools into one table, while withholding a pitch verdict for noise and
pitch-changing effects where a single fundamental does not describe the
requested sound.

Human, strict JSON, and quiet result modes are available. Exit status 0 means
success, 1 an analysis/general failure, 2 invalid input, 3 a missing resource,
and 4 permission denied.

Usage:
  audio_analysis.py wav compare ref.wav cand.wav
  audio_analysis.py wav compare ref.wav cand.wav --spectrogram
  audio_analysis.py wav compare ref.wav hw.wav pv.wav --labels hardware,preview
  audio_analysis.py --output json wav inspect one.wav
  build/obj_dir/console --audio-wav - | audio_analysis.py wav inspect -
  audio_analysis.py sfx analyze render.wav --cart game.p8.png --sfx 8
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import sys
import wave
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np

from _audio_analysis_policy import (
    CLICK_V1,
    ClickPolicy,
    ComparisonPolicy,
    DEFAULT_POLICY,
    click_policy,
    comparison_policy,
    comparison_profile_names,
)

# Private presentation modules import the public facade. When this file is run
# directly, publish the already-loading module under that facade name so Python
# does not execute the signal core a second time.
if __name__ == "__main__":
    sys.modules.setdefault("audio_analysis", sys.modules[__name__])

SCHEMA_VERSION = 2
EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2
EXIT_NOT_FOUND = 3
EXIT_PERMISSION = 4

RATE = 22050
WINDOW = 2205           # 0.1 s at RATE
VOICED = 0.30           # normalised autocorrelation floor for "has a pitch"
TOLERANCE = 1.0         # semitones
LO_HZ, HI_HZ = 70.0, 1200.0
SAMPLES_PER_TICK = 183  # PICO-8 audio sequencer at 22050 / 183 ~= 120.49 Hz
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
LOCK_BLOCK = RATE // 2

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


class CliUsageError(Exception):
    """An argparse failure which the caller can render as JSON."""


class OptionalDependencyError(RuntimeError):
    """A requested presentation needs an unavailable optional package."""


class CliFailure(Exception):
    """Stable agent-facing failure independent of presentation mode."""

    def __init__(self, error, message, *, exit_code=EXIT_FAILURE,
                 retryable=False, suggestion=None, field=None, value=None):
        super().__init__(message)
        self.error = error
        self.message = message
        self.exit_code = exit_code
        self.retryable = retryable
        self.suggestion = suggestion
        self.field = field
        self.value = value

    def as_dict(self, command):
        result = {
            "schema_version": SCHEMA_VERSION,
            "command": command,
            "status": "error",
            "error": self.error,
            "message": self.message,
            "retryable": self.retryable,
        }
        if self.field is not None:
            result["field"] = self.field
        if self.value is not None:
            result["value"] = str(self.value)
        if self.suggestion is not None:
            result["suggestion"] = self.suggestion
        return result


class AgentArgumentParser(argparse.ArgumentParser):
    """Argument parser whose errors remain available to structured output."""

    def __init__(self, *args, **kwargs):
        kwargs.setdefault("formatter_class", argparse.RawDescriptionHelpFormatter)
        super().__init__(*args, **kwargs)

    def error(self, message):
        raise CliUsageError(message)


def json_safe(value):
    """Convert NumPy and non-finite values to strict JSON-compatible values."""
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    if isinstance(value, np.generic):
        value = value.item()
    if isinstance(value, float) and not np.isfinite(value):
        return None
    return value


def emit_json(value, *, out=sys.stdout):
    """Emit exactly one strict JSON value and one trailing newline."""
    print(json.dumps(json_safe(value), sort_keys=True, separators=(",", ":"),
                     allow_nan=False), file=out)


def sha256_bytes(content: bytes) -> str:
    """Return the lowercase SHA-256 digest used by every audio manifest."""
    return hashlib.sha256(content).hexdigest()


def sha256_file(path) -> str:
    """Fingerprint one file without attaching path or timestamp semantics."""
    sha = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def wav_summary(path, samples, *, source_sha256=None):
    """Stable metadata shared by human and structured command results."""
    return {
        "path": "-" if str(path) == "-" else str(Path(path)),
        "label": display_name(path),
        "source_sha256": source_sha256,
        "sample_rate_hz": RATE,
        "sample_count": len(samples),
        "duration_seconds": len(samples) / RATE,
        "peak": float(np.max(np.abs(samples))) if len(samples) else 0.0,
        "rms": rms(samples),
    }


# ----------------------------------------------------------------- input ----


@dataclass(frozen=True)
class LoadedAudio:
    """Mono analysis samples, original channels, and exact source identity."""

    path: str
    samples: np.ndarray
    source_sha256: str
    channel_samples: np.ndarray

    @property
    def channel_count(self):
        return self.channel_samples.shape[1]


def load_audio(path, *, expected_rate=RATE) -> LoadedAudio:
    """Load WAV samples and retain a SHA-256 of the exact input bytes.

    Multi-channel input is mixed down by averaging channels. 8-bit unsigned PCM
    is centered and scaled by 256 so all decoded samples use signed 16-bit
    amplitude units. ``-`` reads stdin exactly once and fingerprints the
    buffered bytes. Analysis in this
    repository is calibrated at 22050 Hz, so the default rejects any other
    rate rather than silently applying the wrong frequency scale.
    """
    content = (sys.stdin.buffer.read() if str(path) == "-"
               else Path(path).read_bytes())
    with wave.open(io.BytesIO(content)) as w:
        width = w.getsampwidth()
        channels = w.getnchannels()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 1:
        # Normalize 8-bit unsigned PCM onto the same signed 16-bit amplitude
        # scale used by every threshold. Without this, a click policy expressed
        # in PCM units would silently become 256x less sensitive on 8-bit WAVs.
        pcm = ((np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0)
               * 256.0)
    elif width == 2:
        pcm = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    else:
        raise ValueError(f"{path}: expected 8- or 16-bit PCM, got {width * 8}-bit")
    channel_samples = pcm.reshape(-1, channels)
    samples = (channel_samples.mean(axis=1) if channels > 1
               else channel_samples[:, 0])
    if expected_rate is not None and rate != expected_rate:
        raise ValueError(f"{path}: {rate} Hz, expected {expected_rate}")
    return LoadedAudio("-" if str(path) == "-" else str(Path(path)), samples,
                       sha256_bytes(content), channel_samples)


def load_wav(path, *, expected_rate=RATE):
    """Load 8- or 16-bit PCM as a mono float64 NumPy array.

    Multi-channel input is mixed down by averaging channels. 8-bit unsigned PCM
    is centered and scaled by 256 to the signed 16-bit amplitude scale. ``-`` reads stdin,
    buffered first because :mod:`wave` seeks and a pipe does not. Analysis in
    this repository is calibrated at 22050 Hz, so the default rejects any other
    rate rather than silently applying the wrong frequency scale; pass
    ``expected_rate=None`` only when the caller will not apply any
    sample-rate-dependent metric.
    """
    return load_audio(path, expected_rate=expected_rate).samples


def load_pcm16_mono(path, *, expected_rate=RATE):
    """Load exact signed PCM samples without mixing or float conversion.

    Byte-exact oracle/model comparisons use this stricter boundary. It belongs
    here so those domain-specific gates do not each grow another WAV decoder.
    ``-`` is supported with the same explicit stdin semantics as :func:`load_wav`.
    """
    content = (sys.stdin.buffer.read() if str(path) == "-"
               else Path(path).read_bytes())
    with wave.open(io.BytesIO(content)) as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        if channels != 1 or width != 2:
            raise ValueError(
                f"{path}: expected mono 16-bit PCM, got "
                f"{channels} channel(s), {width * 8}-bit")
        if expected_rate is not None and rate != expected_rate:
            raise ValueError(f"{path}: {rate} Hz, expected {expected_rate}")
        raw = wav.readframes(wav.getnframes())
    return np.frombuffer(raw, dtype="<i2").copy()


def display_name(path):
    return "stdin" if str(path) == "-" else Path(path).name


def rms(samples):
    """Root-mean-square level, or zero for an empty sequence."""
    samples = np.asarray(samples, dtype=np.float64)
    return float(np.sqrt(np.mean(samples ** 2))) if len(samples) else 0.0


# --------------------------------------------------------------- clicks ----

@dataclass(frozen=True)
class ClickEvent:
    """One isolated adjacent-sample discontinuity on the input timebase."""

    sample_index: int
    time_seconds: float
    delta_pcm: float
    local_derivative_rms_pcm: float
    severity_ratio: float

    def as_dict(self) -> dict:
        return {
            "sample_index": self.sample_index,
            "time_seconds": self.time_seconds,
            "delta_pcm": self.delta_pcm,
            "local_derivative_rms_pcm": self.local_derivative_rms_pcm,
            "severity_ratio": self.severity_ratio,
        }


@dataclass(frozen=True)
class ClickAnalysis:
    """Pure sparse-discontinuity analysis, including suppression accounting."""

    policy: ClickPolicy
    sample_rate_hz: int
    analyzed_delta_count: int
    candidate_edge_count: int
    suppressed_periodic_edge_count: int
    events: tuple[ClickEvent, ...]

    @property
    def event_count(self) -> int:
        return len(self.events)

    @property
    def passed(self) -> bool:
        return self.event_count <= self.policy.standalone_maximum_events

    def as_dict(self) -> dict:
        maximum = self.policy.maximum_reported_events
        reported = self.events[:maximum]
        return {
            "policy": self.policy.as_dict(),
            "sample_rate_hz": self.sample_rate_hz,
            "analyzed_delta_count": self.analyzed_delta_count,
            "candidate_edge_count": self.candidate_edge_count,
            "suppressed_periodic_edge_count":
                self.suppressed_periodic_edge_count,
            "event_count": self.event_count,
            "reported_event_count": len(reported),
            "events_truncated": len(reported) < self.event_count,
            "max_severity_ratio": (
                max(event.severity_ratio for event in self.events)
                if self.events else None),
            "events": [event.as_dict() for event in reported],
        }


@dataclass(frozen=True)
class ClickComparison:
    """Reference-aware click result on one shared, already-aligned timebase."""

    reference: ClickAnalysis
    candidate: ClickAnalysis
    match_tolerance_samples: int
    maximum_unmatched_events: int | None
    matched_event_count: int
    unmatched_events: tuple[ClickEvent, ...]

    @property
    def unmatched_event_count(self) -> int:
        return len(self.unmatched_events)

    @property
    def passed(self) -> bool:
        return (self.maximum_unmatched_events is None
                or self.unmatched_event_count <= self.maximum_unmatched_events)

    def as_dict(self) -> dict:
        maximum = self.candidate.policy.maximum_reported_events
        reported = self.unmatched_events[:maximum]
        return {
            "reference": self.reference.as_dict(),
            "candidate": self.candidate.as_dict(),
            "match_tolerance_samples": self.match_tolerance_samples,
            "maximum_unmatched_events": self.maximum_unmatched_events,
            "matched_event_count": self.matched_event_count,
            "unmatched_event_count": self.unmatched_event_count,
            "reported_unmatched_event_count": len(reported),
            "unmatched_events_truncated":
                len(reported) < self.unmatched_event_count,
            "unmatched_events": [event.as_dict() for event in reported],
        }


def _cluster_click_events(events, maximum_gap):
    """Collapse a multi-sample impulse or step into its strongest edge."""
    groups = []
    for event in events:
        if (groups
                and event.sample_index - groups[-1][-1].sample_index
                <= maximum_gap):
            groups[-1].append(event)
        else:
            groups.append([event])
    return [max(group, key=lambda event: event.severity_ratio)
            for group in groups]


def _is_periodic_waveform_edge(deltas, event, policy):
    """Return true for a local train of similar square/pulse/saw edges."""
    required = policy.periodic_edge_minimum_events
    maximum_gap = policy.periodic_edge_max_gap_samples
    radius = maximum_gap * max(required - 1, 1) + policy.cluster_gap_samples
    derivative_index = event.sample_index - 1
    lo = max(0, derivative_index - radius)
    hi = min(len(deltas), derivative_index + radius + 1)
    threshold = max(
        policy.minimum_delta_pcm,
        abs(event.delta_pcm) * policy.periodic_edge_similarity_ratio)
    nearby = np.flatnonzero(np.abs(deltas[lo:hi]) >= threshold) + lo
    if len(nearby) < required:
        return False

    groups = []
    for index in nearby:
        sample_index = int(index) + 1
        if groups and sample_index - groups[-1][-1] <= policy.cluster_gap_samples:
            groups[-1].append(sample_index)
        else:
            groups.append([sample_index])
    spikes = [max(group, key=lambda sample: abs(deltas[sample - 1]))
              for group in groups]
    if len(spikes) < required:
        return False
    nearest = min(range(len(spikes)),
                  key=lambda index: abs(spikes[index] - event.sample_index))
    start = nearest
    while start > 0 and spikes[start] - spikes[start - 1] <= maximum_gap:
        start -= 1
    stop = nearest + 1
    while stop < len(spikes) and spikes[stop] - spikes[stop - 1] <= maximum_gap:
        stop += 1
    return stop - start >= required


def analyze_clicks(samples, *, rate=RATE, policy=None) -> ClickAnalysis:
    """Detect sparse clicks without mistaking periodic oscillator edges.

    Samples must use signed PCM amplitude units (normally the float64 values
    returned by :func:`load_wav`). A candidate edge must exceed both an absolute
    adjacent-sample delta and a ratio to surrounding derivative RMS. Adjacent
    candidates are clustered, then a local train of similar edges no more than
    ``periodic_edge_max_gap_samples`` apart is classified as waveform structure
    and suppressed. The complete versioned policy is returned with the result.
    """
    selected = click_policy(policy)
    if rate <= 0:
        raise ValueError("click-analysis sample rate must be positive")
    samples = np.asarray(samples, dtype=np.float64)
    if samples.ndim != 1:
        raise ValueError("click analysis expects a one-dimensional sample array")
    deltas = np.diff(samples)
    count = len(deltas)
    if count == 0:
        return ClickAnalysis(selected, int(rate), 0, 0, 0, ())

    indices = np.arange(count)
    squared_prefix = np.concatenate(([0.0], np.cumsum(deltas * deltas)))
    left_start = np.maximum(0, indices - selected.context_radius_samples)
    left_stop = np.maximum(0, indices - selected.guard_radius_samples)
    right_start = np.minimum(count, indices + selected.guard_radius_samples + 1)
    right_stop = np.minimum(count, indices + selected.context_radius_samples + 1)
    context_power = (
        squared_prefix[left_stop] - squared_prefix[left_start]
        + squared_prefix[right_stop] - squared_prefix[right_start])
    context_count = ((left_stop - left_start) + (right_stop - right_start))
    local_rms = np.sqrt(context_power / np.maximum(context_count, 1))
    denominator = np.maximum(
        local_rms, selected.local_derivative_rms_floor_pcm)
    severity = np.abs(deltas) / denominator
    candidate_indices = np.flatnonzero(
        (np.abs(deltas) >= selected.minimum_delta_pcm)
        & (severity >= selected.minimum_severity_ratio))
    candidates = [ClickEvent(
        sample_index=int(index) + 1,
        time_seconds=(int(index) + 1) / rate,
        delta_pcm=float(deltas[index]),
        local_derivative_rms_pcm=float(local_rms[index]),
        severity_ratio=float(severity[index]),
    ) for index in candidate_indices]
    clustered = _cluster_click_events(candidates, selected.cluster_gap_samples)
    events = tuple(event for event in clustered
                   if not _is_periodic_waveform_edge(deltas, event, selected))
    return ClickAnalysis(
        selected, int(rate), count, len(clustered), len(clustered) - len(events),
        events)


def compare_clicks(reference, candidate, *, rate=RATE, policy=None,
                   match_tolerance_samples=8,
                   maximum_unmatched_events=None) -> ClickComparison:
    """Compare click events on a shared timebase without recomputing alignment."""
    if match_tolerance_samples < 0:
        raise ValueError("click match tolerance must be non-negative")
    reference_result = analyze_clicks(reference, rate=rate, policy=policy)
    candidate_result = analyze_clicks(candidate, rate=rate, policy=policy)
    unused_reference = set(range(reference_result.event_count))
    unmatched = []
    matched = 0
    for event in candidate_result.events:
        choices = [
            (abs(event.sample_index - reference_result.events[index].sample_index),
             index)
            for index in unused_reference
            if abs(event.sample_index - reference_result.events[index].sample_index)
            <= match_tolerance_samples
        ]
        if choices:
            _, selected_index = min(choices)
            unused_reference.remove(selected_index)
            matched += 1
        else:
            unmatched.append(event)
    return ClickComparison(
        reference_result, candidate_result, match_tolerance_samples,
        maximum_unmatched_events, matched, tuple(unmatched))


def describe_wav(path, samples, indent="", *, out=sys.stdout):
    """Print the compact duration/peak/RMS description used by every CLI."""
    peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
    print(f"{indent}{path}: {len(samples) / RATE:.2f}s, "
          f"peak {peak:.0f}, rms {rms(samples):.0f}", file=out)


def spectral_centroid(samples, *, rate=RATE, remove_dc=True):
    """Magnitude-weighted spectral centroid in Hz.

    DC is removed by default. Pass ``remove_dc=False`` only for a metric whose
    established baseline intentionally includes recorder offset.
    """
    samples = np.asarray(samples, dtype=np.float64)
    if len(samples) < 2:
        return 0.0
    signal = samples - samples.mean() if remove_dc else samples
    magnitude = np.abs(np.fft.rfft(signal * np.hanning(len(signal))))
    frequencies = np.fft.rfftfreq(len(signal), 1 / rate)
    return float((magnitude * frequencies).sum() / max(magnitude.sum(), 1e-9))


def repeat_rate(samples):
    """Share of adjacent samples that are equal; zero for fewer than two."""
    samples = np.asarray(samples)
    return float(np.mean(np.diff(samples) == 0)) if len(samples) > 1 else 0.0


def high_frequency_power_share(samples, cutoff_hz, *, rate=RATE):
    """Share of Hann-windowed AC power at or above ``cutoff_hz``."""
    samples = np.asarray(samples, dtype=np.float64)
    if len(samples) < 2:
        return 0.0
    centred = samples - samples.mean()
    power = np.abs(np.fft.rfft(centred * np.hanning(len(centred)))) ** 2
    frequencies = np.fft.rfftfreq(len(centred), 1 / rate)
    return float(power[frequencies >= cutoff_hz].sum() / max(power.sum(), 1e-9))


def windowed_spectral_centroids(samples, window, hop, *, rate=RATE,
                                remove_dc=True):
    """Centroid observations from overlapping complete windows."""
    samples = np.asarray(samples, dtype=np.float64)
    if window <= 0 or hop <= 0:
        raise ValueError("window and hop must be positive")
    return [spectral_centroid(samples[start:start + window], rate=rate,
                              remove_dc=remove_dc)
            for start in range(0, len(samples) - window + 1, hop)]


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


def lock(reference, candidate, block=LOCK_BLOCK, span=8000):
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


def contour_centroid(frame):
    """Centroid used by the established unpitched contour contract."""
    magnitude = np.abs(np.fft.rfft(frame * np.hanning(len(frame))))
    frequencies = np.fft.rfftfreq(len(frame), 1 / RATE)
    return float((magnitude * frequencies).sum()
                 / max(magnitude.sum(), 1e-9))


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
            rms.append(np.sqrt((seg ** 2).mean()))
            cen.append(contour_centroid(seg))
        return np.array(rms), np.array(cen)

    a_rms, a_cen = traj(reference)
    b_rms, b_cen = traj(candidate)
    if a_rms.std() == 0 or b_rms.std() == 0:
        return None
    return (float(np.corrcoef(a_rms, b_rms)[0, 1]),
            float(np.corrcoef(a_cen, b_cen)[0, 1]))


def pitch(frame, *, rate=RATE, lo_hz=LO_HZ, hi_hz=HI_HZ):
    """(hz, confidence) by autocorrelation; (0,0) when unvoiced.

    Autocorrelation, not an FFT peak: PICO-8 waveforms are harmonic-heavy and the
    strongest bin is routinely the second harmonic, which would report a
    consistent octave error and make a correct render look broken.
    """
    frame = np.asarray(frame, dtype=np.float64)
    n = len(frame)
    if n < 4:
        return 0.0, 0.0
    x = frame - frame.mean()
    energy = float(x @ x)
    if energy < 1e6:
        return 0.0, 0.0
    size = 1 << int(np.ceil(np.log2(2 * n)))
    spec = np.fft.rfft(x, size)
    corr = np.fft.irfft(spec * np.conj(spec), size)[:n]
    lo = max(1, int(rate / hi_hz))
    hi = min(int(rate / lo_hz), n // 2)
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
    return rate / lag, float(corr[lag] / energy)


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


@dataclass(frozen=True)
class BandObservation:
    """One overlapping band-analysis window retained for presentation."""

    time_seconds: float
    duration_seconds: float
    quiet_reference: bool
    deltas_db: tuple[float | None, ...]


def band_analysis(reference, candidate, *, min_share=BAND_MIN_SHARE,
                  live_power_floor=BAND_LIVE_POWER_FLOOR,
                  quiet_quantile=QUIET_QUANTILE,
                  minimum_quiet_windows=MIN_QUIET_WINDOWS):
    """Absolute spectral-level comparison, including reference-selected troughs.

    Each row is measured independently before robust aggregation. A band must
    carry at least BAND_MIN_SHARE of reference power in a window to participate;
    this prevents near-empty harmonic bands from producing enormous meaningless
    ratios. Whole-track values sum power, while local and quiet values are
    medians so a single transition cannot dominate the verdict.
    """
    n = min(len(reference), len(candidate))
    if n < BAND_WINDOW:
        return [], ()

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
        rows.append((start, total, powers))

    totals = np.array([row[1] for row in rows])
    live = totals > max(float(totals.max()) * live_power_floor, 1e-9)
    if not live.any():
        return [], ()
    quiet_ceiling = float(np.quantile(totals[live], quiet_quantile))
    quiet = live & (totals <= quiet_ceiling)

    results = []
    observation_values = [[None] * len(BANDS) for _ in rows]
    for band_index, (_, _, label) in enumerate(BANDS):
        active = np.array(
            [is_live and powers[band_index][0] >= min_share * total
             for is_live, (_, total, powers) in zip(live, rows)])
        local = []
        quiet_local = []
        ref_sum = cand_sum = 0.0
        for index, (_, _, powers) in enumerate(rows):
            if not active[index]:
                continue
            ref_power, cand_power = powers[band_index]
            value = db_ratio(cand_power, ref_power)
            observation_values[index][band_index] = value
            ref_sum += ref_power
            cand_sum += cand_power
            local.append(value)
            if quiet[index]:
                quiet_local.append(value)
        quiet_value = (float(np.median(quiet_local))
                       if len(quiet_local) >= minimum_quiet_windows else None)
        results.append(BandBalance(
            label=label,
            whole_db=db_ratio(cand_sum, ref_sum) if local else None,
            local_db=float(np.median(local)) if local else None,
            quiet_db=quiet_value,
            windows=len(local),
            quiet_windows=len(quiet_local),
        ))
    observations = tuple(
        BandObservation(
            start / RATE, BAND_WINDOW / RATE, bool(quiet[index]),
            tuple(observation_values[index]))
        for index, (start, _, _) in enumerate(rows))
    return results, observations


def band_balance(reference, candidate, *, min_share=BAND_MIN_SHARE,
                 live_power_floor=BAND_LIVE_POWER_FLOOR,
                 quiet_quantile=QUIET_QUANTILE,
                 minimum_quiet_windows=MIN_QUIET_WINDOWS):
    """Compatibility wrapper returning the established aggregate rows."""
    results, _ = band_analysis(
        reference, candidate, min_share=min_share,
        live_power_floor=live_power_floor, quiet_quantile=quiet_quantile,
        minimum_quiet_windows=minimum_quiet_windows)
    return results


def note_name(hz):
    if hz <= 0:
        return "-"
    midi = 69 + 12 * np.log2(hz / 440.0)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[int(round(midi)) % 12], int(round(midi)) // 12 - 1)


def semitone_distance(a, b):
    """Absolute musical distance in semitones, or infinity if unpitched."""
    if a <= 0 or b <= 0:
        return float("inf")
    return abs(12.0 * np.log2(a / b))


@dataclass(frozen=True)
class PitchAgreementRow:
    """One fixed-window pitch comparison."""

    index: int
    reference_hz: float
    candidate_hz: float
    applicable: bool
    agreed: bool


@dataclass(frozen=True)
class PitchAgreement:
    """Structured pitch-only result used by the preview-schedule gate."""

    rows: tuple[PitchAgreementRow, ...]
    compared: int
    agreed: int
    tolerance: float

    @property
    def ratio(self):
        return self.agreed / self.compared if self.compared else 0.0


def pitch_agreement(reference, candidate, *, window=WINDOW, rate=RATE,
                    voiced=VOICED, tolerance=TOLERANCE):
    """Compare unaligned, fixed-window pitch for two synchronized renders."""
    windows = min(len(reference), len(candidate)) // window
    rows = []
    compared = agreed = 0
    for index in range(windows):
        lo, hi = index * window, (index + 1) * window
        ref_hz, ref_conf = pitch(reference[lo:hi], rate=rate)
        candidate_hz, _ = pitch(candidate[lo:hi], rate=rate)
        applicable = ref_conf >= voiced
        ok = applicable and semitone_distance(ref_hz, candidate_hz) <= tolerance
        compared += int(applicable)
        agreed += int(ok)
        rows.append(PitchAgreementRow(index, ref_hz, candidate_hz,
                                      applicable, ok))
    return PitchAgreement(tuple(rows), compared, agreed, tolerance)


def report_pitch_agreement(reference, candidate, *, label, min_agreement,
                           verbose=False, out=sys.stdout):
    """Print and gate :func:`pitch_agreement`; return whether it passed."""
    result = pitch_agreement(reference, candidate)
    if verbose:
        print("    %-6s %-8s %-8s" % ("win", "reference", label), file=out)
        for row in result.rows:
            mark = ("skip" if not row.applicable
                    else "ok" if row.agreed else "MISMATCH")
            print("    %-6d %-8s %-8s %s"
                  % (row.index, note_name(row.reference_hz),
                     note_name(row.candidate_hz), mark), file=out)

    if result.compared == 0:
        print("    FAIL: no voiced windows in the reference - nothing was "
              "actually compared", file=out)
        return False

    print("    %s: %d/%d voiced windows agree within %.0f semitone (%.0f%%), "
          "need %.0f%%"
          % (label, result.agreed, result.compared, result.tolerance,
             100 * result.ratio, 100 * min_agreement), file=out)
    return result.ratio >= min_agreement


# ------------------------------------------------------- cart-aware SFX ----

NOTE_NAMES = ("C-", "C#", "D-", "D#", "E-", "F-",
              "F#", "G-", "G#", "A-", "A#", "B-")
WAVE_NAMES = ("tri", "tsaw", "saw", "square", "pulse", "organ",
              "noise", "phaser")
EFFECT_NAMES = ("none", "slide", "vibrato", "drop", "fadein", "fadeout",
                "arp-fast", "arp-slow")
STABLE_PITCH_EFFECTS = frozenset((0, 4, 5))


@dataclass(frozen=True)
class SfxRowAnalysis:
    """Measurements and independently applicable verdicts for one SFX row."""

    index: int
    pitch: int
    wave: int
    volume: int
    effect: int
    custom: bool
    rms: float
    peak: float
    measured_hz: float
    pitch_error: float | None
    energy_verdict: str
    pitch_verdict: str

    @property
    def failed(self):
        return self.energy_verdict != "ok" or self.pitch_verdict == "mismatch"


@dataclass(frozen=True)
class SfxAnalysis:
    """Structured result for a cart-annotated SFX render."""

    index: int
    speed: int
    loop_start: int
    loop_end: int
    filter_flags: int
    rows: tuple[SfxRowAnalysis, ...]

    @property
    def failures(self):
        return tuple(row for row in self.rows if row.failed)


def analyze_sfx(samples, rom, sfx_index, *, silent_below=40.0,
                pitch_tolerance=0.5, rate=RATE):
    """Measure a rendered SFX row by row against its cart data.

    Energy is checked for every row. Pitch is checked only where a single
    stable fundamental is meaningful: built-in non-noise waves with none,
    fade-in, or fade-out effects. Noise, custom instruments, slides, vibrato,
    drops, and arpeggios still report their observed level and pitch but carry
    an explicit ``n/a`` pitch verdict.
    """
    if not 0 <= sfx_index < 64:
        raise ValueError("sfx index must be in 0..63")
    if silent_below < 0:
        raise ValueError("silent threshold must not be negative")
    if pitch_tolerance < 0:
        raise ValueError("pitch tolerance must not be negative")
    if not len(samples):
        raise ValueError("audio has no samples")
    base = 0x3200 + sfx_index * 68
    if len(rom) < base + 68:
        raise ValueError("cart ROM is too short to contain the requested SFX")
    speed = rom[base + 65]
    if speed == 0:
        raise ValueError(f"sfx {sfx_index} has speed 0 - nothing to play")

    samples = np.asarray(samples, dtype=np.float64)
    samples_per_row = speed * SAMPLES_PER_TICK * rate / RATE
    rows = []
    for index in range(32):
        word = rom[base + index * 2] | (rom[base + index * 2 + 1] << 8)
        requested_pitch = word & 0x3f
        wave_index = (word >> 6) & 7
        volume = (word >> 9) & 7
        effect = (word >> 12) & 7
        custom = bool(word & 0x8000)
        lo = int(index * samples_per_row)
        hi = int((index + 1) * samples_per_row)
        segment = samples[lo:min(hi, len(samples))]
        if not len(segment):
            break

        level = rms(segment)
        peak = float(np.max(np.abs(segment)))
        energy_verdict = ("missing" if volume and level < silent_below
                          else "leak" if not volume and level >= silent_below
                          else "ok")

        margin = len(segment) // 4
        tail = len(segment) // 8
        steady = segment[margin:len(segment) - tail] if tail else segment[margin:]
        measured_hz, confidence = pitch(steady, rate=rate,
                                        lo_hz=55.0, hi_hz=2200.0)
        applicable = (volume > 0 and not custom and wave_index != 6
                      and effect in STABLE_PITCH_EFFECTS)
        if not applicable:
            error = None
            pitch_verdict = "n/a"
        else:
            wanted_hz = 440.0 * 2.0 ** ((requested_pitch - 33) / 12.0)
            error = (12.0 * np.log2(measured_hz / wanted_hz)
                     if measured_hz > 0 and confidence >= VOICED else None)
            pitch_verdict = ("ok" if error is not None
                             and abs(error) < pitch_tolerance else "mismatch")

        rows.append(SfxRowAnalysis(
            index, requested_pitch, wave_index, volume, effect, custom,
            level, peak, measured_hz, error, energy_verdict, pitch_verdict))

    return SfxAnalysis(sfx_index, speed, rom[base + 66], rom[base + 67],
                       rom[base + 64], tuple(rows))


def report_sfx_analysis(result, *, out=sys.stdout):
    """Print a cart-annotated SFX table; return whether every check passed."""
    row_ms = result.speed * SAMPLES_PER_TICK / RATE * 1000.0
    print(f"sfx {result.index}: speed {result.speed} ({row_ms:.1f} ms/row), "
          f"loop {result.loop_start}..{result.loop_end}, "
          f"filter 0x{result.filter_flags:02x}", file=out)
    print(f"{'row':>4} {'note':>5} {'wave':>9} {'vol':>3} {'effect':>9} "
          f"{'RMS':>7} {'peak':>7} {'got Hz':>8} {'pitch err':>10}  verdict",
          file=out)
    for row in result.rows:
        wave = ("custom-" if row.custom else "") + WAVE_NAMES[row.wave]
        measured = "-" if row.measured_hz <= 0 else f"{row.measured_hz:.1f}"
        error = ("n/a" if row.pitch_error is None
                 else f"{row.pitch_error:+.2f} st")
        failures = []
        if row.energy_verdict != "ok":
            failures.append(row.energy_verdict.upper())
        if row.pitch_verdict == "mismatch":
            failures.append("PITCH")
        verdict = ",".join(failures) if failures else "ok"
        print(f"{row.index:>4} "
              f"{NOTE_NAMES[row.pitch % 12]}{row.pitch // 12:<3} "
              f"{wave:>9} {row.volume:>3} {EFFECT_NAMES[row.effect]:>9} "
              f"{row.rms:>7.0f} {row.peak:>7.0f} {measured:>8} "
              f"{error:>10}  {verdict}", file=out)

    missing = sum(row.energy_verdict == "missing" for row in result.rows)
    leaked = sum(row.energy_verdict == "leak" for row in result.rows)
    pitch_bad = sum(row.pitch_verdict == "mismatch" for row in result.rows)
    pitch_tested = sum(row.pitch_verdict != "n/a" for row in result.rows)
    print(f"\n{missing} audible row(s) silent, {leaked} silent row(s) leaking; "
          f"{pitch_tested - pitch_bad}/{pitch_tested} applicable rows within "
          f"pitch tolerance", file=out)
    return not result.failures


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
        raise OptionalDependencyError(
            "--spectrogram-file needs matplotlib (pip install matplotlib), "
            "or use --spectrogram")

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
class AudioView:
    """Composable terminal views plus the optional spectrogram image artifact.

    ``terminal=True`` remains the library-compatible spelling for a single
    spectrogram. New callers should pass explicit ``views`` and geometry.
    """
    terminal: bool = False
    path: str | None = None
    window: tuple[float, float | None] | None = None
    color: bool = True
    out: object = sys.stdout
    views: tuple[str, ...] = ()
    layout: str = "rows"
    width: int = 32
    lines_per_second: float = SPEC_LINES_PER_SEC
    max_lines: int = SPEC_MAX_LINES
    axis: str = "auto"
    inspection_channel_samples: np.ndarray | None = None
    reference_channel_samples: np.ndarray | None = None
    candidate_channel_samples: np.ndarray | None = None

    def selected_views(self):
        selected = list(self.views)
        if self.terminal and "spectrogram" not in selected:
            selected.append("spectrogram")
        return tuple(selected)

    def wanted(self):
        return bool(self.selected_views()) or bool(self.path)

    def _selection(self, panels):
        total = min(len(samples) for _, samples in panels)
        lo, hi = 0, total
        if self.window is not None:
            lo = min(max(int(self.window[0] * RATE), 0), total)
            hi = total if self.window[1] is None else min(int(self.window[1] * RATE),
                                                          total)
        seconds = max(hi - lo, 0) / RATE
        lines = int(min(self.max_lines,
                        max(6, round(seconds * self.lines_per_second))))
        return lo, hi, seconds, lines

    def _geometry(self, start, seconds, lines):
        from _audio_analysis_terminal import TerminalGeometry
        return TerminalGeometry(
            start_seconds=start, seconds=seconds, lines=lines,
            width=self.width, layout=self.layout, axis=self.axis,
            color=self.color)

    def show_inspection(self, label, samples, clicks):
        """Render selected standalone views and the optional image."""
        lo, hi, seconds, lines = self._selection([(label, samples)])
        clipped = samples[lo:hi]
        channels = (None if self.inspection_channel_samples is None else
                    self.inspection_channel_samples[lo:hi])
        selected = self.selected_views()
        if selected:
            from _audio_analysis_terminal import render_inspection
            output = render_inspection(
                selected, label, clipped, clicks,
                self._geometry(lo / RATE, seconds, lines),
                channel_samples=channels)
            print("\n".join(output), file=self.out)
        if self.path:
            if hi - lo < SPEC_FFT:
                print("    spectrogram: range holds %d samples, need %d"
                      % (max(hi - lo, 0), SPEC_FFT), file=self.out)
            else:
                draw_file([(label, clipped)], lo / RATE, self.path, out=self.out)

    def show_comparison(self, result, reference_label="reference"):
        """Render selected comparison views from one pure analysis result."""
        panels = [(reference_label, result.reference),
                  (result.data["label"], result.shifted_candidate)]
        lo, hi, seconds, lines = self._selection(panels)
        clipped_result = replace(
            result, reference=result.reference[lo:hi],
            shifted_candidate=result.shifted_candidate[lo:hi])
        reference_channels = self.reference_channel_samples
        candidate_channels = self.candidate_channel_samples
        if candidate_channels is not None:
            candidate_channels = np.column_stack([
                shift(candidate_channels[:, channel], result.data["lag_samples"])
                for channel in range(candidate_channels.shape[1])
            ])
        channel_panels = [
            (reference_label,
             None if reference_channels is None else reference_channels[lo:hi]),
            (result.data["label"],
             None if candidate_channels is None else candidate_channels[lo:hi]),
        ]
        selected = self.selected_views()
        if selected:
            from _audio_analysis_terminal import render_comparison
            output = render_comparison(
                selected, clipped_result, reference_label,
                self._geometry(lo / RATE, seconds, lines),
                channel_panels=channel_panels)
            print("\n".join(output), file=self.out)
        if self.path:
            if hi - lo < SPEC_FFT:
                print("    spectrogram: range holds %d samples, need %d"
                      % (max(hi - lo, 0), SPEC_FFT), file=self.out)
            else:
                draw_file(
                    [(reference_label, result.reference[lo:hi]),
                     (result.data["label"], result.shifted_candidate[lo:hi])],
                    lo / RATE, self.path, out=self.out)

    def show(self, panels):
        """Compatibility entry point for callers requesting only spectrograms."""
        lo, hi, seconds, _ = self._selection(panels)
        if hi - lo < SPEC_FFT:
            print("    spectrogram: range holds %d samples, need %d"
                  % (max(hi - lo, 0), SPEC_FFT), file=self.out)
            return
        clipped = [(label, samples[lo:hi]) for label, samples in panels]
        if self.terminal:
            draw(clipped, lo / RATE, seconds, self.color, out=self.out)
        if self.path:
            draw_file(clipped, lo / RATE, self.path, out=self.out)


# Compatibility for repository callers which predate composable terminal views.
SpectrogramView = AudioView


# ---------------------------------------------------------- the report ----

@dataclass(frozen=True)
class ComparisonWindow:
    """One fixed-window observation retained for optional human detail."""

    index: int
    reference_hz: float
    candidate_hz: float
    reference_rms: float
    candidate_rms: float
    spectrum_cosine: float
    pitch_agreed: bool | None
    reference_contour_centroid_hz: float | None = None
    candidate_contour_centroid_hz: float | None = None


@dataclass(frozen=True)
class LockObservation:
    """One timing-lock block retained for diagnostic presentation."""

    time_seconds: float
    duration_seconds: float
    lag_samples: int
    correlation: float


@dataclass(frozen=True)
class ComparisonResult:
    """Pure full-track result, independent of terminal or file presentation."""

    data: dict
    windows: tuple[ComparisonWindow, ...]
    reference: np.ndarray
    shifted_candidate: np.ndarray
    click_analysis: ClickComparison
    lock_observations: tuple[LockObservation, ...] = ()
    band_observations: tuple[BandObservation, ...] = ()

    @property
    def status(self) -> str:
        return self.data["status"]

    @property
    def score(self) -> float:
        return self.data["score"]

    @property
    def passed(self) -> bool:
        return self.status == "ok"

    def as_dict(self) -> dict:
        """Return the JSON-ready public result without presentation state."""
        return dict(self.data)


def analyze_comparison(reference, candidate, label="candidate", *, policy=None):
    """Compute a full-track comparison without printing or writing artifacts."""
    policy = comparison_policy(policy)
    reference = np.asarray(reference, dtype=np.float64)
    candidate = np.asarray(candidate, dtype=np.float64)
    pitchiness = reference_pitchiness(reference)
    pitched = pitchiness >= policy.pitched_reference_minimum
    alignment = "sample" if pitched else "envelope"
    lag = (align(reference, candidate) if pitched
           else align_envelope(reference, candidate))
    shifted = shift(candidate, lag)
    click_result = compare_clicks(
        reference, shifted, rate=RATE, policy=policy.click_detection_policy,
        match_tolerance_samples=policy.click_match_tolerance_samples,
        maximum_unmatched_events=policy.click_maximum_unmatched_events)
    overlap_samples = min(len(reference), len(shifted))
    window_count = overlap_samples // WINDOW
    common = {
        "label": label,
        "policy": policy.as_dict(),
        "threshold": policy.score_minimum,
        "pitched_reference": pitched,
        "reference_pitchiness": pitchiness,
        "alignment_method": alignment,
        "lag_samples": lag,
        "lag_milliseconds": lag / RATE * 1000.0,
        "overlap_samples": overlap_samples,
        "window_count": window_count,
    }
    if window_count < 1:
        failure_types = ["insufficient_audio"]
        if not click_result.passed:
            failure_types.append("clicks")
        data = {
            **common,
            "status": "failed",
            "score": 0.0,
            "failure_types": failure_types,
            "pitch": None,
            "level": None,
            "spectrum": None,
            "contour": None,
            "bands": [],
            "band_failures": [],
            "lock": None,
            "clicks": click_result.as_dict(),
            "first_pitch_mismatch_seconds": None,
        }
        return ComparisonResult(data, (), reference, shifted, click_result)

    reference_hz = []
    candidate_hz = []
    rows = []
    compared = agreed = 0
    for index in range(window_count):
        lo, hi = index * WINDOW, (index + 1) * WINDOW
        ref, cand = reference[lo:hi], shifted[lo:hi]
        ref_pitch, ref_confidence = pitch(ref)
        candidate_pitch, _ = pitch(cand)
        reference_hz.append(ref_pitch)
        candidate_hz.append(candidate_pitch)
        ref_level, candidate_level = rms(ref), rms(cand)
        ref_contour_centroid = contour_centroid(ref) if not pitched else None
        candidate_contour_centroid = (
            contour_centroid(cand) if not pitched else None)
        ref_spectrum, candidate_spectrum = spectrum(ref), spectrum(cand)
        cosine = float(ref_spectrum @ candidate_spectrum /
                       (np.linalg.norm(ref_spectrum)
                        * np.linalg.norm(candidate_spectrum) + 1e-12))
        ok = None
        if ref_confidence >= policy.voiced_confidence_minimum:
            ok = (semitone_distance(ref_pitch, candidate_pitch)
                  <= policy.pitch_tolerance_semitones)
            compared += 1
            agreed += int(ok)
        rows.append(ComparisonWindow(
            index, ref_pitch, candidate_pitch, ref_level, candidate_level,
            cosine, ok, ref_contour_centroid, candidate_contour_centroid))

    settled = 0
    for index, row in enumerate(rows):
        if row.pitch_agreed is None or candidate_hz[index] <= 0:
            continue
        neighbours = [reference_hz[near]
                      for near in (index - 1, index, index + 1)
                      if 0 <= near < window_count]
        settled += any(
            frequency > 0
            and semitone_distance(frequency, candidate_hz[index])
                <= policy.pitch_tolerance_semitones
            for frequency in neighbours)

    reference_levels = np.array([row.reference_rms for row in rows])
    candidate_levels = np.array([row.candidate_rms for row in rows])
    shape = None
    if not pitched and len(rows) >= 4:
        reference_centroids = np.array(
            [row.reference_contour_centroid_hz for row in rows])
        candidate_centroids = np.array(
            [row.candidate_contour_centroid_hz for row in rows])
        if reference_levels.std() != 0 and candidate_levels.std() != 0:
            shape = (
                float(np.corrcoef(reference_levels, candidate_levels)[0, 1]),
                float(np.corrcoef(reference_centroids,
                                  candidate_centroids)[0, 1]),
            )
    live = reference_levels > policy.live_rms_minimum
    level_result = None
    if live.any():
        ratios = candidate_levels[live] / reference_levels[live]
        level_result = {
            "rms_ratio_median": float(np.median(ratios)),
            "rms_ratio_p10": float(np.percentile(ratios, 10)),
            "rms_ratio_p90": float(np.percentile(ratios, 90)),
            "reference_rms_mean": float(reference_levels[live].mean()),
            "candidate_rms_mean": float(candidate_levels[live].mean()),
        }

    cosines = np.array([row.spectrum_cosine for row in rows])
    spectrum_result = {
        "cosine_median": float(np.median(cosines)),
        "cosine_p10": float(np.percentile(cosines, 10)),
    }

    balance, band_observations = band_analysis(
        reference, shifted,
        min_share=policy.band_minimum_reference_share,
        live_power_floor=policy.band_live_power_floor,
        quiet_quantile=policy.quiet_reference_quantile,
        minimum_quiet_windows=policy.minimum_quiet_windows)
    band_failures = []
    band_results = []
    for band in balance:
        failed = band.failures(policy.band_tolerance_db)
        band_failures.extend(f"{band.label} {scope}" for scope in failed)
        band_results.append({
            "label": band.label,
            "whole_db": band.whole_db,
            "local_db": band.local_db,
            "quiet_db": band.quiet_db,
            "window_count": band.windows,
            "quiet_window_count": band.quiet_windows,
            "failed_scopes": failed,
        })

    locks = lock(reference, candidate) if pitched else []
    lock_observations = tuple(
        LockObservation(when, LOCK_BLOCK / RATE, item_lag, correlation)
        for when, item_lag, correlation in locks)
    lock_result = None
    if locks:
        held = [correlation for _, _, correlation in locks]
        strong_lags = [
            item_lag + 20000 for _, item_lag, correlation in locks
            if correlation > policy.lock_block_correlation_minimum
        ]
        modal = (int(np.bincount(strong_lags).argmax() - 20000)
                 if strong_lags else None)
        tracking = ([
            abs(item_lag - modal) <= policy.lock_lag_tolerance_samples
            and correlation > policy.lock_block_correlation_minimum
            for _, item_lag, correlation in locks
        ] if modal is not None else [False] * len(locks))
        last = len(tracking)
        while last > 0 and not tracking[last - 1]:
            last -= 1
        lost_after = last * 0.5 if last < len(tracking) else None
        tracked_count = int(sum(tracking))
        lock_result = {
            "median_correlation": float(np.median(held)),
            "tracked_block_count": tracked_count,
            "tracked_ratio": tracked_count / len(locks),
            "block_count": len(locks),
            "modal_lag_samples": modal,
            "lost_after_seconds": lost_after,
        }

    bad = [row for row in rows if row.pitch_agreed is False]
    first_mismatch = (bad[0].index * WINDOW / RATE
                      if bad and compared and pitched else None)
    raw_score = (min(shape) if not pitched and shape is not None
                 else agreed / compared if pitched and compared else 0.0)
    score = float(raw_score)
    failure_types = []
    if score < policy.score_minimum:
        failure_types.append("comparison_score")
    if band_failures:
        failure_types.append("band_level")
    if level_result is not None:
        median_ratio = level_result["rms_ratio_median"]
        if ((policy.level_ratio_median_minimum is not None
             and median_ratio < policy.level_ratio_median_minimum)
                or (policy.level_ratio_median_maximum is not None
                    and median_ratio > policy.level_ratio_median_maximum)):
            failure_types.append("level")
    if ((policy.spectrum_cosine_median_minimum is not None
         and spectrum_result["cosine_median"]
             < policy.spectrum_cosine_median_minimum)
            or (policy.spectrum_cosine_p10_minimum is not None
                and spectrum_result["cosine_p10"]
                    < policy.spectrum_cosine_p10_minimum)):
        failure_types.append("spectrum")
    if lock_result is not None:
        if ((policy.lock_median_correlation_minimum is not None
             and lock_result["median_correlation"]
                 < policy.lock_median_correlation_minimum)
                or (policy.lock_tracked_ratio_minimum is not None
                    and lock_result["tracked_ratio"]
                    < policy.lock_tracked_ratio_minimum)):
            failure_types.append("lock")
    if not click_result.passed:
        failure_types.append("clicks")

    data = {
        **common,
        "status": "failed" if failure_types else "ok",
        "score": score,
        "failure_types": failure_types,
        "pitch": ({
            "compared_window_count": compared,
            "agreed_window_count": agreed,
            "agreement_ratio": agreed / compared if compared else None,
            "boundary_slack_agreement_ratio":
                settled / compared if compared else None,
            "tolerance_semitones": policy.pitch_tolerance_semitones,
        } if pitched else None),
        "level": level_result,
        "spectrum": spectrum_result,
        "contour": ({
            "loudness_correlation": shape[0],
            "timbre_correlation": shape[1],
        } if shape is not None else None),
        "bands": band_results,
        "band_failures": band_failures,
        "lock": lock_result,
        "clicks": click_result.as_dict(),
        "first_pitch_mismatch_seconds": first_mismatch,
    }
    return ComparisonResult(
        data, tuple(rows), reference, shifted, click_result,
        lock_observations, band_observations)


def report_comparison(result, *, verbose=False, view=None,
                      reference_label="reference", out=sys.stdout):
    """Render one result through the private presentation layer."""
    from _audio_analysis_reporting import report_comparison as render
    return render(result, verbose=verbose, view=view,
                  reference_label=reference_label, out=out)


def report_click_analysis(result, *, out=sys.stdout, indent=""):
    """Render one :class:`ClickAnalysis` without recomputing detection."""
    from _audio_analysis_reporting import report_click_analysis as render
    return render(result, out=out, indent=indent)


def compare_audio(reference, candidate, label, verbose, view,
                  ref_label="reference", *, out=sys.stdout,
                  pass_threshold=None, policy=None):
    """Compatibility reporting wrapper; new callers should use analyze/report."""
    selected = comparison_policy(policy)
    if pass_threshold is not None:
        selected = replace(selected, score_minimum=pass_threshold)
    result = analyze_comparison(reference, candidate, label, policy=selected)
    report_comparison(result, verbose=verbose, view=view,
                      reference_label=ref_label, out=out)
    return result.score if result.passed else 0.0


# ------------------------------------------------------------------- CLI ----

def main(argv=None):
    """Run the private CLI contract through this stable public facade."""
    from _audio_analysis_cli import main as cli_main
    return cli_main(argv)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # `audio_analysis.py wav compare ... | head` closes the pipe under us.
        # Die like a
        # unix tool instead of dumping a traceback the shell then hides anyway.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(141)
    except KeyboardInterrupt:
        sys.exit(130)
