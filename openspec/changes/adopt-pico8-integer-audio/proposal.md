# Adopt the PICO-8 binary's integer audio pipeline

## Why

The PICO-8 binary is a proven exact oracle — the two shapes our RTL already
computes exactly (square, pulse) match its exports at correlation 1.000000 /
NRMSE 0.00001 through the whole capture pipeline — yet every other probe is
gated by tolerances that absorb layers of our own approximation: a
mis-recovered saw constant, single-period wave tables that cannot bake the
binary's universal second-phase term, an approximated volume scale, and
effect recurrences that drift from the binary's integer forms. One of those
tolerances (effect-3-drop, at NRMSE 0.073 of its 0.08 gate) has already
vetoed an area optimization. Adopting the binary's own integer pipeline —
now reverse-engineered to instruction level and spot-verified against the
disassembly, including its truncate-toward-zero fingerprints — replaces
statistical gates with byte-exact ones for every deterministic path,
re-founds the verification substrate that `reduce-psg-ice40-area` stands
on, and is expected to be area-neutral-to-negative because the binary's
native forms (truncating shifts, thresholds, one shared divide) are cheaper
than our approximations of them.

## What Changes

- The eight built-in waveforms become the binary's exact integer functions
  of a 16-bit primary phase and a 17-bit secondary phase
  (`wave(p) + tz(wave(q)/2)` in the binary's per-shape scaling), replacing
  the remaining triangle/organ ROM bank and the bounded tilted-saw/saw
  approximations landed by `reduce-psg-ice40-area` task 5.1.
- The common amplitude stage becomes `scale(z) = tz(G*z/3072)` with
  `G = tz(3a/2)` (noise divides by 2048), replacing the 254-scale table
  convention and the 1317-based volume approximation; the composed
  instrument volume becomes the binary's `tz(a*iv/256)`.
- Note-effect recurrences (slide including its fine path, vibrato, drop,
  fades, arpeggio) adopt the binary's per-tick integer forms — drop is
  `tz(DX(P0)*(D-t)/D)`, fades are `tz(A0*t/D)` family — replacing forms
  that are close but not equal.
- Noise adopts the binary's `_codo_random` generator and held/interpolated
  modes **up to the shared-RNG boundary**: the binary's RNG state is shared
  with other engine consumers, so the exact sample sequence is not
  reproducible in principle; noise gates remain statistical and this limit
  is documented as load-bearing.
- Oracle references are re-captured and every deterministic case's gate
  flips from tolerance thresholds to exact comparison; only the
  RNG-bounded cases keep statistical gates.
- **BREAKING (renders):** shipped audio changes for every case that today
  differs from the binary — that is the point. The `reduce-psg-ice40-area`
  byte-compare baseline is re-frozen once, at the end.

## Capabilities

### New Capabilities

_None — this change tightens an existing capability rather than adding one._

### Modified Capabilities

- `audio-engine`: the "Eight PICO-8 Waveforms" requirement gains exactness
  (waveform samples are the binary's integer functions, bit-for-bit, not
  approximations gated by fitted-gain thresholds); the "Note Effects"
  requirement gains the binary's exact per-tick recurrences; a new
  requirement pins the common amplitude stage and its truncate-toward-zero
  semantics; the noise requirement states the shared-RNG exactness boundary
  explicitly.

## Impact

- `rtl/psg.sv`: wave evaluation, amplitude stage, effect microprogram
  arithmetic, noise generator. The register interface, audio RAM image,
  music sequencer, and CPU-visible behavior are unchanged.
- `tools/gen_psg_tables.py`: wave-table emission retires where shapes
  become computed; the constants block (`rtl/psg_const.hex`) persists.
- `tools/psg_oracle_matrix.py` / stored gates: deterministic cases flip to
  exact-compare; references re-captured once.
- `openspec/changes/reduce-psg-ice40-area`: pauses at its 6,199-cell
  checkpoint until this lands, then resumes against exact gates with the
  drop-gate headroom restored. Its constraints bind here: the 15-EBR
  ceiling and the 1,275-clock sample budget (pre-run depth is a free
  constant if the schedule grows).
- Not touched: Celeste/NEMO sources, CPU, PPU, `rtl/clocks.sv`, the
  register map.
