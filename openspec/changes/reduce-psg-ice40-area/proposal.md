## Why

The fidelity-complete PSG now reaches 7,124 of 7,680 iCE40 HX8K logic cells
and consumes 19 of 32 block RAMs as a standalone target. Local arithmetic and
isolated combinational clean-ups are no longer enough; fitting it alongside
the rest of the console requires spending the large hardware-clock margin on a
substantially smaller state-and-microcode architecture without weakening the
PICO-8 oracle.

## What Changes

- Replace independently decoded voice records with one scheduled state store
  and atomic double-buffered sounding-parameter publication.
- Replace the hard-wired tick/effect control and its named working-register
  muxes with a compact microsequencer operating on stored voice records.
- Serialize phase, filter, interpolation, amplitude, transition and pairwise
  mix arithmetic around a shared accumulator/shift-add service.
- Compute built-in waveform samples from their recovered integer formulae
  instead of retaining a four-EBR sample ROM when this reduces total resources.
- Measure every stage against routed iCE40 area/timing and the complete PICO-8
  export oracle; reject transformations that save neither logic cells nor a
  binding block-RAM resource.
- Treat the derived 28.125 MHz PSG clock and its minimum 1,275-clock sample
  interval as the current hardware deadline. Simulator wall time and Verilator
  lowering remain non-normative.

## Capabilities

### New Capabilities

- `psg-synthesis-area`: Resource, scheduling, publication and verification
  requirements for a time-serialized iCE40 PSG implementation.

### Modified Capabilities

None. The cart-visible audio behavior and register interface remain unchanged.

## Impact

- Primary implementation: `rtl/psg.sv` and, if separation improves inference,
  new PSG-local RTL modules or initialized microcode/table files under `rtl/`.
- Verification: PSG structural tests and PICO-8 export-oracle tooling.
- Synthesis: the existing standalone `make synth-psg` target and its mapped and
  routed reports; no shared Makefile changes are required.
- Coordination: no Celeste- or NEMO-owned source is modified. Their builds and
  audio renders are integration gates only.
