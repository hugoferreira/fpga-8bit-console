#!/usr/bin/env python3
"""Read structured telemetry from the Tang Nano 20K onboard USB-UART."""

from __future__ import annotations

import argparse
import glob
import os
import re
import select
import struct
import sys
import termios
import time
import wave


LINE_RE = re.compile(
    rb"^S=([0-1][0-9A-F]) F=([0-9A-F]{2}) I=([0-1][0-9A-F]{3}) "
    rb"D=([0-9A-F]{2}) E=([0-3]) C=([0-9A-F]{8}) "
    rb"N=([0-1][0-9A-F]{3}) V=([0-1]) G=([0-9A-F]{16})$"
)
PCM_WORD_COUNT = 4096
PCM_INITIAL = 0x811C9DC5
PCM_TRACE_MAGIC = 0xA5
PCM_CHECKPOINT_MAGIC = 0xA6
PCM_CHECKPOINT_COUNTS = (64, 128, 256, 512, 1024, 2048, 4096)


def mix_pcm_signature(state: int, word: int) -> int:
    state = ((state << 5) | (state >> 27)) & 0xFFFFFFFF
    packed = (word & 0xFFFF) * 0x10001
    return state ^ packed ^ 0x9E3779B9


def wav_pcm_words(path: str, word_count: int) -> tuple[int, ...]:
    with wave.open(path, "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 22050):
            raise ValueError("expected mono signed-16 PCM WAV at 22050 Hz")
        raw = wav.readframes(wav.getnframes())
    words = struct.unpack(f"<{len(raw) // 2}h", raw)
    first = next((i for i, word in enumerate(words) if word != 0), None)
    if first is None or len(words) - first < word_count:
        raise ValueError(f"WAV has fewer than {word_count} words after first non-zero")
    return words[first:first + word_count]


def wav_pcm_signatures(path: str, checkpoints: tuple[int, ...]) -> dict[int, int]:
    required = max(checkpoints)
    signature = PCM_INITIAL
    signatures: dict[int, int] = {}
    for count, word in enumerate(wav_pcm_words(path, required), start=1):
        signature = mix_pcm_signature(signature, word)
        if count in checkpoints:
            signatures[count] = signature
    return signatures


def wav_pcm_signature(path: str) -> int:
    return wav_pcm_signatures(path, (PCM_WORD_COUNT,))[PCM_WORD_COUNT]


def parse_line(line: bytes) -> dict[str, int] | None:
    match = LINE_RE.fullmatch(line.strip())
    if not match:
        return None
    state, flags, index, data, failure, signature, count, done, debug = match.groups()
    return {
        "state": int(state, 16),
        "flags": int(flags, 16),
        "index": int(index, 16),
        "data": int(data, 16),
        "failure_stage": int(failure, 16),
        "pcm_signature": int(signature, 16),
        "pcm_count": int(count, 16),
        "pcm_done": int(done, 16),
        "psg_debug": int(debug, 16),
    }


def decode_psg_debug(value: int) -> dict[str, int | list[int]]:
    return {
        "music_playing": (value >> 7) & 1,
        "music_pattern": value & 0x3F,
        "play_bits": (value >> 8) & 0xFF,
        "sfx_ids": [(value >> (16 + channel * 6)) & 0x3F
                    for channel in range(4)],
        "rows": [(value >> (40 + channel * 6)) & 0x1F
                 for channel in range(4)],
    }


def decode_pcm_trace(value: int) -> dict[str, int | list[int]] | None:
    if (value >> 56) != PCM_TRACE_MAGIC:
        return None

    def signed16(word: int) -> int:
        return word - 0x10000 if word & 0x8000 else word

    return {
        "page": (value >> 48) & 0xFF,
        "words": [
            signed16((value >> 32) & 0xFFFF),
            signed16((value >> 16) & 0xFFFF),
            signed16(value & 0xFFFF),
        ],
    }


def decode_pcm_checkpoint(value: int) -> dict[str, int] | None:
    if value >> 56 != PCM_CHECKPOINT_MAGIC:
        return None
    return {
        "valid": (value >> 55) & 1,
        "page": (value >> 48) & 0x7F,
        "count": (value >> 32) & 0xFFFF,
        "signature": value & 0xFFFFFFFF,
    }


def configure(fd: int, baud: int) -> list[object]:
    speed_name = f"B{baud}"
    if not hasattr(termios, speed_name):
        raise ValueError(f"unsupported baud rate: {baud}")
    speed = getattr(termios, speed_name)
    original = termios.tcgetattr(fd)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = speed
    attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)
    return original


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ports", nargs="*", help="serial device(s); defaults to cu.usbserial-*")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--expect-wav", help="require the completed PCM signature to match this WAV")
    parser.add_argument("--expect-checkpoints", action="store_true",
                        help="require every live A6 checkpoint to match --expect-wav")
    parser.add_argument("--expect-trace-words", type=int, default=0, metavar="N",
                        help="require N live A5 trace words to match --expect-wav")
    parser.add_argument("--expect-trace-start", type=int, default=1, metavar="N",
                        help="one-based first word for --expect-trace-words (default: 1)")
    args = parser.parse_args()

    if args.expect_checkpoints and not args.expect_wav:
        parser.error("--expect-checkpoints requires --expect-wav")
    if args.expect_trace_words and not args.expect_wav:
        parser.error("--expect-trace-words requires --expect-wav")
    if args.expect_trace_words < 0:
        parser.error("--expect-trace-words must be non-negative")
    if args.expect_trace_start < 1:
        parser.error("--expect-trace-start must be at least 1")

    expected_signature = None
    expected_checkpoints = None
    expected_trace = None
    if args.expect_wav:
        try:
            expected_signature = wav_pcm_signature(args.expect_wav)
            expected_checkpoints = wav_pcm_signatures(
                args.expect_wav, PCM_CHECKPOINT_COUNTS)
            if args.expect_trace_words:
                last = args.expect_trace_start + args.expect_trace_words - 1
                words = wav_pcm_words(args.expect_wav, last)
                expected_trace = {
                    index: words[index]
                    for index in range(args.expect_trace_start - 1, last)
                }
        except (OSError, ValueError, wave.Error) as exc:
            parser.error(str(exc))

    ports = args.ports or sorted(glob.glob("/dev/cu.usbserial-*"))
    if not ports:
        parser.error("no USB serial ports found")

    opened: dict[int, tuple[str, list[object]]] = {}
    buffers: dict[int, bytearray] = {}
    for path in ports:
        try:
            fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
            opened[fd] = (path, configure(fd, args.baud))
            buffers[fd] = bytearray()
        except OSError as exc:
            print(f"{path}: {exc}", file=sys.stderr)

    if not opened:
        return 2

    valid = 0
    completed = 0
    mismatches = 0
    seen_debug: set[tuple[str, int]] = set()
    seen_checkpoints: dict[int, int] = {}
    checkpoint_mismatches = 0
    seen_trace_words: dict[int, int] = {}
    trace_mismatches: list[tuple[int, int, int]] = []
    deadline = time.monotonic() + args.seconds
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select(list(opened), [], [], 0.25)
            for fd in ready:
                chunk = os.read(fd, 4096)
                if not chunk:
                    continue
                buffers[fd].extend(chunk)
                while b"\n" in buffers[fd]:
                    raw, _, rest = buffers[fd].partition(b"\n")
                    buffers[fd] = bytearray(rest)
                    decoded = parse_line(raw)
                    if decoded is not None:
                        valid += 1
                        print(f"{opened[fd][0]}: {raw.rstrip().decode('ascii')}")
                        debug_key = (opened[fd][0], decoded["psg_debug"])
                        if debug_key not in seen_debug:
                            seen_debug.add(debug_key)
                            checkpoint = decode_pcm_checkpoint(decoded["psg_debug"])
                            trace = decode_pcm_trace(decoded["psg_debug"])
                            if checkpoint is not None:
                                if checkpoint["valid"]:
                                    count = checkpoint["count"]
                                    signature = checkpoint["signature"]
                                    seen_checkpoints[count] = signature
                                    comparison = ""
                                    if expected_checkpoints is not None:
                                        expected = expected_checkpoints.get(count)
                                        if expected != signature:
                                            checkpoint_mismatches += 1
                                            comparison = f" MISMATCH expected={expected:08X}" if expected is not None else " unexpected-count"
                                        else:
                                            comparison = " match"
                                    print(f"{opened[fd][0]}: PCM checkpoint "
                                          f"page={checkpoint['page']:02X} count={count} "
                                          f"signature={signature:08X}{comparison}")
                            elif trace is not None:
                                words = ",".join(str(value) for value in trace["words"])
                                print(f"{opened[fd][0]}: PCM trace "
                                      f"page={trace['page']:02X} words={words}")
                                if expected_trace is not None:
                                    for offset, word in enumerate(trace["words"]):
                                        index = trace["page"] * 3 + offset
                                        if index not in expected_trace:
                                            continue
                                        seen_trace_words[index] = word
                                        expected = expected_trace[index]
                                        if word != expected:
                                            trace_mismatches.append((index + 1, word, expected))
                                            print(f"{opened[fd][0]}: PCM trace mismatch "
                                                  f"word={index + 1} live={word} "
                                                  f"expected={expected}")
                            else:
                                debug = decode_psg_debug(decoded["psg_debug"])
                                sfx_text = ",".join(f"{value:02X}" for value in debug["sfx_ids"])
                                row_text = ",".join(f"{value:02X}" for value in debug["rows"])
                                print(f"{opened[fd][0]}: PSG music={debug['music_playing']} "
                                      f"pattern={debug['music_pattern']:02X} "
                                      f"play={debug['play_bits']:02X} "
                                      f"sfx={sfx_text} rows={row_text}")
                        if expected_signature is not None and decoded["pcm_done"]:
                            completed += 1
                            if (decoded["pcm_count"] != PCM_WORD_COUNT or
                                    decoded["pcm_signature"] != expected_signature):
                                mismatches += 1
    finally:
        for fd, (_, original) in opened.items():
            termios.tcsetattr(fd, termios.TCSANOW, original)
            os.close(fd)

    if valid == 0:
        print("no valid Tang telemetry received", file=sys.stderr)
        return 1
    failed = False
    if expected_signature is not None:
        if completed == 0:
            print("no completed PCM signature received", file=sys.stderr)
            failed = True
        elif mismatches:
            print(f"PCM signature mismatch: expected {expected_signature:08X}",
                  file=sys.stderr)
            failed = True
        else:
            print(f"PCM signature matched {expected_signature:08X} over {PCM_WORD_COUNT} words")
    if args.expect_checkpoints:
        missing = [count for count in PCM_CHECKPOINT_COUNTS
                   if count not in seen_checkpoints]
        if missing:
            print("missing PCM checkpoints: " + ",".join(map(str, missing)),
                  file=sys.stderr)
            failed = True
        if checkpoint_mismatches:
            print(f"PCM checkpoint mismatches: {checkpoint_mismatches}",
                  file=sys.stderr)
            failed = True
        elif not missing:
            print("all PCM checkpoints matched")
    if expected_trace is not None:
        missing = [index + 1 for index in sorted(expected_trace)
                   if index not in seen_trace_words]
        if missing:
            print("missing PCM trace words: " + ",".join(map(str, missing)),
                  file=sys.stderr)
            failed = True
        if trace_mismatches:
            first, live, expected = min(trace_mismatches)
            print(f"first PCM trace mismatch: word {first} live={live} expected={expected}",
                  file=sys.stderr)
            failed = True
        elif not missing:
            print(f"all {len(expected_trace)} PCM trace words matched")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
