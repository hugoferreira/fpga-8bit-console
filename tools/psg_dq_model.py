#!/usr/bin/env python3
"""Exhaustively prove secondary-increment implementation forms.

The RTL receives a 13-bit phase increment ``dp`` and derives the increment for
the secondary oscillator from the wave and detune mode.  R.51 proved a
serialized publication form; R.53 keeps the work combinational but evaluates
it at its natural widths. R.76 evaluates the selected coefficient with one
five-step radix-4 service during the visit's load-to-W0 window. Check every
input and the cycle recurrence before changing RTL.
"""

import numpy as np


DP = np.arange(1 << 13, dtype=np.int64)


def ceil_div(x: np.ndarray, divisor: int) -> np.ndarray:
    return (x + divisor - 1) // divisor


def rtl_reference(wave: int, mode: int, wavetable: bool) -> np.ndarray:
    if wavetable:
        return DP
    if wave == 0:
        if mode == 1:
            return ((DP << 7) + (DP << 6) + DP) >> 8
        if mode == 2:
            return DP + (DP >> 1)
        return DP
    if wave == 7:
        if mode == 1:
            return DP - (((DP << 2) + (DP << 1) + 255) >> 8)
        if mode == 2:
            return (DP << 1) - ((DP + 63) >> 6)
        return DP - ((DP + 127) >> 7)
    if mode != 0:
        return DP - ((DP + 255) >> 8)
    return DP


def serialized_form(wave: int, mode: int, wavetable: bool) -> np.ndarray:
    if wavetable:
        return DP
    if wave == 0:
        if mode == 1:
            return DP - ceil_div(63 * DP, 256)
        if mode == 2:
            return DP + (DP >> 1)
        return DP
    if wave == 7:
        if mode == 1:
            return DP - ceil_div(6 * DP, 256)
        if mode == 2:
            return (DP << 1) - ceil_div(DP, 64)
        return DP - ceil_div(DP, 128)
    if mode != 0:
        return DP - ceil_div(DP, 256)
    return DP


def narrow_form(wave: int, mode: int, wavetable: bool) -> np.ndarray:
    """The R.53 form: one 13-bit value and explicitly narrow corrections."""
    ceil256 = (DP >> 8) + ((DP & 255) != 0)
    ceil128 = (DP >> 7) + (DP & 127 != 0)
    ceil64 = (DP >> 6) + (DP & 63 != 0)
    ceil63_256 = ((63 * DP) >> 8) + ((63 * DP) & 255 != 0)
    ceil6_256 = ((6 * DP) >> 8) + ((6 * DP) & 255 != 0)

    if wavetable:
        return DP
    if wave == 0:
        if mode == 1:
            return DP - ceil63_256
        if mode == 2:
            return DP + (DP >> 1)
        return DP
    if wave == 7:
        if mode == 1:
            return DP - ceil6_256
        if mode == 2:
            return (DP << 1) - ceil64
        return DP - ceil128
    if mode != 0:
        return DP - ceil256
    return DP


def quotient_remainder_form(
    wave: int, mode: int, wavetable: bool
) -> np.ndarray:
    """R.57: move constant products onto the small quotient fields."""
    q256 = DP >> 8
    r256 = DP & 255
    rmod4 = r256 & 3

    # floor(193*r/256) starts as floor(3*r/4).  The missing 1/256*r
    # contributes a carry exactly when the two-bit residue does not exceed
    # the high two bits of r.  This avoids multiplying the eight-bit residue.
    low193 = (r256 - (r256 >> 2) - (rmod4 != 0)
              + ((rmod4 != 0) & ((r256 >> 6) >= rmod4)))
    dq193 = 193 * q256 + low193

    q128 = DP >> 7
    r128 = DP & 127
    ceil3r128 = (3 * r128 + 127) >> 7
    ceil6_256 = 3 * q128 + ceil3r128

    ceil64 = (DP >> 6) + ((DP & 63) != 0)
    ceil128 = q128 + (r128 != 0)
    ceil256 = q256 + (r256 != 0)

    if wavetable:
        return DP
    if wave == 0:
        if mode == 1:
            return dq193
        if mode == 2:
            return DP + (DP >> 1)
        return DP
    if wave == 7:
        if mode == 1:
            return DP - ceil6_256
        if mode == 2:
            return (DP << 1) - ceil64
        return DP - ceil128
    if mode != 0:
        return DP - ceil256
    return DP


def coefficient(wave: int, mode: int, wavetable: bool) -> int:
    """Return K for the exact identity dq = floor(K * dp / 256)."""
    if wavetable:
        return 256
    if wave == 0:
        return 193 if mode == 1 else 384 if mode == 2 else 256
    if wave == 7:
        return 250 if mode == 1 else 508 if mode == 2 else 254
    return 256 if mode == 0 else 255


def radix4_coefficient_form(
    wave: int, mode: int, wavetable: bool
) -> np.ndarray:
    """R.76's five-step 13x9 radix-4 recurrence, including bit placement."""
    coeff = coefficient(wave, mode, wavetable)
    product = np.full_like(DP, coeff)
    for _ in range(5):
        acc = (product >> 10) & ((1 << 14) - 1)
        digit = product & 3
        summed = acc + digit * DP
        product = (summed << 8) | ((product >> 2) & 0xff)
    expected_product = DP * coeff
    if not np.array_equal(product, expected_product):
        where = int(np.flatnonzero(product != expected_product)[0])
        raise AssertionError(
            f"radix4 product: wt={wavetable} wave={wave} mode={mode} "
            f"dp={where}: got={product[where]} "
            f"expected={expected_product[where]}"
        )
    return product >> 8


def main() -> None:
    maximum = 0
    cases = 0
    for wavetable in (False, True):
        for wave in range(8):
            for mode in range(4):
                reference = rtl_reference(wave, mode, wavetable)
                for form_name, candidate in (
                    ("serialized", serialized_form(wave, mode, wavetable)),
                    ("narrow", narrow_form(wave, mode, wavetable)),
                    ("quotient-remainder",
                     quotient_remainder_form(wave, mode, wavetable)),
                    ("radix4-coefficient",
                     radix4_coefficient_form(wave, mode, wavetable)),
                ):
                    if not np.array_equal(reference, candidate):
                        where = int(np.flatnonzero(reference != candidate)[0])
                        raise AssertionError(
                            f"{form_name}: wt={wavetable} wave={wave} "
                            f"mode={mode} dp={where}: "
                            f"reference={reference[where]} "
                            f"candidate={candidate[where]}"
                        )
                    maximum = max(maximum, int(candidate.max()))
                cases += candidate.size

    assert maximum < (1 << 14)
    print(f"psg_dq_model: PASS ({cases:,} cases, max={maximum}, 14 bits)")


if __name__ == "__main__":
    main()
