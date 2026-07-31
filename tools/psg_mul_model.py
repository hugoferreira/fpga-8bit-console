#!/usr/bin/env python3
"""Cycle-exact model of rtl/psg_mulsvc.sv, and the gate for changing it.

The sample walk is scheduled tightly around the multiply service:
request-to-consume slack is zero at every call site
(tools/psg_viz.py measures this). A narrower mode makes a product ready
earlier, but the fixed control-store phases still elapse until a separate
retiming moves the dependent actions. The service has ONE accumulator
boundary, so a mode selects only how many iterations run - and an N-iteration
request therefore lands the exact product shifted LEFT by (12 - N). Every call
site has a fixed N, so its consumer compensates with a constant slice offset;
"the operand fits in 8 bits" is exactly the condition for mode 0 to be safe,
and the position is the caller's business.

This answers that question without touching the RTL:

  python3 tools/psg_mul_model.py                 # run the gate
  python3 tools/psg_mul_model.py --explain 171   # what each mode does to a value

The fixed iteration counts are read from psg_mulsvc.sv; the explicit short
request is modelled separately.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MULSVC_SV = os.path.join(ROOT, "rtl", "psg_mulsvc.sv")

A_BITS = 21                       # m_a, per the module's own width comment
# The service's stated ceiling on |A|: "the widest |A| any arm supplies is
# base_inc, whose pitch-table ceiling is 0x1CE0 << 8". It is what bounds every
# landing below 2^33, so a shifted product still fits the 34-bit register.
# Testing above the ceiling reports an overflow the design never reaches;
# ignoring the distinction hides one it might.
A_CEILING = 0x1CE0 << 8           # 1,892,352
B_BITS = 12                       # mul_start_b
P_BITS = 34                       # m_p


def mask(w):
    return (1 << w) - 1


def parse_iters(path=MULSVC_SV):
    """mode -> iteration count, from the m_cnt load in the RTL."""
    txt = open(path).read()
    # `m_cnt <=` appears three times: the reset, the decrement, and the load.
    # Only the load mentions mul_start_mode, so pick by content rather than by
    # position - taking the first match finds the reset and parses nothing.
    body = None
    for m in re.finditer(r"m_cnt\s*<=\s*(.*?);", txt, re.S):
        cand = re.sub(r"\s+", " ", m.group(1))
        if "mul_start_mode" in cand:
            body = cand
            break
    if body is None:
        raise SystemExit(f"{path}: could not find the m_cnt mode load")
    out = {}
    for cond, val in re.findall(r"mul_start_mode\s*==\s*2'd(\d+)\)\s*\?\s*4'd(\d+)",
                                body):
        out[int(cond)] = int(val)
    tail = re.findall(r":\s*4'd(\d+)\s*$", body)
    if tail:
        missing = [mode for mode in range(4) if mode not in out]
        if len(missing) != 1:
            raise SystemExit(
                f"{path}: expected one default mode in m_cnt load, got "
                f"{missing} from {body!r}")
        out[missing[0]] = int(tail[0])
    if not out:
        raise SystemExit(f"{path}: no iteration counts parsed from {body!r}")
    return dict(sorted(out.items()))


# The one accumulator boundary, shared by every request. It used to move with
# the iteration count so that every product landed at bit 0; that alignment was
# the same shift-add spelled four times in hardware. Fixing it here is what
# makes a product's POSITION a function of its iteration count.
BOUNDARY = 12


def parse_boundary(path=MULSVC_SV):
    """The accumulator boundary, READ from the RTL's m_acc slice."""
    txt = open(path).read()
    m = re.search(r"m_acc\s*=\s*m_p\[33:(\d+)\]", txt)
    if not m:
        raise SystemExit(f"{path}: m_acc is no longer one fixed slice of m_p")
    return int(m.group(1))


def service_shape(b, mode, short=False):
    """Return the live iteration count and accumulator boundary for a request."""
    return (6 if short else parse_iters()[mode]), parse_boundary()


def mulsvc(a, b, mode, iters=None, shift=None, short=False):
    """One complete service transaction. Returns m_res, the whole 34-bit m_p.

    Mirrors the always_ff exactly: strip the sign into m_a, load m_p with B,
    then for each iteration add m_a into the accumulator slice when m_p[0] is
    set and shift the whole register right by one. There is one result port
    because there is one register - the former m_res/m_res_wide/m_res12 were
    three widths of the same bits.
    """
    live_it, live_sh = service_shape(b, mode, short)
    it = iters if iters is not None else live_it
    sh = shift if shift is not None else live_sh
    m_a = abs(a) & mask(A_BITS)
    m_p = b & mask(B_BITS)
    for _ in range(it):
        acc = (m_p >> sh) & mask(22)
        s = (acc + (m_a if m_p & 1 else 0)) & mask(23)
        m_p = ((s << (sh - 1)) | ((m_p >> 1) & mask(sh - 1))) & mask(P_BITS)
    return m_p


def landing(mode, short=False):
    """How far left an N-iteration product lands: the consumer's slice offset."""
    it, sh = service_shape(0, mode, short)
    return sh - it


def sweep(bits=A_BITS, dense=4096, extra=20000):
    """|A| values: every small one, every boundary, then a spread."""
    top = (1 << bits) - 1
    vals = list(range(0, dense))
    vals += [top - k for k in range(64)]
    vals += [1 << k for k in range(bits)]
    vals += [(1 << k) - 1 for k in range(1, bits + 1)]
    step = max(1, top // max(1, extra))
    vals += list(range(0, top, step))
    return sorted(set(v & top for v in vals))


def equivalent(b, mode_a, mode_b, values=None):
    """Do two configurations carry the SAME VALUE, at their own landings?

    Position is no longer part of the answer: each mode lands its product
    (12 - iterations) places left, and each call site's consumer slices at its
    own constant offset. So the question a mode change has to survive is
    whether the bits agree once both are shifted back.
    """
    vals = values if values is not None else sweep()
    bad = []
    for a in vals:
        pa = mulsvc(a, b, mode_a) >> landing(mode_a)
        pb = mulsvc(a, b, mode_b) >> landing(mode_b)
        if pa != pb:
            bad.append(a)
            if len(bad) > 8:
                break
    return bad, len(vals)


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))
    return ok


def gate():
    iters = parse_iters()
    boundary = parse_boundary()
    print("psg_mulsvc iteration counts (read from RTL): "
          + ", ".join(f"mode {k}={v}" for k, v in iters.items())
          + "; explicit short=6")
    print(f"one accumulator boundary (read from RTL): m_p[33:{boundary}] — a "
          f"request of N iterations lands its product {boundary} - N places "
          "left")
    vals = sweep()
    ok = True

    # 1. THE LANDING LAW, which is what every consume slice in psg_walk and
    #    psg_seq is wired against: an N-iteration request returns exactly
    #    |A| * B * 2^(boundary - N). One boundary means position is a pure
    #    function of the iteration count, so each site's compensation is a
    #    constant - and getting it wrong is a shifted, not a corrupted, value.
    #    A mode consumes `iters` bits of B; anything wider has its top bits
    #    still sitting above the multiplier field at load time and is
    #    corrupted before the first iteration. That contract is unchanged.
    bad_land = []
    for mode, it in list(iters.items()) + [("short", 6)]:
        short = mode == "short"
        n = 6 if short else it
        md = 1 if short else mode
        for b in (0, 1, 3, 63, 171, 255, 341, 1023, (1 << n) - 1):
            if b.bit_length() > n:
                continue
            for a in vals:
                want = (abs(a) * b) << (boundary - n)
                if mulsvc(a, b, md, short=short) != want:
                    bad_land.append((mode, a, b))
                    break
            if bad_land:
                break
        if bad_land:
            break
    ok &= check("every request returns |A|*B << (12 - iterations)",
                not bad_land,
                f"{len(vals)} values of |A| per multiplier, all five "
                "iteration counts" if not bad_land else f"{bad_land[:3]}")

    # 1a. And it fits: the widest landing is the narrowest request, so the
    #     shift never pushes a product out of the 34-bit register.
    bad_fit = [(mode, it) for mode, it in list(iters.items()) + [("short", 6)]
               if (A_CEILING * ((1 << (6 if mode == "short" else it)) - 1)
                   << (boundary - (6 if mode == "short" else it))
                   ) >= (1 << P_BITS)]
    ok &= check("no landing overflows the 34-bit accumulator", not bad_fit,
                "|A| <= 0x1CE0<<8 and B < 2^N bound every shifted product "
                "by 2^33" if not bad_fit else f"{bad_fit}")

    # 1b. The converse: a B wider than the mode is corrupted. This is the
    #     trap the gate exists to catch, so assert it happens.
    ok &= check("a B wider than its mode is corrupted (the trap)",
                mulsvc(7, 341, 0) != (7 * 341) << landing(0),
                "341 cannot be evaluated by mode 0's byte ceiling")

    # 2. Mode 0 remains the original eight-cycle path for byte operands.
    bad, n = equivalent(255, 1, 0, values=vals)
    ok &= check("8-bit sequencer B at mode 0 == mode 1",
                not bad, f"{n} values of |A|, compared at their landings")

    # 2b. The reciprocal /3 limb program does not need a second product at
    # all. It currently evaluates x*341 and x*171, then forms
    # `(low25(x*341)<<9) + low25(x*171)`. Since
    #
    #     171*x = (341*x + x) / 2
    #
    # and the sum is always even, the second product can be reconstructed
    # exactly while the first product remains in m_p. Check the COMPLETE
    # 17-bit x domain used by gz_s1_r, including the point where x*341 grows
    # a 26th bit and the stored high partial truncates to 25.
    m25, m34 = mask(25), mask(34)
    bad_recip = []
    for x in range(1 << 17):
        p341 = 341 * x
        legacy = (((p341 & m25) << 9) + ((171 * x) & m25)) & m34
        derived171 = (p341 + x) >> 1
        rebuilt = (((p341 & m25) << 9) + derived171) & m34
        if legacy != rebuilt:
            bad_recip.append(x)
            break
    ok &= check("reciprocal limb: derive 171*x from 341*x + x",
                not bad_recip, "all 131072 values of the 17-bit limb"
                if not bad_recip else f"first divergence at x={bad_recip[0]}")

    # 3. The counter-claim, which must FAIL - 341 needs 9 bits.
    bad341, _ = equivalent(341, 1, 0, values=vals[:400])
    ok &= check("341 at mode 0 differs from mode 1 (mode 0 truncates)",
                bool(bad341), f"first divergence at |A|={bad341[0]}"
                if bad341 else "no divergence — 341 would fit mode 0?!")

    # 4. The spare wmul_mode encoding: a 9-iteration mode serves 341.
    bad9, n9 = equivalent(341, 1, 3, values=vals)
    ok &= check("341 at mode 3 (9 iterations) == mode 1", not bad9,
                f"{n9} values — exact nine-bit service mode")

    # 5. The walk's own consume offsets, spelled as the RTL spells them. These
    #    are the constants a future edit is most likely to get wrong, so name
    #    them rather than leaving them implicit in the landing law.
    sites = [("wavetable lerp  m_res[20:2]", 1, False, 2),
             ("G pass          m_res[26:10]", 2, False, 0),
             ("x*341 limb      m_res[28:3]", 3, False, 3),
             ("K_FX byte       m_res[27:4]", 0, False, 4),
             ("blend / T_NL    m_res[28:6]", 1, True, 6)]
    bad_sites = [name for name, md, sh, off in sites if landing(md, sh) != off]
    ok &= check("every named consume offset matches its launch",
                not bad_sites,
                "; ".join(n for n, _, _, _ in sites) if not bad_sites
                else f"{bad_sites}")

    # 6. Every constant the walk actually multiplies by, checked against the
    #    narrowest EXISTING mode that fits it.
    for b in (341,):
        need = b.bit_length()
        fits = [m for m, it in sorted(iters.items(), key=lambda kv: kv[1])
                if it >= need]
        if not fits:
            continue
        narrow = fits[0]
        bad_c, _ = equivalent(b, 2, narrow, values=vals)
        ok &= check(f"constant {b} ({need} bits) is safe at mode {narrow}",
                    not bad_c)
    return ok


def explain(value):
    iters = parse_iters()
    boundary = parse_boundary()
    print(f"{value} = 0b{value:b} — {value.bit_length()} significant bits\n")
    print(f"  {'mode':<6}{'iters':<7}{'lands<<':<9}{'100000 x B':<14}{'exact?'}")
    for mode in iters:
        it, sh = service_shape(value, mode)
        got = mulsvc(100000, value, mode) >> (sh - it)
        print(f"  {mode:<6}{it:<7}{sh - it:<9}{got:<14}"
              f"{'yes' if got == 100000 * value else 'NO — truncated'}")
    print(f"\nA mode is safe for B when its iteration count is at least B's "
          f"bit length:\n  the loop consumes one bit of B per iteration. The "
          f"product then lands\n  ({boundary} - iterations) places left, and "
          f"its consumer slices there.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--explain", type=int, metavar="B",
                    help="show what each mode does to this multiplier")
    args = ap.parse_args()
    if args.explain is not None:
        explain(args.explain)
        return
    print("psg_mulsvc equivalence gate\n")
    ok = gate()
    print("\n" + ("all checks passed" if ok else "FAILURES — see above"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
