#!/usr/bin/env python3
"""Exhaustively prove the R.83 scalar waveform arithmetic and cycle bound."""

from __future__ import annotations

import numpy as np

import psg_binary_model as M


X = np.arange(1 << 16, dtype=np.int64)


def transaction_schedule(wave: int, alt: bool, secondary: bool) -> tuple[str, ...]:
    """The fixed 16-edge R.83 transaction, from launch through commit.

    The maximal triangle-alt path deliberately leaves no idle edge.  Simpler
    shapes compute early and hold their internal value until the common commit
    edge, so four contexts always consume exactly 64 walker phases.
    """
    div = tuple(f"DIV4_{i}" for i in range(10))
    if wave == 0 and alt:
        ops = ("TRI_FOLD", "TRI_X3", "TRI_Q4",
               "RAMP_X3", "NUM_CORR") + div
    elif wave in (0, 7):
        ops = ("TRI_FOLD", "TRI_X3", "TRI_SCALE")
    elif wave == 1:
        ops = ("RAMP_SELECT", "RAMP_X3", "NUM_CORR") + div + (
            "TILT_BIAS", "SECONDARY_SCALE")
    elif wave == 2 and alt:
        ops = ("SAW_CENTER", "SAW_Q4", "HALF_CENTER", "HALF_Q4",
               "ALT_ADD", "ALT_Q2", "SECONDARY_SCALE")
    elif wave == 2:
        ops = ("SAW_CENTER", "SAW_Q4", "SECONDARY_SCALE")
    elif wave in (3, 4):
        ops = ("THRESHOLD", "SECONDARY_SCALE")
    elif wave == 5 and alt and secondary:
        ops = ("ALT_ORGAN_SQUARE", "SECONDARY_SCALE")
    elif wave == 5:
        ops = ("ORG_RAMP", "ORG_NUM") + div + (
            "ORG_SELECT_BIAS", "SECONDARY_SCALE")
    else:
        ops = ("ZERO",)
    if len(ops) > 15:
        raise AssertionError(f"wave {wave} needs {len(ops) + 1} cycles")
    return ops + ("HOLD",) * (15 - len(ops)) + ("COMMIT",)


def tzv(x: np.ndarray, divisor: int) -> np.ndarray:
    """Vector truncation toward zero, matching the PICO-8 integer forms."""
    return np.where(x < 0, -((-x) // divisor), x // divisor)


def radix4_div(n: np.ndarray, divisor: int) -> np.ndarray:
    """Ten two-bit restoring steps for an unsigned 19-bit numerator."""
    rem = np.zeros_like(n)
    quot = np.zeros_like(n)
    for shift in range(18, -1, -2):
        partial = (rem << 2) | ((n >> shift) & 3)
        digit = partial // divisor
        if np.any(digit > 3):
            raise AssertionError(f"/{divisor}: radix digit exceeds three")
        rem = partial - digit * divisor
        quot = (quot << 2) | digit
    if np.any(rem >= divisor):
        raise AssertionError(f"/{divisor}: non-canonical remainder")
    return quot


def tri_raw(x: np.ndarray) -> np.ndarray:
    return np.where(x < 32768, 3 * x - 49152, 147456 - 3 * x)


def tilt_serial(x: np.ndarray, high: bool) -> np.ndarray:
    """R.83 numerator formation plus the shared radix-4 divider."""
    boundary = 61440 if high else 57344
    divisor = 15 if high else 7
    ceil_shift = 10 if high else 11
    scale = 6 if high else 3
    ramp = np.where(x >= boundary, 65535 - x, x)
    numerator = scale * ramp - ((ramp + (1 << ceil_shift) - 1) >> ceil_shift)
    quotient = radix4_div(numerator, divisor)
    # The short tail's denominator is a power of two; its exact quotient is
    # the numerator itself, as in the retained parallel pipeline.
    return np.where(x >= boundary, numerator, quotient) - 12286


def organ_serial(x: np.ndarray) -> np.ndarray:
    low = np.where(x < 16384, x - 8192, 24576 - x)
    # The low half selects ``low`` after the divide, so feed a canonical zero
    # there rather than allowing an unused negative value into unsigned state.
    high_mag = np.where(x < 32768, 0,
                        np.where(x < 49152, 2 * (x - 32768),
                                 2 * (65536 - x)))
    high = radix4_div(high_mag, 3) - 8192
    return np.where(x < 32768, low, high)


def wave_serial(wave: int, alt: bool, secondary: bool) -> np.ndarray:
    """Result committed by one fixed 16-cycle scalar transaction."""
    if wave in (0, 7):
        raw = tri_raw(X)
        if wave == 0 and alt:
            raw = tilt_serial(X, False) + 3 * tzv(raw, 4)
        return tzv(raw, 8 if secondary else 4)
    if wave == 1:
        raw = tilt_serial(X, alt)
        return tzv(raw, 2) if secondary else raw
    if wave == 2:
        raw = tzv(X - 32768, 4)
        if alt:
            raw = tzv(raw + tzv((X // 2) - 32768, 4), 2)
        return tzv(raw, 2) if secondary else raw
    if wave in (3, 4):
        threshold = ((0x9800 if alt else 0x8000) if wave == 3
                     else (0xC800 if alt else 0xB000))
        raw = np.where(X < threshold, -6143, 6143)
        return tzv(raw, 2) if secondary else raw
    if wave == 5:
        if alt and secondary:
            # Preserve R.78 exactly.  psg_wave selects the already half-scale
            # alternate-organ square and then applies the common secondary
            # divide-by-two at z_eval.  This differs from wave_pair() in the
            # binary model, which treats +/-3071 as the final secondary term.
            return tzv(np.where(X < 32768, -3071, 3071), 2)
        raw = organ_serial(X)
        return tzv(raw, 2) if secondary else raw
    return np.zeros_like(X)


class CycleState:
    """Vectorized register state for one fixed-context scalar transaction.

    Each array lane is one of the 65,536 possible phases.  ``step`` models one
    active clock edge: later operations can observe only state written by an
    earlier call.  The model deliberately keeps the unsigned divider state
    separate from the signed result accumulator; the tilted-saw numerator is
    19-bit unsigned and does not fit an 18-bit signed accumulator.
    """

    def __init__(self, wave: int, alt: bool, secondary: bool) -> None:
        self.wave = wave
        self.alt = alt
        self.secondary = secondary
        self.acc = np.zeros_like(X)
        self.aux = np.zeros_like(X)
        self.dividend = np.zeros_like(X)
        self.quot = np.zeros_like(X)
        self.rem = np.zeros_like(X)
        self.divisor = 0
        self.div_steps = 0
        self.out = np.zeros_like(X)
        self.valid = False
        self.commit_cycle = 0
        self.peak_acc = 0
        self.peak_dividend = 0

    def _ramp(self) -> np.ndarray:
        boundary = 61440 if self.wave == 1 and self.alt else 57344
        return np.where(X >= boundary, 65535 - X, X)

    def _start_divide(self, dividend: np.ndarray, divisor: int) -> None:
        if np.any(dividend < 0) or np.any(dividend >= (1 << 19)):
            raise AssertionError("divider numerator exceeds unsigned 19 bits")
        self.dividend = dividend
        self.divisor = divisor
        self.quot.fill(0)
        self.rem.fill(0)
        self.div_steps = 0
        self.peak_dividend = max(self.peak_dividend, int(np.max(dividend)))

    def _divide_step(self, index: int) -> None:
        if index != self.div_steps or self.divisor not in (3, 7, 15):
            raise AssertionError("divider step is out of sequence")
        shift = 18 - 2 * index
        partial = (self.rem << 2) | ((self.dividend >> shift) & 3)
        # This is the hardware digit recurrence, not a Python divide.  Since
        # the incoming remainder is canonical, partial is always below 4*d.
        digit = np.where(partial >= 3 * self.divisor, 3,
                         np.where(partial >= 2 * self.divisor, 2,
                                  np.where(partial >= self.divisor, 1, 0)))
        self.rem = partial - digit * self.divisor
        self.quot = (self.quot << 2) | digit
        self.div_steps += 1
        if np.any(self.rem < 0) or np.any(self.rem >= self.divisor):
            raise AssertionError("non-canonical cycle divider remainder")
        if self.div_steps == 10:
            self.acc = self.quot.copy()

    def step(self, op: str, cycle: int) -> None:
        if self.valid:
            raise AssertionError("transaction stepped after commit")

        if op == "TRI_FOLD":
            self.acc = np.where(X < 32768, X - 16384, 49152 - X)
        elif op == "TRI_X3":
            self.acc = 3 * self.acc
        elif op == "TRI_Q4":
            self.aux = tzv(self.acc, 4)
        elif op == "TRI_SCALE":
            self.acc = tzv(self.acc, 8 if self.secondary else 4)
        elif op == "RAMP_SELECT":
            self.acc = self._ramp()
        elif op == "RAMP_X3":
            ramp = self._ramp() if self.wave == 0 else self.acc
            self.acc = (6 if self.wave == 1 and self.alt else 3) * ramp
        elif op == "NUM_CORR":
            ramp = self._ramp()
            ceil_shift = 10 if self.wave == 1 and self.alt else 11
            numerator = self.acc - ((ramp + (1 << ceil_shift) - 1)
                                    >> ceil_shift)
            self._start_divide(numerator,
                               15 if self.wave == 1 and self.alt else 7)
            self.acc = numerator
        elif op.startswith("DIV4_"):
            self._divide_step(int(op.removeprefix("DIV4_")))
        elif op == "TILT_BIAS":
            boundary = 61440 if self.alt else 57344
            self.acc = np.where(X >= boundary, self.dividend, self.quot) - 12286
        elif op == "SAW_CENTER":
            self.acc = X - 32768
        elif op == "SAW_Q4":
            self.acc = tzv(self.acc, 4)
        elif op == "HALF_CENTER":
            self.aux = self.acc.copy()
            self.acc = (X // 2) - 32768
        elif op == "HALF_Q4":
            self.acc = tzv(self.acc, 4)
        elif op == "ALT_ADD":
            self.acc = self.aux + self.acc
        elif op == "ALT_Q2":
            self.acc = tzv(self.acc, 2)
        elif op == "THRESHOLD":
            threshold = ((0x9800 if self.alt else 0x8000)
                         if self.wave == 3
                         else (0xC800 if self.alt else 0xB000))
            self.acc = np.where(X < threshold, -6143, 6143)
        elif op == "ALT_ORGAN_SQUARE":
            self.acc = np.where(X < 32768, -3071, 3071)
        elif op == "ORG_RAMP":
            self.acc = np.where(X < 32768, 0,
                                np.where(X < 49152, 2 * (X - 32768),
                                         2 * (65536 - X)))
        elif op == "ORG_NUM":
            self._start_divide(self.acc, 3)
        elif op == "ORG_SELECT_BIAS":
            low = np.where(X < 16384, X - 8192, 24576 - X)
            self.acc = np.where(X < 32768, low, self.quot - 8192)
        elif op == "SECONDARY_SCALE":
            if self.secondary:
                self.acc = tzv(self.acc, 2)
        elif op == "ZERO":
            self.acc.fill(0)
        elif op == "HOLD":
            pass
        elif op == "COMMIT":
            if self.wave == 0 and self.alt:
                raw = np.where(X >= 57344, self.dividend, self.quot)
                raw = raw - 12286 + 3 * self.aux
                self.acc = tzv(raw, 8 if self.secondary else 4)
            self.out = self.acc.copy()
            self.valid = True
            self.commit_cycle = cycle
        else:
            raise AssertionError(f"unknown scalar operation {op}")

        self.peak_acc = max(self.peak_acc, int(np.max(np.abs(self.acc))))
        if self.peak_acc >= (1 << 19):
            raise AssertionError("signed scalar state exceeds 20 bits")


def run_cycle_transaction(wave: int, alt: bool,
                          secondary: bool) -> CycleState:
    """Execute the fixed microprogram one edge at a time."""
    state = CycleState(wave, alt, secondary)
    for cycle, op in enumerate(transaction_schedule(wave, alt, secondary), 1):
        state.step(op, cycle)
    if not state.valid or state.commit_cycle != 16:
        raise AssertionError("transaction did not commit exactly on edge 16")
    if state.divisor and state.div_steps != 10:
        raise AssertionError("transaction committed an incomplete divide")
    return state


def rtl_reference(wave: int, alt: bool, secondary: bool) -> np.ndarray:
    if wave in (0, 7):
        fn = M.tri_alt if wave == 0 and alt else M.tri_raw
        shift = 8 if secondary else 4
    elif wave == 1:
        fn = lambda x: M.tilt(x, 61440 if alt else 57344)
        shift = 2 if secondary else 1
    elif wave == 2:
        fn = M.saw_alt if alt else M.saw
        shift = 2 if secondary else 1
    elif wave == 3:
        fn = lambda x: M.square_at(x, 0x9800 if alt else 0x8000)
        shift = 2 if secondary else 1
    elif wave == 4:
        fn = lambda x: M.square_at(x, 0xC800 if alt else 0xB000)
        shift = 2 if secondary else 1
    elif wave == 5:
        if alt and secondary:
            fn = lambda x: -3071 if x < 32768 else 3071
            # Exact current psg_wave.sv semantics, not wave_pair() semantics.
            shift = 2
        else:
            fn = M.organ
            shift = 2 if secondary else 1
    else:
        fn = lambda _x: 0
        shift = 1
    return np.fromiter((M.tz(fn(x), shift) for x in range(1 << 16)),
                       dtype=np.int64, count=1 << 16)


def main() -> None:
    for divisor in (3, 7, 15):
        n = np.arange(1 << 19, dtype=np.int64)
        got = radix4_div(n, divisor)
        if not np.array_equal(got, n // divisor):
            i = int(np.flatnonzero(got != n // divisor)[0])
            raise AssertionError(f"/{divisor} mismatch at {i}")
        print(f"PROVED radix4 /{divisor}: all 524,288 unsigned 19-bit numerators")

    cases = 0
    cycle_cases = 0
    peak_acc = 0
    peak_dividend = 0
    schedules: set[tuple[str, ...]] = set()
    for wave in range(8):
        for alt in (False, True):
            for secondary in (False, True):
                got = wave_serial(wave, alt, secondary)
                want = rtl_reference(wave, alt, secondary)
                if not np.array_equal(got, want):
                    i = int(np.flatnonzero(got != want)[0])
                    raise AssertionError(
                        f"wave={wave} alt={int(alt)} secondary={int(secondary)} "
                        f"phase={i}: got {got[i]}, expected {want[i]}"
                    )
                state = run_cycle_transaction(wave, alt, secondary)
                if not np.array_equal(state.out, want):
                    i = int(np.flatnonzero(state.out != want)[0])
                    raise AssertionError(
                        f"cycle wave={wave} alt={int(alt)} "
                        f"secondary={int(secondary)} phase={i}: "
                        f"got {state.out[i]}, expected {want[i]}"
                    )
                schedule = transaction_schedule(wave, alt, secondary)
                assert len(schedule) == 16 and schedule[-1] == "COMMIT"
                schedules.add(schedule)
                cases += len(X)
                cycle_cases += len(X)
                peak_acc = max(peak_acc, state.peak_acc)
                peak_dividend = max(peak_dividend, state.peak_dividend)
    print(f"PROVED R.78 scalar waves for R.83: {cases:,} context/phase results")
    print(f"PROVED fixed transactions: 32 contexts, {len(schedules)} paths, "
          "16 cycles each")
    print(f"PROVED cycle-state commits: {cycle_cases:,} context/phase results; "
          f"peak signed state {peak_acc:,}, peak unsigned numerator "
          f"{peak_dividend:,}")
    print("MAXIMAL transaction: "
          + " -> ".join(transaction_schedule(0, True, False)))

    # Preserve the distinction instead of silently treating the binary model
    # as the RTL oracle.  R.78 divides the already-half-amplitude alternate
    # organ secondary once more; wave_pair() does not.
    rtl_alt_organ = wave_serial(5, True, True)
    binary_alt_organ = np.where(X < 32768, -3071, 3071)
    mismatch = int(np.count_nonzero(rtl_alt_organ != binary_alt_organ))
    assert mismatch == len(X)
    print("RECORDED semantic boundary: R.78 alternate-organ secondary "
          f"differs from binary model at {mismatch:,}/65,536 phases")

    visit = 62 - 6 + 4 * 16
    walk = 8 * visit + 34
    total = walk + 272
    assert visit == 120 and walk == 994 and total == 1266 and total < 1275
    print("PROVED schedule: 4x16 replaces 6 phases; visit=120, walk=994, "
          "walk+272=1266/1275 (9 spare)")


if __name__ == "__main__":
    main()
