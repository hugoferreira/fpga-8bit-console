#!/usr/bin/env python3
"""Build the sample walk's control words.

The schedule is a pure function of pph, so the step decode is a ROM: 128 x
16-bit words, one per pph step, read at pph+1 so the word is registered
exactly when its step executes. tools/gen_psg_tables.py embeds the live
0..PLAST range from word 144 onward in rtl/psg_const.hex, sharing that EBR
with the sequencer.

The word is ONE-HOT over the actions. The six former flag bits are gone
because one-hot makes them ALIASES - each sits on a phase that already
carries an action (SYN_A/W0, SYN_B and ISS_SEC/W1, ISS_OLDMAIN/W2,
ISS_OLDSEC/W3, DQ_OLD/W5) - and CAP_FOLD is gone because its phase IS
PLAST, which the walk already tests to close the visit.

THE OFFSETS ARE THE SCHEDULE, and they are spaced by the multiply service's
RADIX-4 latency: a request issued at phase p is readable at p + steps + 1,
so mode 2 (6 steps) lands at p+7, modes 1 and 3 (5 steps) at p+6, and the
short request (3 steps) at p+4. Radix-2 spacing left the chain at 65
phases; this is 43.

  non-wavetable  W4 ->11   W15 ->17   W27 ->25   W40 ->31   W75 ->36
                 (mode 2)  (mode 3)   (mode 2)   (mode 3)   (short)
  wavetable      W4 ->10   W15 ->17   W27 ->25   W40 ->31   W75 ->36
                 (mode 1)  (mode 1)   (mode 2)   (mode 3)   (short)

W15 carries BOTH chains: the wavetable q-side lerp and the non-wavetable
first reciprocal limb are `s_snd_wt`-exclusive, so they share one action
rather than burning a phase each. W26 (the wavetable q consume) and W27
(the G launch, which reads the smp_b W26 writes) canNOT merge - one writes
what the other reads - so they stay one phase apart and the non-wavetable
chain waits that phase out with its product already parked. W84 consumes
the blend two phases after it is readable: that gap is load-bearing (R.31 -
closing it diverged Celeste music 20 at 21.246 s).

Bit layout (must match rtl/psg_walk.sv's CAP_* one-hot indices):

  0 W0   1 W1   2 W2   3 W3   4 W4   5 W5   6 W6   7 W15
  8 W26  9 W27 10 W40 11 W51 12 W75 13 W84 14 W86   15 spare
"""

# Hardware-flavour schedule constants (rtl/psg_walk.sv, REALTIME_PREVIEW=0).
PLOSC = 14
PWORK = 19
PFOLD = 62
PSTOR = 43
PLAST = 62

# pph offset from PWORK -> one-hot bit index.
CAPS = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6,
        11: 7,          # W15: wavetable q lerp / non-wavetable limb 1
        17: 8,          # W26: wavetable q consume
        18: 9,          # W27: G launch, both profiles
        25: 10,         # W40: reciprocal limb, both profiles
        31: 11,         # W51: mx_new / mx_old
        32: 12,         # W75: blend launch
        38: 13,         # W84: blend consume
        40: 14}         # W86: comb and dampen


def build():
    words = [0] * 128
    for k, bit in CAPS.items():
        assert words[PWORK + k] == 0, f"two actions on pph {PWORK + k}"
        words[PWORK + k] |= 1 << bit
    # psg_walk gates pph 0 to zero: the word registered for the visit's first
    # phase was fetched while the sequencer still owned the shared port. An
    # action placed there would be silently suppressed, so forbid one.
    assert words[0] == 0, "pph 0 cannot carry an action (see psg_walk's gate)"
    for i, w in enumerate(words):
        assert w < (1 << 16), f"word {i}: control word exceeds 16 bits"
        assert w == 0 or (w & (w - 1)) == 0, f"word {i}: not one-hot"
    # The oscillator store window and the two late dampen write-backs both
    # have to fit inside the visit, and the last action has to precede them.
    assert PWORK + max(CAPS) < PLAST - 2, "an action lands on a late write"
    assert PSTOR + PLOSC <= PLAST - 2, "store window overruns the late writes"
    assert PSTOR > PWORK + 6, "store window starts before the last s_* write"
    return words


def main():
    words = build()
    live = sum(1 for w in words[:PLAST + 1] if w)
    print(f"{len(words)} control words, {live} with an action; live range "
          f"0..{PLAST} occupies psg_const.hex words 144..{144 + PLAST}")
    print(f"visit is {PLAST + 1} phases; store window {PSTOR}.."
          f"{PSTOR + PLOSC - 1}, late dampen {PLAST - 2}/{PLAST - 1}")


if __name__ == "__main__":
    main()
