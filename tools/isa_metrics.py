#!/usr/bin/env python3
"""ISA ergonomic metrics, scored per corpus.

Implements the metric definitions from openspec add-isa-ergonomic-gates:

    toll        = 2 x (adjacent lda -> sta pairs)
    ceremony    = clc sec cld sed sei cli clv
    transfers   = tax txa tay tya tsx txs
    spills      = pha pla php plp
    plumbing    = (toll + ceremony + transfers + spills) / instructions

Counts are reported PER CORPUS and never pooled: the frequency thresholds are
absolute, so pooling would let a large corpus carry a threshold a small one
fails (see openspec add-celeste-corpus).

Each corpus is also tagged frame_bound or not. Plumbing measured under frame
pressure is partly hand-optimisation rather than instruction-set cost, so the
two classes are reported separately and never compared directly
(openspec add-nemo-corpus).

Usage: isa_metrics.py [--json]
"""
import json
import re
import sys
from collections import Counter

CORPORA = [
    {"name": "breakout", "frame_bound": True,
     "files": ["src/main.asm", "src/breakout_data.asm",
               "src/breakout_tables.asm", "src/breakout_sfx.asm"]},
    {"name": "nemo", "frame_bound": False,
     "files": ["src/nemo/main.asm", "src/nemo/grid.asm", "src/nemo/puzzle.asm",
               "src/nemo/clues.asm", "src/nemo/render.asm",
               "src/nemo/scene.asm", "src/nemo/obj.asm", "src/nemo/input.asm",
               "src/nemo/select.asm"]},
    # Only the hand-written files. gfx, rooms and audio are
    # generated data and contain no instructions, so listing them would say
    # nothing - but leaving them out is also the honest boundary of "what a
    # programmer wrote".
    {"name": "celeste", "frame_bound": True,
     "files": ["src/celeste/main.inlay.asm",
               "src/celeste/math.inlay.asm",
               "src/celeste/obj.inlay.asm",
               "src/celeste/collide.inlay.asm",
               "src/celeste/player.inlay.asm",
               "src/celeste/room.inlay.asm",
               "src/celeste/draw.inlay.asm",
               "src/celeste/sound.inlay.asm"]},
]

CEREMONY = {"clc", "sec", "cld", "sed", "sei", "cli", "clv"}
TRANSFERS = {"tax", "txa", "tay", "tya", "tsx", "txs"}
SPILLS = {"pha", "pla", "php", "plp"}
MNEMONICS = set("""adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld
cli clv cmp cpx cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora
pha php pla plp rol ror rti rts sbc sec sed sei sta stx sty tax tay tsx txa txs
tya""".split())

RE_INSN = re.compile(r"^\s*(?:@?\w+:\s*)?([a-zA-Z]{3})\b(.*)$")


def instructions(paths):
    """(mnemonic, operand) in source order, comments and directives stripped."""
    out = []
    for p in paths:
        try:
            src = open(p, encoding="latin-1").read()
        except FileNotFoundError:
            continue
        for line in src.split("\n"):
            line = line.split(";")[0]
            m = RE_INSN.match(line)
            if not m:
                continue
            mn = m.group(1).lower()
            if mn in MNEMONICS:
                out.append((mn, m.group(2).strip()))
    return out


def measure(corpus):
    insns = instructions(corpus["files"])
    n = len(insns)
    mn = [i[0] for i in insns]
    hist = Counter(mn)

    toll_pairs = sum(1 for i in range(len(mn) - 1)
                     if mn[i] == "lda" and mn[i + 1] == "sta")
    toll = 2 * toll_pairs
    ceremony = sum(hist[m] for m in CEREMONY)
    transfers = sum(hist[m] for m in TRANSFERS)
    spills = sum(hist[m] for m in SPILLS)
    plumbing = toll + ceremony + transfers + spills

    # idiom counts the weakly-evidenced slices need
    ops = [i[1] for i in insns]
    halfpair = sum(1 for o in ops if re.search(r"\+\s*1\b", o))
    indy = sum(1 for o in ops if re.search(r"\)\s*,\s*y", o, re.I))
    indirect_jmp = sum(1 for i, o in insns if i == "jmp" and o.startswith("("))
    clc_adc = sum(1 for i in range(len(mn) - 1)
                  if mn[i] == "clc" and mn[i + 1] == "adc")
    sec_sbc = sum(1 for i in range(len(mn) - 1)
                  if mn[i] == "sec" and mn[i + 1] == "sbc")
    lda_cmp_br = sum(1 for i in range(len(mn) - 2)
                     if mn[i] == "lda" and mn[i + 1] == "cmp"
                     and mn[i + 2].startswith("b"))
    lda_and_br = sum(1 for i in range(len(mn) - 2)
                     if mn[i] == "lda" and mn[i + 1] == "and"
                     and mn[i + 2].startswith("b"))

    return {
        "name": corpus["name"],
        "frame_bound": corpus["frame_bound"],
        "instructions": n,
        "toll_pairs": toll_pairs,
        "toll": toll,
        "ceremony": ceremony,
        "transfers": transfers,
        "spills": spills,
        "plumbing": plumbing,
        "plumbing_ratio": (plumbing / n) if n else 0.0,
        "idioms": {
            "lda_sta_adjacent": toll_pairs,
            "clc_adc": clc_adc,
            "sec_sbc": sec_sbc,
            "lda_cmp_branch": lda_cmp_br,
            "lda_and_branch": lda_and_br,
            "highhalf_operands": halfpair,
            "indirect_y": indy,
            "indirect_jmp": indirect_jmp,
        },
    }


def main():
    results = [measure(c) for c in CORPORA if instructions(c["files"])]
    if "--json" in sys.argv:
        print(json.dumps(results, indent=2))
        return 0

    print("ISA ergonomic metrics, per corpus (never pooled)\n")
    hdr = (f"{'corpus':<12}{'frame':>7}{'insns':>8}{'toll':>7}{'cerem':>7}"
           f"{'xfer':>6}{'spill':>7}{'plumb':>7}{'ratio':>8}")
    print(hdr)
    print("-" * len(hdr))
    for r in results:
        print(f"{r['name']:<12}{'yes' if r['frame_bound'] else 'no':>7}"
              f"{r['instructions']:>8}{r['toll']:>7}{r['ceremony']:>7}"
              f"{r['transfers']:>6}{r['spills']:>7}{r['plumbing']:>7}"
              f"{r['plumbing_ratio']:>7.1%}")

    print("\nidiom counts (threshold for a new instruction is 8 in ANY corpus)\n")
    keys = list(results[0]["idioms"])
    print(f"{'idiom':<22}" + "".join(f"{r['name']:>12}" for r in results))
    print("-" * (22 + 12 * len(results)))
    for k in keys:
        row = "".join(f"{r['idioms'][k]:>12}" for r in results)
        print(f"{k:<22}{row}")

    fb = [r for r in results if r["frame_bound"]]
    nfb = [r for r in results if not r["frame_bound"]]
    if fb and nfb:
        print("\nframe-pressure comparison (the point of a non-frame-bound "
              "corpus)\n")
        a = sum(r["plumbing"] for r in fb) / sum(r["instructions"] for r in fb)
        b = sum(r["plumbing"] for r in nfb) / sum(r["instructions"]
                                                 for r in nfb)
        print(f"  frame-bound      plumbing ratio: {a:.1%}"
              f"   ({', '.join(r['name'] for r in fb)})")
        print(f"  not frame-bound  plumbing ratio: {b:.1%}"
              f"   ({', '.join(r['name'] for r in nfb)})")
        d = b - a
        print(f"  difference: {d:+.1%}")
        print()
        if abs(d) < 0.05:
            print("  -> The ratio holds without frame pressure, so it is")
            print("     attributable to the instruction set rather than to")
            print("     hand-optimisation. The ISA programme is well aimed.")
        elif d < 0:
            print("  -> Plumbing is LOWER without frame pressure. Part of the")
            print("     frame-bound figure is hand-optimisation, so the")
            print("     slices' projected savings are overstated and their G5")
            print("     targets need re-deriving.")
        else:
            print("  -> Plumbing is HIGHER without frame pressure, so frame-")
            print("     bound code is not where the instruction set hurts")
            print("     most. Worth understanding before sizing the slices.")

        # Do not act on that verdict while celeste is registered: this metric
        # does not count the `ldy #FIELD` that precedes every (zp),Y struct
        # access - 6 such sites in breakout, 22 in nemo, 169 in celeste - so a
        # pointer-heavy corpus reports an artificially low ratio and drags the
        # frame-bound average down with it. See docs/corpora.md, section "The
        # pointer-setup blind spot", and docs/agent-coordination.md note 5.
        if any(r["name"] == "celeste" for r in results):
            print("\n  NOTE: the ratios above under-count pointer setup, which")
            print("  makes celeste look ~7 points cleaner than it is. Read")
            print("  docs/corpora.md 'The pointer-setup blind spot' before")
            print("  drawing a conclusion from the comparison.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
