#!/usr/bin/env python3
"""Build the sample walk's encoded control words.

The hardware-flavour synthesis walk used to decode ~40 `pph == K`
equalities and two big case trees every cycle. The schedule is a pure
function of pph, so the decode is a ROM: 128 x 16-bit words, one per
pph step, read at pph+1 so the word is registered exactly when its step
executes. tools/gen_psg_tables.py embeds the live 0..PLAST range from word
144 onward in rtl/psg_const.hex, sharing that EBR with the sequencer.

Bit layout (must match rtl/psg_walk.sv):

  [4:0] CAP_SEL, zero for no action and 1..23 for:
       W0 W1 W2 W3 W4 W5 W6 W15 W17 W26 W27 W28 W39 W40 W51
       W52 W62 W63 W74 W84 W86 FOLD W75
       Product launches are selected by this same phase identity. Ten of
       eleven already coincide with a capture; W75 is the one launch-only
       action. Encoding a second MUL_SEL repeated the phase decode.
  [8:5] spare
  [9]  ISS_SEC     PWORK+1 wave-pipe issue: secondary (q view)
  [10] ISS_OLDMAIN PWORK+2 wave-pipe issue: old-state primary
  [11] ISS_OLDSEC  PWORK+3 wave-pipe issue: old-state secondary
  [12] DQ_OLD      PWORK+5 dq network serves the old context
  [13] SYN_A       PWORK+0 wavetable read, p sample
  [14] SYN_B       PWORK+1 wavetable read, p+1 sample
  [15] spare
"""

# Hardware-flavour schedule constants (rtl/psg.sv, REALTIME_PREVIEW=0).
PLOSC = 14
PWORK = 19
PFOLD = 84
PSTOR = 52
PLAST = 84

CAPS = {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 15: 8, 17: 9,
        26: 10, 27: 11, 40: 14, 50: 15, 51: 23, 60: 20,
        62: 21}


def build():
    words = [0] * 128
    for k, sel in CAPS.items():
        assert words[PWORK + k] & 0x1F == 0
        words[PWORK + k] |= sel
    words[PFOLD] |= 22
    words[PWORK + 1] |= 1 << 9           # ISS_SEC
    words[PWORK + 2] |= 1 << 10          # ISS_OLDMAIN
    words[PWORK + 3] |= 1 << 11          # ISS_OLDSEC
    words[PWORK + 5] |= 1 << 12          # DQ_OLD
    words[PWORK + 0] |= 1 << 13          # SYN_A
    words[PWORK + 1] |= 1 << 14          # SYN_B

    for i, w in enumerate(words):
        assert (w & 0x1F) <= 23, f"word {i}: invalid action opcode"
        assert w < (1 << 15), f"word {i}: control word exceeds 15 bits"
    return words


def main():
    words = build()
    print(f"{len(words)} control words; live range 0..{PLAST} occupies "
          f"psg_const.hex words 144..{144 + PLAST}")


if __name__ == "__main__":
    main()
