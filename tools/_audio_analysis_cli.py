"""Command-line contract for the unified audio-analysis facade."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import wave

from audio_analysis import (
    AgentArgumentParser,
    CLICK_V1,
    CliFailure,
    CliUsageError,
    DEFAULT_POLICY,
    EFFECT_NAMES,
    EXIT_FAILURE,
    EXIT_NOT_FOUND,
    EXIT_PERMISSION,
    EXIT_SUCCESS,
    EXIT_USAGE,
    NOTE_NAMES,
    OptionalDependencyError,
    RATE,
    SAMPLES_PER_TICK,
    SCHEMA_VERSION,
    AudioView,
    WAVE_NAMES,
    analyze_clicks,
    analyze_comparison,
    analyze_sfx,
    comparison_policy,
    comparison_profile_names,
    describe_wav,
    display_name,
    emit_json,
    load_audio,
    report_click_analysis,
    report_comparison,
    report_sfx_analysis,
    sha256_file,
    wav_summary,
)


# ------------------------------------------------------------------- CLI ----

def parse_range(text):
    """'12:16' -> (12.0, 16.0); '12:' -> (12.0, None); ':4' -> (0.0, 4.0)."""
    if not text:
        return None
    lo, sep, hi = text.partition(":")
    if not sep:
        raise ValueError("--view-range wants LO:HI in seconds")
    try:
        start = float(lo) if lo else 0.0
        end = float(hi) if hi else None
    except ValueError:
        raise ValueError(f"--view-range: not a number in {text!r}")
    if start < 0 or (end is not None and end <= start):
        raise ValueError(f"--view-range: empty range {text!r}")
    return start, end


def image_path(base, label, many, index=0):
    """One image per candidate, so renders do not overwrite each other."""
    if not base or not many:
        return base
    stem, ext = os.path.splitext(base)
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in label)
    return f"{stem}-{index + 1:02d}-{safe}{ext}"


def output_mode(args):
    return "quiet" if getattr(args, "quiet", False) else getattr(args, "output", "human")


def requested_output_mode(argv):
    """Find the requested mode even when parsing later fails."""
    for index, token in enumerate(argv):
        if token == "--output" and index + 1 < len(argv):
            value = argv[index + 1]
            return value if value in ("human", "json") else "human"
        if token.startswith("--output="):
            value = token.partition("=")[2]
            return value if value in ("human", "json") else "human"
        if token in ("--quiet", "-q"):
            return "quiet"
    return "human"


def validate_output_mode_argv(argv):
    """Reject scope-dependent last-option-wins behavior before dispatch."""
    flags = [token for token in argv
             if token in ("--output", "--quiet", "-q")
             or token.startswith("--output=")]
    if len(flags) > 1:
        raise CliUsageError(
            "select exactly one output mode once; place --output or --quiet "
            "before the noun or after the verb")


def command_name(argv):
    words = [word for word in argv if word in ("wav", "sfx", "inspect",
                                                "compare", "analyze")]
    if "wav" in words and "inspect" in words:
        return "wav.inspect"
    if "wav" in words and "compare" in words:
        return "wav.compare"
    if "sfx" in words and "analyze" in words:
        return "sfx.analyze"
    return "root"


def load_cli_audio(path, field):
    try:
        return load_audio(path)
    except FileNotFoundError:
        raise CliFailure(
            "input_not_found", f"audio input does not exist: {path}",
            exit_code=EXIT_NOT_FOUND, field=field, value=path,
            suggestion="check the path or render the WAV before retrying")
    except PermissionError:
        raise CliFailure(
            "permission_denied", f"audio input is not readable: {path}",
            exit_code=EXIT_PERMISSION, field=field, value=path,
            suggestion="grant read permission or select another input")
    except (EOFError, ValueError, wave.Error) as error:
        raise CliFailure(
            "invalid_audio", str(error), exit_code=EXIT_USAGE,
            field=field, value=path,
            suggestion=f"provide 8- or 16-bit PCM at {RATE} Hz")
    except OSError as error:
        raise CliFailure(
            "input_unreadable", str(error), field=field, value=path,
            suggestion="check the input path and filesystem")


def parse_range_cli(value):
    try:
        return parse_range(value)
    except ValueError as error:
        raise CliFailure(
            "invalid_range", str(error), exit_code=EXIT_USAGE,
            field="view_range", value=value,
            suggestion="use LO:HI seconds, for example 12:16, 12:, or :4")


def selected_view_names(args):
    views = list(args.view or ())
    if args.spectrogram:
        views.append("spectrogram")
    duplicates = sorted({view for view in views if views.count(view) > 1})
    if duplicates:
        raise CliFailure(
            "duplicate_view", "each terminal view may be requested only once",
            exit_code=EXIT_USAGE, field="view", value=",".join(duplicates),
            suggestion="remove the repeated --view or --spectrogram alias")
    return tuple(views)


def make_view(args, *, path=None, inspection_channel_samples=None,
              reference_channel_samples=None, candidate_channel_samples=None):
    mode = output_mode(args)
    diagnostic_out = sys.stdout if mode == "human" else sys.stderr
    color = (args.color == "always"
             or (args.color == "auto" and diagnostic_out.isatty()
                 and not os.environ.get("NO_COLOR")))
    return AudioView(
        path=path, color=color, views=selected_view_names(args),
        window=parse_range_cli(args.view_range), out=diagnostic_out,
        layout=args.layout, width=args.view_width,
        lines_per_second=args.lines_per_second, max_lines=args.max_lines,
        axis=args.axis,
        inspection_channel_samples=inspection_channel_samples,
        reference_channel_samples=reference_channel_samples,
        candidate_channel_samples=candidate_channel_samples)


def validate_view_args(args, allowed_views):
    views = selected_view_names(args)
    invalid = [view for view in views if view not in allowed_views]
    if invalid:
        raise CliFailure(
            "view_not_applicable",
            f"terminal view {invalid[0]!r} is not available for this command",
            exit_code=EXIT_USAGE, field="view", value=invalid[0],
            suggestion=f"choose one of {', '.join(sorted(allowed_views))}")
    parse_range_cli(args.view_range)
    if args.view_range and not (views or args.spectrogram_file):
        raise CliFailure(
            "unused_range", "--view-range needs a terminal view or spectrogram file",
            exit_code=EXIT_USAGE, field="view_range", value=args.view_range,
            suggestion="add --view KIND or --spectrogram-file PATH")
    if not 16 <= args.view_width <= 110:
        raise CliFailure(
            "invalid_view_width", "--view-width must be in 16..110 cells",
            exit_code=EXIT_USAGE, field="view_width", value=args.view_width)
    if args.lines_per_second <= 0:
        raise CliFailure(
            "invalid_line_density", "--lines-per-second must be positive",
            exit_code=EXIT_USAGE, field="lines_per_second",
            value=args.lines_per_second)
    if args.max_lines < 6:
        raise CliFailure(
            "invalid_max_lines", "--max-lines must be at least 6",
            exit_code=EXIT_USAGE, field="max_lines", value=args.max_lines)


def render_inspection_view(view, label, samples, click_result, output_path):
    try:
        view.show_inspection(label, samples, click_result)
    except PermissionError:
        raise CliFailure(
            "permission_denied", f"cannot write spectrogram: {output_path}",
            exit_code=EXIT_PERMISSION, field="spectrogram_file", value=output_path,
            suggestion="select a writable output path")
    except (OSError, ValueError) as error:
        raise CliFailure(
            "output_write_failed", str(error), field="spectrogram_file",
            value=output_path, suggestion="check the output path and filesystem")


def run_wav_inspect(args):
    validate_view_args(
        args, {"spectrogram", "low-frequency-spectrum", "modulation-spectrum",
               "pitch-track", "waveform", "intersample-peak",
               "rms-level", "rail-ratio",
               "peak-occupancy",
               "quantization-step",
               "flatline-ratio",
               "block-repeat",
               "crest-factor", "derivative-ratio", "spectral-change",
               "spectral-centroid", "spectral-flatness", "sample-density",
               "dc-offset", "stereo-balance", "stereo-level-diff",
               "stereo-correlation",
               "stereo-delay", "stereo-phase", "stereo-coherence", "clicks"})
    loaded = load_cli_audio(args.wav, "wav")
    samples = loaded.samples
    mode = output_mode(args)
    summary = wav_summary(
        args.wav, samples, source_sha256=loaded.source_sha256)
    click_result = analyze_clicks(samples, rate=RATE, policy=CLICK_V1)
    if mode == "human":
        describe_wav(args.wav, samples)
        report_click_analysis(click_result, indent="  ")
    view = make_view(
        args, path=args.spectrogram_file,
        inspection_channel_samples=loaded.channel_samples)
    if view.wanted():
        render_inspection_view(
            view, display_name(args.wav), samples, click_result,
            args.spectrogram_file)

    result = {
        "schema_version": SCHEMA_VERSION,
        "command": "wav.inspect",
        "status": "ok" if click_result.passed else "failed",
        "failure_types": [] if click_result.passed else ["clicks"],
        "audio": summary,
        "clicks": click_result.as_dict(),
        "spectrogram_file": args.spectrogram_file,
    }
    if mode == "json":
        emit_json(result)
    elif mode == "quiet":
        print(result["status"])
    return EXIT_SUCCESS if click_result.passed else EXIT_FAILURE


def failure_item(failure, path, label):
    item = failure.as_dict("wav.compare")
    item.pop("schema_version", None)
    item.pop("command", None)
    item.update({"path": str(path), "label": label})
    return item


def run_wav_compare(args):
    validate_view_args(
        args, {"spectrogram", "low-frequency-spectrum", "modulation-spectrum",
               "pitch-track", "waveform", "intersample-peak",
               "sample-density", "dc-offset",
               "rms-level", "rail-ratio", "peak-occupancy", "quantization-step",
               "flatline-ratio", "block-repeat",
               "crest-factor",
               "derivative-ratio", "spectral-change", "spectral-centroid",
               "spectral-flatness",
               "stereo-balance", "stereo-level-diff", "stereo-correlation",
               "stereo-delay",
               "stereo-phase", "stereo-coherence",
               "wave-correlation", "metrics",
               "pitch-delta", "level-delta", "timing-drift", "contour",
               "spectral-diff", "phase-diff", "spectral-coherence",
               "band-delta", "clicks",
               "residual-ratio",
               "residual"})
    paths = [args.reference] + args.candidate
    if sum(str(path) == "-" for path in paths) > 1:
        raise CliFailure(
            "stdin_reused", "only one audio input can be read from stdin",
            exit_code=EXIT_USAGE, field="wav", value="-",
            suggestion="write one stream to a temporary WAV and pass its path")
    labels = (args.labels.split(",") if args.labels
              else [display_name(candidate) for candidate in args.candidate])
    if len(labels) != len(args.candidate) or any(not label for label in labels):
        raise CliFailure(
            "invalid_labels", "--labels must contain one non-empty label per candidate",
            exit_code=EXIT_USAGE, field="labels", value=args.labels,
            suggestion=f"provide {len(args.candidate)} comma-separated labels")

    mode = output_mode(args)
    policy = comparison_policy(args.profile)
    reference_audio = load_cli_audio(args.reference, "reference")
    reference = reference_audio.samples
    if mode == "human":
        describe_wav(args.reference, reference, indent="reference ")

    results, error_codes = [], []
    for index, (path, label) in enumerate(zip(args.candidate, labels)):
        try:
            candidate_audio = load_cli_audio(path, "candidate")
            candidate = candidate_audio.samples
            if mode == "human":
                describe_wav(path, candidate, indent=f"  {label} ")
            output_path = image_path(args.spectrogram_file, label,
                                     len(args.candidate) > 1, index)
            view = make_view(
                args, path=output_path,
                reference_channel_samples=reference_audio.channel_samples,
                candidate_channel_samples=candidate_audio.channel_samples)
            comparison_result = analyze_comparison(
                reference, candidate, label, policy=policy)
            if mode == "human":
                report_comparison(
                    comparison_result, verbose=args.verbose, view=view,
                    reference_label=display_name(args.reference))
            elif view.wanted():
                view.show_comparison(
                    comparison_result,
                    reference_label=display_name(args.reference))
            comparison = comparison_result.as_dict()
            comparison["audio"] = wav_summary(
                path, candidate,
                source_sha256=candidate_audio.source_sha256)
            comparison["spectrogram_file"] = output_path
            results.append(comparison)
        except CliFailure as failure:
            results.append(failure_item(failure, path, label))
            error_codes.append(failure.exit_code)
            print(f"audio_analysis: {failure.error}: {failure.message}", file=sys.stderr)
        except OptionalDependencyError as error:
            failure = CliFailure(
                "dependency_missing", str(error),
                suggestion="install matplotlib or omit --spectrogram-file")
            results.append(failure_item(failure, path, label))
            error_codes.append(failure.exit_code)
            print(f"audio_analysis: {failure.error}: {failure.message}", file=sys.stderr)
        except PermissionError:
            failure = CliFailure(
                "permission_denied", f"cannot write spectrogram: {output_path}",
                exit_code=EXIT_PERMISSION, field="spectrogram_file", value=output_path,
                suggestion="select a writable output path")
            results.append(failure_item(failure, path, label))
            error_codes.append(failure.exit_code)
            print(f"audio_analysis: {failure.error}: {failure.message}", file=sys.stderr)
        except (OSError, ValueError) as error:
            failure = CliFailure(
                "output_write_failed", str(error), field="spectrogram_file",
                value=output_path, suggestion="check the output path and filesystem")
            results.append(failure_item(failure, path, label))
            error_codes.append(failure.exit_code)
            print(f"audio_analysis: {failure.error}: {failure.message}", file=sys.stderr)

    counts = {
        "total": len(results),
        "ok": sum(item["status"] == "ok" for item in results),
        "failed": sum(item["status"] == "failed" for item in results),
        "error": sum(item["status"] == "error" for item in results),
    }
    if counts["ok"] == counts["total"]:
        status = "ok"
    elif counts["error"] == counts["total"]:
        status = "error"
    elif counts["error"]:
        status = "partial"
    else:
        status = "failed"
    payload = {
        "schema_version": SCHEMA_VERSION,
        "command": "wav.compare",
        "status": status,
        "policy": policy.as_dict(),
        "reference": wav_summary(
            args.reference, reference,
            source_sha256=reference_audio.source_sha256),
        "candidates": results,
        "summary": counts,
    }
    if mode == "json":
        emit_json(payload)
    elif mode == "quiet":
        for result in results:
            print(result["status"])

    if status == "ok":
        return EXIT_SUCCESS
    if counts["failed"]:
        return EXIT_FAILURE
    if counts["error"] == counts["total"] and len(set(error_codes)) == 1:
        return error_codes[0]
    return EXIT_FAILURE


def sfx_payload(args, loaded, cart_sha256, result, click_result):
    samples = loaded.samples
    rows = [{
        "index": row.index,
        "requested_pitch": row.pitch,
        "requested_note": f"{NOTE_NAMES[row.pitch % 12]}{row.pitch // 12}",
        "wave": WAVE_NAMES[row.wave],
        "volume": row.volume,
        "effect": EFFECT_NAMES[row.effect],
        "custom_instrument": row.custom,
        "rms": row.rms,
        "peak": row.peak,
        "measured_hz": row.measured_hz if row.measured_hz > 0 else None,
        "pitch_error_semitones": row.pitch_error,
        "energy_verdict": row.energy_verdict,
        "pitch_verdict": row.pitch_verdict,
        "status": "failed" if row.failed else "ok",
    } for row in result.rows]
    failures = len(result.failures)
    failure_types = []
    if failures:
        failure_types.append("sfx_rows")
    if not click_result.passed:
        failure_types.append("clicks")
    return {
        "schema_version": SCHEMA_VERSION,
        "command": "sfx.analyze",
        "status": "failed" if failure_types else "ok",
        "failure_types": failure_types,
        "audio": wav_summary(
            args.wav, samples, source_sha256=loaded.source_sha256),
        "clicks": click_result.as_dict(),
        "cart": str(args.cart),
        "cart_sha256": cart_sha256,
        "sfx_index": result.index,
        "speed_ticks_per_row": result.speed,
        "row_duration_milliseconds": result.speed * SAMPLES_PER_TICK / RATE * 1000.0,
        "loop_start": result.loop_start,
        "loop_end": result.loop_end,
        "filter_flags": result.filter_flags,
        "rows": rows,
        "summary": {
            "row_count": len(rows),
            "failed_row_count": failures,
            "missing_row_count": sum(row.energy_verdict == "missing" for row in result.rows),
            "leaking_row_count": sum(row.energy_verdict == "leak" for row in result.rows),
            "pitch_mismatch_count": sum(row.pitch_verdict == "mismatch" for row in result.rows),
            "pitch_tested_count": sum(row.pitch_verdict != "n/a" for row in result.rows),
        },
    }


def run_sfx_analyze(args):
    if not args.cart.exists():
        raise CliFailure(
            "cart_not_found", f"cart does not exist: {args.cart}",
            exit_code=EXIT_NOT_FOUND, field="cart", value=args.cart,
            suggestion="provide an existing PICO-8 .p8.png cartridge")
    if not args.cart.is_file():
        raise CliFailure(
            "invalid_cart", f"cart is not a file: {args.cart}",
            exit_code=EXIT_USAGE, field="cart", value=args.cart,
            suggestion="provide a PICO-8 .p8.png file")
    loaded = load_cli_audio(args.wav, "wav")
    samples = loaded.samples
    try:
        cart_sha256 = sha256_file(args.cart)
        from p8_audio import rom_from_png
        rom = rom_from_png(str(args.cart))
    except PermissionError:
        raise CliFailure(
            "permission_denied", f"cart is not readable: {args.cart}",
            exit_code=EXIT_PERMISSION, field="cart", value=args.cart)
    except (OSError, ValueError) as error:
        raise CliFailure(
            "invalid_cart", str(error), exit_code=EXIT_USAGE,
            field="cart", value=args.cart,
            suggestion="provide a readable PICO-8 .p8.png cartridge")
    try:
        result = analyze_sfx(samples, rom, args.sfx,
                             silent_below=args.silent_below,
                             pitch_tolerance=args.pitch_tolerance)
    except ValueError as error:
        raise CliFailure(
            "invalid_analysis_parameters", str(error), exit_code=EXIT_USAGE,
            field="sfx", value=args.sfx,
            suggestion="use --sfx 0..63 and non-negative thresholds")

    mode = output_mode(args)
    click_result = analyze_clicks(samples, rate=RATE, policy=CLICK_V1)
    payload = sfx_payload(args, loaded, cart_sha256, result, click_result)
    if mode == "human":
        describe_wav(args.wav, samples)
        report_click_analysis(click_result, indent="  ")
        report_sfx_analysis(result)
    elif mode == "json":
        emit_json(payload)
    else:
        print(payload["status"])
    return EXIT_SUCCESS if payload["status"] == "ok" else EXIT_FAILURE


def add_output_options(parser, *, root=False):
    default = "human" if root else argparse.SUPPRESS
    quiet_default = False if root else argparse.SUPPRESS
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--output", choices=("human", "json"), default=default,
        help=("stdout format (default: human); json emits one strict JSON "
              "object; specify this option once"))
    group.add_argument(
        "-q", "--quiet", action="store_true", default=quiet_default,
        help="emit only stable status values, one per result; specify once")


def add_visualization_options(parser, view_choices):
    parser.add_argument(
        "--view", action="append",
        choices=view_choices,
        help=("repeatable independent terminal view; JSON/quiet routes views "
              "to stderr"))
    parser.add_argument(
        "--spectrogram", action="store_true",
        help="compatibility alias for --view spectrogram")
    parser.add_argument(
        "--spectrogram-file", metavar="PATH",
        help="write/replace a PNG/PDF/SVG; requires matplotlib")
    parser.add_argument(
        "--view-range", "--spectrogram-range", dest="view_range",
        metavar="LO:HI",
        help="seconds rendered by every view, e.g. 12:16 (default: all)")
    parser.add_argument(
        "--layout", choices=("rows", "columns"), default="rows",
        help="compose requested terminal panels (default: rows)")
    parser.add_argument(
        "--view-width", type=int, default=32, metavar="CELLS",
        help=("content width of each independent panel; titles/footer prose "
              "clip, colliding frequency labels are omitted "
              "(default: 32; range: 16..110)"))
    parser.add_argument(
        "--lines-per-second", type=float, default=2.0, metavar="N",
        help="time density shared by all views (default: 2.0; must be >0)")
    parser.add_argument(
        "--max-lines", type=int, default=120, metavar="N",
        help="maximum time rows per view (default: 120; minimum: 6)")
    parser.add_argument(
        "--axis", choices=("auto", "first", "each", "none"), default="auto",
        help=("time-axis placement (default: auto; each for row layout, first "
              "for column layout)"))
    parser.add_argument(
        "--color", choices=("auto", "always", "never"), default="auto",
        help="terminal colour policy (default: auto; respects NO_COLOR)")


def make_parser():
    """Build the complete noun-verb grammar for help and contract tests."""
    parser = AgentArgumentParser(
        description="Inspect, compare, and diagnose 22,050 Hz PCM audio.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Command tree:
  wav inspect     read metadata, detect clicks, and render optional terminal views
  wav compare     compare one or more candidates with a reference
  sfx analyze     check a rendered SFX against its cartridge rows

Exit codes: 0 success; 1 measured/general failure; 2 invalid input or usage;
3 resource not found; 4 permission denied. Commands are non-interactive.
Only --spectrogram-file writes state; it idempotently replaces the named file.
Repeat --view to compose independent terminal panels. Explicit geometry is stable
across TTY sizes; JSON/quiet stdout never contains terminal visualization text.
wav inspect and sfx analyze use click-v1 and fail on any isolated discontinuity.
wav compare defaults to full-track-v2: every applicable pitch/contour, level,
spectrum, band, lock, and unmatched-click gate must pass; score alone is not
the verdict. full-track-v1 keeps its historical non-click verdict.

Examples:
  audio_analysis.py --output json wav inspect render.wav
  audio_analysis.py wav compare reference.wav candidate.wav
  audio_analysis.py -q sfx analyze render.wav --cart game.p8.png --sfx 8""")
    add_output_options(parser, root=True)
    nouns = parser.add_subparsers(
        dest="noun", required=True, parser_class=AgentArgumentParser)

    wav_parser = nouns.add_parser(
        "wav", help="inspect WAV files and compare rendered audio",
        description="Read-only WAV inspection and reference comparison.")
    add_output_options(wav_parser)
    wav_verbs = wav_parser.add_subparsers(
        dest="verb", required=True, parser_class=AgentArgumentParser)

    inspect_parser = wav_verbs.add_parser(
        "inspect", help="report WAV metadata, detect clicks, and optionally draw a spectrogram",
        description="Inspect one WAV and fail when click-v1 detects an artifact.",
        epilog="""INPUT may be '-' for stdin. --spectrogram-file is the only side
effect and replaces that file on retry. JSON stdout is one object; quiet stdout
is ok or failed. click-v1 fails on any isolated edge with delta >=64 PCM and
severity >=8x surrounding derivative RMS. Adjacent edges within 3 samples are
one event; trains of at least 3 similar edges no more than 551 samples apart are
treated as periodic square/pulse/saw structure, not clicks. At most 32 events
are printed, while JSON always retains the total and a truncation flag. Terminal
views share a newest-at-top time grid; repeat --view and select --layout.
Every plot has a separate horizontal boundary before its prose footer;
frequency plots add non-overlapping Hz ticks to that boundary.
The leading view-input line names INPUT once; inspect panel titles omit that
redundant filename.
pitch-track reuses the analyzer's non-overlapping 100 ms autocorrelation windows,
70..1200 Hz bounds, and >=0.30 voiced-confidence floor on a fixed log scale.
waveform is a min/max PCM envelope scaled to the selected range's peak and
reports exact signed-16-bit rail sample counts. Click rows prefix their event
count and scale the bar by maximum severity, with a full bar at >=64x local
derivative RMS. sample-density shows a fixed signed-16-bit amplitude histogram
per time row; dc-offset plots the signed per-row mean on a dynamic scale with a
minimum of +/-256 PCM. crest-factor plots peak/RMS per displayed time row on a
fixed 0..24 dB scale and leaves silence blank. derivative-ratio plots first-
difference RMS versus mean-removed signal RMS on a fixed -48..+6 dB scale;
constant and silent rows are blank. rms-level plots absolute row RMS on a fixed
-96..0 dBFS scale and places exact silence at the left edge. These are
diagnostic views and do not change the click verdict. rail-ratio plots exact
signed-16-bit rail occupancy on a fixed logarithmic 1 ppm..100% scale;
zero-rail rows stay at the left edge.
intersample-peak estimates four reconstruction phases with a 33-tap Hann-
windowed sinc and plots the peak on a fixed -12..+6 dBFS scale. Values above
0 dBFS are red; 16 selected-range edge samples are omitted because they lack
full context. This is not a standards true-peak meter and has no verdict effect.
peak-occupancy counts samples within 1% of each row's absolute peak on a fixed
0..100% scale, exposing flat-topping below the signed-16-bit rails. Its footer
recomputes whole-range occupancy from the whole-range peak, not a row average.
quantization-step plots the GCD of gaps between occupied non-rail integer PCM
levels on a fixed logarithmic 1..32768 PCM scale. spectral-change plots the
maximum cosine change between consecutive
normalized 1024-sample Hann spectra at a 512-sample hop on a fixed 0..1 scale.
spectral-centroid plots DC-removed magnitude centroid in non-overlapping 100 ms
windows on a fixed logarithmic 55..11025 Hz scale.
spectral-flatness plots 55..8000 Hz power-spectrum Wiener entropy in
non-overlapping 100 ms Hann windows on a fixed 0..1 tonal-to-noisy scale.
modulation-spectrum derives a 110-sample RMS envelope every 55 samples, then
maps 512-envelope-sample Hann FFTs at a 256-sample hop over 1..100 Hz log
frequency. Sinusoidal envelope magnitude is normalized by each frame's local
mean RMS and plotted on a fixed -60..0 dB modulation-depth scale. The envelope
rate is 400.909091 Hz, each FFT spans 1.277098 s, and bins are 0.783025 Hz.
Silence, unavailable time, and depth at or below -60 dB remain at the floor.
Natural beats, tremolo, and rhythmic pumping can be intentional. This is an
RMS-envelope diagnostic, not carrier-frequency analysis or a verdict.
low-frequency-spectrum maps DC-removed carrier energy over 1..250 Hz using
16384-sample Hann FFTs at an 8192-sample hop. Magnitudes are calibrated to
signed-16-bit full scale and plotted on a fixed -96..0 dBFS amplitude scale;
FFT duration is 0.743039 s, hop is 0.371519 s, and bins are 1.345825 Hz.
The frequency axis is linear so 50/60 Hz hum and their harmonics remain
separable. Ranges shorter than 16384 samples are explicitly too short. This is
carrier frequency, not envelope-modulation rate; bass and rumble can be
intentional. It is diagnostic only and does not change JSON, click verdict, or
exit status.
stereo-balance uses original decoded channels 1 and 2 on a fixed -24..+24 dB
R/L RMS scale; one-sided silence pins to the corresponding red edge, both-silent
rows are blank, and mono is explicitly not applicable. It does not change mono
analysis, JSON, the click verdict, or exit status.
stereo-level-diff maps signed channel-2-minus-channel-1 energy over time and
55..8000 Hz log frequency using 1024-sample Hann FFTs at a 512-sample hop. It
clips both channels to one shared -60 dB floor, leaves differences below 3 dB
blank, and reaches full blue/red glyphs at -/+24 dB. Blue/< means channel 2 is
quieter; red/> means it is louder. Mono is explicitly not applicable and inputs
with more than two channels use only channels 1/2. It is diagnostic only and
does not change mono analysis, JSON, the click verdict, or exit status.
stereo-correlation uses original decoded channels 1 and 2 on a fixed -1..+1
Pearson scale; mono is explicitly not applicable, flat channels are blank, and
inputs with more than two channels use only channels 1/2. It does not change the
mono analysis, JSON result, click verdict, or exit status.
stereo-delay searches original decoded channels 1 and 2 over a fixed -5..+5 ms
range. Positive means channel 2 is later. A row is drawn only when the strongest
absolute Pearson peak is >=0.50 and exceeds every other local peak by >=0.05;
periodic, flat, short, and otherwise ambiguous rows are blank. Search-edge hits
are red because the true delay may be outside the range. It is diagnostic only
and does not change mono analysis, JSON, the click verdict, or exit status.
stereo-phase maps wrapped channel-2-minus-channel-1 phase over time and log
frequency using 1024-sample Hann FFTs at a 512-sample hop. It uses the same
fixed -180..+180 degree, coherence >=0.80, shared -60 dB power-floor, and
5-degree neutral-zone contract as phase-diff. Positive/red means channel 2
leads; negative/blue means it lags. Mono is explicitly not applicable and
inputs with more than two channels use only channels 1/2. It is diagnostic only
and does not change mono analysis, JSON, the click verdict, or exit status.
stereo-coherence maps the magnitude of the normalized complex channel-1/2
cross-spectrum over time and 55..8000 Hz log frequency. It uses 1024-sample
Hann FFTs at a 512-sample hop and requires both channels within the shared
-60 dB power range. The fixed 0..1 glyph scale is X below .25, O below .50,
o below .75, . below .90, and a dot at or above .90. This is normalized
coherence, not magnitude-squared coherence. Low values can be intentional
stereo width, reverb, or independent noise. Mono is explicitly not applicable;
inputs with more than two channels use channels 1/2. It is diagnostic only and
does not change mono analysis, JSON, the click verdict, or exit status.
flatline-ratio plots the percentage of exactly equal adjacent decoded PCM
samples on a fixed 0..100% scale. block-repeat compares each displayed time row
with its immediate
predecessor using Pearson correlation on a fixed -1..+1 scale; the first
chronological and constant rows are blank. Each block starts with the full input
label.
Examples:
  audio_analysis.py wav inspect render.wav --view sample-density --view dc-offset --layout columns
  producer | audio_analysis.py --output json wav inspect -""")
    add_output_options(inspect_parser)
    inspect_parser.add_argument("wav", metavar="INPUT", help="WAV path, or '-' for stdin")
    add_visualization_options(
        inspect_parser,
        ("spectrogram", "low-frequency-spectrum", "modulation-spectrum",
         "pitch-track", "waveform", "intersample-peak",
         "rms-level", "rail-ratio",
         "peak-occupancy",
         "quantization-step", "flatline-ratio",
         "block-repeat",
         "crest-factor", "derivative-ratio", "spectral-change",
         "spectral-centroid", "spectral-flatness", "sample-density", "dc-offset",
         "stereo-balance", "stereo-level-diff", "stereo-correlation",
         "stereo-delay",
         "stereo-phase", "stereo-coherence", "clicks"))
    inspect_parser.set_defaults(handler=run_wav_inspect)

    compare_parser = wav_verbs.add_parser(
        "compare", help="compare candidate WAVs with one reference",
        description="Analyze one or more candidates against a reference WAV.",
        epilog="""REFERENCE or one CANDIDATE may be '-' for stdin. JSON returns one
object with a result for every candidate. Quiet emits one ok/failed/error token
per candidate in input order. Aggregate JSON status is partial when some inputs
could not be analyzed. Batch exit is 1 for measured or mixed failures; a
uniform resource error is retained only when every candidate has that error.
The default full-track-v2 profile requires score >=0.85, median RMS ratio
0.75..1.33, spectrum cosine median/p10 >=0.90/0.80, active bands within 1.5 dB,
and (when applicable) lock median/tracked ratio >=0.68/0.45. It also requires
zero click-v1 candidate events unmatched within +/-8 samples of a reference
event. Score is only the pitch-or-contour aggregate; status is failed when any
applicable gate fails. full-track-v1 reports clicks but preserves the historical
non-click verdict. pitch-band-v1 gates only score and bands. Select either legacy
profile explicitly.
Terminal views are independent panels over one newest-at-top time grid.
Every plot has a separate horizontal boundary before its prose footer;
frequency plots add non-overlapping Hz ticks to that boundary.
Comparison panel titles retain reference/candidate labels for attribution.
metrics shows worst pitch/level/spectrum/click state per row; clicks shows candidate-only
event severity; pitch-track shows absolute voiced pitch on a fixed log-frequency
scale; waveform shows reference/candidate min/max PCM envelopes on one
shared scale; intersample-peak estimates four reconstruction phases with a
33-tap Hann-windowed sinc on a fixed -12..+6 dBFS scale; values above 0 are red,
16 selected-range edge samples are omitted, and it is explicitly not a
standards true-peak meter; rms-level plots absolute RMS on a fixed -96..0 dBFS scale;
rail-ratio plots exact full-scale sample occupancy on a fixed logarithmic scale;
peak-occupancy plots row-local near-peak sample occupancy on a fixed 0..100%
scale;
quantization-step plots the occupied integer PCM lattice on a fixed log2 scale;
flatline-ratio plots exact adjacent-sample equality on a fixed 0..100% scale;
block-repeat correlates each displayed row with its immediate predecessor;
crest-factor plots peak/RMS dynamics on a fixed 0..24 dB scale; derivative-ratio
plots first-difference/AC RMS on a fixed -48..+6 dB scale;
spectral-change plots adjacent-frame normalized spectral-shape change;
spectral-centroid plots absolute DC-removed spectral brightness;
spectral-flatness plots absolute power-spectrum tonality versus noisiness;
modulation-spectrum maps 1..100 Hz RMS-envelope modulation depth using a fixed
110-sample RMS window, 55-sample envelope hop, 512-sample Hann FFT, 256-sample
FFT hop, and -60..0 dB depth scale. The 400.909091 Hz envelope rate yields a
1.277098 s FFT duration and 0.783025 Hz bins. It is local-mean normalized,
presentation-only, and does not analyze carrier frequency; natural beats,
tremolo, or pumping may be intentional;
low-frequency-spectrum maps DC-removed 1..250 Hz carrier energy with a
16384-sample Hann FFT, 8192-sample hop, linear frequency axis, and fixed
-96..0 dBFS amplitude scale. At 22050 Hz the FFT duration is 0.743039 s, hop is
0.371519 s, and bins are 1.345825 Hz. It separates 50/60 Hz hum that the normal
55..8000 Hz, 1024-sample spectrogram can collapse. It is presentation-only;
bass and rumble can be intentional, and carrier Hz must not be confused with
modulation-spectrum envelope rate;
sample-density shows time-local amplitude histograms on the fixed signed-16-bit
range; dc-offset plots signed per-row means on one shared dynamic scale;
stereo-balance plots original decoded channel-2/channel-1 RMS on a fixed
-24..+24 dB scale; one-sided silence pins red to an edge, both-silent rows are
blank, and mono is explicitly not applicable;
stereo-level-diff maps signed channel-2-minus-channel-1 energy over time and
55..8000 Hz log frequency using 1024-sample Hann FFTs at a 512-sample hop. It
uses one shared -60 dB floor, blanks absolute differences below 3 dB, and
reaches full blue/red glyphs at -/+24 dB. Mono is explicitly not applicable;
inputs with more than two channels use channels 1/2; candidate channels receive
the same global comparison alignment as other candidate views. It has no
verdict effect;
stereo-correlation plots original decoded channels 1 and 2 on a fixed -1..+1
Pearson scale, where -1 exposes anti-phase cancellation hidden by mono downmix;
mono is explicitly not applicable, flat channels are blank, and inputs with
more than two channels use only channels 1/2. This presentation context does
not change the mono analysis, JSON result, verdict, or exit status;
stereo-delay searches original channels 1 and 2 on a fixed -5..+5 ms lag scale;
positive means channel 2 is later, rows require absolute Pearson >=0.50 and a
>=0.05 margin over every other local peak, and periodic/flat/short/ambiguous
rows are blank. Search-edge hits are red; it has no verdict effect;
stereo-phase maps wrapped channel-2-minus-channel-1 phase over time and log
frequency using the same fixed FFT, phase, coherence, power-floor, and neutral-
zone contract as phase-diff. Mono is explicitly not applicable; inputs with
more than two channels use channels 1/2; candidate channels receive the same
global comparison alignment as other candidate views. It has no verdict effect;
stereo-coherence maps normalized complex channel-1/2 cross-spectrum magnitude
over time and 55..8000 Hz using the same 1024/512 STFT and shared -60 dB power
floor as stereo-phase. Its fixed 0..1 glyph scale makes low-coherence shared
energy explicit where stereo-phase would be blank. It is normalized coherence,
not magnitude-squared coherence; mono is not applicable, more-than-stereo input
uses channels 1/2, and low values can be intentional width, reverb, or noise.
Candidate channels receive global comparison alignment; it has no verdict
effect;
wave-correlation plots mean-removed Pearson correlation from -1 polarity
inversion through 0 unrelated to +1 identical; level-delta plots signed
per-window RMS error; pitch-delta plots signed semitone error; timing-drift
plots half-second best-lag movement;
contour expands to normalized loudness/timbre trajectory overlays for unpitched
material; band-delta maps the four calibrated policy bands and quiet windows;
spectral-diff maps signed candidate/reference energy by time and log frequency;
phase-diff maps wrapped candidate-minus-reference phase by time and log
frequency after comparison sample alignment. It uses 1024-sample Hann FFTs at
a 512-sample hop on a fixed -180..+180 degree scale. Cells are blank when
absolute phase is below 5 degrees, normalized cross-spectrum coherence is below
0.80, or either input is more than 60 dB below the shared cell-power peak.
Positive/red means the candidate leads; negative/blue means it lags. Phase is
wrapped, presentation-only, and does not change JSON, verdict, or exit status;
spectral-coherence maps normalized complex reference/candidate cross-spectrum
magnitude over time and 55..8000 Hz using the same 1024-sample Hann FFT,
512-sample hop, and shared -60 dB power floor as phase-diff. The fixed 0..1
glyph scale is X below .25, O below .50, o below .75, . below .90, and a dot at
or above .90. It makes shared but decorrelated energy explicit where phase-diff
is blank. This is normalized coherence, not magnitude-squared coherence; low
values can be intentional modulation, noise, or processing. It is comparison-
only and presentation-only; only wav compare supports this view. It does not
change JSON, verdict, or exit status;
residual-ratio plots aligned residual/reference RMS on a fixed -60..+6 dB
scale; residual shows the aligned candidate-minus-reference envelope. Repeat
--view to
compose them; explicit --view-width, --lines-per-second and --max-lines make
geometry independent of terminal size.
metrics is a per-window diagnostic, not the verdict; branch on status and
failure_types. Waveforms report PCM-rail sample counts, not a clipping verdict.
Pitch-track uses non-overlapping 100 ms autocorrelation windows over 70..1200 Hz
with the >=0.30 voiced-confidence floor. It spans each row's voiced min/max,
leaves unvoiced rows blank, and reanchors windows at the selected range start.
It has no verdict effect; use pitch-delta for signed candidate/reference error,
and expect possible octave ambiguity on polyphonic or harmonic-heavy material.
rms-level places exact silence at the <=-96 dBFS display edge but prints -inf in
its footer; it has no good/bad colours or verdict gate.
Rail-ratio uses a fixed logarithmic 1 ppm..100% scale, places zero at the left,
and prints exact selected counts and percentages. Red means at least one exact
signed-16-bit rail sample, not a verdict. Deliberately rail-limited material can
be valid, while clipping below full scale is invisible; compose with waveform,
sample-density, flatline-ratio, and crest-factor before diagnosing clipping.
Peak-occupancy counts decoded samples whose absolute magnitude is at least 99%
of that displayed row's own peak. It uses a fixed 0..100% scale, leaves silence
and rows shorter than two samples blank, and can expose flat-topping below the
PCM rails even when dither defeats exact-repeat detection. It depends on row
geometry and has no verdict effect: sine peaks have nonzero occupancy, while
square, pulse, constant, and intentionally limited signals can sit at 100%.
The footer's whole-range occupancy is recomputed from the whole-range peak and
is not the median, maximum, or mean of row-local values.
Compare with waveform, crest-factor, flatline-ratio, and rail-ratio before
diagnosing clipping.
Quantization-step is the GCD of gaps between occupied non-rail decoded PCM
levels on a fixed log2 1..32768 PCM scale. It leaves rows with fewer than two
interior levels blank and prints exact row/selected steps. Dither or noise can
reduce the result to 1 PCM even for low-bit-depth source, while square waves and
stepped synthesis can be coarse intentionally; it has no verdict effect.
Spectral-change takes the maximum 1-cosine change per displayed row between
1024-sample Hann frames at a 512-sample hop. DC is removed and each magnitude
spectrum is normalized, so gain-only changes are intentionally suppressed; a
silent/non-silent transition is 1, two silent frames are blank, and short ranges
without a frame pair are blank. The fixed 0..1 scale has no good/bad threshold
or verdict effect; musical onsets can legitimately move right.
Spectral-centroid uses non-overlapping 100 ms DC-removed magnitude spectra on a
fixed log 55..11025 Hz scale, spans each row's minimum/maximum, leaves flat or
short rows blank, and reanchors windows at the selected range start. It has no
verdict effect: harmonic-rich, noisy, and intentionally bright material can sit
rightward. Use spectral-diff to identify the frequencies behind a shift.
Spectral-flatness uses non-overlapping 100 ms Hann power spectra over
55..8000 Hz. Wiener entropy is 0 for concentrated/tonal energy and approaches
1 for a flat/noisy spectrum; silence and short rows are blank. It reanchors
windows at the selected range start and has no verdict effect. Noise, percussion,
and intentionally unpitched synthesis can legitimately sit rightward; compare
with a reference and use spectral-diff to identify the affected frequencies.
Flatline-ratio counts exact decoded PCM equality and has no good/bad colours or
verdict gate. Low-bit-depth audio and square/pulse plateaus can sit rightward by
design; compare with the reference before diagnosing a frozen buffer.
Block-repeat uses a fixed -1..+1 Pearson scale, where +1 is the same waveform
shape and -1 is an inverted repeat. It depends on the explicit row geometry,
does not search other block lengths, leaves the first chronological and constant
rows blank, and has no good/bad colours or verdict gate. Intentional periodic
material can repeat; compare with the reference before diagnosing a replayed
buffer.
Crest-factor is blank for silence, clips only its presentation at 24 dB, and
prints exact row/selected summaries. It has no good/bad colours or verdict gate.
Derivative-ratio is blank for constant/silent rows, marks left as smoother and
right as rougher, and has no good/bad colours or verdict gate. Periodic waveform
edges can legitimately sit rightward; use spectral-diff to identify frequency.
Sample-density normalizes density within each row, marks exact rail occupancy
in red, and never changes analysis. DC-offset has a minimum +/-256 PCM scale;
red means |row mean| >=256 PCM and is a diagnostic highlight, not a verdict.
Wave-correlation is green at >=0.95, yellow at >=0.70, and red below; these are
presentation thresholds, not gates. Flat rows are blank, and independently
randomized noise can be uncorrelated by design even when perceptually correct.
Level-delta uses a minimum +/-3 dB dynamic scale, a 1 PCM silence floor, and
marks right as louder. It visualizes individual windows while the profile gates
their aggregate median.
Pitch-delta uses a minimum +/-1 semitone dynamic scale and marks right as sharp.
Timing-drift is relative to the trusted modal lag, marks right as later, and
flags weak-correlation or out-of-tolerance blocks; it is blank when lock is not
applicable.
Contour independently z-normalizes reference and candidate over the selected
range, draws their trajectories as R/C, and is blank for pitched material. The
printed correlations remain the full-track verdict inputs.
Band-delta uses B/M/H/U for 55-250/250-1000/1000-4000/4000-8000 Hz,
marks reference-selected quiet rows with q, and prints the whole/quiet aggregates
which can fail the profile. Local row glyphs are diagnostic, not verdicts.
Spectral-diff leaves changes below 3 dB blank and reaches full glyphs at +/-24
dB after applying the shared spectrogram floor. Click bars are full at >=64x
local derivative RMS. Residual-ratio is 20*log10(residual RMS/reference RMS)
after alignment on a fixed -60..+6 dB scale. Identity stops at the left floor;
reference-silent or short rows are blank. It is sample-domain and diagnostic,
not perceptual or a verdict: polarity, phase, and tiny timing errors can move it
rightward. Residual uses the selected range's maximum absolute PCM difference
as its horizontal scale. Each block starts with the full candidate and reference
labels.
Examples:
  audio_analysis.py wav compare ref.wav candidate.wav
  audio_analysis.py --output json wav compare ref.wav a.wav b.wav
  audio_analysis.py wav compare ref.wav a.wav --view waveform --view block-repeat --layout columns
  audio_analysis.py wav compare ref.wav a.wav --view spectral-diff --view phase-diff --view spectral-coherence --layout columns
  audio_analysis.py wav compare ref.wav a.wav --spectrogram-file build/diff.png""")
    add_output_options(compare_parser)
    compare_parser.add_argument("reference", metavar="REFERENCE", help="reference WAV path")
    compare_parser.add_argument("candidate", metavar="CANDIDATE", nargs="+",
                                help="one or more candidate WAV paths")
    compare_parser.add_argument("--labels", help="one comma-separated label per candidate")
    compare_parser.add_argument(
        "--profile", choices=comparison_profile_names(),
        default=DEFAULT_POLICY.profile_id,
        help=(f"versioned verdict policy (default: {DEFAULT_POLICY.profile_id}; "
              "see below for exact gates)"))
    compare_parser.add_argument("--verbose", action="store_true",
                                help="include per-window rows in human output")
    add_visualization_options(
        compare_parser,
        ("spectrogram", "low-frequency-spectrum", "modulation-spectrum",
         "pitch-track", "waveform", "intersample-peak",
         "rms-level", "rail-ratio",
         "peak-occupancy",
         "quantization-step", "flatline-ratio",
         "block-repeat",
         "crest-factor", "derivative-ratio", "spectral-change",
         "spectral-centroid", "spectral-flatness", "sample-density", "dc-offset",
         "stereo-balance", "stereo-level-diff", "stereo-correlation",
         "stereo-delay",
         "stereo-phase", "stereo-coherence",
         "wave-correlation", "metrics", "level-delta", "pitch-delta",
         "timing-drift", "contour", "spectral-diff", "phase-diff",
         "spectral-coherence", "band-delta", "clicks", "residual-ratio",
         "residual"))
    compare_parser.set_defaults(handler=run_wav_compare)

    sfx_parser = nouns.add_parser(
        "sfx", help="analyze a rendered PICO-8 sound effect",
        description="Cart-aware sound-effect analysis.")
    add_output_options(sfx_parser)
    sfx_verbs = sfx_parser.add_subparsers(
        dest="verb", required=True, parser_class=AgentArgumentParser)
    analyze_parser = sfx_verbs.add_parser(
        "analyze", help="compare rendered rows with cartridge note data",
        description="Analyze one rendered SFX and fail on row or click artifacts.",
        epilog="""INPUT may be '-' for stdin. This command is read-only and never
prompts. JSON returns every row and click-v1 analysis; quiet emits ok or failed.
The click-v1 thresholds and waveform-edge suppression are identical to wav
inspect, and any detected event fails the command. Example:
  audio_analysis.py --output json sfx analyze render.wav --cart game.p8.png --sfx 8""")
    add_output_options(analyze_parser)
    analyze_parser.add_argument("wav", metavar="INPUT", help="rendered WAV, or '-' for stdin")
    analyze_parser.add_argument("--cart", type=Path, required=True,
                                help="existing PICO-8 .p8.png cartridge")
    analyze_parser.add_argument("--sfx", type=int, required=True,
                                help="SFX index in 0..63")
    analyze_parser.add_argument(
        "--silent-below", type=float, default=40.0, metavar="RMS",
        help="RMS below this is silence (default: 40)")
    analyze_parser.add_argument(
        "--pitch-tolerance", type=float, default=0.5, metavar="SEMITONES",
        help="stable-note tolerance (default: 0.5 semitones)")
    analyze_parser.set_defaults(handler=run_sfx_analyze)
    return parser


def emit_cli_failure(failure, command, mode):
    if mode == "json":
        emit_json(failure.as_dict(command))
    print(f"audio_analysis: {failure.error}: {failure.message}", file=sys.stderr)
    if failure.suggestion:
        print(f"suggestion: {failure.suggestion}", file=sys.stderr)
    return failure.exit_code


def main(argv=None):
    original = list(sys.argv[1:] if argv is None else argv)
    mode = requested_output_mode(original)
    command = command_name(original)
    try:
        validate_output_mode_argv(original)
        args = make_parser().parse_args(original)
        return args.handler(args)
    except CliUsageError as error:
        failure = CliFailure(
            "invalid_arguments", str(error), exit_code=EXIT_USAGE,
            suggestion=f"run audio_analysis.py {command.replace('.', ' ')} --help")
        return emit_cli_failure(failure, command, mode)
    except CliFailure as failure:
        return emit_cli_failure(failure, command, mode)
    except OptionalDependencyError as error:
        failure = CliFailure(
            "dependency_missing", str(error),
            suggestion="install matplotlib or omit --spectrogram-file")
        return emit_cli_failure(failure, command, mode)
