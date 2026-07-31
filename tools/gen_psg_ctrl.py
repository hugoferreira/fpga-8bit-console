#!/usr/bin/env python3
"""Build the sample walk's control words.

The hardware-flavour synthesis walk used to decode ~40 `pph == K`
equalities and two big case trees every cycle. The schedule is a pure
function of pph, so the decode is a ROM: 128 x 16-bit words, one per
pph step, read at pph+1 so the word is registered exactly when its step
executes. tools/gen_psg_tables.py embeds the live 0..PLAST range from word
144 onward in rtl/psg_const.hex, sharing that EBR with the sequencer.

The word is ONE-HOT over the sixteen actions, not an encoded opcode. The
encoded form existed to fit 32 bits into 16 and so save a block, back when
blocks were the binding resource; the walk then paid ~50 logic cells to
decode it every cycle. There are exactly sixteen actions, so one-hot fits
the SAME 16-bit word and the same shared port - the decode is free.

The six former flag bits are gone because one-hot makes them ALIASES: each
sits on a phase that already carries an action.

  SYN_A       PWORK+0  = W0     wavetable read, p sample
  SYN_B       PWORK+1  = W1     wavetable read, p+1 sample
  ISS_SEC     PWORK+1  = W1     wave-pipe issue: secondary (q view)
  ISS_OLDMAIN PWORK+2  = W2     wave-pipe issue: old-state primary
  ISS_OLDSEC  PWORK+3  = W3     wave-pipe issue: old-state secondary
  DQ_OLD      PWORK+5  = W5     dq network serves the old context

CAP_FOLD is likewise gone: it fired at PFOLD, which IS PLAST, and the walk
already tests `pph == PLAST` to close the visit.

Bit layout (must match rtl/psg_walk.sv's CAP_* one-hot indices):

  0 W0   1 W1   2 W2   3 W3   4 W4   5 W5   6 W6   7 W15
  8 W17  9 W26 10 W27 11 W40 12 W51 13 W75 14 W84 15 W86
"""

# Hardware-flavour schedule constants (rtl/psg.sv, REALTIME_PREVIEW=0).
PLOSC = 14
PWORK = 19
PFOLD = 84
PSTOR = 52
PLAST = 84

# pph offset from PWORK -> one-hot bit index.
CAPS = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 15: 7, 17: 8,
        26: 9, 27: 10, 40: 11, 50: 12, 51: 13, 60: 14,
        62: 15}


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
    return words


def main():
    words = build()
    live = sum(1 for w in words[:PLAST + 1] if w)
    print(f"{len(words)} control words, {live} with an action; live range "
          f"0..{PLAST} occupies psg_const.hex words 144..{144 + PLAST}")


if __name__ == "__main__":
    main()
