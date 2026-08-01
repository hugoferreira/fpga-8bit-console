#!/usr/bin/env python3
"""Regenerate the coloured terminal captures in ``audio-analysis.md``.

This is documentation plumbing, not a second audio analyzer. It invokes the
public ``tools/audio_analysis.py`` CLI, verifies its JSON stdout, and renders
the ANSI diagnostic stream directly to deterministic PNGs with exact Fira Code
font files.  It never creates an SVG or asks a browser to rasterize one.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/images/audio-analysis"
ANSI = re.compile(r"\x1b\[([0-9;]*)m")
BACKGROUND = (13, 17, 23)
FOREGROUND = (220, 224, 232)
RENDER_SCALE = 2
LOGICAL_FONT_SIZE = 16
FONT_SIZE = LOGICAL_FONT_SIZE * RENDER_SCALE
CELL_WIDTH = 10 * RENDER_SCALE
CELL_HEIGHT = 20 * RENDER_SCALE
PADDING = 16 * RENDER_SCALE
PNG_DPI = 72 * RENDER_SCALE
FONT_DIRECTORY = Path.home() / "Library/Fonts"
FONT_REGULAR = FONT_DIRECTORY / "FiraCode-Retina.ttf"
FONT_BOLD = FONT_DIRECTORY / "FiraCode-Bold.ttf"
FONT_REGULAR_SHA256 = "4fe2df1cea543281e8ec0fa512d1b493eacb859cf62bc7a84886daa89268b3f3"
FONT_BOLD_SHA256 = "41f6554e845e2f5b70adad3950122334b866aac436793b7742ade600067701be"
PALETTE = (
    (0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16),
    (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
    (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67),
    (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255),
)

CAPTURES = (
    (
        "terminal-spectrogram-diff.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/psg_fidelity/noise-sweep-rtl.wav",
            "--labels", "rtl",
            "--view", "spectrogram", "--view", "spectral-diff",
            "--layout", "columns", "--view-width", "32",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-phase-difference.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/phase-reference.wav",
            "build/audio-analysis-docs/phase-shift.wav",
            "--labels", "high-tone+90deg",
            "--view", "wave-correlation", "--view", "spectral-diff",
            "--view", "phase-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-spectral-coherence.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/coherence-reference.wav",
            "build/audio-analysis-docs/coherence-phase-modulated.wav",
            "--labels", "fm",
            "--view", "wave-correlation", "--view", "spectral-diff",
            "--view", "phase-diff", "--view", "spectral-coherence",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-pitch-track.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/pitch-steps.wav",
            "--view", "spectrogram", "--view", "pitch-track",
            "--view", "rms-level", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-click-localization.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/psg_fidelity/noise-sweep-rtl.wav",
            "--labels", "rtl",
            "--view", "waveform", "--view", "clicks",
            "--view", "residual", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-noise-contour.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/psg_fidelity/noise-sweep-rtl.wav",
            "--labels", "rtl",
            "--view", "metrics", "--view", "contour",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-band-delta.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/psg_fidelity/noise-sweep-rtl.wav",
            "--labels", "rtl",
            "--view", "metrics", "--view", "band-delta",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-pitch-spectrum.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_oracle/clk26500000/reference/effect-1-slide.wav",
            "build/psg_oracle/clk26500000/rtl/effect-2-vibrato.wav",
            "--labels", "vibrato-vs-slide",
            "--view", "metrics", "--view", "pitch-delta",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "8",
            "--max-lines", "8", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-level-timing.png",
        (
            "--output", "json", "wav", "compare",
            "build/p8ref/pico8-0.wav", "build/p8ref/pvfit-0.wav",
            "--labels", "preview-fit",
            "--view", "metrics", "--view", "level-delta",
            "--view", "timing-drift", "--layout", "columns",
            "--view-range", "0:12", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "12",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-amplitude-health.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/amplitude-artifacts.wav",
            "--view", "waveform", "--view", "rail-ratio",
            "--view", "quantization-step", "--view", "sample-density",
            "--view", "dc-offset", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-subrail-clipping.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/subrail-clipping.wav",
            "--view", "waveform", "--view", "rail-ratio",
            "--view", "flatline-ratio", "--view", "peak-occupancy",
            "--view", "crest-factor", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-intersample-peak.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/intersample-over.wav",
            "--view", "waveform", "--view", "rail-ratio",
            "--view", "intersample-peak", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-wave-correlation.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/audio-analysis-docs/polarity-flip.wav",
            "--labels", "polarity-flip",
            "--view", "waveform", "--view", "wave-correlation",
            "--view", "residual", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-stereo-cancellation.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/stereo-in-phase.wav",
            "build/audio-analysis-docs/stereo-phase-flip.wav",
            "--labels", "phase-flip",
            "--view", "waveform", "--view", "stereo-correlation",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-stereo-phase.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/stereo-frequency-cancellation.wav",
            "--view", "spectrogram", "--view", "stereo-balance",
            "--view", "stereo-correlation", "--view", "stereo-phase",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-stereo-level-diff.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/stereo-frequency-loss.wav",
            "--view", "spectrogram", "--view", "stereo-balance",
            "--view", "stereo-correlation", "--view", "stereo-phase",
            "--view", "stereo-level-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-stereo-coherence.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/stereo-frequency-decorrelation.wav",
            "--view", "stereo-balance", "--view", "stereo-correlation",
            "--view", "stereo-level-diff", "--view", "stereo-phase",
            "--view", "stereo-coherence", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-channel-loss.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/stereo-in-phase.wav",
            "build/audio-analysis-docs/stereo-channel-loss.wav",
            "--labels", "right-channel-loss",
            "--view", "waveform", "--view", "stereo-balance",
            "--view", "stereo-correlation",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-stereo-delay.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/stereo-delay-reference.wav",
            "build/audio-analysis-docs/stereo-delay-2ms.wav",
            "--labels", "right-2ms-late",
            "--view", "spectral-diff", "--view", "stereo-correlation",
            "--view", "stereo-delay",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-residual-severity.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/steady-two-tone.wav",
            "build/audio-analysis-docs/residual-bursts.wav",
            "--labels", "error-bursts",
            "--view", "level-delta", "--view", "wave-correlation",
            "--view", "residual-ratio", "--view", "residual",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-crest-factor.png",
        (
            "--output", "json", "wav", "compare",
            "build/psg_fidelity/noise-sweep-head.wav",
            "build/audio-analysis-docs/rms-matched-compression.wav",
            "--labels", "compressed",
            "--view", "waveform", "--view", "level-delta",
            "--view", "crest-factor", "--layout", "columns",
            "--view-width", "20", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-derivative-ratio.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/hf-reference.wav",
            "build/audio-analysis-docs/hf-hash.wav",
            "--labels", "hf-hash",
            "--view", "level-delta", "--view", "derivative-ratio",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-spectral-change.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/steady-two-tone.wav",
            "build/audio-analysis-docs/spectral-jumps.wav",
            "--labels", "jumps",
            "--view", "rms-level", "--view", "spectral-change",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-spectral-centroid.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/steady-two-tone.wav",
            "build/audio-analysis-docs/brightened.wav",
            "--labels", "brightened",
            "--view", "rms-level", "--view", "spectral-centroid",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-spectral-flatness.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/steady-two-tone.wav",
            "build/audio-analysis-docs/noisy-two-tone.wav",
            "--labels", "broadband-noise",
            "--view", "rms-level", "--view", "spectral-flatness",
            "--view", "spectral-diff", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-modulation-spectrum.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/am-50hz.wav",
            "--view", "rms-level", "--view", "crest-factor",
            "--view", "spectrogram", "--view", "modulation-spectrum",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-low-frequency-spectrum.png",
        (
            "--output", "json", "wav", "inspect",
            "build/audio-analysis-docs/low-frequency-50-60.wav",
            "--view", "rms-level", "--view", "spectral-change",
            "--view", "spectrogram", "--view", "modulation-spectrum",
            "--view", "low-frequency-spectrum",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-dropout-localization.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/hf-reference.wav",
            "build/audio-analysis-docs/dropouts.wav",
            "--labels", "dropouts",
            "--view", "rms-level", "--view", "clicks",
            "--view", "residual", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first",
            "--color", "always",
        ),
    ),
    (
        "terminal-held-buffer.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/hf-reference.wav",
            "build/audio-analysis-docs/held-buffer.wav",
            "--labels", "held-buffer",
            "--view", "waveform", "--view", "flatline-ratio",
            "--layout", "columns", "--view-width", "24",
            "--lines-per-second", "1", "--max-lines", "10",
            "--axis", "first", "--color", "always",
        ),
    ),
    (
        "terminal-replayed-buffer.png",
        (
            "--output", "json", "wav", "compare",
            "build/audio-analysis-docs/hf-reference.wav",
            "build/audio-analysis-docs/replayed-buffer.wav",
            "--labels", "replayed",
            "--view", "waveform", "--view", "flatline-ratio",
            "--view", "block-repeat", "--layout", "columns",
            "--view-width", "24", "--lines-per-second", "1",
            "--max-lines", "10", "--axis", "first", "--color", "always",
        ),
    ),
)


def prepare_artifact_fixtures():
    """Inject staged amplitude and polarity artifacts into a local render."""
    intersample_path = ROOT / "build/audio-analysis-docs/intersample-over.wav"
    fixture_rate = 22050
    pattern = np.resize(
        np.array((1.0, 1.0, -1.0, -1.0)), 8 * fixture_rate)
    intersample = pattern * 0.65 * 32768.0
    intersample[4 * fixture_rate:] = (
        pattern[4 * fixture_rate:] * 0.75 * 32768.0)
    intersample_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(intersample_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(intersample).astype("<i2").tobytes())

    phase_reference_path = (
        ROOT / "build/audio-analysis-docs/phase-reference.wav")
    phase_candidate_path = ROOT / "build/audio-analysis-docs/phase-shift.wav"
    coherence_reference_path = (
        ROOT / "build/audio-analysis-docs/coherence-reference.wav")
    coherence_candidate_path = (
        ROOT / "build/audio-analysis-docs/coherence-phase-modulated.wav")
    stereo_frequency_path = (
        ROOT / "build/audio-analysis-docs/stereo-frequency-cancellation.wav")
    stereo_loss_path = (
        ROOT / "build/audio-analysis-docs/stereo-frequency-loss.wav")
    stereo_coherence_path = (
        ROOT / "build/audio-analysis-docs/stereo-frequency-decorrelation.wav")
    fixture_index = np.arange(8 * fixture_rate, dtype=np.float64)
    low_hz = 16 * fixture_rate / 1024.0
    high_hz = 128 * fixture_rate / 1024.0
    low_tone = 16000.0 * np.sin(
        2.0 * np.pi * low_hz * fixture_index / fixture_rate)
    high_phase = 2.0 * np.pi * high_hz * fixture_index / fixture_rate
    high_tone = 2000.0 * np.sin(high_phase)
    shifted_tone = 2000.0 * np.sin(high_phase + np.pi / 2.0)
    phase_reference = low_tone + high_tone
    phase_candidate = phase_reference.copy()
    transition_samples = fixture_rate // 10
    transition_start = 4 * fixture_rate - transition_samples // 2
    transition_end = transition_start + transition_samples
    blend = 0.5 - 0.5 * np.cos(
        np.linspace(0.0, np.pi, transition_samples))
    phase_candidate[transition_start:transition_end] = (
        low_tone[transition_start:transition_end]
        + (1.0 - blend) * high_tone[transition_start:transition_end]
        + blend * shifted_tone[transition_start:transition_end])
    phase_candidate[transition_end:] = (
        low_tone[transition_end:] + shifted_tone[transition_end:])
    for path, values in ((phase_reference_path, phase_reference),
                         (phase_candidate_path, phase_candidate)):
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(fixture_rate)
            wav.writeframes(np.rint(values).astype("<i2").tobytes())

    coherence_candidate = phase_reference.copy()
    coherence_phase = 2.4048255577 * np.sin(
        2.0 * np.pi * 10.0 * fixture_index[4 * fixture_rate:] / fixture_rate)
    coherence_candidate[4 * fixture_rate:] = (
        low_tone[4 * fixture_rate:]
        + 2000.0 * np.sin(
            high_phase[4 * fixture_rate:] + coherence_phase))
    for path, values in ((coherence_reference_path, phase_reference),
                         (coherence_candidate_path, coherence_candidate)):
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(fixture_rate)
            wav.writeframes(np.rint(values).astype("<i2").tobytes())

    modulation_path = ROOT / "build/audio-analysis-docs/am-50hz.wav"
    modulation_index = np.arange(8 * fixture_rate, dtype=np.float64)
    modulation_fixture = 12000.0 * np.sin(
        2.0 * np.pi * (fixture_rate / 20.0)
        * modulation_index / fixture_rate)
    modulation_fixture[4 * fixture_rate:] *= (
        1.0 + 0.30 * np.sin(
            2.0 * np.pi * 50.0
            * modulation_index[4 * fixture_rate:] / fixture_rate))
    with wave.open(str(modulation_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(modulation_fixture).astype("<i2").tobytes())

    low_frequency_path = (
        ROOT / "build/audio-analysis-docs/low-frequency-50-60.wav")
    low_frequency_fixture = 12000.0 * np.sin(
        2.0 * np.pi * (fixture_rate / 20.0)
        * modulation_index / fixture_rate)
    low_frequency_fixture[:4 * fixture_rate] += 400.0 * np.sin(
        2.0 * np.pi * 50.0
        * modulation_index[:4 * fixture_rate] / fixture_rate)
    low_frequency_fixture[4 * fixture_rate:] += 400.0 * np.sin(
        2.0 * np.pi * 60.0
        * modulation_index[4 * fixture_rate:] / fixture_rate)
    with wave.open(str(low_frequency_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(low_frequency_fixture).astype("<i2").tobytes())

    stereo_left = phase_reference
    stereo_right = phase_reference.copy()
    stereo_right[transition_start:transition_end] = (
        low_tone[transition_start:transition_end]
        + (1.0 - 2.0 * blend) * high_tone[transition_start:transition_end])
    stereo_right[transition_end:] = (
        low_tone[transition_end:] - high_tone[transition_end:])
    stereo_frequency = np.column_stack((stereo_left, stereo_right))
    with wave.open(str(stereo_frequency_path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(stereo_frequency).astype("<i2").tobytes())

    stereo_loss_right = phase_reference.copy()
    stereo_loss_right[transition_start:transition_end] = (
        low_tone[transition_start:transition_end]
        + (1.0 - blend) * high_tone[transition_start:transition_end])
    stereo_loss_right[transition_end:] = low_tone[transition_end:]
    stereo_loss = np.column_stack((stereo_left, stereo_loss_right))
    with wave.open(str(stereo_loss_path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(stereo_loss).astype("<i2").tobytes())

    coherence_right = phase_reference.copy()
    coherence_time = fixture_index / fixture_rate
    coherence_phase = 2.4048255577 * np.sin(
        2.0 * np.pi * 10.0 * coherence_time[4 * fixture_rate:])
    coherence_right[4 * fixture_rate:] = (
        low_tone[4 * fixture_rate:]
        + 2000.0 * np.sin(
            high_phase[4 * fixture_rate:] + coherence_phase))
    coherence_channels = np.column_stack((phase_reference, coherence_right))
    with wave.open(str(stereo_coherence_path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(fixture_rate)
        wav.writeframes(np.rint(coherence_channels).astype("<i2").tobytes())

    source = ROOT / "build/psg_fidelity/noise-sweep-head.wav"
    amplitude_path = ROOT / "build/audio-analysis-docs/amplitude-artifacts.wav"
    polarity_path = ROOT / "build/audio-analysis-docs/polarity-flip.wav"
    dynamics_path = ROOT / "build/audio-analysis-docs/rms-matched-compression.wav"
    music_source = ROOT / "build/p8ref/pico8-0.wav"
    hf_reference_path = ROOT / "build/audio-analysis-docs/hf-reference.wav"
    hf_hash_path = ROOT / "build/audio-analysis-docs/hf-hash.wav"
    dropout_path = ROOT / "build/audio-analysis-docs/dropouts.wav"
    held_path = ROOT / "build/audio-analysis-docs/held-buffer.wav"
    replayed_path = ROOT / "build/audio-analysis-docs/replayed-buffer.wav"
    spectral_reference_path = ROOT / "build/audio-analysis-docs/steady-two-tone.wav"
    spectral_jump_path = ROOT / "build/audio-analysis-docs/spectral-jumps.wav"
    pitch_steps_path = ROOT / "build/audio-analysis-docs/pitch-steps.wav"
    brightened_path = ROOT / "build/audio-analysis-docs/brightened.wav"
    noisy_path = ROOT / "build/audio-analysis-docs/noisy-two-tone.wav"
    subrail_path = ROOT / "build/audio-analysis-docs/subrail-clipping.wav"
    residual_bursts_path = ROOT / "build/audio-analysis-docs/residual-bursts.wav"
    stereo_in_phase_path = ROOT / "build/audio-analysis-docs/stereo-in-phase.wav"
    stereo_phase_flip_path = ROOT / "build/audio-analysis-docs/stereo-phase-flip.wav"
    stereo_channel_loss_path = ROOT / "build/audio-analysis-docs/stereo-channel-loss.wav"
    stereo_delay_reference_path = ROOT / "build/audio-analysis-docs/stereo-delay-reference.wav"
    stereo_delay_candidate_path = ROOT / "build/audio-analysis-docs/stereo-delay-2ms.wav"
    if not source.exists() or not music_source.exists():
        return
    with wave.open(str(source), "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth()) != (1, 2):
            raise RuntimeError("amplitude fixture source must be mono 16-bit PCM")
        rate = wav.getframerate()
        samples = np.frombuffer(
            wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float64)
    damaged = samples.copy()
    boundaries = np.linspace(0, len(damaged), 5).astype(int)
    # Original, then coarse quantization, positive DC, and hard clipping.
    damaged[boundaries[1]:boundaries[2]] = (
        np.round(damaged[boundaries[1]:boundaries[2]] / 8192.0) * 8192.0)
    damaged[boundaries[2]:boundaries[3]] += 6000.0
    damaged[boundaries[3]:boundaries[4]] *= 8.0
    damaged = np.clip(damaged, -32768.0, 32767.0).astype("<i2")
    amplitude_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(amplitude_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(damaged.tobytes())

    polarity = samples.copy()
    polarity[len(polarity) // 2:] *= -1.0
    polarity = np.clip(polarity, -32768.0, 32767.0).astype("<i2")
    with wave.open(str(polarity_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(polarity.tobytes())

    dynamics = samples.copy()
    block_size = max(1, rate // 2)
    for start in range(len(dynamics) // 2, len(dynamics), block_size):
        end = min(start + block_size, len(dynamics))
        block = samples[start:end]
        limit = max(256.0, float(np.percentile(np.abs(block), 45.0)))
        compressed = np.clip(block, -limit, limit)
        original_rms = float(np.sqrt(np.mean(block * block)))
        compressed_rms = float(np.sqrt(np.mean(compressed * compressed)))
        if compressed_rms > 0:
            compressed *= original_rms / compressed_rms
        dynamics[start:end] = compressed
    dynamics = np.clip(dynamics, -32768.0, 32767.0).astype("<i2")
    with wave.open(str(dynamics_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(dynamics.tobytes())

    with wave.open(str(music_source), "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth()) != (1, 2):
            raise RuntimeError("HF fixture source must be mono 16-bit PCM")
        music_rate = wav.getframerate()
        music = np.frombuffer(
            wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float64)
    hf_reference = music[:8 * music_rate].copy()
    hf_hash = hf_reference.copy()
    block_size = max(1, music_rate // 2)
    for start in range(len(hf_hash) // 2, len(hf_hash), block_size):
        end = min(start + block_size, len(hf_hash))
        block = hf_reference[start:end]
        original_rms = float(np.sqrt(np.mean(block * block)))
        phase = 2.0 * np.pi * 6000.0 * np.arange(start, end) / music_rate
        contaminated = block + 0.35 * original_rms * np.sin(phase)
        contaminated_rms = float(np.sqrt(np.mean(contaminated * contaminated)))
        if contaminated_rms > 0:
            contaminated *= original_rms / contaminated_rms
        hf_hash[start:end] = contaminated
    dropouts = hf_reference.copy()
    dropouts[4 * music_rate:5 * music_rate] = 0.0
    dropouts[6 * music_rate:7 * music_rate] = 0.0
    held = hf_reference.copy()
    for start, end in ((4 * music_rate, 5 * music_rate),
                       (6 * music_rate, 7 * music_rate)):
        block = hf_reference[start:end]
        held[start:end] = float(np.sqrt(np.mean(block * block)))
    replayed = hf_reference.copy()
    for start, end in ((4 * music_rate, 5 * music_rate),
                       (6 * music_rate, 7 * music_rate)):
        replayed[start:end] = hf_reference[start - music_rate:end - music_rate]
    spectral_time = np.arange(8 * music_rate, dtype=np.float64)
    spectral_reference = (
        7000.0 * np.sin(2.0 * np.pi * 24.0 * spectral_time / 1024.0)
        + 3500.0 * np.sin(2.0 * np.pi * 48.0 * spectral_time / 1024.0))
    residual_bursts = spectral_reference.copy()
    for start_seconds, error_db in ((4, -40.0), (6, -20.0)):
        start, end = start_seconds * music_rate, (start_seconds + 1) * music_rate
        block = spectral_reference[start:end]
        reference_rms = float(np.sqrt(np.mean(block * block)))
        error_phase = np.arange(end - start, dtype=np.float64) / music_rate
        residual_bursts[start:end] += (
            np.sqrt(2.0) * reference_rms * 10.0 ** (error_db / 20.0)
            * np.sin(2.0 * np.pi * 3000.0 * error_phase))
    subrail_clipping = spectral_reference.copy()
    clipping_random = np.random.default_rng(20260802)
    for start in range(4 * music_rate, len(subrail_clipping), block_size):
        end = min(start + block_size, len(subrail_clipping))
        block = spectral_reference[start:end]
        limit = float(np.percentile(np.abs(block), 45.0))
        limited = np.clip(block, -limit, limit)
        plateau = np.abs(limited) >= limit
        dither = clipping_random.uniform(
            -0.005 * limit, 0.005 * limit, int(np.count_nonzero(plateau)))
        limited[plateau] += dither * np.sign(limited[plateau])
        original_rms = float(np.sqrt(np.mean(block * block)))
        limited_rms = float(np.sqrt(np.mean(limited * limited)))
        subrail_clipping[start:end] = limited * original_rms / limited_rms
    spectral_jumps = spectral_reference.copy()
    for region_start, region_end in ((4 * music_rate, 5 * music_rate),
                                     (6 * music_rate, 7 * music_rate)):
        for start in range(region_start, region_end, block_size):
            end = min(start + block_size, region_end)
            block = spectral_reference[start:end]
            rms = float(np.sqrt(np.mean(block * block)))
            phase = 2.0 * np.pi * 280.0 * np.arange(start, end) / 1024.0
            spectral_jumps[start:end] = np.sqrt(2.0) * rms * np.sin(phase)
    pitch_steps = np.zeros(8 * music_rate, dtype=np.float64)
    fade = max(1, music_rate // 100)
    for start_seconds, end_seconds, frequency in (
            (0, 2, 220.0), (2, 4, 440.0), (6, 8, 880.0)):
        start, end = start_seconds * music_rate, end_seconds * music_rate
        phase = np.arange(end - start, dtype=np.float64) / music_rate
        tone = 8000.0 * np.sin(2.0 * np.pi * frequency * phase)
        ramp = np.sin(np.linspace(0.0, np.pi / 2.0, fade)) ** 2
        tone[:fade] *= ramp
        tone[-fade:] *= ramp[::-1]
        pitch_steps[start:end] = tone
    brightened = spectral_reference.copy()
    for start in range(4 * music_rate, len(brightened), block_size):
        end = min(start + block_size, len(brightened))
        block = spectral_reference[start:end]
        original_rms = float(np.sqrt(np.mean(block * block)))
        phase = 2.0 * np.pi * 280.0 * np.arange(start, end) / 1024.0
        contaminated = block + original_rms * np.sin(phase)
        contaminated_rms = float(np.sqrt(np.mean(contaminated * contaminated)))
        brightened[start:end] = contaminated * original_rms / contaminated_rms
    noisy = spectral_reference.copy()
    random = np.random.default_rng(20260801)
    broadband = random.normal(size=len(noisy))
    broadband_spectrum = np.fft.rfft(broadband)
    broadband_frequencies = np.fft.rfftfreq(len(broadband), 1.0 / music_rate)
    broadband_spectrum[(broadband_frequencies < 55.0)
                       | (broadband_frequencies > 8000.0)] = 0.0
    broadband = np.fft.irfft(broadband_spectrum, len(broadband))
    broadband /= np.sqrt(np.mean(broadband * broadband))
    for start in range(4 * music_rate, len(noisy), block_size):
        end = min(start + block_size, len(noisy))
        block = spectral_reference[start:end]
        original_rms = float(np.sqrt(np.mean(block * block)))
        contaminated = block + original_rms * broadband[start:end]
        contaminated_rms = float(np.sqrt(np.mean(contaminated * contaminated)))
        noisy[start:end] = contaminated * original_rms / contaminated_rms
    for path, values in ((hf_reference_path, hf_reference),
                         (hf_hash_path, hf_hash),
                         (dropout_path, dropouts),
                         (held_path, held),
                         (replayed_path, replayed),
                         (spectral_reference_path, spectral_reference),
                         (spectral_jump_path, spectral_jumps),
                         (pitch_steps_path, pitch_steps),
                         (brightened_path, brightened),
                         (noisy_path, noisy),
                         (subrail_path, subrail_clipping),
                         (residual_bursts_path, residual_bursts)):
        pcm = np.clip(values, -32768.0, 32767.0).astype("<i2")
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(music_rate)
            wav.writeframes(pcm.tobytes())

    stereo_in_phase = np.column_stack((spectral_reference, spectral_reference))
    stereo_phase_flip = stereo_in_phase.copy()
    stereo_phase_flip[len(stereo_phase_flip) // 2:, 1] *= -1.0
    stereo_channel_loss = stereo_in_phase.copy()
    stereo_channel_loss[len(stereo_channel_loss) // 2:, 1] = 0.0
    for path, values in ((stereo_in_phase_path, stereo_in_phase),
                         (stereo_phase_flip_path, stereo_phase_flip),
                         (stereo_channel_loss_path, stereo_channel_loss)):
        pcm = np.clip(values, -32768.0, 32767.0).astype("<i2")
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(music_rate)
            wav.writeframes(pcm.tobytes())

    delay_rng = np.random.default_rng(20260803)
    delay_source = delay_rng.normal(size=8 * music_rate)
    delay_spectrum = np.fft.rfft(delay_source)
    delay_frequencies = np.fft.rfftfreq(len(delay_source), 1.0 / music_rate)
    delay_spectrum[(delay_frequencies < 55.0)
                   | (delay_frequencies > 8000.0)] = 0.0
    delay_source = np.fft.irfft(delay_spectrum, len(delay_source))
    delay_source *= 9000.0 / max(float(np.max(np.abs(delay_source))), 1.0)
    stereo_delay_reference = np.column_stack((delay_source, delay_source))
    stereo_delay_candidate = stereo_delay_reference.copy()
    delay_samples = round(0.002 * music_rate)
    delay_start = 4 * music_rate
    stereo_delay_candidate[delay_start:, 1] = delay_source[
        delay_start - delay_samples:-delay_samples]
    for path, values in (
            (stereo_delay_reference_path, stereo_delay_reference),
            (stereo_delay_candidate_path, stereo_delay_candidate)):
        pcm = np.clip(values, -32768.0, 32767.0).astype("<i2")
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(music_rate)
            wav.writeframes(pcm.tobytes())


def xterm_colour(index):
    """Resolve one xterm-256 palette index to RGB."""
    if index < 16:
        return PALETTE[index]
    if index < 232:
        value = index - 16
        levels = (0, 95, 135, 175, 215, 255)
        return (levels[value // 36], levels[(value // 6) % 6],
                levels[value % 6])
    grey = 8 + 10 * (index - 232)
    return grey, grey, grey


def apply_sgr(state, raw):
    """Apply one SGR sequence to a mutable ``[fg, bg, bold]`` state."""
    values = [int(value) if value else 0 for value in raw.split(";")]
    index = 0
    while index < len(values):
        code = values[index]
        if code == 0:
            state[:] = [FOREGROUND, BACKGROUND, False]
        elif code == 1:
            state[2] = True
        elif code == 22:
            state[2] = False
        elif 30 <= code <= 37:
            state[0] = PALETTE[code - 30 + (8 if state[2] else 0)]
        elif 90 <= code <= 97:
            state[0] = PALETTE[code - 90 + 8]
        elif 40 <= code <= 47:
            state[1] = PALETTE[code - 40]
        elif 100 <= code <= 107:
            state[1] = PALETTE[code - 100 + 8]
        elif code in (38, 48) and index + 2 < len(values):
            target = 0 if code == 38 else 1
            if values[index + 1] == 5:
                state[target] = xterm_colour(values[index + 2])
                index += 2
            elif values[index + 1] == 2 and index + 4 < len(values):
                state[target] = tuple(values[index + 2:index + 5])
                index += 4
        elif code == 39:
            state[0] = FOREGROUND
        elif code == 49:
            state[1] = BACKGROUND
        index += 1


def styled_lines(text):
    """Return lines of fixed terminal cells, including SGR weight."""
    output = []
    for line in text.rstrip("\n").splitlines():
        cells = []
        state = [FOREGROUND, BACKGROUND, False]
        cursor = 0
        for match in ANSI.finditer(line):
            cells.extend((char, state[0], state[1], state[2])
                         for char in line[cursor:match.start()])
            apply_sgr(state, match.group(1))
            cursor = match.end()
        cells.extend((char, state[0], state[1], state[2])
                     for char in line[cursor:])
        output.append(cells)
    return output


def load_fonts():
    """Load the exact Fira Code faces used by deterministic documentation."""
    missing = [path for path in (FONT_REGULAR, FONT_BOLD) if not path.is_file()]
    if missing:
        names = ", ".join(str(path) for path in missing)
        raise RuntimeError(
            f"missing Fira Code screenshot font(s): {names}; "
            "install Fira Code Retina and Bold before regenerating captures")
    for path, expected in ((FONT_REGULAR, FONT_REGULAR_SHA256),
                           (FONT_BOLD, FONT_BOLD_SHA256)):
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError(
                f"unexpected Fira Code font revision: {path} has SHA-256 "
                f"{actual}, expected {expected}")
    regular = ImageFont.truetype(FONT_REGULAR, FONT_SIZE)
    bold = ImageFont.truetype(FONT_BOLD, FONT_SIZE)
    for name, font in (("Retina", regular), ("Bold", bold)):
        advance = font.getlength("M")
        if not 19.0 <= advance <= 20.0:
            raise RuntimeError(
                f"Fira Code {name} advance {advance:.3f}px does not fit the "
                f"declared {CELL_WIDTH}px terminal cell")
    return regular, bold


def render_ansi(text, path):
    """Render ANSI directly to a deterministic Retina-density PNG.

    The 20x40 physical-pixel cell is a 10x20 logical terminal cell at 2x.
    Every baseline, background rectangle, and glyph origin is integer-aligned;
    Fira Code's box glyphs overlap cell edges so rules remain connected.
    """
    lines = styled_lines(text)
    regular, bold = load_fonts()
    ascent, _ = regular.getmetrics()
    columns = max((len(line) for line in lines), default=1)
    image = Image.new(
        "RGB", (2 * PADDING + columns * CELL_WIDTH,
                2 * PADDING + max(1, len(lines)) * CELL_HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for row, line in enumerate(lines):
        top = PADDING + row * CELL_HEIGHT
        baseline = top + ascent
        for column, (char, foreground, background, is_bold) in enumerate(line):
            x = PADDING + column * CELL_WIDTH
            if background != BACKGROUND:
                draw.rectangle(
                    (x, top, x + CELL_WIDTH - 1, top + CELL_HEIGHT - 1),
                    fill=background)
            if char != " ":
                draw.text((x, baseline), char, font=bold if is_bold else regular,
                          fill=foreground, anchor="ls")
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("Software", "render-audio-analysis-screenshots.py")
    metadata.add_text("Font", "Fira Code Retina/Bold 32 px")
    metadata.add_text("TerminalCell", "20x40 physical px; 10x20 logical px at 2x")
    metadata.add_text("Capture", "direct PNG, 144 DPI, no SVG intermediate")
    image.save(path, optimize=True, compress_level=9,
               dpi=(PNG_DPI, PNG_DPI), pnginfo=metadata)


def main():
    cli = ROOT / "tools/audio_analysis.py"
    prepare_artifact_fixtures()
    environment = os.environ.copy()
    environment["COLORTERM"] = "truecolor"
    environment.pop("NO_COLOR", None)
    missing = sorted({argument for _, arguments in CAPTURES
                      for argument in arguments
                      if argument.endswith(".wav")
                      and not (ROOT / argument).exists()})
    if missing:
        print("missing screenshot source WAV(s):", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 3
    for filename, arguments in CAPTURES:
        process = subprocess.run(
            [sys.executable, str(cli), *arguments], cwd=ROOT,
            env=environment, capture_output=True, text=True)
        if process.returncode not in (0, 1):
            sys.stderr.write(process.stderr)
            return process.returncode
        json.loads(process.stdout)
        if not process.stderr.startswith(("view comparison:", "view input:")):
            raise RuntimeError("expected terminal view diagnostics on stderr")
        destination = OUTPUT / filename
        render_ansi(process.stderr, destination)
        print(destination.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
