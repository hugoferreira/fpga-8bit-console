# adopt-pico8-integer-audio — design

## Context

The PSG's fidelity was recovered empirically: waveforms as 8-bit tables
sampled from float formulas, volume as `(nv*iv*1317) >> 8`, effects as
close-but-not-equal recurrences, all adjudicated by fitted-gain/NRMSE
gates against PICO-8's own exports. The 2026-07-27 oracle analysis
(appended to `docs/hardware-gaps.md`) proved the export pipeline is clean —
square/pulse match at NRMSE 1e-5 — and decomposed every remaining residual
into our own layers. Meanwhile the routine-level reverse engineering at
`/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md` contains the
binary's exact integer forms, and this session spot-verified the
load-bearing ones against `pico8.x86_64.asm` at instruction level:

| formula | verification |
| --- | --- |
| `scale(z) = tz(G*z/3072)` | `imulq $0x2aaaaaab; shrq $0x3f; shrq $0x29; add` — magic divide WITH sign correction (tz, not floor) |
| `q0 = (q0+dq) & 0x1ffff`, `q = u16(q0 << mode)` | `andl $0x1ffff`, `shll %cl` + `movzwl` |
| square/pulse thresholds `0x8000/0xb000`, alternates `+0x1800`, p-term ±6143 + q-term ±3071 | constants and cmov chain in the wave switch |
| organ, both halves incl. `tz(2(x-32768)/3)` | `_inst5`: `imulq $0x55555556` with sign correction, `-8192` tails |
| drop `tz(DX(P0)*(D-t)/D)` | `imull; cltd; idivl` — hardware truncation |
| composed volume `tz(a*iv/256)` | `imull; leal 0xff(...); cmovnsl; sarl $8` — the tz bias |
| custom wave: 64-entry lerp, 10 fractional bits | `shrl $0xa; andl $0x3f` index, `andl $0x3ff` fraction — matches our RTL |
| alternate-triangle skew `/57344` | `$0x92492493` (÷7 magic) with `$0x2000` |

Formulas not yet instruction-verified (tri_raw's `3x-49152`, saw's
`tz((x-32768)/4)`, fades, vibrato, slide fine path, the 64-sample blend,
noise modes) each get a verification task before their RTL lands.

**Model checkpoint (task 1.1/1.3 first milestone):**
`tools/psg_binary_model.py` reproduces the stored PICO-8 exports
**byte-for-byte on all 24 deterministic single-voice cases** — every
wave 0-5, every pitch probe, and all seven effects including the slide
fine path, drop's rounding-to-zero, and both arpeggios. The exports
carry a per-case lead-in (8..160 samples) which the comparison aligns
by onset. Getting to exactness forced three additions beyond the notes,
now part of the verified record:

- `dq = tz(dp*K/256)` with K = 256 in mode 0 (so dq = dp exactly) and
  K = 255 in the detune flavor - decoded from `_calculate_osc_state`'s
  stores to +0x10, matching the RTL's recovered DETUNE-1 form.
- A zero-amplitude tick resets the oscillator to canonical phase; the
  next audible tick restarts from zero rather than continuing (the
  binary's speed-2 fade-in rows export byte-identical audible ticks,
  which is how the model's phase drift was caught).
- `_get_dx_for_note_fine` interpolates the NOTE_DX **table entries** by
  the 16-bit fraction before the shared reciprocal multiply and octave
  shift - not the final increments - against a 13-entry table whose
  octave-wrap entry (1046) was read out of the binary's data segment.

Indirectly verified byte-exact through those 24 cases: tri_raw, saw,
tilt_57344, the fades, vibrato's multiplier sequence, the slide
recurrences, and the 64-sample crossfade.

**Second milestone: 29/29 deterministic single-voice cases**, adding
the detune modes, the buzz/alternate waveform family and the phaser.
The additional decoded facts:

- The per-wave/per-mode dq map from `_calculate_osc_state`'s tails:
  triangle detunes at 193/256 (mode 1) and 384/256 - a fifth up -
  (mode 2); the phaser's secondary runs at exactly 254/256 by default,
  250/256 and 508/256 in its modes (the RTL's 109/110 serial chain is
  a mis-approximation to replace); waves 1..5 use the general 255/256.
- Detuned voices of waves 0..5 get an amplitude boost `a = tz(5a/4)`
  before G (the +0x1c rewrite at `0x1000f1bbb`) - this is the
  detune-probe level the old fitted-gain gates absorbed.
- The buzz flag selects the alternate family: tri_alt with the /57344
  skew, tilt at 61440, square/pulse thresholds 0x9800/0xC800, saw_alt,
  and organ's half-amplitude-square secondary - all byte-verified
  through filter-buzz.
- **The history comb is live-playback only.** The wave-7-phaser export
  matches the comb-free stream on all 5,696 samples: the eight-slot
  ring stays empty in the export path that produced every reference.
  The comb (and with it the reverb question) is a documented model
  boundary alongside the shared RNG; the phaser's export-visible
  identity is the triangle core with the 254/256 secondary.

**Third milestone: 43/43 cases byte-exact** - the soft_add tree with
real multi-voice content (mix-four crosses the compression threshold),
all three transitions (free: the crossfade machinery already models
them), the complete meta-instrument family, and the wavetable voice.
Decoded and confirmed on the way:

- Music-launched channels occupy tree leaves 4..7; the pairwise order
  and 5:1 compression verified byte-exact under load.
- The instrument volume composition is `a = tz(a * iv / 7)` with iv the
  raw 0..7 row volume - exact sevenths, confirmed through
  sfx-instrument-volume. The RTL's `(nv*iv*1317) >> 8` is the
  approximation it replaces.
- Retrigger rules, the per-tick playhead advance, per-instrument-row
  prev tracking and the instrument-effect context (the instrument's own
  speed/tick/pos timing when the note's effect is 0) all verified
  through the eight sfx-instrument variants.
- The wavetable voice: record bytes as signed samples at load shift 7,
  the 10-fractional-bit lerp, full volume from the note path - and the
  octave-down applies when the speed byte's bit 0 is CLEAR, the
  opposite of the RTL comment's rule (convicted by the export's 2x
  rate; the RTL list of adoption fixes grows: 109/110 -> 254/256,
  bass-rule inversion, 1317-composition -> tz(a*iv/7)).

**Fourth milestone: 48/48 - the deterministic model is complete**,
adding dampen, reverb and the pattern-chain music flow, and landing the
regression harness as a durable subcommand (`psg_binary_model.py
sweep`: every deterministic case of the oracle matrix rendered through
the music player and byte-compared onset-aligned; the two noise cases
skip at the shared-RNG boundary). Decoded and confirmed:

- DAMPEN is the per-sample one-pole `y = tz((x + (2^d - 1)*y) / 2^d)`
  with d the filter digit (level 1: /2). The truncation applies to the
  whole blend, not to a difference-form step: `y += tz((x-y)/2^d)`
  reproduces the identical onset settle (0, 4031, 6046, 7054 toward
  +/-8062, stuck one short at 8061) but stalls at |y| = 1 on decay,
  while filter-dampen-impulse's export decays to exactly zero - the
  discriminating case (one-unit mismatches from tick 1, sample 4).
- REVERB confirmed on the first run, exactly as decoded: the per-voice
  eight-slot history ring, tap `(rpos+4+2*(level==1)) & 7` - 366
  samples back at level 1, 732 at level 2 - comb `y = tz((4y+2h)/4)`,
  post-comb write-back. The ring runs only under the reverb digit,
  which closes the phaser reconciliation: wave-7's export is comb-free
  because its case carries reverb 0, not because the comb is unreal.
- The pattern-chain song clock: pace = the left-most launched
  non-looping channel (speed x its length-only-or-32 rows), stop =
  pattern byte2 bit7, voices persist their OscState across pattern
  switches.

Recorded as open rather than guessed closed: no current case exercises
dampen level 2 (the /4, 3y form) or reverb level 2 (the 732-sample
tap), and none combines dampen with reverb, so their relative order
(model: dampen, then reverb) is untested. The re-capture (task 5.1)
should add filter-dampen-2 (filt 144), filter-reverb-2 (filt 48) and a
combined probe (filt 96) to pin all three.

Noise stays at the RNG boundary; the model's remaining work is the
reference re-capture and gate flip (section 5), then the RTL phases.

Constraints inherited from `reduce-psg-ice40-area`, which pauses at its
6,199-cell / 15-EBR checkpoint until this change lands: the 15-EBR
ceiling, the 1,275-clock sample budget (pre-run depth is a free constant),
and the measurement law — placed cells at seed 1 decide, and shared
routing pays only through address-selected storage.

## Goals / Non-Goals

**Goals:**

- Byte-exact waveform and effect arithmetic against the binary's integer
  forms, verified per formula against both the disassembly and a Python
  model of the export references before any RTL edit.
- Flip every deterministic oracle case from tolerance gates to exact
  comparison; re-capture references once, at the end.
- Hold or improve the area checkpoint (6,199 / 15 EBR) and the sample
  budget; the freed triangle/organ EBR is the expected area payback.
- State the shared-RNG noise boundary as a documented, permanent limit.

**Non-Goals:**

- Reproducing the binary's noise sample sequence (impossible across the
  shared-RNG boundary) or its SDL playback stage (references come from the
  export path).
- Touching the register map, audio RAM image, music sequencer semantics,
  `rtl/clocks.sv`, or any Celeste/NEMO/PPU/CPU source.
- Area work beyond what the adoption itself yields — squeezing resumes in
  `reduce-psg-ice40-area` afterward, against the new exact gates.

## Decisions

### 1. Model first, RTL second

For each formula family: implement the binary's form in a Python model,
render the relevant oracle cases, and require byte-equality against the
stored PICO-8 exports **before** writing RTL. This catches mis-recoveries
(the saw's 0.653 precedent) while they cost minutes. The model then
doubles as the per-stage gate: RTL output must equal the model exactly.

The model is also the pre-RTL sizing instrument: a `probe()` hook at
every load-bearing intermediate feeds `tools/psg_width_report.py`,
which renders the full deterministic matrix (byte-verified while
instrumented), reports observed ranges per site, and derives exhaustive
analytic bounds for the wave layer and amplitude ladder. Candidate
hardware forms - narrower widths, shift-add decompositions, service
sharing - are validated model-side under the same byte gate before any
SystemVerilog exists.

### 2. Phase representation: keep 24 bits, evaluate at the binary's widths

The oscillator keeps its 24-bit phase registers (the state layout and the
transition machinery depend on them), but wave evaluation consumes
`p = phase[23:8]` and the secondary phase becomes a true 17-bit `q0` with
the binary's `& 0x1ffff` wrap and `u16(q0 << mode)` read. The extra 8
fractional increment bits our slide path added beyond the binary's are a
divergence source; the slide adopts the binary's fine-path recurrence and
the fractional extension retires with it. Alternative — narrowing the
whole datapath to 16/17 bits — is deferred to the area change; it is an
optimization, not a correctness need.

### 3. The universal second phase rides the existing second-voice machinery

`s_phase2` already advances for detune/phaser/wavetable voices; the
adoption makes it advance for every voice with the binary's `dq`
derivation, and every wave read becomes the pair
`wave(p) + tz(wave(q)/2)` (in each shape's own scaling). The visit
schedule already has the two read slots; universalizing costs schedule
occupancy, not new datapath.

### 4. One amplitude stage on the product service

`G = tz(3a/2)` is two adds; `tz(x/3072)` is a sign-managed shift through
the established magnitude pattern (`wi_neg` precedent). The 254-scale,
the 1317 constant and the noise gain concept all retire. Per the
measurement law this is service-shaped work (products), not
operand-mux-shaped.

**Sizing correction (tools/psg_width_report.py, 2026-07-27):** the
original "G <= 378 fits the 24x10 m-service" figure assumed the old
8-bit 254-scale amplitude. The adopted ladder reaches a = 2240 (volume
1792, instrument sevenths, then the detune boost tz(5a/4)), so
**G <= 3360 - 13 signed bits** - and the oracle matrix observes that
maximum. z spans +/-24,576 (wavetable; built-ins +/-18,432), giving an
analytic product bound of +/-82.6M = **28 signed bits** (observed
+/-66.1M). The amplitude stage therefore needs a 13x16 product - z can
ride the service's wide port but G does not fit a 10-bit port; task 2.3
widens or stages the service accordingly. Same report, for later
stages: blend accumulator 22 bits, soft-add excess product 29 bits
observed, wavetable lerp accumulator 25 bits, slide fine-path
reciprocal product 57 bits, dq up to 65,024 (17 bits, phaser mode 2).

### 5. Waveforms compute; the wave ROM retires

All eight shapes become integer functions (shifts, thresholds, one ÷3 for
organ via the service or a constant chain). The remaining triangle/organ
EBR is freed — either banked for `reduce-psg-ice40-area` or spent on its
microcode home. The 5.1 approximations are superseded rather than layered.

### 6. Gates flip to exact where determinism allows

Deterministic cases (waves, effects, mixes, transitions, music flow)
become `cmp`-exact against re-captured references. Noise-consuming cases
keep the statistical gates with the RNG boundary cited. The
`reduce-psg-ice40-area` byte-compare baseline re-freezes once, at the
final checkpoint of this change.

## Risks / Trade-offs

- **[Mis-recovery residue]** A formula may still be subtly wrong despite
  the notes' track record. → Decision 1's model-vs-export byte gate per
  family, before RTL.
- **[Schedule growth]** Universal q0 plus per-visit dual reads may extend
  the visit. → The 1,275-clock budget has ~700 clocks of visit headroom
  and the pre-run constant is free; assert per stage.
- **[dq derivation unknowns]** The per-mode `dq` rules (octave scaling,
  `u16(q0 << (state==2))`) must be extracted per waveform from the notes'
  phase-increment section and verified in the model.
- **[Blend interplay]** The 64-sample crossfade must keep matching after
  operand forms change; it is itself on the unverified list.
- **[Two changes in flight]** `reduce-psg-ice40-area` holds its checkpoint
  until this lands; any area regression here must stay within its ceiling
  and be repaid by the freed EBR or explicitly adjudicated.
- **[Render-change blast radius]** Every non-exact case's audio shifts
  once. Accepted deliberately — that is the change — and Celeste/NEMO
  integration re-verifies by ear and headless capture at the end.
