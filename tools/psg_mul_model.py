#!/usr/bin/env python3
"""Cycle-exact model of rtl/psg_mulsvc.sv, and the gate for changing it.

The sample walk is scheduled tightly around the multiply service:
request-to-consume slack is zero at every call site
(tools/psg_viz.py measures this). A narrower mode makes a product ready
earlier, but the fixed control-store phases still elapse until a separate
retiming moves the dependent actions. The mode also selects the accumulator
SLICE as well as the iteration count, so "the operand fits in 8 bits" does not
by itself mean mode 0 returns the same number.

This answers that question without touching the RTL:

  python3 tools/psg_mul_model.py                 # run the gate
  python3 tools/psg_mul_model.py --explain 171   # what each mode does to a value

The iteration counts are read from psg_mulsvc.sv rather than written here, so
a retuned service fails the gate instead of silently invalidating it.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MULSVC_SV = os.path.join(ROOT, "rtl", "psg_mulsvc.sv")

A_BITS = 21                       # m_a, per the module's own width comment
# The service's stated ceiling on |A|: "the widest |A| any arm supplies is
# base_inc, whose pitch-table ceiling is 0x1CE0 << 8". Beyond it a 12-bit B
# can push the product past 33 bits, which m_res (32) cannot hold - m_res_wide
# (34) can. Testing above the ceiling reports an overflow the design never
# reaches; ignoring the distinction hides one it might.
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


# The accumulator slice and the re-pack shift, both keyed by mode. These are
# the halves people forget: changing the mode moves BOTH, which is why a
# narrower mode is not obviously equivalent even for an operand that fits.
SHIFT = {0: 8, 1: 10, 2: 12, 3: 9}


def mulsvc(a, b, mode, iters=None, shift=None):
    """One complete service transaction. Returns (m_res, m_res_wide, m_res12).

    Mirrors the always_ff exactly: strip the sign into m_a, load m_p with B,
    then for each iteration add m_a into the accumulator slice when m_p[0] is
    set and shift the whole register right by one.
    """
    it = iters if iters is not None else parse_iters()[mode]
    sh = shift if shift is not None else SHIFT[mode]
    m_a = abs(a) & mask(A_BITS)
    m_p = b & mask(B_BITS)
    for _ in range(it):
        acc = (m_p >> sh) & mask(22)
        s = (acc + (m_a if m_p & 1 else 0)) & mask(23)
        m_p = ((s << (sh - 1)) | ((m_p >> 1) & mask(sh - 1))) & mask(P_BITS)
    return m_p & mask(32), m_p & mask(P_BITS), m_p & mask(28)


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


def equivalent(b, mode_a, mode_b, iters_b=None, shift_b=None, values=None):
    """Do two configurations agree on ALL THREE result ports, everywhere?

    All three, because the consume steps read different slices - CAP_W17 takes
    m_res12[26:10] while CAP_W63 takes m_res_wide[24:0]. Checking only m_res
    would pass a change that corrupts a consumer.
    """
    vals = values if values is not None else sweep()
    bad = []
    for a in vals:
        if mulsvc(a, b, mode_a) != mulsvc(a, b, mode_b, iters_b, shift_b):
            bad.append(a)
            if len(bad) > 8:
                break
    return bad, len(vals)


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))
    return ok


def gate():
    iters = parse_iters()
    print(f"psg_mulsvc iteration counts (read from RTL): "
          + ", ".join(f"mode {k}={v}" for k, v in iters.items()))
    for mode, it in iters.items():
        if SHIFT.get(mode) != it:
            print(f"  note: mode {mode} loads {it} iterations but this model "
                  f"shifts by {SHIFT.get(mode)} — the two must match")
    vals = sweep()
    ok = True

    # 1. The model IS a multiplier - but only for operands that FIT the mode.
    #    A mode consumes `iters` bits of B; anything wider has its top bits
    #    sitting in the accumulator slice at load time and is corrupted before
    #    the first iteration. That is the property the rest of this gate is
    #    about, so the exactness check must respect it rather than trip on it.
    bad_exact, bad_wide = [], []
    for mode, it in iters.items():
        for b in (0, 1, 3, 171, 255, 341, 1023, (1 << it) - 1):
            if b.bit_length() > it:
                continue
            for a in (0, 1, 777, 12345, 100000, (1 << 17) - 1,
                      A_CEILING, (1 << A_BITS) - 1):
                want = abs(a) * b
                res, wide, _ = mulsvc(a, b, mode)
                if wide != want:
                    bad_wide.append((mode, a, b))
                # m_res is 32 bits. The widest |A| times the widest B needs 33
                # and would fail here - but the RTL notes products "peak at 22
                # bits real, 33 structural": no arm pairs a 21-bit A with a
                # 12-bit B. Asserting that corner would be asserting something
                # the design never asks for, so the claim is scoped to
                # products that fit the port.
                if want < (1 << 32) and res != want:
                    bad_exact.append((mode, a, b))
    ok &= check("m_res is exact for every product that fits its 32 bits",
                not bad_exact,
                "wider products are the structural corner, carried by "
                "m_res_wide" if not bad_exact else f"{bad_exact[:3]}")
    ok &= check("m_res_wide is exact across the full 21-bit |A| range",
                not bad_wide,
                "the 34-bit port holds products m_res would truncate"
                if not bad_wide else f"{bad_wide[:3]}")

    # 1b. And the converse: a B wider than the mode is corrupted. This is the
    #     trap the gate exists to catch, so assert it happens.
    ok &= check("a B wider than its mode is corrupted (the trap)",
                mulsvc(7, 341, 0)[0] != 7 * 341,
                "341 at mode 0 gives 596, not 2387")

    # 2. The measured claim: 171 fits 8 bits, so mode 0 is enough.
    bad, n = equivalent(171, 1, 0, values=vals)
    ok &= check("171 at mode 0 == mode 1 (2 iterations recoverable)",
                not bad, f"{n} values of |A|, all three ports")

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

    # 4. The spare wmul_mode encoding: a 9-iteration mode would serve 341.
    bad9, n9 = equivalent(341, 1, 3, values=vals)
    ok &= check("341 at mode 3 (9 iterations) == mode 1", not bad9,
                f"{n9} values — exact nine-bit service mode")

    # 5. And a 6-iteration mode would serve bl_cnt[5:0].
    bad6, _ = equivalent(63, 0, None, iters_b=6, shift_b=6, values=vals)
    ok &= check("6-bit B at a 6-iteration mode == mode 0", not bad6)

    # 6. Every constant the walk actually multiplies by, checked against the
    #    narrowest EXISTING mode that fits it.
    for b in (171, 341):
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
    print(f"{value} = 0b{value:b} — {value.bit_length()} significant bits\n")
    print(f"  {'mode':<6}{'iters':<7}{'shift':<7}{'100000 x B':<14}{'exact?'}")
    for mode, it in iters.items():
        got = mulsvc(100000, value, mode)[0]
        print(f"  {mode:<6}{it:<7}{SHIFT[mode]:<7}{got:<14}"
              f"{'yes' if got == 100000 * value else 'NO — truncated'}")
    print("\nA mode is safe for B when its iteration count is at least B's bit "
          "length:\n  the loop consumes one bit of B per iteration, and the "
          "shift keeps the product in place.")


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
