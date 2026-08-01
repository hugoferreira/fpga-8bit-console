"""Human presentation for the unified audio-comparison result.

This private module keeps terminal formatting out of the signal-analysis core.
The public facade remains ``audio_analysis``.
"""
from __future__ import annotations

import sys

from audio_analysis import (
    RATE,
    WINDOW,
    note_name,
    semitone_distance,
)


def report_click_analysis(result, *, out=sys.stdout, indent=""):
    """Render standalone click findings and their complete verdict boundary."""
    policy = result.policy
    threshold = (
        f"delta >= {policy.minimum_delta_pcm:.0f} PCM, severity >= "
        f"{policy.minimum_severity_ratio:.1f}x local derivative RMS")
    if result.events:
        print(f"{indent}clicks: {result.event_count} isolated discontinuity event(s); "
              f"limit {policy.standalone_maximum_events} "
              f"({policy.profile_id}; {threshold})",
              file=out)
        for event in result.events[:policy.maximum_reported_events]:
            print(f"{indent}  {event.time_seconds:.6f}s sample "
                  f"{event.sample_index}: delta {event.delta_pcm:+.0f} PCM, "
                  f"severity {event.severity_ratio:.1f}x", file=out)
        omitted = result.event_count - policy.maximum_reported_events
        if omitted > 0:
            print(f"{indent}  ... {omitted} more event(s) omitted", file=out)
    else:
        print(f"{indent}clicks: none ({policy.profile_id}; {threshold}); "
              f"suppressed {result.suppressed_periodic_edge_count} periodic "
              "waveform edge(s)", file=out)
    verdict = "ok" if result.passed else "FAIL"
    print(f"{indent}click verdict: {verdict} ({policy.profile_id})", file=out)
    return result.passed


def report_comparison(result, *, verbose=False, view=None,
                      reference_label="reference", out=sys.stdout):
    """Render one :class:`ComparisonResult`; never recompute its verdict."""
    data = result.data
    policy = data["policy"]
    label = data["label"]
    print(f"  {label}: {data['alignment_method']} lag "
          f"{data['lag_samples']:+d} samples "
          f"({data['lag_milliseconds']:+.1f} ms), "
          f"{data['window_count']} windows of {WINDOW / RATE:.1f} s", file=out)
    print(f"    policy   {policy['profile_id']}; every applicable gate must pass "
          "regardless of the aggregate score", file=out)
    if data["window_count"] < 1:
        print(f"    {data['overlap_samples'] / RATE:.3f}s of overlap is under "
              f"one {WINDOW / RATE:.1f} s window - nothing to compare", file=out)
    elif not data["pitched_reference"]:
        print("    UNPITCHED reference: pitch and lock are not applicable; "
              "contour carries the verdict.", file=out)
        if data["contour"] is not None:
            print(f"    contour  loudness "
                  f"{data['contour']['loudness_correlation']:.3f}, timbre "
                  f"{data['contour']['timbre_correlation']:.3f}", file=out)
    elif data["pitch"] and data["pitch"]["compared_window_count"]:
        pitch_result = data["pitch"]
        print(f"    pitch    {pitch_result['agreed_window_count']}/"
              f"{pitch_result['compared_window_count']} voiced windows within "
              f"{pitch_result['tolerance_semitones']:.1f} semitone = "
              f"{100 * pitch_result['agreement_ratio']:.1f}% "
              f"(boundary slack "
              f"{100 * pitch_result['boundary_slack_agreement_ratio']:.1f}%)",
              file=out)
    else:
        print("    pitch    no voiced reference windows were comparable", file=out)

    if data["level"] is not None:
        level = data["level"]
        print(f"    level    rms ratio median {level['rms_ratio_median']:.2f} "
              f"(p10 {level['rms_ratio_p10']:.2f}, "
              f"p90 {level['rms_ratio_p90']:.2f}); reference rms "
              f"{level['reference_rms_mean']:.0f}, render "
              f"{level['candidate_rms_mean']:.0f}", file=out)

    if data["spectrum"] is not None:
        spectrum_result = data["spectrum"]
        print(f"    spectrum cosine median "
              f"{spectrum_result['cosine_median']:.3f} "
              f"(p10 {spectrum_result['cosine_p10']:.3f})", file=out)

    if data["bands"]:
        print(f"    band level, dB render/reference (guard "
              f"+/-{policy['bands']['tolerance_db']:.1f} dB; quiet = lowest "
              f"{100 * policy['bands']['quiet_reference_quantile']:.0f}% of reference "
              "windows)", file=out)
        print("      band            whole   local   quiet", file=out)

        def value(number):
            return "   n/a" if number is None else f"{number:+6.2f}"

        for band in data["bands"]:
            failed = band["failed_scopes"]
            verdict = "" if not failed else f"   FAIL ({', '.join(failed)})"
            print(f"      {band['label']:<14} {value(band['whole_db'])} "
                  f"{value(band['local_db'])} {value(band['quiet_db'])}"
                  f"{verdict}", file=out)

    if data["lock"] is not None:
        lock_result = data["lock"]
        print(f"    lock     correlation at best lag: median "
              f"{lock_result['median_correlation']:.2f}; tracks the reference "
              f"in {lock_result['tracked_block_count']}/"
              f"{lock_result['block_count']} half-second blocks at a constant "
              f"lag of {lock_result['modal_lag_samples']} samples", file=out)
        if lock_result["lost_after_seconds"] is not None:
            print(f"    LOST LOCK for good after "
                  f"{lock_result['lost_after_seconds']:.1f}s of "
                  f"{lock_result['block_count'] * 0.5:.1f}s", file=out)

    clicks = data["clicks"]
    click_policy = clicks["candidate"]["policy"]
    click_limit = clicks["maximum_unmatched_events"]
    limit_text = "report-only" if click_limit is None else f"limit {click_limit}"
    print(f"    clicks   candidate {clicks['candidate']['event_count']}, reference "
          f"{clicks['reference']['event_count']}, matched "
          f"{clicks['matched_event_count']}, candidate-only "
          f"{clicks['unmatched_event_count']} ({limit_text}; "
          f"{click_policy['profile_id']}; match +/-"
          f"{clicks['match_tolerance_samples']} samples)", file=out)
    for event in clicks["unmatched_events"]:
        print(f"      click at {event['time_seconds']:.6f}s, sample "
              f"{event['sample_index']}: delta {event['delta_pcm']:+.0f} PCM, "
              f"severity {event['severity_ratio']:.1f}x", file=out)
    if clicks["unmatched_events_truncated"]:
        omitted = (clicks["unmatched_event_count"]
                   - clicks["reported_unmatched_event_count"])
        print(f"      ... {omitted} more candidate-only event(s) omitted", file=out)

    if data["first_pitch_mismatch_seconds"] is not None:
        bad = next(row for row in result.windows if row.pitch_agreed is False)
        print(f"    first mismatch at "
              f"{data['first_pitch_mismatch_seconds']:.1f}s "
              f"(reference {note_name(bad.reference_hz)}, "
              f"render {note_name(bad.candidate_hz)})", file=out)

    if verbose:
        print("      t/s     ref      render   err/st  rms ref/cand   cos", file=out)
        for row in result.windows:
            mark = ("     " if row.pitch_agreed is None
                    else "  ok " if row.pitch_agreed else " BAD ")
            error = (f"{semitone_distance(row.reference_hz, row.candidate_hz):6.2f}"
                     if row.reference_hz > 0 and row.candidate_hz > 0 else "   inf")
            print(f"    {row.index * WINDOW / RATE:6.1f} "
                  f"{note_name(row.reference_hz):>6}({row.reference_hz:6.1f}) "
                  f"{note_name(row.candidate_hz):>6}({row.candidate_hz:6.1f}) "
                  f"{error} {row.reference_rms:7.0f}/{row.candidate_rms:7.0f} "
                  f"{row.spectrum_cosine:5.3f} {mark}", file=out)

    if view is not None and view.wanted():
        view.show_comparison(result, reference_label=reference_label)
    if data["failure_types"]:
        print(f"    verdict  FAIL ({', '.join(data['failure_types'])})", file=out)
    else:
        print(f"    verdict  ok ({policy['profile_id']})", file=out)
    return result.passed
