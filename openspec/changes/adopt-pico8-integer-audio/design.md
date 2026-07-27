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
recurrences, and the 64-sample crossfade. Remaining model scope:
detune/phaser/custom voices, multi-voice mixes, transitions, and music
flow - then the reference re-capture.

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

`G = tz(3a/2)` is two adds; `G*z` fits the existing 24x10 m-service
(G <= 378); `tz(x/3072)` is a sign-managed shift through the established
magnitude pattern (`wi_neg` precedent). The 254-scale, the 1317 constant
and the noise gain concept all retire. Per the measurement law this is
service-shaped work (products), not operand-mux-shaped.

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
