#!/usr/bin/env python3
"""Area and timing summary from a vendor Gowin (gw_sh) build directory.

    python3 tools/gowin_vendor_report.py build/gowin_vendor/tangprimer20k

The counterpart of tools/gowin_stat.py (yosys area) and tools/gowin_timing.py
(nextpnr timing) for the vendor flow, which reports both in HTML rather than on
stdout. Prints the same shape of information so the two flows can be read side
by side - which matters, because they do not agree and the difference is the
point: on the Tang Primer 20K the vendor flow packs the design into 40 block
RAMs where yosys + nextpnr needs 46.

Everything here is scraped from Gowin's HTML reports, so it is deliberately
forgiving: a missing field prints nothing rather than failing a build.
"""
import html
import re
import sys
from pathlib import Path


def text_of(path):
    if not path.exists():
        return ""
    raw = path.read_text(errors="ignore")
    return re.sub(r"\|+", "|", html.unescape(re.sub(r"<[^>]*>", "|", raw)))


def find(body, label, width=60):
    """First `label | value` pair in the flattened report."""
    m = re.search(r"\|\s*" + re.escape(label) + r"\s*\|[^|]*\|\s*([^|]{1,%d})" % width,
                  body)
    return " ".join(m.group(1).split()) if m else None


def main(dirname):
    d = Path(dirname)
    rpt = text_of(next(iter(d.glob("impl/pnr/*.rpt.html")), Path("/nonexistent")))
    if not rpt:
        print("  (no vendor report found)")
        return 0

    print("  area, from Gowin's own place-and-route report:")
    for label in ("Logic", "Register", "BSRAM", "DSP", "rPLL", "I/O Port"):
        v = find(rpt, label)
        if not v:
            continue
        if label == "BSRAM":
            # Block RAM is reported as one cell per primitive type - "32 SP",
            # "5 SDPB", "3 pROM" - and the total is what matters against the
            # device's 46, so gather them and add them up.
            m = re.search(r"\|\s*BSRAM\s*\|((?:[^|]*\|){1,8})", rpt)
            parts = re.findall(r"(\d+)\s+([A-Za-z0-9]+)",
                               m.group(1) if m else v)
            if parts:
                total = sum(int(n) for n, _ in parts)
                v = f"{total} ({', '.join(n + ' ' + t for n, t in parts)})"
        print(f"    {label:<10} {v}")
    m = re.search(r"LUT,ALU,ROM16\|[^|]*\|\s*([^|]{1,60})", rpt)
    if m:
        print(f"    {'breakdown':<10} {' '.join(m.group(1).split())}")

    # ---- clock networks -------------------------------------------------
    # Every real clock must land on a global resource. This is checked rather
    # than assumed because the open-source flow does NOT manage it: under
    # nextpnr, psgclk stays on ordinary routing and picks up 0.53 ns of skew on
    # the Tang Nano and 1.06 ns on the Primer - the same shape of fault that
    # once cost cpuclk three hold violations, surviving on placement luck.
    # Gowin promotes all three to PRIMARY. If that ever stops, say so loudly.
    i = rpt.find("Global Clock Signals:")
    if i >= 0:
        table = rpt[i:i + 1200]
        seen = dict(re.findall(r"\|\s*([A-Za-z_][\w./]*)\s*\|\s*\|\s*"
                               r"(PRIMARY|GCLK|HCLK|LW)\s*\|", table))
        print("  clock networks:")
        for name in ("pllclk", "pllclk_div32", "psgclk"):
            res = seen.get(name)
            if res in ("PRIMARY", "GCLK", "HCLK"):
                print(f"    {name:<14} {res}")
            elif res:
                print(f"    {name:<14} {res}   *** NOT A GLOBAL CLOCK - "
                      f"expect skew and hold violations ***")
            else:
                print(f"    {name:<14} *** not on any global clock network ***")

    # Timing: the report pairs a constraint with the frequency achieved.
    tr = text_of(next(iter(d.glob("impl/pnr/*_tr_content.html")), Path("/nonexistent")))
    freqs = re.findall(r"\|\s*([0-9]+\.[0-9]+)\(MHz\)\s*\|", tr)
    if len(freqs) >= 2:
        print("  timing, constraint -> achieved:")
        for want, got in zip(freqs[0::2], freqs[1::2]):
            ok = "ok" if float(got) >= float(want) else "*** SHORT ***"
            print(f"    {float(want):10.3f} MHz -> {float(got):10.3f} MHz   {ok}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
