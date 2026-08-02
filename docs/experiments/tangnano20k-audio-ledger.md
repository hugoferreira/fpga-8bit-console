# Tang Nano 20K audio debug ledger

## Context

- Topic: Celeste music 0 through the standalone Tang Nano 20K SDRAM/PSG/I2S design.
- Owner scope: `rtl/top_tangnano20k_psg.sv`, `rtl/i2s_out.sv`, its board PLL/constraints, and task-local Makefile targets.
- Correctness gate: SDRAM readback reaches the playing LED; current 18.75 MHz multipump PSG matches the PICO-8 reference; captured or user-audited speaker output is recognisable and clean.
- Benchmark/analyzer gate: `tools/audio_analysis.py wav compare` plus exact clock/format checks for I2S.
- Dirty-tree constraints: the worktree contains extensive pre-existing PSG and documentation work; do not stage, revert, or absorb unrelated files.

## Current State

- Active hypothesis: none; H028 completed the board-only exact PCM localization.
- Next hypothesis ID: H029.
- Current hardware artifact: H028 seed-3 offset trace image, SHA-256 `e6c9be9ccff6538d1e8d8e25c84a9b4f15d22943d0565609bd9bcb280d24fb01`, programmed to SRAM successfully.
- Latest decision: H028 is accepted; live words 1-62 exactly match behavioral RTL and word 63 is the first mismatch (`-5629` live versus `-5575` behavioral).
- Best accepted result: H022 seed 3 fixes the mapped slot alias and the user now
  hears music on the Tang Nano 20K at the existing 37.5% gain; SDRAM/audio-RAM
  readback still passes. H028 proves exact PCM parity through word 62 and fixes
  the remaining diagnostic boundary at word 63; the internal cause remains open.
- Last updated: 2026-08-02.

## Next Experiment Gate

- Next permitted experiment: H029 source-localize the state or arithmetic stage that first changes committed PCM word 63, using read-only mapped evidence or an explicitly coordinated diagnostic boundary before any generic RTL edit.
- Proof required before another correction: identify the first valid internal state/stage mismatch leading to word 63; do not infer a fix from the small PCM delta alone.
- Required verification: preserve H028 as the SRAM rollback, keep final live signature `E62BFAF2`, and re-coordinate with the generic PSG owner before shared production RTL instrumentation or correction.
- Blocked repeat families: no speculative sample-rate, SDRAM, or I2S edits before the PSG-only render separates those mechanisms.

## Latest Completed Hypothesis Row

- ID: H013.
- Hypothesis: increasing the currently programmed 25% amplitude by exactly 50%, to 37.5% of the original PCM amplitude, makes the existing hardware symptom easier to audit without reintroducing the unsafe full-volume tone.
- Scope: `rtl/i2s_out.sv`, `rtl/i2s_out_tb.sv`, `rtl/top_tangnano20k_psg.sv`, the H013 render, and Tang Nano SRAM programming; generic PSG RTL is fixed at checkpoint `e447962`.
- Baseline: programmed SHA-256 `8a9c9584028853fe059a6d4423bf9efe0ca223ebf2985f250bfdacbbfe212730`, peak 6,213 PCM at 25% amplitude, telemetry `S=16 F=63 I=11FF D=00 E=0`.
- Change: apply a signed 3/2 boost after `ATTEN_SHIFT=2`, producing 3/8 amplitude with no clipping for the measured track.
- Result so far: exact I2S positive/negative words pass and the rendered peak is 9,320 PCM with zero click-v1 events. Seed 2 is rejected for four `audio_index` to `audio_rom` hold violations at -0.12 ns. Seed 3 routes with 1 warning/0 errors and no hold violations and programs to SRAM successfully. The accepted 25% rollback image is also UART byte-silent, after which H013 was restored successfully.
- Decision: rejected; the user reports the same fault at 37.5% amplitude with the orange PLAY LED on.
- Repeat only if: a fresh deterministic seed is used and its report has zero timing errors; do not change audio logic merely to repair placement-specific hold timing.

## Latest Completed Hypothesis Row - H014

- ID: H014.
- Hypothesis: the unsynchronised 16-bit `pcm` transfer from `psgclk` to `fastclk` lets the I2S frame latch a mixed or metastable sample word in hardware, producing sparse low-spectrum output and clicks that ideal RTL simulation cannot reproduce.
- Scope: `rtl/pcm_cdc.sv`, `rtl/pcm_cdc_tb.sv`, `rtl/i2s_out.sv`, `rtl/i2s_out_tb.sv`, and `rtl/top_tangnano20k_psg.sv`; generic PSG RTL and the soundtrack image remain unchanged.
- Baseline: H013 seed 3, orange PLAY LED on, exact memory verification previously accepted, but the user hears low-pitched ZX Spectrum-like beeper audio with only one or two apparent instruments.
- Change: hold the complete word in the source domain, synchronize a toggle through two fast-clock flops, then capture the long-stable payload before the existing `HALF=40` serializer.
- Result: same-domain I2S seeds 3 and 4 each failed four placement-only `audio_index` to `audio_rom` hold checks at -0.12 ns, so that implementation was stopped. The toggle bridge passes exact-word simulation, routes with 1 warning/0 errors and no hold failures, programs successfully, and reports `S=16 F=63 I=11FF D=00 E=0` on hardware. Listening is pending.
- Decision: rejected; the user reports exactly unchanged low-pitched single-instrument/drum playback.
- Repeat only if: the serializer remains in a different domain or captured hardware evidence shows malformed sample words despite the same-domain boundary.

## Latest Completed Hypothesis Row - H015

- ID: H015.
- Hypothesis: Gowin-synthesized PSG commits or live voice state differ from the faithful RTL render even though audio RAM, controller state, I2S framing, gain, and PCM CDC checks pass.
- Scope: `DBG_PORT=2` registered PCM-commit pulse in `rtl/psg.sv`, board-only signature logic, and structured Tang UART fields; soundtrack, music mask, gain, and audio output remain unchanged.
- Baseline: H014 reports `S=16 F=63 I=11FF D=00 E=0` while sounding exactly like the prior low-pitched ZX Spectrum-style single-instrument/drum output.
- Change: register `dry_valid` into existing `dbg[0]`, then sign 4,096 committed PCM words beginning with the first non-zero word and report signature/count/done over UART.
- Result: focused signature/UART/PCM-CDC/I2S tests and the full PSG regression pass. The host predicts `5C504089`. Seed 3 routes with 1 warning/0 errors and no hold violations, then programs to SRAM successfully. Live UART repeatedly reports `C=811C9DC5 N=1000 V=1`, a completed but mismatching 4,096-word window.
- Decision: accepted as a localization result; the committed Gowin hardware PCM stream differs from the faithful RTL render, so further I2S, CDC, gain, and SDRAM hypotheses remain blocked.
- Repeat only if: the first signature window is too short to cover all three pattern-0 music voices or transport corruption invalidates a record.

## Latest Completed Hypothesis Row - H016

- ID: H016.
- Hypothesis: one or more pattern-0 music slots fail to launch in the Gowin image, causing the sparse single-instrument/drum PCM signature and sound.
- Scope: switch the Tang instance to existing `DBG_PORT=1`, snapshot its reliable music/play/SFX metadata into structured UART telemetry, and leave PSG/audio/control data unchanged.
- Baseline: H015 completes 4,096 commits with hardware signature `811C9DC5` versus RTL `5C504089`; SDRAM/audio-RAM, PCM CDC, I2S framing, and gain are already cleared or rejected.
- Change: report the complete existing 64-bit debug word over UART and decode its music state, eight play bits, and eight SFX IDs.
- Result: exact UART snapshot/parser and unchanged PCM-CDC/I2S tests pass. Seed 3 routes with 1 warning/0 errors and no hold violations, then programs to SRAM. Pattern 0 reports `music=1 pattern=00 play=30 sfx=15,0A,00,00` with both active rows advancing, exactly matching audio bytes `95,0A,56,44`. Pattern 4 later reports `play=70 sfx=14,13,12,00` with three advancing rows, exactly matching the soundtrack.
- Decision: accepted as a localization result; trigger, pattern chaining, SFX selection, and row progression are correct in Gowin hardware, so the severe timbre/pitch fault is later in pitch/wave/mix generation.
- Repeat only if: UART bandwidth or snapshot tearing makes the first metadata record ambiguous.

## Active Hypothesis Row

- ID: H017.
- Hypothesis: Gowin technology mapping changes the single-clock PSG PCM sequence even though behavioral RTL simulation and control telemetry pass.
- Scope: synthesize only `psg` with `CLK_HZ=18750000`, `MULTIPUMP=0`, and `DBG_PORT=0`; render the mapped netlist with the existing driver and compare the first 4,096 committed nonzero PCM words.
- Baseline: RTL signature `5C504089`; hardware signature `811C9DC5`; H016 proves exact pattern/SFX/row control on hardware.
- Change: no source change; create and simulate a preserved Gowin gate netlist with the same audio/start sequence.
- Result: the functional Gowin-mapped render completed 8,192 samples with range `-9214..-6910`. Its hardware-compatible first-nonzero 4,096-word signature is `811C9DC5`, exactly the repeated live hardware value and different from RTL `5C504089`. Gate and RTL differ at every one of the 8,192 overlapping samples; gate starts `-9214,-9214,...` while RTL starts `0,-390,-772,...`.
- Decision: accepted as a localization result; the offline mapped netlist reproduces the board fault, clearing physical-only reset/timing and all post-PCM mechanisms as the cause.
- Repeat only if: the gate simulation cannot model inferred Gowin RAM initialization or the driver startup differs from the board.

## Active Hypothesis Row - H018

- ID: H018.
- Hypothesis: H017's constant-negative waveform is caused by the exported Gowin Verilog leaving its optimized constant carriers undriven: `u_seq.released[4]` is the design-wide zero carrier and `u_seq.par_act[3]` is the design-wide one carrier, but neither has a driver in the emitted netlist.
- Scope: isolated copy of the frozen H017 netlist and a short functional mapped-netlist render only; add the two intended constant assignments without resynthesis. Do not edit shared generic PSG RTL or program the board.
- Baseline: H017 gate samples begin `-9214,-9214,...` and hash `811C9DC5`; RTL begins `0,-390,-772,...` and hashes `5C504089`. H009 verified all audio-RAM bytes and H016 verified exact control sequencing.
- Change: tie `u_seq.released[4]` to `1'b0` and `u_seq.par_act[3]` to `1'b1` in the isolated exported netlist, then render an identical short pattern-0 startup window.
- Result: not started.
- Result: an isolated netlist copy tied `u_seq.released[4]` low and `u_seq.par_act[3]` high, then rendered the identical first 64 samples. Runtime was 6.476 s and every sample remained `-9214`, exactly matching H017's prefix.
- Decision: rejected; the missing exported constant drivers are a netlist-quality defect but not the source of the mapped PCM fault under the H017 simulation conditions.
- Repeat only if: the short discriminator is ambiguous or disabling one memory family changes synthesis scheduling/resource mapping enough to require an internal trace.

## Active Hypothesis Row - H019

- ID: H019.
- Hypothesis: Gowin `DPX9B` mapping of either the 512x16 voice-state store or the reverb ring changes stored-state/read semantics and produces the long constant-negative PCM plateaus; audio RAM remains excluded by H009/H016.
- Scope: isolated synthesis commands, short functional mapped-netlist renders, and a mapped unit test only. Remove the reverb ring with `REVERB=0`; test the voice-state RAM as a small side-by-side behavioral/mapped module. Do not edit shared generic PSG RTL or program the board.
- Baseline: H017 and H018 both begin with at least 64 samples of `-9214`; RTL begins `0,-390,-772,...`.
- Change: first attempted to map only `u_state.state_m` to logic while preserving all other H017 synthesis settings. The netlist synthesized with the state `DPX9B` removed and all other nine blocks retained, but Verilator elaboration was killed with exit 137 before producing a model. Continue with a `REVERB=0` whole-core render for the ring family and a small mapped-vs-behavioral state-memory unit test.
- Result: the direct whole-core state-to-logic variant was capacity-blocked at Verilator exit 137 and was not repeated. A `REVERB=0` mapped build retained only audio RAM plus state RAM and still rendered all first 64 samples as `-9214`, excluding the ring family. A standalone mapped `psg_state_mem` then matched RTL for 3,716 cycles covering initialized reads of all 512 addresses, full writes/reads, same/different-address collisions, walk-over-engine priority, replay, and deterministic mixed traffic.
- Decision: rejected; neither reverb-ring storage nor voice-state `DPX9B` semantics explains the mapped PCM fault.
- Repeat only if: a lower-memory elaboration method becomes available; do not rerun the same 8,192-flop whole-core variant unchanged.

## Active Hypothesis Row - H020

- ID: H020.
- Hypothesis: the first mapped divergence occurs after correct state/control reads in the computed-wave/shared-multiplier path or in the serial soft-add fold, and a cycle-aligned dual-instance trace can localize it before another source change.
- Scope: isolated renamed copy of the frozen mapped `psg` beside behavioral RTL, driven by the exact H017 reset/upload/music-start sequence. Observe timing/walk control, `state_q`, loaded phase/effect state, `z_eval`, `m_res`, `mx_filt`, `mix_leaf`, fold state, `dry16`, and PCM. Do not edit shared generic PSG RTL or program the board.
- Baseline: H017/H018/H019 mapped samples begin with at least 64 copies of `-9214`; RTL begins `0,-390,-772,...`. H016 clears control sequencing and H019 clears both mapped internal RAM families.
- Change: compare valid internal stages at each settled clock edge and report the first mismatch with cycle, slot, and walk phase.
- Result: after correcting the trace to observe DPX9B port `DOB` and ignoring the inlined/undriven exported `cap` name, the first valid mismatch occurs at post-start cycle 65, slot 1, `pph=0`: RTL reads `0x04a` while the mapped core reads `0x08a`. The complete `pph=0` map is RTL `00a,04a,08a,0ca,10a,14a,18a,1ca` versus mapped `00a,08a,10a,18a,00a,08a,10a,18a`. Thus mapped slots use `{pc_ch[1:0],1'b0}` as address bits 8:6, doubling the intended slot field and aliasing slots 4-7 onto 0-3. At cycle 73 (`pph=8`) the wrong read produces RTL `state_q=0x1400` versus mapped `0x1600`, before waveform, multiplier, mix, fold, or PCM logic.
- Decision: accepted as a localization result; the severe missing-voice audio is explained by whole-core mapped address generation/wiring, while H019 still clears the DPX9B primitive's standalone semantics.
- Repeat only if: an observed mismatch is in an uninitialized or not-yet-valid datapath register; then tighten the stage-valid gate rather than changing RTL.

## Active Hypothesis Row - H021

- ID: H021.
- Hypothesis: Gowin synthesis mis-sizes or rewires the walker's `{pc_ch, offset}` read-address expression; assembling the nine-bit address from explicit slot, zero, and five-bit offset fields in an isolated frozen source will restore the 64-word slot stride. If the mapped address remains doubled, the fault is instead in `psg_state_mem`'s walk/engine address mux.
- Scope: copy the frozen H017 source inputs into `build/gowin_psg/h021_addr/`, change only the isolated `psg_walk.sv` read-address construction, synthesize a preserved Gowin netlist, and rerun the H020 dual trace. Do not edit shared generic PSG RTL, program the board, or alter gain/I2S/CDC/SDRAM paths.
- Baseline: H020 first mismatch at cycle 65, slot 1, `pph=0`, RTL `state_ra=0x04a`, mapped `0x08a`; complete mapped bases are `0,2,4,6,0,2,4,6` times 64.
- Change: replace concatenations containing arithmetic with an explicit five-bit offset and `wlk_ra={pc_ch,1'b0,offset}` only in the isolated H021 source copy.
- Result: the first attempt was invalid because Yosys resolved includes relative to root `rtl/psg.sv`; it was discarded before decision. The corrected isolated source root preserved `psg.sv` plus the frozen pre-`ca18727` `psg_dqsvc.sv`/`psg_walk.sv` and changed only walker address assembly. Its mapped `state_ra[8:6]` select `pc_ch[2:0]` respectively. The complete map then matches RTL exactly for slots 0-7: `00a,04a,08a,0ca,10a,14a,18a,1ca`. A PCM-only validity gate matches `dry_valid`, `dry16`, and `pcm` for 3,600,000 post-start cycles, covering more than the 4,096 committed-word signature window; both finish at PCM `-2101`.
- Decision: accepted; the root cause is SystemVerilog expression width in `{pc_ch, PSG_V_OSC + 5'(pph)}` and its related bank expression. Gowin/Yosys kept the arithmetic operand wide enough that assignment to nine bits discarded `pc_ch[2]`, shifting `pc_ch[1:0]` and aliasing the eight voice slots modulo four. Explicit `{pc_ch,1'b0,wlk_roff[4:0]}` restores mapped behavior without changing behavioral RTL.
- Repeat only if: the isolated variant fails to preserve the exact pre-`ca18727` scheduling sources or the trace observes a different memory port/address than H020.

## Active Hypothesis Row - H022

- ID: H022.
- Hypothesis: applying the proven explicit walker read-address assembly to current generic RTL will preserve all behavioral PSG gates, restore the Tang Gowin mapped PCM signature to the RTL value, and make all intended voices audible at the existing 37.5% gain.
- Scope: after explicit coordination, edit only the walker address construction in `rtl/psg_walk.sv`; run current-HEAD structural/lint/render gates, rebuild the board image, verify mapped or live PCM telemetry, and program SRAM only after timing passes. Do not alter gain, I2S, PCM CDC, SDRAM, reverb, or soundtrack selection.
- Baseline: frozen mapped H017 and hardware signature `811C9DC5` versus RTL `5C504089`; H020 shows slot aliasing and H021 proves the isolated fix matches RTL PCM for 3.6 million cycles.
- Change: coordinated and committed only the width-explicit walker correction as
  `e099e52`; restored the board's existing 4,096-word PCM signature telemetry
  without changing the 37.5% gain or any audio/control data.
- Result so far: full/PREVIEW lint and `make test-psg` pass. Fresh current-RTL
  rendering predicts signature `5C504089`; fresh GW2A synthesis directly assigns
  `wlk_ra[8:6]=pc_ch[2:0]`. Seed 3 routes at 56.61 MHz in the 18.75 MHz PSG
  domain with 1 warning/0 errors and no hold failures; bitstream SHA-256 is
  `b208899c03153aae90d375087b58bcdd9764a2c8352291b8602400b8acbb959e`.
  After reconnect, SRAM programming succeeds and UART repeatedly completes
  `C=E62BFAF2 N=1000 V=1`, not `5C504089`. Searching current RTL window offsets
  -8 through +1024 finds no match, so this is not a sample-window phase shift.
  The user reports "finally we have music", confirming that the severe
  missing-instrument/single-beeper symptom is fixed by this image.
- Decision: rejected; the original read-slot alias is fixed, but the newer
  current generic state still has a distinct mapped-versus-behavioral mismatch.
- Repeat only if: the optimization task changes walker/state-memory addressing or rebases the generic RTL before H022 lands; then rebuild the isolated proof from that new checkpoint.

## Completed Hypothesis Row - H023

- ID: H023.
- Hypothesis: the preserved H022 PSG-only Gowin netlist reproduces live signature `E62BFAF2`, proving the remaining mismatch is inside mapped generic PSG logic after the corrected walker address.
- Scope: `build/gowin_psg/h022_addr/psg_gowin_gate.v`, a scalar-port adapter, the existing standalone PSG WAV driver, and offline signature comparison only; no source edit, board build, or programming.
- Baseline: behavioral signature `5C504089`; live H022 signature `E62BFAF2`; preserved netlist SHA-256 `3efa97298b5e29fe8717351b1f4afb30a8c04b25fa7f61e36d792f14d173f3b0`.
- Change: render the mapped netlist with the exact 4,608-byte Celeste image, music 0, mask 7, and 18.75 MHz capture clock, then sign the first 4,096 words from the first nonzero sample.
- Result: the first command used unsupported option `--clock`, silently retained the driver's 3.50658 MHz default, repeated samples, and produced invalid signature `92458E9C`; it is not hardware evidence. The corrected `--clk 18750000` render produced 4,200 samples, SHA-256 `9ff27940b436147fd236cf2cf55e4492fca98c6948fd37f8158d07863b205317`, signature `5C504089`, and matched behavioral RTL for all 4,199 aligned samples after the common leading zero.
- Decision: accepted as a localization result; isolated current Gowin PSG mapping is exact, so H022's live signature mismatch lies in `DBG_PORT=2`/signature integration or whole-board synthesis context, not the generic PCM datapath.
- Repeat only if: the preserved netlist or startup sequence changes; never reuse `--clock`, which the driver ignores.

## Active Hypothesis Row - H024

- ID: H024.
- Hypothesis: the registered `DBG_PORT=2` commit pulse and same-domain `pcm_signature` sampler diverge under Gowin mapping or sample the adjacent PCM word, producing `E62BFAF2` even though isolated mapped PCM is exact.
- Scope: isolated DBG_PORT=2 PSG plus `pcm_signature`, preserved H022 source/netlist inputs, functional Gowin primitives, and exact per-commit comparison; board audio, gain, SDRAM, I2S, CDC, soundtrack, and generic RTL remain unchanged.
- Baseline: H023 mapped and RTL PCM both sign `5C504089`; live completed board telemetry is `E62BFAF2`, `N=1000`, `V=1`.
- Change: observe the PCM word on every registered debug commit pulse in behavioral and mapped integration, and compare the integrated 4,096-word signature.
- Result: the standalone mapped signature unit, netlist SHA-256 `6091e47f5e244aff1660204b5138ef1ef7e3e3a53bd5b7fd1315e66c25e6b570`, signs the exact H022 RTL WAV as `5C504089`, count 4096, done 1. The combined DBG_PORT=2 PSG/signature netlist SHA-256 is `467ec4c7d854c543daa432463cd6225ca05fab02d21a25febf91a8b4dda032c9`; its 4,200-sample mapped render is byte-identical to H023, hashes `9ff27940b436147fd236cf2cf55e4492fca98c6948fd37f8158d07863b205317`, signs `5C504089`, and finishes with debug word `000030005C504089` (done 1, count 4096). Preserved H022 `top.json` also aliases all 16 `pcm_sig0.pcm` bits, `pcm_sig0.commit`, and `pcm_sig0.clk` directly to the corresponding `psg0` nets.
- Decision: accepted as a localization result; DBG_PORT=2 timing, signature mapping, and direct synthesized wiring are exact outside the full-board optimization context.
- Repeat only if: the isolated integration does not preserve the exact H022 reset/upload/music-start sequencing or synthesis parameters.

## Active Hypothesis Row - H025

- ID: H025.
- Hypothesis: whole-board synthesis changes the PSG/signature cone relative to isolated mapping, and the exact preserved H022 `top.json` subgraph reproduces live `E62BFAF2` under the standalone upload/start sequence.
- Scope: read-only preserved `build/gowin_psg/top.json`, mechanically extracted `psg0.*` plus `pcm_sig0.*` cells, functional Gowin primitives, and offline replay; no source edit, rebuild, placement, or board programming.
- Baseline: H023 and H024 isolated mappings both sign `5C504089`; live H022 bitstream repeatedly reports `E62BFAF2`, count 4096, done 1.
- Change: use Yosys `submod` to retain the exact whole-board mapped cells and expose cut nets as ports, then drive its bus/reset/clock inputs with the accepted standalone sequence.
- Result: preserved `top.json` SHA-256 remains `df83d18ecee2935ca512b65a95f7e6c6122f3dbf1180d0c60bbb317a92ec5279`. A prefix/source-selected extraction exposes 205 merged cut ports; recursive fan-in still captures controller, SDRAM, PLL, and UART state and cannot be driven by the standalone PSG sequence without invented values. Separately, the exact preserved H022 bitstream SHA-256 `b208899c03153aae90d375087b58bcdd9764a2c8352291b8602400b8acbb959e` was reprogrammed to SRAM and repeatedly reports `C=E62BFAF2 N=1000 V=1`, confirming artifact identity and reproducibility.
- Decision: rejected as a replay method; post-flatten extraction is not an auditable boundary for this design.
- Repeat only if: the extracted cell selection omits an aliased PSG/signature cell or introduces a driver not present in preserved `top.json`.

## Completed Hypothesis Row - H026

- ID: H026.
- Hypothesis: a small board-only trace of the first exact registered-commit PCM words will reveal the first whole-board divergence while leaving the working H022 audio and existing 4,096-word signature unchanged.
- Scope: new board-only PCM trace module/testbench, `rtl/top_tangnano20k_psg.sv`, UART host decoding, route/program/readback; no generic PSG, gain, I2S, CDC, SDRAM, soundtrack, or controller change.
- Baseline: H023/H024 first words are `-390,-772,-1143,-1505,...` and sign `5C504089`; exact H022 SRAM reload signs `E62BFAF2` with completed count 4096.
- Change: capture 33 committed words beginning at the first nonzero PCM, then rotate 11 pages of three signed 16-bit words through `G={8'hA5,page,word0,word1,word2}` slowly enough for repeated 10 Hz UART snapshots.
- Result: the capture/page self-check passes. Seed 3 routes with 9,222 LUT4, 2,138 DFF, 15 BSRAM, one known non-dedicated `psgclk` routing warning, zero errors, no hold failures, and final PSG Fmax 58.65 MHz. SRAM image SHA-256 `fdc4c0af36dff4864722449967ac44606a6dc08cfc3b85c6ab06a19d79f91fec` preserves live signature `E62BFAF2`. Its first 33 signed words are `-390,-772,-1143,-1505,-1857,-2199,-2531,-2854,-3168,-3471,-3764,-4048,-4322,-4586,-4840,-5085,-5320,-5545,-5761,-5966,-6162,-6348,-6525,-6691,-6848,-6995,-7132,-7260,-7378,-7486,-7583,-7673,-7751`, exactly matching behavioral RTL.
- Decision: accepted as telemetry infrastructure; startup, `DBG_PORT=2`, same-domain sampling, and early whole-board PCM are exact, so the first divergence is after committed word 33.
- Repeat only if: route timing passes and the live 4,096-word signature remains `E62BFAF2`; otherwise treat instrumentation perturbation as the result.

## Completed Hypothesis Row - H027

- ID: H027.
- Hypothesis: rolling signatures captured at committed counts 64, 128, 256, 512, 1024, 2048, and 4096 will identify the first bounded interval containing the whole-board PCM divergence without storing a large exact trace or changing generic PSG behavior.
- Scope: new board-only checkpoint telemetry module/testbench, `rtl/top_tangnano20k_psg.sv`, UART host decoding/comparison, route/program/readback; no generic PSG, gain, I2S, CDC, SDRAM, soundtrack, or controller change.
- Baseline: H026 first 33 live words exactly match behavioral RTL; its completed live signature is still `E62BFAF2` versus behavioral `5C504089` at count 4096.
- Change: hash the same first-nonzero committed stream and freeze seven rolling signatures, then rotate `G={8'hA6,page,count,signature}` slowly enough for repeated 10 Hz UART snapshots.
- Result: the checkpoint self-check, host decoder, signature/UART/PCM-CDC/I2S gates, and host-derived expected values pass. Seed 3 routes with 9,021 LUT4, 2,182 DFF, 15 BSRAM, one known non-dedicated `psgclk` routing warning, zero errors/no hold failures, and final PSG Fmax 59.94 MHz. SRAM image SHA-256 is `499b8745513c4733eadeefb8917ba9f0032482e4435d715950e64617fdd0d148`. Live checkpoints are 64:`32AC2E75`, 128:`541548CC`, 256:`015C1D85`, 512:`A148BD91`, 1024:`982184F8`, 2048:`2F5A3383`, 4096:`E62BFAF2`; behavioral values are respectively `35E02939`,`6FC17318`,`22653EBC`,`5BB6476F`,`F628EAF1`,`80A39C7A`,`5C504089`.
- Decision: accepted; the first failing checkpoint is 64, and H026 proves words 1-33 exact, so the first whole-board PCM divergence is in committed words 34-64.
- Repeat only if: a checkpoint is missing or transport-corrupt, or the instrumentation changes the unchanged 4,096-word `C=` signature; otherwise narrow only the first mismatching interval.

## Completed Hypothesis Row - H028

- ID: H028.
- Hypothesis: extending the already-proven exact trace through committed word 66 will identify the first mismatch inside words 34-64 and provide two words of immediate context without changing the working audio path.
- Scope: reuse the board-only exact PCM trace module with `WORD_COUNT=66`, add host exact-word comparison, update `rtl/top_tangnano20k_psg.sv`, route/program/readback; no generic PSG, gain, I2S, CDC, SDRAM, soundtrack, or controller change.
- Baseline: H026 proves words 1-33 exact; H027 count-64 hash differs (`32AC2E75` versus `35E02939`) and final live signature remains `E62BFAF2`.
- Change: the first variant captured all 66 words in 22 pages. After its seed-3 route failed eight placement-only `audio_rom` hold checks at -0.12 ns, replace it with a 33-word window starting at word 34 and absolute pages 11-21, matching H026's proven buffer size while comparing only the unresolved interval plus two following words.
- Result: exact trace, offset-window, and host-reference unit tests pass. The 66-word seed-3 route used 9,550 LUT4, 2,284 DFF, 15 BSRAM and reached 55.18 MHz PSG Fmax, but failed eight `audio_rom` hold checks at -0.12 ns and was not packed or programmed. The reduced 33-word offset window routes with 9,282 LUT4, 2,154 DFF, 15 BSRAM, one known non-dedicated `psgclk` routing warning, zero errors/no hold failures, and final PSG Fmax 66.36 MHz. Its SRAM image SHA-256 is `e6c9be9ccff6538d1e8d8e25c84a9b4f15d22943d0565609bd9bcb280d24fb01`. Live words 34-62 match behavioral RTL exactly. The first mismatch is word 63, `-5629` live versus `-5575` behavioral; words 64-66 are `-5349,-5032,-4717` live versus `-5353,-5038,-4726` behavioral. The unchanged final live signature remains `E62BFAF2`.
- Decision: accepted; exact telemetry now proves whole-board PCM is identical through word 62 and first diverges at committed word 63.
- Repeat only if: one or more trace pages are missing or transport-corrupt, or the instrumentation changes the unchanged `C=` signature.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| H001 | accepted | PSG-only render is faithful; move downstream to I2S. |
| H002 | accepted | Self-checking receiver decodes exact 16-bit signed words in both slots; framing is not the corruption source. |
| H003 | rejected | RTL phase sweep passed; H008 reopens the broader CDC implementation only because physical one-voice/click evidence is absent from that idealized test. |
| H004 | rejected | MAX98357A supports 32-bit I2S; user reports missing instruments rather than excessive level or generic distortion. |
| H005 | rejected | Pattern 40 intentionally enables only SFX 56, 58, and 60; byte 4 is disabled and mask 7 is correct. |
| H006 | rejected | Exact no-reset render remains active with zero clicks; do not retry without hardware-only reset evidence. |
| H007 | rejected | Correct cue programmed, but hardware remains severely incomplete and clicky. |
| H008 | rejected | Single-clock build routed cleanly and preserved simulated PCM, but hardware sounded unchanged. |
| H009 | accepted | Hardware reaches PLAY only after SDRAM and PSG audio RAM both compare all 4,608 bytes; telemetry reports `I=11FF`, `E=0`. |
| H010 | accepted as board control | Official bitstream produces its intended single tone, proving the pins/amplifier/speaker path is alive; it is unacceptably loud and harsh for further diagnostics. |
| H011 | rejected | Hardware sounds unchanged with official 16-bit/32-BCLK framing; do not retry another framing without a captured malformed stream. |
| H012 | accepted | Exact UART simulation passes and hardware emits valid records on `/dev/cu.usbserial-20230306211`; PLAY/refresh states and flags decode correctly. |
| H013 | rejected | Orange PLAY stays on, but 50% more amplitude leaves the same low-pitched ZX Spectrum-like sparse fault; do not adjust gain again. |
| H014 | rejected | Toggle bridge is clean and telemetry-verified but sounds exactly unchanged; do not retry PCM CDC without captured word corruption. |
| H015 | accepted | Exact commit count completes, but hardware signature `811C9DC5` differs from RTL `5C504089`; the fault is at or before PSG PCM. |
| H016 | accepted | Patterns 0 and 4 report exact play/SFX fields and advancing rows; control/trigger loss is not the fault. |
| H017 | accepted | Functional mapped render exactly reproduces hardware signature `811C9DC5`; fault is in synthesis/technology mapping. |
| H018 | rejected | Driving the exported zero/one constant carriers leaves all first 64 samples at `-9214`; not the mapped fault. |
| H019 | rejected | No-reverb gate prefix is unchanged; mapped state RAM matches RTL over 3,716 exhaustive/mixed cycles. |
| H020 | accepted | First mismatch is voice-state address generation: mapped slot field doubles and aliases modulo four before waveform/mix. |
| H021 | accepted | Explicit nine-bit walker address assembly restores all mapped slots and matches RTL PCM for 3.6 million cycles. |
| H022 | rejected | Live current hardware signs `E62BFAF2`, not RTL `5C504089`, despite corrected mapped `wlk_ra[8:6]`. |
| H023 | accepted | Correct-clock isolated mapped PCM matches behavioral RTL and signs `5C504089`. |
| H024 | accepted | Isolated mapped `DBG_PORT=2` plus signature integration remains exact. |
| H025 | rejected | Whole-board flattened extraction requires fabricated controller inputs and is not an auditable replay boundary. |
| H026 | accepted | First 33 live committed words exactly match RTL; divergence is later. |
| H027 | accepted | Count 64 is the first failing checkpoint; first divergence is in words 34-64. |
| H028 | accepted | Words 1-62 are exact; first live mismatch is word 63, `-5629` versus `-5575`. |

## Active Hypothesis Row - H023

- ID: H023.
- Hypothesis: a generic PSG change after H021's isolated frozen source introduced a second Gowin expression-width or publication mismatch; a current behavioral-versus-current mapped trace will diverge before PCM and identify its first valid stage.
- Scope: read-only current GW2A netlist, exact H017 upload/reset/music-start sequence, and a short dual trace. Preserve H022 audio bytes, clock, mask, gain, and board image; do not edit generic PSG or program another image.
- Baseline: H022 behavioral signature `5C504089`, live mapped hardware `E62BFAF2`; current mapped `wlk_ra[8:6]` directly equals `pc_ch[2:0]`.
- Change: compare current behavioral and mapped instances at settled edges, beginning with control, state addresses/data, executor service outputs, walk intermediates, and committed PCM.
- Result: live H022 audio is recognizably music after the address correction,
  while its completed PCM signature remains `E62BFAF2`; first-divergence tracing
  is deferred so the working audio image stays untouched.
- Decision: active.
- Repeat only if: the trace probes an optimized-away carrier or invalid pipeline phase; then tighten the validity gate or compare the consuming result instead of changing RTL.

## Active DNR Index

- SDRAM corruption: do not retry without a lit error LED or a failing readback probe; the hardware byte comparison passed.
- Static-only proof: timing closure and synthesis success do not establish audio fidelity.
- I2S format: do not edit until the source PCM has been cleared by H001.
- Analog attenuation: defer until the Gowin-specific multipump phase is cleared; the existing design has zero schedule margin and was not validated on this clock source.
- Multipump relative phase: H003 swept the complete fast period without a miss; H008 is permitted by new physical evidence of lost voices and clicks not represented by RTL simulation.
- I2S slot width: H011's materially changed condition is the official Sipeed board example's working 16-bit/32-BCLK frame; do not try further formats without a captured malformed hardware frame.
- Output gain: H013 changed amplitude by exactly 50% without changing the fault; do not retry volume as a fidelity mechanism.
- PCM CDC: H014's source-held toggle bridge leaves the hardware sound exactly unchanged; do not retry without captured word corruption.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `bin/tangnano20k-psg.fs` | `make tangnano20k-psg-prog` | Programs and reaches the orange playing state. |
| `build/gowin_psg/music40-current-rtl.wav` | `python3 tools/psg_oracle_render.py --audio build/p8ref/celeste-audio.bin --music 40 --mask 7 --samples 220500 --clock 18750000 --out build/gowin_psg/music40-current-rtl.wav` | H001 current RTL at the exact board PSG clock. |
| `build/gowin_psg/music40-current-vs-pico8.json` | `python3 tools/audio_analysis.py --output json wav compare build/p8ref/pico8-40.wav build/gowin_psg/music40-current-rtl.wav --labels tang-current` | Pass: score 0.9718, pitch agreement 0.9718, spectral median 0.9955. |
| `build/i2s_out_tb` | `iverilog -g2012 -s i2s_out_tb -o build/i2s_out_tb rtl/i2s_out_tb.sv rtl/i2s_out.sv && vvp build/i2s_out_tb` | H002 pass: exact words, zero padding, standard one-bit delay, BCLK `/40`, LRCK `/64`. |
| `build/gowin_psg/phase-sweep/phase-*.log` | compile/run `rtl/psg_mulmp_phase_tb.sv` with `SLOW_OFFSET_NS=0..9` | H003 rejected: all ten offsets pass the longest/short/result-shape cases and padded deadline. |
| `build/gowin_psg/music0-current-rtl.wav` | `python3 tools/psg_oracle_render.py --audio build/p8ref/celeste-audio.bin --music 0 --mask 7 --samples 188416 --clock 18750000 --out build/gowin_psg/music0-current-rtl.wav` | H007 cue proof: active range -24797..24853; current dirty PSG scores 0.8065 against PICO-8, so listening remains required. |
| `bin/tangnano20k-psg.fs` | `openFPGALoader -b tangnano20k bin/tangnano20k-psg.fs` | H007 pattern-0 bitstream built with 1 warning/0 errors and loaded to SRAM successfully. |
| `build/gowin_psg/music0-single-clock.wav` | direct Verilator build with `CLK_HZ=18750000,MULTIPUMP=0` | H008 preserves the intended active PCM and has zero detected click events in simulation. |
| `build/gowin_psg/pnr.log` | `make tangnano20k-psg GOWIN_SEED=2 ...` | H008 single-clock route: seed 2, 7,749 LUT4, slow-domain Fmax 57.78 MHz, 1 warning/0 errors. Seed 1 was preserved separately after eight hold failures and not programmed. |
| `bin/tangnano20k-psg.fs` | `openFPGALoader -b tangnano20k bin/tangnano20k-psg.fs` | H008 single-clock pattern-0 image loaded to SRAM successfully. |
| `build/gowin_psg/music0-no-post-reset.wav` | temporary no-reset renderer at `CLK_HZ=18750000,MULTIPUMP=0` | H006 rejected: same active range, score 0.8065, zero clicks; no-reset launch does not reproduce hardware symptom. |
| `build/gowin_psg/music0-h011-atten12db.wav` | `ffmpeg -i music0-single-clock.wav -af volume=0.25 ...` | H011 safety render: peak 6,213 PCM, zero click-v1 events, 0.8065 pitch agreement; full-track level gate fails only because the deliberate `/4` attenuation is compared with an unattenuated reference. |
| `bin/tangnano20k-psg.fs` | seed-2 H011 build before H009 | SHA-256 `18f6e9645c67fbc903ec9b4098aa4bfcc7bcb6f84f85625be9050773a60bb887`; 1 warning/0 errors, slow-domain Fmax 57.55 MHz. Not programmed. |
| `build/obj_psg_aram_readback/Vpsg_aram_readback_tb` | Verilator build of `rtl/psg_aram_readback_tb.sv` | H009 pass: all 4,608 actual audio-RAM bytes match through `$42ff`; no write-shadow shortcut. |
| `build/obj_psgtb_h009/psg_tb_bin` | direct clean Verilator build after restoring unrelated generated files | H009 regression pass: all PSG behavior and deadline tests passed; worst walk 524/850 clocks and tick pre-run 1,095 clocks spare. |
| `bin/tangnano20k-psg.fs` | seed-2 H009+H011 build before the final read-capture wait | SHA-256 `240cf283606a3f57deb9ed8948c63d87e5e09308e0002ce2d9aef283ef90da72`; superseded before programming after review found the top-level checker sampled `dout` on its commit edge. |
| `bin/tangnano20k-psg.fs` | final H009+H011+H012 seed-2 build from PSG checkpoint `e447962` | SHA-256 `8a9c9584028853fe059a6d4423bf9efe0ca223ebf2985f250bfdacbbfe212730`; 8,084 LUT4, 15 BSRAMs, 55.78 MHz slow-domain Fmax, 1 warning/0 errors, no hold failures; programmed to SRAM successfully. |
| `/dev/cu.usbserial-20230306211` | `python3 tools/tangnano20k_telemetry.py --seconds 5` | H009/H012 hardware pass: repeated `S=16 F=63 I=11FF D=00 E=0`; `S=17`/busy or refresh-due flag changes are expected refresh excursions. |
| `build/gowin_psg/music0-h013-boost50.wav` | apply exact signed 3/2 gain to the verified 25% render | H013 safety render: peak 9,320 PCM, zero click-v1 events. |
| `build/gowin_psg/pnr.h013-seed2-failed.log` | `make -B tangnano20k-psg GOWIN_SEED=2 ...` | H013 rejected placement: four `audio_index` to `audio_rom` hold violations at -0.12 ns, 1 warning/4 errors; SHA-256 `271af411c4fe1bcd736c500867c0dc2f1d8da2ee9f88bd28c84297ca22758645`; not programmed. |
| `build/gowin_psg/tangnano20k-psg.h013-seed3-atten37p5.fs` | H013 seed-3 build and SRAM program | SHA-256 `92992859d5d120d8ce05a4176d8e27918512edbca50458d48c6f4769e4d52e10`; route has 1 warning/0 errors and no hold violations, but `/dev/cu.usbserial-20230306211` produced zero bytes in repeated reads after programming. |
| `build/gowin_psg/pnr.h014-seed3-failed.log` | H014 seed-3 place-and-route | Four `audio_index` to `audio_rom` hold violations at -0.12 ns, 1 warning/4 errors; SHA-256 `bbbb9ff8b462a4e188c593b0f7d7f7ff71fbe64447f705117b51a2d69ba7b3eb`; not programmed. |
| `build/gowin_psg/pnr.h014-seed4-failed.log` | H014 seed-4 place-and-route | Same four `audio_index` to `audio_rom` hold violations at -0.12 ns, 1 warning/4 errors; SHA-256 `8736c7033eb4071ae3e38e1071bc0b4b156c6f377ecec462544e3db738a9d1d9`; not programmed. |
| `build/gowin_psg/tangnano20k-psg.h014-bridge-seed3.fs` | H014 toggle-bridge seed-3 build and SRAM program | SHA-256 `793bccaad6c941f11ead22f8bd3b61ee58fb4cc66d52f2975bc4fddc3a1b2215`; 1 warning/0 errors, no hold violations, telemetry `S=16 F=63 I=11FF D=00 E=0`. |
| `build/gowin_psg/tangnano20k-psg.h015-seed3.fs` | H015 exact PCM-commit signature build and SRAM program | SHA-256 `01976ffd8ab8b14efe9416dcb45c1c9835ca3bd876ed98f197712a5ca9e60485`; 1 warning/0 errors, no hold violations; host expected `5C504089`, hardware repeatedly reports `C=811C9DC5 N=1000 V=1`. |
| `build/gowin_psg/tangnano20k-psg.h016-seed3.fs` | H016 live PSG control-state build and SRAM program | SHA-256 `7ed2661634230f0755ca9e7200e9c004222b823a4f81972bc57623660b3ebd7e`; 1 warning/0 errors, no hold violations; exact pattern 0/4 play, SFX, and advancing-row telemetry. |
| `build/gowin_psg/h017_gate/music0-gowin-functional-gate.wav` | functional simulation of frozen Gowin-mapped PSG with official GW2A primitives plus a functional `DPX9B` model | H017 pass: 8,192 samples, range `-9214..-6910`, signature `811C9DC5` exactly matches hardware and differs from RTL `5C504089`; host time 809.329 s. |
| `build/gowin_psg/h018_const/music0-const-tied-64.wav` | H017 netlist copy with intended zero/one carrier assignments restored | H018 rejection: 64/64 samples remain `-9214`; the exported undriven carriers are not the mapped PCM cause. |
| `build/gowin_psg/h019_mem/music0-no-reverb-gate-64.wav` | exact H017 synthesis/model flow with top-level `REVERB=0` | H019 rejection: all 64 samples remain `-9214`, so the six ring `DPX9B` blocks are not required for the fault. |
| `build/gowin_psg/h019_mem/obj_state_compare/state_compare` | mapped `psg_state_mem` versus behavioral RTL self-check | H019 pass: exact match over 3,716 cycles including all addresses, initialization, collisions, priority, replay, and mixed traffic. |
| `build/gowin_psg/h020_trace/obj/psg_dual_trace` | `build/gowin_psg/h020_trace/obj/psg_dual_trace --audio build/p8ref/celeste-audio.bin --cycles 1800 --address-map` | H020 pass: first valid mismatch at cycle 65 and complete slot map prove mapped voice-state bases `0,2,4,6,0,2,4,6` instead of `0..7`; the fault precedes waveform/multiply/mix. |
| `build/gowin_psg/h021_addr/obj/psg_dual_trace` | `build/gowin_psg/h021_addr/obj/psg_dual_trace --audio build/p8ref/celeste-audio.bin --cycles 3600000 --pcm-only` | H021 pass: explicit walker address fields make all eight mapped slot addresses exact and preserve every committed PCM word for 3.6 million post-start cycles; final RTL/gate PCM is `-2101`. |
| `build/gowin_psg/h023_trace/music0-gate-clk18750000-4200.wav` | corrected mapped discriminator using `--clk 18750000` | H023 pass: SHA-256 `9ff27940b436147fd236cf2cf55e4492fca98c6948fd37f8158d07863b205317`; signature `5C504089`; all 4,199 aligned post-start samples match behavioral RTL. |
| `build/gowin_psg/h024_signature/music0-integrated-gate-4200.wav` | isolated mapped DBG_PORT=2 PSG plus `pcm_signature` | H024 pass: SHA-256 `9ff27940b436147fd236cf2cf55e4492fca98c6948fd37f8158d07863b205317`; final debug `000030005C504089`; exact signature/count/done and PCM. |
| `build/gowin_psg/tangnano20k-psg.h026-trace-seed3.fs` | H026 exact 33-word trace build and SRAM program | SHA-256 `fdc4c0af36dff4864722449967ac44606a6dc08cfc3b85c6ab06a19d79f91fec`; 9,222 LUT4, 2,138 DFF, 15 BSRAM, 58.65 MHz PSG Fmax, one known routing warning/zero errors/no hold failures; live signature `E62BFAF2`, first 33 words exact. |
| `build/gowin_psg/tangnano20k-psg.h027-checkpoints-seed3.fs` | H027 rolling checkpoint build and SRAM program | SHA-256 `499b8745513c4733eadeefb8917ba9f0032482e4435d715950e64617fdd0d148`; 9,021 LUT4, 2,182 DFF, 15 BSRAM, 59.94 MHz PSG Fmax, one known routing warning/zero errors/no hold failures; live count-64 hash already differs. |
| `build/gowin_psg/tangnano20k-psg.h028-offset34-seed3.fs` | H028 exact words 34-66 trace build and SRAM program | SHA-256 `e6c9be9ccff6538d1e8d8e25c84a9b4f15d22943d0565609bd9bcb280d24fb01`; 9,282 LUT4, 2,154 DFF, 15 BSRAM, 66.36 MHz PSG Fmax, one known routing warning/zero errors/no hold failures; first mismatch is committed word 63. |

## Archive

- Full historical rows: none yet.
- Resume-audit history: current file.
- Archived DNR table: none.

## Handoff

- Next allowed experiment: H029 source-localize the internal cause of word 63 using read-only evidence or an explicitly coordinated diagnostic boundary; no uncoordinated generic edit.
- Blocked/rejected mechanisms: generic PCM correction, sample-window shift, SDRAM corruption, I2S, CDC, gain, and soundtrack data lack evidence after H009-H026.
- Verification still missing: the first internal state/stage mismatch leading to word 63, followed by a corrected live signature `5C504089` without changing the audible H022 path.
- Files to avoid staging: every pre-existing dirty file outside the owner scope above.
