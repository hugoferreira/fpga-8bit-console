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

THE OFFSETS ARE THE SCHEDULE. The iCE40 full schedule uses the R.74
multi-pumped service: every normal product has crossed back through the
acknowledge synchronizer in time for a consumer at request+5, and the short
request retains its request+4 shipped spacing. The sequencer sees a separate
padded busy and is deliberately not recompacted.

  both profiles  W4 ->9    W15 ->14   W27 ->20   W40 ->25   W75 ->30
                 (normal)  (normal)   (normal)   (normal)   (short)

W15 carries BOTH chains: the wavetable q-side lerp and the non-wavetable
first reciprocal limb are `s_snd_wt`-exclusive, so they share one action
rather than burning a phase each. W26 (the wavetable q consume) and W27
(the G launch, which reads the smp_b W26 writes) canNOT merge - one writes
what the other reads - so they stay one phase apart and the non-wavetable
chain waits that phase out with its product already parked. R.58 makes the
sequencer credit independent of walk length, so W84 now consumes the blend
on its first readable phase and commits dampen/filter on that edge. The last
late state write shares PLAST with slot close and fold launch.

Bit layout (must match rtl/psg_walk.sv's CAP_* one-hot indices):

  0 W0   1 W1   2 W2   3 W3   4 W4   5 W5   6 W6   7 W15
  8 W26  9 W27 10 W40 11 W51 12 W75 13 W84 14 spare  15 spare
"""

# Hardware-flavour schedule constants (rtl/psg_walk.sv, REALTIME_PREVIEW=0).
PLOSC = 14
PWORK = 29
PFOLD = 61
PSTOR = 46
PLAST = 61

# pph offset from PWORK -> one-hot bit index.
CAPS = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6,
        9: 7,           # W15: wavetable q lerp / non-wavetable limb 1
        14: 8,          # W26: wavetable q consume
        15: 9,          # W27: G launch, both profiles
        20: 10,         # W40: reciprocal limb, both profiles
        25: 11,         # W51: mx_new / mx_old
        26: 12,         # W75: blend launch
        30: 13}         # W84: blend consume and dampen/filter commit


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
    # have to fit inside the visit. The final state write shares PLAST with
    # slot close and fold launch; the last action precedes both late writes.
    assert PWORK + max(CAPS) < PLAST - 1, "an action lands on a late write"
    assert PSTOR + PLOSC <= PLAST - 1, "store window overruns the late writes"
    assert PSTOR > PWORK + 6, "store window starts before the last s_* write"
    return words


def main():
    words = build()
    live = sum(1 for w in words[:PLAST + 1] if w)
    print(f"{len(words)} control words, {live} with an action; live range "
          f"0..{PLAST} occupies psg_const.hex words 144..{144 + PLAST}")
    print(f"visit is {PLAST + 1} phases; store window {PSTOR}.."
          f"{PSTOR + PLOSC - 1}, late dampen {PLAST - 1}/{PLAST}")


if __name__ == "__main__":
    main()
