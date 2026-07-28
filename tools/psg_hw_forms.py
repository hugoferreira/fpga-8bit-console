#!/usr/bin/env python3
"""Prove hardware-friendly forms equal to the binary's audio arithmetic.

Each experiment either PROVES a candidate RTL decomposition byte-equal
to the reference form over its TRUE operand domain (exhaustively where
the domain permits, with the domain stated), or REFUTES it with the
first counterexample. The domains come from tools/psg_width_report.py's
analytic bounds; the reference forms are tools/psg_binary_model.py's,
which is byte-exact against the PICO-8 exports (51/51). A form proven
here can be transcribed to SystemVerilog with no further fidelity risk.

Sections:
  div   - constant divisors as shift + small magnitude reciprocal
  mix   - the soft-add compressor's //5 identity, and the minimal
          reciprocal for the reachable excess domain
  slide - the fine-path reciprocal: reachable domain, limb splits
          (6-pass and 3-pass), constant-precision floor
  svc   - the G*z product as two passes of the 24x10 m-service shape
  tzpow - the biased-arithmetic-shift idiom for every tz-by-2^k site
  blend - the crossfade as one multiply instead of two
  dq    - the seven per-wave dq constants as add/ceil forms
  amp   - G, the detune boost and vibrato as pure shift-adds
  bound - exact worst-case interval propagation through the whole
          pipeline (comb feedback to its fixpoint), and the int16 verdict
  csd   - constant multiplies as signed adder networks: the target
          fabric has NO DSP blocks, so every product is LUT4+carry
          adds (combinational CSD network or serial service cycles)
  rom   - packing notes for the small tables

Usage: psg_hw_forms.py [section ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import psg_binary_model as M

FAILURES: list[str] = []


def report(name: str, ok: bool, detail: str) -> None:
    tag = "PROVED " if ok else "REFUTED"
    print(f"  {tag} {name:34s} {detail}")
    if not ok:
        FAILURES.append(name)


def resign(neg: bool, mag: int) -> int:
    return -mag if neg else mag


# --- div: shift + magnitude reciprocal --------------------------------------

def find_reciprocal(d: int, n_max: int) -> tuple[int, int] | None:
    """Smallest (shift, mult) with (n*mult)>>shift == n//d on [0, n_max].

    With m = ceil(2^s/d) and e = m*d - 2^s, the form is exact on the
    whole range iff e*N' < 2^s where N' is the largest n <= n_max with
    n mod d == d-1 (the binding residue). Small domains are verified
    exhaustively on top of the criterion; large ones check the binding
    boundary neighbourhood and a stride."""
    for s in range(d.bit_length(), 48):
        m = -(-(1 << s) // d)                 # ceil(2^s / d)
        e = m * d - (1 << s)
        np_ = n_max - ((n_max - (d - 1)) % d)
        if e and e * np_ >= (1 << s):
            continue
        if n_max <= 2_000_000:
            ok = all((n * m) >> s == n // d for n in range(n_max + 1))
        else:
            pts = [n for base in (np_, n_max) for n in
                   range(max(0, base - 2 * d), base + 1)]
            pts += list(range(0, n_max, max(1, n_max // 100_000)))
            ok = all((n * m) >> s == n // d for n in pts)
        if ok:
            return s, m
    return None


def sec_div() -> None:
    print("div: every constant divisor as shifts + one small reciprocal")

    # scale /3072 = >>10 then /3, on the magnitude (tz semantics).
    # The shift-composition |x|//1024//3 == |x|//3072 is the floor
    # theorem; the band check below guards the resign implementation.
    p_max = 82_575_360                        # analytic |G*z| bound
    s3 = find_reciprocal(3, max(p_max >> 10, 131_072))
    report("div3.reciprocal", s3 is not None,
           f"n*{s3[1]}>>{s3[0]} == n//3 on [0, {max(p_max >> 10, 131_072):,d}]"
           if s3 else "no (shift, mult) found")
    band = list(range(-3_100_000, 3_100_001))
    band += [s * v for v in range(3072, p_max, 3072) for s in (1, -1)]
    ok = all(M.tz(x, 3072)
             == resign(x < 0, (abs(x) >> 10) * s3[1] >> s3[0])
             for x in band)
    report("div3072.decompose", ok,
           f"tz(x/3072) == resign((|x|>>10)*recip3) on {len(band):,d} "
           f"points incl. every multiple to +/-{p_max:,d}")

    # organ's tz(2(x-32768)/3) shares the same /3 unit: operand <= 32768.
    ok = all(M.tz(2 * (x - 32768), 3)
             == resign(x < 32768,
                       (abs(2 * (x - 32768)) * s3[1]) >> s3[0])
             for x in range(32768, 65536)) and (2 * 32768) <= (p_max >> 10)
    report("div3.organ_shares", ok,
           "organ magnitudes [0, 65536) fit the same unit, exhaustively")

    # tilt 57344 = 7*8192 and skew0: (24572*x)//57344 == ((24572*x)>>13)//7
    n7 = max((24572 * 57343) >> 13, 12_544)
    s7 = find_reciprocal(7, n7 + 1024)
    report("div7.reciprocal", s7 is not None,
           f"n*{s7[1]}>>{s7[0]} == n//7 on [0, {n7 + 1024:,d}]"
           if s7 else "no (shift, mult) found")
    ok = all((24572 * x) // 57344 == (((24572 * x) >> 13) * s7[1]) >> s7[0]
             for x in range(57344))
    report("div57344.decompose", ok,
           "(24572x)//57344 == recip7((24572x)>>13), x in [0, 57344) "
           "exhaustively")
    ok = all(M.tz(a * iv, 7) == ((a * iv) * s7[1]) >> s7[0]
             for a in range(0, 1793) for iv in range(8))
    report("div7.instrument_shares", ok,
           "tz(a*iv/7) on the full volume grid uses the same unit")

    # tilt 61440 = 15*4096
    n15 = (24572 * 61439) >> 12
    s15 = find_reciprocal(15, n15 + 1024)
    report("div15.reciprocal", s15 is not None,
           f"n*{s15[1]}>>{s15[0]} == n//15 on [0, {n15 + 1024:,d}]"
           if s15 else "no (shift, mult) found")
    ok = all((24572 * x) // 61440 == (((24572 * x) >> 12) * s15[1]) >> s15[0]
             for x in range(61440))
    report("div61440.decompose", ok,
           "(24572x)//61440 == recip15((24572x)>>12), x in [0, 61440) "
           "exhaustively")


# --- mix: the compressor is //5 ---------------------------------------------

def sec_mix() -> None:
    print("mix: the soft-add compressor")
    print(f"  note   5 * 52429 = {5 * 52429:,d} = 2^18 + 1 - the constant "
          "is ceil(2^18 / 5)")
    e_max = 131_072                           # >> any reachable excess (bound)
    ok = all(M.tz(e * 52429, 1 << 18) == e // 5 for e in range(e_max + 1))
    report("mix.excess_div5", ok,
           f"tz(e*52429/2^18) == e//5 on [0, {e_max:,d}] exhaustively - "
           "the 29-bit product is not real hardware")
    # the reachable excess: two comb-fixpoint voices into one soft_add
    reach = 2 * 53_759 - M.SOFT_TH
    s5 = find_reciprocal(5, reach)
    report("mix.min_reciprocal", s5 is not None,
           f"reachable excess <= {reach:,d}: minimal exact form is "
           f"n*{s5[1]}>>{s5[0]}" if s5 else "no (shift, mult) found")


# --- slide: the fine-path reciprocal ----------------------------------------

def sec_slide() -> None:
    print("slide: _get_dx_for_note_fine's 57-bit product")
    K = 0x2F8DF18F
    dom = sorted({(0x10000 - f) * M.NOTE_DX[c] + f * M.NOTE_DX[c + 1]
                  for c in range(12) for f in range(0x10000)})
    print(f"  note   reachable blended domain: {len(dom):,d} values in "
          f"[{dom[0]:,d}, {dom[-1]:,d}] ({dom[-1].bit_length()} bits); "
          f"table gaps max {max(M.NOTE_DX[i + 1] - M.NOTE_DX[i] for i in range(12))}")

    # limb split: blended = bh*2^14 + bl, K = k2*2^20 + k1*2^10 + k0;
    # six partials, none wider than 14x10, exact 56-bit accumulate.
    k2, k1, k0 = K >> 20, (K >> 10) & 1023, K & 1023
    ok = True
    for b in dom:
        bh, bl = b >> 14, b & 0x3FFF
        acc = ((bh * k2 << 34) + (bh * k1 << 24) + (bh * k0 << 14)
               + (bl * k2 << 20) + (bl * k1 << 10) + bl * k0)
        if acc != b * K:
            ok = False
            break
    report("slide.limb_split", ok,
           "6 partials <=14x10 into a 56-bit accumulator, whole domain")

    # constant-precision floor: how many low bits of K matter?
    kept = None
    for t in range(0, 24):
        kt = (K >> t) << t
        if all((b * kt) >> 44 == (b * K) >> 44 for b in dom):
            kept = t
        else:
            break
    report("slide.k_low_bits", kept is not None,
           f"K's low {kept} bits are free over the reachable domain "
           f"(truncating bit {kept + 1 if kept is not None else 0} breaks)"
           if kept is not None else "full precision required")

    # 3-pass split: blended's top 3 bits leave the 24-bit port; bh*K is
    # a shift-add correction (bh <= 4: at most two adds), the low 24
    # bits take three 24x10 service passes.
    ok = True
    for b in dom:
        bh, bl = b >> 24, b & 0xFFFFFF
        acc = (bh * K << 24) + ((bl * k2) << 20) + ((bl * k1) << 10) + bl * k0
        if acc != b * K:
            ok = False
            break
    report("slide.three_pass", ok,
           "bh*K (bh<=4, shift-adds) + three 24x10 passes on bl - halves "
           "the 6-limb schedule, whole domain")

    dps = sorted({(b * K) >> 44 for b in dom})
    print(f"  note   pre-octave dp spans [{dps[0]:,d}, {dps[-1]:,d}] "
          f"({dps[-1].bit_length()} bits before the octave shifts)")


# --- svc: the amplitude product on the m-service ----------------------------

def sec_svc() -> None:
    print("svc: G*z on the 24x10 product service")
    print("  note   G <= 3,360 (12-bit magnitude + sign): does NOT fit the "
          "10-bit port;")
    print("         z in [-24,576, 24,384] rides the 24-bit port instead")
    zs = list(range(-24576, 24385, 7)) + [-24576, -1, 0, 1, 24384]
    ok = True
    for g in list(range(0, 3361, 13)) + [3360]:
        gh, gl = g >> 7, g & 127
        for z in zs:
            if (z * gh << 7) + z * gl != g * z:
                ok = False
                break
        if not ok:
            break
    report("svc.two_pass_G", ok,
           "G = gh*128+gl: two passes (24x5 then 24x7) accumulate to the "
           "exact 28-bit product, grid + corners")


# --- tzpow: tz by a power of two as one biased arithmetic shift -------------

def sec_tzpow() -> None:
    print("tzpow: tz(x/2^k) == (x + (x<0 ? 2^k-1 : 0)) >> k  (arithmetic)")
    # k values used by the pipeline: /2 /4 /8 (wave secondaries, comb,
    # dampen), /64 (blend). Domains: band around zero plus every
    # boundary multiple across the widest accumulator range.
    for k, span in ((1, 120_000), (2, 3_500_000), (3, 160_000),
                    (6, 3_500_000)):
        pts = list(range(-600_001, 600_002))
        step = 1 << k
        pts += [v + d for v in range(-span, span + 1, step)
                for d in (-1, 0, 1)]
        ok = all(M.tz(x, step)
                 == (x + ((step - 1) if x < 0 else 0)) >> k
                 for x in pts)
        report(f"tzpow.k{k}", ok,
               f"{len(pts):,d} points incl. every multiple of {step} with "
               f"neighbours to +/-{span:,d}")


# --- blend: the crossfade with one multiply ---------------------------------

def sec_blend() -> None:
    print("blend: i*new + (64-i)*old == (old<<6) + i*(new-old)")
    vals = list(range(-53_759, 53_760, 997)) + [-53_759, -1, 0, 1, 53_339]
    ok = True
    for i in range(65):
        for old in vals:
            for new in (vals[0], vals[-1], old, -old,
                        vals[len(vals) // 2]):
                a = i * new + (64 - i) * old
                if a != (old << 6) + i * (new - old):
                    ok = False
                    break
    report("blend.one_multiply", ok,
           "identical accumulator, so identical tz(acc/64): the blend "
           "needs one 7x18 product (i * (new-old)), not two")


# --- dq: the per-wave secondary increments as add/ceil forms ----------------

def sec_dq() -> None:
    print("dq: tz(dp*K/256) for every K in the map, dp in [8, 32768]")
    forms = {
        256: ("dp", lambda dp: dp),
        255: ("dp - ceil(dp/256)", lambda dp: dp - ((dp + 255) >> 8)),
        254: ("dp - ceil(dp/128)", lambda dp: dp - ((dp + 127) >> 7)),
        250: ("dp - ceil(6dp/256)", lambda dp: dp - ((6 * dp + 255) >> 8)),
        193: ("(dp<<7 + dp<<6 + dp) >> 8", lambda dp: (193 * dp) >> 8),
        384: ("dp + (dp>>1)", lambda dp: dp + (dp >> 1)),
        508: ("2dp - ceil(dp/64)", lambda dp: 2 * dp - ((dp + 63) >> 6)),
    }
    for k, (label, fn) in forms.items():
        ok = all(M.tz(dp * k, 256) == fn(dp) for dp in range(8, 32769))
        report(f"dq.k{k}", ok, f"== {label}, exhaustively")
    print("  note   every dq is at most two adds and one shift - the "
          "109/110 serial chain has no successor")


# --- amp: amplitude ladder and vibrato as shift-adds ------------------------

def sec_amp() -> None:
    print("amp: the per-tick amplitude arithmetic")
    ok = all(M.tz(3 * a, 2) == a + (a >> 1) for a in range(2241))
    report("amp.G_shiftadd", ok,
           "G = tz(3a/2) == a + (a>>1) on the full ladder")
    ok = all(M.tz(5 * a, 4) == a + (a >> 2) for a in range(2241))
    report("amp.boost_shiftadd", ok,
           "tz(5a/4) == a + (a>>2) on the full ladder")
    ok = True
    for dx in range(8, 32769):
        for s in (-2, -1, 0, 1, 2):
            want = (dx * (128 + s)) >> 7
            got = (dx + ((dx * s) >> 7) if s >= 0
                   else dx - ((dx * -s + 127) >> 7))
            if want != got:
                ok = False
                break
        if not ok:
            break
    report("amp.vibrato", ok,
           "(dx*(128+s))>>7 == dx +/- small term, s in [-2,2], "
           "dx in [8, 32768] exhaustively")


# --- bound: exact worst-case interval propagation ---------------------------

def soft_iv(a: tuple[int, int], b: tuple[int, int]) -> tuple[int, int]:
    """soft_add is monotone in each operand, so endpoint sums bound it."""
    return (M.soft_add(a[0], b[0]), M.soft_add(a[1], b[1]))


def sec_bound() -> None:
    print("bound: exact worst-case widths through the pipeline")

    # monotonicity premise for interval soft_add, checked around the knees
    ok = all(M.soft_add(s + 1, 0) >= M.soft_add(s, 0)
             for s in range(-140_000, 140_000))
    report("bound.softadd_monotone", ok,
           "soft_add nondecreasing across both knees, [-140k, 140k]")

    g_max = 3360
    z_lo, z_hi = -24576, 24384
    v = (M.tz(g_max * z_lo, 3072), M.tz(g_max * z_hi, 3072))
    print(f"  note   voice pre-filter: [{v[0]:,d}, {v[1]:,d}] "
          f"({M.tz(g_max * z_lo, 3072).bit_length() + 1} bits)")

    # comb feedback fixpoint: ring holds post-comb(-and-dampen) output
    lo, hi = v
    for _ in range(64):
        nlo = M.tz(4 * v[0] + 2 * lo, 4)
        nhi = M.tz(4 * v[1] + 2 * hi, 4)
        if (nlo, nhi) == (lo, hi):
            break
        lo, hi = nlo, nhi
    print(f"  note   comb fixpoint: [{lo:,d}, {hi:,d}] - reverb DOUBLES "
          f"the voice bound; ring entries need {max(-lo, hi).bit_length() + 1}"
          " bits, comb acc "
          f"{max(4 * -v[0] + 2 * -lo, 4 * v[1] + 2 * hi).bit_length() + 1} "
          "bits")
    in16 = -32768 <= lo and hi <= 32767
    print(f"  note   ring entries {'fit' if in16 else 'EXCEED'} int16 "
          f"- a 16-bit ring RAM is {'safe' if in16 else 'NOT safe'} at "
          "worst case")
    voice = (lo, hi)                          # dampen and blend preserve it

    # Audibility rule: foreground on channel c REPLACES music slot 4+c,
    # so exactly one of leaves {c, 4+c} is live - at most 4 live leaves,
    # 16 placements. The 8-live figure is the unreachable over-bound.
    def tree(leaves: list[tuple[int, int]]) -> tuple[int, int]:
        l1 = [soft_iv(leaves[0], leaves[1]), soft_iv(leaves[2], leaves[3]),
              soft_iv(leaves[4], leaves[5]), soft_iv(leaves[6], leaves[7])]
        l2 = [soft_iv(l1[0], l1[1]), soft_iv(l1[2], l1[3])]
        return soft_iv(l2[0], l2[1])

    eight = tree([voice] * 8)
    print(f"  note   8 live leaves (unreachable over-bound): "
          f"[{eight[0]:,d}, {eight[1]:,d}] - would clip int16")
    worst = (0, 0)
    worst_mask = 0
    for mask in range(16):
        leaves = [(0, 0)] * 8
        for c in range(4):
            leaves[c if mask >> c & 1 else 4 + c] = voice
        t = tree(leaves)
        if t[0] < worst[0]:
            worst, worst_mask = t, mask
    print(f"  note   worst reachable placement (fg mask "
          f"{worst_mask:04b}): [{worst[0]:,d}, {worst[1]:,d}] - "
          f"{32768 + worst[0]:,d} units of int16 headroom")
    ok = -32768 <= worst[0] and worst[1] <= 32767
    report("bound.mix_never_clips", ok,
           "all 16 reachable audibility placements stay in int16 at "
           "worst case - the four-audible rule is the invariant that "
           "makes a 16-bit mix bus exact")

    d_acc = max(abs(voice[0]), voice[1]) * 4
    print(f"  note   dampen: |y| <= voice bound (one-pole cannot "
          f"overshoot); level-2 acc x+3y <= {d_acc:,d} "
          f"({d_acc.bit_length() + 1} bits)")
    b_acc = 64 * max(abs(voice[0]), voice[1])
    print(f"  note   blend acc 64*|v| <= {b_acc:,d} "
          f"({b_acc.bit_length() + 1} bits)")


# --- csd: constant-multiply adder costs on LUT4 fabric ----------------------

def naf(n: int) -> list[tuple[int, int]]:
    """Non-adjacent form: minimal signed-power-of-two decomposition."""
    out, k = [], 0
    while n:
        if n & 1:
            d = 2 - (n & 3)                   # +1 or -1
            out.append((d, k))
            n -= d
        n >>= 1
        k += 1
    return out


def sec_csd() -> None:
    print("csd: constant multiplies as signed adder networks (no DSP - "
          "LUT4+carry only)")
    print("  cost model: combinational = (terms-1) adds of ~result width; "
          "serial = one pass per multiplier bit on the shared adder")

    consts = [
        ("tilt/skew 24572", 24572, 16),
        ("recip3 174763", 174763, 17),
        ("recip7 149797", 149797, 18),
        ("recip15 279621", 279621, 19),
        ("compressor 52429", 52429, 17),
        ("slide K 0x2F8DF18F", 0x2F8DF18F, 27),
    ]
    for name, c, opw in consts:
        terms = naf(c)
        print(f"  note   {name:22s} {c.bit_length():2d} bits, "
              f"{bin(c).count('1'):2d} ones -> {len(terms):2d} CSD terms "
              f"= {len(terms) - 1:2d} adds (operand {opw} bits) | serial "
              f"{c.bit_length()} cycles")

    # the 3-term tilt/skew identity, exhaustively
    ok = all(24572 * x == (x << 14) + (x << 13) - (x << 2)
             for x in range(65536))
    report("csd.tilt_two_adds", ok,
           "24572x == (x<<14) + (x<<13) - (x<<2): the tilt/skew ramp "
           "multiply is TWO adds, exhaustively")

    # direct one-shot reciprocals as an alternative to the staged routes
    p_max = 82_575_360
    for name, d, n_max, staged in (
            ("3072", 3072, p_max, "(>>10 then recip3: 9 adds x 17b)"),
            ("57344", 57344, 24572 * 57343, "(>>13 then recip7)"),
            ("61440", 61440, 24572 * 61439, "(>>12 then recip15)")):
        r = find_reciprocal(d, n_max)
        if r is None:
            report(f"csd.direct{name}", False, "no direct reciprocal found")
            continue
        s, m = r
        t = naf(m)
        print(f"  note   direct /{name}: n*{m}>>{s} exact to "
              f"{n_max:,d}; {m.bit_length()} bits, {len(t)} CSD terms = "
              f"{len(t) - 1} adds on the full {n_max.bit_length()}-bit "
              f"operand {staged}")
    print("  note   staged routes shift first, so their adders are "
          "narrower; direct routes skip a stage but add on the full "
          "operand - synthesis spikes decide per the measurement law")

def sec_rom() -> None:
    print("rom: small-table packing")
    dx = M.NOTE_DX
    gaps = [dx[i + 1] - dx[i] for i in range(12)]
    print(f"  note   NOTE_DX: 13 entries x {max(dx).bit_length()} bits = "
          f"{13 * max(dx).bit_length()} bits; 13 constants-EBR words "
          "(13-bit) hold it directly")
    print(f"  note   delta form: {dx[0].bit_length()}-bit base + 12 gaps "
          f"<= {max(gaps)} ({max(g.bit_length() for g in gaps)} bits) = "
          f"{dx[0].bit_length() + 12 * max(g.bit_length() for g in gaps)} "
          "bits total")
    vib = [128, 129, 130, 129, 128, 127, 126, 127]
    print(f"  note   vibrato multipliers: 8 x (128 + s), s in "
          f"[{min(vib) - 128}, {max(vib) - 128}] - 3-bit signed offsets, "
          "24 bits total")


SECTIONS = {"div": sec_div, "mix": sec_mix, "slide": sec_slide,
            "svc": sec_svc, "tzpow": sec_tzpow, "blend": sec_blend,
            "dq": sec_dq, "amp": sec_amp, "bound": sec_bound,
            "csd": sec_csd, "rom": sec_rom}


def main() -> int:
    picked = sys.argv[1:] or list(SECTIONS)
    for name in picked:
        SECTIONS[name]()
        print()
    if FAILURES:
        print(f"REFUTED: {', '.join(FAILURES)}")
        return 1
    print("all candidate forms proved on their stated domains")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
