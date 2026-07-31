## Context

The fidelity-complete standalone PSG currently maps to 6,054 LUT4s, about
1,800 flip-flops and 19 `SB_RAM40_4K` blocks. Seed-1 placement reports
7,124/7,680 HX8K logic cells (92%). The immediately preceding RTL maps to
5,830 LUT4s, so the transition/secondary-oscillator corrections added 224
LUT4s and four flops; reverting those corrections would lose measured PICO-8
fidelity without addressing the older fixed cost.

The hardware clock is not a simulator budget. A 112.5 MHz PLL feeds the PSG
through the current divide-by-four clock, giving 28.125 MHz and a minimum of
1,275 hardware clocks between 22,050 Hz sample boundaries. The current
non-preview synthesis walk uses 62 clocks for each of eight slots plus three
post-walk reduction clocks, about 499 clocks total. The unused approximately
776 clocks are the resource this design spends.

The complete PICO-8 export matrix contains 50 bounded cases. It is the
functional oracle. `rtl/psg_tb.sv` covers structural scheduling and the
Celeste simulator run covers integration and non-silent output.

### Accepted baseline

The pre-area checkpoint is RTL fingerprint `9a813a938b98` at repository
commit `8a73b48`. Yosys maps 6,054 LUT4s, 1,359 carry cells, 1,792 flip-flops
and 19 block RAMs. Seed-1 nextpnr placement reports 7,124/7,680 logic cells
and 19/32 block RAMs. Routing was deliberately stopped after placement because
this checkpoint is an area baseline; the preceding completed routed checkpoint
remains the timing reference.

The stored PICO-8 matrix is 50/50 diagnostic-clean and its oracle unit tests
pass. These files predate the storage rewrite and their thresholds are frozen
for every implementation stage in this change.

## Goals / Non-Goals

**Goals:**

- Reduce the standalone target to no more than 5,500 HX8K logic cells and 15
  block RAMs while retaining all current audio behavior.
- Keep worst-case sample work within 1,275 derived PSG clocks and tick
  publication complete before the following sample observes it.
- Replace replicated destination muxes and arithmetic with stored state,
  narrow microcode and one physical write site per shared working register.
- Preserve the complete PICO-8 oracle, register interface and eight-slot
  foreground/music model.

**Non-Goals:**

- Reintroducing a simulator or host-wall-time constraint.
- Returning the PSG to the undivided 112.5 MHz source as a prerequisite for
  this area change.
- Weakening oracle tolerances, dropping filters/instruments/transitions, or
  approximating arithmetic that a current probe observes.
- Modifying Celeste, NEMO, PPU, or CPU sources.
- Moving the audio image into the external memory subsystem in this change;
  the design leaves a clean future port for that separate system change.

## Decisions

### 1. Establish mapped and routed baselines separately

Every stage records the RTL fingerprint, LUT4/flop/carry/BRAM counts from
Yosys and logic-cell/Fmax results from nextpnr. Mapped counts provide a quick,
deterministic experiment loop; a stage is not accepted until a routed seed-1
result confirms the packing result. The final result additionally uses
multiple seeds.

Host runtime is recorded only as test cost. The hardware deadline is derived
from `CLK_HZ` and asserted in clocks, rather than inferred from Verilator
execution.

### 2. Collapse the voice records into one scheduled store

The three current memories contain:

| record | words/slot | eight-slot words |
| --- | ---: | ---: |
| tick/note (`vmem`) | 10 | 80 |
| sounding parameters (`spar_m`) | 4 | 32 |
| oscillator (`sosc_m`) | 14 | 112 |
| **total** | | **224** |

A second 32-word parameter bank makes exactly 256 16-bit words, one
`SB_RAM40_4K`. The synthesis walk has priority during its bounded sample job;
the tick walk pauses for an ordinary 532-clock job. At the 120 Hz boundary
where `tick_en` and `sample_en` coincide, ordering reverses: the tick
microprogram first publishes the complete bank, then the sample walk runs
while pattern-flow work is held. The measured worst combined deadline is 1,133
of the minimum 1,275 clocks. This removes concurrent-owner steering while one
read and one write site lower directly to the EBR's simple dual-port interface.

The per-slot word layout is:

| word | contents |
| --- | --- |
| 0..9 | tick/note record |
| 10..23 | oscillator and preceding-transition state |
| 24..27 | sounding-parameter bank 0 |
| 28..31 | sounding-parameter bank 1 |

The sequencer writes the inactive parameter bank. When the complete walk is
ready, one bank bit publishes all eight slots atomically before the next
sample. This decouples arithmetic duration from audible commit order and
removes the reason earlier serialized volume experiments changed renders.

Small public state (`row`, `sfx_id`, `released`) remains a candidate for
currently unused record bits where synchronous readback permits. The playing
and pending vectors remain flops because they are latency-sensitive, randomly
addressed control.

Rejected: merely concatenate the three arrays while leaving concurrent,
uncoordinated ports. Yosys would replicate or demote the memory and lose both
the EBR and LC benefit.

#### Atomic-store implementation result

The first implementation stage maps the complete 256×16 `state_m` through one
`$__ICE40_RAM4K_` cell and reduces the standalone total from 19 to 17
`SB_RAM40_4K` blocks. At `rtl/psg.sv` fingerprint `851cabd08fc1` and
`rtl/target_psg.sv` fingerprint `6f9b42682a71`, the retained result maps to
6,039 LUT4s, 1,383 carries, 1,722 flip-flops and 17 EBRs. Ten LUTs relative to
the original accepted report are the correction from the target's stale
112.5 MHz `CLK_HZ` constant to the shipping 28.125 MHz clock; on a
like-for-like clock constant the architecture is approximately -25 LUT4s,
+24 carries, -70 flip-flops and -2 EBRs. Seed-1 place-and-route packs to 7,070
logic cells and 17 EBRs, 54 fewer cells than the baseline, and routes at
32.26 MHz while meeting the actual 28.125 MHz clock.

This stage is retained for its binding BRAM reduction, lower placed-cell count
and timing improvement. It is intentionally not credited as the main LC cut:
the tick microengine and shared sample service remain responsible for reaching
the 5,500-cell target.

The reset audit removes reset muxes from 660 streamed/datapath flops:
`SB_DFFESR` falls from 1,108 to 450. Only validity, counters and externally
observable control retain reset. The actual-clock structural test passes with
the 1,133/1,275 combined deadline and a 602-clock tick publication.

Two variants were rejected by mapped/packed evidence:

- Allowing tick memory traffic in sample arithmetic gaps added 47 LUT4s
  relative to the complete sample-owner stall and was unnecessary once
  tick-first ordering provided the required publication phase.
- Writing the effect microprogram's 32 result bits directly into
  `w_eff_inc`/`w_eff_vol` removed staging flops but increased packed cells from
  7,092 to 7,096; the destination-input mux merely moved rather than vanished.

The retained 50-case PICO-8 matrix is diagnostic-clean at 28.125 MHz. The
renderer now resets sample/tick phase after upload, tracks the DUT divider from
reset, and discards the launch-setup strobe. The same logical render is
therefore byte-identical at 28.125 and 112.5 MHz; host runtime is reported only
as non-normative test cost.

### 3. Use a memory-to-accumulator tick microengine

The tick engine becomes a compact micro-PC, flags, an 8-bit data register and
a carry/shift accumulator. It loads voice-record bytes/words, executes
byte-serial pitch, volume, effect and address operations, then stores the
result. Wide values are little-endian word sequences, not separately named
24-bit destination registers.

The decisive inference rule is one physical write site for each accumulator
and state-store port. Operation selection happens before that site. The prior
general-ALU and phase2 experiments assigned many named registers from many FSM
states; iCE40 implemented the resulting register-input muxes and increased
area. This design removes those destinations instead of placing an ALU in
front of them.

The inactive parameter bank provides a fixed commit boundary. Tick evaluation
may take a different number of clocks for different effects without exposing a
partially updated voice set.

#### Staging constraints recorded at the serial-fold checkpoint

- **Clock budget.** The combined worst deadline is 1,159/1,275, so tick
  microcode may grow by at most ~116 clocks under today's tick-first
  coincident ordering. The double-buffered bank already decouples evaluation
  from publication: pre-running the tick walk one sample early (evaluate at
  scnt == 181 into the inactive bank, flip at the boundary) frees the whole
  preceding sample for tick microcode. A CPU write landing inside that
  one-sample window is observed one tick evaluation later than today;
  the oracle's launch strobes sit outside the window, but psg_tb's
  register-timing cases must be re-baselined deliberately, not silently.
- **Bulk-only.** Per 5c, standalone consolidations under ~50 cells are noise.
  The microengine lands as whole families: states, their destination fields
  and their operand selection together. The trigger/instrument load chains
  (T_*/I_TR*, table-shaped, under ~80 cells of decode) fold in as part of
  the engine, not as separate slices. The pinc prefetch registers
  (base_r/prev_r/arp_r, 72 flops) retire only when the effect microprogram
  re-reads pinc at its consumption points; e_pitch/e_prevp/e_arp are
  consumed in disjoint states and time-share one clamp unit once their
  operands come from the microprogram.
- **Microcode storage.** No EBR is free at the 15-block ceiling. The
  microcode ROM shares the constants block that the section-5.1 hybrid-wave
  replacement recovers, together with pinc and nz_gain (one shared EBR
  measured -77 LUT4s) and fstep as recip >> 4 with the n = 1 exception. The
  dependency chain is 5.1 first, then the constants EBR, then the microcode
  home; until then any control table is LUT-ROM and counts against its
  stage.

#### Stage 3.1/3.2 design freeze: the bookkeeping family

The first engine stage migrates the counter/loop family - tcnt, fcnt, sp,
lps, lpe, play_len for both banks (11 registers, 84 bits) - out of the
working-register file into flow-owned record words, with every producer
and consumer. Word addresses replace the note/instrument destination
muxes: the two advance paths become one sequence with a bank bit and a
+6 word-base.

Relayout (tick words; family words are whole so no store ever merges
register and memory fields):

| word | contents | ownership |
| --- | --- | --- |
| 0 | {tcnt, fcnt} | flow-owned |
| 1 | {lpe, lps} | flow-owned (pairs the loop compares in one word) |
| 2 | {2'b0, play_len, sp} | flow-owned |
| 3,4,5 | unchanged identity/filter fields | register-resident |
| 6 | {ins_tcnt, ins_fcnt} | flow-owned |
| 7 | {ins_lpe, ins_lps} | flow-owned |
| 8 | {2'b0, ins_pitch, ins_sp} | flow-owned; V_LD refreshes the ins_pitch read-copy; all writers are in-flow |
| 9 | {2'b0, ins_wt, ins_on, ins_prev_vol, ins_fx, ins_prev_pitch} | register-resident (wt/on relocate here from old word 2) |

Flow-owned words are never unpacked and never stored by V_ST; the engine
reads/modifies/writes them in place through the existing single state-port
read and write sites (new address/data sources, same two always_ff
owners). V_LD shrinks to {3,4,5,8,9,spar}, V_ST to {3,4,5,9,spar}.

Engine (3.1): acc[15:0] and wrd[15:0] word registers, froll/ge_lpe/
end_hit flags, one 9-bit add/compare unit, micro-steps E_A0..E_A6 shared
by both banks (bank 1 skips the play_len arm - its word-8 high byte is
ins_pitch, not a length). The trigger loads assemble words in acc/wrd
(T_LE holds lps, T_NL writes {lpe,lps}, T_NH writes {play_len,sp}, T_LS
writes the mod-32 seed into word 0; I_TR2/3/4 mirror onto words 6-8).
The effect path's family reads become an EFFSEL staging step after the
note/instrument dispatch: {eff_sp, eff_tcnt[4:0], eff_fcnt} (21 bits)
replace the e_sp/e_tcnt/e_fcnt bank muxes; recip addressing, the
vibrato LFO, arp_idx and the xs0 row-fraction operand read the staging.
pat_rows and the T_NL assert read lps from the assembly instead of a
register. Schedule cost ~+5..12 clocks per slot; pre_tick moves 181 to
180 (two intervals) in the same stage.

##### Implementation result

Landed as designed, plus one mechanism the byte-compare demanded: at
pre-run depths beyond one interval, the tick program's unbanked
playing[] clears become visible early. The first run differed from the
prior render in exactly one sample per case - the final note-off,
rendered at the depth-2 pre-run's second interval. Deferred stop masks
restore the exact visibility classes: note-end, length-stop and fade-out
stops apply at the boundary flip (class 1), and the music-flow stops
from W_MUS/ML_STOP - which previously landed behind the walk frozen by
the boundary render - apply one sample later (class 2, at the scnt==1
sample). A trigger clears both masks for its slot; a CPU launch's
ML_STOP keeps stopping immediately (ml_cpu discriminates the entry
path). With the masks in place the complete matrix is 50/50
diagnostic-clean and every WAV byte-identical to the 3.0 render at
depth 2, making the pre-run depth a free constant for section 3.3.

The first 3.3 family followed at once: prev_r had no consumer at all
(a phase-increment-slide leftover), and base_r duplicated the pitch
table's idle read - pinc_addr sits at e_pitch through every K_FX step
and the earliest consumer runs tens of cycles after the port settles,
including after the slide detour. Both registers and two of the three
prefetch states are gone; base_inc is the live port. The arp capture
deliberately keeps its one-cycle issue-to-capture shape: a walk freeze
landing in that window lets pinc_q drift before the capture, a latent
deterministic hazard the reference renders share - fixing it changes
renders and is its own adjudicated stage. 50/50 byte-identical;
seed-1 placed 6,317 (-27), routed 40.98 MHz.

The second 3.3 family made publication direct-to-bank: P_W0..P_W3 write
the four inactive sounding words straight through the engine's store
site from the effect program's own result slots (arp_r, vol_r, the xs 6
product held in m_res) and the identity/filter registers, deleting the
w_eff_inc/w_snd_*/w_eff_vol staging (45 bits) and V_ST's four sounding
stores. A skipped slot publishes by verbatim copy (K_ROT/PC0..PC3, five
cycles) - its cone inputs are unchanged since its last evaluation, so
the copy equals the old register re-publication - and cpz zeroes the
volume byte for any not-playing slot, which covers both this-pass stops
and CPU stops that never ran a publishing pass, with identical cone
bits either way. The one dependency restored deliberately: a continuing
instrument passes no filter-writing state, so V_LD reads the active
filter word to refresh the carried w_ch_* registers. 50/50
byte-identical on the first run; seed-1 placed **6,220 (-97)**, routed
40.50 MHz - the largest single-family engine win, the amortization the
3.1 stage bought.

The third 3.3 family completed the pattern-control migration: the ML
chain launches each channel from its byte as it lands, deleting the
pb[0:2] staging (23 unpackable flip-flops) at unchanged state count.
The four trig_req bits now set over four cycles, which nothing
observes - the walk cannot dispatch mid-chain and $03 reads only the
foreground bits. Measured honestly against the 5c noise floor: placed
**6,214 (-6)** - the per-byte launch decode ate most of the register
saving, exactly the sub-50-cell band the rule warns about - retained
as a verified improvement with flip-flop headroom. The slide/combine
cone dedup was priced at net -15..30 (e_arp depends on arp_p, which
lands mid-sequence and forces extra staging) and skipped as a
standalone per the same rule; it remains an accompaniment candidate
for a future family. 50/50 byte-identical; psg_tb passes, pre-run
completion 1,075/1,275, zero late flips.

Mapped 5,476 LUT4s (-25), 936 carries (-66), 1,512 flip-flops, 15 EBRs;
seed-1 placed **6,344 cells (-25)**, routed 39.64 MHz. psg_tb passes with
the sample deadline unchanged at 558/1,275 and worst pre-run completion
1,114 clocks with zero late flips - the V_LD/V_ST shrink nearly offset
the engine's added cycles, so even the grown pass fits one interval and
depth 2 leaves ~1,400 clocks for section 3.3. The census counts
597 unpackable flip-flops: the LUT-fanout class fell 431 to 334 (the
deleted V_LD/V_ST arms and e_* muxes) while the engine's own
state_q-fed word registers added route-throughs. The net is modest
because the family's gross saving (~150 cells) largely paid the
engine's fixed cost - acc/wrd, the port arbitration, the generalized
replay, the pend masks - exactly once; sections 3.3's effect families
ride the same infrastructure without re-paying it.

#### Pre-run implementation result (task 3.0)

`pre_tick` fires one sample before `tick_en` (scnt == 181) and queues the
walk plus the fade step; the boundary edge itself only flips the staged
bank. A completed tick pass raises `bank_ready` instead of flipping;
`tick_en` performs the flip. Two corners are handled explicitly: a pass
that completes on the boundary edge itself flips immediately (the V_ST
arm is textually after the boundary handler, so its assignment wins), and
a trigger pass in flight at `pre_tick` delays the tick pass past the
boundary, where `flip_pend` makes it publish at its own V_ST completion
rather than holding the tick a whole period. S_IDLE holds new dispatches
while a publication is staged, so a trigger pass cannot rewrite and
immediately publish the staged bank. The old coincident-boundary deferral
(`sample_pending`/`tick_publish`) is deleted; every sample now starts on
its own `sample_en`, and the tick program stopped sharing the boundary
sample's budget.

What this buys, stated precisely: evaluation and publication are now
DECOUPLED, and the evaluation window is a constant choice rather than an
architectural bound. Each interval still contains one sample render
(~558 clocks of walk freeze), so at pre_tick = 181 the tick program's
growth margin is ~116 clocks - the same arithmetic as the old coincident
bound. The difference is that moving the constant earlier (178 gives four
intervals, and so on) scales the window in whole sample intervals under
the identical bank_ready/flip_pend handshake, at the cost of widening the
accepted CPU-write observability window by the same number of samples.
The boundary sample's own deadline also fell from 1,159 to 558 clocks,
so sample-side serialization (4.3 and later) and tick-side microcode
growth no longer compete for one interval.

Gates: mapped 5,501 LUT4s (-7), 1,002 carries, 15 EBRs; seed-1 placed
**6,369 cells (-2)**, routed 40.68 MHz. The complete 50-case matrix has
zero diagnostics and every WAV is byte-identical to the serial-fold
renders - no oracle launch lands inside a pre-run window, and outside CPU
writes the pre-run is render-exact by construction (mutations sit between
the same two renders as before). psg_tb's tick instrumentation now
measures pre_tick-to-bank_ready completion and counts late flips: worst
observed completion 1,159 of the 1,275-clock interval (558 freeze + the
601-clock tick pass), zero late flips, and no register-timing case
required re-baselining.

### 4. Share sample arithmetic through one service

The current RTL contains four separately registered shift/add engines for
effect multiplication, sample-by-volume, transition blending and wavetable
interpolation, plus independent phase/filter/reverb adders and the factored
soft-add product. The sample microprogram serializes these operations through
one signed, width-explicit accumulator service.

The service supports load, add/subtract, arithmetic/logical shift, clamp and
conditional shift/add multiply. Narrow operations retain their current
truncation point. A destination is committed only after the service finishes.

Transition behavior is represented by a compact phase operation rather than
parallel expressions feeding `s_phase`: ordinary hold, twice-old-minus-new,
old-plus-new and twice-new. The operands remain the recovered PICO-8 state;
only their execution is serialized.

The seven pairwise `soft_add` operations retain voice order. Their exact
division by five is iterative through the same service, and the eight leaves
and intermediate nodes occupy scratch words rather than a parallel register
tree.

#### First shared-service increment

Sample-by-volume and transition blending are mutually exclusive in the sample
schedule, so the first retained increment replaces their two accumulators,
adders and counters with one 16×8 shift-add service. The six-bit blend weight
is zero-extended and takes eight iterations; the two extra clocks are idle
schedule space and leave the measured worst-case sample deadline unchanged at
1,133/1,275 clocks.

The initial sample-only result at `rtl/psg.sv` fingerprint `27e3deffcf2d`
maps 6,033 LUT4s, 1,365 carries, 1,694 flip-flops and 17 EBRs. Relative to the
atomic-store checkpoint this removes 6 LUT4s, 18 carries and 28 flops. Seed-1
place-and-route packs to 7,060 logic cells and routes at 33.57 MHz.

Moving the physical write site into a PSG-wide service then lets the same
24×8 engine execute tick/effect, sample-volume and blend products. That
removes the complete sample multiplier rather than merely sharing its two
clients. The mapped result falls to 5,866 LUT4s and 1,650 flip-flops; seed-1
packing falls to 6,895 logic cells and routed Fmax is 33.74 MHz.

Finally, a narrow 10-bit mode evaluates the two signed wavetable interpolation
products. Explicit magnitude/sign handling preserves arithmetic-right-shift
rounding for negative fractional deltas. The retained source fingerprint is
`642a5baee480`; Yosys maps 5,852 LUT4s, 1,346 carries, 1,603 flip-flops and 17
EBRs. Seed-1 place-and-route packs to 6,884 logic cells and routes at 31.42
MHz, meeting 28.125 MHz. The structural deadline remains 1,133/1,275 clocks
and the complete 50-case PICO-8 matrix, including wavetable and compound
instrument probes, is diagnostic-clean.

The general signed add/shift service is not yet complete: filter and mix
operations still retain separate arithmetic. Phase sharing is added in the
handover checkpoint below.

The tick microprogram's final pitch and volume temporaries are also removed:
micro-ops 5 and 6 overwrite the now-dead arpeggio and current-volume registers
and publication consumes those registers directly. At `rtl/psg.sv`
fingerprint `a327138f4e5a`, the result maps to 5,847 LUT4s, 1,339 carries,
1,582 flip-flops and 17 EBRs. Seed-1 packing falls to 6,847 logic cells and
routed Fmax is 32.98 MHz. The complete matrix remains 50/50
diagnostic-clean.

Two more lifetime reductions are retained. The ordinary and instrument note
fetches share `note_lo`, and slide's lower-semitone/fine-pitch value reuses
`arp_r` after the arpeggio source is dead. Together they map to 5,825 LUT4s,
1,345 carries and 1,550 flip-flops; seed-1 place-and-route packs to 6,831
logic cells and routes at 33.05 MHz.

Rejected: widening the global product service to 16 bits to serialize the
seven `soft_add` divide-by-five operations. It was functionally clean in the
structural suite and used 1,197/1,275 clocks, but mapped to 5,915 LUT4s and
packed to 6,956 logic cells. The 16-bit request/result mux and control state
cost more than the four factored constant-add stages it removed, despite a
42.10 MHz routed Fmax.

A dedicated three-bit restoring divider was also rejected. It avoided the
global operand mux and was exact, passing the structural suite at
1,205/1,275 clocks, but its quotient/capture state increased the flop count by
71. The result mapped to 5,845 LUT4s and 1,276 carries yet packed to 6,915
logic cells, 31 worse than the retained factored network.

Changing the public `playing`, `sfx_id`, `row` and `released` arrays from
unpacked to packed SystemVerilog arrays was rejected at mapped synthesis: it
increased LUT4s from 5,852 to 5,997 before routing. The representation exposed
wider variable-index muxes to Yosys rather than reducing them.

Removing the final mix register, broadening the reset audit, reusing waveform
table temporaries and reusing pattern bytes across note/volume staging were
also rejected individually: each removed flops or source-level state but
increased mapped LUTs or placed cells. These results reinforce that an iCE40
register is often free when its LUT is already occupied; a lifetime change is
accepted only from the routed result.

### 5. Compute built-in waveforms after the shared service exists

PICO-8 computes its built-in waveforms from phase. The four-EBR 2,048-byte
sample ROM is therefore replaced only after the shared arithmetic service can
evaluate the recovered integer triangle, tilted saw, saw, square, pulse, organ
and phaser formulae without a second datapath. Noise and custom-wavetable
behavior remain separate.

The first retained hybrid stored triangle, tilted saw, saw and organ in a
compact 1,024-byte synchronous ROM. Square and pulse became their exact
phase-threshold functions (`0x80` and `0xb0`); noise and phaser continued
through their existing synthesis paths. That reduced the waveform store from
four EBRs to two and brought the standalone total from 17 to the 15-EBR
ceiling. The isolated change cost 46 seed-1 placed cells (6,831 to 6,877), so
it was retained specifically for the binding BRAM resource and not credited as
an LC reduction. The complete 50-case matrix, including both threshold
discontinuities, remained diagnostic-clean.

#### Task 5.1 waveform-formula spike

The second hybrid computes tilted saw and saw directly, leaving the
fidelity-sensitive triangle and organ as the two 256-byte banks in one EBR.
The 4.1 measurement law rules out adding these narrow chains as new phase-ALU
operand arms: the direct shifts are smaller than that routing. Tilted saw uses
the nearest one-add forms of its recovered `127/112` and `-127/16` slopes
(maximum table error 3 sample units); saw uses a two-chain 5/8 ramp in place of
the recovered 0.653 coefficient (maximum error 4). The generator asserts those
bounds over all 256 phases. The complete unchanged 50-case oracle is
diagnostic-clean: the dedicated tilted-saw probe reports fitted gain 1.0134,
correlation 0.999641 and NRMSE 0.02680; saw reports 1.0661, 0.999937 and
0.01127 respectively.

This is the first stage in the change that alters shipped audio, and it
does so under section 7's explicit exception: a measured trade required
to meet the binding BRAM resource, adjudicated by the frozen per-case
probe gates rather than byte identity, with the recovered block being
the prerequisite for the constants-ROM move that repays it. Exactly
three renders diverge from the pre-5.1 set - wave-1-tilted-saw,
wave-2-saw and mix-four - and the other 47 remain byte-identical. The
byte-compare baseline is therefore RE-FROZEN at this stage's renders
(`build/psg_oracle/area-wave-formulae/rtl`); stage-over-stage byte
comparison from here on uses that set, not any earlier one.

At fingerprints `rtl/psg.sv d221d449ca2c`,
`rtl/psg_waves_compact.hex d85b61ab614d` and
`tools/gen_psg_tables.py 92c4a907ab6f`, Yosys maps 5,427 LUT4s, 939 carries,
1,436 flip-flops and 14 EBRs. Seed-1 place-and-route packs to **6,258 logic
cells** and routes at **40.72 MHz**. `psg_tb` passes with the sample deadline
unchanged at 558/1,275 clocks and tick pre-run at 1,075/1,275 with zero late
flips. Relative to the committed 6,214/15-EBR checkpoint the isolated resource
trade is +44 cells and -1 EBR. It is retained because the recovered block is
the prerequisite for the already measured constants-ROM move (-77 cells),
making that immediate two-stage chain net-positive before microcode storage is
counted.

Three shapes were rejected on the same seed. Exact triangle plus exact saw
reproduced every old table byte but placed at 6,407 (+193). Exact triangle by
itself placed at 6,296 (+82) without freeing an EBR. Exact triangle plus the
cheap saw placed at 6,339 (+125). The cheapest folded-triangle/cheap-saw pair
placed at 6,268 (+54), but failed the unchanged `effect-3-drop` NRMSE gate
(0.0869 against 0.08); that failure is why triangle remains in ROM. These
measurements close the per-waveform choice: formulas are retained only for
tilted saw and saw.

The constants block landed in the freed EBR immediately after: words
0..63 hold the pitch increment's effective 13 bits (every pinc is
dp << 8, dp max 0x1CE0), reconstructed as {3'b0, word, 8'b0} on the
same synchronous port, and words 64..255 are reserved for microcode
and scheduled tables (section 6 finally has a home). The dead
nz_gain/nz_mul/nz_scaled cone - orphaned when the fidelity rework made
built-in noise the one-pole process - left the source with it. Seed-1
places **6,199 cells at the 15-EBR ceiling**, routed 41.18 MHz; the
oracle is 50/50 with every render byte-identical to the re-frozen
area-wave-formulae baseline, and psg_tb rebinds its three pitch-table
checks to the constants words. The two-stage chain closes net -15
against the 6,214 checkpoint with the microcode store banked.

The final combined checkpoint must still improve LC as well as satisfying the
BRAM ceiling.

### 5a. Serialize transition and secondary phase arithmetic

The fidelity transition renderer was isolated as the largest remaining area
family: with reverb disabled, the full renderer maps 1,257 LUT4s, 242 carries
and about 220 flops above `REALTIME_PREVIEW`. This is a diagnostic ablation,
not permission to ship the preview path.

The retained phase service selects one 24-bit add/subtract result before one
physical datapath. Repeated slide, compound transition and DROP corrections
use two scheduled clocks; ordinary, wavetable and old-continuation advances
use one. Phaser's `x-(x>>7)-(x>>10)-(x>>12)` ratio uses four clocks, and
DETUNE-1 computes `(dp-ceil(dp/256))<<8` over two. All waveform reads capture
the pre-advance phase before these idle-clock operations begin, so render
ordering is unchanged.

At the handover checkpoint, `rtl/psg.sv` fingerprint
`22b35726cf1c5a18a4e20fc3bd8f24c3b63c9cc3` maps to 5,659 LUT4s, 1,213
carries, 1,557 flip-flops and 15 EBRs. Seed-1 place-and-route packs to 6,662
logic cells and routes at 33.75 MHz, passing the 28.125 MHz constraint. The
structural schedule remains 1,133/1,275 clocks with tick publication at 602
clocks. The exact checkpoint is 50/50 diagnostic-clean in
`build/psg_oracle/area-shared-phase-v2/results.json`.

This is a handover checkpoint, not completion of the change: it is still 1,162
logic cells above the 5,500-cell goal. The next high-leverage stage is the
memory-to-accumulator tick microengine in tasks 3.1-3.4. After that, move
DAMPEN/noise/brown and reverb arithmetic onto the already-proven scheduled
add/sub contract. A partially started filter-serialization experiment was
removed before handover; no unmeasured filter schedule remains in the source.

### 5b. Serial soft_add fold, single-chain fusions, and the packing metric

Placed logic cells and mapped LUT4s disagree by about a thousand cells, and
the difference is measurable, not noise: an iCE40 flip-flop can share a cell
only with the LUT that drives its D input, and only when that LUT has no other
fanout. A census of the handover netlist (`tools`-candidate script, currently
`ff_census.py` in the session scratchpad) counted 671 of 1,557 flip-flops that
fail this test and therefore each occupy a whole logic cell behind a
feed-through LUT. The l1/l2a/l2b/sa_hold/dry16 mix-tree registers alone were
165 such cells. **Consequence: a stage that trades flip-flops for mapped LUTs
can be a large placed win while mapped counts call it a regression - the two
earlier soft_add serialization rejections were partly artifacts of this.**
Stages are now judged on seed-1 placed cells, with the census as the fast
in-between proxy.

Four stages landed on this basis, every one byte-identical across all 50
oracle candidate WAVs against the pre-stage render:

1. **Serial soft_add fold on the phase ALU.** The parallel node (23-bit sum,
   two signed compares, excess mux, and the 20/32/34-bit shift-add network
   for (excess * 52429) >> 18) and the l1[]/l2a/l2b/sa_hold register file are
   replaced by a three-entry stack and a ten-cycle fold microprogram on the
   shared 24-bit phase ALU, idle from PWORK+10 onward. Division by five is a
   truncating series plus one bounded fixup, verified exhaustively equal to
   the binary's multiply form for every excess below 80k. Mid-walk folds run
   inside the following visit's record-load phases; the slot-7 chain runs
   past the walk with walk_frozen extended by fold_busy. The ALU gained a
   carry-in and computes subtract as a + ~b + 1, so add and subtract share
   one physical chain.
2. **Offset-stored fractional divider.** divd holds the classical divacc
   minus the wrap threshold; the sample decision is its sign bit. One adder
   with a two-constant operand mux replaces a 27-bit comparator plus separate
   add and subtract. Identical clock-for-clock sample_en/tick_en sequence.
3. **Single-chain arithmetic fusions.** Vibrato's floor/ceil rounding and
   sign selection, DROP's subtract, slide's +/-, fade's fx-1 volume arm and
   the mixer's nm_signed negate each collapsed to one carry chain via
   two's-complement identities (x - y as x + ~y + 1 with the round-up riding
   the carry-in).
4. **Tick-side multipliers.** The row*speed seed keeps only its observable
   residue - arp_idx tops out at tcnt bit 4 and the vibrato LFO at bit 3, and
   the per-tick increment preserves residues mod 32 - so the 8x8 array is a
   5x5 corner. The pattern-length product w_sp*pat_rows launches
   fire-and-forget on the m service at T_NL and is captured when it lands;
   K_FX's existing m_busy stall absorbs the overlap with no new wait states.
   One trap recorded: m_res holds the product IN PLACE (bit k is product bit
   k); the volume steps' [15:8] slice is a semantic Q8 scale, not a placement
   offset. The first capture read [20:8], which shortened every music
   pattern; the oracle matrix flagged 44 cases and the byte-compare against
   the prior render caught it immediately. The WAV byte-compare is the
   cheapest exact gate this change has and should be run per stage.

At `rtl/psg.sv` fingerprint `232353e9d469`: Yosys maps 5,508 LUT4s, 1,001
carries, 1,526 flip-flops and 15 EBRs; the census counts 563 unpackable
flip-flops (from 671). Seed-1 place-and-route packs to **6,371 logic cells**
(from 6,662 at handover, -291) and routes at 41.94 MHz (from 33.75), passing
the 28.125 MHz constraint. The structural testbench passes with a worst
combined deadline of 1,159/1,275 clocks (1,133 before the serial fold), and
the fold-collision and product-launch simulation checks stayed silent for
the complete run. The remaining gap to 5,500 (871 cells) is tracked in
tasks; the tick microengine (section 3)
remains the stage expected to close most of it, and it should be planned
against the census as much as against mapped counts - pb, note_lo, base_r,
last_addr, fade_step and the public sfx_id/row arrays are ~230 of the
remaining unpackable flip-flops.

### 5c. Re-priced families and two rejected micro-consolidations

The REALTIME_PREVIEW ablation re-run against the `232353e9d469` build (both
variants with REVERB=0) prices what the serial-fold stages left behind: the
transition/fidelity renderer still maps 882 LUT4s, 49 carries and about 220
flip-flops above the preview path, and reverb itself is 107/75/87. The
transition family remains the largest identified block, ahead of the entire
tick side.

Two byte-identical micro-consolidations inside that family were then rejected
at seed-1 placed cells, each attributed in isolation against the same HEAD:

- Blend update as one 17-bit chain (xor-and-carry-in replacing the +/- mux):
  -16 carries but +32 LUT4s, placed **+31 cells**.
- wt_pf/wt_qf retirement (wavetable phase advances deferred to PWORK+16/+17
  so both interpolation products read the phase slices directly): the
  predicted -20 flip-flops appeared, but +99 LUT4s, placed **+70 cells**.
  Routed Fmax rose 41.94 to 42.88 MHz, consistent with abc9 spending area to
  re-buffer the lengthened cones under the timing constraint.

The lesson generalizes the packing note in 5b: a register retirement pays
only when the arithmetic or decode it feeds leaves with it, as in the
serial-fold stage (132 flops, the divide network and the compare tree
together). An isolated retirement that lengthens a combinational cone hands
the cells straight back. **Consolidations below roughly 50 cells sit inside
abc9's restructuring noise for this design and are not worth their
verification cost; the remaining 871 must come from bulk stages.** The
transition family's bulk candidate is a two-pass old-voice render: store the
main oscillator words early in the visit, reload the old-continuation
parameters into the same working registers, and run the old voice through
the identical wave-read/product path - retiring s_old_phase/inc/vol/wave,
old_smp and the duplicated schedule slots (~60-80 unpackable flops plus
their muxes). The visit has the idle span (18..51) and the store port is
free there; the byte-compare is the gate that makes the choreography safe
to attempt.

#### The map after section 3: where the remaining 714 cells are

With tasks 3.1-3.3 closed at 6,214, the census and ablations re-price
what remains, and two candidates fall away honestly:

- **The section-2 public-array migration is dead under the current
  record budget.** sfx_id+row need 11 bits; the flow-owned words hold
  10 spare even counting tcnt's three dead high bits, no single word
  can host a whole field, and the record is at 32/32 words. The CPU
  mirror would eat half the win regardless.
- **Task 4.7 as a register retirement is mispriced**: the s_old_*
  family packs far better than the handover netlist suggested (it no
  longer appears among the top route-through families). A two-pass
  render harvests ~40-70 cells at the highest choreography risk on the
  board - not worth standalone.

What remains, by size: **the fidelity/transition family still maps
~900 LUT4 above REALTIME_PREVIEW** (the dual-voice schedule muxes, the
three wide inequality compares, the phase_op cone and the blend
datapath - logic, not registers), and the only credible attack is the
open task 4.1: the sample-side counterpart of what section 3 did to
the tick side - one signed accumulator service with one result write
site, migrated family by family under the same gates. Second, the
section-5.1 chain: computing two ROM waves frees the EBRs that home
the constants ROM (pinc+nz_gain, -77 measured) and a microcode store,
which in turn enables compressing what remains of the sst decode.
Third, scraps above the noise floor: fade_step via recip>>4 (needs the
port-borrow guard), and the transition compares folded into whatever
4.1 family touches them. Summed optimistically these reach ~600 of the
714; the goal therefore likely needs 4.1 to over-deliver the way 3.3b
did, and the fallback trade to name explicitly is REVERB (~150 cells,
currently a protected feature).

#### Task 4.1 design freeze: the sample-side service is the three
#### existing units, plus lifetime discipline

The sample side already owns one 24-bit add/subtract ALU (with the
fold's serial sequencing on top of it) and one 24x10 product service.
4.1 is therefore not a new datapath: it is the rule that no sample-side
operation may keep a dedicated chain or a dedicated lifetime register
when a shared unit is idle in its window and a shared temporary is dead
there. Families, in landing order:

**Family 1 was implemented in both shapes and rejected on placed
cells, and the two rejections refine the law this task rests on.**
The full service shape - blend chains as ALU operand arms at
+23/+24/+33, mx_new/mx_old retired into fx_r/ft2 - measured
**+35** (the three 24-bit operand-mux arms, especially the sign-swap's
stacked muxes, outweigh 61 deleted carries and 33 deleted flops). The
salvage shape - registers borrowed, dedicated chains kept - measured
**+132**: sharing fx_r/ft2 across the fold and blend domains entangles
their fanout cones, and abc9 duplicates what it previously optimized
as separate islands. Both reverted; the tree is byte-identical to the
6,214 checkpoint.

The refined law: **shared routing pays only through address-selected
storage.** The section-3 wins borrowed a MEMORY - BRAM ports have no
per-bit input muxes, so new users cost address arms, not datapath. A
borrowed register costs its D-mux and its fanout entanglement, and a
shared ALU costs operand-mux arms wider than the chains they delete.
With three blend attempts at +31/+35/+132, the transition family is
measured DENSE: its remaining ~900 LUT4 is schedule decode, the
wavetable-interpolation feature, and arithmetic already at its
cheapest form. Task 4.1's credible remainder is therefore not the
transition family: it is the section-5.1 chain, which is BRAM-shaped
(compute waves, free EBRs, home the constants and microcode) and
consistent with the law - plus the explicit REVERB decision if the
final gap demands it.

### 6. Keep tables scheduled, not replicated

Pitch, noise gain, filter decode, fade-step and microcode constants are
accessed at different micro-operations. They may share an initialized control
ROM or be computed serially. No new table gets its own EBR unless another
accepted stage has recovered at least that block and the combined LC/BRAM
result improves.

### 7. Fidelity and resource gates are both mandatory

For each accepted stage:

1. PSG oracle unit tests pass.
2. The complete 50-case PICO-8 matrix is diagnostic-clean under its committed
   per-case gates.
3. `rtl/psg_tb.sv` passes, including deadline assertions.
4. Celeste builds and runs headlessly with active, non-constant audio.
5. Mapped and routed iCE40 measurements improve the selected binding resource.

An experiment that improves Fmax but increases LC may be retained only as a
documented alternative, not as the area implementation. The one exception is
an explicitly measured trade required to meet the binding 15-EBR ceiling; a
later combined checkpoint must recover its LC overhead.

### 8. Post-fidelity redundant-work pass

The completed wave-6 correction introduced two simultaneous variable
products: the live noise walk and the copied old continuation both computed
`(8*dp + 1120) * random >> 8` at sample phase W0. Their results have different
deadlines. The live result feeds the main-wave pipeline after W0, while the old
continuation is not issued until W2. The retained schedule therefore computes
the live product at W0 and the old product at W1 through one multiplier cone.
A nine-bit register preserves the old walk's pre-LFSR-advance draw, and W0
stages its base plus shared kick in the existing `s_old_phase` accumulator, so
serializing the step changes neither draw order nor arithmetic truncation.

The same pass removes sequencer bits synthesis could not infer dead across
registered boundaries: `wrd` carries only its six-bit length and eight-bit
speed, effect staging carries `tcnt[4:1]` because every consumer discards bit
zero, and the pitch-table port exposes only the 21-bit increment it represents.

At RTL fingerprint `2c7196d957fd`, Yosys maps 7,043 LUT4s, 1,656 carries,
1,619 flip-flops and 22 EBRs. nextpnr's placement attempt falls from 8,327 to
8,106 logic cells, a 221-cell reduction well outside the mapping-noise band,
but still cannot place on the 7,680-cell HX8K. The frozen matrix remains 59/59
byte-identical, the PICO-8 noise sweep passes, and the structural schedule
remains 906/1,275 sample clocks with tick pre-run at 5,022/7,654 clocks.
The provenance-bound Celeste music-30 comparison also passes, with whole-track
band deltas of -0.09/+0.16/+0.07/+0.14 dB and -0.04 dB in quiet 4-8 kHz
windows.

### 9. Consolidate the sequencer's fade table

The 32x13 `fstep_rom` duplicated storage already available in the constants
EBR. Its exact values are `8191` for index zero and `floor(4096/n)` for
indices 1..31, now generated into words 112..143 of `psg_const.hex`. A CPU
`$22` write borrows the synchronous constants port for one cycle; a replay bit
holds the sequencer for the borrow and following reissue cycles, and the
existing 13-bit `fstep_q` preserves the returned fade word until `$20`
consumes it. An immediately following `$20` may consume `crom_q` directly
during the replay cycle, preserving the original adjacent-write contract.

At RTL fingerprint `27f53a125e75`, the dedicated EBR retires: standalone
synthesis moves from 22 to 21 blocks. The control and preserved output cost
29 LUT4s and 14 flops structurally, with mapped totals of 7,072 LUT4s, 1,656
carries and 1,633 flops. Placement moves from 8,106 to 8,153 cells (+47).
This is retained under section 7's binding-BRAM exception: it is one concrete
step toward the 15-block ceiling and eliminates duplicated table storage, but
the later combined checkpoint must recover its LC cost. `psg_tb` passes with
the sample/tick deadlines unchanged, the PICO-8 noise gate passes, and the
frozen render matrix remains 59/59 byte-identical.

Two exact arithmetic shapes were rejected before this retention. Replacing the
noise kick threshold `g < floor(x/3)` with the exhaustively equivalent
`3g+3 <= x` removed 16 carries but added 57 LUT4s and 22 placed cells.
Computing vibrato directly in the 13-bit published quotient domain removed
nine carries but added 23 LUT4s and 17 placed cells. Both confirm that the
iCE40 mapper absorbs selection into the existing arithmetic more cheaply than
an explicit scaled comparator or rounding mux.

The remaining `eff_rem` width candidate behaves the same way: narrowing its
subtractor from 12 to 8 bits adds five LUT4s, three carries and eight placed
cells, so it is reverted. The retained table merge also passes the
provenance-bound Celeste music-30 comparison with unchanged band deltas
(-0.09/+0.16/+0.07/+0.14 dB whole-track, -0.04 dB quiet 4-8 kHz).

### 10. Encode the walker's sparse control word

The sample control store used 22 one-hot action bits even though the generator
guarantees exactly zero or one action per cycle. Encoding those actions as a
five-bit opcode, followed by the existing four-bit multiplier selector and six
independent issue/context bits, shrinks each word from 32 to 16 bits. The
128-word store therefore maps to one `SB_RAM40_4K` instead of two; the opcode
case restores the action decode at the registered ROM output without changing
the schedule or adding a cycle.

At RTL fingerprint `7de2f07ad0dc`, standalone synthesis moves from 21 to 20
EBRs. The explicit decode trade maps 7,122 LUT4s, 1,655 carries and 1,633
flops, versus 7,072/1,656/1,633 before it; nextpnr's placement attempt moves
from 8,153 to 8,198 cells (+45). This is retained under the same binding-BRAM
exception as section 9: it removes a whole redundant control-store block and
continues toward the 15-EBR ceiling, while a later combined checkpoint remains
responsible for recovering the logic overhead.

The frozen render matrix remains 59/59 byte-identical. `psg_tb` passes at the
unchanged 906/1,275 sample clocks and 5,022/7,654 tick pre-run clocks with zero
late flips; the PICO-8 noise gate and its unit tests pass. The provenance-bound
Celeste music-30 comparison is also unchanged at
-0.09/+0.16/+0.07/+0.14 dB whole-track and -0.04 dB in quiet 4-8 kHz windows.

### 11. Share the constants and walker-control port

The encoded control store's reachable range is only pph 0..108, or 109 words.
It fits exactly in constants words 144..252, which were unused after pitch,
slide and fade data occupied words 0..143. The two clients are mutually
exclusive: `prun` freezes the sequencer for the complete sample walk, so it
selects the control address onto the constants ROM's single synchronous port.
When `prun` falls, the state store's existing one-cycle replay hold re-primes
the sequencer constant address before its FSM can advance. The separate
`psg_ctrl.hex` image and its physical EBR therefore retire.

At RTL fingerprint `9f327071ab8f`, the standalone total moves from 20 to 19
EBRs. The shared-address/output routing maps 7,147 LUT4s, 1,662 carries and
1,633 flops; nextpnr's placement attempt moves from 8,198 to 8,237 cells
(+39). Relative to the pre-control-consolidation section-9 checkpoint, sections
10 and 11 remove two EBRs for +84 placed cells. Both stages remain explicit
binding-BRAM trades, and the combined LC overhead still has to be recovered.

The port handoff is render-exact: the frozen matrix is 59/59 byte-identical,
the PICO-8 noise and analysis-unit gates pass, and `psg_tb` remains at
906/1,275 sample clocks and 5,022/7,654 tick pre-run clocks with zero late
flips. Celeste music 30 retains the same -0.09/+0.16/+0.07/+0.14 dB
whole-track band deltas and -0.04 dB in quiet 4-8 kHz windows.

### 12. Retire post-consume walker lifetimes

Three schedule-proven lifetimes collapse without changing an operation or its
clock:

1. The shared constants ROM exports its registered word directly. Only the
   three wave-issue bits and the old-dq context can affect state outside the
   action case, so those four are qualified by `prun` at their consumers
   instead of zeroing all 16 output bits.
2. The old primary and secondary samples were captured in two 18-bit registers
   only to be added once. W4 now replaces the dead built-in `smp_b` after the
   new G-product launch, and W5 accumulates the old secondary into it. The
   wavetable path keeps `smp_b` through its lerp and never uses the old-sample
   accumulator, so both former old-only registers retire.
3. Wavetable interpolation's sign bit uses `mxs_new`: it is dead on that path
   until W27, which overwrites it with the completed sample's sign before the
   G-product consume. The dedicated `wi_neg` lifetime retires.

At RTL fingerprint `10dd65abd3c7`, Yosys maps 7,142 LUT4s, 1,658 carries,
1,596 flops and 19 EBRs. Relative to section 11 this is -5 LUT4s, -4 carries
and -37 flops; nextpnr's placement attempt falls from 8,237 to 8,189 cells
(-48). The result remains above the HX8K capacity, but it recovers more than
half of sections 10/11's 84-cell BRAM-trade overhead without giving back either
recovered block.

One broader lifetime reuse was measured and rejected. Replacing the dedicated
17-bit `gz_s1_r` with dead `smp_a` storage removed 17 flops but entangled the
sample register with the reciprocal and noise-bypass fanout: +33 LUT4s,
+4 carries and +24 placed cells. It was reverted before verification.

The retained checkpoint passes the noise-fidelity and analysis-unit gates,
`psg_tb` at the unchanged 906/1,275 sample and 5,022/7,654 tick clocks with
zero late flips, and the frozen matrix at 59/59 byte-identical. The
provenance-bound Celeste music-30 comparison remains aligned at zero samples,
with whole-track band deltas -0.09/+0.16/+0.07/+0.14 dB and -0.04 dB in quiet
4-8 kHz windows.

### 13. Reuse the fold destination during compression

The serial `soft_add` fold kept an 18-bit `ft2` register solely for divide-by-
five micro-steps 4..9 even though the selected destination stack word is dead
after the threshold compares and receives the completed fold at step 9 or 10.
Compression now carries its divide series in that stack word. The write is
qualified by the captured overflow/underflow flags: an in-range fold must
retain its plain sum, and the first unqualified experiment was correctly
rejected by the noise-fidelity gate before synthesis.

At combined RTL fingerprint `67b0b3f73e3c`, Yosys maps 7,138 LUT4s, 1,658
carries, 1,578 flip-flops and 19 EBRs. Relative to section 12 this retires all
18 `ft2` flops and four LUT4s; nextpnr's placement attempt falls from 8,189 to
8,164 cells (-25). The schedule is unchanged at 906/1,275 sample clocks and
5,022/7,654 tick clocks with zero late flips.

The corrected checkpoint passes the noise-fidelity and analysis-unit gates,
`psg_tb`, and the frozen matrix at 59/59 byte-identical. The provenance-bound
Celeste music-30 render remains aligned at zero samples, with whole-track band
deltas -0.09/+0.16/+0.07/+0.14 dB and -0.04 dB in quiet 4-8 kHz windows.

### 14. Reuse the dead fold operand for the compression selector

After fold micro-step 7 has formed the compressed magnitude, the 25-bit
`fx_r` operand is dead. Micro-step 8 now stores the four-bit divide-by-five
remainder in `fx_r[3:0]`, and step 9 reads that slice for the round-to-nearest
comparison. The dedicated four-bit `fr_r` register and its publication cone
retire without changing the schedule or arithmetic.

At combined RTL fingerprint `0ea9c400b998`, Yosys maps 7,116 LUT4s, 1,656
carries, 1,574 flip-flops and 19 EBRs. Relative to section 13 this is -22
LUT4s, -2 carries and -4 flip-flops; nextpnr's placement attempt falls from
8,164 to 8,138 cells (-26). Relative to section 12, the two fold lifetime
changes together remove 26 LUT4s, two carries, 22 flip-flops and 51 placed
cells.

The retained arithmetic is render-exact against section 12: `make test-psg`
passes at 906/1,275 sample and 5,022/7,654 tick clocks with zero late flips,
and the frozen matrix is 59/59 byte-identical. The new final Celeste gate
covers entry points 0, 10, 20, 30 and 40. Entries 10, 20, 30 and 40 pass;
entry 0 exposes a pre-existing post-pattern-3 spectral mismatch. That known
PICO-8 divergence is recorded for the later fidelity pass; render-exact
regression against the pre-optimization checkpoint remains the commit gate.

### 15. Fold multiply launch selection into the action opcode

The control word encoded its phase identity twice: once as the five-bit
capture/action opcode and again as a four-bit multiply selector. Ten of the
eleven product launches already occur on a capture phase. The multiply request
mux now keys directly on that action opcode, and the blend-only launch receives
`CAP_W75`; control bits 8:5 become spare. A denser encoding that overloaded the
opcode high bit as a launch flag was measured and rejected because its extra
decode mapped larger.

At combined RTL fingerprint `a106714c2ab0`, Yosys maps 7,099 LUT4s, 1,658
carries, 1,574 flip-flops and 19 EBRs. Relative to section 14 this is -17
LUT4s, +2 carries and no flip-flop or EBR change; nextpnr's placement attempt
falls from 8,138 to 8,127 cells (-11). The placed delta is small, but the
structural result removes a net fifteen logic cells and a redundant control
field.

`make test-psg` remains at 906/1,275 sample and 5,022/7,654 tick clocks with
zero late flips, and the frozen matrix remains 59/59 byte-identical. The
schedule visualizer now derives product launches from the live request mux
instead of the retired selector. It classifies all 109 hardware phases as
scheduled work or a proven multiplier-latency shadow: 46 phases are busy on
every path, 15 more on some runtime profiles, and zero are unexplained by the
model. The apparent blank columns are therefore mostly serialized multiplier
latency, not free cycles.

### 16. Stop multiplying leading zeroes in the reciprocal limb

The visualizer also proves that the three constant-171 products fit the
existing eight-iteration mode. That arithmetic change is exact across all
three multiplier result ports and is retained: it frees four multiplier
iterations for each non-wavetable voice visit and two for each wavetable
visit. A mode change alone only makes the product ready early; fixed request
and consume phases still elapse, so current walker clocks do not fall. The
combined RTL fingerprint is `c06087a366b8`; Yosys remains at 7,099 LUT4s,
1,658 carries, 1,574 flip-flops and 19 EBRs, while placement changes from
8,127 to 8,151 cells (+24). This is an accepted placement trade for service
capacity available to later work or schedule retiming. The report presents
shorter iteration counts only as a retiming upper bound, not as clocks already
recovered. It now attributes the newly visible pph 92 gap explicitly: the
`CAP_W63` product is complete and held there for the fixed pph 93 consume, so
the phase is neither unexplained nor immediately available for another
multiply. In the retained schedule 46 phases perform work, 42 are
multiply-busy on every profile, 18 are busy conditionally, three hold
pipeline/completed-product state, and zero are unexplained.

### 17. Derive the reciprocal sibling instead of multiplying it

The `/3` reconstruction launched both `341*x` and `171*x` for the same
17-bit limb. They are not independent products:

```
171*x = (341*x + x) / 2
```

The numerator on the right is always even, so this identity is exact before
the existing truncation point. The walker now retains only `341*x`,
reconstructs `171*x` from that result and the captured limb, and removes all
three `171*x` launches plus the 25-bit `g_part` register. The cycle model
checks all 131,072 possible limb values, not a sample set.

Before retiming, fingerprint `2c95ddbe92d6` mapped 7,112 LUT4s, 1,686 carries,
1,549 flip-flops and 19 EBRs; nextpnr attempted 8,126 placed cells. Relative
to section 16 that is +13 LUT4s, +28 carries, -25 flip-flops and -25 placed
cells. The arithmetic gate, `make test-psg`, and the frozen 59-case render
matrix all pass byte-exactly.

### 18. Spend the recovered service capacity on shorter visits

Removing the sibling products makes the new- and old-voice chains independent.
The control schedule now consumes each product on the first readable phase,
launches the old voice in the wavetable path's mutually exclusive phase, and
uses mode 3 as an exact nine-iteration service for the remaining constant
`341` products. The exhaustive multiplier model proves mode 3 equivalent to
the old ten-iteration mode across every relevant `A` value and all three
result ports.

The hardware visit falls from 109 to 85 phases, recovering 24 clocks per slot
or 192 clocks per sample. `psg_tb` improves from 906 to 714 of 1,275 sample
clocks and from 5,022 to 3,555 of 7,654 tick-preparation clocks, with zero late
flips. The generated visualization finds zero request/consume slack, a
32-clock true multiply-data depth versus 55 clocks on the one shared service,
and no unexplained hardware phases.

At fingerprint `bcb0ac999e8d`, Yosys maps 7,113 LUT4s, 1,682 carries, 1,549
flip-flops and 19 EBRs; nextpnr attempts 8,124 placed cells. Relative to the
unretimed algebraic form this is +1 LUT4, -4 carries, no flip-flop change and
-2 placed cells while recovering the 192 sample clocks. Relative to section
16 it is +14 LUT4s, +24 carries, -25 flip-flops and -27 placed cells.
`make test-psg` passes, and the frozen render matrix remains 59/59
byte-identical. The provenance-bound final gate also passes all five Celeste
entry points (0, 10, 20, 30 and 40) from the same RTL fingerprint; music 0
retains only the previously documented fidelity divergence reserved for the
later fidelity pass.

### 19. Stop charging eight iterations for six-bit products

The blend position and pattern-row operands are both six bits, but mode 0
charged each eight iterations. The retained service adds one explicit
`mul_start_short` request bit. A short request runs six iterations while
retaining mode 1's existing ten-bit accumulator alignment, so its product
lands four bits left of the natural position; the two named consumers select
the correspondingly shifted slices. The iterative add/shift datapath and all
ordinary mode timings are unchanged. The cycle model checks 24,302
multiplicands and proves the shifted product exact.

This deliberately creates capacity without retiming the walker. The hardware
visit remains 85 phases and `psg_tb` remains 714/1,275 sample clocks and
3,555/7,654 tick-preparation clocks. The visualizer now reports a 30-clock
multiply-data depth, 53 clocks on the one shared service, and two phases of
completed-product hold before the fixed blend consume. It attributes both
hold phases rather than reporting unexplained empty cycles.

Fingerprint `2ecf587b7999` maps 7,142 LUT4s, 1,677 carries, 1,549 flip-flops
and 19 EBRs; nextpnr attempts 8,138 placed cells. Relative to section 18 this
is +29 LUT4s, -5 carries, no flip-flop or EBR change and +14 placed cells. The
small area trade is accepted for the two recovered service iterations.

Two superficially passing retimes were rejected by a new full-track
byte-comparison against section 18. Moving the fixed walker consume two phases
earlier first diverged in Celeste music 20 at 21.246 s (433,450 differing
samples, maximum delta 20,144). Reassigning all sequencer byte products to a
nine-iteration mode first diverged at 42.493 s (128,895 differing samples,
maximum delta 20,144). Both had passed the 59-case oracle and ordinary
full-track tolerance gate, demonstrating why the direct prior-RTL comparison
is required for schedule work. The retained explicit-short form is
byte-identical for all 1,226,752 music-20 samples, passes `make test-psg`, and
is 59/59 unchanged against the frozen matrix. The provenance-bound final gate
passes Celeste entry points 0, 10, 20, 30 and 40 from source fingerprint
`a11f43ccbe2f`.

### 20. One accumulator boundary: stop spelling the multiplier four times

The service's mode moved the accumulator boundary WITH the iteration count so
that every product landed at bit 0 no matter how many steps it took. That made
one shift-add engine into four: a 22-bit four-way mux selecting `m_acc`, a
34-bit four-way mux re-packing `m_p`, and the `m_mode` register that drove
both. None of it is arithmetic — it is alignment.

Fixing the boundary at 12 for every request makes an N-step product land N
steps short of bottom, so its value is the exact product shifted LEFT by
(12 - N):

```
m_p after N iterations = |A| * B * 2^(12-N)      (N = 6, 8, 9, 10, 12)
```

`tools/psg_mul_model.py` proves that over the whole |A| sweep for all five
live iteration counts, and proves the shift never overflows: a mode-N request
contracts B < 2^N and |A| <= 0x1CE0 << 8, so every landing is below 2^33.
`mul_start_short` was already this idea in miniature — six steps at mode 1's
boundary, landing four bits left, with two consumers compensating in wiring —
and this generalises it to every mode.

Every call site has a FIXED iteration count, so its consumer's offset is a
constant and the compensation is wiring, not a shifter. The five offsets are
now named in the gate so a future edit cannot get them silently wrong:
wavetable lerp `m_res[20:2]`, the twelve-step G pass `m_res[26:10]`
(unmoved), the `x*341` limb `m_res[28:3]`, the sequencer's eight-step effect
products `m_res[27:4]` / `m_res[31:11]` / `m_res[10:4]`, and the six-step
blend and pattern-length products `m_res[28:6]` / `m_res[18:6]`. The single
ten-step sequencer product, the music gain at xs 10, takes `m_res[21:10]`.
Widths and truncation points are unchanged at every one of them, so every
consumed value is bit-identical — this is a re-positioning, not a re-rounding.
The three result ports collapse with the alignment: `m_res`, `m_res_wide` and
`m_res12` were 32, 34 and 28 bits of the same register, and picking the wrong
one is the bug class this file keeps recording. There is now one 34-bit view.

At RTL fingerprint `0dde4052c511`, Yosys maps 7,009 LUT4s, 1,687 carries,
1,547 flip-flops and 19 EBRs; nextpnr attempts 8,017 placed cells. Relative to
section 19 that is -133 LUT4s, +10 carries, -2 flip-flops, no EBR change and
-121 placed cells. The pre-mapping census moves 16,235 -> 16,089.

Nothing about the schedule moves: iteration counts, `m_busy` and every request
and consume phase are unchanged, so `make test-psg` stays at 714/1,275 sample
clocks and 3,555/7,654 tick-preparation clocks with zero late flips. The
frozen matrix is 59/59 byte-exact against PICO-8 and byte-identical against
the anchor, and all five Celeste entry points (0, 10, 20, 30, 40) render
byte-identically to their section-19 WAVs.

Two neighbouring experiments were measured and REFUTED in the same pass, and
both refute by the same mechanism:

- Narrowing `mul_start_a` from 25 to 22 bits. The service reads only bit 24
  and bits 20:0, and no arm exceeds |A| < 2^21, so three bits of every operand
  arm are dead — and removing them is **exactly 0 cells**. `synth_ice40`
  flattens before optimising, so bits no consumer reads are already pruned
  through the module port. Bit-width "invisible bounds" are only worth
  spelling when the bound is on a VALUE; a bound on a POSITION is already
  visible to synthesis.
- Sharing the two comb networks. Ablating `cmb_old` to a constant priced it at
  -158 cells, but ablating it to its actual replacement — the identity, which
  is what `tz((2x + h)/2)` is at h = 0, verified over all 131,072 17-bit
  values — is **0 cells**. Yosys already folds both combs away at REVERB=0.
  The -158 was the downstream `blend_diff` subtract and `bl_acc` term
  collapsing, which no sharing can remove. **Ablate to the proposed
  replacement, never to zero**: a constant ablation prices the cone plus
  everything it feeds, and reports a saving that cannot be realised.

### 21. Fold the split identity onto its own remainder, and share one block

The three reciprocal tables were seven of the nineteen blocks: `tab15`
2048x7 mapped to four, `tab7` 1024x7 to two, `org3` 512x8 to one. Depth is
what costs, not content - an EBR is 4 kbit whatever its shape, so a 2048-deep
array is stuck in 2048x2 mode and a seven-bit value eats four blocks to use
seven of the eight bits it can reach.

The identity that built those tables applies to its own remainder, and the
second application is the cheap one. Choosing k with 2^k = d + 1 makes the
outer multiplier 1, so the recombine gains a bare add and no shift:

```
/15   y <= 1695,  k=4:  y/15 = (y>>4) + z/15,  z = (y>>4) + y[3:0] <= 120
/7    y <=  847,  k=3:  y/7  = (y>>3) + z/7,   z = (y>>3) + y[2:0] <= 112
/3    y <=  509,  k=2:  y/3  = (y>>2) + z/3,   z = (y>>2) + y[1:0] <= 129
```

Verified exhaustively end to end - every value of each shape's whole ramp,
368,635 for tilted-saw high, 172,030 for tilted-saw low, 65,535 for the organ
- against the plain quotient, before any RTL moved.

Two folds are also the MINIMUM. One fold cannot reach an index below 256: it
would need 2^k < 256, and then h = x >> k is itself in the thousands.

Every index is now under 256 and every remainder under six bits, so the three
tables become three FIELDS of one 256 x 16 word - 4 + 5 + 6 = 15 bits. The
consuming shapes are wsel-exclusive per evaluation, so one read port serves
all three: the stage-1 address selects the divisor and the stage-2 field
select follows it, on exactly the selection the recombine already made.
Entries above each divisor's index bound are truncated rather than wrong to
read; they are never addressed, the same discipline the single-stage tables
used for `7'(i/15)`.

One divisor is live per evaluation, so one index add serves all three: the
halves are selected and added once, rather than three adds racing to a mux.
That form is 22 structural cells cheaper than the three-add one, and the
second fold's quotient falls out of the same selection.

At RTL fingerprint `b434542f3d01`: **19 -> 13 EBRs**, with Yosys mapping 7,076
LUT4s, 1,693 carries and 1,554 flip-flops, and nextpnr attempting 8,092 placed
cells. Relative to section 20 that is +67 LUT4s, +6 carries, +7 flip-flops and
+75 placed cells; the pre-mapping census moves 16,089 -> 16,125. This is the
same explicit binding-BRAM trade sections 9 to 11 made, at a much better rate:
**+12.5 placed cells per block freed against the +39 to +47 each of those
stages paid for one.** It also takes the standalone target under the change's
15-EBR ceiling for the first time, with six blocks of headroom for the state
and decode migrations that are the remaining logic-cell levers.

The arithmetic is proven, so the renders are unchanged: `make test-psg` stays
at 714/1,275 sample clocks and 3,555/7,654 tick clocks with zero late flips,
the frozen matrix is 59/59 byte-exact against PICO-8 and byte-identical
against the anchor, and all five Celeste entry points render byte-identically
to their section-20 WAVs.

Not condensable, checked rather than assumed: `aram` is 4,608 x 8 = 36,864
bits in nine blocks, which is 100% of nine EBRs - the PICO-8 audio image is
exactly that size, so it cannot shrink without changing what a cart may
contain. `crom` uses 253 of its 256 words. `state_m`'s two blocks are half
spare BY DESIGN - that spare is what the record migrations are for.

## Risks / Trade-offs

- **[Single-store contention]** Tick and sample work can request the voice EBR
  together. → Give sample work fixed priority, pause tick microcode at a
  replayable instruction, and assert completion before publication.
- **[Microcode changes audible ordering]** A mathematically identical result
  can be committed one sample later. → Write only the inactive parameter bank
  and swap it at the existing atomic boundary.
- **[Generic ALU recreates a wide mux]** Many source/destination selectors can
  exceed the arithmetic they replace. → Use a small memory-addressed register
  contract and exactly one accumulator write site; synthesize after each
  migrated operation.
- **[BRAM is also scarce]** The PPU already owns sixteen blocks. → The first
  state-store stage recovers two blocks and the hybrid waveform stage recovers
  two more; microcode/table storage must fit within that recovered budget.
- **[Algorithmic waveform rounding]** Formulae may differ at discontinuities
  or signed division points. → Compare each waveform probe before removing its
  ROM bank and preserve explicit truncation-toward-zero behavior.
- **[Large rewrite obscures regressions]** → Land and measure independently
  reversible stages; never combine an unmeasured state migration with an
  arithmetic migration.

## Migration Plan

1. Freeze the current oracle output and mapped/routed fingerprints.
2. Add deadline instrumentation without changing the datapath.
3. Introduce double-buffered publication, then collapse the voice memories.
4. Replace tick evaluation with the memory-to-accumulator microengine.
5. Migrate sample arithmetic one operation family at a time.
6. Replace built-in waveform ROM banks where the shared engine wins.
7. Run the final multi-seed and full integration gates.

Each stage remains a separable diff. Rollback is removal of the latest stage,
not restoration of pre-fidelity RTL.

## Open Questions

- Whether a 16-bit or byte-serial accumulator gives the best HX8K packing will
  be decided by two synthesis spikes against the same memory/write-site
  contract.
- Whether all built-in waves should be computed or a hybrid table should
  remain will be decided per waveform by oracle and mapped-resource results.
