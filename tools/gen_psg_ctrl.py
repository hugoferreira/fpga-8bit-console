#!/usr/bin/env python3
"""Generate rtl/psg_ctrl.hex - the sample walk's one-hot control store.

The hardware-flavour synthesis walk used to decode ~40 `pph == K`
equalities and two big case trees every cycle. The schedule is a pure
function of pph, so the decode is a ROM: 128 x 32-bit words, one per
pph step, read at pph+1 so the word is registered exactly when its step
executes. Two spare EBRs carry it; the equality fabric retires.

Bit layout (must match the CTRL_* localparams in rtl/psg.sv):

  [0]  CAP_W0    PWORK+0   advance/change-detect/copy arm
  [1]  CAP_W1    PWORK+1   main sample capture
  [2]  CAP_W2    PWORK+2   secondary capture + s_last_* update
  [3]  CAP_W3    PWORK+3   smp_b capture
  [4]  CAP_W4    PWORK+4   old main z / wt q1 + sign staging
  [5]  CAP_W5    PWORK+5   old secondary z + old phase/q0 advance
  [6]  CAP_W6    PWORK+6   universal q0 advance
  [7]  CAP_W15   PWORK+15  wt p lerp result
  [8]  CAP_W17   PWORK+17  gz_s1 capture + old sign
  [9]  CAP_W26   PWORK+26  wt q lerp result
  [10] CAP_W27   PWORK+27  wt sign/leaf staging
  [11] CAP_W28   PWORK+28  recip3-hi partial
  [12] CAP_W39   PWORK+39  mx_new consume
  [13] CAP_W40   PWORK+40  wt gz_s1
  [14] CAP_W51   PWORK+51  wt recip3-hi
  [15] CAP_W52   PWORK+52  old gz_s1
  [16] CAP_W62   PWORK+62  wt mx_new consume
  [17] CAP_W63   PWORK+63  old recip3-hi
  [18] CAP_W74   PWORK+74  mx_old consume
  [19] CAP_W84   PWORK+84  blend consume
  [20] CAP_W86   PWORK+86  dampen stage
  [21] CAP_FOLD  PFOLD     fold leaf / chain launch
  [22] ISS_SEC     PWORK+1 wave-pipe issue: secondary (q view)
  [23] ISS_OLDMAIN PWORK+2 wave-pipe issue: old-state primary
  [24] ISS_OLDSEC  PWORK+3 wave-pipe issue: old-state secondary
  [25] DQ_OLD      PWORK+5 dq network serves the old context
  [29:26] MUL_SEL  product-request arm for this step (0 = none):
       1 W4 (wt lerp-p | G new)     2 W15 (wt lerp-q)
       3 W17 (limb 341)             4 W27 (wt G new)
       5 W28 (limb 171)             6 W39 (old G)
       7 W40 (wt limb 341)          8 W51 (wt limb 171)
       9 W52 (limb 341)            10 W63 (limb 171)
      11 W75 (blend)
  [30] SYN_A     PWORK+0   wavetable read, p sample
  [31] SYN_B     PWORK+1   wavetable read, p+1 sample

The invariant the RTL relies on: at most one CAP_* bit and one MUL_SEL
value per word, so the parallel `if (ctrl_q[...])` arms that replaced
the case tree stay mutually exclusive by construction.
"""

# Hardware-flavour schedule constants (rtl/psg.sv, REALTIME_PREVIEW=0).
PLOSC = 14
PWORK = 19
PFOLD = 108
PSTOR = 52
PLAST = 108

CAPS = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 15: 7, 17: 8, 26: 9,
        27: 10, 28: 11, 39: 12, 40: 13, 51: 14, 52: 15, 62: 16, 63: 17,
        74: 18, 84: 19, 86: 20}
MULS = {4: 1, 15: 2, 17: 3, 27: 4, 28: 5, 39: 6, 40: 7, 51: 8, 52: 9,
        63: 10, 75: 11}


def build():
    words = [0] * 128
    for k, bit in CAPS.items():
        words[PWORK + k] |= 1 << bit
    words[PFOLD] |= 1 << 21
    words[PWORK + 1] |= 1 << 22          # ISS_SEC
    words[PWORK + 2] |= 1 << 23          # ISS_OLDMAIN
    words[PWORK + 3] |= 1 << 24          # ISS_OLDSEC
    words[PWORK + 5] |= 1 << 25          # DQ_OLD
    for k, sel in MULS.items():
        assert (words[PWORK + k] >> 26) & 0xF == 0
        words[PWORK + k] |= sel << 26
    words[PWORK + 0] |= 1 << 30          # SYN_A
    words[PWORK + 1] |= 1 << 31          # SYN_B

    for i, w in enumerate(words):
        caps = [b for b in range(22) if (w >> b) & 1]
        assert len(caps) <= 1, f"word {i}: multiple capture bits {caps}"
    return words


def main():
    words = build()
    with open("rtl/psg_ctrl.hex", "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"rtl/psg_ctrl.hex: {len(words)} words")


if __name__ == "__main__":
    main()
