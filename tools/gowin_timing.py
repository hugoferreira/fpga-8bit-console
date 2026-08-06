#!/usr/bin/env python3
"""Per-domain timing verdict, read from a nextpnr-himbaechel log.

    python3 tools/gowin_timing.py build/gowin_primer/pnr.log

Replaces the hand-written thresholds this report used to carry. The Makefile
used to grep `Max frequency for clock` and compare each number against literals
copied out of rtl/clocks.sv into an awk script - which meant the thresholds
could drift from the design silently, and, worse, that the numbers were being
compared against a target nextpnr had never been given.

**The numbers only mean something because rtl/gowin_boards.sdc is passed.**
Without an SDC, nextpnr places and routes against a default 12 MHz target and
then prints whatever critical path it happened to end up with; that is a lower
bound taken under no timing pressure, not a closure result. With the SDC,
nextpnr does timing-driven work at the real periods and prints its own verdict,
which is what this reads. So this script deliberately reports nextpnr's
PASS/FAIL rather than recomputing one: there is exactly one source of truth for
each target, and it is the SDC.

A clock whose target is nextpnr's 12 MHz default is one the SDC does not
constrain, and is labelled as such instead of being allowed to read as a pass.

Fmax is printed twice per clock - after placement and after routing. The last
is the routed one, which is the one that counts.

Targets are printed to two decimals because that is all nextpnr echoes back:
cpuclk's 284.444 ns period comes back as "3.52 MHz", not 3.515625. The SDC holds
the exact value; this report shows what the tool was actually working to.
"""
import re
import sys

# Info: Max frequency for clock  'pllclk': 40.02 MHz (FAIL at 112.50 MHz)
LINE = re.compile(
    r"Max frequency for clock\s+'([^']+)':\s+([0-9.]+)\s+MHz"
    r"(?:\s+\((PASS|FAIL) at ([0-9.]+)\s+MHz\))?"
)

# nextpnr's own default when a clock is not in the SDC. A target of exactly this
# means "unconstrained", not "met a requirement".
NEXTPNR_DEFAULT_MHZ = 12.00


def main(path):
    seen = {}
    with open(path, errors="ignore") as f:
        for line in f:
            m = LINE.search(line)
            if m:
                name, fmax, verdict, target = m.groups()
                seen[name] = (float(fmax), verdict,
                              float(target) if target else None)

    if not seen:
        print("  timing: no 'Max frequency' lines in the log")
        return 0

    print("  timing, against rtl/gowin_boards.sdc:")
    short = []
    for name, (fmax, verdict, target) in sorted(seen.items()):
        if target is None or abs(target - NEXTPNR_DEFAULT_MHZ) < 0.005:
            print(f"    {name:<9} {fmax:8.2f} MHz achieved   "
                  f"(unconstrained - nextpnr's 12 MHz default, not a target)")
        elif verdict == "FAIL":
            print(f"    {name:<9} {fmax:8.2f} MHz achieved, "
                  f"{target:8.2f} needed   *** SHORT ***")
            short.append(name)
        else:
            print(f"    {name:<9} {fmax:8.2f} MHz achieved, "
                  f"{target:8.2f} needed   ok")

    if short:
        print(f"  NOTE: {', '.join(short)} misses its constraint. The bitstream"
              " is still written")
        print("        (--timing-allow-fail); it is not a bitstream you should"
              " trust on hardware.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else "build/gowin/pnr.log"))
