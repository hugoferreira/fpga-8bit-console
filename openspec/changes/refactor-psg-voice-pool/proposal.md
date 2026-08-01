# Replace the PSG's four fixed channels with PICO-8's voice pool

## Why

PICO-8 does not have four audio channels. It has **sixteen mixer voices** and
four *logical channel tags*. `sfx(n, -1)` — which is what essentially every
cart uses, including all three of ours — takes a free voice from that pool and
tags it. It never displaces anything. Music holds four voices tagged 0–3 and
they are untouchable by a sound effect.

This is from a routine-level disassembly of the shipping PICO-8 binary
(`/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md`, recorded in
`docs/hardware-gaps.md`): the mixer state array `_ms0` is 16 × 0x3700 bytes,
`_codo_mixer_callback_0` updates all sixteen, `_codo_play_pico8_song` assigns
tags 0–3 at voice offset `+0x203c`, and "an automatically selected channel is
assigned from the internal pool instead of being tied permanently to one of
four physical buffers".

Our PSG has four physical channels, so a sound effect *must* take one. Every
audio defect chased in this port traces back to that single divergence:

- A cursor beep could take a music channel and silence the song. Worked around
  by reserving channels, then by a borrow/restore mechanism (`sav_sfx`,
  `sav_row`, `sav_valid` and the preempt paths in `rtl/psg.sv`), then by
  teaching the pattern clock not to depend on any one channel.
- Three separate races were found in that borrow path in one sitting (test 18c
  in `rtl/psg_tb.sv`), all of which are unreachable if a sound effect can never
  take a music voice in the first place.
- Auto-channel-pick lives in 6502 software, duplicated in `src/nemo/sound.asm`
  and `src/main.asm`, because the PSG cannot do it. It has to consult the
  status register, the reservation mask and now the song's occupied channels,
  and it still has to decide what to do when nothing is free — a decision
  PICO-8 never has to make.

The measurements say the hardware can afford the real thing in time but not in
logic. The PSG clock is derived from the design's 112.5 MHz PLL source. The
current iCE40 implementation divides it by four while the existing
combinational datapath is timing-limited, still providing 1275 clocks per
22 050 Hz sample; closing at the undivided source provides 5102. A Verilated
console's host-dependent execution rate is not a hardware clock budget and
does not constrain the RTL. The real cost is state and parallel arithmetic,
so the fix is to store voice state in block RAM and trade the hardware's clock
headroom for a microcoded, time-shared datapath. See `design.md`.

## What Changes

- **Sixteen voices, four logical channels.** Voices carry a channel tag. The
  music sequencer owns four voices tagged 0–3; the CPU addresses channels, not
  voices.
- **Auto-allocation moves into hardware.** A new register write means "play
  this SFX on a free voice" — PICO-8's `sfx(n, -1)`. A voice the music owns is
  never a candidate. The software auto-pick in `src/nemo/sound.asm` and
  `src/main.asm` collapses to a single store.
- **Borrow/restore is deleted.** `sav_sfx`, `sav_row`, `sav_valid`,
  `music_owned`'s preempt paths and the reservation-mask workarounds all exist
  only to survive a situation that can no longer arise.
- **Voice state is partitioned by rate.** Per-sample state stays in registers;
  per-tick sequencer state moves to a BRAM-backed register file walked once per
  tick. This is what makes sixteen voices cost *less* silicon than four do now.
- **The mix becomes PICO-8's pairwise `soft_add` reduction tree** instead of a
  flat sum with a hard clip — the natural way to reduce sixteen voices, and a
  known gap in its own right.
- **Arithmetic becomes microcoded and time-shared.** Effects are evaluated by
  a microcode-oriented engine; redundant resets and registers are removed;
  reciprocal networks become iterative; and sample-rate arithmetic is
  serialised around a shared ALU/DSP. Correctness is gated on completing work
  before the next sample or tick boundary, never on a Verilator host-cycle
  estimate.

## Impact

- Affected specs: `audio-engine` (voice pool, auto-allocation, mix, sequencer,
  status readback)
- Affected code: `rtl/psg.sv` (substantially rewritten), `rtl/psg_tb.sv`,
  `src/nemo/sound.asm`, `src/main.asm` (breakout), `src/celeste/` audio if it
  auto-picks, `sim/console.cpp` (`--psg-trace` gains voices)
- **Cross-game impact**: this change alters the audio for every game.
- Risk: this is the largest single change to the PSG since it was written. It
  is gated on the existing `make test-psg` suite passing unchanged, plus new
  cases for allocation and pooling, plus an A/B render of each game's music.
