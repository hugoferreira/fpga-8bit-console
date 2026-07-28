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

**Fifth milestone: 51/51 against the re-captured references - task 5.1
closed, no open guesses remain.** The capture (53 cases into
`build/psg_oracle/adopt-exact/`, PICO-8 export run from a
accessibility-granted terminal) re-adjudicated everything:

- All 48 prior cases match the fresh exports byte-for-byte. The new
  capture carries different per-case lead-ins than the old one, so the
  model matching both captures exactly is the export-pipeline
  stability evidence, stronger than file identity.
- filter-reverb-2 and filter-dampen-2 confirmed the generalized
  level-2 forms on the first run: reverb tap four slots back (732
  samples), dampen `tz((x + 3y)/4)`.
- filter-dampen-reverb convicted the guessed order. The chain is
  **comb first, dampen second, and the ring stores the tick's FINAL
  post-dampen samples** - the echo train re-enters the comb already
  smoothed. Hand-verified before the code change: the reference's
  -15/-46/-89 fall out of that structure exactly, while both
  dampen-first and a pre-dampen write-back give -31/-78/-133.
- The flipped gates now define the finish line: against the fresh
  references the current RTL is red on all 51 deterministic cases
  (it renders the superseded approximations; results.json records
  per-case mismatch counts) and clean on the two statistical noise
  cases. Sections 2-4 drive the deterministic set to zero mismatches.

The `area-final` reference/render set stays frozen untouched for
`reduce-psg-ice40-area`'s stage-over-stage byte comparison until task
5.2 re-freezes it at this change's final renders.

Noise stays at the RNG boundary; the model's remaining work is done -
the RTL phases follow, sized by the width report.

**Pre-RTL proven forms (`tools/psg_hw_forms.py`, 14/14 PROVED on
stated domains):** every candidate decomposition below is exhaustively
equal to the binary's form over its true operand domain and can be
transcribed to RTL with no fidelity risk.

- Divisors: `tz(x/3072)` = magnitude `>>10` then a /3 reciprocal
  (`n*174763>>19`, proven to 131,072) - and organ's `tz(2(x-32768)/3)`
  shares that same /3 unit. The skew/tilt `//57344` = `>>13` then /7
  (`n*149797>>20`), shared with the instrument sevenths `tz(a*iv/7)`.
  Tilt-61440 = `>>12` then /15 (`n*279621>>22`). Every divide in the
  deterministic pipeline is shifts plus one of three small reciprocal
  units.
- The soft-add compressor is exactly `excess // 5` (52429 =
  (2^18+1)/5; proven to 131,072): the apparent 29-bit constant product
  is not real hardware - it is the /5 reciprocal itself.
- Slide fine path: reachable `blended` spans 786,432 values in
  [34.3M, 68.6M]; the x0x2F8DF18F product splits into six partials no
  wider than 14x10 into a 56-bit accumulator, exact over the whole
  domain; no low bit of K is droppable (bit-1 truncation already
  breaks); pre-octave dp spans [1,554, 3,108] - 12 bits.
- `G*z`: G = gh*128+gl gives two service passes (24x5, 24x7)
  accumulating the exact 28-bit product - the 24x10 m-service carries
  it in two visits without widening.
- Worst-case bounds (exact interval propagation, comb feedback to its
  fixpoint): voice pre-filter [-26,880, 26,670]; reverb DOUBLES it -
  ring entries reach +/-53,759 so a **16-bit ring RAM is NOT safe**
  (17 bits; comb acc 19); dampen acc 19 bits (level 2); blend acc 23
  bits. The mix bus: all 16 reachable audibility placements (the
  binary's foreground-replaces-music rule - at most one live leaf per
  column pair) stay inside int16 at worst case, minimum headroom 378
  at fg-mask 0101; the hypothetical 8-live tree would clip at
  -34,111. The four-audible invariant is what makes a 16-bit mix bus
  exact, and the RTL must preserve it (or clamp).
- Tables: NOTE_DX is 13x11-bit = 13 constants-EBR words directly (or
  10-bit base + 12 six-bit gaps = 82 bits); vibrato's eight
  multipliers are 128+s with s in [-2, 2].

Second tier (31/31 total after the follow-up sweep):

- The tz-by-2^k idiom for RTL: `tz(x/2^k) == (x + (x<0 ? 2^k-1 : 0))
  >> k` arithmetic shift, proven at k = 1,2,3,6 across every boundary
  multiple of the widest accumulator ranges - the sign-handling form
  every per-sample site (wave secondaries, comb /4, dampen, blend /64)
  transcribes to.
- The crossfade needs ONE multiply, not two: `i*new + (64-i)*old ==
  (old<<6) + i*(new-old)` - a 7x18 product per blend sample.
- Every dq constant is at most two adds and one shift: K=255 is
  `dp - ceil(dp/256)`, 254 `dp - ceil(dp/128)`, 250 `dp -
  ceil(6dp/256)`, 193 `(dp<<7 + dp<<6 + dp)>>8`, 384 `dp + (dp>>1)`,
  508 `2dp - ceil(dp/64)` - exhaustive over the clamped dp range. The
  109/110 serial chain has no successor.
- The amplitude ladder is pure shift-adds: `G = a + (a>>1)`, boost
  `a + (a>>2)`; vibrato is `dx +/- ` a ceil term, all exhaustive.
- Slide improves to a 3-pass schedule: blended's top 3 bits (bh <= 4)
  leave the 24-bit port as a shift-add correction `bh*K`, the low 24
  bits take three 24x10 service passes - halving the 6-limb form.
- The binary's compressor constant is already minimal: even on the
  true reachable excess domain (<= 82,942 = 2x53,759 - 24,576), no
  reciprocal smaller than 52429>>18 is exact.

Third tier - the no-DSP cost model (the target fabric synthesizes all
arithmetic to LUT4s + carry chains + FFs; a "service pass" is serial
shift-add cycles on one shared adder, and a constant multiply is a CSD
signed-adder network of (terms-1) adds; the svc "10-bit port" is a
register/mux width choice, not silicon - two visits or a 2-bit port
widening are both legal, synthesis decides):

- CSD adder counts for every pipeline constant: tilt/skew 24572 =
  **2 adds** (`(x<<14)+(x<<13)-(x<<2)`, proven exhaustively); recip15
  5 adds; recip7 6 adds; compressor 8 adds (rare path - serial is
  fine); recip3 9 adds (alternating bits resist CSD; serial 18
  cycles is its alternative); slide K collapses 19 ones to 10 CSD
  terms (per-tick only).
- Direct single-constant reciprocals exist for /3072, /57344, /61440
  (found and range-proven) but all lose to the staged shift-first
  routes on adder bits (13 vs 9 adds for /3072, on wider operands);
  both routes are recorded, synthesis spikes decide per the
  measurement law.

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
