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
import functools
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MULSVC_SV = os.path.join(ROOT, "rtl", "psg_mulsvc.sv")

A_BITS = 18                       # m_a, per the module's own width comment
# The live request audit bounds every A to a signed 18-bit source. The most
# negative value therefore has magnitude 2^17; positive values stop one below.
# Older RTL supplied a shift-scaled pitch increment and needed 21 bits, but the
# current service receives the unshifted 13-bit table word and restores its
# fixed-point position only at the named consumer slices below.
A_CEILING = 1 << 17               # 131,072, inclusive magnitude ceiling
B_BITS = 12                       # mul_start_b
P_BITS = 34                       # m_p
ACC_BITS = A_BITS + 1             # product accumulator above bit 12
SUM_BITS = A_BITS + 3             # accumulator + radix-4 3*A term


def mask(w):
    return (1 << w) - 1


@functools.lru_cache(maxsize=None)
def parse_radix_bits(path=MULSVC_SV):
    """Multiplier bits retired per step, from the RTL's write-back shift.

    `m_p <= {m_sum, m_p[11:k]}` retires k bits per step: k=1 is radix-2, k=2
    radix-4. The engine went radix-4 because the landing law makes that free -
    see `landing`.
    """
    txt = open(path).read()
    m = re.search(
        r"m_p\s*<=\s*\{[^;\n]*m_sum,\s*m_p\[11:(\d+)\]\}", txt)
    if not m:
        raise SystemExit(f"{path}: cannot find the m_p write-back shift")
    return int(m.group(1))


@functools.lru_cache(maxsize=None)
def parse_preshift(path=MULSVC_SV):
    """Modes whose B is loaded pre-shifted, and by how much.

    Radix-4 retires an EVEN number of multiplier bits, so an odd radix-2
    iteration count has no exact radix-4 twin. Mode 3's nine steps become five,
    which would land the product one place low; loading `B << 1` puts it back.
    """
    txt = open(path).read()
    out = {}
    m = re.search(r"m_p\s*<=\s*\(mul_start_mode\s*==\s*2'd(\d+).*?"
                  r"\{\d+'b0,\s*mul_start_b,\s*(\d+)'b0\}", txt, re.S)
    if m:
        out[int(m.group(1))] = int(m.group(2))
    return out


@functools.lru_cache(maxsize=None)
def parse_iters(path=MULSVC_SV):
    """mode -> step count, from the m_cnt load in the RTL."""
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
    for cond, val in re.findall(
            r"mul_start_mode\s*==\s*2'd(\d+)\)\s*\?\s*\d+'d(\d+)", body):
        out[int(cond)] = int(val)
    tail = re.findall(r":\s*\d+'d(\d+)\s*$", body)
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


@functools.lru_cache(maxsize=None)
def parse_boundary(path=MULSVC_SV):
    """The accumulator boundary, READ from the RTL's m_acc slice."""
    txt = open(path).read()
    m = re.search(r"m_acc\s*=\s*m_p\[(\d+):(\d+)\]", txt)
    if not m:
        raise SystemExit(f"{path}: m_acc is no longer one fixed slice of m_p")
    return int(m.group(2))


SHORT_STEPS = {1: 6, 2: 3}      # radix -> steps for an explicit short request


def service_shape(b, mode, short=False):
    """Return the live step count and accumulator boundary for a request."""
    steps = SHORT_STEPS[parse_radix_bits()] if short else parse_iters()[mode]
    return steps, parse_boundary()


def landing(mode, short=False):
    """How far left this request lands its product: the consumer's offset.

    boundary - (bits retired) + (any pre-shift of B). The whole point of the
    radix-4 move is that this is UNCHANGED for every call site.
    """
    steps, boundary = service_shape(0, mode, short)
    pre = 0 if short else parse_preshift().get(mode, 0)
    return boundary - parse_radix_bits() * steps + pre


def mulsvc(a, b, mode, iters=None, shift=None, short=False, radix_bits=None,
           preshift=None):
    """One complete service transaction. Returns m_res, the whole 34-bit m_p.

    Mirrors the always_ff exactly: strip the sign into m_a, load m_p with B
    (pre-shifted for the one mode that needs it), then for each step add
    m_a * m_p[radix_bits-1:0] into the accumulator slice and shift the whole
    register right by radix_bits. There is one result port because there is
    one register.
    """
    live_it, live_sh = service_shape(b, mode, short)
    it = iters if iters is not None else live_it
    sh = shift if shift is not None else live_sh
    r = radix_bits if radix_bits is not None else parse_radix_bits()
    pre = preshift if preshift is not None else (
        0 if short else parse_preshift().get(mode, 0))
    m_a = abs(a) & mask(A_BITS)
    m_p = (b << pre) & mask(B_BITS)
    for _ in range(it):
        acc = (m_p >> sh) & mask(ACC_BITS)
        d = m_p & mask(r)
        srt = (acc + m_a * d) & mask(SUM_BITS)
        m_p = ((srt << (sh - r)) | ((m_p >> r) & mask(sh - r))) & mask(P_BITS)
    return m_p


def signed(v, width):
    """Interpret the low *width* bits as a two's-complement integer."""
    v &= mask(width)
    return v - (1 << width) if v & (1 << (width - 1)) else v


def mulsvc_recoded(a, b, mode, short=False, trace=False):
    """R.72 carried signed-digit candidate, including final correction.

    For t = radix-4 digit + carry, 0..2 remain 0/+A/+2A, while 3 is
    represented as -A with carry one and 4 as zero with carry one.  The
    registered combined word may therefore be negative while busy.  Once the
    last digit retires, adding carry*A at the accumulator boundary returns the
    exact nonnegative public m_res without another service cycle.

    The candidate narrows the live accumulator to signed 18 bits and the
    add/sub result to signed 20 bits.  *trace* returns their observed extrema
    so the gate proves those widths rather than trusting comments in RTL.
    """
    steps, boundary = service_shape(b, mode, short)
    pre = 0 if short else parse_preshift().get(mode, 0)
    m_a = abs(a) & mask(A_BITS)
    m_p = (b << pre) & mask(B_BITS)
    carry = 0
    acc_lo = acc_hi = sum_lo = sum_hi = 0
    for _ in range(steps):
        acc = signed(m_p >> boundary, 18)
        t = (m_p & 3) + carry
        digit = t - 4 if t >= 3 else t
        carry = int(t >= 3)
        total = acc + m_a * digit
        acc_lo, acc_hi = min(acc_lo, acc), max(acc_hi, acc)
        sum_lo, sum_hi = min(sum_lo, total), max(sum_hi, total)

        # RTL shape: {{4{sum[19]}}, sum[19:0], m_p[11:2]}.
        total20 = total & mask(20)
        total24 = total20 | ((mask(4) << 20) if total20 & (1 << 19) else 0)
        m_p = ((total24 << 10) | ((m_p >> 2) & mask(10))) & mask(P_BITS)

    result = (m_p + ((m_a << boundary) if carry else 0)) & mask(P_BITS)
    if trace:
        return result, (acc_lo, acc_hi), (sum_lo, sum_hi)
    return result


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
    rb = parse_radix_bits()
    print(f"psg_mulsvc is radix-{1 << rb} (read from RTL): "
          + ", ".join(f"mode {k}={v} steps" for k, v in iters.items())
          + f"; explicit short={SHORT_STEPS[rb]}")
    print(f"one accumulator boundary (read from RTL): bit {boundary} — an "
          f"M-step request lands its product {boundary} - {rb}*M places left"
          + (f", plus a pre-shift on mode(s) {sorted(parse_preshift())}"
             if parse_preshift() else ""))
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
    for mode, it in list(iters.items()) + [("short", None)]:
        short = mode == "short"
        n = SHORT_STEPS[rb] if short else it
        md = 1 if short else mode
        width = rb * n - (0 if short else parse_preshift().get(md, 0))
        off = landing(md, short)
        for b in (0, 1, 3, 63, 171, 255, 341, 1023, (1 << width) - 1):
            if b.bit_length() > width:
                continue
            for a in vals:
                want = (abs(a) * b) << off
                if mulsvc(a, b, md, short=short) != want:
                    bad_land.append((mode, a, b))
                    break
            if bad_land:
                break
        if bad_land:
            break
    ok &= check("every request returns |A|*B << its landing",
                not bad_land,
                f"{len(vals)} values of |A| per multiplier, all five step "
                "counts" if not bad_land else f"{bad_land[:3]}")

    # 1a. And it fits: the widest landing is the narrowest request, so the
    #     shift never pushes a product out of the 34-bit register.
    bad_fit = []
    for mode in list(iters) + ["short"]:
        sh = mode == "short"
        md = 1 if sh else mode
        n = SHORT_STEPS[rb] if sh else iters[mode]
        width = rb * n - (0 if sh else parse_preshift().get(md, 0))
        if (A_CEILING * ((1 << width) - 1) << landing(md, sh)) >= (1 << P_BITS):
            bad_fit.append((mode, n))
    ok &= check("no landing overflows the 34-bit result", not bad_fit,
                "|A| <= 2^17 and B < 2^N bound every shifted product"
                if not bad_fit else f"{bad_fit}")

    # 1b. The converse: a B wider than the mode is corrupted. This is the
    #     trap the gate exists to catch, so assert it happens.
    ok &= check("a B wider than its mode is corrupted (the trap)",
                mulsvc(7, 341, 0) != (7 * 341) << landing(0),
                "341 cannot be evaluated by mode 0's byte ceiling")

    # 1c. THE RADIX CLAIM. A radix-4 step retires TWO multiplier bits, so a
    #     request of M steps lands at boundary - 2M; M = N/2 therefore lands
    #     exactly where the radix-2 N-step request did, and no consumer slice
    #     moves. Mode 3's nine steps are odd and have no exact half - loading
    #     B << 1 for that one mode puts its landing back. Checked against the
    #     radix-2 reference on every mode, every corner B, the whole |A| sweep
    #     and both signs, so the engine's radix is an implementation choice the
    #     rest of the chip cannot observe.
    R2 = {0: 8, 1: 10, 2: 12, 3: 9}          # the shipped radix-2 counts
    R4 = {0: 4, 1: 5, 2: 6, 3: 5}            # their radix-4 twins
    PRE4 = {3: 1}                            # ...and the one that needs a nudge
    bad_radix = []
    for mode, n2 in R2.items():
        for b in (0, 1, 3, 63, 171, 255, 341, 511, 1023, 4095,
                  (1 << n2) - 1):
            if b.bit_length() > n2:
                continue
            for a in vals[::7]:
                for sgn in (1, -1):
                    ref = mulsvc(sgn * a, b, mode, iters=n2, radix_bits=1,
                                 preshift=0)
                    got = mulsvc(sgn * a, b, mode, iters=R4[mode], radix_bits=2,
                                 preshift=PRE4.get(mode, 0))
                    if ref != got:
                        bad_radix.append((mode, a, b, sgn))
                        break
                if bad_radix:
                    break
            if bad_radix:
                break
        if bad_radix:
            break
    ok &= check("radix-4 at N/2 steps lands exactly where radix-2 at N did",
                not bad_radix,
                f"4 modes x corner B x {len(vals[::7])} values of |A| x both signs"
                if not bad_radix else f"{bad_radix[:3]}")
    # And the same for the explicit short request: six radix-2 steps, three
    # radix-4 ones.
    bad_short = [a for a in vals[:2000]
                 if mulsvc(a, 63, 1, iters=6, radix_bits=1, preshift=0, short=True)
                 != mulsvc(a, 63, 1, iters=3, radix_bits=2, preshift=0, short=True)]
    ok &= check("short request: three radix-4 steps == six radix-2 steps",
                not bad_short, f"{len(vals[:2000])} values of |A|")

    # 1d. R.72: eliminate the explicit 3*A producer by carrying digit three
    # into the next radix-4 position.  Compare the COMPLETE public m_res word,
    # including each mode's fixed landing and the odd-width pre-shift.  Sweep
    # every legal B at the A-domain boundaries, then the broad A sweep at all
    # digit-pattern corners.  Sign is deliberately checked too: the service
    # strips it before either recurrence, so both signs must remain identical.
    recode_bad = []
    acc_lo = acc_hi = sum_lo = sum_hi = 0
    edge_a = (0, 1, 2, 3, 255, 256, 4095, A_CEILING - 1, A_CEILING)
    shapes = [(mode, False) for mode in iters] + [(1, True)]
    for mode, short in shapes:
        n = SHORT_STEPS[rb] if short else iters[mode]
        width = rb * n - (0 if short else parse_preshift().get(mode, 0))
        for b in range(1 << width):
            for a in edge_a:
                for sgn in (1, -1):
                    ref = mulsvc(sgn * a, b, mode, short=short)
                    got, ab, sb = mulsvc_recoded(
                        sgn * a, b, mode, short=short, trace=True)
                    acc_lo, acc_hi = min(acc_lo, ab[0]), max(acc_hi, ab[1])
                    sum_lo, sum_hi = min(sum_lo, sb[0]), max(sum_hi, sb[1])
                    if got != ref:
                        recode_bad.append((mode, short, a, b, sgn, ref, got))
                        break
                if recode_bad:
                    break
            if recode_bad:
                break
        if recode_bad:
            break

        corners = sorted(set((0, 1, 2, 3, (1 << width) - 1,
                              mask(width) // 3, (2 * mask(width)) // 3)))
        live_vals = [a for a in vals if a <= A_CEILING]
        for b in corners:
            for a in live_vals:
                ref = mulsvc(a, b, mode, short=short)
                got = mulsvc_recoded(a, b, mode, short=short)
                if got != ref:
                    recode_bad.append((mode, short, a, b, 1, ref, got))
                    break
            if recode_bad:
                break
        if recode_bad:
            break
    ok &= check("carried signed digits reproduce complete m_res",
                not recode_bad,
                ("every legal B at 9 A boundaries and both signs; all A "
                 "sweep values at digit-pattern corners")
                if not recode_bad else f"{recode_bad[:1]}")
    ok &= check("recoded accumulator fits signed 18 bits",
                -(1 << 17) <= acc_lo and acc_hi < (1 << 17),
                f"observed {acc_lo}..{acc_hi}")
    ok &= check("recoded add/sub result fits signed 20 bits",
                -(1 << 19) <= sum_lo and sum_hi < (1 << 19),
                f"observed {sum_lo}..{sum_hi}")

    # 1e. R.73: expose an unsigned radix-4 digit as its two binary partial
    #     products.  This is the exact arithmetic presented to synthesis;
    #     whether the mapper turns it into a cheaper compressor is measured
    #     separately by the registered-service harness.
    partial_bad = []
    for a in vals:
        for digit in range(4):
            got = (a if digit & 1 else 0) + ((a << 1) if digit & 2 else 0)
            if got != a * digit:
                partial_bad.append((a, digit, a * digit, got))
                break
        if partial_bad:
            break
    ok &= check("two gated partial products reproduce every radix-4 digit",
                not partial_bad,
                f"4 digits x {len(vals)} values of |A|"
                if not partial_bad else f"{partial_bad[:1]}")

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
