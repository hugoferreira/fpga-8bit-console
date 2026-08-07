#!/usr/bin/env python3
"""Check both Gowin SDC files against the clock frequencies the RTL defines.

    python3 tools/sdc_check.py          # part of `make gowin-check`

There are two SDC files because the flows need different dialects - see the
header of rtl/gowin_vendor.sdc - and each restates the same periods. Two copies
of a number that must agree with a third place (the RTL) is exactly the kind of
drift this project keeps getting caught by: the "PSG misses its clock by 2.3x"
claim survived two weeks because a board top and a constraint disagreed with
rtl/clocks.sv and nothing compared them.

So this does not merely check the two files against each other. It derives what
the frequencies should be FROM THE DESIGN and checks both files against that:

  pllclk  from rtl/pll_gowin.v   - FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1)
  cpuclk  from rtl/pll_gowin.v   - pllclk / DYN_SDIV_SEL
  psgclk  from the board tops    - pllclk / PSG_DIV

A clock a file does not constrain is reported, not failed: the vendor flow
deliberately omits cpuclk (GowinSynthesis does not name that net and derives it
itself), and lcd0.cs is deliberately unconstrained in both.
"""
import re
import sys
from pathlib import Path

PLL = Path("rtl/pll_gowin.v")
TOPS = [Path("rtl/top_tangnano20k.sv"), Path("rtl/top_tangprimer20k.sv")]
SDCS = [Path("rtl/gowin_boards.sdc"), Path("rtl/gowin_vendor.sdc")]
TOL_MHZ = 0.01          # periods are written to 3 decimals, so allow rounding


def param(text, name):
    m = re.search(r"\.%s\(\"?(-?\d+)\"?\)" % name, text)
    return int(m.group(1)) if m else None


def expected():
    """The frequencies the RTL actually defines, in MHz."""
    t = PLL.read_text()
    fin, idiv, fbdiv, sdiv = (param(t, n) for n in
                              ("FCLKIN", "IDIV_SEL", "FBDIV_SEL", "DYN_SDIV_SEL"))
    if None in (fin, idiv, fbdiv, sdiv):
        sys.exit(f"sdc-check: cannot read the rPLL settings from {PLL}")
    pll = fin * (fbdiv + 1) / (idiv + 1)

    divs = set()
    for top in TOPS:
        m = re.search(r"PSG_DIV\s*=\s*(\d+)", top.read_text())
        if m:
            divs.add(int(m.group(1)))
    if len(divs) != 1:
        sys.exit(f"sdc-check: board tops disagree on PSG_DIV: {sorted(divs)}")
    psg_div = divs.pop()

    return {"pllclk": pll, "cpuclk": pll / sdiv, "psgclk": pll / psg_div}


def constrained(path):
    """{name: MHz} from a file's create_clock lines."""
    out = {}
    for m in re.finditer(r"^\s*create_clock\s+-name\s+(\S+)\s+-period\s+([\d.]+)",
                         path.read_text(), re.M):
        out[m.group(1)] = 1000.0 / float(m.group(2))
    return out


def main():
    want = expected()
    print("  clock frequencies the RTL defines:")
    for k in sorted(want):
        print(f"    {k:<8} {want[k]:10.4f} MHz")

    bad = 0

    # THE CPU->PSG CROSSING. rtl/clocks.sv: "the PSG samples CPU-side register
    # writes directly, and a masterclk-domain signal is stable for at least
    # floor(32/PSGDIV) complete PSG clocks". The PSG's write capture is a level
    # edge-detect in the psgclk domain with NO synchroniser, so that window is
    # the entire safety argument - and DYN_SDIV_SEL is free to shrink it,
    # because it is chosen for the frame rate at the other end of the design.
    #
    # It was shrunk to 1 (DYN_SDIV_SEL=8) and the symptom was not a failed gate:
    # the console ran, the picture was correct at 60.6 fps, and the music
    # stopped. Nothing in the build noticed. Two complete PSG clocks is the
    # floor here because an edge-detect needs the level held across two sampling
    # edges; below that, writes are missed.
    hold = want["psgclk"] / want["cpuclk"]
    print(f"    cpuclk holds a signal for {hold:.2f} PSG clocks "
          f"({int(hold)} complete)")
    if int(hold) < 2:
        print(f"      *** the PSG samples the CPU bus with no synchroniser and "
              f"needs >= 2 complete psgclk per cpuclk; raise DYN_SDIV_SEL in "
              f"{PLL} or lower PSG_DIV")
        bad += 1

    for sdc in SDCS:
        if not sdc.exists():
            print(f"    {sdc}: MISSING"); bad += 1; continue
        got = constrained(sdc)
        notes = []
        for name, mhz in sorted(got.items()):
            if name not in want:
                notes.append(f"{name} is not a clock the RTL defines"); bad += 1
            elif abs(mhz - want[name]) > TOL_MHZ:
                notes.append(f"{name} constrained at {mhz:.4f}, "
                             f"RTL says {want[name]:.4f}"); bad += 1
        missing = sorted(set(want) - set(got))
        print(f"    {sdc.name:<22} {len(got)} clock(s)"
              + (f", not constrained: {', '.join(missing)}" if missing else ""))
        for n in notes:
            print(f"      *** {n}")

    if bad:
        print(f"  sdc-check: FAIL ({bad} disagreement(s))")
        return 1
    print("  sdc-check: both SDCs agree with the RTL")
    return 0


if __name__ == "__main__":
    sys.exit(main())
