## Context

The fidelity-complete standalone PSG currently maps to 6,054 LUT4s, about
1,800 flip-flops and 19 `SB_RAM40_4K` blocks. Seed-1 placement reports
7,124/7,680 HX8K logic cells (92%). The immediately preceding RTL maps to
5,830 LUT4s, so the transition/secondary-oscillator corrections added 224
LUT4s and four flops; reverting those corrections would lose measured PICO-8
fidelity without addressing the older fixed cost.

The hardware clock is not a simulator budget. At the change baseline, a
112.5 MHz PLL fed the PSG through a divide-by-four clock, giving 28.125 MHz and
a minimum of 1,275 hardware clocks between 22,050 Hz sample boundaries. The
accepted R.54 result supersedes that operating point: the current divide-by-five
clock is 22.5 MHz and supplies at least 1,020 clocks per sample. Its 618-clock
full walk plus 272 fixed sequencer credits leaves 130 clocks of margin.

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
- Keep worst-case sample work within 1,020 derived PSG clocks and tick
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

### 22. Fold the decode back into the table, and the defect that exposed

The question section 21 raises is what else is LOGIC APPLIED TO A TABLE VALUE.
Audited across all four memories, the genuine arithmetic is already folded or
cannot be: `pinc` is stored in 13 bits precisely because its `<< 8` is folded
into the wiring; `fstep` feeds an accumulator with no constant of its own; the
slide affine's `r` and `b` are operands of a variable multiply and add; and
`recip`'s remainder is one addend of a variable sum - the one constant near
it, `div_out`'s -8192/-12286, is applied AFTER the mux that selects the
non-table tail path, so folding it in would buy a second subtract.

The control store is the exception, and a large one. Section 10 encoded the
walker's one-hot actions as a five-bit opcode to halve the word and save a
block, and section 11 then shared the port - together +84 placed cells, paid
deliberately when blocks were the binding resource. Blocks are no longer the
binding resource, and that decode is exactly logic applied to a table value.

It reverses for FREE rather than for a block, on three coincidences:

1. There are exactly SIXTEEN actions, so a one-hot field is a 16-bit word -
   the width the encoded word already occupies in `psg_const.hex`, on the same
   shared port. No block changes hands.
2. All six former flag bits are ALIASES under one-hot, each sitting on a phase
   that already carries an action: SYN_A and W0; SYN_B, ISS_SEC and W1;
   ISS_OLDMAIN and W2; ISS_OLDSEC and W3; DQ_OLD and W5.
3. CAP_FOLD's phase IS PLAST, which the walk already tests to close the visit,
   so the seventeenth action needs no bit either.

The two step decodes become `(* parallel_case *) case (1'b1)` over the one-hot
bits - section 9's measured spelling; a parallel IF chain builds a priority
network and cost +154 structural when it was tried.

**And the first attempt failed its gate, which is the important part of this
section.** `make test-psg`, the 59-case matrix and the ordinary tolerance gate
all passed; the direct byte comparison against the previous RTL did not -
Celeste music 20 diverged at 16.997 s, 39% of samples, maximum delta 41,475.
That is the R.25 lesson repeating, and probing the walk found a real defect
underneath it:

**`ctrl_addr` is only selected onto the shared port while `prun` is set, so
the word registered for pph 0 was fetched on the cycle BEFORE the walk started
- when the sequencer still owned the port. Slot 0 reads a stale pitch word on
the first phase of every visit and executes whatever action those bits name,
against the previous slot's streamed state.** Measured at HEAD: `ctrl_q` =
0x00c2 at slot 0 / pph 0, every sample, decoding to CAP_W1. Slots 1..7 are
fine - `pph_nxt` wraps to 0 under `prun`, so they read the true pph-0 word,
which is zero.

The defect was INVISIBLE because it was inert: CAP_W1's writes (`s_phase`,
`smp_a`, `s_old_phase`, `nz_old_out_r`) are each overwritten or gated before
any consumer. That is luck, not design - the stale word is whichever pitch
word the sequencer last addressed, so which action fires is cart data. One-hot
decodes the same garbage into SEVERAL actions, and those are not inert.

Gating the word to zero at pph 0 is exactly "the schedule has no action at
pph 0", and `tools/gen_psg_ctrl.py` now asserts that so no future schedule can
quietly depend on one. Applied to the UNCHANGED encoded design it is
byte-identical - Celeste music 20 identical over all 1,226,752 samples, and
the provenance-bound fidelity numbers against real PICO-8 unmoved to the last
digit - which is what makes it a render-neutral prerequisite rather than a
render change. With it in place the one-hot fold is byte-exact.

At RTL fingerprint `12037fb1cc6e`: 8,092 -> 8,078 placed cells (-14), Yosys
mapping 7,065 LUT4s (-11), 1,690 carries (-3), 1,554 flip-flops and 13 EBRs
unchanged; pre-mapping census 16,125 -> 16,089 (-36). The fold alone is -45
LUT4s and -56 placed; the gate costs +34 LUT4s of the saving. The placed delta
is inside the mapping-noise band, so the cell claim rests on the structural
number - and the real return is the defect and what it unblocks.

**And the same argument does NOT extend to the rest of the walker's
pph-derived fabric - measured, refuted, recorded.** `wlk_ra`/`wlk_wa`'s
comparators, subtracts and adds and the three record enables were built as a
128 x 16 control word in its own block. The result is render-exact and
structurally cheaper and still not worth a block:

| form | pre-map cells | placed | LUT4 | carries |
| --- | --- | --- | --- | --- |
| shape ablation, arbitrary contents | -88 | - | - | - |
| real, 14-bit word, offset write address | -73 | **+32** | +62 | -22 |
| real, 16-bit word, absolute write address | -75 | **-14** | +21 | -23 |

**-75 structural cells map to +21 LUT4s.** The reason generalises and is worth
carrying: the pph comparator fabric is SHARED - the 18-arm record-load
`case (pph)`, `s_stw`, `pph == PWORK+26`, `pph == PLAST` all read it - so
peeling individual consumers off removes terms without retiring the decode,
and abc9 then covers what remains worse than it covered the whole. It is THE
LAW in a new dress: a partial migration off shared fabric pays nothing.

A -14 placed delta is inside the +/-60 mapping-noise band, so nothing is
established, and it spends one of the blocks section 21 banked. The version
worth measuring next is the total one - EVERY pph-derived decode moved at
once, record-load case included, so the fabric stops existing. That needs a
load-slot field the 16-bit word cannot hold, so two blocks (13 -> 15), still
inside this change's EBR ceiling.

### 23. The noise walk still has a PARALLEL multiplier, and it is 4% of the chip

Census on the section-22 build puts `nz_out_r`'s cone at 480 LUT4s, the
largest single family in the design, ahead of the whole tilted-saw
reciprocal. It contains the one remaining `*` operator in the hardware
lowering:

```
wire signed [25:0] nz_mul_full = ($signed({1'b0, nz_mul_j}) * nz_mul_rand) >>> 8;
```

A 17 x 8 signed parallel multiplier, on a chip whose entire arithmetic design
is one shared iterative service and whose fabric has no DSP. R.14 already
merged the live and old noise walks onto this ONE cone, which is why it reads
as a single modest line; it is nevertheless a full array.

Ablated by replacing the product with a same-width, non-constant wiring
function of the same operands - downstream clamps, accumulator and publication
untouched, so this is the multiply network alone: **8,078 -> 7,771 placed
cells (-307), 7,065 -> 6,771 LUT4s (-294), 1,690 -> 1,653 carries, 13 EBRs
unchanged; pre-mapping 16,089 -> 15,382 (-707).** It takes the standalone
target from 105% to 101% of the HX8K, 91 cells from placing, and it is the
largest single lever this change has measured.

The destination is the existing service, not new hardware. |A| = `nz_mul_j`
is 17 bits (inside the service's 2^21 ceiling) and B = |`nz_mul_rand`| <= 128
fits mode 0's byte contract, so it is two ordinary eight-iteration requests
per visit. Two things have to be got right:

- **Semantics.** `(j * rand) >>> 8` is an arithmetic shift of a SIGNED product
  - floor. The service works in the magnitude domain with consumer-side sign,
  which truncates toward zero. They differ by one whenever the product is
  negative and its low eight bits are nonzero, so the negative arm needs the
  `+255` round-up. Exactly reproducible, and `tools/psg_mul_model.py` is the
  place to prove it before any RTL moves.
- **Schedule.** The live product is consumed at CAP_W0 and the old at CAP_W1,
  but its operands only settle when the record load does (`s_eff_inc` at
  PLOSC+1/+2, `s_old_inc` at pph 9/10; both LFSRs are stable until W0 steps
  them). The service is IDLE through the whole load window - the walk's first
  existing request is CAP_W4 - so the two requests fit there, and the consumes
  need PWORK to move later by about eight phases. Shift PWORK, PSTOR, PFOLD
  and PLAST by the same amount and every relative relationship in the visit is
  preserved; the control ROM regenerates from those constants. Cost is about
  eight phases per slot, 714 -> ~778 clocks per sample, against 561 spare.

This is a schedule change on the most fidelity-delicate path in the chip, so
it is R.25's danger zone by construction: gate it on the 400,000-sample
music-20 byte comparison (an 80-second loop) before spending the full battery.

Two neighbours priced at the same time, both already closed:

- `nz_thresh = nz_sum / 3` ablates at -726 PRE-MAPPING cells and looks like a
  bigger prize than the multiplier. It is not: R.15 already built the exact
  replacement (`3g + 3 <= x`, which is an exact rewrite of `g < floor(x/3)`)
  and measured **+57 LUT4s and +22 placed**. Structural cells are not LUT4s -
  the same trap section 22 records for the pph fabric. Do not retry.

  Re-measured standalone (the cone lifted out registered-in/registered-out,
  same yosys, plus nextpnr for placed LCs) because -726 kept looking like it
  had to mean something. It does not, and the isolated numbers reproduce the
  in-design ones exactly:

      as built  `g < (dp+500)/3`      763 pre-map   36 LUT4  50 carry  107 LC
      R.15      `3g + 3 <= dp+500`    108 pre-map   76 LUT4  38 carry  109 LC
      ablation  (wiring fn)            36 pre-map   18 LUT4   9 carry   48 LC

  The ablation delta is -727, i.e. the recorded -726 to within one cell, and
  R.15's rewrite is +40 LUT4 / -12 carry / +2 LC against the +57 / -16 / +22
  it measured in-design. The cone is unshared; context is doing nothing here.

  **The mechanism, which the "structural cells are not LUT4s" phrasing does
  not capture: the structural-to-LC ratio is not constant across cell
  families.** The divider alone is 713 pre-map cells and 63 placed LCs -
  **11:1**. The adder/comparator forms are **1:1** (108 pre-map -> 109 LC;
  84 -> 84). Yosys lowers `$div` to a restoring array before exploiting the
  constant divisor: 13 quotient stages x a 17-bit conditional subtract, which
  is the 289 `$__ICE40_CARRY_WRAPPER` cells. With divisor 3 the partial
  remainder is always < 3, so ~15 of the 17 bits of every subtract sit on
  constant zeros; opt and abc9 delete them and what survives is near the
  minimal MSB-first digit recurrence, about two cells per dividend bit. 289
  carry wrappers become 50. The array was ~92% scaffolding. The rewrite has
  no such slack to give back - `g` is a free 13-bit variable, so `3g` and the
  15-bit compare are all real, and both are committed to hard carry chains at
  alumacc time before abc9 can restructure. The ledger was comparing 727
  fictional cells against 108 real ones.

  So the usable rule is per-family: carry-chain arithmetic ~1:1 (pre-map is
  an honest proxy), `$div`/`$mod` by a constant ~11:1 (pre-map is fiction),
  shared decode fabric the section-22/R.29 case (the count drops but nothing
  retires). `tools/psg_ff_census.py`'s docstring carries the carve-out.

  One loose end for anyone re-deriving this: R.15's rewrite is not the
  cheapest exact one. Folding the constant to the other side - `3g <= dp+497`
  rather than `3g+3 <= dp+500` - measures **84 LC against the divider's 107**,
  so -23 rather than +2. Do not retry still holds, because -23 is inside the
  +/-60 mapping-noise band. But the reason is that the whole `/3` is worth
  ~59 LCs (107 against the 48-LC ablation floor) and the best rewrite recovers
  about a third of it - not that the rewrite is inherently worse.
- `nz_kick_m` is already a three-term masked shift-add, not a multiply.

### 24. SEQ_BUDGET: built, measured, and the reason it buys nothing here

R.30 needs about thirteen more phases per visit, so before it could land the
question "is the visit's LENGTH render-load-bearing?" had to be answered.
Measured directly: shifting PWORK, PSTOR, PFOLD and PLAST by +13 with no
arithmetic change of any kind moves **two of 400,000** Celeste music-20
samples. It is.

The recorded fix for that is a cycle budget for the sequencer - a fixed number
of cycles offered per sample interval, frozen for the remainder, so the FSM's
position at every sample boundary is a function of the sample index alone. It
was written up as landed. **It is not in the RTL** - `git grep SEQ_BUDGET`
finds nothing, and `1261e19` is the measurement commit and never mentions it.
So it was built here, and then measured. Everything below is measurement.

**The counter is inert.** With a budget too large to bind, Celeste music 20 is
byte-identical to HEAD over 400,000 samples. Every difference seen at any
other setting is the BOUND, not the mechanism. (First attempt at this control
used a 9-bit counter and the value 1023, which truncates to 511 and bound
after all - the control has to be checked as carefully as the experiment.)

**The leftover is already CONSTANT.** Probing the cycles actually offered per
interval: **565, every interval, unchanging across 400,000 samples.** That
follows from the walk being a fixed program - 85 phases x 8 slots plus a fold
- so `1275 - 710` is the same number every sample. The design is therefore
already deterministic at a FIXED clock and a FIXED walk length; the fragility
is only ACROSS changes to either.

**And the sequencer uses those cycles.** Clipping below 565 costs timing
fidelity against real PICO-8, measured on the provenance-bound Celeste gate:

| SEQ_BUDGET | tick pre-run | music-20 lock | blocks tracked | gate |
| --- | --- | --- | --- | --- |
| unbounded (today) | 3,555 / 7,654 | 0.83 | 94 / 110 | pass |
| 416 | 4,705 / 7,654 | 0.73 | 59 / 110 | pass |
| 288 | 6,053 / 7,654 | 0.71 | 49 / 110 | **FAIL** |

Both bounded settings keep `psg_tb` at zero late flips and the frozen matrix
at 59/59 byte-exact against PICO-8 - the 59 short cases never exercise a
chain, so the oracle cannot see this. Only `mix-four` moves against the
anchor, and it is a pure one-sample onset shift (bit-identical at lag +1).
**The oracle is blind to exactly the property this bound changes**, which is
why the full-track gate is the one that adjudicated it.

So the window is empty. Invariance needs SEQ_BUDGET <= the leftover, fidelity
needs it >= what the sequencer draws, and at 28.125 MHz those meet at 565 -
the whole leftover. A budget of 565 states `f_min = 22050 * (710 + 565) =
28.125 MHz` exactly: the bound is honoured only at precisely the shipping
clock and leaves zero room for the walk to grow. It buys the invariance in
name and nothing in practice. Not landed; the counter costs 8,078 -> 8,096
placed cells (+18, nine flops and a comparator) for it.

**What this actually says about R.30.** Its price was never "a render change
needing a re-frozen baseline". Its price is that the sequencer loses 104 of
its 565 cycles per sample, which lands it in the degraded band the table
above measures - closer to the 416 row than to today. R.30 must therefore be
adjudicated on the full-track gate as a FIDELITY trade, not booked as a free
-307 cells. The three ways out, in the order they are worth trying:

1. **Buy the phases back inside the visit.** The walk is 85 phases with 41 of
   them multiply-latency shadow; R.30 adds 13 to the load window. Any 13
   phases retired elsewhere make it free. This is the only option that costs
   nothing.
2. **Raise the PSG clock.** PSGDIV is a one-way ratchet - 112.5/4 = 28.125 and
   /3 = 37.5 MHz against a routed Fmax near 36 - so this is not currently
   available.
3. **Spend the fidelity** and adjudicate it explicitly on the five-track gate.

### 25. Radix-4: the landing law makes the radix free

Section 24 closed with "buy the thirteen phases back inside the visit" as the
only option that costs nothing. The place to buy them is the service itself.

`psg_mulsvc` was radix-2: one multiplier bit per clock, latency N+1. The
landing law from section 20 is what makes a wider radix free. Restated
generally, a product lands as many places short of bottom as there are
multiplier bits still unretired:

```
m_p after M steps = |A| * B * 2^(12 - RADIX_BITS*M)
```

A radix-4 step retires TWO bits, so **M = N/2 lands exactly where the radix-2
N-step request did** - 12->6, 10->5, 8->4, 6->3 steps - and **no consumer
slice moves anywhere in the chip**. Mode 3's nine steps are the one odd count
with no exact half; loading `B << 1` for that mode alone restores its landing,
and mode 3's own B < 2^9 contract leaves room for the shift. Average latency
falls 10.0 -> 5.6 cycles.

`tools/psg_mul_model.py` now carries this as a permanent gate rather than a
one-off: it reads the radix out of the RTL's write-back shift and the
pre-shift out of the `m_p` load, and checks the engine against the SHIPPED
radix-2 reference across every mode, every corner B, the whole |A| sweep and
both signs. The "every named consume offset matches its launch" check is what
states the no-slice-moves claim.

3A is combinational, not registered: the 23 flops registering it would cost
more than the adder they save, measured standalone at 282 LC / 99.7 MHz
against 259 / 118.9.

**Isolated** (harness minus an empty DUT), all five candidates proven
bit-identical to the shipped engine over 6,000 cases:

| variant | avg latency | LUT4 | carry | LC | Fmax |
| --- | --- | --- | --- | --- | --- |
| base (radix-2) | 10.0 | 127 | 43 | 207 | 124.2 |
| r2fold (first step in the load cycle) | 9.0 | 167 | 43 | 263 | 91.9 |
| **r4comb (retained)** | **5.6** | 178 | 64 | **259** | **118.9** |
| r4reg (registered 3A) | 5.6 | 180 | 64 | 282 | 99.7 |
| r4fold | 4.6 | 261 | 64 | 372 | 73.5 |
| r8comb (radix-8) | 4.2 | 378 | 108 | 460 | 73.4 |

**In design**, at RTL fingerprint `6aaa743b4414`: pre-mapping 16,089 ->
16,173 (+84), Yosys mapping 7,156 LUT4s (+91), 1,711 carries (+21), 1,553
flip-flops (-1) and 13 EBRs unchanged; nextpnr attempts 8,171 placed cells
(+93). **The cost is real, not mapping noise** - it is paid for by section 26.

What it buys with no schedule edit at all: the tick side reclaims immediately,
because the sequencer stalls on `!m_busy` rather than on fixed phases. `psg_tb`
goes from 3,555 to **3,356** of 7,654 tick-preparation clocks, zero late flips
- **-199 clocks per tick, free.** The sample walk stays at 714/1,275 because it
IS phase-pinned by the control ROM; collecting that is section 26's job.
**It is NOT render-neutral, and the reason is worth stating.** The arithmetic
is bit-identical - the frozen matrix is 59/59 byte-exact against PICO-8 AND
byte-identical against the anchor, and Celeste music 20 is byte-identical over
400,000 samples. But `psg_seq`'s effect microprogram STALLS on the service:
`K_FX: if (!m_busy && ...)` gates the whole arm, so the micro-PC does not
advance while a product is in flight. Halving the latency advances it about
five cycles earlier per product, six products a slot, and the tick program
finishes sooner. Where that crosses a sample boundary the render moves -
**Celeste music 10, 2,202 of 848,896 samples (0.26%), first at 25.496 s**; the
other four entry points are byte-identical. Every fidelity number is
unchanged: pitch 87.9%, spectrum cosine 0.997, lock 0.72 at 37/75 blocks, rms
5,529 against 5,534. The gate passes.

This is section 24's unbounded sequencer seen from the other side, and note
that SEQ_BUDGET would NOT have made it transparent: a fixed cycle offer still
lets a faster sequencer get further within it. The only way to make radix-4
byte-neutral is to hold `m_busy` for the radix-2 duration while the product is
ready early - and that is mutually exclusive with the recompaction, whose
whole point is to space the walk's launches by the TRUE latency. Two busy
signals (true for the walk's request mux, padded for the sequencer) would give
both, at the cost of a small counter and of preserving an accident: nothing
but the stall ties the sequencer's pace to the multiplier's latency. Retained
as a render change on the evidence that no fidelity metric moves.

Rejected with numbers:

- **Radix-8.** 4.2 cycles average, but +253 LC standalone on a design that is
  491 cells from placing, and Fmax down 41%.
- **Folding the first step into the load cycle** (N+1 -> N). +56 LC for one
  cycle, and it changes WHEN `m_busy` rises. `psg_seq`'s fire-and-forget
  `ptick_pend && !m_busy` capture depends on `m_busy` being high the cycle
  after a launch. Radix-4 only moves the DEASSERT earlier, which is exactly
  why it is transparent; the fold is not.
- **Per-site mode retuning.** `lfo_mag` is 2 bits on an 8-step request and
  `sl_bhi` is 9 bits on a 12-step one - real over-provisioning, but radix-4
  collapses the gap to one cycle and it stops being worth a stage.

### 26. Recompacting the control ROM onto the radix-4 latency

The walk is phase-pinned by the control store, so radix-4 bought it nothing
until the timetable moved in. Respacing every launch to the new latency -
request at p, readable at p + steps + 1, so mode 2 lands at p+7, modes 1 and 3
at p+6, the short request at p+4 - collapses the chain from 65 phases to 43
and the visit from **85 phases to 63**.

Two collisions had to be resolved, and they resolve differently:

- **W15 and W17 both want phase +11.** The wavetable q-side lerp and the
  non-wavetable first reciprocal limb are `s_snd_wt`-exclusive, so they share
  ONE action rather than burning a phase each - one opcode, the guard inside,
  in both the request mux and the capture case. Fifteen actions now, one bit
  spare.
- **W26 and W27 cannot merge the same way.** W26 writes the `smp_b` that W27's
  operand reads, so merging them would make W27 read the pre-edge value. They
  stay one phase apart, and the non-wavetable chain waits that phase out with
  its product already parked. That is the one phase this schedule gives away.

Everything phase-relative outside the ROM moved with it, and where possible it
now reads its position from something that cannot drift: the two late dampen
write-backs are stated against `PLAST - 2`/`PLAST - 1` rather than `PWORK+63`,
and the wavetable lerp base reads `cap[CAP_W26]` rather than a phase number.
The reverb ring taps (REVERB=1 only) moved with the chain. `gen_psg_ctrl.py`
asserts the store window and the late writes still fit inside the visit.

At RTL fingerprint `ffdb1243f85f`: pre-mapping 16,173 -> 16,138 (-35), Yosys
7,094 LUT4s (-62), 1,718 carries (+7), 1,553 flip-flops and 13 EBRs unchanged;
nextpnr attempts 8,123 placed cells (-48).

**The walk falls from 714 to 538 of 1,275 clocks per sample** - 176 clocks
back - and the tick pre-run from 3,356 to 2,289 of 7,654 with 5,365 spare and
zero late flips. Taken with section 25 the pair costs +45 placed cells and
returns 176 clocks a sample and 1,266 a tick.

**And it settles section 24.** The sequencer's per-interval offer rises from
565 to about 741 cycles. R.30 needs eight phases at radix-4 - live product
launched at 18 and readable at 23, old at 23 and readable at 28, so PWORK 19
-> 27 - which is 64 clocks. That leaves the sequencer more than it has ever
had, so **R.30 no longer takes anything from it**: the fidelity trade section
24 priced has been bought out.

Gates: the frozen matrix is 59/59 byte-exact against PICO-8 AND byte-identical
against the anchor - a 22-phase reschedule that moved no oracle sample.
`make test-psg` passes. Fidelity against PICO-8 across all five Celeste entry
points is within tolerance of the recorded baseline, with music 10's contour
improving 0.967 -> 0.972.

### 27. Fidelity against PICO-8, as a regression gate

`psg_track_gate.py` compares a render to a real PICO-8 recording, but its
verdict is an ABSOLUTE tolerance - which is how section 24's SEQ_BUDGET=416
went green while moving music 20's lock from 0.83 to 0.73, and how the same
thing nearly happened twice more. Seeing it required diffing numbers out of
two logs by hand.

`tools/psg_pico8_fidelity.py` (`make test-psg-pico8`) renders all five entry
points with the current RTL, measures them against the committed recordings,
and compares the measurements to a baseline in `tests/psg/pico8-fidelity.json`.
A metric that gets worse by more than its tolerance FAILS; a metric that
improves never does. The measured set is the one that actually moved during
this campaign: lock median and the fraction of half-second blocks holding
lag - which is what catches sequencer timing drift - the contour correlation,
which is the metric for unpitched material, and the twelve band levels.

The baseline is fidelity against PICO-8, NOT against our own previous render.
Our previous render is not ground truth; the recordings are. That distinction
is what lets a schedule change that moves samples pass, and a change that
moves the sound fail, which is the discrimination this campaign kept having to
make by eye.

### 28. The noise walk joins the shared service

Section 23 measured the last `*` in the hardware lowering - a 17x8 parallel
array feeding `nz_out_r`, the largest LUT4 family in the design - at -307
placed cells, and section 24 priced its migration at "the sequencer loses 104
of its 565 cycles a sample". Section 26 bought that out: the walk is 63
phases, so the ten this needs cost the sequencer nothing it was using.

Both steps are now ordinary mode-0 requests. |A| = j is 17 bits, inside the
service's 2^21 ceiling; B = |rand| <= 128 fits mode 0's byte contract; mode 0
is four radix-4 steps and lands four places left, so the magnitude is
`m_res[27:4]`. Three things had to be right:

1. **The semantics.** `(j * rand) >>> 8` is an arithmetic shift of a SIGNED
   product - floor - while the service works in the magnitude domain, which
   truncates toward zero. They differ by one whenever the product is negative
   and its low eight bits are nonzero, so the negative arm rounds up. Proven
   before any RTL moved.
2. **The increment the old step multiplies.** The old product used to be
   evaluated at CAP_W1, AFTER CAP_W0's edge - so on a restart sample it saw
   the `s_last_inc` that CAP_W0's params-changed block had just copied into
   `s_old_inc`. Running it in the load window means reading the copy that has
   not happened yet, so the restart decision is factored into `blend_restart`
   and the product selects `blend_restart ? s_last_inc : s_old_inc`. Without
   this the render was wrong on exactly the tick boundaries - 2,202 samples of
   music 20 in an earlier attempt. One cone serves both readers: every term is
   stable from pph 19 (s_eff_a is the last word in) until CAP_W2 rewrites the
   `last_*` registers.
3. **The phases.** The service is idle through the whole load window - the
   walk's first other request is CAP_W4 - so NZ_OLD launches at 19, the first
   phase its restart cone is valid, and is readable at 24; NZ_LIVE takes the
   service on that same cycle and is readable at 29. The old product is
   therefore read out on exactly the phase the live one is requested, and only
   it needs a register. PWORK moves 19 -> 29 and PSTOR/PFOLD/PLAST with it.
   The request mux DROPS rather than queues, so a simulation assertion fires
   if either phase ever finds the service busy.

`nz2_rand_r` retires: both draws are pre-advance by construction now, because
the LFSRs step at CAP_W0, long after these phases.

At RTL fingerprint `2dc67844558a`: pre-mapping 16,138 -> **15,674 (-464)**,
Yosys 6,923 LUT4s (-171), 1,718 carries unchanged, 1,563 flip-flops (+10, the
capture register), 13 EBRs unchanged; nextpnr attempts **7,931 placed cells
(-192)**. That is **103% of the HX8K, 251 cells from placing**, against 491
before this session's last three stages.

The visit grows 63 -> 73 phases, so the walk goes 538 -> 618 of 1,275 clocks
per sample - still 96 below where this session found it - and the tick pre-run
sits at 2,443 of 7,654 with 5,211 spare and zero late flips.

Renders: Celeste music 20 byte-identical over 400,000 samples, the frozen
matrix 59/59 byte-exact against PICO-8 AND byte-identical against the anchor,
and fidelity against PICO-8 within tolerance on all five entry points.

### 29. Group the multiply requests by OPERANDS, not by phase

A per-module census is misleading on a flattened netlist, and following it
found this. `u_mul` reads as 670 LUT4s for one iterative engine, which is
absurd until you look at the cell names: `m_a`'s D-cone alone is ~250, and
that cone is not the multiplier - it is the whole request mux, flattened in
and then named after the flop it drives. **The service's operand SELECTION was
about 470 LUT4s**, which is section 5c's law stated as a measurement.

Seven arms, one per launching phase. But the phases are mutually exclusive and
several ask for the SAME shape, so the arms can be grouped by what they need
rather than by who needs it - selecting the operands where a second arm would
have selected the result, which is the cheap direction:

- **The two noise requests** are one expression, `J = 8*dp + 1120` against
  `|draw|`, on different increments and draws. One selected `dp`, one adder,
  one arm.
- **The wavetable lerp** is a signed 9-bit table delta times a 10-bit phase
  fraction at W4 (p side) and again at W15 (q side).
- **The G pass** is `|z| x G` at W4 for the new voice, at W27 for the old -
  and at W27 for the new one too on the wavetable path, whose lerp already
  used W4.
- **The retained `x*341` limb** is IDENTICAL at W15 and W40: same operand,
  same constant, same mode. Two arms for one expression.

Seven arms become four. Three 25-bit arms, a 17-bit adder and a duplicated
12-bit constant stop existing; what replaces them is a 13-bit select, a 9-bit
select and two one-bit ones.

At RTL fingerprint `d583d0cd1b29`: pre-mapping 15,674 -> **15,506 (-168)**,
Yosys 6,868 LUT4s (-55), 1,709 carries (-9), 1,563 flip-flops and 13 EBRs
unchanged; nextpnr attempts **7,877 placed cells (-54)**. That is 102% of the
HX8K, **197 cells from placing**.

Nothing about the schedule or the arithmetic moves - the same operands reach
the same service on the same phases - so `make test-psg` is unchanged at
618/1,275 and 2,443/7,654, Celeste music 20 is byte-identical over 400,000
samples, the frozen matrix is 59/59 byte-exact against PICO-8 AND
byte-identical against the anchor, and PICO-8 fidelity is within tolerance on
all five entry points.

**The reusable form: when two arms of a wide selector want the same
expression, select its OPERANDS.** The law says selection eats arithmetic; the
corollary is that selection should happen where the values are narrowest.

### 30. Make the schedule clock-invariant and select `/5`

The failed clock sweep in R.52 changed the number of sequencer advances
available between samples. Long pattern chains eventually crossed a sample
boundary in a different state, so changing the clock in either direction
changed the render even though the 618-clock sample walk still met its own
deadline. R.54 fixes that mechanism rather than treating the old 28.125 MHz
point as a frequency floor.

The full schedule now grants exactly 272 non-walk sequencer advances after
every `sample_en`. The common value uses an eight-bit counter seeded at 239
plus one phase bit; generic `SEQ_BUDGET` values retain the direct counter. A
held sequencer state does not identify the byte previously issued to the
synchronous audio RAM, so `psg_aram` preserves `last_addr` across arbitrary
credit freezes and replays that address. A second collision surfaced at the
shared constants/control ROM: a CPU `$22` fade lookup can displace a walker
control word. The fade lookup takes priority and `psg_walk` holds one phase
while the displaced control word is reissued.

The clock choices are then arithmetic rather than empirical fixed points:

| divider | PSG clock | minimum clocks/sample | after 618 + 272 | decision |
| --- | ---: | ---: | ---: | --- |
| `/4` | 28.125 MHz | 1,275 | 385 spare | exact, higher power/work |
| `/5` | 22.5 MHz | 1,020 | 130 spare | **accepted** |
| `/6` | 18.75 MHz | 850 | 40 short | rejected |

The non-power-of-two divider is a registered modulo counter clocked on the
112.5 MHz PLL's falling edge. For `/5`, the output is high for two source
cycles and low for three; every PSG rising edge is therefore on a PLL falling
phase and cannot coincide with the CPU/master rising edge on a PLL rising
phase. This is a phase relationship, not a synchronizer: the closest launch to
capture separation is only half a PLL period, about 4.44 ns. The current bus
level is stable for at least `floor(32/5) = 6` complete PSG clocks, but any PLL,
divider, or CPU-bus timing change must re-analyse and constrain this crossing.
No synchronizer was added at this checkpoint because placement leaves only
seven logic cells spare.

At source fingerprint `44f732e11f49`, Yosys maps 6,723 LUT4s, 1,690 carries,
1,464 flip-flops and 13 EBRs. Seed-1 place-and-route uses 7,673/7,680 logic
cells and routes at 34.94 MHz. The report therefore fails its generic 50 MHz
request but clears the selected 22.5 MHz clock by 12.44 MHz.

`make test-psg` passes at 618/1,020 sample clocks and 4,791/6,123 tick-preparation
clocks, with 1,332 spare and zero late flips. The frozen oracle is 59/59
byte-identical. A final 400,000-sample Celeste music-0 comparison at 28.125 and
22.5 MHz is byte-identical with SHA-256
`970b0691a90202d2be83ef158be4c750adc4ec66b4528454c9a80abb581737d5`;
host render time falls from 57.612 s to 46.830 s (18.7%, non-normative).
`make test-clocks` covers `/4`, `/5` and `/6` period, duty and phase, and the
five-frame Celeste smoke reports active, non-constant audio. A `/6` structural
run aborts on the explicit insufficient-credit assertion rather than silently
changing the render.

### 31. Hold the synchronous audio-RAM output across credit freezes

R.54 restored the 13-bit `psg_aram.last_addr` register because an arbitrary
sequencer-credit freeze can hold a state whose current `seq_addr` already
names the following byte, not the byte issued on the previous executed state.
The address is unnecessary if the EBR output itself is held. Ordinary
`seq_hold` cycles now deassert the audio RAM read clock-enable, preserving
`seq_q`; `syn_rd` still forces a wavetable read, and the following registered
`replay` cycle forces one read of the held `seq_addr` before the output is held
again. This is distinct from R.43's synthesis-borrow-only contract and changes
neither the sequencer state nor the 618+272 schedule.

At fingerprint `83ebc6c79f11`, all nine audio-RAM blocks infer their `RCLKE`
from `aram_rd`; no RAM is demoted and the standalone total remains 13 EBRs.
Yosys maps 6,705 LUT4s, 1,690 carries and 1,451 flip-flops, reductions of 18
LUT4s and 13 flops from R.54. Seed-1 placement uses 7,642/7,680 LCs, 31 fewer
than R.54 and 38 below capacity. The default router repeats a fixed
7,398-arc impasse, while `router2` completes normally on the same seed and
JSON at 33.21 MHz, clearing 22.5 MHz by 10.71 MHz.

`make test-psg` remains at 618/1,020 sample clocks and 4,791/6,123 tick clocks,
with 1,332 spare and zero late flips; the frozen renders remain 59/59
byte-identical. The schedule did not move, so no new cross-clock render is
required beyond R.54's 400,000-sample proof. A forced Verilator 5.050 console
build is warning-clean.

### 32. Decompose the secondary increment by quotient and residue

R.51's published-state form and R.53's direct natural-width rewrite both made
`psg_wave.dq17` larger, closing direct restatements of that cone. R.57 changes
the arithmetic shape. Triangle detune-1 splits `dp = 256*q+r`, applying the
193 coefficient to five-bit `q` and evaluating the low-byte residue with a
small correction. Phaser detune-1 splits at 128, reducing the six-scale
correction to `3*q + ceil(3*r/128)`. The `/64`, `/128` and `/256` cases become
high quotients plus one low-residue bit, and all correction-bearing modes feed
one selected 14-bit subtract.

`tools/psg_dq_model.py` proves the quotient/remainder form against the shipped
expressions for all 524,288 wavetable/wave/mode/increment tuples; the maximum
remains 16,254. At fingerprint `0e5e9be9e713`, Yosys maps 6,705 LUT4s, 1,663
carries, 1,451 flops and 13 EBRs. LUT/flop totals are unchanged from R.55, but
27 carries and 48 total mapped submodules retire. Seed-1 `router2` placement
uses 7,619/7,680 LCs, 23 fewer than R.55, and routes at 33.80 MHz.

The rewrite is combinational and leaves every schedule phase unchanged.
`make test-psg` remains at 618/1,020 sample clocks and 4,791/6,123 tick clocks,
with 1,332 spare and zero late flips; all 59 frozen renders are byte-identical,
and the forced Verilator 5.050 console build is warning-clean.

### 33. Close the exact `/6` schedule

R.54 made sequencer progress clock-invariant but left `/6` exactly 40 clocks
short: eight 73-phase visits cost 584 clocks, the full walk cost 618, and the
fixed 272 sequencer credits made a 890-clock job against the 850-clock minimum.
R.58 removes exactly five phases per visit without changing either credit count
or arithmetic.

The retained schedule moves `PSTOR` from 53 to 51 and stores oscillator words
on phases 51..64. The blend still launches at `CAP_W75` on phase 61, but W84
consumes it on its first readable phase at 65. Dampen and filter commit on that
same edge from the combinational blend result; the obsolete `smp_a` staging
phase is gone. Persistent low-pass writes use phases 66 and 67, and phase 67
also closes the slot and launches the fold (`PFOLD=PLAST=67`). Every streamed
oscillator word is therefore finalized before its write, and the final state
write is not lost to slot close.

An earlier shape launched blend at `CAP_W51`. It became render-exact after a
stale bypass was corrected but mapped at 6,840 LUT4s and could not place at
7,768 LCs. Launching at `CAP_W75` keeps the operand cone local and is the
retained form.

At final RTL fingerprint `85d2e30c4873`, forced synthesis after changing the
standalone target's authoritative clock parameter maps 6,708 LUT4s, 1,663
carries, 1,451 flip-flops and 13 EBRs. Seed-1 placement uses 7,625/7,680 LCs.
Router2's ordinary weights settle at one overused wire; its alternate weights
route the same seed and netlist at 31.30 MHz, clearing 18.75 MHz by 12.55 MHz.

`make test-psg` reports 578/850 sample clocks and 4,070/5,103 tick-preparation
clocks with 1,033 spare, zero late flips and no lost state writes. The frozen
matrix is 59/59 byte-identical at explicit 18.75 MHz. The multiplier and dq17
models, lifetime audit and `/4`/`/5`/`/6` clock bench pass. A forced Verilator
5.050 Celeste build is warning-clean, the five-frame smoke reports active,
non-constant audio, and the regenerated schedule visualization reports 68
hardware phases without stale attribution warnings.

This is an exact-bound operating point: 578 walk clocks plus 272 sequencer
credits consume all 850 clocks in the minimum `/6` sample interval. Any walk
growth, credit change, PLL change, or CPU-crossing change must re-open the
clock decision. The Tang Nano path remains on its independent 112.5 MHz PSG
clock until that board has separate clock-routing and placement evidence.

### 34. Publish the effect increment when it becomes final

The effect engine retained `arp_r` for one reason: its final 13-bit increment
had to survive until P_W0/P_W1 wrote the inactive sounding bank. The current
direct-publication contract makes that lifetime unnecessary. P_W0/P_W1 now
run immediately after the increment becomes final, then return to the same
K_FX micro-step; K_FX enters P_W2/P_W3 at its former publication point. The
four writes and the atomic bank flip are unchanged, and the total sequencer
state count does not grow.

Slide publishes while its final synchronous table word and multiplier result
are held. Arpeggio effects hold the arpeggiated pitch-table address through
both writes. Every other effect publishes from the ordinary pitch lookup,
vibrato result or completed divide result. The previous-volume register is
also unnecessary: its two possible source fields are stable for the complete
effect pass and feed the same subtract and final add directly.

At fingerprint `81eb0cefc834`, Yosys maps 6,665 LUT4s, 1,662 carries, 1,435
flops and 13 EBRs, reductions of 43 LUT4s, one carry and 16 flops from R.58.
Seed-1 placement uses 7,586/7,680 LCs, 39 fewer than R.58, and alternate-weight
router2 routes at 34.42 MHz against the selected 18.75 MHz clock. The placed
delta is inside the known mapping-sensitivity band, but the independent
LUT/flop reductions establish that the mechanism is a real structural saving.

`make test-psg` remains at the exact 578/850 sample contract and
4,070/5,103 tick-preparation clocks with 1,033 spare and zero late flips. The
59-case frozen set is byte-identical at explicit 18.75 MHz, and the forced
Verilator 5.050 console build is warning-clean. This is the address-selected
storage law paying on a complete effect lifetime; it does not justify folding
the remaining `vol_r` work into an arbitrary live register, the mechanism
already closed by the lifetime-merge experiments.

### 35. Narrow the multiplier around its current real operands

R.11's 21-bit multiplier boundary was correct for the older request contract:
the service then received a shift-scaled pitch increment whose ceiling was
`0x1ce0 << 8`. The current request mux receives the unshifted table value and
restores its fixed-point position only in each named result slice. Auditing all
live arms gives an 18-bit signed ceiling: waveform and blend operands include
the limiting `-131072`, the noise J operand is 17 bits, slide fraction is 16,
and every sequencer pitch or volume operand is at most 13 bits.

The retained service therefore narrows its magnitude from 21 to 18 bits and
narrows the accumulator and radix-4 add path with it. The external `m_res`
remains 34 bits with the same landing positions; the now-impossible high bits
are explicit zero-extension, so no consumer slice or schedule phase moves.
`tools/psg_mul_model.py` reads the live radix, iteration counts, pre-shift and
accumulator boundary from RTL and proves every mode, both signs, corner
operands, overflow bounds and every named consume offset under the new
`|A| <= 2^17` magnitude bound.

At RTL fingerprint `95095b93cabb`, Yosys maps 6,648 LUT4s, 1,656 carries,
1,429 flip-flops and 13 EBRs. Relative to R.59 this is -17 LUT4s, -6 carries
and -6 flops. Seed-1 placement falls 7,586 -> **7,566/7,680 logic cells**;
router2 routes at **33.87 MHz**, clearing the selected 18.75 MHz clock by
15.12 MHz. The exact `/6` schedule is unchanged: `make test-psg` reports
578/850 sample clocks and 4,070/5,103 tick-preparation clocks with zero late
flips. The 59 frozen renders remain byte-identical at 18.75 MHz, and the forced
Verilator 5.050 console build is warning-clean.

### 36. Direct consumption does not retire the volume family cheaply

R.61 tested whether the effect program could remove its remaining twelve-bit
`vol_r` by consuming the persistent divider and multiplier results directly.
The initial voice fields are stable across the pass, `d_res` survives every
effect and instrument consumer, and `m_res` survives through the final P_W3
publication. The candidate therefore removed all four `vol_r` writes without
moving a request, microstep, publication word, sample phase or sequencer
credit.

The lifetime proof was correct but the packing hypothesis was not. Candidate
fingerprint `f7b2e1e9705b` maps 6,674 LUT4s, 1,655 carries, 1,417 flops and 13
EBRs: twelve flops retire, but the direct value selection adds 26 LUT4s.
Seed-1 placement rises 7,566 -> **7,590 LCs (+24)** and routing completes at
**30.79 MHz**, still above 18.75 MHz but worse than the area baseline. The
structural schedule remains exactly 578+272 = 850 clocks, `make test-psg`
reports 4,070/5,103 tick-preparation clocks with 1,033 spare and zero late
flips, the frozen set is 59/59 byte-identical at 18.75 MHz, and the forced
Verilator 5.050 console build is warning-clean.

R.61 is rejected and the RTL is restored exactly to R.60 fingerprint
`95095b93cabb`. Persistent service storage is not free storage when every
consumer needs a wider state/value selection cone. Reopen this shape only if
the effect order, service-result persistence or publication cone changes.

### 37. Shape-selected wave payloads cost more than parallel fields

R.62 applied the same question to one wave-pipeline boundary. `z_lin_r` and
`tri4_r` were replaced by one shape-selected 18-bit payload;
`t_pre_r`/`t_h7_r`/`t_h15_r`/`org_h_r` became one selected 15-bit divide
payload; and `tilt_hi_r` was derived from the registered shape tag. The source
therefore removed 48 fields at one common pipeline edge, with the downstream
shape selection removed at the same time. This is a stronger test than an
arbitrary lifetime merge because the values are mutually exclusive views of
one scheduled context.

The arithmetic and pipeline timing remain exact, but the mapper exposes the
same selection cost. Candidate fingerprint `fb9c4d6512fe` maps 6,702 LUT4s,
1,656 carries, 1,400 flops and 13 EBRs: only 29 physical flops retire while 54
LUT4s are added. Seed-1 placement rises 7,566 -> **7,591 LCs (+25)** and
routes at **33.13 MHz**. `make test-psg` is unchanged at 578+272 clocks with
zero late flips, the dq17 model passes all 524,288 cases, and the 59 frozen
renders are byte-identical at 18.75 MHz.

R.62 is rejected and reverted exactly to `95095b93cabb`. R.61 and R.62 now
close selector-fed register retirement on both the sequencer and waveform
sides until the relevant fanout or pipeline boundaries change.

### 38. Sharing the magnitude conversion with the accumulator adder loses

R.63 selected the multiplier's 21-bit accumulator-adder operands between the
busy radix step and the cycle-disjoint request-time expression
`(A ^ sign) + sign`. The cycle-exact model proves all signed magnitudes,
radices, modes, result landings and consumer slices, so the transformation is
arithmetically exact and schedule-neutral.

Candidate fingerprint `5ee62b672b50` maps 6,668 LUT4s, 1,639 carries, 1,429
flops and 13 EBRs. The intended 17 carry cells retire, but selecting the two
adder roles adds 20 LUT4s. Seed-1 placement rises 7,566 -> **7,610 LCs (+44)**
and routes at **31.10 MHz**. The RTL is reverted exactly to `95095b93cabb`
before render testing because the area acceptance gate is already false. Only
the materially different radix-digit-adder sharing shape remains worth one
measurement; a second selector-cost result closes the mechanism.

### 39. Measure magnitude conversion on the radix-digit adder

R.64 is the second and final current adder-sharing shape. The request load
edge is cycle-disjoint from every radix step, and the digit adder is active
only for `m_d == 3`, where it forms `A + 2A`. On a real idle request it can
instead form the exact magnitude `(A ^ sign) + sign`, with `m_a` loading the
shared result. Unlike R.63, the accumulator adder and its busy-path operands
remain untouched.

The baseline is the restored R.60 fingerprint `95095b93cabb`: 6,648 LUT4,
1,656 carries, 1,429 flops, 13 EBRs and 7,566 placed LCs, with seed-1 routing
at 34.06 MHz against the selected 18.75 MHz clock. The cycle-exact multiplier
model must pass before synthesis. If mapped LUT/carry resources and placed LCs
do not both improve, revert before the render battery and close current
arithmetic-adder sharing under the two-variant stop rule.

The model passes every sign, mode, landing, overflow bound and named result
slice, but candidate fingerprint `536732e78c3d` maps 6,681 LUT4s, 1,640
carries, 1,429 flops and 13 EBRs. The intended 16 carry cells retire, while
the selected digit-adder inputs add 33 LUT4s and increase the multiplier's
unpackable-flop count. Seed-1 placement rises 7,566 -> **7,609 LCs (+43)**
and routes at 33.87 MHz. The RTL is reverted exactly to `95095b93cabb` before
render testing. R.63 and R.64 are the two materially different adder-sharing
placements and both lose to selector cost, so this mechanism is closed until
the digit arithmetic, request boundary or mapper lowering changes.

### 40. Audit the remaining effect-volume value width

R.65 tests an invisible bound in the remaining `vol_r` family rather than
removing its storage. Every initial and previous volume is a three-bit value
scaled by 256, so the maximum is 1,792. Effect 1 stays between its two
endpoints, effects 4 and 5 attenuate by a fraction no greater than one,
instrument scaling is at most 7/7, and music gain is `(gain+1)/256` with
`gain <= 255`. The complete value path therefore fits 11 unsigned bits even
though the signed endpoint difference still needs 12 bits.

Before RTL moves, enumerate every valid effect speed/count pair, endpoint,
instrument volume and music gain, and require every old 12-bit result to equal
its 11-bit form with bit 11 clear. Then narrow the internal value carriers and
constant consumer slices while preserving the published 12-bit field by zero
extension. The R.60 baseline is `95095b93cabb`: 6,648 LUT4s, 1,656 carries,
1,429 flops, 13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Reject if the
bound fails or mapped/placed area does not improve.

The exhaustive proof covers 6,315,840 valid effect cases and every instrument
volume and music gain. It confirms a `0..0x700` range at every stage, bit 11
always clear and a 12-bit signed endpoint difference. Candidate fingerprint
`a15823bc80b2` nevertheless maps 6,655 LUT4s, 1,651 carries, 1,428 flops and
13 EBRs: the single flop and five carries removed cost seven LUT4s. Seed-1
placement rises 7,566 -> **7,572 LCs (+6)**, and the router then stalls at
7,819 unresolved arcs. It is terminated and the RTL reverted exactly to
`95095b93cabb` before functional/render testing because both deterministic
LUT area and binding placement already fail. The source bound is real, but
Yosys already absorbs its high bit through the existing selected arithmetic.

### 41. Reuse the slide affine's next-stage register

R.66 is an adjacent-stage lifetime retirement inside one arithmetic family.
`sl_rlo` holds the constants ROM's 16-bit low word from `K_SL5` through the
`K_SL6` combinational `sl_u` evaluation. The 18-bit `sl_uhi` register is dead
during that interval and is wholly overwritten with `sl_u[29:12]` on the
`K_SL6` edge. Loading `{2'b0,crom_q}` into `sl_uhi` at `K_SL5` therefore lets
`sl_u` read `sl_uhi[15:0]` and removes `sl_rlo` without changing an operand,
clock, truncation point or consumer.

Unlike the rejected cross-family walker merges, both roles are consecutive
stages of the same affine and share the same downstream family. Baseline R.60
is fingerprint `95095b93cabb`: 6,648 LUT4s, 1,656 carries, 1,429 flops,
13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Reject if the added host write
arm costs back the register in LUT or placed fabric.

Candidate fingerprint `034fb20afb4e` retires the complete 16-bit `sl_rlo`
register, but maps 6,665 LUT4s, 1,650 carries, 1,413 flops and 13 EBRs. The
flop and carry reductions are real; so is the 17-LUT increase from selecting
the two `sl_uhi` write roles. Seed-1 placement falls only 7,566 -> **7,557
LCs (-9)** and routes at 34.29 MHz. Since the placed movement is inside the
known mapping-sensitivity band and deterministic LUT area regresses, R.66 is
rejected and reverted exactly to `95095b93cabb` before render testing. The
adjacent lifetime alone is insufficient; the surrounding affine stage must
also disappear for this reuse to pay.

### 42. Price two spare EBRs against the `/7` reciprocal cone

R.67 reverses only the tilted-saw part of R.27's second-fold condensation.
For every reachable phase, the existing first fold gives
`x/7 = 73*h + y/7`, `h=x>>9`, `y=h+x[8:0]`; exhaustive enumeration bounds
`x <= 172,001` and `y <= 844`. A direct 1,024x7 table therefore supplies the
exact remainder quotient in two EBRs, on the same registered pipeline edge.
The `/3` and `/15` fields remain in the 256x15 condensed block; the `/7` path
stops participating in their second-fold address and extra-quotient term.

This intentionally spends all available block headroom (13 -> 15) in pursuit
of the binding LC resource. R.60 is the baseline at fingerprint
`95095b93cabb`: 6,648 LUT4s, 1,656 carries, 1,429 flops, 13 EBRs, 7,566 placed
LCs and 34.06 MHz routed. Retain only if the partial reversal reduces mapped
logic and placed LCs while preserving the pipeline and render exactly.

Candidate fingerprint `b3408a401fff` infers the intended two additional EBRs
and retains the exact pipeline, but maps 6,737 LUT4s, 1,655 carries, 1,429
flops and 15 EBRs. The second registered table port and quotient selection add
89 LUT4s while removing only one carry. Seed-1 placement rises 7,566 ->
**7,652 LCs (+86)** and routes at 32.13 MHz. The partial reversal is therefore
rejected and reverted exactly to `95095b93cabb` before structural/render
testing. R.27's favourable whole-partition average cannot be spent one divisor
at a time while the condensed port remains; any retry must replace a complete
port/selection partition, not add a parallel one.

### 43. Retire the complete full-schedule phase decode

R.68 is the total-domain form that R.29 explicitly left open. R.29 moved only
the memory addresses and enables into a table while the record-load cases,
store-data selection, late writes, final close and noise-request phases still
decoded `pph`. That partial migration reduced the pre-map count but increased
mapped LUTs because abc9 still had to cover the shared decode fabric.

The new 128x16 auxiliary word migrates every full-schedule consumer together:

- bits 4:0: read code (`0` none, `1..14` oscillator words 0..13, `15..18`
  sounding words 0..3; the active bank is applied to the latter code);
- bits 9:5: write code (`0` none, `1..14` ordinary oscillator words 0..13,
  `15` the late `s_lp` write to word 5, `16` the late/final `PSG_OSC_W14`
  write to word 4);
- bits 13:10: load code (`0` none, `1..14` oscillator destinations, `15`
  sounding destination); for code 15 the current read code's low two bits
  identify the preceding synchronous sounding word, with zero wrapping to the
  fourth word;
- bits 14 and 15: the PNZ_OLD and PNZ_LIVE multiplier requests.

Write code 16 also identifies the final phase for slot close and fold launch;
write codes 1..14 select the existing oscillator-store payload by code rather
than by `pph-PSTOR`. The auxiliary memory prefetches `pph_nxt`, remains primed
with word zero while idle, and is independent of the shared constants/control
port. `REALTIME_PREVIEW` deliberately keeps its direct `pph` schedule.

Fresh forced R.60 baseline before any R.68 RTL edit: fingerprint
`95095b93cabb`, 6,648 LUT4s, 1,656 carries, 1,429 flops, 13 EBRs and
7,566/7,680 placed LCs; seed-1 routes at 34.06 MHz against the selected
18.75 MHz clock. R.68a fingerprint `293899b6ce84` infers one extra EBR and
maps 6,676 LUT4s, 1,636 carries, 1,429 flops and 14 EBRs. Placement is 7,560
LCs and routing reaches 31.93 MHz. The -6 placed movement is inside the known
mapping-sensitivity band while the deterministic LUT count regresses by 28,
so R.68a fails the first gate and receives no long render test.

R.68b was the second and final encoding variant. R.29 measured its
absolute-write-address word 41 LUTs smaller than the offset-address form.
Ordinary write codes therefore become absolute record offsets 10..23, codes
1 and 2 identify the late `s_lp` and final `PSG_OSC_W14` writes, and the store
payload is selected directly by the absolute code. This removes both the
offset-to-address adder and the full schedule's store-index subtract. Candidate
fingerprint `820b4e170776` maps 6,663 LUT4s, 1,629 carries, 1,429 flops and 14
EBRs. It places at 7,538 LCs and reaches 35.66 MHz after placement; routing is
stopped after two million iterations because mapped LUTs already regress by
15. The -28 placed movement is still inside mapping sensitivity and cannot
rescue the deterministic area failure.

R.68 is rejected and reverted exactly to R.60 before structural/render tests.
Both materially different write encodings increase LUT area, so complete
auxiliary phase decode is closed under the two-variant stop rule. The result
also strengthens R.29: even total-domain retirement does not repay an extra
registered table output and its destination selection on this netlist. Reopen
only if the schedule, record layout, encoding capacity or mapper changes.

### 44. Overlay disjoint phase classes in the existing control word

R.69 removes the cost R.68 could not repay: no new memory, address port or
registered output. The current 16-bit one-hot control word has only one live
action per phase, while the record load, early action and record store windows
are disjoint. The same physical word can therefore be a tagged union:

- class 0: idle;
- class 1: bits 4:0 absolute record-read code and bits 8:5 load code;
- class 2: ten early one-hot actions in bits 9:0 and PNZ_OLD/PNZ_LIVE in bits
  10/11;
- class 3: bits 4:0 absolute write code and bits 8:5 the four late one-hot
  actions.

Class occupies bits 15:14. No opcode decoder is introduced: each class exposes
direct bit fields, and the four late actions reconstruct the existing one-hot
positions W40/W51/W75/W84. Normal writes use absolute oscillator offsets
10..23; codes 1 and 2 mark the late `s_lp` and final `PSG_OSC_W14` writes.
Class 3 with write code zero carries W84 after the ordinary store window.

The shared constants port cannot deliver word zero on the first phase because
the sequencer owned the preceding read. Phase zero therefore keeps one direct
oscillator-word-0 read and gates the stale ROM word to class 0. From phase one
onward `pph_nxt` supplies the class word already used by the action schedule.
Preview retains its direct schedule.

This is not a retry of R.29 or R.68 under the same condition: both paid another
registered EBR output, while R.69 overlays disjoint fields in the already-paid
port. Fresh R.60 baseline is fingerprint `95095b93cabb`, 6,648 LUT4s, 1,656
carries, 1,429 flops, 13 EBRs, 7,566 placed LCs and 34.06 MHz routed.

R.69a fingerprint `9bbdf431ee0b` maps 6,652 LUT4s, 1,632 carries, 1,429 flops
and 13 EBRs. Placement falls to 7,534 LCs and routing reaches 33.88 MHz, but
the -32 placed delta remains inside mapping sensitivity while the deterministic
LUT count regresses by four. Long tests are skipped.

R.69b was the final encoding variant. Three one-hot class bits leave 13
payload bits, still enough for the 12-bit early-action class and the nine-bit
read/write classes, while eliminating all binary-class equality comparators.
Candidate fingerprint `cd68339eaeb4` maps 6,698 LUT4s, 1,636 carries, 1,429
flops and 13 EBRs. Seed-1 placement regresses to 7,576 LCs and routing reaches
31.61 MHz. The +50 mapped LUT and +10 placed-cell regressions fail both area
gates, so R.69b receives no long functional/render test and is reverted
exactly to R.60 fingerprint `95095b93cabb`. The two variants close
existing-word phase overlays until the class partition, phase-zero port
ownership, schedule or mapper changes. The exact 578+272 `/6` schedule did
not grow.

### 45. Replace the fold correction lifetime with a quotient table

R.70 attacks the two largest remaining fold-local mapped cones together:
`f_over` and `fx_r` account for roughly 250 LUT4s in the R.60 census, and
twelve of `fx_r`'s flops are unpackable. They persist because the corrected
shift-series divider destroys the quotient operand while still needing the
original excess to recover its remainder.

An exact representation removes that dependency. Write a reachable excess as
`x = 256*h + l`. Since `256 = 51*5 + 1`,
`floor(x/5) = 51*h + floor((h+l)/5)`. Complete enumeration covers all 40,961
reachable excess values and all 131,071 possible `soft_add` pair sums. It
also proves `h <= 160`, the small quotient-table index `h+l <= 414`, and the
final quotient <=8,192.

One 512x7 EBR supplies `floor((h+l)/5)`. The selected fold-stack word first
holds the detected excess and then carries `3*h`, `51*h`, the quotient and
the signed final value through the existing 18-bit phase ALU. The 18-bit
`fx_r`, `f_over` and the old correction series disappear; only one sign bit
survives. The worst underflow path shortens from eleven microsteps to nine,
so the exact `/6` sample deadline does not spend another clock. This differs
from R.19/R.20: those reused destinations inside the same quotient series and
could not retire the original excess, while R.70 changes the mathematical
representation and deliberately spends one of the two EBRs available under
the change ceiling.

The baseline is restored R.60 fingerprint `95095b93cabb`: 6,648 LUT4s, 1,656
carries, 1,429 flops, 13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Retain
only if mapped LUT area and placed LCs both fall at no more than 15 EBRs, the
exhaustive arithmetic and exact 578+272 schedule pass, all 59 renders remain
byte-identical at 18.75 MHz, the application build is warning-clean and
routed Fmax remains above 18.75 MHz.

The retained candidate is fingerprint `6e8aa593ff4f`. Yosys maps 6,589 LUT4s,
1,664 carries, 1,410 flops and 14 EBRs: -59 LUT4s, +8 carries, -19 flops and
one deliberately spent block against R.60. The census reports 524 unpackable
flops instead of 547. Seed-1 place-and-route uses 7,488/7,680 logic cells,
78 fewer than R.60, and routes at 35.01 MHz, clearing the selected 18.75 MHz
clock by 16.26 MHz. The candidate therefore improves both required area
surfaces while staying below the 15-EBR ceiling.

The proof now lives in `tools/psg_hw_forms.py` and runs through
`make test-psg-fold`, which is a prerequisite of `make test-psg`. It covers
all 40,961 reachable excesses and all 131,071 signed-int16 pair sums, with
`h <= 160`, table address `h+l <= 414`, seven-bit table quotient <=82 and
final quotient <=8,192. The integrated PSG suite passes the noise gate,
32 audio-analysis tests and every structural case. Its observed longest
synthesis path is 572/850 clocks while the fixed clock contract remains
exactly 578 walker plus 272 sequencer clocks; tick preparation is
4,056/5,103 with 1,047 spare and zero late flips.

The explicit 18.75 MHz render gate is 59/59 byte-identical. A forced
Verilator 5.050 console rebuild emits no HDL warnings, and the five-frame
Celeste smoke produces 3,668 active samples over 1,073 distinct levels.
R.70 is accepted. It does not add margin to the `/6` minimum interval:
schedule or sequencer-credit growth still re-opens the clock decision.

### 46. Stream the preceding secondary phase from the state store

R.71 targets `old_q0`, whose 17-bit working register and input/fanout cone
account for 236 LUT4s in the R.70 census. The value is already persistent
state, split between oscillator words 1 and 7, but its low 16 bits are needed
only when the old-secondary context is issued and when that phase advances.
State-memory reads are idle after the sounding words load and before the next
slot; unused per-slot word 33 can therefore hold the low phase in the existing
512x16 memory without another EBR.

The proposed schedule reads word 33 at phase 31 for the phase-32 `CAP_W3`
issue, then holds it through the store window. A `CAP_W0` restart first writes
the current secondary phase to that word. Only `old_q0[16]` remains in a flop,
packed beside `bl_cnt`; the existing old-context `dq17` add supplies the high
bit at the word-7 store and the low word at a free phase after the ordinary
oscillator stores. This preserves the pre-increment value seen by the old
waveform and the post-increment value persisted for the next sample.

Unlike R.51, no derived increment or extra publication port is introduced.
The candidate moves an existing phase lifetime onto address-selected storage
and retains the arithmetic and wave issue. Baseline R.70 is fingerprint
`6e8aa593ff4f`: 6,589 LUT4s, 1,664 carries, 1,410 flops, 14 EBRs,
7,488 placed LCs and 35.01 MHz. It is accepted only if both mapped LUT/flop
area and placed LCs fall, EBR stays 14, and the exact `/6`, render, application
and routed-timing gates remain clean.

Three state-port shapes close the experiment without retention. R.71a uses the
bounded phase-31..65 word-33 read window. Fingerprint `0dc564680a73` passes the
exact schedule and 59-render gates and maps 6,577 LUT4s, 1,676 carries, 1,394
flops and 14 EBRs, but placement rises 7,488 -> 7,493 LCs; it fails the binding
area gate despite routing at 30.55 MHz. R.71b lends the read port to word 33 for
the complete idle post-parameter window, eliminating the range decoder. At
`8b4650beca18` it maps 6,558 LUT4s, 1,665 carries, 1,394 flops and 14 EBRs and
places at 7,452 LCs. Both lint flavours, the 572/850-clock structural gate and
59/59 byte regression pass, but seed-1 routing remains stationary at 1,000
unresolved arcs after ten minutes. Requesting 18.75 MHz directly reaches the
same placement checksum and deadlock, proving congestion rather than a timing
threshold failure. R.71c retains only the phase-31 lower bound; fingerprint
`603f5827f568` maps 6,596 LUT4s, 1,671 carries, 1,394 flops and 14 EBRs and
therefore fails mapped area before placement.

The family is rejected and closed under the three-variant evidence. Restored
R.70 plus preview-only P.1 is fingerprint `d6b3811ce178`; full-schedule
synthesis exactly reproduces 6,589 LUT4s, 1,664 carries, 1,410 flops, 524
unpackable flops, 14 EBRs, 7,488 placed LCs and 35.01 MHz. Retry only after the
old-secondary issue, state-port schedule, oscillator-record layout or mapper
changes.

### 47. Restore preview secondary-oscillator timing before more area work

The interactive console alone instantiates `REALTIME_PREVIEW=1`; the hardware
oracle and synthesis schedule instantiate zero. A fresh 28.125 MHz preview
render of Celeste music 0 fails independently of clock capacity: each music
channel and the combined mix has zero voiced-window pitch agreement with the
hardware schedule. Stable notes move one octave upward and the combined level
rises by roughly 2--3 dB through the main music bands. This is the reported
"missing channels" soundtrack defect, not a `/6` hardware-clock consequence.

The preview captures `smp_a` and `smp_b` at `PWORK+1` and `PWORK+2`. Wavetable
reads already line up with those captures, but computed-wave `iss_sec` is also
asserted at `PWORK+1`; its two-stage result does not reach `z_eval` until after
the `smp_b` edge. Both registers therefore receive the main oscillator. Issue
the secondary context at `PWORK` and advance `s_phase2` on the same phase so
the existing captures receive primary then secondary for computed and table
waves. Preview does not consume the later old-main/old-secondary results, so
their issue signals are zero in this mode rather than perturbing the pipeline.

The first timing correction exposes an independent representation regression.
Commit `6b28873` removed the low eight primary-phase bits and retained the
increment at bit 7 upward. Full mode therefore advances the 16-bit phase view
by `einc[13:1]`; preview still advances it by all fourteen retained bits, the
spelling appropriate only when `s_phase` was the old 24-bit accumulator. That
doubles the preview fundamental and explains the stable octave substitution.
Preview must use the same high-phase increment as full mode.

This repair is isolated from R.71 and carries no area claim. Its proof surface
is fresh per-channel and combined Celeste preview renders at both the generous
correctness clock and the console clock, warning-clean full/preview lint,
`make test-psg`, and unchanged 59/59 hardware-schedule renders at 18.75 MHz.
R.71 stays paused until this preview item is closed.

The retained repair moves the secondary issue/advance one phase earlier,
disables the unused old-context preview issues, and changes the primary
preview increment to `einc[13:1]`. The latter is the decisive octave fix; the
former restores the missing secondary/detune component. Both are eliminated
from the hardware lowering by `REALTIME_PREVIEW=0`.

The preview checker now creates true per-channel audio images by setting the
PICO-8 disabled bit in the other three pattern bytes; changing `$21` never did
that because it is advisory reservation state. The combined mix and active
channels pass pitch, RMS and activity gates at both 1,275 and 159 clocks per
sample. Hardware remains 59/59 byte-identical at 18.75 MHz, the structural
suite and both lint flavours pass, and a 300-frame Celeste console run produces
five seconds of active audio at 90.39 fps. P.1 is closed and R.71 may resume.

### 48. Carried signed-digit radix-4 recode is larger

After R.71 restores, the two largest mapped families are again the shared
multiplier's `m_a` and `m_p` cones at 442 and 372 LUT4s. The radix-4 step
constructs digit three as `A + 2A`, then adds that 20-bit value to the
accumulator. A carried signed-digit representation removes the first add:
for `t = digit + carry`, use `t` for 0..2, use `-1` with next carry one for 3,
and use zero with next carry one for 4. A final carry supplies the extra high
radix digit. The recurrence must reproduce the complete shipped `m_res` word,
not merely the unaligned product, for all 8/9/10/12-bit and short modes.

This is distinct from R.63 and R.64. Those left the radix digits unchanged and
put request-time conversion or selection onto the existing accumulator adder,
increasing its input mux. R.72 changes the digit set so the `3A` producer can
cease to exist. Proof precedes RTL in `tools/psg_mul_model.py`; an isolated
registered service synthesis must improve LUT/LC area before the integrated
candidate is permitted. The integrated baseline and acceptance surface are
R.70 plus P.1 fingerprint `d6b3811ce178`: 6,589 LUT4s, 1,664 carries, 1,410
flops, 14 EBRs, 7,488 placed LCs, 35.01 MHz, exact 578+272 clocks and 59/59
byte-identical renders.

The mathematical recode is exact. `tools/psg_mul_model.py` compares the
complete fixed-alignment `m_res` word for every legal B at nine A-domain
boundaries and both signs, then sweeps the broad A set at digit-pattern
corners. It observes a signed accumulator range of -43,648..87,296 and an
add/sub range of -174,720..349,440, within the proposed 18- and 20-bit
boundaries. Full and preview lint are warning-clean.

The physical form fails before integration. Under the same registered service
harness, the restored radix-4 baseline maps 157 LUT4s, 55 carries and 119
flops, places in 232 LCs and routes at 119.15 MHz. The carried recurrence maps
215 LUT4s, 73 carries and 122 flops, places in 273 LCs and routes at 107.17
MHz: +58 LUT4s, +18 carries, +3 flops, +41 LCs and -11.98 MHz. Removing the
`3A` producer does not remove an adder overall; the carry state, signed-digit
decode/add-sub path and conditional 34-bit public-result correction are more
expensive. The evidence is saved under `build/psg_mul_r72/`. The candidate is
reverted, and the restored service exactly reproduces the isolated baseline.
No integrated synthesis or render battery is run because the isolated
prerequisite failed. Retry only if the final carry can be absorbed without the
public-result correction/state bit, or if the service boundary or mapper
lowering changes.

### 49. Expose radix-4 as two gated partial products

R.73 keeps the shipped unsigned recurrence and changes only its combinational
spelling. A radix-4 digit is `d[0] + 2*d[1]`, so one step is exactly
`acc + (d[0] ? A : 0) + (d[1] ? 2A : 0)`. The current source instead selects
one `m_add` value and materializes `A+2A` for digit three before adding it to
the accumulator. Exposing both partial products may let the iCE40 mapper absorb
digit selection into a three-operand/carry-save cover without a separate `3A`
producer.

This is distinct from R.63/R.64 because request-time magnitude conversion is
not routed into an existing adder, and distinct from R.72 because the digits
remain unsigned: no carry state, negative digit or public-result correction is
introduced. The registered isolated baseline, reproduced after the R.72
revert, is 157 LUT4s, 55 carries, 119 flops, 232 LCs and 119.15 MHz. The
candidate must improve both isolated LUT and LC area without losing required
timing before integrated synthesis is allowed. If it survives, the complete
R.70+P.1 acceptance surface applies unchanged.

The arithmetic and both lint modes pass, but the physical result is neutral on
the binding resource. The partial-product spelling maps 158 LUT4s, 36 carries
and 119 flops, places in 232 LCs and routes at 121.48 MHz. Against the restored
baseline that is +1 LUT4, -19 carries, unchanged flops and LCs, and +2.33 MHz.
The mapper does infer a different compressor resource mix, but its extra LUT
cover occupies every cell released by the carry reduction. R.73 is rejected
at the isolated gate, retained only as evidence in `build/psg_mul_r73/`, and
the RTL is restored before integrated synthesis. Retry only with a materially
different compressor lowering that removes LUT cover rather than exchanging
carry cells for it.

### 50. Gate repeated foreground-SFX recovery in preview

P.1 proves that the compact schedule renders a steady Celeste music pattern
with the right primary and secondary oscillators. It does not exercise the
foreground half of the eight-slot pool. Celeste auto-picks the lowest channel
that is neither reserved nor busy; with music mask seven its jump effects
repeatedly use foreground slot 3. The reported failure is history-dependent:
after enough jump SFX, most of the soundtrack becomes silent.

P.2 therefore starts from the actual console at its 3,506,580 Hz core clock,
injects repeated jump edges, captures the per-frame foreground/music ownership
trace and writes the console PCM. A compact-schedule regression must cover a
foreground takeover, retriggers while active and after stop, and the final
return to the continuously advancing music slot. The first diagnostic split
is ownership versus synthesis state: if foreground `playing` remains set,
repair the sequencer stop/retrigger contract; if it clears while the music
leaf remains silent, localize the preview oscillator, clear-token or fold
state that survives the slot transition. Hardware lowering remains unchanged
and must stay 59/59 byte-identical.

The failure was neither ownership nor a stale clear token. A sample walk can
displace the sequencer's synchronous state-store read. `state_replay` correctly
reissues the current consume word for the first recovery cycle, but PREVIEW's
serial fold keeps the complete `seq_hold` asserted for two further cycles. The
read scheduler retained EA/ES/publication/V_LD consume addresses only while
`state_replay` was high. In held EA2 it therefore changed from word 2 to word 1
before the FSM could consume word 2; the registered `state_q` became `0x0000`
instead of the stored `0x0020` speed. Celeste's music SFX 11 then advanced one
row per tick rather than every 32 ticks and stopped at row 31, producing the
history-dependent missing channel.

The retained repair defines the address lifetime by the existing complete
hold contract. EA1--EA3, ES1--ES2, PC0--PC3 and the V_LD `tick_issue` selector
now retain their current consume address for all of `seq_hold`, including the
post-replay fold cycles. No state, schedule phase or arithmetic was added.

`make test-psg-preview-recovery` makes the failure deterministic at 3,506,580
Hz. Its synthetic Celeste-shaped 16/32/16-speed mix and the real frozen
`celeste-audio.hex` image each survive 64 foreground SFX-1 retriggers: all
three music leaves are audible and nonzero for 512 visits before and after,
their phases advance, the foreground stops naturally, its final clear token
is acknowledged, and coalesced ticks, delayed publications and dropped
samples are all zero. The P.1 combined/per-channel gate passes at both 1,275
and 159 clocks/sample. Full and PREVIEW lint are warning-clean; `make test-psg`
passes at the exact 578+272 `/6` schedule; and the 18.75 MHz frozen hardware
set remains byte-identical 59/59.

The actual lowercase `game=celeste` console was then rebuilt and run for 1,800
frames with scripted jump input, `--psg-trace` and a console WAV. The trace
contains 25 foreground SFX-1 episodes, the last ending at frame 1,430. Frames
1,500--1,800 contain no foreground owner and retain music ownership on every
frame. The final six seconds remain strongly active (RMS -14.63 dBFS, range
-24,931..22,304); the complete 30-second capture has 37,810 distinct levels
and 15.2 effective bits. Evidence is under `build/psg_p2/`. P.2 is accepted as
a preview-correctness repair with no area claim; the next area hypothesis
remains a separate experiment.

### 51. Multi-pump the multiplier across the related PLL and PSG clocks

R.73's 121.48 MHz is an isolated multiplier result, not the complete PSG's
Fmax. It nevertheless identifies a useful architectural resource: the iCE40
PLL already runs at 112.5 MHz while the accepted full PSG runs at `/6`, or
18.75 MHz. A multiplier clocked from the PLL can perform six internal cycles
per PSG period without asking the full PSG datapath to close at 112.5 MHz.

The implementation boundary follows the ordinary closed-loop multi-cycle-path
CDC pattern. On a slow-domain request, registers capture magnitude, initial
multiplier bits and iteration count and toggle `req`. Two synchronizer stages
deliver `req` to the fast domain. The request payload is held unchanged until
completion, so it is a bundled stable bus rather than a separately synchronized
set of unrelated bits. The fast recurrence holds its completed result and
copies the synchronized request value into `ack`; two slow-domain synchronizer
stages return `ack`. The slow domain declares the result ready only after that
acknowledge. Synchronizer flops carry the `async_reg` attribute, and explicit
timing constraints give the PLL and PSG domains their independent 112.5 MHz
and 18.75 MHz requirements while excluding only the handshake-protected CDC
paths.

This boundary is deliberately phase-independent even though `clocks.sv`
derives every clock from one PLL. It avoids a fabric-generated fast clock,
does not apply a 112.5 MHz requirement to the complete PSG, and does not rely
on a half-PLL-cycle source/destination edge separation for correctness. The
source transaction registers also replace the multiplier's old A holding
register where possible; only initial B/count storage and handshake state are
new fixed costs.

The first comparison is complete-service area, not core-only Fmax. Measure the
current radix-4 recurrence behind this boundary, then a radix-2 recurrence.
The smaller radix-2 core needs up to twelve PLL cycles, roughly two PSG periods
before synchronization overhead, but can still beat the current three-to-six
PSG-clock arithmetic while removing the radix-4 `3A` producer. No integrated
edit is allowed unless the wrapper plus core both close 112.5 MHz and reduce
isolated LCs.

The service has two slow-domain timing meanings. `ready` is the true
acknowledged result and is the contract the walker may use when its schedule is
recompacted. `seq_busy` retains the shipped radix-4 duration for the sequencer,
because R.33 proved that changing the real `m_busy` duration moves 0.26% of one
Celeste track even when every product bit is identical. The padded contract
must never expire before true readiness, and the shared result must not be
overwritten while a padded sequencer consumer is frozen. This separates a
hardware-capacity optimization from an audible sequencer-timing change.

Fresh post-P.2 baseline fingerprint `568c1b5a5f4c` maps 6,614 LUT4s, 1,663
carries, 1,410 flops and 14 EBRs. Seed-1 placement uses 7,511/7,680 LCs and
reports 33.72 MHz after placement in the PSG domain. The dense baseline route
is unresolved when R.74 opens; the experiment therefore uses 7,511 placed LCs
as its initial binding comparison and must report fresh routed results for both
clocks before retention.

The retained implementation makes multi-pumping an explicit elaboration
contract. The iCE40 `/6` board, standalone synthesis target and exact `/6`
regression benches enable it; Tang Nano, PREVIEW and non-18.75 MHz oracle
models keep the original single-clock radix-4 service. The Verilated renderer
similarly compiles six fast-domain evaluations only into the multi-pumped
binary, so PREVIEW does not pay for an unused clock domain.

Icarus compares 6,020 boundary and random transactions in every mode and sign
against the shipped service. Both the radix-2 and radix-4 CDC variants match
the complete 34-bit result and padded busy on every PSG edge. True radix-2
completion takes at most four PSG clocks and never misses the padded contract.
The isolated complete-service results are:

| service | LUT4 | carry | flop | LC | fast Fmax |
| --- | ---: | ---: | ---: | ---: | ---: |
| original single-clock radix-4 | 157 | 55 | 119 | 232 | 119.15 MHz |
| CDC + radix-4 | 171 | 57 | 146 | 257 | 128.24 MHz |
| CDC + radix-2 | 124 | 38 | 146 | 219 | 151.17 MHz |

The complete retained PSG fingerprint is `23897c2534cd`: 6,571 LUT4s, 1,646
carries, 1,436 flops and 14 EBRs. Against P.2 this is -43 LUT4s, -17 carries,
+26 CDC flops and -17 combined LUT+flop cells. Seed-1 placement falls
7,511 -> **7,481 LCs**. router1 repeats the baseline's congestion plateau at
1,000 unresolved arcs; router2 completes normally and reports **116.95 MHz**
for the fast domain and **31.62 MHz** for the PSG domain. The PSG synthesis
target therefore selects router2 explicitly and reports both clocks.

The fixed 578+272 timing contract and every request/consume assertion pass;
the longest observed sample work remains 572/850 clocks and tick preparation
is 4,056/5,103 with 1,047 spare. The 18.75 MHz regression is 59/59
byte-identical. Full and PREVIEW lint are warning-clean. P.1 passes the
combined Celeste tune and every active channel at both 1,275 and 159
clocks/sample; P.2 passes synthetic and frozen-Celeste recovery with no
coalesced ticks, delayed publication or dropped samples. A lowercase
five-frame Celeste build/run produces 3,668 active audio samples. R.74 is
accepted; evidence is saved under `build/psg_mul_r74/`.

### 52. Recompact the walker against acknowledged multiplier readiness

R.75 is a separate schedule experiment after R.74's service-boundary result.
The retained 68-phase visit still carries the single-clock radix-4 spacings:
normal products are consumed six or seven phases after launch and the short
blend product four phases after launch. R.74's closed-loop result is visible
only after the returned acknowledge, and the isolated test proves the normal
radix-2 request never exceeds four PSG busy observations while the short
request never exceeds the shipped three-cycle padding. A normal consumer at
launch+5 and a short consumer at launch+4 therefore remain on the safe side of
the acknowledged boundary without relying on the related clocks' phase.

Keep W0..W6 and the two mode-0 noise requests fixed. Repack the dependent
chain as W15/W26/W27/W40/W51/W75/W84 at pph
38/43/44/49/54/55/59. The wavetable W26 result still precedes W27 by one edge;
W51 still commits both gain arms before W75 reads `blend_diff`; and the short
blend still has four launch-to-consume phases. Stream the 14 oscillator words
at 46..59, then retain the two late dampen writes at 60/61. This changes one
visit from 68 to 62 phases and the fixed eight-slot walk from 578 to 530
clocks, leaving 48 clocks after the unchanged 272 sequencer credits in the
minimum 850-clock `/6` interval.

R.74 fingerprint `23897c2534cd` is the physical baseline: 6,571 LUT4s, 1,646
carries, 1,436 flops, 14 EBRs, 7,481 placed LCs, and routed Fmax 116.95 MHz
fast / 31.62 MHz slow. The candidate must preserve 59/59 bytes, P.1/P.2,
warning-clean lint and both routed clocks without regressing mapped or placed
area. Sequencer requests continue to use `m_seq_busy`; R.75 changes only the
walker's true-ready schedule.

The retained R.75 schedule meets that contract. The seven dependent actions
land at 38/43/44/49/54/55/59, the store window is 46..59, and late dampen
writes close the visit at 60/61. The fixed walk falls **578 -> 530 clocks**;
with the unchanged 272 sequencer credits the `/6` interval now has 48 clocks
of slack. All multiplier request/consume assertions, `make test-psg`, P.1,
P.2, full/PREVIEW lint, and the 59-render 18.75 MHz gate pass; every render is
byte-identical. Yosys maps **6,565 LUT4s, 1,647 carries, 1,436 flops and 14
EBRs**; seed-1 router2 places **7,479 LCs** and routes at **150.53 MHz fast /
33.61 MHz PSG**. Relative to R.74 this is -6 LUT4s, +1 carry, unchanged
flops/EBRs, -2 placed LCs, and substantially more timing margin. R.75 is
accepted independently of the following click repair.

### 53. Remove transition clicks without weakening click-v1

P.3 is a correctness repair separate from R.75's schedule and area claim.
Fresh four-second Celeste SFX-10 renders fail the versioned `click-v1` gate:
the full schedule has 15 events and PREVIEW has 12, while the committed
PICO-8 music-0 reference has none. SFX 10 alternates phaser/noise rows under
effect 5. PREVIEW's largest events land directly on loud phaser row boundaries
(for example sample 5,856, delta -16,128 PCM); the full schedule smooths that
edge, but its corresponding event lands one 183-sample effect tick later
(sample 6,039, delta -14,715 PCM). The same shape repeats on rows 8, 14, 16,
24 and 30. Evidence is under `build/psg_clicks/`.

The active hypothesis is that these are two faces of the transition contract:
PREVIEW publishes a new row without smoothing, while full mode restarts an
in-flight 64-sample blend when effect-5 changes gain on the following tick and
does not preserve the previously audible blend value. Instrument `blend_restart`,
`bl_cnt`, old/live tuples and `blend_y` around SFX-10 transitions before changing
RTL. Any repair must add a deterministic SFX-10 click regression using the
unchanged `click-v1` policy, retain P.1/P.2, preserve the 59 hardware-oracle
renders unless a reference-backed correction is explicitly adjudicated, and
leave R.75's synthesis attribution separate. Retry this mechanism only if the
trace disproves the restart timing or a PICO-8 reference shows the same events.

The first repair has two parts in full mode: a restart snapshots the
just-audible tuple rather than a stale pre-blend tuple, and a noise-only
restart requires nonzero `s_eff_a`. The four-second full SFX-10 render then
has zero `click-v1` events. PREVIEW stores a five-bit gain signature and adds
a 32-sample transition from the last emitted leaf; that reduces its SFX-10
result from 12 events to two, at samples 8,784 and 49,776, both +3,920 PCM.
A coarser signature regressed to 22 events and is rejected.

The two survivors are a distinct, trace-proven zero-edge alias. On SFX-10
rows 3 and 17, `s_eff_a` changes 112 -> 0 while the previous emitted leaf is
-490. Both gains encode as zero in `s_eff_a[11:7]`, so the signature does not
restart, `preview_alpha` remains zero, and the fold leaf snaps -490 -> 0.
Evidence is `build/psg_clicks/pv-fix1b-walk.csv`; the output pipeline places
the corresponding first WAV event at sample 8,784. The next permitted P.3
experiment retains the successful five-bit signature and adds only an
explicit idle-transition zero edge when `s_eff_a == 0`, no transition is
already active, and `s_lp != 0`. Repeat the rejected coarse signature only if
the stored-field budget or transition trace changes.

That zero-edge experiment is accepted: the four-second PREVIEW SFX-10 render
now has zero `click-v1` events, as does the full render, and the new
`make test-psg-clicks` target reproduces both at the selected 18.75 MHz
hardware clock and 3,506,580 Hz console clock. An actual seven-second Celeste
console capture with four accepted SFX-1 jump retriggers keeps the music
channels active and has no event at any jump, but exposes one separate event
at 3.184399 s (sample 70,216, delta -11,619 PCM). It aligns with frame 192,
where the title/spawn sequence retriggers a stopped foreground slot while
starting music 0, not with a jump.

The next permitted experiment addresses that newly observed trigger class.
PREVIEW's compact signature has no active/trigger bit, and `noise_filt_step`
currently acknowledges `clr_tog` at PWORK before PSTOR decides whether to
restart a transition. If the stopped slot's new tuple has the same signature,
the trigger edge is therefore invisible. Keep the clear token pending through
PSTOR, include that mismatch in `preview_restart`, and acknowledge it only
after the transition starts. This reuses the existing clear-token state and
does not widen the oscillator record. Repeat only if the console event remains
or a trace shows the clear token was already matched before the trigger.

The pending-token experiment is accepted by the console click gate: the same
seven-second capture falls from one event to zero. Its first P.1 rerun exposed
a separate integration defect rather than an interpolation error. Inactive
PREVIEW slots take the phase-0 fast path directly to PFOLD, so they do not load
the per-slot transition leaf; the new `fold_leaf` reused the preceding active
slot's `mx_filt`. Trace `build/psg_clicks/pv-music0-allslots.csv` shows slots
0..3, 6 and 7 emitting the active music leaf while their own `mix_leaf` is
zero, raising per-channel RMS by 2--4x. The interpolation stays between its
old/new endpoints on every traced row. Gate the PREVIEW fold leaf with the
already-computed `mx_aud`, restoring the required zero leaves for skipped and
hidden slots without adding storage. Repeat interpolation arithmetic only if
a traced blend leaves its endpoint interval.

With the stale-slot gain removed, `click-v1` exposed seven smaller periodic
PREVIEW events rather than letting the duplicated 2--4x RMS mask them. The
first is sample 1,464, where the emitted phaser leaf changes 6,913 -> 6,044 as
`s_eff_a` changes 1,008 -> 896. The five-bit `s_eff_a[11:7]` signature aliases
both gains to seven even though PREVIEW's multiplier consumes
`s_eff_a[10:4]`. The retained form uses all seven stored bits for that exact
audible gain and keeps the waveform signature; detune changes phase evolution
rather than the instantaneous primary gain. The same dual-mode SFX-10 gate
then returns to zero events at corrected PREVIEW RMS 2,985.

P.3 is accepted. P.1 passes the combined mix and every active channel at both
1,275 and 159 clocks/sample; P.2 passes both 64-retrigger recovery cases with
zero coalesced ticks, delayed publications or dropped samples. Full and
PREVIEW lint are warning-clean, `make test-psg` proves the unchanged 530+272
schedule with 48 `/6` clocks spare, `make test-clocks` passes, and the hardware
matrix remains byte-identical 59/59. The final exact-rate seven-second Celeste
console capture has zero `click-v1` events through the title/spawn transition
and repeated jump SFX; its exact-decimated evidence is
`build/psg_clicks/celeste-repeated-jumps-final-22k.wav`.

P.3 fingerprint `f819fe4cf85c` maps 6,571 LUT4s, 1,644 carries, 1,436 flops
and 14 EBRs; seed-1 router2 places 7,483 LCs and routes at 137.76 MHz fast /
30.22 MHz PSG. Relative to R.75 this correctness repair is +6 LUT4, -3
carries, unchanged flops/EBRs and +4 LCs. Its area/timing cost is therefore
reported independently rather than folded into R.75's schedule result.

### 54. Serialize secondary-increment evaluation before W0

R.76 is the first post-P.3 area hypothesis. The current `psg_wave.dq17`
network evaluates every triangle, phaser and ordinary detune correction in
parallel. That was the right shape while its result had to remain
combinational, but R.75 leaves a different schedule opportunity: both the live
and preceding-voice increment tuples have loaded by phase 18, their results
are not consumed until W5/W6, and phases 19..28 provide ten PSG clocks while
the fast-domain multiplier handles the independent noise products.

The candidate computes exactly two 14-bit values per visit through one narrow
add/sub accumulator and stores them until W5/W6. It must not extend the
62-phase visit or move any existing W action. Before implementation, price the
parallel correction network by replacing it with a same-input non-constant
wire in a disposable synthesis candidate; this keeps the selected inputs and
all consumers dynamic, avoiding a constant ablation that would overstate the
saving. Continue only if the mapped and placed ceiling comfortably pays for
the accumulator, control and two result lifetimes. If continued, an exhaustive
cycle model must prove all 524,288 wavetable/wave/mode/increment tuples before
the integrated render gates run.

This is materially different from R.51 and R.53. R.51 added publication and
state-store selection across ticks; R.53 retained the parallel mode network
and merely restated its width. R.76 keeps both results visit-local and removes
parallel arithmetic by spending already-idle slow-domain phases. Acceptance
requires lower mapped LUT/carry resources and placed LCs, unchanged 14 EBRs,
the exact 530+272 `/6` contract, 59/59 byte identity, P.1/P.2/P.3, clean lint
and application builds, and routed closure above 112.5 MHz fast and 18.75 MHz
PSG. Retry only if the load window, increment representation, formula set or
wave/service boundary changes.

The non-constant ablation confirms a useful but optimistic ceiling. Against
P.3's 6,571 LUT4s, 1,644 carries and 7,483 placed LCs it maps 6,375 LUT4s,
1,567 carries and places in 7,281 LCs: at most -196 LUT4s, -77 carries and
-202 LCs are attributable to the complete correction cone and its downstream
cover. Evidence is retained under `build/psg_r76/ablate.*`; the ablation edit
was restored before the real implementation was measured.

The retained service evaluates `floor(K*dp/256)` in five radix-4 steps for
`K` in 193, 250, 254, 255, 256, 384 and 508. The live request starts at phase
19. Its terminal phase accepts the preceding-voice request at phase 24, so the
two transactions occupy the existing 19..28 window without moving W0 or any
later action. A restart selects the tuple W0 is about to snapshot, matching
the prior combinational old-context semantics. PREVIEW retains `dq17`; the
full target removes that parallel network at elaboration.

`make test-psg-dq` proves all 524,288 formula tuples and 57,344 Icarus service
transactions, including terminal-cycle chaining. The integrated fingerprint
is `de8a30582959`: Yosys maps **6,513 LUT4s, 1,592 carries, 1,521 flops and
14 EBRs**. Relative to P.3 this is -58 LUT4s, -52 carries, +85 service/result
flops and unchanged EBRs. Seed-1 router2 places **7,454/7,680 LCs (-29)** and
routes at **141.30 MHz fast / 31.01 MHz PSG**, clearing both 112.5/18.75 MHz
requirements. The real win is much smaller than the ablation ceiling because
the accumulator, transaction state and two result lifetimes consume most of
the released cover, but both deterministic combinational resources and the
binding placed result improve.

The direct structural bench passes every case with a 524/850-clock observed
path; the fixed contract remains 530 walker plus 272 sequencer clocks, leaving
48 clocks in the minimum `/6` interval. Tick preparation is 4,008/5,103 with
1,095 spare and zero late flips. The 18.75 MHz render set is 59/59
byte-identical. P.1 passes the combined Celeste tune and every active channel
at both 1,275 and 159 clocks/sample; P.2 passes both 64-retrigger recovery
cases. The unchanged `click-v1` detector finds zero events in both the full and
PREVIEW four-second SFX-10 renders. Full/PREVIEW lint, `/4`/`/5`/`/6` clocks,
and the lowercase five-frame Celeste build/run pass. R.76 is accepted.

### 55. Capture the terminal detune step without a registered handoff

R.77 targets only the visit-local service boundary introduced by R.76. On the
terminal `count == 1` cycle, `step_next[21:8]` is already the complete exact
result and `active_tag` already identifies its live/old destination. The
service nevertheless copies those signals into `result`, `result_tag` and
`done` registers, after which `psg_walk` copies the registered result again
into `dq_live_r` or `dq_old_r` on the following edge. That intermediate
handoff has no independent lifetime or consumer.

Expose the terminal result, tag and valid condition combinationally from the
registered recurrence state, and let the existing walker destination registers
capture them on the terminal edge. Keep the recurrence register, request
chaining, active tag, five-step latency, phases 19/24, W0 and every later
action unchanged. This differs from the rejected cross-family lifetime merges:
no destination gains another role or fanout domain, and a complete write
boundary disappears instead of moving behind a wider D-input selector.

Baseline is accepted R.76 fingerprint `de8a30582959`: 6,513 LUT4s, 1,592
carries, 1,521 flops, 14 EBRs and 7,454 placed LCs, routed at 141.30 MHz fast
and 31.01 MHz PSG. Acceptance requires the exhaustive formula and transaction
models, terminal-cycle chaining, the fixed 530+272 `/6` contract, 59/59 byte
identity, P.1/P.2/P.3 including zero `click-v1` events, clean full/PREVIEW
lint, unchanged EBRs, lower mapped flops/LUTs or placed LCs, and both routed
clock domains above their constraints.

The retained form is RTL fingerprint `e1097eb59c9b`. Yosys maps 6,518 LUT4s,
1,592 carries, 1,505 flops and 14 EBRs: the complete 16-flop handoff retires
for five added LUT4s. Seed-1 router2 places 7,449 LCs, five fewer than R.76,
and routes at 125.87 MHz fast / 31.05 MHz PSG. Both clock domains therefore
remain above 112.5/18.75 MHz, and the binding placed result improves despite
the small combinational trade.

`make test-psg-dq` proves all 524,288 formula tuples and 57,344 transactions,
including direct observation of the first terminal result while the next
request chains. A fresh structural Verilator build passes every case at
524/850 observed clocks; the fixed contract remains 530+272 with 48 `/6`
clocks spare, tick preparation is 4,008/5,103 with 1,095 spare and zero late
flips. The explicit 18.75 MHz render set is unchanged 59/59. P.1 passes the
combined Celeste tune and every active channel at both 1,275 and 159
clocks/sample; P.2 and both lint flavours pass; `click-v1` reports zero events
for full and PREVIEW; and the lowercase five-frame Celeste build/run produces
3,668 active samples. R.77 is accepted. Repeat only if the service latency,
destination lifetime, terminal recurrence or request-chaining contract
changes.

### 56. Consume the final detune result from the idle recurrence

R.78 follows the lifetime exposed by R.77. The second transaction terminates
at phase 29, after which the service receives no request for the rest of the
visit. Its registered recurrence state therefore holds the complete old-voice
result through W5 at phase 34. Copying that value into `dq_old_r` creates a
14-bit lifetime for a result that already has stable storage at its only
consumer.

The candidate removes `dq_old_r` and lets W5 consume the service result
directly; the first live result still needs `dq_live_r` because the chained
old request overwrites the recurrence. With only the first completion needing
a destination choice, remove the service's `active_tag`, `start_tag` and
`result_tag` state and identify that capture from the fixed phase-24
chained-request edge. Preserve both five-step transactions, phases 19/24,
W0..W84 and the 530+272 contract.

Baseline is accepted R.77 fingerprint `e1097eb59c9b`: 6,518 LUT4s, 1,592
carries, 1,505 flops, 14 EBRs, 7,449 placed LCs and routed Fmax 125.87 MHz
fast / 31.05 MHz PSG. Acceptance requires lower mapped flops and placed LCs,
the exhaustive transaction/formula gate, 59/59 byte identity, P.1/P.2,
zero full/PREVIEW `click-v1` events, clean lint, the lowercase Celeste smoke,
and both routed clocks above their constraints.

Variant A exposed `step_next[21:8]` directly at W5. It removed the intended
state but widened the idle consumer cone: 6,546 LUT4s and 7,459 placed LCs,
with 1,490 flops. It is rejected. The retained variant instead commits
`step_next` into the existing recurrence register `p` on the final unchained
terminal edge. `result` exposes `step_next[21:8]` while `done` is asserted and
otherwise exposes `p[21:8]`; W5 therefore reads a registered result that holds
for the five idle phases. Only the phase-24 chained live result is copied into
`dq_live_r`.

Retained fingerprint `e12aae41e2ce` maps 6,536 LUT4s, 1,596 carries, 1,490
flops and 14 EBRs. Versus R.77 that is +18 LUT4s, +4 carries, -15 flops and
unchanged EBRs. Seed-1 router2 places 7,437 LCs, 12 fewer than R.77, and routes
at 144.80 MHz fast / 29.94 MHz PSG, clearing both 112.5 and 18.75 MHz
requirements.

`make test-psg-dq` passes all 524,288 formula cases and 57,344 service
transactions, including chaining and five idle result-retention phases. The
structural bench remains 524/850 observed clocks with the fixed 530+272
contract and 48 `/6` clocks spare; tick preparation remains 4,008/5,103 with
1,095 spare and zero late flips. All 59 hardware renders are byte-identical.
P.1 passes the combined mix and every active channel at both 1,275 and 159
clocks/sample, and P.2 passes both synthetic and frozen-Celeste 64-retrigger
cases. The full and PREVIEW four-second SFX-10 renders contain zero `click-v1`
events. Both lint flavours, `make test-clocks`, and the lowercase five-frame
Celeste smoke pass. R.78 is accepted. Repeat only if a later request enters
the phase-29..W5 interval, the W5 consumer moves, or the service recurrence
stops holding its terminal state.

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
