#!/usr/bin/env python3
"""Regression tests for the shared audio-analysis library and CLI."""
from __future__ import annotations

import json
import io
import re
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import audio_analysis as check
import _audio_analysis_cli as check_cli
from _audio_analysis_terminal import (
    TerminalGeometry,
    TerminalPanel,
    coherence_grid,
    compose,
    flatline_ratio,
    intersample_peak_dbfs,
    intersample_peak_estimate,
    low_frequency_peak,
    low_frequency_ruler,
    low_frequency_spectrogram,
    modulation_peak,
    modulation_ruler,
    modulation_spectrogram,
    phase_difference_grid,
    peak_occupancy_percent,
    rail_ratio_percent,
    render_band_delta,
    render_block_repeats,
    render_contour,
    render_crest_factors,
    render_dc_offsets,
    render_derivative_ratios,
    render_flatline_ratios,
    render_intersample_peaks,
    render_metrics,
    render_low_frequency_spectra,
    render_modulation_spectra,
    render_level_delta,
    render_pitch_delta,
    render_pitch_tracks,
    render_peak_occupancy,
    render_phase_diff,
    render_quantization_steps,
    render_rail_ratios,
    render_residual_ratio,
    render_rms_levels,
    render_sample_density,
    render_spectral_changes,
    render_spectral_centroids,
    render_spectral_flatness,
    render_spectral_diff,
    render_spectral_coherence,
    render_stereo_balances,
    render_stereo_coherences,
    render_stereo_correlations,
    render_stereo_delays,
    render_stereo_level_diffs,
    render_stereo_phases,
    render_timing_drift,
    render_wave_correlation,
    render_waveforms,
    spectral_change_series,
    spectral_flatness_series,
    stereo_balance_db,
    stereo_delay_observation,
    residual_ratio_db,
    visible_width,
    waveform_correlation,
)
import psg_track_gate as track_gate


SCHEMA_PATH = ROOT / "docs/schemas/audio-analysis-v2.schema.json"


def validate_schema(instance, schema, *, root=None, path="$"):
    """Validate the JSON-Schema subset used by the checked contract artifact."""
    root = schema if root is None else root
    if "$ref" in schema:
        target = root
        for part in schema["$ref"].removeprefix("#/").split("/"):
            target = target[part.replace("~1", "/").replace("~0", "~")]
        return validate_schema(instance, target, root=root, path=path)
    if "oneOf" in schema:
        matches = 0
        errors = []
        for option in schema["oneOf"]:
            try:
                validate_schema(instance, option, root=root, path=path)
                matches += 1
            except AssertionError as error:
                errors.append(str(error))
        assert matches == 1, f"{path}: matched {matches} oneOf branches: {errors}"
        return
    if "const" in schema:
        assert instance == schema["const"], f"{path}: expected {schema['const']!r}"
    if "enum" in schema:
        assert instance in schema["enum"], f"{path}: {instance!r} not in enum"

    expected = schema.get("type")
    if expected is not None:
        expected = [expected] if isinstance(expected, str) else expected

        def has_type(name):
            checks = {
                "null": instance is None,
                "boolean": isinstance(instance, bool),
                "integer": isinstance(instance, int) and not isinstance(instance, bool),
                "number": (isinstance(instance, (int, float))
                           and not isinstance(instance, bool)),
                "string": isinstance(instance, str),
                "array": isinstance(instance, list),
                "object": isinstance(instance, dict),
            }
            return checks[name]

        assert any(has_type(name) for name in expected), (
            f"{path}: {type(instance).__name__} is not {expected}")

    if isinstance(instance, dict):
        for key in schema.get("required", []):
            assert key in instance, f"{path}: missing required property {key!r}"
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extra = set(instance) - set(properties)
            assert not extra, f"{path}: unexpected properties {sorted(extra)}"
        for key, value in instance.items():
            if key in properties:
                validate_schema(value, properties[key], root=root,
                                path=f"{path}.{key}")
    if isinstance(instance, list):
        assert len(instance) >= schema.get("minItems", 0), f"{path}: too few items"
        if "items" in schema:
            for index, value in enumerate(instance):
                validate_schema(value, schema["items"], root=root,
                                path=f"{path}[{index}]")
    if isinstance(instance, str) and "pattern" in schema:
        assert re.search(schema["pattern"], instance), f"{path}: pattern mismatch"
    if (isinstance(instance, (int, float)) and not isinstance(instance, bool)
            and "minimum" in schema):
        assert instance >= schema["minimum"], f"{path}: below minimum"


def band_noise(seed: int, lo_hz: float, hi_hz: float, seconds: int = 10):
    """Deterministic unit-RMS noise restricted to one frequency band."""
    rng = np.random.default_rng(seed)
    samples = rng.normal(size=check.RATE * seconds)
    spectrum = np.fft.rfft(samples)
    freqs = np.fft.rfftfreq(len(samples), 1 / check.RATE)
    spectrum[(freqs < lo_hz) | (freqs >= hi_hz)] = 0
    result = np.fft.irfft(spectrum, len(samples))
    return result / np.sqrt(np.mean(result ** 2))


def swept_noise_pair():
    """Equal-RMS pair whose candidate retains too much 4-8 kHz energy."""
    samples = check.RATE * 10
    time = np.arange(samples) / check.RATE
    # Repeated deep troughs make the quiet-window selection observable without
    # hard-coding their timestamps in the comparison.
    envelope = 0.15 + 0.85 * (0.5 + 0.5 * np.cos(2 * np.pi * time / 4.0))
    low = band_noise(1, 55, 250)
    middle = band_noise(2, 250, 4000)
    high = band_noise(3, 4000, 8000)
    reference = envelope * (low + 0.45 * middle + 0.18 * high)
    candidate = envelope * (low + 0.45 * middle + 0.40 * high)
    candidate *= np.sqrt(np.mean(reference ** 2) / np.mean(candidate ** 2))
    return reference, candidate


def write_wav(path: Path, samples, gain=None):
    peak = max(float(np.max(np.abs(samples))), 1.0)
    gain = 12000.0 / peak if gain is None else gain
    pcm = np.clip(np.rint(samples * gain), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(check.RATE)
        wav.writeframes(pcm.tobytes())


def write_cart_png(path: Path, rom: bytes):
    payload = bytes(rom).ljust(0x8000, b"\0")[:0x8000]
    pixels = [((value >> 4) & 3, (value >> 2) & 3, value & 3,
               (value >> 6) & 3) for value in payload]
    image = Image.new("RGBA", (128, 256))
    image.putdata(pixels)
    image.save(path)


def run_cli(*args, input_bytes=None):
    return subprocess.run(
        [sys.executable, str(ROOT / "tools/audio_analysis.py"), *map(str, args)],
        cwd=ROOT, input=input_bytes, capture_output=True,
        text=input_bytes is None)


class WavInputTests(unittest.TestCase):
    def test_8_bit_stereo_is_centered_and_mixed_to_mono(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stereo.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(2)
                wav.setsampwidth(1)
                wav.setframerate(check.RATE)
                wav.writeframes(bytes((128, 130, 132, 134)))
            samples = check.load_wav(path)
        np.testing.assert_array_equal(samples, np.array((256.0, 1280.0)))

    def test_loaded_audio_retains_channels_without_changing_mono_mix(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stereo.wav"
            expected_channels = np.array(
                ((100, -100), (300, 100), (-500, 100)), dtype="<i2")
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(2)
                wav.setsampwidth(2)
                wav.setframerate(check.RATE)
                wav.writeframes(expected_channels.tobytes())
            loaded = check.load_audio(path)
            compatibility_mix = check.load_wav(path)
        self.assertEqual(loaded.channel_count, 2)
        np.testing.assert_array_equal(
            loaded.channel_samples, expected_channels.astype(np.float64))
        np.testing.assert_array_equal(loaded.samples, (0.0, 200.0, -200.0))
        np.testing.assert_array_equal(compatibility_mix, loaded.samples)

    def test_wrong_sample_rate_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "wrong-rate.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(44100)
                wav.writeframes(np.zeros(16, dtype="<i2").tobytes())
            with self.assertRaisesRegex(ValueError, "44100 Hz, expected 22050"):
                check.load_wav(path)

    def test_exact_pcm_loader_preserves_signed_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "exact.wav"
            expected = np.array((-32768, -1, 0, 1, 32767), dtype="<i2")
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(check.RATE)
                wav.writeframes(expected.tobytes())
            actual = check.load_pcm16_mono(path)
        np.testing.assert_array_equal(actual, expected)
        self.assertEqual(actual.dtype, np.dtype("<i2"))

    def test_exact_pcm_loader_rejects_format_coercion(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stereo.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(2)
                wav.setsampwidth(2)
                wav.setframerate(check.RATE)
                wav.writeframes(np.zeros(8, dtype="<i2").tobytes())
            with self.assertRaisesRegex(ValueError, "expected mono 16-bit PCM"):
                check.load_pcm16_mono(path)


class SharedMetricTests(unittest.TestCase):
    def test_pitch_agreement_uses_the_shared_pitch_estimator(self):
        time = np.arange(check.RATE) / check.RATE
        tone = 4000.0 * np.sin(2 * np.pi * 220.0 * time)
        result = check.pitch_agreement(tone, tone.copy())
        self.assertGreater(result.compared, 0)
        self.assertEqual(result.agreed, result.compared)
        self.assertEqual(result.ratio, 1.0)

    def test_common_noise_metrics_match_direct_definitions(self):
        samples = np.array((0.0, 1.0, 1.0, -1.0, -1.0))
        self.assertAlmostEqual(check.rms(samples),
                               float(np.sqrt(np.mean(samples ** 2))))
        self.assertEqual(check.repeat_rate(samples), 0.5)

    def test_frequency_ruler_is_exact_width_with_non_overlapping_labels(self):
        edges = np.array((55.0, check.RATE / 2.0))
        allowed = {check.hz_label(55 * 2 ** octave)
                   for octave in range(9)}
        for width in (16, 20, 24, 32):
            with self.subTest(width=width):
                axis, labels = check.ruler(edges, width)
                self.assertEqual(len(axis), width)
                self.assertEqual(len(labels), width)
                matches = list(re.finditer(r"\S+", labels))
                self.assertTrue(matches)
                self.assertTrue({match.group() for match in matches} <= allowed)
                for index, match in enumerate(matches):
                    self.assertEqual(axis[match.start()], "┬")
                    if index:
                        self.assertGreater(match.start(), matches[index - 1].end())


class TerminalCompositionTests(unittest.TestCase):
    def test_plot_axis_is_separate_from_footer_text_in_columns(self):
        geometry = TerminalGeometry(0.0, 2.0, 2, 16,
                                    "columns", "first", False)
        panels = (
            TerminalPanel("plain", ("a", "b"), ("legend text",)),
            TerminalPanel("ticks", ("c", "d"), ("55       440",),
                          "─┬───────┬──────"),
        )
        rendered = compose(panels, geometry)
        axis_row = next(line for line in rendered if "0.0s└" in line)
        footer_row = next(line for line in rendered if "legend text" in line)
        self.assertIn("└" + "─" * 16, axis_row)
        self.assertIn("─┬───────┬──────", axis_row)
        self.assertNotIn("legend", axis_row)
        self.assertNotIn("└legend", footer_row)
        self.assertEqual(visible_width(axis_row), 8 + 16 + 3 + 16)
        self.assertEqual(visible_width(footer_row), 8 + 16 + 3 + 16)

    def test_plot_axis_is_separate_from_footer_text_in_rows(self):
        geometry = TerminalGeometry(0.0, 1.0, 1, 16,
                                    "rows", "each", False)
        rendered = compose(
            (TerminalPanel("plain", ("data",), ("legend text",)),), geometry)
        self.assertIn("   0.0s└" + "─" * 16, rendered)
        self.assertIn(" " * 8 + "legend text".ljust(16), rendered)
        self.assertNotIn("└legend", "\n".join(rendered))


class ClickAnalysisTests(unittest.TestCase):
    def test_smooth_tone_has_no_clicks(self):
        time = np.arange(check.RATE * 2) / check.RATE
        tone = 8000.0 * np.sin(2 * np.pi * 220.0 * time)
        result = check.analyze_clicks(tone)
        self.assertTrue(result.passed)
        self.assertEqual(result.event_count, 0)
        self.assertEqual(result.as_dict()["policy"]["profile_id"], "click-v1")

    def test_periodic_square_pulse_and_saw_edges_are_not_clicks(self):
        time = np.arange(check.RATE * 2) / check.RATE
        for frequency in (65.0, 220.0):
            phase = (frequency * time) % 1.0
            signals = {
                "square": np.where(phase < 0.5, 8000.0, -8000.0),
                "pulse": np.where(phase < 0.25, 8000.0, -8000.0),
                "saw": 8000.0 * (2.0 * phase - 1.0),
            }
            for waveform, samples in signals.items():
                with self.subTest(frequency=frequency, waveform=waveform):
                    result = check.analyze_clicks(samples)
                    self.assertEqual(result.event_count, 0)
                    self.assertGreater(result.suppressed_periodic_edge_count, 0)

    def test_single_impulse_is_one_timestamped_event(self):
        time = np.arange(check.RATE * 2) / check.RATE
        samples = 8000.0 * np.sin(2 * np.pi * 220.0 * time)
        samples[check.RATE] += 6000.0
        result = check.analyze_clicks(samples)
        self.assertFalse(result.passed)
        self.assertEqual(result.event_count, 1)
        event = result.events[0]
        self.assertEqual(event.sample_index, check.RATE)
        self.assertEqual(event.time_seconds, 1.0)
        self.assertGreater(event.severity_ratio, 8.0)

    def test_phase_resets_every_100ms_remain_sparse_clicks(self):
        samples = check.RATE * 2
        candidate = np.empty(samples)
        random = np.random.default_rng(9)
        for start in range(0, samples, check.RATE // 10):
            stop = min(start + check.RATE // 10, samples)
            time = np.arange(stop - start) / check.RATE
            candidate[start:stop] = 8000.0 * np.sin(
                2 * np.pi * 220.0 * time + random.uniform(0, 2 * np.pi))
        result = check.analyze_clicks(candidate)
        self.assertGreater(result.event_count, 5)

    def test_event_time_uses_explicit_sample_rate(self):
        samples = np.zeros(88200)
        samples[44100] = 2000.0
        result = check.analyze_clicks(samples, rate=44100)
        self.assertEqual(result.events[0].time_seconds, 1.0)
        self.assertEqual(result.sample_rate_hz, 44100)

    def test_8_bit_scale_step_exceeds_the_explicit_absolute_floor(self):
        samples = np.concatenate((np.zeros(1000), np.full(1000, 100.0)))
        result = check.analyze_clicks(samples)
        self.assertEqual(result.event_count, 1)
        self.assertEqual(result.events[0].delta_pcm, 100.0)

    def test_reference_matched_event_is_not_a_comparison_artifact(self):
        samples = np.zeros(check.RATE * 2)
        samples[check.RATE] = 2000.0
        matched = check.compare_clicks(
            samples, samples.copy(), maximum_unmatched_events=0)
        self.assertTrue(matched.passed)
        self.assertEqual(matched.matched_event_count, 1)
        self.assertEqual(matched.unmatched_event_count, 0)

    def test_event_detail_limit_retains_total_and_truncation_state(self):
        samples = np.zeros(check.RATE * 5)
        for index in range(40):
            samples[1000 + index * (check.RATE // 10)] = 2000.0
        data = check.analyze_clicks(samples).as_dict()
        self.assertEqual(data["event_count"], 40)
        self.assertEqual(data["reported_event_count"], 32)
        self.assertEqual(len(data["events"]), 32)
        self.assertTrue(data["events_truncated"])


class SfxAnalysisTests(unittest.TestCase):
    def test_energy_and_applicable_pitch_share_one_row_report(self):
        rom = bytearray(0x4300)
        base = 0x3200
        rom[base + 65] = 1

        def set_row(index, pitch, wave_index, volume, effect=0):
            word = (pitch | (wave_index << 6) | (volume << 9)
                    | (effect << 12))
            rom[base + 2 * index:base + 2 * index + 2] = word.to_bytes(2, "little")

        set_row(0, 33, 3, 7)       # stable A4: pitch applies
        set_row(1, 33, 6, 7)       # noise: pitch is intentionally n/a
        set_row(2, 33, 3, 7, 1)    # slide: pitch is intentionally n/a
        set_row(3, 33, 3, 0)       # silent request with an injected leak

        samples = np.zeros(32 * check.SAMPLES_PER_TICK)
        phase = np.arange(check.SAMPLES_PER_TICK) / check.RATE
        tone = 1000.0 * np.sin(2 * np.pi * 440.0 * phase)
        samples[0:check.SAMPLES_PER_TICK] = tone
        samples[check.SAMPLES_PER_TICK:2 * check.SAMPLES_PER_TICK] = \
            np.random.default_rng(1).normal(0, 1000, check.SAMPLES_PER_TICK)
        samples[2 * check.SAMPLES_PER_TICK:3 * check.SAMPLES_PER_TICK] = tone
        samples[3 * check.SAMPLES_PER_TICK:4 * check.SAMPLES_PER_TICK] = tone

        result = check.analyze_sfx(samples, rom, 0)
        self.assertEqual(result.rows[0].pitch_verdict, "ok")
        self.assertEqual(result.rows[1].pitch_verdict, "n/a")
        self.assertEqual(result.rows[2].pitch_verdict, "n/a")
        self.assertEqual(result.rows[3].energy_verdict, "leak")

        output = io.StringIO()
        self.assertFalse(check.report_sfx_analysis(result, out=output))
        self.assertIn("LEAK", output.getvalue())
        self.assertIn("applicable rows within pitch tolerance", output.getvalue())


class BandBalanceTests(unittest.TestCase):
    def test_band_analysis_retains_local_windows_without_changing_aggregates(self):
        reference, candidate = swept_noise_pair()
        aggregates, observations = check.band_analysis(reference, candidate)
        self.assertEqual(aggregates, check.band_balance(reference, candidate))
        self.assertGreater(len(observations), 1)
        self.assertTrue(any(item.quiet_reference for item in observations))
        self.assertTrue(any(
            item.deltas_db[3] is not None and item.deltas_db[3] > 0
            for item in observations))

    def test_equal_rms_does_not_hide_high_frequency_excess(self):
        reference, candidate = swept_noise_pair()
        rms_db = 20 * np.log10(np.sqrt(np.mean(candidate ** 2))
                               / np.sqrt(np.mean(reference ** 2)))
        self.assertAlmostEqual(rms_db, 0.0, places=6)

        results = {row.label: row for row in
                   check.band_balance(reference, candidate)}
        high = results["4-8 kHz"]
        self.assertGreater(high.whole_db, check.BAND_TOL_DB)
        self.assertGreater(high.quiet_db, check.BAND_TOL_DB)
        self.assertEqual(high.failures(), ["whole", "quiet"])

    def test_identical_audio_passes_every_band(self):
        reference, _ = swept_noise_pair()
        for result in check.band_balance(reference, reference.copy()):
            self.assertAlmostEqual(result.whole_db, 0.0, places=9)
            self.assertAlmostEqual(result.local_db, 0.0, places=9)
            if result.quiet_db is not None:
                self.assertAlmostEqual(result.quiet_db, 0.0, places=9)
            self.assertEqual(result.failures(), [])

    def test_quiet_passages_can_fail_when_whole_track_average_passes(self):
        reference, _ = swept_noise_pair()
        time = np.arange(len(reference)) / check.RATE
        envelope = 0.15 + 0.85 * (0.5 + 0.5 * np.cos(2 * np.pi * time / 4.0))
        quiet_gate = np.clip((0.5 - envelope) / 0.35, 0.0, 1.0)
        candidate = reference + 0.08 * quiet_gate * band_noise(9, 4000, 8000)
        candidate *= np.sqrt(np.mean(reference ** 2) / np.mean(candidate ** 2))

        results = {row.label: row for row in
                   check.band_balance(reference, candidate)}
        high = results["4-8 kHz"]
        self.assertLess(abs(high.whole_db), check.BAND_TOL_DB)
        self.assertGreater(high.quiet_db, check.BAND_TOL_DB)
        self.assertEqual(high.failures(), ["quiet"])

    def test_inactive_bands_do_not_create_meaningless_failures(self):
        time = np.arange(check.RATE * 4) / check.RATE
        tone = np.sin(2 * np.pi * 220 * time)
        results = check.band_balance(tone, tone.copy())
        self.assertEqual(results[0].failures(), [])
        for result in results[1:]:
            self.assertIsNone(result.whole_db)
            self.assertEqual(result.failures(), [])

    def test_noise_alignment_uses_the_power_envelope(self):
        reference, _ = swept_noise_pair()
        delay = 7 * check.ENVELOPE_HOP
        candidate = np.concatenate((np.zeros(delay), reference[:-delay]))
        self.assertLessEqual(abs(check.align_envelope(reference, candidate) - delay),
                             check.ENVELOPE_HOP)


class ComparisonPolicyTests(unittest.TestCase):
    def test_unpitched_result_retains_the_verdict_contour_observations(self):
        reference, candidate = swept_noise_pair()
        result = check.analyze_comparison(reference, candidate, "noise")
        self.assertFalse(result.data["pitched_reference"])
        self.assertTrue(all(
            item.reference_contour_centroid_hz is not None
            and item.candidate_contour_centroid_hz is not None
            for item in result.windows))
        expected = check.contour(reference, result.shifted_candidate)
        self.assertAlmostEqual(
            result.data["contour"]["loudness_correlation"], expected[0])
        self.assertAlmostEqual(
            result.data["contour"]["timbre_correlation"], expected[1])
        self.assertGreater(len(result.band_observations), 1)

        geometry = TerminalGeometry(0.0, 10.0, 10, 24,
                                    "columns", "none", False)
        panels = render_contour(result, geometry)
        self.assertEqual(len(panels), 2)
        self.assertIn("full corr", panels[0].footer[-1])
        self.assertTrue(any("◆" in row for row in panels[0].rows))
        band_panel = render_band_delta(result, geometry)
        self.assertTrue(any("q " in row for row in band_panel.rows))
        self.assertTrue(any("U>" in row for row in band_panel.rows))
        self.assertIn("W whole Q quiet", band_panel.footer)

    def test_full_track_profile_rejects_audible_phase_resets(self):
        samples = check.RATE * 4
        reference = 8000.0 * np.sin(
            2 * np.pi * 220.0 * np.arange(samples) / check.RATE)
        candidate = np.empty(samples)
        random = np.random.default_rng(7)
        for start in range(0, samples, check.WINDOW):
            stop = min(start + check.WINDOW, samples)
            time = np.arange(stop - start) / check.RATE
            candidate[start:stop] = 8000.0 * np.sin(
                2 * np.pi * 220.0 * time + random.uniform(0, 2 * np.pi))

        stdout = io.StringIO()
        old_stdout = sys.stdout
        try:
            sys.stdout = stdout
            result = check.analyze_comparison(reference, candidate, "phase-reset")
        finally:
            sys.stdout = old_stdout

        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.score, 1.0)
        self.assertIn("spectrum", result.data["failure_types"])
        self.assertIn("lock", result.data["failure_types"])
        self.assertLess(result.data["lock"]["tracked_ratio"], 0.2)
        self.assertEqual(len(result.lock_observations),
                         result.data["lock"]["block_count"])

        compatibility = check.analyze_comparison(
            reference, candidate, "phase-reset", policy="pitch-band-v1")
        self.assertEqual(compatibility.status, "ok")

        with tempfile.TemporaryDirectory() as directory:
            reference_path = Path(directory) / "reference.wav"
            candidate_path = Path(directory) / "candidate.wav"
            write_wav(reference_path, reference, gain=1.0)
            write_wav(candidate_path, candidate, gain=1.0)
            process = run_cli(
                "--output", "json", "wav", "compare",
                reference_path, candidate_path)
        self.assertEqual(process.returncode, check.EXIT_FAILURE, process.stderr)
        payload = json.loads(process.stdout)
        self.assertEqual(payload["policy"]["profile_id"], "full-track-v2")
        self.assertEqual(payload["candidates"][0]["score"], 1.0)
        self.assertEqual(payload["candidates"][0]["status"], "failed")
        self.assertIn("lock", payload["candidates"][0]["failure_types"])
        self.assertIn("clicks", payload["candidates"][0]["failure_types"])

    def test_full_track_v1_reports_clicks_without_changing_legacy_verdict(self):
        samples = check.RATE * 8
        time = np.arange(samples) / check.RATE
        reference = 8000.0 * np.sin(2 * np.pi * 220.0 * time)
        candidate = reference.copy()
        candidate[4 * check.RATE] += 4000.0

        current = check.analyze_comparison(
            reference, candidate, policy="full-track-v2")
        legacy = check.analyze_comparison(
            reference, candidate, policy="full-track-v1")
        self.assertEqual(current.data["failure_types"], ["clicks"])
        self.assertEqual(current.data["clicks"]["unmatched_event_count"], 1)
        self.assertEqual(legacy.status, "ok")
        self.assertEqual(legacy.data["failure_types"], [])
        self.assertEqual(legacy.data["clicks"]["unmatched_event_count"], 1)
        self.assertIsNone(
            legacy.data["policy"]["clicks"]["maximum_unmatched_events"])

    def test_policy_json_contains_every_threshold_group(self):
        policy = check.DEFAULT_POLICY.as_dict()
        self.assertEqual(policy["profile_id"], "full-track-v2")
        self.assertEqual(
            set(policy),
            {"profile_id", "description", "score", "reference", "pitch",
             "level", "spectrum", "bands", "lock", "clicks"})
        self.assertEqual(policy["clicks"]["detection"]["profile_id"],
                         "click-v1")
        self.assertEqual(policy["clicks"]["maximum_unmatched_events"], 0)

    def test_metric_view_uses_uncapped_click_events(self):
        """Presentation must not inherit the 32-event JSON detail cap."""
        events = tuple(
            check.ClickEvent(index, 0.5, 1000.0, 10.0, 100.0)
            for index in range(40))
        empty = check.ClickAnalysis(check.CLICK_V1, check.RATE, 0, 0, 0, ())
        candidate = check.ClickAnalysis(
            check.CLICK_V1, check.RATE, 40, 40, 0, events)
        clicks = check.ClickComparison(empty, candidate, 8, 0, 0, events)
        data = {
            "label": "candidate",
            "policy": check.DEFAULT_POLICY.as_dict(),
            # Deliberately empty: this public detail array may be capped.
            "clicks": {"unmatched_events": []},
        }
        window = check.ComparisonWindow(0, 220.0, 220.0, 100.0, 100.0,
                                        1.0, True)
        result = check.ComparisonResult(
            data, (window,), np.zeros(check.WINDOW),
            np.zeros(check.WINDOW), clicks)
        geometry = TerminalGeometry(0.0, 1.0, 1, 16, "rows", "none", False)
        rendered = render_metrics(result, geometry)
        self.assertIn("C:+", rendered.rows[0])

    def test_pitch_delta_preserves_error_direction_and_scale(self):
        empty = check.ClickAnalysis(check.CLICK_V1, check.RATE, 0, 0, 0, ())
        clicks = check.ClickComparison(empty, empty, 8, 0, 0, ())
        data = {"label": "candidate", "policy": check.DEFAULT_POLICY.as_dict(),
                "pitched_reference": True}
        windows = (
            check.ComparisonWindow(0, 220.0, 440.0, 100.0, 100.0,
                                   1.0, False),
            check.ComparisonWindow(1, 220.0, 110.0, 100.0, 100.0,
                                   1.0, False),
        )
        result = check.ComparisonResult(
            data, windows, np.zeros(2 * check.WINDOW),
            np.zeros(2 * check.WINDOW), clicks)
        geometry = TerminalGeometry(
            0.0, 2 * check.WINDOW / check.RATE, 2, 16,
            "rows", "none", False)
        rendered = render_pitch_delta(result, geometry)
        self.assertEqual(rendered.footer[1], "scale ±12.00 st")
        self.assertEqual(rendered.rows[0].index("•"), 0)
        self.assertEqual(rendered.rows[1].index("•"), 15)

        contour_panels = render_contour(result, geometry)
        self.assertEqual(contour_panels[0].footer,
                         ("not applicable: pitched",))

    def test_level_delta_preserves_quieter_and_louder_direction(self):
        empty = check.ClickAnalysis(check.CLICK_V1, check.RATE, 0, 0, 0, ())
        clicks = check.ClickComparison(empty, empty, 8, 0, 0, ())
        data = {"label": "candidate", "policy": check.DEFAULT_POLICY.as_dict()}
        windows = (
            check.ComparisonWindow(0, 220.0, 220.0, 100.0, 200.0,
                                   1.0, True),
            check.ComparisonWindow(1, 220.0, 220.0, 100.0, 50.0,
                                   1.0, True),
        )
        result = check.ComparisonResult(
            data, windows, np.zeros(2 * check.WINDOW),
            np.zeros(2 * check.WINDOW), clicks)
        geometry = TerminalGeometry(
            0.0, 2 * check.WINDOW / check.RATE, 2, 16,
            "rows", "none", False)
        rendered = render_level_delta(result, geometry)
        self.assertEqual(rendered.footer[1], "scale ±6.02 dB")
        self.assertTrue(rendered.rows[0].startswith("! "))
        self.assertTrue(rendered.rows[1].startswith("! "))
        self.assertEqual(rendered.rows[0].index("•"), 2)
        self.assertEqual(rendered.rows[1].index("•"), 15)

    def test_timing_drift_marks_weak_or_outside_blocks(self):
        empty = check.ClickAnalysis(check.CLICK_V1, check.RATE, 0, 0, 0, ())
        clicks = check.ClickComparison(empty, empty, 8, 0, 0, ())
        data = {
            "label": "candidate",
            "policy": check.DEFAULT_POLICY.as_dict(),
            "lock": {"modal_lag_samples": 100},
        }
        observations = (
            check.LockObservation(0.0, 0.5, 108, 0.9),
            check.LockObservation(0.5, 0.5, 132, 0.9),
        )
        result = check.ComparisonResult(
            data, (), np.zeros(check.RATE), np.zeros(check.RATE), clicks,
            observations)
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "rows", "none", False)
        rendered = render_timing_drift(result, geometry)
        self.assertTrue(rendered.rows[0].startswith("! "))
        self.assertTrue(rendered.rows[1].startswith("· "))
        self.assertEqual(rendered.footer[2], "guard ±0.36 ms")
        self.assertEqual(rendered.footer[3], "mode +100 samples")

    def test_waveform_panels_share_scale_and_report_pcm_rails(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        panels = render_waveforms([
            ("reference", np.array([-1000.0, 1000.0])),
            ("candidate", np.array([-32768.0, 32767.0])),
        ], geometry)
        self.assertEqual(len(panels), 2)
        self.assertEqual(panels[0].footer[1], "scale ±32768 PCM")
        self.assertEqual(panels[1].footer[1], "scale ±32768 PCM")
        self.assertEqual(panels[0].footer[3], "rail samples 0")
        self.assertEqual(panels[1].footer[3], "rail samples 2")

    def test_rms_level_keeps_exact_silence_visible(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        audible = np.full(16, 32768.0)
        silence = np.zeros(16)
        panel = render_rms_levels([
            ("candidate", np.concatenate((audible, silence))),
        ], geometry)[0]
        self.assertEqual(panel.rows[0][0], "<")
        self.assertEqual(panel.rows[1][-1], ">")
        self.assertEqual(panel.footer[1], "fixed -96..0 dBFS")
        self.assertIn("row min -inf dBFS", panel.footer)
        self.assertEqual(panel.footer[-1], "selected RMS -3.01 dBFS")

    def test_rail_ratio_distinguishes_presence_from_prevalence(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        clean = np.arange(16, dtype=np.float64)
        saturated = np.concatenate((np.full(8, 32767.0), np.zeros(8)))
        panel = render_rail_ratios([
            ("candidate", np.concatenate((clean, saturated))),
        ], geometry)[0]
        self.assertIn("●", panel.rows[0])
        self.assertEqual(panel.rows[1][0], "•")
        self.assertEqual(panel.footer[1], "log scale 1 ppm..100%")
        self.assertEqual(panel.footer[-3], "row max 50.0000%")
        self.assertEqual(panel.footer[-2], "selected rails 8/32")
        self.assertEqual(panel.footer[-1], "selected ratio 25.0000%")

    def test_quantization_step_exposes_a_coarse_pcm_lattice(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        clean = np.arange(16, dtype=np.float64)
        quantized = np.tile(np.arange(-4, 4) * 1024.0, 2)
        panel = render_quantization_steps([
            ("candidate", np.concatenate((clean, quantized))),
        ], geometry)[0]
        self.assertIn("●", panel.rows[0])
        self.assertEqual(panel.rows[1][0], "•")
        self.assertEqual(panel.footer[1], "log2 scale 1..32768 PCM")
        self.assertEqual(panel.footer[-2], "row max 1024 PCM")
        self.assertEqual(panel.footer[-1], "selected step 1 PCM")

        constant = render_quantization_steps([
            ("constant", np.ones(32)),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in constant.rows))

    def test_spectral_change_exposes_an_abrupt_timbre_replacement(self):
        count = 4096
        phase = np.arange(count, dtype=np.float64)
        low = np.sin(2.0 * np.pi * 32.0 * phase / 1024.0)
        high = np.sin(2.0 * np.pi * 128.0 * phase / 1024.0)
        switched = np.concatenate((low[:count // 2], high[count // 2:]))
        _, steady_changes = spectral_change_series(low)
        _, switched_changes = spectral_change_series(switched)
        self.assertLess(float(np.nanmax(steady_changes)), 1e-6)
        self.assertGreater(float(np.nanmax(switched_changes)), 0.35)

        geometry = TerminalGeometry(0.0, count / check.RATE, 2, 16,
                                    "columns", "none", False)
        panel = render_spectral_changes([
            ("candidate", switched),
        ], geometry)[0]
        self.assertEqual(panel.footer[1], "1024 Hann / 512 hop")
        self.assertIn("row max", panel.footer[-2])
        self.assertIn("selected max", panel.footer[-1])

        silence = render_spectral_changes([
            ("silence", np.zeros(count)),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in silence.rows))

    def test_pitch_track_shows_steps_and_blanks_unvoiced_rows(self):
        phase = np.arange(check.WINDOW, dtype=np.float64) / check.RATE
        low = 8000.0 * np.sin(2.0 * np.pi * 220.0 * phase)
        high = 8000.0 * np.sin(2.0 * np.pi * 440.0 * phase)
        samples = np.concatenate((low, high, np.zeros(check.WINDOW)))
        geometry = TerminalGeometry(0.0, len(samples) / check.RATE, 3, 16,
                                    "columns", "none", False)
        panel = render_pitch_tracks([("steps", samples)], geometry)[0]
        self.assertFalse(panel.rows[0].strip())
        high_position = panel.rows[1].index("•")
        low_position = panel.rows[2].index("•")
        self.assertGreater(high_position, low_position)
        self.assertEqual(panel.footer[1], "fixed log 70..1200 Hz")
        self.assertIn("voiced 2/3 windows", panel.footer)

    def test_spectral_centroid_shows_sustained_brightness_and_silence(self):
        phase = np.arange(check.WINDOW, dtype=np.float64) / check.RATE
        low = 8000.0 * np.sin(2.0 * np.pi * 220.0 * phase)
        high = 8000.0 * np.sin(2.0 * np.pi * 4000.0 * phase)
        samples = np.concatenate((low, high, np.zeros(check.WINDOW)))
        geometry = TerminalGeometry(0.0, len(samples) / check.RATE, 3, 16,
                                    "columns", "none", False)
        panel = render_spectral_centroids([("brightness", samples)], geometry)[0]
        self.assertFalse(panel.rows[0].strip())
        high_position = panel.rows[1].index("•")
        low_position = panel.rows[2].index("•")
        self.assertGreater(high_position, low_position)
        self.assertEqual(panel.footer[1], "fixed log 55..11025 Hz")
        self.assertIn("active 2/3 windows", panel.footer)

    def test_spectral_flatness_separates_tone_noise_and_silence(self):
        phase = np.arange(check.WINDOW, dtype=np.float64) / check.RATE
        tone = 8000.0 * np.sin(2.0 * np.pi * 220.0 * phase)
        noise = 8000.0 * np.random.default_rng(7).normal(size=check.WINDOW)
        _, tone_value = spectral_flatness_series(tone)
        _, noise_value = spectral_flatness_series(noise)
        _, silent_value = spectral_flatness_series(np.zeros(check.WINDOW))
        self.assertLess(tone_value[0], 0.001)
        self.assertGreater(noise_value[0], 0.40)
        self.assertTrue(np.isnan(silent_value[0]))

        samples = np.concatenate((tone, noise, np.zeros(check.WINDOW)))
        geometry = TerminalGeometry(0.0, len(samples) / check.RATE, 3, 16,
                                    "columns", "none", False)
        panel = render_spectral_flatness([("character", samples)], geometry)[0]
        self.assertFalse(panel.rows[0].strip())
        self.assertGreater(panel.rows[1].index("•"), panel.rows[2].index("•"))
        self.assertEqual(panel.footer[1], "fixed scale 0..1")
        self.assertIn("0 tonal  1 flat/noisy", panel.footer)
        self.assertIn("active 2/3 windows", panel.footer)

    def test_modulation_spectrum_localizes_50_hz_envelope_depth(self):
        index = np.arange(8 * check.RATE, dtype=np.float64)
        carrier = 12000.0 * np.sin(
            2.0 * np.pi * (check.RATE / 20.0) * index / check.RATE)
        modulated = carrier.copy()
        modulated[4 * check.RATE:] *= (
            1.0 + 0.30 * np.sin(
                2.0 * np.pi * 50.0 * index[4 * check.RATE:] / check.RATE))

        measured = modulation_spectrogram(modulated, 16, 64)
        self.assertIsNotNone(measured)
        decibels, edges = measured
        peak_band, _ = np.unravel_index(np.argmax(decibels), decibels.shape)
        fft_bin = np.fft.rfftfreq(
            512, 55.0 / check.RATE)[np.argmin(np.abs(
                np.fft.rfftfreq(512, 55.0 / check.RATE) - 50.0))]
        self.assertLessEqual(edges[peak_band], fft_bin)
        self.assertGreater(edges[peak_band + 1], fft_bin)
        self.assertAlmostEqual(float(decibels.max()), -11.54, places=2)
        peak_hz, peak_depth, peak_db = modulation_peak(modulated)
        self.assertAlmostEqual(peak_hz, 50.113636, places=6)
        self.assertAlmostEqual(peak_depth, 0.264966, places=5)
        self.assertAlmostEqual(peak_db, -11.54, places=2)

        unmodulated, _ = modulation_spectrogram(carrier, 16, 64)
        silent, _ = modulation_spectrogram(
            np.zeros(8 * check.RATE), 16, 64)
        self.assertLess(float(unmodulated.max()), -200.0)
        self.assertEqual(float(silent.max()), -240.0)
        self.assertIsNone(modulation_spectrogram(np.zeros(check.RATE), 16, 64))

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", False)
        panel = render_modulation_spectra(
            (("am-50hz", modulated),), geometry)[0]
        self.assertTrue(any(row.strip() for row in panel.rows[:4]))
        self.assertTrue(all(not row.strip() for row in panel.rows[-3:]))
        self.assertIn("fixed -60..0 dB depth", panel.footer)
        self.assertIn("1..100 Hz log frequency", panel.footer)
        self.assertIn("110-sample (5 ms) RMS", panel.footer)
        self.assertIn("55-sample (2.5 ms) hop", panel.footer)
        self.assertIn("512 Hann / 256 hop", panel.footer)
        self.assertIn("FFT 1.277 s; bins 0.783 Hz", panel.footer)
        self.assertIn("depth / local mean RMS", panel.footer)
        self.assertIn("beats/tremolo may be intended", panel.footer)
        self.assertIn("diagnostic, not verdict", panel.footer)
        self.assertEqual(panel.footer[-1], "peak 50.114 Hz -11.54 dB")
        self.assertEqual(modulation_ruler(edges, 24)[1].split(),
                         ["1", "5", "20", "50"])

        short = render_modulation_spectra(
            (("short", np.zeros(check.RATE)),), geometry)[0]
        self.assertTrue(all("range too short" in row for row in short.rows))
        self.assertIn("needs 1.277 s RMS envelope", short.footer)

    def test_low_frequency_spectrum_separates_50_and_60_hz_hum(self):
        index = np.arange(4 * check.RATE, dtype=np.float64)
        carrier = 12000.0 * np.sin(
            2.0 * np.pi * (check.RATE / 20.0) * index / check.RATE)
        hum_50 = carrier + 400.0 * np.sin(
            2.0 * np.pi * 50.0 * index / check.RATE)
        hum_60 = carrier + 400.0 * np.sin(
            2.0 * np.pi * 60.0 * index / check.RATE)

        peak_50 = low_frequency_peak(hum_50)
        peak_60 = low_frequency_peak(hum_60)
        self.assertAlmostEqual(peak_50[0], 49.795532, places=6)
        self.assertAlmostEqual(peak_50[2], -38.3973, places=3)
        self.assertAlmostEqual(peak_60[0], 60.562134, places=6)
        self.assertAlmostEqual(peak_60[2], -39.2561, places=3)

        grid_50, edges = low_frequency_spectrogram(hum_50, 8, 48)
        grid_60, _ = low_frequency_spectrogram(hum_60, 8, 48)
        band_50 = np.unravel_index(np.argmax(grid_50), grid_50.shape)[0]
        band_60 = np.unravel_index(np.argmax(grid_60), grid_60.shape)[0]
        self.assertLessEqual(edges[band_50], peak_50[0])
        self.assertGreater(edges[band_50 + 1], peak_50[0])
        self.assertLessEqual(edges[band_60], peak_60[0])
        self.assertGreater(edges[band_60 + 1], peak_60[0])
        self.assertEqual((band_50 // 2, band_60 // 2), (4, 5))

        silent, _ = low_frequency_spectrogram(
            np.zeros(4 * check.RATE), 8, 48)
        self.assertEqual(float(silent.max()), -240.0)
        self.assertIsNone(low_frequency_spectrogram(np.zeros(16000), 8, 48))

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", False)
        panel = render_low_frequency_spectra((
            ("50-to-60", np.concatenate((hum_50, hum_60))),
        ), geometry)[0]
        self.assertIn("fixed -96..0 dBFS amplitude", panel.footer)
        self.assertIn("1..250 Hz linear frequency", panel.footer)
        self.assertIn("16384 Hann / 8192 hop", panel.footer)
        self.assertIn("FFT 0.743 s; bins 1.346 Hz", panel.footer)
        self.assertIn("carrier Hz, not envelope rate", panel.footer)
        self.assertIn("bass/rumble may be intended", panel.footer)
        self.assertIn("diagnostic, not verdict", panel.footer)
        self.assertEqual(panel.footer[-1],
                         "peak 49.796 Hz -38.40 dBFS")
        self.assertEqual(low_frequency_ruler(24)[1].split(),
                         ["1", "50", "100", "150", "200", "250"])

        short = render_low_frequency_spectra((
            ("short", np.zeros(16000)),
        ), geometry)[0]
        self.assertTrue(all("range too short" in row for row in short.rows))
        self.assertIn("needs 0.743 s of audio", short.footer)

    def test_peak_occupancy_exposes_dithered_subrail_clipping(self):
        time = np.arange(check.RATE * 2, dtype=np.float64) / check.RATE
        reference = (7000.0 * np.sin(2.0 * np.pi * 220.0 * time)
                     + 3500.0 * np.sin(2.0 * np.pi * 440.0 * time))
        cap = float(np.percentile(np.abs(reference), 45.0))
        candidate = np.clip(reference, -cap, cap)
        plateau = np.abs(candidate) >= cap
        dither = np.random.default_rng(20260801).uniform(
            -0.005 * cap, 0.005 * cap, int(np.count_nonzero(plateau)))
        candidate[plateau] += dither * np.sign(candidate[plateau])
        candidate *= (np.sqrt(np.mean(reference * reference))
                      / np.sqrt(np.mean(candidate * candidate)))
        reference = np.rint(reference).astype(np.int16)
        candidate = np.rint(candidate).astype(np.int16)

        reference_occupancy = peak_occupancy_percent(reference)
        candidate_occupancy = peak_occupancy_percent(candidate)
        self.assertLess(reference_occupancy, 10.0)
        self.assertGreater(candidate_occupancy, 50.0)
        self.assertLess(abs(flatline_ratio(candidate)
                            - flatline_ratio(reference)), 1.0)
        self.assertIsNone(peak_occupancy_percent(np.zeros(check.WINDOW)))

        geometry = TerminalGeometry(0.0, 4.0, 2, 16,
                                    "columns", "none", False)
        panel = render_peak_occupancy([
            ("candidate", np.concatenate((reference, candidate))),
        ], geometry)[0]
        self.assertGreater(panel.rows[0].index("●"), panel.rows[1].index("●"))
        self.assertEqual(panel.footer[1], "row-local |x| ≥.99 peak")
        self.assertIn("diagnostic, not verdict", panel.footer)
        self.assertIn("row max", panel.footer[-3])

    def test_intersample_peak_exposes_subrail_reconstruction_over(self):
        pattern = np.resize(np.array((1.0, 1.0, -1.0, -1.0)),
                            check.RATE * 2)
        safe = pattern * (0.65 * 32768.0)
        over = pattern * (0.75 * 32768.0)
        self.assertLess(np.max(np.abs(over)), 32767.0)
        self.assertEqual(rail_ratio_percent(over), 0.0)
        self.assertAlmostEqual(intersample_peak_dbfs(safe), -0.7303, places=3)
        self.assertAlmostEqual(intersample_peak_dbfs(over), +0.5127, places=3)
        self.assertGreater(intersample_peak_estimate(over), 32768.0)

        edge_only = np.zeros(128)
        edge_only[0] = 32767.0
        self.assertEqual(intersample_peak_estimate(edge_only), 0.0)
        self.assertIsNone(intersample_peak_dbfs(np.zeros(128)))
        self.assertIsNone(intersample_peak_estimate(np.zeros(32)))

        geometry = TerminalGeometry(0.0, 2.0, 2, 16,
                                    "columns", "none", True)
        panel = render_intersample_peaks((
            ("candidate", np.concatenate((safe, over))),
        ), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[1])
        self.assertGreater(newest.index("•"), oldest.index("•"))
        self.assertTrue(panel.rows[0].startswith("\x1b[1;31m"))
        self.assertEqual(panel.footer[2], "fixed -12..+6 dBFS")
        self.assertIn("not a standards meter", panel.footer)
        self.assertIn("16 range-edge samples omitted", panel.footer)
        self.assertIn("┬", panel.x_axis)

    def test_flatline_ratio_exposes_a_held_sample_region(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        changing = np.arange(16, dtype=np.float64)
        held = np.full(16, 1234.0)
        panel = render_flatline_ratios([
            ("candidate", np.concatenate((changing, held))),
        ], geometry)[0]
        self.assertEqual(panel.rows[0][-1], ">")
        self.assertEqual(panel.rows[1][0], "•")
        self.assertEqual(panel.footer[1], "fixed scale 0..100%")
        self.assertEqual(panel.footer[-2], "row max 100.00%")

        too_short = render_flatline_ratios([
            ("short", np.array([1.0])),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in too_short.rows))
        self.assertEqual(too_short.footer[-1], "selected flat n/a")

    def test_block_repeat_exposes_replayed_and_inverted_rows(self):
        geometry = TerminalGeometry(0.0, 3.0, 3, 16,
                                    "columns", "none", False)
        first = np.array([0.0, 1.0, -1.0, 2.0] * 4)
        panel = render_block_repeats([
            ("candidate", np.concatenate((first, first, -first))),
        ], geometry)[0]
        self.assertEqual(panel.rows[0][0], "•")
        self.assertEqual(panel.rows[1][-1], "•")
        self.assertFalse(panel.rows[2].strip())
        self.assertEqual(panel.footer[1], "Pearson fixed -1..+1")
        self.assertEqual(panel.footer[-1], "row max |corr| 1.000")

        constant = render_block_repeats([
            ("constant", np.ones(48)),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in constant.rows))

    def test_crest_factor_shows_impulses_and_blanks_silence(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        steady = np.ones(16)
        impulse = np.concatenate((np.array([4.0]), np.zeros(15)))
        panel = render_crest_factors([
            ("candidate", np.concatenate((steady, impulse))),
        ], geometry)[0]
        self.assertEqual(panel.rows[0].index("●"), 7)
        self.assertEqual(panel.rows[1][0], "•")
        self.assertEqual(panel.footer[1], "fixed scale 0..24 dB")
        self.assertEqual(panel.footer[-2], "row max 12.04 dB")

        silent = render_crest_factors([
            ("silence", np.zeros(32)),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in silent.rows))
        self.assertEqual(silent.footer[-1], "selected crest n/a")

    def test_derivative_ratio_separates_smooth_and_alternating_audio(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        smooth = np.sin(np.linspace(0.0, 2.0 * np.pi, 16, endpoint=False))
        alternating = np.tile(np.array([-1.0, 1.0]), 8)
        panel = render_derivative_ratios([
            ("candidate", np.concatenate((smooth, alternating))),
        ], geometry)[0]
        self.assertEqual(panel.rows[0][-1], ">")
        self.assertLess(panel.rows[1].index("●"), 15)
        self.assertEqual(panel.footer[1], "fixed -48..+6 dB")
        self.assertIn("left=smooth right=rough", panel.footer)

        constant = render_derivative_ratios([
            ("constant", np.ones(32)),
        ], geometry)[0]
        self.assertTrue(all(not row.strip() for row in constant.rows))
        self.assertEqual(constant.footer[-1], "selected ratio n/a")

    def test_sample_density_surfaces_silence_and_rail_occupancy(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", False)
        samples = np.concatenate((
            np.zeros(16),
            np.tile(np.array([-32768.0, 32767.0]), 8),
        ))
        panel = render_sample_density([("candidate", samples)], geometry)[0]
        self.assertEqual(panel.rows[0][0], "█")
        self.assertEqual(panel.rows[0][-1], "█")
        self.assertEqual(panel.rows[1][geometry.width // 2], "█")
        self.assertEqual(panel.footer[1], "fixed -32768..+32767 PCM")
        self.assertEqual(panel.footer[-1], "rail samples 16")

    def test_dc_offset_panels_share_scale_and_preserve_direction(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", True)
        panels = render_dc_offsets([
            ("reference", np.array([-1024.0, -1024.0])),
            ("candidate", np.array([1024.0, 1024.0])),
        ], geometry)
        self.assertEqual(len(panels), 2)
        self.assertEqual(panels[0].footer[1], "scale ±1024.0 PCM")
        self.assertEqual(panels[1].footer[1], "scale ±1024.0 PCM")
        self.assertEqual(panels[0].footer[2], "shared across WAVs")
        reference_row = re.sub(r"\x1b\[[0-9;]*m", "", panels[0].rows[0])
        candidate_row = re.sub(r"\x1b\[[0-9;]*m", "", panels[1].rows[0])
        self.assertEqual(reference_row.index("•"), 0)
        self.assertEqual(candidate_row.index("•"), 15)
        self.assertTrue(panels[0].rows[0].startswith("\x1b[1;31m•"))
        self.assertEqual(panels[1].footer[-1], "selected mean +1024.0 PCM")

    def test_wave_correlation_exposes_a_local_polarity_inversion(self):
        geometry = TerminalGeometry(0.0, 1.0, 2, 16,
                                    "columns", "none", True)
        chunk = np.array([-2.0, -1.0, 0.0, 1.0, 2.0, 0.0])
        reference = np.concatenate((chunk, chunk))
        candidate = np.concatenate((chunk, -chunk))
        panel = render_wave_correlation(
            reference, candidate, geometry, label="candidate")
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[1])
        self.assertEqual(newest.index("•"), 0)
        self.assertEqual(oldest.index("•"), 15)
        self.assertTrue(panel.rows[0].startswith("\x1b[1;31m•"))
        self.assertIn("fixed scale -1..+1", panel.footer)
        self.assertEqual(panel.footer[-1], "selected corr +0.000")

        flat = render_wave_correlation(
            np.zeros(12), np.zeros(12), geometry, label="flat")
        self.assertTrue(all(not row.strip() for row in flat.rows))
        self.assertEqual(flat.footer[-1], "selected corr n/a")

    def test_stereo_correlation_exposes_antiphase_and_explicit_edge_cases(self):
        geometry = TerminalGeometry(0.0, 2.0, 2, 16,
                                    "columns", "none", True)
        chunk = np.array((-2.0, -1.0, 0.0, 1.0, 2.0, 0.0))
        channels = np.column_stack((
            np.concatenate((chunk, chunk)),
            np.concatenate((chunk, -chunk)),
        ))
        panel = render_stereo_correlations(
            (("stereo", channels),), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[1])
        self.assertEqual(newest.index("•"), 0)
        self.assertEqual(oldest.index("•"), 15)
        self.assertTrue(panel.rows[0].startswith("\x1b[1;31m•"))
        self.assertEqual(panel.footer[1], "fixed scale -1..+1")
        self.assertIn("channels 1/2", panel.footer)

        mono = render_stereo_correlations(
            (("mono", chunk[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)

        flat = render_stereo_correlations(
            (("flat", np.zeros((12, 2))),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in flat.rows))
        self.assertEqual(flat.footer[-1], "selected corr n/a")

        surround = render_stereo_correlations(
            (("surround", np.column_stack((channels, channels[:, 0]))),),
            geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

    def test_stereo_balance_exposes_one_channel_loss_and_edge_cases(self):
        geometry = TerminalGeometry(0.0, 2.0, 2, 16,
                                    "columns", "none", True)
        chunk = np.array((-2.0, -1.0, 0.0, 1.0, 2.0, 0.0))
        channels = np.column_stack((
            np.concatenate((chunk, chunk)),
            np.concatenate((chunk, np.zeros_like(chunk))),
        ))
        panel = render_stereo_balances((("stereo", channels),), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[1])
        self.assertEqual(newest.index("•"), 0)
        self.assertEqual(oldest.index("•"), geometry.width // 2)
        self.assertTrue(panel.rows[0].startswith("\x1b[1;31m•"))
        self.assertEqual(panel.footer[1], "fixed -24..+24 dB")
        self.assertIn("channels 1/2", panel.footer)
        self.assertAlmostEqual(stereo_balance_db(chunk, 2 * chunk),
                               20.0 * np.log10(2.0))
        self.assertTrue(np.isneginf(stereo_balance_db(chunk, np.zeros(6))))
        self.assertTrue(np.isposinf(stereo_balance_db(np.zeros(6), chunk)))
        self.assertIsNone(stereo_balance_db(np.zeros(6), np.zeros(6)))

        mono = render_stereo_balances(
            (("mono", chunk[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)

        surround = render_stereo_balances(
            (("surround", np.column_stack((channels, channels[:, 0]))),),
            geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

    def test_stereo_phase_localizes_frequency_selective_cancellation(self):
        count = 8 * check.RATE
        index = np.arange(count, dtype=np.float64)
        low_hz = 16 * check.RATE / 1024
        high_hz = 128 * check.RATE / 1024
        low = 16000.0 * np.sin(
            2.0 * np.pi * low_hz * index / check.RATE)
        high = 2000.0 * np.sin(
            2.0 * np.pi * high_hz * index / check.RATE)
        left = low + high
        right = left.copy()
        right[4 * check.RATE:] = low[4 * check.RATE:] - high[4 * check.RATE:]
        channels = np.column_stack((left, right))
        self.assertAlmostEqual(
            stereo_balance_db(left[4 * check.RATE:], right[4 * check.RATE:]),
            0.0, places=3)
        self.assertGreater(
            waveform_correlation(left[4 * check.RATE:], right[4 * check.RATE:]),
            0.95)

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", True)
        panel = render_stereo_phases((("stereo", channels),), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[-1])
        self.assertTrue("<" in newest or ">" in newest)
        self.assertEqual(oldest.strip(), "")
        self.assertRegex(panel.rows[0], r"\x1b\[1;(?:31|34)m")
        self.assertIn("channel 2-channel 1 phase", panel.footer)
        self.assertIn("+ means channel 2 leads", panel.footer)
        self.assertIn("channels 1/2", panel.footer)

        mono = render_stereo_phases(
            (("mono", left[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)
        self.assertIn("┬", mono.x_axis)

        surround = render_stereo_phases((
            ("surround", np.column_stack((channels, left))),
        ), geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

        short = render_stereo_phases((
            ("short", channels[:1023]),
        ), geometry)[0]
        self.assertTrue(all("range too short" in row for row in short.rows))
        self.assertIn("channels 1/2", short.footer)

        random = np.random.default_rng(20260802)
        incoherent = np.column_stack((
            random.normal(0.0, 4000.0, 4 * check.RATE),
            random.normal(0.0, 4000.0, 4 * check.RATE),
        ))
        blank = render_stereo_phases(
            (("incoherent", incoherent),), geometry)[0]
        self.assertTrue(all(not re.sub(
            r"\x1b\[[0-9;]*m", "", row).strip() for row in blank.rows))

    def test_stereo_coherence_exposes_equal_energy_phase_instability(self):
        count = 8 * check.RATE
        index = np.arange(count, dtype=np.float64)
        time = index / check.RATE
        low_hz = 16 * check.RATE / 1024
        high_hz = 128 * check.RATE / 1024
        low = 16000.0 * np.sin(2.0 * np.pi * low_hz * time)
        high = 2000.0 * np.sin(2.0 * np.pi * high_hz * time)
        left = low + high
        right = left.copy()
        start = 4 * check.RATE
        phase_modulation = 2.4048255577 * np.sin(
            2.0 * np.pi * 10.0 * time[start:])
        right[start:] = low[start:] + 2000.0 * np.sin(
            2.0 * np.pi * high_hz * time[start:] + phase_modulation)
        channels = np.column_stack((left, right))

        self.assertAlmostEqual(
            stereo_balance_db(left[start:], right[start:]), 0.0, places=5)
        self.assertGreater(
            waveform_correlation(left[start:], right[start:]), 0.98)
        coherence, edges = coherence_grid(left, right, 8, 24)
        low_band = np.flatnonzero(
            (edges[:-1] <= low_hz) & (low_hz < edges[1:]))[0]
        high_band = np.flatnonzero(
            (edges[:-1] <= high_hz) & (high_hz < edges[1:]))[0]
        np.testing.assert_allclose(coherence[low_band], 1.0, atol=1e-6)
        np.testing.assert_allclose(coherence[high_band, :4], 1.0,
                                   atol=1e-6)
        self.assertLess(float(np.max(coherence[high_band, 5:])), 0.002)

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", True)
        panel = render_stereo_coherences(
            (("stereo", channels),), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[-1])
        self.assertEqual(newest[high_band], "X")
        self.assertEqual(oldest[high_band], "·")
        self.assertEqual(newest[low_band], "·")
        self.assertIn("\x1b[1;31mX", panel.rows[0])
        self.assertIn("fixed coherence 0..1", panel.footer)
        self.assertIn("normalized, not squared", panel.footer)
        self.assertIn("both levels within 60 dB", panel.footer)
        self.assertIn("low can be width/reverb/noise", panel.footer)
        self.assertIn("channels 1/2", panel.footer)
        self.assertIn("diagnostic, not verdict", panel.footer)

        phase_panel = render_stereo_phases(
            (("stereo", channels),), geometry)[0]
        level_panel = render_stereo_level_diffs(
            (("stereo", channels),), geometry)[0]
        self.assertTrue(all(not re.sub(
            r"\x1b\[[0-9;]*m", "", row).strip()
                            for row in phase_panel.rows))
        self.assertTrue(all(not re.sub(
            r"\x1b\[[0-9;]*m", "", row).strip()
                            for row in level_panel.rows))

        mono = render_stereo_coherences(
            (("mono", left[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)
        self.assertIn("┬", mono.x_axis)

        surround = render_stereo_coherences((
            ("surround", np.column_stack((channels, left))),
        ), geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

        short = render_stereo_coherences((
            ("short", channels[:1023]),
        ), geometry)[0]
        self.assertTrue(all("range too short" in row for row in short.rows))
        self.assertIn("channels 1/2", short.footer)

        silent_grid, _ = coherence_grid(
            np.zeros(check.RATE), np.zeros(check.RATE), 8, 24)
        self.assertTrue(np.all(np.isnan(silent_grid)))

    def test_stereo_level_diff_localizes_narrow_band_channel_loss(self):
        count = 8 * check.RATE
        index = np.arange(count, dtype=np.float64)
        low_hz = 16 * check.RATE / 1024
        high_hz = 128 * check.RATE / 1024
        low = 16000.0 * np.sin(
            2.0 * np.pi * low_hz * index / check.RATE)
        high = 2000.0 * np.sin(
            2.0 * np.pi * high_hz * index / check.RATE)
        left = low + high
        right = left.copy()
        right[4 * check.RATE:] = low[4 * check.RATE:]
        channels = np.column_stack((left, right))
        self.assertGreater(
            waveform_correlation(left[4 * check.RATE:], right[4 * check.RATE:]),
            0.99)
        self.assertGreater(
            stereo_balance_db(left[4 * check.RATE:], right[4 * check.RATE:]),
            -0.1)

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", True)
        panel = render_stereo_level_diffs(
            (("stereo", channels),), geometry)[0]
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[-1])
        self.assertIn("<", newest)
        self.assertEqual(oldest.strip(), "")
        self.assertIn("\x1b[1;34m<", panel.rows[0])
        self.assertIn("< ch2 quieter > louder", panel.footer)
        self.assertIn("floor -60 dB shared", panel.footer)
        self.assertIn("channels 1/2", panel.footer)
        self.assertIn("diagnostic, not verdict", panel.footer)

        louder = render_stereo_level_diffs((
            ("louder", np.column_stack((right, left))),
        ), geometry)[0]
        self.assertIn(">", re.sub(
            r"\x1b\[[0-9;]*m", "", louder.rows[0]))

        mono = render_stereo_level_diffs(
            (("mono", left[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)
        self.assertIn("┬", mono.x_axis)

        surround = render_stereo_level_diffs((
            ("surround", np.column_stack((channels, left))),
        ), geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

        short = render_stereo_level_diffs((
            ("short", channels[:1023]),
        ), geometry)[0]
        self.assertTrue(all("range too short" in row for row in short.rows))
        self.assertIn("channels 1/2", short.footer)
        self.assertIn("diagnostic, not verdict", short.footer)

        silent = render_stereo_level_diffs((
            ("silent", np.zeros((check.RATE, 2))),
        ), geometry)[0]
        self.assertTrue(all(not row.strip() for row in silent.rows))

    def test_stereo_delay_localizes_broadband_lag_and_blanks_periodic_ambiguity(self):
        delay = 44
        rng = np.random.default_rng(20260801)
        left = rng.normal(size=4096)
        right = np.concatenate((np.zeros(delay), left[:-delay]))
        observation = stereo_delay_observation(left, right)
        self.assertTrue(observation.accepted)
        self.assertEqual(observation.lag_samples, delay)
        self.assertAlmostEqual(observation.peak_correlation, 1.0)
        self.assertGreater(observation.peak_margin, 0.50)

        time = np.arange(4096) / check.RATE
        tone = np.sin(2.0 * np.pi * 220.0 * time)
        delayed_tone = np.concatenate((np.zeros(delay), tone[:-delay]))
        ambiguous = stereo_delay_observation(tone, delayed_tone)
        self.assertIsNotNone(ambiguous)
        self.assertFalse(ambiguous.accepted)
        self.assertLess(ambiguous.peak_margin, 0.05)
        self.assertIsNone(stereo_delay_observation(
            np.zeros(4096), np.zeros(4096)))

        first = rng.normal(size=2048)
        second = rng.normal(size=2048)
        channels = np.column_stack((
            np.concatenate((first, second)),
            np.concatenate((first, np.zeros(delay), second[:-delay])),
        ))
        geometry = TerminalGeometry(0.0, 2.0, 2, 16,
                                    "columns", "none", False)
        panel = render_stereo_delays((("delayed", channels),), geometry)[0]
        self.assertGreater(panel.rows[0].index("•"), geometry.width // 2)
        self.assertEqual(panel.rows[1].index("•"), geometry.width // 2)
        self.assertEqual(panel.footer[1], "fixed -5..+5 ms")
        self.assertIn("channels 1/2", panel.footer)

        mono = render_stereo_delays(
            (("mono", first[:, None]),), geometry)[0]
        self.assertTrue(all(not row.strip() for row in mono.rows))
        self.assertIn("not applicable: mono", mono.footer)

        surround = render_stereo_delays((
            ("surround", np.column_stack((channels, channels[:, 0]))),
        ), geometry)[0]
        self.assertIn("using channels 1/2 of 3", surround.footer)

    def test_residual_ratio_preserves_two_fixed_error_severities(self):
        second = check.RATE
        phase = np.arange(4 * second, dtype=np.float64) / check.RATE
        reference = 8000.0 * np.sin(2.0 * np.pi * 220.0 * phase)
        candidate = reference.copy()
        for start_second, error_db in ((1, -40.0), (3, -20.0)):
            start, end = start_second * second, (start_second + 1) * second
            reference_rms = float(np.sqrt(np.mean(reference[start:end] ** 2)))
            error_phase = np.arange(second, dtype=np.float64) / check.RATE
            candidate[start:end] += (
                np.sqrt(2.0) * reference_rms * 10.0 ** (error_db / 20.0)
                * np.sin(2.0 * np.pi * 3000.0 * error_phase))
            self.assertAlmostEqual(
                residual_ratio_db(reference[start:end], candidate[start:end]),
                error_db, places=6)
        self.assertTrue(np.isneginf(
            residual_ratio_db(reference, reference.copy())))
        self.assertIsNone(residual_ratio_db(np.zeros(second), np.ones(second)))

        geometry = TerminalGeometry(0.0, 4.0, 4, 16,
                                    "columns", "none", False)
        panel = render_residual_ratio(
            reference, candidate, geometry, label="candidate")
        self.assertGreater(panel.rows[0].index("●"), panel.rows[2].index("●"))
        self.assertEqual(panel.rows[1][0], "<")
        self.assertEqual(panel.rows[3][0], "<")
        self.assertEqual(panel.footer[1], "fixed -60..+6 dB")
        self.assertIn("blank=ref silent/short", panel.footer)
        self.assertIn("whole ratio", panel.footer[-1])

    def test_spectral_diff_marks_missing_and_excess_energy(self):
        time = np.arange(check.RATE * 2) / check.RATE
        reference = 8000.0 * np.sin(2 * np.pi * 220.0 * time)
        candidate = 8000.0 * np.sin(2 * np.pi * 440.0 * time)
        geometry = TerminalGeometry(0.0, 2.0, 6, 32,
                                    "rows", "none", False)
        rendered = render_spectral_diff(
            reference, candidate, geometry, label="candidate")
        cells = "".join(rendered.rows)
        self.assertIn("<", cells)
        self.assertIn(">", cells)
        self.assertIn("blank |Δ| <3 dB", rendered.footer)

    def test_phase_diff_localizes_a_magnitude_matched_phase_fault(self):
        count = 8 * check.RATE
        index = np.arange(count, dtype=np.float64)
        low_hz = 16 * check.RATE / 1024
        high_hz = 128 * check.RATE / 1024
        low = 8000.0 * np.sin(2.0 * np.pi * low_hz * index / check.RATE)
        reference = low + 4000.0 * np.sin(
            2.0 * np.pi * high_hz * index / check.RATE)
        candidate = reference.copy()
        second = index >= 4 * check.RATE
        candidate[second] = low[second] + 4000.0 * np.sin(
            2.0 * np.pi * high_hz * index[second] / check.RATE
            + np.pi / 2.0)

        measured = phase_difference_grid(reference, candidate, 8, 24)
        self.assertIsNotNone(measured)
        phase, coherence, edges = measured
        high_band = int(np.argmin(np.abs(
            np.sqrt(edges[:-1] * edges[1:]) - high_hz)))
        self.assertTrue(np.all(np.abs(phase[high_band, :4]) < 0.1))
        self.assertTrue(np.all(phase[high_band, 5:] > 89.9))
        self.assertTrue(np.all(coherence[high_band, 5:] > 0.999))
        self.assertTrue(np.isnan(phase_difference_grid(
            reference, np.zeros_like(reference), 8, 24)[0]).all())
        random = np.random.default_rng(20260802)
        incoherent = phase_difference_grid(
            random.normal(0.0, 4000.0, 4 * check.RATE),
            random.normal(0.0, 4000.0, 4 * check.RATE), 1, 24)
        self.assertTrue(np.isnan(incoherent[0]).all())
        self.assertTrue(np.all(incoherent[1] < 0.80))
        self.assertIsNone(phase_difference_grid(
            reference[:1023], candidate[:1023], 8, 24))

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", True)
        panel = render_phase_diff(
            reference, candidate, geometry, label="phase-shift")
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[-1])
        self.assertIn("*", newest)
        self.assertEqual(oldest.strip(), "")
        self.assertIn("candidate-reference phase", panel.footer)
        self.assertIn("require coherence >=0.80", panel.footer)
        self.assertIn("both levels within 60 dB", panel.footer)
        self.assertIn("wrapped; diagnostic only", panel.footer)
        self.assertIn("┬", panel.x_axis)

    def test_spectral_coherence_exposes_equal_energy_phase_instability(self):
        count = 8 * check.RATE
        index = np.arange(count, dtype=np.float64)
        time = index / check.RATE
        low_hz = 16 * check.RATE / 1024
        high_hz = 128 * check.RATE / 1024
        low = 16000.0 * np.sin(2.0 * np.pi * low_hz * time)
        high_phase = 2.0 * np.pi * high_hz * time
        reference = low + 2000.0 * np.sin(high_phase)
        candidate = reference.copy()
        start = 4 * check.RATE
        phase_modulation = 2.4048255577 * np.sin(
            2.0 * np.pi * 10.0 * time[start:])
        candidate[start:] = low[start:] + 2000.0 * np.sin(
            high_phase[start:] + phase_modulation)

        self.assertAlmostEqual(
            waveform_correlation(reference, candidate), 0.992307623,
            places=8)
        self.assertAlmostEqual(
            waveform_correlation(reference[start:], candidate[start:]),
            0.984616140, places=8)
        coherence, edges = coherence_grid(reference, candidate, 8, 24)
        low_band = np.flatnonzero(
            (edges[:-1] <= low_hz) & (low_hz < edges[1:]))[0]
        high_band = np.flatnonzero(
            (edges[:-1] <= high_hz) & (high_hz < edges[1:]))[0]
        np.testing.assert_allclose(coherence[low_band], 1.0, atol=1e-6)
        np.testing.assert_allclose(coherence[high_band, :4], 1.0,
                                   atol=1e-6)
        np.testing.assert_allclose(
            coherence[high_band, 4:],
            (0.020361, 0.001436, 0.001305, 0.001210), atol=1e-6)

        geometry = TerminalGeometry(0.0, 8.0, 8, 24,
                                    "columns", "none", True)
        panel = render_spectral_coherence(
            reference, candidate, geometry, label="phase-modulated")
        newest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[0])
        oldest = re.sub(r"\x1b\[[0-9;]*m", "", panel.rows[-1])
        self.assertEqual(newest[high_band], "X")
        self.assertEqual(oldest[high_band], "·")
        self.assertEqual(newest[low_band], "·")
        self.assertIn("reference/candidate cross-spectrum", panel.footer)
        self.assertIn("fixed coherence 0..1", panel.footer)
        self.assertIn("normalized, not squared", panel.footer)
        self.assertIn("low may be intentional", panel.footer)
        self.assertIn("diagnostic, not verdict", panel.footer)

        spectral = render_spectral_diff(
            reference, candidate, geometry, label="phase-modulated")
        phase = render_phase_diff(
            reference, candidate, geometry, label="phase-modulated")
        for hidden in (spectral, phase):
            self.assertTrue(all(not re.sub(
                r"\x1b\[[0-9;]*m", "", row).strip()
                                for row in hidden.rows))

        short = render_spectral_coherence(
            reference[:1023], candidate[:1023], geometry, label="short")
        self.assertTrue(all("range too short" in row for row in short.rows))
        silent = render_spectral_coherence(
            np.zeros(check.RATE), np.zeros(check.RATE), geometry,
            label="silent")
        self.assertTrue(all(not row.strip() for row in silent.rows))
        self.assertIn("minimum n/a", silent.footer)


class CommandContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._fixtures = tempfile.TemporaryDirectory()
        cls.wav = Path(cls._fixtures.name) / "check.wav"
        time = np.arange(check.RATE * 4) / check.RATE
        write_wav(cls.wav, np.sin(2 * np.pi * 220.0 * time))
        cls.schema = json.loads(SCHEMA_PATH.read_text())

    @classmethod
    def tearDownClass(cls):
        cls._fixtures.cleanup()

    def assertSchema(self, value):
        validate_schema(value, self.schema)

    def test_every_help_path_is_offline_and_successful(self):
        paths = (("--help",), ("wav", "--help"), ("wav", "inspect", "--help"),
                 ("wav", "compare", "--help"), ("sfx", "--help"),
                 ("sfx", "analyze", "--help"))
        for path in paths:
            with self.subTest(path=path):
                process = run_cli(*path)
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertIn("usage:", process.stdout)
                self.assertEqual(process.stderr, "")
        root_help = run_cli("--help").stdout
        self.assertIn("--output {human,json}", root_help)
        self.assertIn("Exit codes: 0 success", root_help)
        compare_help = run_cli("wav", "compare", "--help").stdout
        self.assertIn(
            "--profile {full-track-v2,full-track-v1,pitch-band-v1}",
            compare_help)
        self.assertIn("score is only the", compare_help.lower())
        self.assertIn("spectrum cosine median/p10 >=0.90/0.80", compare_help)
        self.assertIn("zero click-v1 candidate events", compare_help)
        self.assertIn(
            "--view {spectrogram,low-frequency-spectrum,modulation-spectrum,pitch-track,waveform,intersample-peak,rms-level,rail-ratio,peak-occupancy,quantization-step,flatline-ratio,block-repeat,crest-factor,derivative-ratio,spectral-change,spectral-centroid,spectral-flatness,sample-density,dc-offset,stereo-balance,stereo-level-diff,stereo-correlation,stereo-delay,stereo-phase,stereo-coherence,wave-correlation,metrics,level-delta,pitch-delta,timing-drift,contour,spectral-diff,phase-diff,spectral-coherence,band-delta,clicks,residual-ratio,residual}",
            compare_help)
        inspect_help = run_cli("wav", "inspect", "--help").stdout
        self.assertIn("delta >=64 PCM", inspect_help)
        self.assertIn("severity >=8x", inspect_help)
        self.assertIn("fail", inspect_help.lower())
        self.assertIn(
            "--view {spectrogram,low-frequency-spectrum,modulation-spectrum,pitch-track,waveform,intersample-peak,rms-level,rail-ratio,peak-occupancy,quantization-step,flatline-ratio,block-repeat,crest-factor,derivative-ratio,spectral-change,spectral-centroid,spectral-flatness,sample-density,dc-offset,stereo-balance,stereo-level-diff,stereo-correlation,stereo-delay,stereo-phase,stereo-coherence,clicks}",
            inspect_help)
        self.assertIn("--layout {rows,columns}", inspect_help)
        self.assertIn("default: 32", inspect_help)
        self.assertIn("default: 2.0", inspect_help)
        self.assertIn("default: 120", inspect_help)
        self.assertIn("panel titles omit that", inspect_help)
        self.assertIn("retain reference/candidate labels", compare_help)
        self.assertIn("bar at >=64x", inspect_help)
        self.assertIn("rail sample counts", inspect_help)
        self.assertIn("fixed signed-16-bit amplitude histogram", inspect_help)
        self.assertIn("minimum of +/-256 PCM", inspect_help)
        self.assertIn("fixed 0..24 dB scale", inspect_help)
        self.assertIn("fixed -48..+6 dB scale", inspect_help)
        self.assertIn("four reconstruction phases", inspect_help)
        self.assertIn("33-tap Hann-", inspect_help)
        self.assertIn("windowed sinc", inspect_help)
        self.assertIn("fixed -12..+6 dBFS scale", inspect_help)
        self.assertIn("not a standards true-peak meter", inspect_help)
        self.assertIn("16 selected-range edge samples", inspect_help)
        self.assertIn("-96..0 dBFS scale and places exact silence", inspect_help)
        self.assertIn("logarithmic 1 ppm..100% scale", inspect_help)
        self.assertIn("flat-topping below the signed-16-bit rails", inspect_help)
        self.assertIn("GCD of gaps", inspect_help)
        self.assertIn("1024-sample Hann spectra", inspect_help)
        self.assertIn("70..1200 Hz bounds", inspect_help)
        self.assertIn("55..11025 Hz scale", inspect_help)
        self.assertIn("power-spectrum Wiener entropy", inspect_help)
        self.assertIn("1..100 Hz log", inspect_help)
        self.assertIn("fixed -60..0 dB modulation-depth scale", inspect_help)
        self.assertIn("400.909091 Hz", inspect_help)
        self.assertIn("1.277098 s", inspect_help)
        self.assertIn("0.783025 Hz", inspect_help)
        self.assertIn("not carrier-frequency analysis or a verdict", inspect_help)
        self.assertIn("1..250 Hz", inspect_help)
        self.assertIn("fixed -96..0 dBFS amplitude scale", inspect_help)
        self.assertIn("0.743039 s", inspect_help)
        self.assertIn("0.371519 s", inspect_help)
        self.assertIn("1.345825 Hz", inspect_help)
        self.assertIn("carrier frequency, not envelope-modulation rate", inspect_help)
        self.assertIn("RMS-envelope modulation depth", compare_help)
        self.assertIn("presentation-only", compare_help)
        self.assertIn("fixed -24..+24 dB", inspect_help)
        self.assertIn("original decoded channels 1 and 2", inspect_help)
        self.assertIn("mono is explicitly not applicable", inspect_help)
        self.assertIn("fixed -5..+5 ms", inspect_help)
        self.assertIn("channel-2-minus-channel-1 energy", inspect_help)
        self.assertIn("55..8000 Hz log frequency", inspect_help)
        self.assertIn("one shared -60 dB floor", inspect_help)
        self.assertIn("differences below 3 dB", inspect_help)
        self.assertIn("full blue/red glyphs at -/+24 dB", inspect_help)
        self.assertIn("other local peak by >=0.05", inspect_help)
        self.assertIn("channel-2-minus-channel-1 phase", inspect_help)
        self.assertIn("fixed -180..+180 degree", inspect_help)
        self.assertIn("Positive/red means channel 2", inspect_help)
        self.assertIn("shared -60 dB power-floor", inspect_help)
        self.assertIn("normalized complex channel-1/2", inspect_help)
        self.assertIn("fixed 0..1 glyph scale", inspect_help)
        self.assertIn("not magnitude-squared coherence", inspect_help)
        self.assertIn("width, reverb, or independent noise", inspect_help)
        self.assertIn("predecessor using Pearson correlation", inspect_help)
        self.assertIn("fixed 0..100%", inspect_help)
        self.assertIn("per-window diagnostic, not the verdict", compare_help)
        self.assertIn("maximum absolute PCM", compare_help)
        self.assertIn("-1 polarity", compare_help)
        self.assertIn("randomized noise can be uncorrelated", compare_help)
        self.assertIn("pitch-delta", compare_help)
        self.assertIn("spectral-diff", compare_help)
        self.assertIn("residual RMS/reference RMS", compare_help)
        self.assertIn("fixed -180..+180 degree scale", compare_help)
        self.assertIn("coherence is below", compare_help)
        self.assertIn("more than 60 dB below", compare_help)
        self.assertIn("Positive/red means the candidate leads", compare_help)
        self.assertIn("reference/candidate cross-spectrum", compare_help)
        self.assertIn("shared but decorrelated energy", compare_help)
        self.assertIn("only wav compare supports this view", compare_help)
        self.assertIn("presentation-only", compare_help)

    def test_json_usage_failure_is_structured(self):
        process = run_cli("--output", "json", "wav", "inspect")
        self.assertEqual(process.returncode, check.EXIT_USAGE)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "error")
        self.assertEqual(data["error"], "invalid_arguments")
        self.assertSchema(data)
        self.assertIn("invalid_arguments", process.stderr)

    def test_retired_flat_alias_is_a_structured_usage_error(self):
        process = run_cli("--output", "json", "compare", self.wav)
        self.assertEqual(process.returncode, check.EXIT_USAGE)
        data = json.loads(process.stdout)
        self.assertEqual(data["command"], "root")
        self.assertEqual(data["error"], "invalid_arguments")
        self.assertSchema(data)

    def test_output_mode_may_not_be_repeated_across_parser_scopes(self):
        process = run_cli(
            "--output", "json", "wav", "inspect", self.wav,
            "--output", "human")
        self.assertEqual(process.returncode, check.EXIT_USAGE)
        data = json.loads(process.stdout)
        self.assertEqual(data["error"], "invalid_arguments")
        self.assertIn("exactly one output mode once", data["message"])
        self.assertSchema(data)

    def test_default_profile_is_visible_in_human_and_json_results(self):
        human = run_cli("wav", "compare", self.wav, self.wav)
        self.assertEqual(human.returncode, 0, human.stderr)
        self.assertIn("policy   full-track-v2", human.stdout)
        self.assertIn("every applicable gate must pass", human.stdout)

        structured = run_cli(
            "--output", "json", "wav", "compare", self.wav, self.wav)
        self.assertEqual(structured.returncode, 0, structured.stderr)
        data = json.loads(structured.stdout)
        self.assertEqual(data["policy"]["profile_id"], "full-track-v2")
        self.assertEqual(data["candidates"][0]["policy"]["profile_id"],
                         "full-track-v2")
        self.assertSchema(data)

    def test_json_inspect_success_has_clean_stdout(self):
        process = run_cli("--output", "json", "wav", "inspect",
                          self.wav)
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["command"], "wav.inspect")
        self.assertEqual(data["status"], "ok")
        self.assertIsInstance(data["audio"]["duration_seconds"], float)
        self.assertEqual(data["audio"]["sample_rate_hz"], check.RATE)
        self.assertEqual(data["audio"]["source_sha256"],
                         check.sha256_file(self.wav))
        self.assertEqual(data["clicks"]["event_count"], 0)
        self.assertEqual(data["failure_types"], [])
        self.assertSchema(data)
        self.assertEqual(process.stderr, "")

    def test_json_inspect_waveform_keeps_stdout_clean(self):
        process = run_cli(
            "--output", "json", "wav", "inspect", self.wav,
            "--view", "waveform", "--view-width", "16",
            "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "ok")
        self.assertNotIn("view input:", process.stdout)
        self.assertIn("view input: check.wav", process.stderr)
        self.assertIn("waveform", process.stderr)
        self.assertNotIn("waveform: check.wav", process.stderr)
        self.assertIn("rail samples 0", process.stderr)
        self.assertSchema(data)

    def test_json_stereo_correlation_keeps_stdout_clean_and_exposes_antiphase(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "antiphase.wav"
            phase = np.arange(check.RATE * 2) / check.RATE
            left = np.rint(8000.0 * np.sin(2 * np.pi * 220.0 * phase)).astype("<i2")
            channels = np.column_stack((left, -left)).astype("<i2")
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(2)
                wav.setsampwidth(2)
                wav.setframerate(check.RATE)
                wav.writeframes(channels.tobytes())
            process = run_cli(
                "--output", "json", "wav", "inspect", path,
                "--view", "stereo-correlation", "--view-width", "24",
                "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "ok")
        self.assertNotIn("stereo-correlation", process.stdout)
        self.assertIn("stereo-correlation", process.stderr)
        self.assertNotIn("stereo-correlation: anti", process.stderr)
        self.assertIn("selected corr -1.000", process.stderr)
        self.assertSchema(data)

    def test_json_inspect_click_is_a_structured_process_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "click.wav"
            time = np.arange(check.RATE * 2) / check.RATE
            samples = 8000.0 * np.sin(2 * np.pi * 220.0 * time)
            samples[check.RATE] += 6000.0
            write_wav(path, samples, gain=1.0)
            process = run_cli("--output", "json", "wav", "inspect", path)
            human = run_cli("wav", "inspect", path)
        self.assertEqual(process.returncode, check.EXIT_FAILURE, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "failed")
        self.assertEqual(data["failure_types"], ["clicks"])
        self.assertEqual(data["clicks"]["event_count"], 1)
        self.assertEqual(data["clicks"]["events"][0]["sample_index"],
                         check.RATE)
        self.assertSchema(data)
        self.assertEqual(process.stderr, "")
        self.assertEqual(human.returncode, check.EXIT_FAILURE, human.stderr)
        self.assertIn("click verdict: FAIL (click-v1)", human.stdout)

    def test_quiet_inspect_click_is_failed_and_exit_one(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "click.wav"
            samples = np.zeros(check.RATE)
            samples[check.RATE // 2] = 2000.0
            write_wav(path, samples, gain=1.0)
            process = run_cli("-q", "wav", "inspect", path)
        self.assertEqual(process.returncode, check.EXIT_FAILURE, process.stderr)
        self.assertEqual(process.stdout, "failed\n")
        self.assertEqual(process.stderr, "")

    def test_json_missing_input_is_structured_and_exit_three(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.wav"
            process = run_cli("--output", "json", "wav", "inspect", missing)
        self.assertEqual(process.returncode, check.EXIT_NOT_FOUND)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "error")
        self.assertEqual(data["error"], "input_not_found")
        self.assertFalse(data["retryable"])
        self.assertIn("suggestion", data)
        self.assertSchema(data)
        self.assertIn("input_not_found", process.stderr)

    def test_json_batch_has_one_result_per_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.wav"
            process = run_cli(
                "--output", "json", "wav", "compare",
                self.wav, self.wav, missing)
        self.assertEqual(process.returncode, check.EXIT_FAILURE)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "partial")
        self.assertEqual(data["summary"], {"total": 2, "ok": 1,
                                           "failed": 0, "error": 1})
        self.assertEqual([item["status"] for item in data["candidates"]],
                         ["ok", "error"])
        self.assertSchema(data)

    def test_uniform_batch_resource_error_retains_specific_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.wav"
            second = Path(directory) / "second.wav"
            process = run_cli(
                "--output", "json", "wav", "compare",
                self.wav, first, second)
        self.assertEqual(process.returncode, check.EXIT_NOT_FOUND)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "error")
        self.assertEqual(data["summary"]["error"], 2)
        self.assertSchema(data)

    def test_quiet_batch_is_bare_status_lines(self):
        process = run_cli(
            "-q", "wav", "compare", self.wav, self.wav, self.wav)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(process.stdout, "ok\nok\n")
        self.assertEqual(process.stderr, "")

    def test_terminal_views_compose_with_explicit_deterministic_geometry(self):
        process = run_cli(
            "wav", "compare", self.wav, self.wav,
            "--view", "metrics", "--view", "residual",
            "--layout", "columns", "--view-width", "16",
            "--lines-per-second", "1", "--max-lines", "6",
            "--axis", "first", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        title = next(line for line in process.stdout
                     .splitlines() if "metrics: check" in line)
        self.assertIn("residual: check", title)
        self.assertIn("view comparison: check.wav vs check.wav", process.stdout)
        self.assertNotIn("\x1b[", process.stdout)
        self.assertIn("P:", process.stdout)
        self.assertIn("candidate-refere", process.stdout)
        self.assertIn("scale ±1 PCM", process.stdout)
        self.assertIn("   0.0s└", process.stdout)

    def test_json_view_keeps_stdout_clean_and_routes_terminal_to_stderr(self):
        process = run_cli(
            "--output", "json", "wav", "compare", self.wav, self.wav,
            "--view", "waveform", "--view", "rms-level",
            "--view", "intersample-peak",
            "--view", "pitch-track",
            "--view", "rail-ratio",
            "--view", "peak-occupancy",
            "--view", "quantization-step",
            "--view", "flatline-ratio", "--view", "crest-factor",
            "--view", "block-repeat",
            "--view", "derivative-ratio", "--view", "sample-density",
            "--view", "spectral-change",
            "--view", "spectral-centroid",
            "--view", "spectral-flatness",
            "--view", "low-frequency-spectrum",
            "--view", "modulation-spectrum",
            "--view", "dc-offset", "--view", "stereo-balance",
            "--view", "stereo-level-diff",
            "--view", "stereo-correlation",
            "--view", "stereo-delay",
            "--view", "stereo-phase",
            "--view", "stereo-coherence",
            "--view", "wave-correlation",
            "--view", "metrics",
            "--view", "level-delta", "--view", "pitch-delta",
            "--view", "timing-drift", "--view", "contour",
            "--view", "spectral-diff", "--view", "phase-diff",
            "--view", "spectral-coherence",
            "--view", "band-delta",
            "--view", "residual-ratio",
            "--view-width", "16",
            "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["status"], "ok")
        self.assertNotIn("view comparison:", process.stdout)
        self.assertIn("view comparison: check.wav vs check.wav", process.stderr)
        self.assertIn("waveform: check", process.stderr)
        self.assertIn("intersample-peak", process.stderr)
        self.assertIn("pitch-track", process.stderr)
        self.assertIn("rms-level: check", process.stderr)
        self.assertIn("rail-ratio", process.stderr)
        self.assertIn("peak-occupancy", process.stderr)
        self.assertIn("GCD of occupied", process.stderr)
        self.assertIn("flatline-ratio", process.stderr)
        self.assertIn("block-repeat", process.stderr)
        self.assertIn("crest-factor: ch", process.stderr)
        self.assertIn("derivative-ratio", process.stderr)
        self.assertIn("spectral-change", process.stderr)
        self.assertIn("spectral-centroi", process.stderr)
        self.assertIn("spectral-flatnes", process.stderr)
        self.assertIn("low-frequency-sp", process.stderr)
        self.assertIn("modulation-spect", process.stderr)
        self.assertIn("sample-density: ", process.stderr)
        self.assertIn("dc-offset: check", process.stderr)
        self.assertIn("stereo-balance: ", process.stderr)
        self.assertIn("stereo-level-dif", process.stderr)
        self.assertIn("stereo-correlati", process.stderr)
        self.assertIn("stereo-delay: ch", process.stderr)
        self.assertIn("stereo-phase: ch", process.stderr)
        self.assertIn("stereo-coherence", process.stderr)
        self.assertIn("not applicable:", process.stderr)
        self.assertIn("wave-correlation", process.stderr)
        self.assertIn("metrics: check", process.stderr)
        self.assertIn("level-delta: che", process.stderr)
        self.assertIn("pitch-delta: che", process.stderr)
        self.assertIn("timing-drift: ch", process.stderr)
        self.assertIn("contour-level: c", process.stderr)
        self.assertIn("contour-timbre: ", process.stderr)
        self.assertIn("spectral-diff: c", process.stderr)
        self.assertIn("phase-diff: chec", process.stderr)
        self.assertIn("spectral-coheren", process.stderr)
        self.assertIn("band-delta: chec", process.stderr)
        self.assertIn("residual-ratio", process.stderr)
        self.assertSchema(data)

    def test_quiet_view_keeps_bare_status_and_routes_terminal_to_stderr(self):
        process = run_cli(
            "-q", "wav", "compare", self.wav, self.wav,
            "--view", "residual", "--view", "low-frequency-spectrum",
            "--view", "modulation-spectrum", "--view", "spectral-coherence",
            "--view-width", "16",
            "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(process.stdout, "ok\n")
        self.assertIn("view comparison: check.wav vs check.wav", process.stderr)
        self.assertIn("residual: check", process.stderr)
        self.assertIn("low-frequency-sp", process.stderr)
        self.assertIn("modulation-spect", process.stderr)
        self.assertIn("spectral-coheren", process.stderr)

    def test_quiet_stereo_view_keeps_bare_status_and_routes_view_to_stderr(self):
        process = run_cli(
            "-q", "wav", "inspect", self.wav,
            "--view", "stereo-balance", "--view", "stereo-level-diff",
            "--view", "stereo-correlation",
            "--view", "stereo-delay", "--view", "stereo-phase",
            "--view", "stereo-coherence",
            "--view-width", "16",
            "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(process.stdout, "ok\n")
        self.assertIn("stereo-balance", process.stderr)
        self.assertIn("stereo-level-dif", process.stderr)
        self.assertIn("stereo-correlati", process.stderr)
        self.assertIn("stereo-delay", process.stderr)
        self.assertIn("stereo-phase", process.stderr)
        self.assertIn("stereo-coherence", process.stderr)
        for title in ("stereo-balance", "stereo-level-diff",
                      "stereo-correlation", "stereo-delay", "stereo-phase",
                      "stereo-coherence"):
            self.assertNotIn(f"{title}: check.wav", process.stderr)
        self.assertIn("not applicable:", process.stderr)

    def test_minimum_width_click_legend_keeps_its_scale_explicit(self):
        process = run_cli(
            "wav", "inspect", self.wav, "--view", "clicks",
            "--view-width", "16", "--max-lines", "6", "--color", "never")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("view input: check.wav", process.stdout)
        self.assertIn("clicks", process.stdout)
        self.assertNotIn("clicks: check.wav", process.stdout)
        self.assertIn("!N event count", process.stdout)
        self.assertIn("bar=max severity", process.stdout)
        self.assertIn("full bar >=64x", process.stdout)

    def test_non_applicable_and_duplicate_views_are_structured_usage_errors(self):
        for view in ("residual", "spectral-coherence"):
            with self.subTest(view=view):
                invalid = run_cli(
                    "--output", "json", "wav", "inspect", self.wav,
                    "--view", view)
                self.assertEqual(invalid.returncode, check.EXIT_USAGE)
                invalid_data = json.loads(invalid.stdout)
                self.assertEqual(invalid_data["error"], "invalid_arguments")
                self.assertSchema(invalid_data)

        duplicate = run_cli(
            "--output", "json", "wav", "inspect", self.wav,
            "--view", "spectrogram", "--spectrogram")
        self.assertEqual(duplicate.returncode, check.EXIT_USAGE)
        duplicate_data = json.loads(duplicate.stdout)
        self.assertEqual(duplicate_data["error"], "duplicate_view")
        self.assertSchema(duplicate_data)

    def test_view_geometry_validation_is_explicit(self):
        cases = (("--view-width", "15", "invalid_view_width"),
                 ("--lines-per-second", "0", "invalid_line_density"),
                 ("--max-lines", "5", "invalid_max_lines"),
                 ("--view-range", "not-a-range", "invalid_range"))
        for flag, value, expected in cases:
            with self.subTest(flag=flag):
                process = run_cli(
                    "--output", "json", "wav", "inspect", self.wav,
                    "--view", "clicks", flag, value)
                self.assertEqual(process.returncode, check.EXIT_USAGE)
                data = json.loads(process.stdout)
                self.assertEqual(data["error"], expected)
                if flag == "--view-range":
                    self.assertIn("--view-range wants LO:HI", data["message"])
                self.assertSchema(data)

    def test_json_stdin_is_explicit_and_non_interactive(self):
        content = self.wav.read_bytes()
        process = run_cli("--output", "json", "wav", "inspect", "-",
                          input_bytes=content)
        self.assertEqual(process.returncode, 0, process.stderr.decode())
        data = json.loads(process.stdout)
        self.assertEqual(data["audio"]["path"], "-")
        self.assertEqual(data["audio"]["source_sha256"],
                         check.sha256_bytes(content))
        self.assertSchema(data)
        self.assertEqual(process.stderr, b"")

    def test_json_sfx_result_contains_every_analyzed_row(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wav_path, cart_path = root / "silent.wav", root / "cart.p8.png"
            samples = np.zeros(32 * check.SAMPLES_PER_TICK)
            write_wav(wav_path, samples, gain=1.0)
            rom = bytearray(0x8000)
            rom[0x3200 + 65] = 1
            write_cart_png(cart_path, rom)
            cart_sha256 = check.sha256_file(cart_path)
            process = run_cli("--output", "json", "sfx", "analyze", wav_path,
                              "--cart", cart_path, "--sfx", "0")
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(data["command"], "sfx.analyze")
        self.assertEqual(data["status"], "ok")
        self.assertEqual(len(data["rows"]), 32)
        self.assertEqual(data["summary"]["failed_row_count"], 0)
        self.assertEqual(data["clicks"]["event_count"], 0)
        self.assertEqual(data["failure_types"], [])
        self.assertEqual(data["cart_sha256"], cart_sha256)
        self.assertSchema(data)
        self.assertEqual(process.stderr, "")

    def test_spectrogram_artifact_is_retry_safe(self):
        try:
            import matplotlib  # noqa: F401
        except ImportError:
            self.skipTest("matplotlib is optional")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "inspect.png"
            command = ("--output", "json", "wav", "inspect", self.wav,
                       "--spectrogram-file", output)
            first = run_cli(*command)
            second = run_cli(*command)
            files = list(output.parent.iterdir())
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads(first.stdout)["status"], "ok")
        self.assertEqual(json.loads(second.stdout)["status"], "ok")
        self.assertIn("spectrogram written", first.stderr)
        self.assertEqual([path.name for path in files], ["inspect.png"])

    def test_batch_spectrogram_names_are_unique_even_when_labels_repeat(self):
        first = check_cli.image_path("build/diff.png", "same", True, 0)
        second = check_cli.image_path("build/diff.png", "same", True, 1)
        self.assertEqual(first, "build/diff-01-same.png")
        self.assertEqual(second, "build/diff-02-same.png")
        self.assertNotEqual(first, second)

        try:
            import matplotlib  # noqa: F401
        except ImportError:
            return
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diff.png"
            process = run_cli(
                "--output", "json", "wav", "compare",
                self.wav, self.wav, self.wav,
                "--labels", "same,same", "--spectrogram-file", output)
            files = sorted(path.name for path in output.parent.iterdir())
        self.assertEqual(process.returncode, 0, process.stderr)
        data = json.loads(process.stdout)
        self.assertEqual(
            [Path(item["spectrogram_file"]).name for item in data["candidates"]],
            ["diff-01-same.png", "diff-02-same.png"])
        self.assertEqual(files, ["diff-01-same.png", "diff-02-same.png"])
        self.assertSchema(data)

    def test_hidden_spectral_tilt_is_a_process_failure(self):
        reference, candidate = swept_noise_pair()
        with tempfile.TemporaryDirectory() as directory:
            reference_path = Path(directory) / "reference.wav"
            candidate_path = Path(directory) / "candidate.wav"
            scale = max(np.max(np.abs(reference)), np.max(np.abs(candidate)))
            gain = 12000.0 / scale
            write_wav(reference_path, reference, gain)
            write_wav(candidate_path, candidate, gain)
            process = subprocess.run(
                [sys.executable, str(ROOT / "tools/audio_analysis.py"),
                 "wav", "compare", str(reference_path), str(candidate_path)],
                cwd=ROOT, text=True, capture_output=True)
            json_process = run_cli(
                "--output", "json", "wav", "compare",
                reference_path, candidate_path)

        self.assertEqual(process.returncode, 1, process.stdout + process.stderr)
        self.assertIn("4-8 kHz", process.stdout)
        self.assertIn("FAIL (whole, quiet)", process.stdout)
        self.assertEqual(process.stderr, "")
        self.assertEqual(json_process.returncode, 1, json_process.stderr)
        data = json.loads(json_process.stdout)
        self.assertEqual(data["status"], "failed")
        self.assertEqual(data["candidates"][0]["status"], "failed")
        self.assertSchema(data)
        self.assertEqual(json_process.stderr, "")

    def test_identical_audio_succeeds_from_process_boundary(self):
        reference, _ = swept_noise_pair()
        with tempfile.TemporaryDirectory() as directory:
            reference_path = Path(directory) / "reference.wav"
            write_wav(reference_path, reference)
            process = subprocess.run(
                [sys.executable, str(ROOT / "tools/audio_analysis.py"),
                 "wav", "compare", str(reference_path), str(reference_path)],
                cwd=ROOT, text=True, capture_output=True)

        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertNotIn("FAIL", process.stdout)
        self.assertEqual(process.stderr, "")


class DocumentationTests(unittest.TestCase):
    def test_terminal_views_and_coloured_captures_stay_documented(self):
        documentation = (ROOT / "docs/audio-analysis.md").read_text()
        for view in ("spectrogram", "low-frequency-spectrum",
                     "modulation-spectrum", "pitch-track", "waveform", "clicks", "metrics",
                     "intersample-peak", "rms-level", "rail-ratio",
                     "peak-occupancy", "quantization-step",
                     "flatline-ratio", "block-repeat", "crest-factor",
                     "derivative-ratio", "spectral-change", "spectral-centroid",
                     "spectral-flatness",
                     "sample-density", "dc-offset",
                     "stereo-balance", "stereo-level-diff",
                     "stereo-correlation", "stereo-delay",
                     "stereo-phase", "stereo-coherence",
                     "spectral-coherence",
                     "wave-correlation",
                     "level-delta", "pitch-delta",
                     "timing-drift", "contour", "band-delta", "spectral-diff",
                     "phase-diff",
                     "residual-ratio", "residual"):
            self.assertIn(f"`{view}`", documentation)
        screenshots = (
            "terminal-spectrogram-diff.png",
            "terminal-phase-difference.png",
            "terminal-spectral-coherence.png",
            "terminal-pitch-track.png",
            "terminal-click-localization.png",
            "terminal-noise-contour.png",
            "terminal-band-delta.png",
            "terminal-pitch-spectrum.png",
            "terminal-level-timing.png",
            "terminal-residual-severity.png",
            "terminal-amplitude-health.png",
            "terminal-subrail-clipping.png",
            "terminal-intersample-peak.png",
            "terminal-wave-correlation.png",
            "terminal-stereo-cancellation.png",
            "terminal-stereo-phase.png",
            "terminal-stereo-level-diff.png",
            "terminal-stereo-coherence.png",
            "terminal-channel-loss.png",
            "terminal-stereo-delay.png",
            "terminal-crest-factor.png",
            "terminal-derivative-ratio.png",
            "terminal-spectral-change.png",
            "terminal-spectral-centroid.png",
            "terminal-spectral-flatness.png",
            "terminal-modulation-spectrum.png",
            "terminal-low-frequency-spectrum.png",
            "terminal-dropout-localization.png",
            "terminal-held-buffer.png",
            "terminal-replayed-buffer.png",
        )
        renderer = (ROOT / "docs/render-audio-analysis-screenshots.py").read_text()
        self.assertIn('"--output", "json"', renderer)
        self.assertIn('"--color", "always"', renderer)
        self.assertIn('"FiraCode-Retina.ttf"', renderer)
        self.assertIn('"FiraCode-Bold.ttf"', renderer)
        self.assertIn("RENDER_SCALE = 2", renderer)
        self.assertIn("direct PNG, 144 DPI, no SVG intermediate", renderer)
        for filename in screenshots:
            with self.subTest(filename=filename):
                self.assertIn(
                    f"images/audio-analysis/{filename}", documentation)
                self.assertIn(filename, renderer)
                path = ROOT / "docs/images/audio-analysis" / filename
                with Image.open(path) as image:
                    width, height = image.size
                    dpi = image.info.get("dpi", (0.0, 0.0))
                    self.assertEqual(image.info.get("Font"),
                                     "Fira Code Retina/Bold 32 px")
                    self.assertEqual(
                        image.info.get("TerminalCell"),
                        "20x40 physical px; 10x20 logical px at 2x")
                    self.assertEqual(
                        image.info.get("Capture"),
                        "direct PNG, 144 DPI, no SVG intermediate")
                    pixels = np.asarray(image.convert("RGB"))
                self.assertGreaterEqual(dpi[0], 143.5)
                self.assertGreaterEqual(dpi[1], 143.5)
                self.assertEqual((width - 64) % 20, 0)
                self.assertEqual((height - 64) % 40, 0)
                self.assertGreater(pixels.shape[1], 1500)
                self.assertTrue(np.any(np.ptp(pixels, axis=2) > 80),
                                "capture must contain ANSI colour")

        with Image.open(ROOT / "docs/images/audio-analysis"
                        / "terminal-stereo-delay.png") as image:
            pixels = np.asarray(image.convert("RGB"))
        occupied = np.any(pixels != np.array((13, 17, 23)), axis=2)

        def longest_run(rows):
            maximum = 0
            for row in rows:
                edges = np.flatnonzero(np.diff(np.r_[False, row, False]))
                if len(edges):
                    maximum = max(
                        maximum, int(np.max(edges[1::2] - edges[::2])))
            return maximum

        self.assertGreaterEqual(longest_run(occupied), 480,
                                "horizontal box rules must join across cells")
        self.assertGreaterEqual(longest_run(occupied.T), 300,
                                "vertical box rules must join across rows")

    def test_audio_view_name_and_compatibility_alias(self):
        self.assertIs(check.AudioView, check.SpectrogramView)


class ProvenanceTests(unittest.TestCase):
    def test_source_fingerprint_covers_the_psg_datapath(self):
        first, sources = track_gate.source_fingerprint()
        second, _ = track_gate.source_fingerprint()
        relative = {path.relative_to(ROOT).as_posix() for path in sources}
        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)
        self.assertIn("rtl/psg_walk.sv", relative)
        self.assertIn("rtl/psg_seq.sv", relative)
        self.assertIn("sim/psg_wav.cpp", relative)

    def test_manifest_fingerprints_reference_candidate_and_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference = root / "reference.wav"
            candidate = root / "candidate.wav"
            manifest = root / "candidate.json"
            reference.write_bytes(b"reference")
            candidate.write_bytes(b"candidate")
            source_sha, sources = track_gate.source_fingerprint()
            track_gate.write_manifest(
                manifest, source_sha=source_sha, sources=sources,
                audio=b"audio", reference=reference, candidate=candidate,
                music=30, mask=7, clock=28_125_000, samples=123)
            data = json.loads(manifest.read_text())

        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["source_sha256"], source_sha)
        self.assertEqual(data["audio_sha256"], track_gate.digest(b"audio"))
        self.assertEqual(data["reference_sha256"],
                         track_gate.digest(b"reference"))
        self.assertEqual(data["candidate_sha256"],
                         track_gate.digest(b"candidate"))
        self.assertEqual(data["comparison_policy"]["profile_id"],
                         "full-track-v2")
        self.assertIn("lock", data["comparison_policy"])
        self.assertIn("clicks", data["comparison_policy"])
        self.assertEqual(data["music"], 30)
        self.assertEqual(data["samples"], 123)


if __name__ == "__main__":
    unittest.main()
