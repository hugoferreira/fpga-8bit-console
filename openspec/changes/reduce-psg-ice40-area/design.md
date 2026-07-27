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
- Modifying Celeste-, NEMO-, PPU- or CPU-owned sources.
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

The retained hybrid stores triangle, tilted saw, saw and organ in a compact
1,024-byte synchronous ROM. Square and pulse are their exact phase-threshold
functions (`0x80` and `0xb0`); noise and phaser continue through their existing
synthesis paths. This reduces the waveform store from four EBRs to two and
brings the standalone total from 17 to the 15-EBR ceiling. The isolated change
costs 46 seed-1 placed cells (6,831 to 6,877), so it is retained specifically
for the binding BRAM resource and not credited as an LC reduction. The
complete 50-case matrix, including both threshold discontinuities, remains
diagnostic-clean.

A hybrid ROM/formula layout is preferred to calculating the four non-trivial
shapes until a shared byte-serial waveform service demonstrates a routed LC
win. The final combined checkpoint must still improve LC as well as satisfying
the BRAM ceiling.

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
