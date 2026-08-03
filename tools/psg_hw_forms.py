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
  wtsign - fold wavetable product sign into the interpolation addition
  dq    - the seven per-wave dq constants as add/ceil forms
  amp   - G, the detune boost and vibrato as pure shift-adds
  aram  - page-local audio-upload address and range decode
  timing - parameter-derived fractional sample-accumulator width
  pitch - signed pitch-sum bounds and prefix saturation
  noise - signed-prefix saturation at the exact +/-6143 audio bounds
  seq   - exact prefix forms for sequencer register inputs
  bound - exact worst-case interval propagation through the whole
          pipeline (comb feedback to its fixpoint), and the int16 verdict
          for the mix bus (buffer SIZES live in tools/psg_buffers.py)
  csd   - constant multiplies as signed adder networks: the target
          fabric has NO DSP blocks, so every product is LUT4+carry
          adds (combinational CSD network or serial service cycles)
  rom   - packing notes for the small tables

Usage: psg_hw_forms.py [section ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

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

    # Outside the alternate-secondary bypass, the completed linear organ
    # sample carries the only later-needed top phase bit in bits 15^14.
    # The bypass excludes that predicate from the final selection entirely.
    organ_hi_ok = True
    for phase in range(1 << 16):
        org_lin = (phase - 8192 if not (phase & 0x4000)
                   else 24576 - phase)
        bits = org_lin & ((1 << 18) - 1)
        organ_hi_ok &= bool(phase & 0x8000) == bool(
            ((bits >> 15) ^ (bits >> 14)) & 1)
    report("div3.organ_high_from_linear", organ_hi_ok,
           "z_lin[15]^z_lin[14] equals phase[15] on all 65,536 organ phases")

    # tilt_hi, wsel and walt cross the same pipeline edge.  The later mode bit
    # is therefore already encoded by the registered selector/control pair;
    # keeping a third register for the predicate is redundant state.
    def capture_predicate(wsel: int, walt: bool) -> bool:
        return wsel == 1 and walt

    def capture_controls(wsel: int, walt: bool) -> tuple[int, bool]:
        return wsel, walt

    tilt_mode_ok = all(
        capture_predicate(wsel, walt)
        == (capture_controls(wsel, walt)[0] == 1
            and capture_controls(wsel, walt)[1])
        for wsel in range(8) for walt in (False, True))
    report("div.tilt_mode_from_controls", tilt_mode_ok,
           "same-edge registered controls reconstruct all 16 predicate states")

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

    ok = all((x >= (61440 if high else 57344))
             == (((x >> 13) == 7) and (not high or bool(x & 0x1000)))
             for high in (False, True) for x in range(1 << 16))
    report("div.tilt_tail_prefix", ok,
           "high-bit prefix == x >= 0xE000/0xF000, both modes exhaustively")


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

    # R.70: retire the corrected shift series and its original-excess
    # lifetime by splitting x = 256*h + l. Since 256 = 51*5 + 1,
    # floor(x/5) = 51*h + floor((h+l)/5). The latter quotient fits one
    # 512x7 table. A soft_add input is the sum of two signed int16 values, so
    # this also covers every later tree level: compression returns int16.
    pair_lo = -(1 << 16)
    pair_hi = (1 << 16) - 2
    excess_max = max(pair_hi - M.SOFT_TH, -M.SOFT_TH - pair_lo)
    excesses = range(excess_max + 1)

    def split5(x: int) -> tuple[int, int, int, int]:
        h, low = divmod(x, 256)
        addr = h + low
        return 51 * h + addr // 5, h, addr, addr // 5

    split = [split5(x) for x in excesses]
    quotient_max = max(q for q, _, _, _ in split)
    h_max = max(h for _, h, _, _ in split)
    addr_max = max(addr for _, _, addr, _ in split)
    table_q_max = max(q for _, _, _, q in split)
    bounds_ok = (len(split) == 40_961 and h_max == 160
                 and addr_max == 414 and table_q_max < (1 << 7)
                 and quotient_max == 8_192)
    report("mix.base256_bounds", bounds_ok,
           f"{len(split):,d} excesses: h <= {h_max}, h+l <= {addr_max}, "
           f"table q <= {table_q_max}, final q <= {quotient_max:,d}")

    quotient_ok = all(q == x // 5
                      for x, (q, _, _, _) in zip(excesses, split))
    report("mix.base256_div5", quotient_ok,
           "51*h + floor((h+l)/5) == floor(x/5) on every reachable excess")

    def shipped_soft_add(s: int) -> int:
        if s >= M.SOFT_TH:
            return M.SOFT_TH + ((s - M.SOFT_TH) * 52429 >> 18)
        if s <= -M.SOFT_TH:
            return -M.SOFT_TH - ((-M.SOFT_TH - s) * 52429 >> 18)
        return s

    def split_soft_add(s: int) -> int:
        if s >= M.SOFT_TH:
            return M.SOFT_TH + split5(s - M.SOFT_TH)[0]
        if s <= -M.SOFT_TH:
            return -M.SOFT_TH - split5(-M.SOFT_TH - s)[0]
        return s

    pair_sums = range(pair_lo, pair_hi + 1)
    soft_ok = all(split_soft_add(s) == shipped_soft_add(s)
                  for s in pair_sums)
    report("mix.base256_soft_add", soft_ok,
           f"exact over all {len(pair_sums):,d} signed-int16 pair sums")


# --- slide: the fine-path reciprocal ----------------------------------------

def sec_slide() -> None:
    print("slide: _get_dx_for_note_fine's 57-bit product")
    octave_ok = True
    for pitch in range(64):
        reference_oct, reference_chr = divmod(pitch, 12)
        ge12 = bool(pitch & 0x30 or (pitch & 0x0c) == 0x0c)
        ge24 = bool(pitch & 0x20 or (pitch & 0x18) == 0x18)
        ge36 = bool(pitch & 0x20 and pitch & 0x1c)
        ge48 = (pitch & 0x30) == 0x30
        ge60 = (pitch & 0x3c) == 0x3c
        octave = (5 if ge60 else 4 if ge48 else 3 if ge36 else
                  2 if ge24 else 1 if ge12 else 0)
        chromatic = pitch - 12 * octave
        octave_ok &= (octave, chromatic) == (reference_oct, reference_chr)
    report("slide.octave_prefix", octave_ok,
           "five shared prefix predicates preserve octave and chromatic for all 64 pitches")

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

    # The AFFINE-TABLE route, which beats every split above on a fabric
    # with no DSP and no LC to spare. blended*K is affine in the 16-bit
    # fraction, so per chromatic the whole 57-bit product collapses to
    #   dp_pre = base_c + ((r_c + frac*b_c) >> 29)
    # with base/r/b precomputed. That is ONE 16-bit multiply instead of
    # three or six service passes, and no 56-bit accumulator: the price
    # is 12 table entries, which the constants ROM already has free.
    tab = slide_affine_table()
    if tab is None:
        report("slide.affine_table", False,
               "no feasible (r, b) at scale 29")
        return
    print(f"  note   affine table: base <= "
          f"{max(t[0] for t in tab).bit_length()} bits, r <= "
          f"{max(t[1] for t in tab).bit_length()} bits, b <= "
          f"{max(t[2] for t in tab).bit_length()} bits, 12 entries")

    # Exhaustive against the model's own dx_clamped, over every pitch and
    # every fraction the slide can reach - including the octave shift and
    # the two-pass split of frac*b that the 12-bit B port forces.
    bad = None
    u_max = w_max = 0
    for p in range(64):
        octave, c = divmod(p, 12)
        base, r, b = tab[c]
        b_lo, b_hi = b & 0xFFF, b >> 12
        for frac in range(0x10000):
            u = r + frac * b_lo                    # 30 bits
            w = (u >> 12) + frac * b_hi            # 25 bits
            dp_pre = base + (w >> 17)
            dp = (dp_pre >> (3 - octave) if octave < 3
                  else dp_pre << (octave - 3))
            if dp != M.dx_clamped((p << 16) | frac):
                bad = (p, frac, dp, M.dx_clamped((p << 16) | frac))
                break
            u_max, w_max = max(u_max, u), max(w_max, w)
        if bad:
            break
    report("slide.affine_table", bad is None,
           "dp = base_c + ((r_c + frac*b_c) >> 29), octave shift folded: "
           "exhaustive over 64 pitches x 65,536 fractions"
           if bad is None else f"first counterexample {bad}")
    # The 12-bit B port splits frac*b as (frac*b[11:0]) + (frac*b[20:12]
    # << 12); the low 12 bits of that first sum cannot carry across the
    # >>29, which is what lets the second add be 25 bits and not 37.
    report("slide.affine_two_pass", bad is None,
           f"two 16x12 passes, {u_max.bit_length()}-bit then "
           f"{w_max.bit_length()}-bit accumulate - no wide product")


def slide_affine_table() -> list[tuple[int, int, int]] | None:
    """Per-chromatic (base, r, b) for dp_pre = base + ((r + frac*b) >> 29).

    Scale 29 is minimal: below it no integer (r, b) reproduces every
    floor boundary, because the slope needs ~16 significant bits to place
    all 184 of them. b is then chosen as the truncated or rounded slope,
    and r from the feasible interval the floor constraints leave.
    """
    K = 0x2F8DF18F
    out = []
    for c in range(12):
        a = (M.NOTE_DX[c] << 16) * K
        d = (M.NOTE_DX[c + 1] - M.NOTE_DX[c]) * K
        base = a >> 44
        steps = [((a + f * d) >> 44) - base for f in range(0x10000)]
        for b in (d >> 15, (d >> 15) + 1):
            lo = max((g << 29) - f * b for f, g in enumerate(steps))
            hi = min(((g + 1) << 29) - 1 - f * b for f, g in enumerate(steps))
            if lo <= hi and hi >= 0:
                out.append((base, max(lo, 0), b))
                break
        else:
            return None
    return out


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

    postshift_ok = True
    for bits in range(1 << 18):
        value = bits - (1 << 18) if bits & (1 << 17) else bits
        for k in range(4):
            mask = (1 << k) - 1
            biased = (value + (mask if value < 0 else 0)) >> k
            postshift = (value >> k) + int(value < 0 and bool(bits & mask))
            postshift_ok &= postshift == biased
    report("tzpow.postshift_remainder", postshift_ok,
           "arithmetic shift + negative nonzero-remainder correction, "
           "all 1,048,576 signed18/k combinations")

    wave_ok = True
    for bits in range(1 << 18):
        value = bits - (1 << 18) if bits & (1 << 17) else bits
        for tri_core in (False, True):
            for secondary in (False, True):
                current_k = ((3 if secondary else 2) if tri_core
                             else (1 if secondary else 0))
                selected_k = ((3 if secondary else 2) if tri_core
                              else int(secondary))
                wave_ok &= ((value + ((1 << current_k) - 1
                                      if value < 0 else 0)) >> current_k
                            == (value + ((1 << selected_k) - 1
                                         if value < 0 else 0)) >> selected_k)
    report("tzpow.wave_selected_shift", wave_ok,
           "one selected k preserves all 1,048,576 signed18/context tuples")


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


# --- wtsign: fold product sign into the interpolation addition --------------

def sec_wtsign() -> None:
    print("wtsign: +/-m == (m XOR sign-mask) + sign in a 20-bit word")
    mag = np.arange(1 << 19, dtype=np.int64)
    word_mask = (1 << 20) - 1
    ok = True
    for sign in (0, 1):
        current = np.where(sign, -mag, mag) & word_mask
        sign_mask = word_mask if sign else 0
        candidate = ((mag ^ sign_mask) + sign) & word_mask
        ok &= np.array_equal(current, candidate)
    report("wtsign.addsub_carry", ok,
           "all 1,048,576 19-bit magnitude/sign tuples; the following "
           "base add and arithmetic shift therefore remain identical")


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

    # The phaser's seven-bit remainder needs only a four-interval decode:
    # ceil(3r/128) is 0, 1, 2, 3 on r=0, 1..42, 43..85, 86..127.
    # Spell the two lower-six-bit thresholds as Boolean trees so the iCE40
    # mapper does not infer another carry chain for either comparison.
    def ceil3r_threshold(r: int) -> int:
        lo = r & 0x3f
        b = [(lo >> i) & 1 for i in range(6)]
        ge43 = b[5] and (b[4] or (b[3] and (b[2] or (b[1] and b[0]))))
        ge22 = b[5] or (b[4] and (b[3] or (b[2] and b[1])))
        high = (r >> 6) & 1
        y1 = high or ge43
        y0 = ((not high) and lo != 0 and not ge43) or (high and ge22)
        return (int(y1) << 1) | int(y0)

    ok = all(ceil3r_threshold(r) == (3 * r + 127) >> 7
             for r in range(128))
    report("dq.ceil3r_threshold", ok,
           "direct thresholds == ceil(3r/128), all 128 remainders")
    ok = all(3 * (dp >> 7) + ceil3r_threshold(dp & 127)
             == (6 * dp + 255) >> 8 for dp in range(1 << 13))
    report("dq.k250_split", ok,
           "3q + threshold(r) == ceil(6dp/256), all 8192 dp13 values")

    count_map = {0: 0, 1: 1, 2: 4, 3: 2, 4: 5, 5: 6}

    def count_step(state: int) -> int:
        return ((state & 3) << 1) | (((state >> 2) ^ state) & 1)

    sequence = [6]
    for _ in range(4):
        sequence.append(count_step(sequence[-1]))
    transitions_ok = sequence == [6, 5, 2, 4, 1]
    for count in range(2, 6):
        transitions_ok &= count_step(count_map[count]) == count_map[count - 1]
    report("dq.count_lfsr", transitions_ok,
           "6->5->2->4->1 preserves five binary-countdown iterations")
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
          f"the voice bound; the comb's VALUE needs "
          f"{max(-lo, hi).bit_length() + 1} bits, its accumulator "
          f"{max(4 * -v[0] + 2 * -lo, 4 * v[1] + 2 * hi).bit_length() + 1} "
          "bits in the transcribed 4x+2h form (18 as the proven 2x+h - "
          "psg_buffers entry.comb_acc_narrower)")
    in16 = -32768 <= lo and hi <= 32767
    print(f"  note   ring entries {'fit' if in16 else 'EXCEED'} int16 "
          f"- so the comb ACCUMULATOR needs 17 bits at worst case")
    print("  note   the STORAGE is still 16 bits: the binary's ring is "
          "8 x 366 bytes of int16 (tools/psg_buffers.py layout), so the "
          "overflow is the binary's too - a wider cell would be a "
          "different answer, not a safer one. psg_buffers entry/fit owns "
          "the storage question")
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
    print("  note   leaves here carry the unclamped comb value; with the "
          "binary's int16 ring cell they are narrower still, so the "
          "no-clip conclusion holds a fortiori")

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


# --- aram: page-local CPU upload decode ------------------------------------

def sec_aram() -> None:
    print("aram: page-local PICO-8 audio-upload decode")

    def candidate(addr: int) -> tuple[bool, int]:
        page = addr >> 8
        page_lo = page & 0x0f
        valid = ((page >> 4 == 3 and page_lo != 0)
                 or (page >> 4 == 4 and page_lo >> 2 == 0
                     and page_lo & 3 != 3))
        index = ((((addr >> 8) & 0x1f) - 17) & 0x1f) << 8
        return valid, index | (addr & 0xff)

    valid_ok = True
    index_ok = True
    valid_count = 0
    for addr in range(1 << 16):
        reference = (addr - 0x3100) & 0xffff
        reference_valid = reference < 4608
        valid, index = candidate(addr)
        valid_ok &= valid == reference_valid
        if valid:
            valid_count += 1
            index_ok &= index == reference

    report("aram.upload_window", valid_ok and valid_count == 4608,
           f"page prefixes select exactly {valid_count:,d} addresses in "
           "$3100..$42ff, all 65,536 addresses checked")
    report("aram.upload_index", index_ok,
           "{page-17, byte} == address-$3100 for every valid upload")


def sec_timing() -> None:
    print("timing: parameter-derived fractional sample-accumulator width")
    sample_hz = 22_050
    clocks = (3_506_580, 18_750_000, 22_500_000,
              28_125_000, 112_500_000)
    widths = []
    invariant_ok = True
    recurrence_ok = True
    shared_update_ok = True

    for clk_hz in clocks:
        width = (clk_hz - 1).bit_length() + 1
        widths.append(f"{clk_hz}:{width}")
        signed_lo = -(1 << (width - 1))
        signed_hi = (1 << (width - 1)) - 1
        down = clk_hz - sample_hz

        # divd is always in [-down, sample_hz-1]. Both recurrence arms map
        # that interval back into itself, so checking the four endpoints is
        # an exact interval proof rather than a sampled trajectory.
        invariant_ok &= signed_lo <= -down
        invariant_ok &= sample_hz - 1 <= signed_hi
        invariant_ok &= -down <= -down + sample_hz <= sample_hz - 1
        invariant_ok &= -down <= -1 + sample_hz <= sample_hz - 1
        invariant_ok &= -down <= 0 - down <= sample_hz - 1
        invariant_ok &= -down <= sample_hz - 1 - down <= sample_hz - 1

        divd = -down
        for _ in range(20_000):
            sample = divd >= 0
            reference = divd - down if sample else divd + sample_hz
            delta = -down if sample else sample_hz
            shared_update_ok &= reference == divd + delta
            divd = reference
            recurrence_ok &= -down <= divd < sample_hz
            recurrence_ok &= signed_lo <= divd <= signed_hi

    report("timing.divd_width", invariant_ok,
           "configured CLK_HZ:DIV_W = " + ", ".join(widths))
    report("timing.divd_recurrence", recurrence_ok,
           "exact invariant endpoints plus 20,000 clocks per configuration")
    report("timing.divd_shared_update", shared_update_ok,
           "sign-selected delta equals both original recurrence arms")


def sec_pitch() -> None:
    print("pitch: live signed-sum width and prefix saturation")

    clamp_ok = True
    for bits in range(1 << 9):
        value = bits - (1 << 9) if bits & (1 << 8) else bits
        reference = 0 if value < 0 else 63 if value > 63 else value
        candidate = 0 if bits & 0x100 else 63 if bits & 0x0c0 else bits & 0x3f
        clamp_ok &= candidate == reference
    report("pitch.clamp_prefix", clamp_ok,
           "sign/high-bit decode equals clamp(v, 0, 63) for all signed9 values")

    live_ok = True
    lo, hi = 0, 0
    for a in range(64):
        for b in range(64):
            value = a + b - 24
            lo = min(lo, value)
            hi = max(hi, value)
            bits = value & 0xff
            candidate = (0 if bits & 0x80 else
                         63 if bits & 0x40 else bits & 0x3f)
            reference = 0 if value < 0 else 63 if value > 63 else value
            live_ok &= candidate == reference
    report("pitch.live_sum_width", live_ok and (lo, hi) == (-24, 102),
           f"all 4,096 operand pairs stay in [{lo}, {hi}] and signed8 clamp exactly")

    # The current and arpeggiated sums feed schedule-exclusive consumers.  In
    # the arpeggio states, select arp as operand A and either the current or
    # instrument pitch as B; everywhere else select the ordinary current plus
    # instrument pair.  e_insfx is contained in ins_use by construction.
    cur, ins, arp = np.indices((64, 64, 64), dtype=np.int16)
    selected_ok = True
    selected_count = 0
    for ins_use in (False, True):
        for insfx_sel in (False, True):
            e_insfx = ins_use and insfx_sel
            old_pitch = (np.clip(cur + ins - 24, 0, 63)
                         if ins_use else cur)
            arp_raw = (cur + arp - 24 if e_insfx else
                       arp + ins - 24 if ins_use else arp)
            old_arp = np.clip(arp_raw, 0, 63)
            for use_arp in (False, True):
                old = old_arp if use_arp else old_pitch
                operand_a = arp if use_arp else cur
                operand_b = cur if use_arp and e_insfx else ins
                new = (np.clip(operand_a + operand_b - 24, 0, 63)
                       if ins_use else operand_a)
                selected_ok &= np.array_equal(old, new)
                selected_count += old.size
    report("pitch.selected_add_clamp", selected_ok,
           f"one selected cone preserves {selected_count:,} current/arpeggio tuples")

    schedule_ok = all(
        (state == 14 or (state in (15, 34, 35) and effect in (6, 7)))
        == (state == 14 or (state in (15, 34, 35)
                            and (effect & 0b110) == 0b110))
        for state in range(64) for effect in range(8))
    report("pitch.selected_schedule", schedule_ok,
           "K_PF0 and effect-6/7 K_FX/P_W0/P_W1 select arpeggio in all 512 states")


def sec_noise() -> None:
    print("noise: signed-prefix saturation at the exact +/-6143 bounds")

    clamp_ok = True
    for bits in range(1 << 18):
        value = bits - (1 << 18) if bits & (1 << 17) else bits
        reference = max(-6143, min(6143, value))
        positive = not (bits & 0x20000)
        over = positive and bool(bits & 0x1e000
                                 or (bits & 0x1800) == 0x1800)
        under = not positive and (
            (bits & 0x1e000) != 0x1e000
            or not (bits & 0x1000)
            and (not (bits & 0x0800) or not (bits & 0x07ff))
        )
        candidate = 6143 if over else -6143 if under else value
        clamp_ok &= candidate == reference
    report("noise.clamp_prefix", clamp_ok,
           "positive/negative prefixes equal clamp(v, -6143, 6143) for all signed18 values")

    # The kick condition's two adders and relational chain can be one bounded
    # signed subtraction.  Exercise the actual 16-bit wrap/sign interpretation,
    # not merely the unbounded algebraic identity.
    g = np.arange(1 << 13, dtype=np.int32)
    g3 = 3 * g
    kick_ok = True
    delta_lo = 1 << 30
    delta_hi = -(1 << 30)
    for dp in range(1 << 13):
        delta = dp + 497 - g3
        delta16 = ((delta + (1 << 15)) & 0xffff) - (1 << 15)
        kick_ok &= np.array_equal(delta16 >= 0, g3 <= dp + 497)
        delta_lo = min(delta_lo, int(delta.min()))
        delta_hi = max(delta_hi, int(delta.max()))
    report("noise.kick_signed_delta", kick_ok,
           f"signed16 sign equals 3*g <= dp+497 for all 67,108,864 pairs; "
           f"delta range [{delta_lo}, {delta_hi}]")

    # g[12] implies 3*g >= 12288 > max(dp+497)=8688.  Reject that half of
    # the domain directly; the remaining signed delta fits in 15 bits.
    g_lo = g & 0xfff
    g_lo3 = 3 * g_lo
    kick15_ok = True
    delta15_lo = 1 << 30
    delta15_hi = -(1 << 30)
    for dp in range(1 << 13):
        delta15 = dp + 497 - g_lo3
        signed15 = ((delta15 + (1 << 14)) & 0x7fff) - (1 << 14)
        candidate = (g < (1 << 12)) & (signed15 >= 0)
        kick15_ok &= np.array_equal(candidate, g3 <= dp + 497)
        delta15_lo = min(delta15_lo, int(delta15.min()))
        delta15_hi = max(delta15_hi, int(delta15.max()))
    report("noise.kick_highbit_delta15", kick15_ok,
           f"g[12] reject plus signed15 sign equals the predicate for all "
           f"67,108,864 pairs; low-half delta range "
           f"[{delta15_lo}, {delta15_hi}]")


def sec_seq() -> None:
    print("seq: exact prefix forms for sequencer register inputs")

    length_ok = True
    for value in range(1 << 8):
        reference = min(value, 32)
        over = bool((value & 0xc0) or ((value & 0x20) and (value & 0x1f)))
        candidate = 32 if over else value & 0x3f
        length_ok &= candidate == reference
    report("seq.trigger_length_prefix", length_ok,
           "high prefix equals saturate(byte, 32) for all 256 input values")

    # A pattern launch marks the four music channels that actually started.
    # The first marked non-looping channel owns the pattern-length product;
    # the first marked channel independently supplies the fallback speed.  In
    # the old protocol tch_seen inhibited later products while leaving all
    # launch marks set.  The replacement consumes the worklist at the winning
    # product.  Compare every launch/qualifier pattern over the ordered scan.
    launch_protocol_ok = True
    cases = 0
    for launch_mask in range(1 << 4):
        for qualifies_mask in range(1 << 4):
            old_seen = False
            old_ptick_seen = False
            old_fallback = None
            old_requests = []

            new_launch = launch_mask
            new_ptick_seen = False
            new_fallback = None
            new_requests = []

            for channel in range(4):
                old_marked = bool(launch_mask & (1 << channel))
                qualifies = bool(qualifies_mask & (1 << channel))
                old_request = old_marked and not old_seen and qualifies
                if old_marked and not old_ptick_seen:
                    old_ptick_seen = True
                    old_fallback = channel
                if old_request:
                    old_seen = True
                    old_requests.append(channel)

                new_marked = bool(new_launch & (1 << channel))
                new_request = new_marked and qualifies
                if new_marked and not new_ptick_seen:
                    new_ptick_seen = True
                    new_fallback = channel
                if new_request:
                    new_launch = 0
                    new_requests.append(channel)

            launch_protocol_ok &= old_requests == new_requests
            launch_protocol_ok &= old_fallback == new_fallback
            launch_protocol_ok &= old_ptick_seen == new_ptick_seen
            launch_protocol_ok &= bool(old_requests) == bool(new_requests)
            # If there was no owner, the launch marks remain available exactly
            # as before.  If there was one, only the now-dead marks differ.
            launch_protocol_ok &= (
                new_launch == launch_mask if not old_requests
                else new_launch == 0
            )
            cases += 1
    report("seq.launch_worklist_consume", launch_protocol_ok,
           f"request and fallback traces match for all {cases} launch/qualifier masks")


SECTIONS = {"div": sec_div, "mix": sec_mix, "slide": sec_slide,
            "svc": sec_svc, "tzpow": sec_tzpow, "blend": sec_blend,
            "wtsign": sec_wtsign,
            "dq": sec_dq, "amp": sec_amp, "aram": sec_aram,
            "timing": sec_timing, "pitch": sec_pitch, "noise": sec_noise,
            "seq": sec_seq, "bound": sec_bound,
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
