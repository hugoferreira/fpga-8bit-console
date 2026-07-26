#!/usr/bin/env python3
"""Export a bounded music probe through PICO-8's MUSIC-mode WAV exporter.

This is intentionally macOS-specific: it launches one isolated PICO-8 process,
switches editor tabs with physical Option+Right key events (SDL does not see
AppleScript's synthetic modifier flags reliably), invokes EXPORT, waits for the
WAV, and terminates only that child.

Accessibility permission is required for the invoking terminal/Codex process.
The user's normal PICO-8 home and configuration are never touched.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_PICO8 = Path("/Applications/PICO-8.app/Contents/MacOS/pico8")

PHYSICAL_ALT_RIGHT = r"""
import CoreGraphics
import Darwin
func key(_ code: CGKeyCode, _ down: Bool) {
  CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    .post(tap: .cghidEventTap)
  usleep(100000)
}
for _ in 0..<COUNT {
  key(58, true)
  key(124, true)
  key(124, false)
  key(58, false)
  usleep(150000)
}
"""


def osascript(pid: int, *lines: str) -> None:
    script = [
        'tell application "System Events"',
        f"set p to first process whose unix id is {pid}",
        "set frontmost of p to true",
    ]
    script.extend(lines)
    script.append("end tell")
    command = ["osascript"]
    for line in script:
        command += ["-e", line]
    subprocess.run(command, check=True, capture_output=True, text=True)


def switch_tabs(count: int) -> None:
    subprocess.run(
        ["swift", "-e", PHYSICAL_ALT_RIGHT.replace("COUNT", str(count))],
        check=True, capture_output=True, text=True,
    )


def wait_for_exports(carts: Path, timeout: float) -> list[Path]:
    deadline = time.monotonic() + timeout
    previous: tuple[tuple[str, int], ...] = ()
    stable = 0
    while time.monotonic() < deadline:
        files = sorted(carts.glob("reference_*.wav"))
        state = tuple((path.name, path.stat().st_size) for path in files)
        if state and all(size > 44 for _, size in state) and state == previous:
            stable += 1
            if stable >= 3:
                return files
        else:
            stable = 0
        previous = state
        time.sleep(0.2)
    raise TimeoutError(f"PICO-8 did not finish a WAV export within {timeout}s")


def export(cart: Path, output: Path, pico8: Path, timeout: float) -> None:
    if sys.platform != "darwin":
        raise SystemExit("PICO-8 MUSIC export automation currently requires macOS")
    if not pico8.is_file():
        raise SystemExit(f"PICO-8 executable not found: {pico8}")
    cart = cart.resolve()
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="p8-music-export.") as raw:
        root = Path(raw)
        home = root / "home"
        carts = home / "carts"
        carts.mkdir(parents=True)
        local_cart = carts / ("probe" + cart.suffix)
        shutil.copy2(cart, local_cart)
        log = (root / "pico8.log").open("wb")
        process = subprocess.Popen(
            [str(pico8), "-home", str(home), local_cart.name],
            cwd=carts, stdout=log, stderr=subprocess.STDOUT,
        )
        try:
            time.sleep(1.5)
            osascript(process.pid)
            # PICO-8 remembers its last editor mode outside the isolated cart
            # home. Do not assume a starting tab. In SFX mode %d creates 64
            # files; in MUSIC mode it creates exactly one, numbered by the
            # current pattern. Cycle until the exporter itself proves the mode.
            wav = None
            for attempt in range(5):
                files = []
                for parity in range(2):
                    osascript(
                        process.pid,
                        'tell p to key code 53' if parity == 0 else "delay 0.1",
                        "delay 0.3",
                        'tell p to keystroke "export reference_%d.wav"',
                        'tell p to key code 36',
                    )
                    try:
                        files = wait_for_exports(carts, min(timeout, 5.0))
                        break
                    except TimeoutError:
                        # The first ESC can have moved from console to editor.
                        # A second ESC reaches the opposite parity.
                        osascript(process.pid, 'tell p to key code 53')
                if not files:
                    raise TimeoutError(
                        "PICO-8 produced no WAV from either console parity")
                if len(files) == 1:
                    wav = files[0]
                    break
                for path in files:
                    path.unlink()
                osascript(process.pid, 'tell p to key code 53')
                switch_tabs(1)
                time.sleep(0.3)
            if wav is None:
                raise RuntimeError(
                    "could not select MUSIC mode: every WAV export had the "
                    "64-file SFX signature")
            shutil.copy2(wav, output)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            log.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cart", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pico8", type=Path, default=DEFAULT_PICO8)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    export(args.cart, args.out, args.pico8, args.timeout)
    print(f"exported {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
