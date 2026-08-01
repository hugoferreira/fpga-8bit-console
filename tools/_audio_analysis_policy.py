"""Versioned click and comparison policies for :mod:`audio_analysis`.

This module is private so the repository keeps one public audio-analysis
facade.  Policies live separately from the signal implementation to make a
verdict auditable: every threshold has a name, a stable profile identifier,
and a JSON representation which can be stored beside a render.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ClickPolicy:
    """Stable sparse-discontinuity detector and standalone verdict policy."""

    profile_id: str
    description: str
    context_radius_samples: int = 64
    guard_radius_samples: int = 2
    minimum_delta_pcm: float = 64.0
    minimum_severity_ratio: float = 8.0
    local_derivative_rms_floor_pcm: float = 1.0
    cluster_gap_samples: int = 3
    periodic_edge_max_gap_samples: int = 551
    periodic_edge_minimum_events: int = 3
    periodic_edge_similarity_ratio: float = 0.5
    maximum_reported_events: int = 32
    standalone_maximum_events: int = 0

    def as_dict(self) -> dict:
        """Return every detector threshold, including units, for JSON output."""
        return {
            "profile_id": self.profile_id,
            "description": self.description,
            "context_radius_samples": self.context_radius_samples,
            "guard_radius_samples": self.guard_radius_samples,
            "minimum_delta_pcm": self.minimum_delta_pcm,
            "minimum_severity_ratio": self.minimum_severity_ratio,
            "local_derivative_rms_floor_pcm":
                self.local_derivative_rms_floor_pcm,
            "cluster_gap_samples": self.cluster_gap_samples,
            "periodic_edge_max_gap_samples":
                self.periodic_edge_max_gap_samples,
            "periodic_edge_minimum_events":
                self.periodic_edge_minimum_events,
            "periodic_edge_similarity_ratio":
                self.periodic_edge_similarity_ratio,
            "maximum_reported_events": self.maximum_reported_events,
            "standalone_maximum_events": self.standalone_maximum_events,
        }


# PCM values in this repository use the signed 16-bit amplitude scale even
# after conversion to float64.  The local derivative guard identifies an edge
# which is exceptional for its immediate neighbourhood.  A second pass
# suppresses a train of at least three similar edges no more than 25 ms apart;
# this is what keeps square, pulse, and saw oscillators from becoming clicks.
# Phase resets every 100 ms and isolated sample impulses remain visible.
CLICK_V1 = ClickPolicy(
    profile_id="click-v1",
    description=(
        "Detect isolated PCM discontinuities relative to nearby derivative "
        "energy; suppress short-period trains of similar waveform edges."
    ),
)

CLICK_POLICIES = {CLICK_V1.profile_id: CLICK_V1}


def click_policy(profile: str | ClickPolicy | None = None) -> ClickPolicy:
    """Resolve a click detector profile ID or return a supplied policy."""
    if profile is None:
        return CLICK_V1
    if isinstance(profile, ClickPolicy):
        return profile
    try:
        return CLICK_POLICIES[profile]
    except KeyError as error:
        choices = ", ".join(sorted(CLICK_POLICIES))
        raise ValueError(f"unknown click profile {profile!r}; choose {choices}") from error


@dataclass(frozen=True)
class ComparisonPolicy:
    """All measurement and verdict thresholds for one comparison profile."""

    profile_id: str
    description: str
    score_minimum: float = 0.85
    pitched_reference_minimum: float = 0.25
    voiced_confidence_minimum: float = 0.30
    pitch_tolerance_semitones: float = 1.0
    live_rms_minimum: float = 50.0
    level_ratio_median_minimum: float | None = None
    level_ratio_median_maximum: float | None = None
    spectrum_cosine_median_minimum: float | None = None
    spectrum_cosine_p10_minimum: float | None = None
    band_tolerance_db: float = 1.5
    band_minimum_reference_share: float = 0.005
    band_live_power_floor: float = 1e-6
    quiet_reference_quantile: float = 0.35
    minimum_quiet_windows: int = 3
    lock_block_correlation_minimum: float = 0.70
    lock_lag_tolerance_samples: int = 8
    lock_median_correlation_minimum: float | None = None
    lock_tracked_ratio_minimum: float | None = None
    click_detection_policy: ClickPolicy = CLICK_V1
    click_match_tolerance_samples: int = 8
    click_maximum_unmatched_events: int | None = None

    def as_dict(self) -> dict:
        """Return the complete stable policy representation used in JSON."""
        return {
            "profile_id": self.profile_id,
            "description": self.description,
            "score": {"minimum": self.score_minimum},
            "reference": {
                "pitched_minimum": self.pitched_reference_minimum,
                "voiced_confidence_minimum": self.voiced_confidence_minimum,
            },
            "pitch": {
                "tolerance_semitones": self.pitch_tolerance_semitones,
            },
            "level": {
                "live_rms_minimum": self.live_rms_minimum,
                "median_ratio_minimum": self.level_ratio_median_minimum,
                "median_ratio_maximum": self.level_ratio_median_maximum,
            },
            "spectrum": {
                "cosine_median_minimum": self.spectrum_cosine_median_minimum,
                "cosine_p10_minimum": self.spectrum_cosine_p10_minimum,
            },
            "bands": {
                "tolerance_db": self.band_tolerance_db,
                "minimum_reference_share": self.band_minimum_reference_share,
                "live_power_floor": self.band_live_power_floor,
                "quiet_reference_quantile": self.quiet_reference_quantile,
                "minimum_quiet_windows": self.minimum_quiet_windows,
            },
            "lock": {
                "block_correlation_minimum":
                    self.lock_block_correlation_minimum,
                "lag_tolerance_samples": self.lock_lag_tolerance_samples,
                "median_correlation_minimum":
                    self.lock_median_correlation_minimum,
                "tracked_ratio_minimum": self.lock_tracked_ratio_minimum,
            },
            "clicks": {
                "detection": self.click_detection_policy.as_dict(),
                "match_tolerance_samples":
                    self.click_match_tolerance_samples,
                "maximum_unmatched_events":
                    self.click_maximum_unmatched_events,
            },
        }


# Calibrated against the five stored current-RTL/PICO-8 track pairs: their
# weakest applicable lock is 0.715 median / 0.493 tracked and spectrum is at
# least 0.994 median / 0.984 p10. A same-pitch, same-level synthetic render with
# phase reset every 100 ms measures 0.607 / 0.143 lock and 0.527 / 0.430
# spectrum. These guards leave measured corpus margin while rejecting that
# audible false green. Changing them requires a new profile ID.
FULL_TRACK_V1 = ComparisonPolicy(
    profile_id="full-track-v1",
    description=(
        "Gate pitch or contour, absolute bands, median level, spectral shape, "
        "and timing lock wherever each measurement applies."
    ),
    level_ratio_median_minimum=0.75,
    level_ratio_median_maximum=1.33,
    spectrum_cosine_median_minimum=0.90,
    spectrum_cosine_p10_minimum=0.80,
    lock_median_correlation_minimum=0.68,
    lock_tracked_ratio_minimum=0.45,
)


FULL_TRACK_V2 = ComparisonPolicy(
    profile_id="full-track-v2",
    description=(
        "Gate every full-track-v1 measurement plus candidate click events "
        "which do not match a reference event."
    ),
    level_ratio_median_minimum=0.75,
    level_ratio_median_maximum=1.33,
    spectrum_cosine_median_minimum=0.90,
    spectrum_cosine_p10_minimum=0.80,
    lock_median_correlation_minimum=0.68,
    lock_tracked_ratio_minimum=0.45,
    click_maximum_unmatched_events=0,
)


PITCH_BAND_V1 = ComparisonPolicy(
    profile_id="pitch-band-v1",
    description=(
        "Compatibility profile: gate pitch or contour and absolute band level; "
        "report level, spectral shape, and lock without gating them."
    ),
)


POLICIES = {
    FULL_TRACK_V2.profile_id: FULL_TRACK_V2,
    FULL_TRACK_V1.profile_id: FULL_TRACK_V1,
    PITCH_BAND_V1.profile_id: PITCH_BAND_V1,
}
DEFAULT_POLICY = FULL_TRACK_V2


def comparison_policy(profile: str | ComparisonPolicy | None = None) -> ComparisonPolicy:
    """Resolve a profile ID or return an already constructed policy."""
    if profile is None:
        return DEFAULT_POLICY
    if isinstance(profile, ComparisonPolicy):
        return profile
    try:
        return POLICIES[profile]
    except KeyError as error:
        choices = ", ".join(sorted(POLICIES))
        raise ValueError(f"unknown comparison profile {profile!r}; choose {choices}") from error


def comparison_profile_names() -> tuple[str, ...]:
    """Stable profile IDs accepted by the CLI."""
    return tuple(POLICIES)
