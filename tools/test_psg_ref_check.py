#!/usr/bin/env python3
"""Regression tests for full-track PSG reference comparisons."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import psg_ref_check as check
import psg_track_gate as track_gate


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


class BandBalanceTests(unittest.TestCase):
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


class CommandContractTests(unittest.TestCase):
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
                [sys.executable, str(ROOT / "tools/psg_ref_check.py"),
                 str(reference_path), str(candidate_path)],
                cwd=ROOT, text=True, capture_output=True)

        self.assertEqual(process.returncode, 1, process.stdout + process.stderr)
        self.assertIn("4-8 kHz", process.stdout)
        self.assertIn("FAIL (whole, quiet)", process.stdout)
        self.assertEqual(process.stderr, "")

    def test_identical_audio_succeeds_from_process_boundary(self):
        reference, _ = swept_noise_pair()
        with tempfile.TemporaryDirectory() as directory:
            reference_path = Path(directory) / "reference.wav"
            write_wav(reference_path, reference)
            process = subprocess.run(
                [sys.executable, str(ROOT / "tools/psg_ref_check.py"),
                 str(reference_path), str(reference_path)],
                cwd=ROOT, text=True, capture_output=True)

        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertNotIn("FAIL", process.stdout)
        self.assertEqual(process.stderr, "")


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
        self.assertEqual(data["music"], 30)
        self.assertEqual(data["samples"], 123)


if __name__ == "__main__":
    unittest.main()
