# PSG RTL area continuation ledger

This is the resume surface for small, generic-RTL area and source-simplicity
experiments running independently of the R.84 stored-state executor work in
`r78-continuation.md`. Do not edit or integrate the R.84 executor from this
loop. Detailed earlier area history remains in `design.md`, `tasks.md`, and
`r78-continuation.md`.

## Context

- Topic: exact generic PSG RTL simplification and iCE40 HX8K area reduction.
- Owner scope: existing production RTL outside the R.84 executor/controller
  replacement; each hypothesis records its exact RTL and proof boundary.
- Correctness gate: proof of exact arithmetic, focused model/unit tests,
  `make test-psg`, 59-render PICO-8 regression, and no weakened tolerance.
- Physical gate: canonical `PATH=/opt/homebrew/bin:$PATH make synth-psg` with
  seed-1 router2 placement, routed timing, mapped resources, and 14 or fewer
  EBRs. An accepted area change must improve a deterministic mapped resource
  and not regress placed LCs.
- Dirty-tree constraints: stage only the active RTL, proof, generated artifact,
  and this ledger. Companion R.84 files and unrelated user work are excluded.
  H096 resumes from merged clean main `a84dbff` on its dedicated branch.

## Current State

- Active hypothesis: none; H001--H003, H005, H007, H022, H023, H027, H030,
  H031, H039, H044, H047, H051, H056, H057, H069, H075, H080, and H089
  accepted; H095 accepted on the direct lineage; H096 accepted atop merged
  main; H102 accepted atop H096; H134 accepted atop H102; H139 accepted atop
  H134; H155 accepted atop the C001--C011 clarity lineage.
- Next hypothesis ID: H170. H169 (volume-chain narrowing) accepted at a55b349; H168 was consumed by the refuted dp/dq narrowing (entry 6). Chapter A of the sizing audit is CLOSED; chapters B/C/D queued (entries 8-10), C recommended next. H167 (trg/aud stage 2, −107 floor, oracle 59/59) is measured on branch h167-trg-aud, pending the canonical seed-1 route and pico8 stage. C012 (width intent) merged at 6cb0539. H166 (timing-accumulator gcd reduction) accepted on branch h166-timing-gcd; it opens the Sizing Audit section. H165 (RDY wait-states + sfx_id BRAM migration, stage 1) is measured CANDIDATE on a worktree branch, held for the mix-four anchor decision — see its row. The 2026-08-03 `/goal` reopened the area loop
  after the clarity campaign closed it at H139. H155 (the H055 shared-limb
  retry) is accepted; it also restores a routable seed-1 canonical build,
  which clean `644d68f` had silently lost (see the H155 row). H161 is the
  accepted tip (rtl `e004a57e4ee8`, placed 7,027 @ 14 EBR).
- **2026-08-04 evening: the `pico8` gate red is FIXED** — not pacing but a
  shared-bus clobber: the sequencer consumed the live `m_res` against its
  *padded* busy, so a freeze in which the walk reused the multiplier left a
  walk product for the resumed consume. Fix: sequencer-owned `m_res_seq`
  latch in `psg.sv` (+29 pre-map / +59 `-noabc` floor, a correctness cost).
  All eight gates green, oracle 59/59 byte-identical, five-track pico8
  corpus green. Mechanism, diagnosis method and traps: the skill's
  psg-project.md and the `psg-pico8-fidelity` memory. **Re-record the area
  baseline (`make area-psg RECORD=1`) before measuring any candidate.**
- **MEASUREMENT DOCTRINE, 2026-08-04 — this supersedes the acceptance rule
  every row below was judged by.** abc9's covering is sensitive to the
  netlist's *encoding*, not just its content. Renaming a third of the PSG's
  cells with the circuit provably unchanged (pre-map pinned at 13,482) moves
  the floor over **62-72 cells**. The `+-60` band is therefore not a resolution
  limit -- it is *narrower than the noise*, and **a single abc9 build resolves
  nothing under ~100 cells.** Named phenomenon: Kahng & Mantik, "Measurement of
  Inherent Noise in EDA Tools" (ISQED'02) -- ordering is canonicalised away,
  RNG seeds move ~0.25%, naming moves up to 7%, hierarchy up to 12%, and noise
  is **not additive**, which is why H159 (0) and H160 (+31) composed to -33.

  | Instrument | value | spread over renames |
  | -- | -- | -- |
  | pre-map cells | 13,482 | 0 (by construction) |
  | `-noabc9 -noabc` floor | 8,879 | **0** |
  | `-noabc9 -flowmap` floor | 9,340 | not sampled |
  | `-noabc9` classic abc floor | 6,947 | 9 |
  | abc9 floor | ~6,840 median | **62-72** |

  **ROUTABILITY DOCTRINE (user-amended 2026-08-05).** The canonical build
  remains seed-1 router2. When and only when it exhibits the single-wire
  oscillation (overuse=1 flatlined for >20k router2 iterations with placement
  complete — the H055/H155 signature, drawn three times by H167 across
  distinct source texts), the routability requirement is satisfied by DUAL
  EVIDENCE: the same netlist must route with seed-1 router1 AND seed-2
  router2, both meeting timing, and the row must record all three results
  plus the oscillation. Rationale: placement is router-independent, so the
  canonical placed-LC number is still the seed-1 figure; the pathology is
  router2's rip-up loop, not the netlist, and two independent routing proofs
  preserve the contract's intent (reproducible evidence the design fits and
  times). The fallback is NOT permission to skip the canonical draw — it
  must be attempted and its wedge documented every time.

  **Procedure.** `scripts/detfloor.sh psg` gives the deterministic numbers;
  they must move in the right direction first. Only then sample abc9 with
  `tools/psg_area_dist.sh N label` (n>=16/arm) and compare with a rank test
  named *before* looking. `-noabc` is a ruler, not a result -- never quote
  8,879 as "the area".

  **RE-PRICED 2026-08-04 under the doctrine, both load-bearing:**

  | tree | pre-map | `-noabc` floor | classic-abc floor |
  | -- | -- | -- | -- |
  | `d76241f` H139 accepted | 13,487 | 8,881 | 6,952 |
  | `644d68f` after C001--C011 clarity | **13,487** | **8,881** | **6,952** |
  | `78b8bec` H155 | 13,482 | 8,879 | 6,947 |

  - **The "+28 floor drift" from the clarity commits is REFUTED. It was noise.**
    All three deterministic instruments are *identical* across the entire
    C-series -- the clarity passes changed the design's structure by exactly
    nothing, which is what "comment-only" always claimed. The ledger asserted
    the +28 was real "because the floor is a deterministic mapped resource and
    the band does not apply to it". That reasoning is wrong: deterministic is
    not the same as insensitive. There is no debt to recover and no candidate
    should ever again be charged for it.
  - **H155 is VINDICATED, at a smaller size than recorded.** Pre-map -5,
    `-noabc` floor -2, classic-abc floor -5: consistent in sign across every
    stable instrument, so the shared complemented noise limb is a real
    structural saving. Its recorded -6 abc9 floor happened to agree, but was a
    single draw and could not have established this on its own.

  **Consequence for this ledger.** Every verdict whose magnitude is under ~100
  cells rests on a single draw and is **unestablished** -- not wrong, but not
  demonstrated. That includes accepted H155 (-6 floor / -3 placed), the +28
  lineage drift attributed to the C-series clarity commits (almost certainly
  noise, not a cost), and most of the H140s-H150s rejection series. The
  campaign's large landings are unaffected: -190 placed, -128, -448 are far
  outside any plausible band. It is the sub-50 tail -- where the last ~15
  hypotheses lived -- that needs re-running under the doctrine above.
  Correctness is untouched: those stages were proven exact and rendered
  byte-identically. What is in question is the area accounting, not the chip.
- **READ THIS BEFORE APPLYING THE +-60 BAND TO ANYTHING.** The band is a
  resolution limit on **placed LCs only**, caused by abc9's order- and
  name-sensitive LUT covering. It does **not** apply to the packing floor
  (LUT4 + unpackable flops) or to pre-map cells: both are deterministic, so a
  -20 floor is a real -20 that banks and composes. `tools/psg_area_gate.sh`
  already encodes this -- it returns UNRESOLVED only when the floor is *flat*,
  and CANDIDATE whenever the floor improves, whatever the placed delta does
  inside the band. Rejecting every sub-60 candidate individually is a trap: it
  guarantees nothing is ever landed, because small deterministic wins can only
  become visible in aggregate. The 2026-08-03 pass fell into exactly this and
  binned two real wins (H156, H158's `q16` arm) before the error was caught.
  **The correct handling of a small real win is to bundle it, not to reject
  it.** What genuinely refutes a candidate is a measured *positive* net -- and
  the H149--H154 family supplies plenty of those (+47, +52, +72 floor), which
  is why those rows stand while H156/H158 were re-opened.
- **The never-examined space is priced; it is thin, not empty (H156--H158,
  2026-08-03, rescored 2026-08-04).** Attributing carry cells to net families
  -- which
  `tools/psg_ff_census.py` does not report, and which the LUT4-only ranking
  hid -- found seven families that no row in H001--H155 had ever named:
  `gz_filt_r` (259 LUT4 / 106 carries, the second-largest carry family),
  `s_old_phase` (164), `w_clr_tog` (157), `fstk` (155), `q16` (143 / 47),
  `old_q0` (109) and `w_ch_det` (92 / 39). Ablation ceilings: the whole
  `gz_filt_r` scale network is 52 cells (honest re-association ~8); the
  bundled `q16`/filter-max/`t_ix15` arithmetic is 76 cells with the behaviour
  deleted (honest ~11, and only the `q16` share is even a candidate). The
  complete remaining lifetime-alias pool is 17 flops. **Honest remaining sum
  across everything unexamined: about 19 pre-map cells** -- real and bankable,
  but only as part of a bundle, never as three separate stages each carrying
  its own proof and battery.
- **Open composition stage (2026-08-04) -- RE-PRICED BY H164, 2026-08-04
  evening: the cheap half is dead.** The gz re-association measures exactly 0
  (wreduce already performs it), the q16 share is subsumed by H161's index
  add, and H1' is closed at pool time by the pph precedent. **What survives is
  H4' alone (~-29 floor screened, sfx_id wash-risk documented) -- see the H164
  row before starting it.** The original text follows for the record. A plan,
  not a result: **none of
  these four has a measured net yet.** Each figure below is a component or a
  ceiling-minus-estimate, and H4's inputs are H101's *isolated* syntheses,
  which the record says reverse globally more often than not. Nothing here is
  bankable until the bundle is built and measured whole. **And the figures
  below are in the wrong currency:** H159 measured a -81 pre-map / -20 carry
  change at exactly **zero floor**, so every item here must be re-priced on
  mapped floor before it is banked. Treat these as screening numbers only.
  The items, none individually worth its own stage: `gz` re-association -8
  pre-map (H156); `q16` second-address adder share ~-11 carries (H158, gated
  on `q16[15:10] != 63`); the `sfx_id`/`trg_row`/`trg_len` state-mem migration
  ~-29 floor (H4', removal -90 floor against a +37 shared write-through and a
  +24 readback mirror); and the sequencer control-ROM address decode, whose
  replaceable core measures -41 pre-map (H1') but whose prefetch register and
  stall handling are still unpriced. Bundle total before H1' is about -48
  floor; with H1' it plausibly clears -70. Two rules for working it: bank only
  **nets**, never ablation ceilings, and re-measure the bundle as a whole,
  because candidates peeling at the same shared fabric cannot both pay.
- **Audit A001 (2026-08-04): the eleven accepted rows inside the noise are
  re-priced.** Nine of eleven are real (~236 floor cells total); **H057 and
  H096 delivered exactly zero** on both deterministic instruments and their
  recorded -23/-31 LUT4 were noise. Magnitudes elsewhere are unreliable even
  where signs are right (H007 claimed -46, delivers -6). The accepted lineage
  is sound. See the `Audit A001` section for the table and the method.
- **Analysis A002 (2026-08-04): residual selection measured at the mapped
  layer.** `tools/psg_mux_census.py`: ~1,000 of 6,300 shipped LUTs (16%) are
  pure 2:1 muxes (the mapped-layer counterpart of the catalog's 29% pre-map
  `$_MUX_`); 45% sit in u_walk. Only **16/2,034 are hold-muxes** — the DFFE
  enable-extraction lever class is empty. Independently confirms the
  catalog's largest-cluster call (old_rev/old_alt attribution 274) and
  calibrates its ceilings: the wave-side old-ctx steering that constant
  ablation prices at -315 ablates **to its replacement at -30 pre-map** —
  constant ablation over-attributes ~10x on this family. See the `Analysis
  A002` section.
- **Start here, not at H159:** the `Operation Cost Catalog (2026-08-04)` and
  `Clean-room Candidate Pool (2026-08-04)` sections below carry the measured
  ranking of every distinct operation, the four calibration constants that
  make those numbers readable, and ten priced candidates. The catalog answers
  "where is the area and what would removing it buy" without re-running 45
  ablations. Its headline: restructuring is closed, and area now tracks the
  *number of distinct scheduled operations* at ~38 cells of fabric each.
- ~~Known lineage debt, unattributed: the floor has drifted +28 cells since
  H139~~ -- **REFUTED by the measurement doctrine above** (all three
  deterministic instruments identical across the C-series). This bullet is
  kept struck-through because earlier sessions cited it; there is no debt,
  and no candidate should be charged for it.
- H139 integration status: I004 accepts the R.84 source rebinding and complete
  merge battery. The v6 contract binds canonical `d76241f`; both structural
  and value audits, complete forms, functional/cadence/render/PREVIEW/recovery/
  click/Celeste gates, and two forced canonical physical builds pass. The
  reproducible retained result remains 6,302 LUT4s, 1,291 carries, 1,450
  flops, 14 EBRs, floor 6,800 and 7,018 routed LCs at 142.63/31.17 MHz.
- H155 hypothesis row: retry H055's shared negative noise limb --
  `-(nz_mag + |frac|)` respelled as `~nz_mag + !|frac|` -- after H134/H139
  changed the pitched-noise consumer pipeline and its routing neighbourhood,
  meeting H055's recorded repeat condition. Decision: accepted. The exhaustive
  262,144-case scalar proof and unconstrained SAT miter pass; the identity is
  retained as `noise.round_shared_limb` in `tools/psg_hw_forms.py`. Measured
  against clean `644d68f` (rtl `23c2bbe7dc6e`) with the unchanged July
  toolchain: pre-map 13,487 -> 13,482 cells (-3 `$_AND_`, -2 `$_XOR_`;
  carries, flops, EBRs unchanged); canonical map 6,333 -> 6,330 LUT4s, 1,291
  -> 1,292 carries, 1,450 flops, 501 -> 498 unpackable, floor 6,834 -> 6,828,
  14 EBRs; seed-1 placement 7,055 -> 7,052 LCs. Decisively, clean `644d68f`
  itself does NOT complete seed-1 router2 -- overuse flatlines at two wires
  through 18,052 iterations, the exact H055 failure signature -- while the
  H155 netlist routes at 7,052 LCs and 33.50/138.20 MHz PSG/fast, both
  passing. The clean-HEAD numbers differ from accepted H139's retained
  6,302/floor 6,800/7,018 routed because the C-series clarity passes changed
  source text and line numbers and abc9's covering is order/name-sensitive;
  C010's "unchanged by construction" inference bound the canonicalized token
  stream, not the physical artifact. Full battery on the H155 tree: full and
  PREVIEW lint at the three established width warnings; `make test-psg` ALL
  PASSED (PICO-8 statistical fidelity, fold, 524,288 dq formulas + 57,344
  transactions, 93 audio-analysis and 13 visualizer tests); all 59 frozen
  renders byte-identical and diagnostic-clean at 18.75 MHz; `make
  test-clocks` /4 /5 /6 PASS; PREVIEW P.1 passes both 1,275- and 159-clock
  rates; synthetic and Celeste recovery ALL TESTS PASSED with zero coalesced,
  delayed or dropped samples; zero `click-v1` events in both modes; the
  five-frame Celeste smoke is byte-identical at SHA-256 `3d4933a9...` with
  2,079/3,668 off-centre samples, range -21,544..7,711 and 1,014 levels; a
  forced canonical rebuild reproduces the JSON/ASC byte-identically.
- H154 hypothesis row: encode the production radix-2 multiplier's five fast-
  step classes in prefix bits above each request class's proved live `B`
  width. Preserve all twelve `B` bits for the sole twelve-step class, use the
  otherwise-zero thirteenth payload bit plus the two high bits that are dead
  for every shorter class as a prefix, and retire the separate four-bit
  `req_steps` source-domain payload. Decision: rejected and reverted. Exact
  proof and the complete isolated service improve floor 148 -> 146 with three
  fewer flops, but the canonical whole PSG adds 51 LUT4s, one unpackable flop
  and 52 floor cells.
- H153 hypothesis row: retire the standalone `cpz` copy-zero flag into
  `note_lo[7]`, which is dead after the note consumer on every K_ADV/EA5 route
  that can reach PC3. Preserve the captured historical decision that H122
  proved cannot be reconstructed from live `playing`. Decision: rejected
  before production; one unpackable FF becomes one LUT4 and floor stays 33.
- H152 hypothesis row: retire the duplicate eight-bit effective-filter tuple
  by letting the existing base-filter working tuple hold the effective value.
  Preserve the base tuple in its existing record fields, refresh those fields
  during trigger setup, and recover them through otherwise-idle scheduled
  state reads only when a note transition leaves or retriggers an instrument.
  Decision: rejected and reverted. Exact proof and isolated synthesis retire
  eight flops and five floor cells, but the canonical whole PSG adds 72 LUT4s,
  four carries and 72 floor cells while leaving unpackable flops unchanged.
- H151 hypothesis row: retire the divider's eight-bit captured divisor and
  consume the stable live `eff_sp`, with the sole `/7` request identified by
  its existing `K_FX/xs=10` wait state. Decision: rejected and reverted. The
  isolated floor improves by three cells and eight flops retire, but the
  canonical whole PSG adds 31 LUT4s, four carries, 25 floor cells and 32
  routed LCs.
- H150 hypothesis row: store only `fade_step[11:0]`; among the fade-eligible
  table indices 1--31, a zero low field uniquely encodes index 1's value 4096.
  Decision: rejected before production RTL. Exact proof passes and one
  unpackable flop retires, but three LUT4s worsen the isolated floor by two
  cells.
- H149 hypothesis row: store the one-cycle displaced-control collision fact in
  `fstep_q[12]` only while the fade lookup is replaying, when an adjacent
  `$20` consumes `crom_q` directly and the prior fade-step value is
  unobservable. Decision: rejected and reverted. Exact proof passes and the
  isolated floor improves by twelve cells, but the canonical whole PSG adds
  58 LUT4s, five carries, 47 floor cells and 58 routed LCs.
- H148 hypothesis row: give the fade-step lookup its own 32x13 synchronous
  ROM, preserving the accepted two-cycle sequencer hold and displaced-control
  stall while removing the shared constants-port address arm and external
  `fstep_q` lifetime. Decision: rejected and reverted. Exact proof and isolated
  synthesis save 22 LUT4s, thirteen flops and 35 floor cells, but the canonical
  whole PSG adds nineteen LUT4s, four carries, five floor cells and thirteen
  routed LCs while spending the fifteenth EBR.
- H147 hypothesis row: narrow reachable live/last/old gain history from
  thirteen to twelve bits while preserving the oscillator-record bit
  positions. Decision: rejected and reverted. Exact isolated synthesis saves
  five LUT4s and two FFs, but the canonical whole PSG adds 26 LUT4s, two
  carries, 27 floor cells and 33 routed LCs, and fails fast timing.
- H146 hypothesis row: select the mutually exclusive `/64`, `/128`, or
  `/256` DQ ceiling operands before one eight-bit incrementer. Decision:
  rejected and reverted. Exact isolated synthesis saves thirteen LUT4s and
  eleven carries, but the canonical whole PSG adds 36 LUT4s, one carry, 36
  floor cells and 43 routed LCs.
- H145 hypothesis row: serialize W84 dampen accumulation and rounding through
  the idle fold ALU, storing the signed-19 intermediate in dead `mxs_old` plus
  `smp_a` storage before the late state write. Decision: rejected before
  production RTL. Exact exhaustive/SAT proofs pass and carries fall, but the
  best complete isolated consumer worsens the LUT-plus-unpackable floor by
  twelve cells; encoding the second phase in `fmc` is worse again.
- H144 hypothesis row: exploit accepted H039's four-byte-aligned record base
  at the final byte-offset addition, adding only `sa_off[7:2]` to the eleven-
  bit word address and appending `sa_off[1:0]`. Decision: rejected before
  production RTL; the identity and SAT proofs pass, but the complete registered
  consumer is mapping-identical because Yosys already exploits the alignment.
- H143 hypothesis row: preserve exact reset-zero PCM output with one resettable
  validity token and a resetless 16-bit committed payload, targeting the
  H139 census's sixteen unpackable `pcm` flops. Decision: rejected before
  production RTL. Exact transition/SAT proofs pass, but the payload flops stay
  unpackable and the validity token raises the isolated floor by three cells.
- H142 hypothesis row: extend `mx_old`'s accepted old-noise-step role by
  overwriting it at CAP_W1 with the proved signed-17 old pre-clamp sum, then
  retain its existing W51 old-gain role and retire `nz_old_out_r`. Decision:
  rejected before production RTL. Exact range/exhaustive/SAT proofs pass and
  eleven unpackable flops disappear, but seventeen additional LUT4s worsen the
  complete isolated floor by six cells.
- H141 hypothesis row: encode the serial soft-add underflow path in unused
  `fmc` states 12--15 instead of the separate `f_under` flop. Decision:
  rejected and reverted. The exact isolated controller removes one unpackable
  flop/floor cell, but the canonical whole PSG adds 24 LUT4s, four carries, 20
  floor cells and 31 routed LCs.
- H140 hypothesis row: select the live CAP_W0 or old CAP_W1 signed-18 noise
  accumulation inputs before one shared add/clamp cone. Decision: rejected and
  reverted. The exact isolated consumer saves eight LUT4s, seventeen carries
  and five floor cells, but the canonical whole PSG adds 30 LUT4s, three
  unpackable flops, 33 floor cells and 36 routed LCs.
- H139 hypothesis row: select the live W4 or old W15/W27 registered pre-clamp
  noise value and increment before one exact shared post-shift scale tree,
  replacing the two parallel `nz_z`/`nz_old_z` trees without changing either
  register. Decision: accepted. Exactness, canonical physical, complete
  fidelity/cadence/PREVIEW/recovery/click/smoke, and forced-reproducibility
  gates pass; the retained result saves 58 LUT4s, 26 carries, two floor cells
  from packing, 60 deterministic floor cells, and 68 routed LCs.
- H138 hypothesis row: narrow the two registered live/old pre-clamp noise
  values from signed 18 to 17 bits, retaining explicit signed-18 views at
  their output-scaling consumers. Decision: rejected and reverted. The exact
  isolated floor improves six cells, but the canonical whole PSG adds 29
  LUT4s and 28 floor cells despite removing seven carries and two flops.
- H137 hypothesis row: replace the shared-EBR fade-step borrow with an exact
  32-entry combinational decode from the retained `fade_len[7:3]`, removing
  `fstep_q`, the lookup-port mux, and both replay/displacement tokens. Decision:
  rejected and reverted. The isolated floor improves eight cells, but the
  canonical whole PSG adds 84 LUT4s, one carry and 72 floor cells.
- H136 hypothesis row: carry each multiplier request's arithmetic sign through
  the otherwise-dead `m_res[33]` result bit, preserving it across the chained
  reciprocal request, and retire full-schedule `mxs_new`/`mxs_old`. Decision:
  rejected before production RTL. The token is exact, but the multi-pumped
  boundary activates both `req_b[12]` and `m_p[33]`, replacing rather than
  reducing the two sign flops; the production-shaped isolated floor worsens
  274 -> 275 cells.
- H135 hypothesis row: retire the adjacent 17-bit `mx_new` result into
  `smp_b`. Exhaustive and both full-path nine-step SAT miters pass, but the
  complete registered consumer changes 58 -> 95 LUT4s, 72 -> 55 flops and
  floor 77 -> 96 cells. Decision: rejected before production RTL.
- H131 hypothesis row: replace the `aud_sl(...) == c` row-owner relation with
  the exact foreground-play XOR. All 65,536 slot/play/phase tuples and
  arbitrary-state SAT pass, but both complete row writers map identically at
  18 LUT4s and twenty unpackable flops. Decision: rejected before production.
- H130 hypothesis row: select the addressed CPU status channel/slot before its
  row/SFX payload instead of building the 44-bit all-channel bus first. All
  2,048 control/index cases and full-domain SAT pass, but the complete
  registered readback grows from 61 to 63 LUT4s with seven packed flops in
  both. Decision: rejected before production RTL.
- H129 hypothesis row: split the live 48-bit `sfx_id` FF array into its fixed
  foreground/music banks. Full-domain SAT and 16,384 control/index cases pass,
  but both forms retain 48 unpackable flops and the split consumer grows from
  76 to 86 LUT4s. Decision: rejected before production RTL.
- H128 hypothesis row: `psg_seq` rechecks `rw` after receiving the already
  qualified `cs_wr` pulse. Removing that redundant term is exact over all
  2,048 bus/address tuples and with SAT, but both complete registered event
  decoders map to nine LUT4s and four packed flops. Decision: rejected before
  production RTL.
- H127 hypothesis row: phaser detune-1 currently computes both low-six-bit
  threshold predicates (`>=43` and `>=22`) even though `dp13[6]` selects only
  one. Select the threshold first, compute one predicate, and reconstruct the
  exact two-bit `ceil(3*r/128)` quotient from that predicate, `dp13[6]`, and
  low-remainder nonzero. Both spellings are exact. Explicit Boolean sharing
  adds two isolated LUT4s; the direct comparator saves three isolated LUT4s
  for six carries but adds 50 whole-PSG LUT4s and 49 floor cells. Decision: rejected
  and reverted before routing or fidelity work.
- H126 hypothesis row: `ctrl_displaced` remembers whether a `$22` fade-table
  lookup displaced a live walker control read, while `crom_replay` remembers
  only the lookup. Deriving the replay stall as `crom_replay && prun` observes
  post-edge walker validity instead of the prior `ctrl_read`: an idle
  `sample_en + $22` edge therefore invents a stall and leaves the new walk one
  phase behind. Decision: rejected before synthesis or RTL.
- H125 hypothesis row: `s_ch_noiz` is loaded on the same edge as the
  unreachable `s_eff_a[11]` bit and maps as a separate unpackable flop whose
  named fanout cone contains 92 LUT4s. Pack this materially higher-fanout
  payload into bit 11 while masking only numeric amplitude consumers. The
  exact registered cone saves 31 LUT4s, one carry and one FF, but the whole
  PSG adds 45 LUT4s, two carries and 45 floor cells. Decision: rejected and
  reverted.
- H124 hypothesis row: the walker stores the full-mode clear toggle in one
  dedicated flop while all reachable amplitudes fit eleven bits and the
  existing twelve-bit `s_eff_a` storage still maps bit 11. Pack the clear
  toggle into that dead storage bit. The exact registered cone saves 29 LUT4s,
  one carry and one FF, but both production spellings add 39 whole-PSG LUT4s,
  two carries and 39 floor cells. Decision: rejected and reverted.
- H123 hypothesis row: `spar_last` and `nz_tick_r` retain a two-sample bank
  history even though the pulse is consumed only during the following sample
  walk. Holding `spar_last` through the walk and deriving the pulse from the
  live bank observes a same-edge publication one sample too early; a dropped
  PREVIEW start also has no terminal edge on which to advance history.
  Decision: rejected before synthesis or RTL.
- H122 hypothesis row: the sole `cpz` consumer at PC3 is reached only from
  K_ADV's skip path or EA5's two stop paths. Live-state reconstruction fails:
  a CPU stop may change `playing[c]` during K_ROT..PC3 after `cpz=0` was
  captured. Decision: rejected before synthesis or RTL.
- H121 hypothesis row: the canonical 272-credit limiter's sticky
  `{seq_phase,seq_count}` representation visits exactly the same nine-bit
  states as a counter seeded at 239 and stopped at 511. The single-register
  form saves two isolated floor cells but adds thirteen whole-PSG LUT4s, five
  carries and nine floor cells. Decision: rejected and reverted.
- H120 hypothesis row: `fade_dir` is the reset-valid bit for `fade_acc` and
  `fade_step`; every transition from idle to an active fade initializes both
  payloads on the same edge, and every payload read is guarded by active
  direction. The exact reset removal adds one isolated LUT4 and retires no FF
  or unpackable cell. Decision: rejected before production.
- H119 hypothesis row: PREVIEW and the canonical multi-pumped schedule need
  only six `pph` bits, while the compatibility single-clock schedule retains
  seven. The exact width derivation removes one FF and five carries, but adds
  35 LUT4s, 34 floor cells, and 32 routed LCs. Decision: rejected and
  reverted.
- H118 hypothesis row: every `vol_r` producer stays in 0..1,792, but the
  mapped design retains all twelve declared bits. Narrow the complete stored
  volume/interpolation/instrument-scaling cone to eleven bits and explicitly
  zero-extend only at the unchanged 12-bit publication/service boundaries.
  Both exact variants save one FF but add 35/60 LUT4s, 35/57 floor cells,
  and 41/66 routed LCs. Decision: rejected and reverted.
- H117 hypothesis row: `prun` is the reset-valid bit for the walk controller,
  and the first accepted sample initializes `pc_ch` and `pph` before any
  prun-gated read, write, request, or action can observe them. Remove only
  their redundant synchronous-reset bits while retaining their ordinary
  assignments, controller encoding, and schedule. The exact combined and
  channel-only variants add 34/56 LUT4s, 40/56 floor cells, and 44/64 routed
  LCs. Decision: rejected and reverted.
- H116 hypothesis row: retire the eight `w_ch_{damp,rev,det,buzz,noiz}`
  effective-filter flops into the existing inactive parameter-bank word. Copy
  active P_W2 to inactive at V_LD outside join passes, overwrite its filter
  field at ordinary K_LD or I_TR1, pre-read it during K_FX,
  and update its late effect-1 bit at P_W2. This adds no state or sequencer
  cycle and materially changes H099's retained-flop ownership. The two exact
  variants retire eight FFs but add 20/51 LUT4s, 21/52 floor cells, and 30/53
  routed LCs. Decision: rejected and reverted.
- H115 hypothesis row: the three instrument/base filter joins take the numeric
  maximum of two-bit values whose reachable domain is only 0, 1, or 2. An
  explicit bounded max may replace comparator/mux logic with one high-bit OR
  and one low-bit predicate per field. The exact bounded and comparator forms
  both map to six LUT4s and six flops. Decision: rejected before production.
- H114 hypothesis row: the complete reciprocal output domain is 0..32767
  minus 8192 or 12286, so the current 18-bit subtract result always fits
  signed 16 bits. An explicit narrow subtract followed by sign extension is
  exact, but the global map adds 27 LUT4s, four carries, 25 floor cells, and
  28 routed LCs. Decision: rejected and reverted.
- H113 hypothesis row: the top-level multiplier request combines the mutually
  exclusive walker and sequencer payloads with five bitwise OR networks. Keep
  the same ORed start signal, but select the captured payload from its active
  owner. This may let Yosys retain the owner predicate through the large
  flattened `req_a`/`req_b` cones instead of independently merging every bit.
  The request cones shrink, but the global map adds 66 LUT4s, four carries,
  66 floor cells, and 73 routed LCs. Decision: rejected and reverted.
- H112 hypothesis row: packing pending trigger row and length into one 11-bit
  FF array preserves all 6,291,456 field/priority transitions, but the complete
  separate and packed consumers both map to 61 LUT4s and 44 flops. Decision:
  rejected before production RTL.
- H111 hypothesis row: every non-reset readback branch assigns
  `aram_rd_pending_next=aram_cpu_rd`; hoisting that assignment is exact, but
  the complete registered baseline and candidate both synthesize to 14 LUT4s
  and nine flops. Decision: rejected before production RTL.
- H110 hypothesis row: `join_stage` cannot be reconstructed from live
  `bank_ready`, `walk_tick`, and controller state. If `tick_en_d` publishes a
  pending bank on the same `S_IDLE` edge that a trigger starts a join pass, the
  next state is `join_stage=1`, `bank_ready=0`, `walk_tick=0`, `V_LD`.
  Decision: rejected before production RTL or synthesis.
- H109 hypothesis row: Yosys declines automatic recoding of the 60-state
  sequencer FSM and leaves its many equality consumers on a six-bit binary
  state. Force complete one-hot synthesis encoding and gate on the deterministic
  LUT-plus-unpackable-FF floor, not LUT count alone. Mapping reduces that floor
  by eleven cells and placement by three LCs, but canonical routing remains
  stuck on one overused wire through 29,349 iterations. Decision: rejected and
  reverted.
- H108 hypothesis row: `REVERB=0` already folds both comb datapaths to the
  identity, but `blend_restart` still compares the live and prior reverb modes,
  retaining disabled-feature control/state in the HX8K build. Gate only that
  restart term with `REVERB`; preserve `REVERB=1` textually. Whole-PSG mapping
  adds 39 LUT4s, four carries, one unpackable FF, 40 floor cells, and 47 routed
  LCs. Decision: rejected and reverted before equivalence work.
- H107 hypothesis row: `psg_seq` stores playback activity in an unpacked
  `playing[]` array and continuously repacks it into the dynamically indexed
  output `play_bits`. Use `play_bits` as the sole packed storage to remove the
  duplicate representation and simplify source/array lowering. Whole-PSG
  mapping adds 79 LUT4s, two carries, 73 floor cells, and 79 routed LCs despite
  six fewer unpackable FFs. Decision: rejected and reverted.
- H106 hypothesis row: after diagnostic readback was composed on main, upload
  data writes and CPU reads contain two priority-separated copies of the same
  16-bit pointer increment. Factor one exact advance transaction without
  changing H005's index/window form. The 6,291,456-transition proof, hold test,
  and 4,608-byte readback pass, and the isolated consumer falls from 51 to 49
  LUT4s. Whole-PSG mapping instead adds 51 LUT4s, one unpackable FF, 52 floor
  cells, and 54 routed LCs. Decision: rejected and reverted.
- H105 hypothesis row: `vcnt` only visits 0--7 because V_LD terminates at 7
  and V_ST terminates at 4, yet the accepted netlist maps all four declared
  counter bits. A three-bit form is exact and removes one FF/two carries in the
  complete isolated consumer, but adds 24 LUT4s. Decision: rejected before
  production.
- H104 hypothesis row: encode the three legal instrument-kind states directly
  as one-hot `{wavetable, SFX}` rather than `{on, wavetable}`. This keeps two
  flops but makes both hot mode predicates direct wires. The proof passes, but
  the complete isolated consumer changes from 138 to 139 LUT4s with two FF and
  eight carries unchanged. Decision: rejected before production.
- H103 hypothesis row: the post-H096 launched mask and ascending T_NL scan do
  identify the fallback-speed owner exactly, but spelling that ownership as a
  lower-bit priority predicate changes the complete isolated consumer from 26
  to 28 LUT4s while retiring only one FF. Decision: rejected before production.
- H102 hypothesis row: encode wavetable bass in `w_ins_fx[0]`, which is forced
  zero and otherwise dead whenever `w_ins_wt=1`, and retire the dedicated
  `w_ins_bass` working flop. The 1,024-tuple mode/store/reload proof and complete
  H096 battery pass; two forced builds reproduce 6,360 LUT4 / 1,321 carry /
  1,458 FF / 508 unpackable / 14 EBR / floor 6,868 / 7,087 routed LCs at
  140.92/32.65 MHz. Decision: accepted as generic RTL/proof commit `ccfb2a0`.
- H101 hypothesis row: store the four pending trigger row/length tuples in one
  prefetched block RAM, with resettable per-field valid bits preserving zeroed
  state and same-edge CPU-write precedence. A plain EBR has a one-cycle stale
  read counterexample; both exact forwarding variants exceed the 97-cell
  isolated reference floor. Archive audit: this inadvertently duplicated
  legacy R.44's already-closed mechanism; no production edit was repeated.
  Decision: rejected before production RTL.
- H100 hypothesis row: restrict `released` storage to the four foreground
  slots. Music-slot bits have no set path and are therefore invariant zero;
  their loop condition can bypass the foreground array. The proof passes
  2,560 transitions, but Yosys already removes the upper elements and both
  complete isolated forms map identically. Decision: rejected before
  production RTL.
- H099 hypothesis row: stop rewriting the effective channel-filter tuple from
  the base tuple and publish the already-live base tuple when `w_ins_on=0`.
  The ownership proof passes 4,224 legal paths and the isolated consumer falls
  from 29 to 12 LUT4s, but both whole-PSG variants regress. Decision: rejected
  and reverted.
- H098 hypothesis row: encode the fast multiplier's exact 3--12 active-step
  durations as start points on one four-bit maximal-LFSR segment. The token is
  exact and removes four LUT4s/two carries in isolation, but the whole PSG adds
  20 LUT4s, 19 floor cells, and 16 routed LCs. Decision: rejected and reverted.
- H097 hypothesis row: retire `ml_cpu` by reusing `walk_tick` as the
  `ML_STOP` provenance token. The invariant is exact and saves three LUT4s and
  one FF in isolation, but the whole PSG adds 18 LUT4s, four carries, 17 floor
  cells, and 20 routed LCs. Decision: rejected and reverted.
- H096 hypothesis row: retire `tch_seen` by consuming the existing launched-
  channel worklist when the left-most qualifying music channel owns pattern
  pacing. Exhaustive scan equivalence covers all 256 launch/qualifier masks.
  The complete merged-main battery passes, and two forced builds reproduce
  6,364 LUT4 / 1,321 carry / 1,459 FF / 509 unpackable / 14 EBR / floor 6,873 /
  7,095 routed LCs at 151.17/33.09 MHz. Decision: accepted as generic RTL/proof
  commit `a647185`. Repeat only if launch ordering, T_NL visitation, or pacing
  ownership changes.
- Current evidence: `build/experiments/h001/` and
  `build/experiments/h002/`, `build/experiments/h003/`, and
  `build/experiments/h005/`, `build/experiments/h007/`,
  `build/experiments/h022/`, `build/experiments/h023/`,
  `build/experiments/h024/`, `build/experiments/h025/`, and
  `build/experiments/h026/`, `build/experiments/h027/`, and
  `build/experiments/h028/`, `build/experiments/h029/`,
  `build/experiments/h030/`, `build/experiments/h031/`, and
  `build/experiments/h032/`, `build/experiments/h033/`, and
  `build/experiments/h034/`, `build/experiments/h035/`, and
  `build/experiments/h036/`, `build/experiments/h037/`,
  `build/experiments/h038/`, `build/experiments/h039/`, and
  `build/experiments/h040/`, `build/experiments/h041/`, and
  `build/experiments/h042/`, `build/experiments/h043/`, and
  `build/experiments/h044/`, `build/experiments/h045/`, and
  `build/experiments/h046/`, `build/experiments/h047/`, and
  `build/experiments/h048/`, `build/experiments/h049/`, and
  `build/experiments/h050/`, `build/experiments/h051/`, and
  `build/experiments/h052/`, `build/experiments/h053/`, and
  `build/experiments/h054/`, `build/experiments/h055/`, and the copied direct-
  frontier `build/experiments/h056/`, `build/experiments/h057/`,
  `build/experiments/h058/`, `build/experiments/h059/`, and
  `build/experiments/h060/`, `build/experiments/h061/`, and
  `build/experiments/h062/`, `build/experiments/h063/`, and
  `build/experiments/h064/`, `build/experiments/h065/`, and
  `build/experiments/h066/`, `build/experiments/h067/`, and
  `build/experiments/h068/`, `build/experiments/h069/`,
  `build/experiments/h071/`, `build/experiments/h072/`,
  `build/experiments/h073/`, `build/experiments/h074/`,
  `build/experiments/h075/`, `build/experiments/h076/`,
  `build/experiments/h077/`, `build/experiments/h078/`,
  `build/experiments/h079/`, `build/experiments/h080/`, and the accepted
  `build/experiments/h089/`, `build/experiments/h090/`, and
  `build/experiments/h091/`, `build/experiments/h092/`, and the rejected
  `build/experiments/h093/`, the rejected `build/experiments/h094/`, and the
  accepted `build/experiments/h095/` and `build/experiments/h096/`, the
  rejected `build/experiments/h097/`, `build/experiments/h098/`, and
  `build/experiments/h099/`, `build/experiments/h100/`,
  `build/experiments/h101/`, the accepted `build/experiments/h102/`, and the
  rejected `build/experiments/h106/`, `build/experiments/h107/`, and
  `build/experiments/h108/`, `build/experiments/h109/`, and the rejected
  `build/experiments/h110/`, `build/experiments/h111/`,
  `build/experiments/h112/`, `build/experiments/h113/`,
  `build/experiments/h114/`, `build/experiments/h115/`, and
  `build/experiments/h116/`, `build/experiments/h117/`,
  `build/experiments/h118/`, `build/experiments/h119/`, and the rejected
  `build/experiments/h127/`, plus
  `build/experiments/h009/`, `build/experiments/h010/`, and
  `build/experiments/h012/` and `build/experiments/h013/` synthesis,
  placement, click, recovery, and smoke artifacts as applicable.
- Latest completed decision: H127 rejected after exhaustive/SAT arithmetic
  proof, two complete registered-consumer maps, full/PREVIEW lint, and a
  canonical whole-PSG map. The explicit shared Boolean form adds two isolated
  LUT4s. The direct selected comparator changes 49 LUT4/19 carry locally to
  46/25, but changes the accepted whole PSG from 6,360 LUT4/1,321 carry/floor
  6,868 to 6,410/1,321/floor 6,917 with flops and EBRs unchanged. Production
  RTL is byte-for-byte restored; route and fidelity gates were correctly
  skipped. H126 was rejected after exhaustive edge-order proof.
  Across full multi-pumped, compatibility single-clock, and PREVIEW schedules,
  3,750 transition classes agree, while ten accepted same-edge walk starts
  produce a false candidate stall and eight terminal closures lose the
  baseline history bit. Adjacent `$22/$20` writes retain the fade value, but
  the start collision changes walker phase and control-ROM prefetch. No RTL or
  synthesis gate ran. H120 was rejected after inductive/SAT validity proof and
  complete isolated registered-consumer synthesis. Removing 29 payload reset
  assignments adds one LUT4 while retaining all 41 FFs and the same 13
  unpackable cells. H119 was rejected after exact three-mode schedule
  proof, lint, and canonical whole-PSG place-and-route. The elaboration-
  specific `pph` width removes one FF and five carries but adds 35 LUT4s and
  32 routed LCs. H118 bounded the volume cone to eleven bits, but narrowing it
  saves one FF while adding 35/60 LUT4s and 41/66 routed LCs. H117 removed reset from
  validity-dominated walk payloads but added 34/56 LUT4s and 44/64 routed LCs.
  H116 moved the eight effective-filter
  bits into inactive P_W2 but added 20/51 LUT4s and 30/53 routed LCs.
  I003 remains the accepted H102 source-contract v5 integration, and H102
  remains the best accepted generic RTL/proof point at `ccfb2a0`.
- Latest rejected variants: H127's two exact selected-threshold spellings are
  locally neutral/trade LUTs for carries and globally much worse. H126's
  replay/live-valid reconstruction loses the
  prior-edge collision fact on walker start/finish transitions. H125's
  high-fanout amplitude-bit packing and H124's low-fanout form both save a
  local flop/cone but regress the global map. H123's bank-history
  reconstruction mishandles same-edge publication and dropped PREVIEW starts.
  H120's exact fade-payload reset removal is locally
  worse despite simpler source. H119's exact elaboration-specific walk-phase
  width is globally worse despite one fewer FF and five fewer carries. H118's
  exact volume-width contraction is globally
  worse despite one fewer FF. H117's validity-dominated reset removal is
  globally worse despite unchanged state count. H116's EBR-owned effective-filter lifetime is
  globally worse despite eight fewer FFs. H115's bounded filter max is already recovered by
  Yosys. H114's exact narrow reciprocal subtract defeats
  Yosys's better implicit width reduction. H113's owner-selected multiplier request payload
  shrinks `req_a`/`req_b` but globally expands downstream cones. H112's
  exact trigger-metadata packing is already
  recovered by Yosys. H111's exact pending-valid hoist is already
  recovered by Yosys. H110's join-mode reconstruction loses historical
  state on a same-edge bank publication/pass start. H109's one-hot sequencer state lowers mapped floor
  and placed LCs slightly but cannot route. H108's `REVERB=0` restart specialization is
  globally much worse before equivalence work. H107's packed playback register is globally much
  worse despite simpler source and fewer unpackable FFs. H106's exact factored
  upload/read pointer advance
  is globally much worse despite its two-LUT4 isolated saving. H101's pending-
  trigger EBR is inexact without
  forwarding and locally worse with it. H100's unreachable music release bits are already
  removed by Yosys. H099's exact filter-publication ownership change
  is globally worse despite its 17-LUT4 isolated saving. H098's exact multiplier iteration token is globally
  worse despite its isolated four-LUT4/two-carry saving. H097's exact `ML_STOP` provenance reuse is globally
  worse despite its isolated three-LUT4/one-FF saving. H094's packed transition inequality is globally
  worse despite its isolated one-LUT4 saving. H093's grouped DQ table is locally
  worse. H092's result-flop merge is globally worse despite
  its isolated one-LUT4/one-FF saving. H091's remaining-ticks compression changes
  post-wrap completion. H090's shared step-count decode is locally worse.
  H079's exact reverb rounding is globally worse.
  H078's exact threshold fusion is locally worse.
  H074's affine slide carry is observably required.
  H073's aligned noise offset is already recovered
  by Yosys. H072's exact dampen post-shift correction is
  globally worse despite its carry win. H071's exact blend post-shift correction is
  globally worse despite its isolated win. H070's exact divider iteration token is globally
  worse despite its isolated win. H068's exact pre-terminal DQ result retention
  regresses deterministic floor and placement despite its isolated LUT win.
  H067's exact tilt-quotient prefix factorization is
  already recovered by Yosys. H066's exact reciprocal-index tail sentinel is
  globally worse and misses fast timing. H065's exact sample-register width contraction is
  globally worse despite its isolated four-FF saving. H064's exact selected noise-draw XOR sharing is
  globally much worse despite its isolated win. H063's exact old-arm sign lifetime retirement is
  globally much worse despite its isolated one-FF saving. H062's exact old-noise flag reconstruction is
  globally much worse despite its isolated win. H061's exact fade-state compression fails its
  isolated LUT/floor gate. H060's exact triangle `/4` payload reconstruction
  regresses every whole-PSG area metric except FF count. H059's exact organ quotient reconstruction
  regresses every whole-PSG physical area gate. H058's exact replay-flop retirement fails every
  physical area gate and does not route. H055's two signed-noise-rounding forms
  fail the complete physical gate. H054's centered triangle fold is locally worse.
  H053's fold-state publication token is globally
  worse. H052's selector-state final token is locally worse.
  H050's upload-page Boolean outputs are globally
  worse despite a zero-carry isolated form. H049's Boolean square/pulse thresholds worsen the
  global LUT/floor/placement trade. H048's two-axis selector adds 16 isolated LUT4s.
  H046's global decode/fanout remap overwhelms its
  three-LUT4 isolated win. H045's source-closed trit identity produces no
  isolated physical saving. H043's named active/advance predicates are already
  recovered by Yosys. H042's exact four-input truth table becomes
  globally worse despite its one-LUT4 isolated win. H041's shared exact prefix trades four isolated
  carries for two LUT4s, but becomes globally worse in LUT4s and placement.
  H040's explicit conditional complement becomes
  globally worse despite its isolated win. H038's residue correction costs 28 LUT4s locally.
  H037's conditional dead bit is already removed by Yosys. H036 loses its local register saving to global D-input/fanout
  remapping. H035 is mapping-identical because Yosys already
  shares the nested suffix logic. H034's exact prefix regresses every global
  area metric. H033's exact paired CPU activity bit maps identically to the current
  dynamic audible-slot lookup. H032's isolated record-base
  sharing saves one LUT4 and seven carries, but adds 32 LUT4s and 32 placed LCs.
  H029's large isolated LUT saving becomes a slight LUT/placement regression
  in the whole PSG. H028's local carry saving disappears in the full
  selector context. H026's first carry form misses only `a=255,b=0`;
  its repaired zero-bound form is exact but globally worse as above. H025's
  shared fade sum is mapping-identical. H024 proves both clamp-to-32 bounds are exact prefix
  intervals, but the whole-PSG map regresses as above. H021 proves the 32-arm filter decode is wrapped
  base-3, but the existing table maps to 23 LUT4/no carries versus 28 LUT4/70
  carries for direct arithmetic and 26 LUT4/11 carries for staged thresholds.
  H020 proves the audio-RAM busy export is contained
  inside `prun` and locally saves one LUT4, but whole-PSG mapping adds three
  LUT4s/three carries and seed-1 placement adds one LC. H019 proves whole-walk state-memory ownership is
  behaviorally exact and both forms reduce the isolated mux/store cone, but
  whole-PSG mapping adds 48 LUT4s/seven carries for the complete bundle and 22
  LUT4s/six carries for the retained-enable-OR form. H018's exact 25-bit
  half-sum trades one local carry for one LUT, but whole-PSG mapping adds 31
  LUT4s, nine carries, and 38 LCs.
  H017's full context sharing maps locally much
  smaller but globally adds 16 LUT4s and 36 placed LCs; scale-only sharing
  still adds 11 LUT4s and 22 placed LCs. Both save six mapped carries. H016 proves a nine-bit restoring subtract is exact
  and locally trades one carry for one LUT, but whole-PSG mapping adds 60
  LUT4s, eight carries, and 67 placed LCs. H015 proves the final detune subtract qualifier is
  algebraically redundant, but both registered cones map identically at 188
  LUT4s, 73 carries, and 14 flops. H014 proves all detune corrections fit eight bits,
  but the complete registered detune cone maps identically at 189 LUT4s, 73
  carries, and 14 flops: Yosys already removes the unreachable ninth bit.
  H013 proves the internal multiplier recurrence fits 29 bits, but both the
  two-service and target-only forms add 24 LUT4s/three carries and 26 placed
  LCs while removing two flops. H012 proves the true-
  busy OR is invariant-redundant and locally saves one LUT4, but whole-PSG
  mapping adds 48 LUT4s/five carries and seed-1 placement regresses by 50 LCs.
  H011 proves the reflected ramp is a bitwise complement, but both spellings
  map identically in the registered-use cone. H010's phase-qualified pending
  bit is exact and saves four LUT4s/one flop in the isolated timing cone, but
  whole-PSG mapping adds 29 LUT4s/five carries and seed-1 placement regresses
  by 36 LCs. H009's shift token failed similarly; H005's `< 3` suffix remains
  rejected on fast-clock timing; H004, H006, and H008 remain rejected as
  indexed below.
- Current post-integration accepted seed-1 result: H096 commit `a647185` atop
  merged main `a84dbff`: 6,364 LUT4s, 1,321 carries, 1,459 flops, 509
  unpackable flops, 14 EBRs, 6,873-cell floor, and 7,095/7,680 LCs at
  151.17/33.09 MHz. Versus merged main it deterministically removes 31 LUT4s,
  one FF, and 28 floor cells; the 25-LC route reduction is below placement
  sensitivity and is not independently overclaimed. Two forced builds
  reproduced JSON SHA-256 `da8f01f6...` and ASC SHA-256 `519dabc7...`
  bit-for-bit. The numerically smaller direct H095 point predates the required
  main/R.84/diagnostic-ARAM composition and is not the current integration base.
  The older H051 source lineage remains at
  6,506 LUT4s / 1,421 carries / 1,476 flops / floor 7,028 / 7,247 LCs.
- Last updated: 2026-08-03.

## Main Integration I001

- **ID:** I001.
- **Hypothesis:** accepted direct H095 `3d7a2e2`, the final accepted R.84
  proof foundation `7cc639a`, and the durable generic ledger `bca1454` can
  be composed on main `86d4fab` without losing either the direct RTL savings
  or the R.84 address/control/live-value guarantees.
- **Scope:** a dedicated integration branch only. Preserve every accepted
  direct generic RTL change, merge the committed R.84 proof/controller state,
  regenerate all source-derived C2-C-C and later proof artifacts against the
  composed RTL, then run the complete algebraic, structural, cadence, render,
  recovery, click, Celeste, forced HX8K, strict OpenSpec and scope battery.
  The dirty main worktree, Tang/image paths and unrelated user changes remain
  untouched until a verified fast-forward is possible.
- **Baseline:** direct H095 maps 6,342 LUT4s, 1,321 carries, 1,459 flops,
  504 unpackable flops, 14 EBRs, floor 6,846 and 7,066 seed-1 LCs at
  133.69/32.79 MHz. R.84 head is proof-only and makes no composed area claim.
- **Change:** merge R.84 `7cc639a` into direct H095 `3d7a2e2`, retain every
  committed source change, and repair only the four source-derived integration
  bindings: the retired H075 walk leaves in `psg_budget_tb`, H051's reachable
  DQ recurrence in `psg_dqsvc_tb`, the H075/noise-clamp source spellings in
  `psg_exec_model.py`, and this ledger row.
- **Result:** two independent model generations and two independent composed
  traces are byte-identical.  Binding audits pass 152,893 structural rows;
  value audits pass 385,792 rows / 192,896 pairs and 43,459 service
  transactions.  Full forms, full/PREVIEW and executor lints, Python compile,
  strict OpenSpec, `make test-psg`, 59/59 frozen renders, ordinary and
  multipumped `/4`--`/6` cadence, `make test-clocks`, all eight PREVIEW checks,
  synthetic/Celeste recovery, exact zero-click hardware/PREVIEW SFX-10
  renders, and the five-frame Celeste smoke pass.  Two forced HX8K builds are
  byte-identical at JSON SHA-256 `4e0d5930d1dde2ecea8d72167ff94329093879d86758ec72041ac871201bf921`
  and ASC SHA-256 `5c51c6684f861ff7481012dd921259220b367cd00f3e20f3fce81704cdb9ea19`:
  6,386 LUT4s, 1,325 carries, 1,459 flops, 504 unpackable flops, 14 EBRs,
  6,890-cell deterministic floor and 7,116 seed-1 routed LCs at 143.64 MHz
  fast / 30.95 MHz PSG.  Relative to direct H095, the required R.84 runtime
  substrate costs 44 LUT4s, four carries, 44 floor cells and 50 routed LCs;
  no area reduction is claimed for the composition itself.  Accepted model
  parent `0db0484` is also merged and rebound to I001: independent upgraded
  source certificates are byte-identical at `bcadbae4...`, all other model and
  event artifacts remain byte-identical, both binding/value audits pass, and
  the default model, complete forms, Python and strict OpenSpec gates pass.
- **Decision:** accepted.  This is the verified H095 + R.84 integration point;
  it was safely fast-forwarded through the later main landing at `a84dbff`,
  which unblocked the now-accepted H096 generic continuation. R.84 B2 remains
  companion-owned.
- **Repeat only if:** retry a rejected merge resolution only after identifying
  a concrete changed source/proof contract or an independently accepted newer
  direct/R.84 checkpoint.

## Main Integration I002

- **ID:** I002.
- **Hypothesis:** accepted H096 `a647185` changes exactly the launch/pacing
  source and its exhaustive hardware form relative to merged main `a84dbff`.
  Rebinding the H095-to-I001-to-main source certificate to that exact revision
  should preserve the complete R.84 manifests, event dictionary, structural
  joins and live-value lineage while making H096 safe to integrate.
- **Scope:** `tools/psg_exec_model.py`, `tools/psg_exec_bindings.py`, generated
  proof artifacts and the two PSG continuation ledgers only. Do not change
  production RTL, the accepted image, controller, manifest, event dictionary,
  pool work, tolerances, or begin R.84 B2.
- **Baseline:** H096 commit `a647185` already passes the full generic battery at
  6,364 LUT4s, 1,321 carries, 1,459 flops, 14 EBRs, 6,873 floor cells and 7,095
  routed LCs. The accepted main source certificate is v3 SHA-256 `3f8a3ec8...`,
  bound to H095 `3d7a2e2`, I001 `6c9eebe`, and main composition `9aacce1`.
- **Change:** add an exact v4 certificate that retains those lineage
  anchors, binds H096 `a647185`, proves that only `rtl/psg_seq.sv` and
  `tools/psg_hw_forms.py` differ from merged main in the complete bound source
  set, and independently convicts revision/hash/schema mutations.
- **Result:** independent A/B generation produces byte-identical v4 source
  certificates at SHA-256 `2af2c61f...`. Candidate `6f5713e2...`, manifest
  `438d85a0...`, control `a9233d6d...`, requirements `5a7b9809...`, controller
  `f86698f6...`, and events `5b178017...` remain byte-identical to I001. Both
  structural audits pass 152,893 legacy rows and convict all nine source
  mutations; both value audits pass 192,896 pairs and 43,459 service
  transactions. Complete forms, `make test-psg` including 59 frozen renders,
  93 analysis tests and structural timing, `make test-clocks`, the default
  model, Python compilation, strict OpenSpec and diff checks pass. H096's exact
  committed RTL retains its two forced-build result of 6,364 LUT4s, 1,321
  carries, 1,459 flops, 14 EBRs, 6,873 floor cells and 7,095 routed LCs at
  151.17/33.09 MHz.
- **Decision:** accepted. H096 is now source-bound to the accepted R.84 proof
  lineage without starting B2 or changing production RTL/image artifacts.
- **Repeat only if:** retry after rejection only if the accepted H096 revision,
  source-boundary schema, or an R.84 prerequisite changes.

## Main Integration I003

- **ID:** I003.
- **Hypothesis:** accepted H102 `ccfb2a0` changes exactly
  `rtl/psg_common.svh`, `rtl/psg_seq.sv`, and `tools/psg_hw_forms.py` relative
  to the I002 H096 source boundary. A v5 certificate should bind this exact
  revision while preserving every R.84 manifest, structural join, event, and
  live-value result.
- **Scope:** source-certificate tools, generated proof evidence, and the two PSG
  continuation ledgers only. Do not alter H102 production RTL, the accepted
  image/controller/manifest/events, tolerances, or begin R.84 B2.
- **Baseline:** H102's two forced builds reproduce 6,360 LUT4s, 1,321 carries,
  1,458 flops, 14 EBRs, 6,868 floor cells and 7,087 routed LCs at
  140.92/32.65 MHz. I002 source-contract v4 is `2af2c61f...` on H096.
- **Change:** extend the exact lineage boundary through H102 and independently
  convict revision, changed-source, hash, schema and type drift.
- **Result:** independent A/B generation produces byte-identical v5 source
  certificates at SHA-256 `d54dde5d...`; all thirteen source mutations are
  convicted. Candidate `6f5713e2...`, manifest `438d85a0...`, control
  `a9233d6d...`, requirements `5a7b9809...`, controller `f86698f6...`, events
  `5b178017...`, inventory `95619e61...`, and the accepted image remain
  byte-identical. Both structural audits pass 152,893 rows and both value
  audits pass 192,896 pairs / 43,459 service transactions. Complete H102 forms,
  `make test-psg`, `make test-clocks`, the default model, Python compilation,
  strict OpenSpec and diff checks pass.
- **Decision:** accepted. H102 is now source-bound to the accepted R.84 proof
  lineage without starting B2 or changing production RTL/image artifacts.
- **Repeat only if:** retry after rejection only if the accepted H102 revision,
  source-boundary schema, or an R.84 prerequisite changes.

## Next Experiment Gate

- Next experiment: H123 on accepted H102 `ccfb2a0`, only after a fresh source
  and DNR audit. It must not repeat H096/H103's
  launch-worklist/pacing-state family, H102's wavetable-bass/effect-state
  encoding family,
  H104's instrument-kind state-encoding family,
  H105's record-transfer counter-width family,
  H106's upload/diagnostic pointer-advance factoring family,
  H107's unpacked/packed playback-state representation family,
  H108's disabled-reverb restart specialization family,
  H109's sequencer-FSM synthesis-encoding family,
  H110's inactive-bank join-mode reconstruction family,
  H111's registered readback pending-valid factoring family,
  H112's pending-trigger FF-array packing family,
  H113's top-level walker/sequencer multiplier-payload merge family,
  H114's reciprocal-output subtract-width family,
  H115's bounded instrument/base filter-max spelling family,
  H116's effective-filter inactive-bank lifetime family,
  H117's walk-controller payload-reset family,
  H118's sequencer volume-width family,
  H119's elaboration-specific walk-phase counter-width family,
  H120's fade-payload reset-removal family,
  H121's sequencer-credit state-representation family,
  H122's PC3 copy-zero live-state reconstruction family,
  H123's sampled parameter-bank history family,
  H124's clear-toggle/amplitude dead-bit packing family,
  H125's noiz/amplitude dead-bit packing family,
  H097's `ML_STOP` provenance/lifetime-alias family,
  H098's fast multiplier iteration-token family,
  H099's filter-tuple ownership/publication-source family,
  H100's foreground/music release-state partition family,
  H101's pending-trigger row/length memory family,
  H095's now-composed foreground trigger-length
  prefix family, H094's now-closed packed transition-inequality
  family, H093's DQ coefficient-decoder spelling family, H092's EA2/EA4 result-
  flop lifetime family, H091's pattern-counter compression, H090's multiplier
  step-count family, or H089's state-selected pitch-add/clamp family. It must remain
  outside the closed affine-slide-carry,
  tilt-affine-reassociation, tilt-index-adder-sharing,
  aligned-noise-offset,
  dampen-rounding, blend-rounding,
  DQ-result-publication,
  quotient-prefix,
  tail-sentinel,
  sample-register-width,
  noise-draw, old-arm-sign, old-noise-flag, fade-state,
  triangle-payload,
  organ quotient-byte, and organ-high-
  predicate, organ-fold,
  signed-noise-rounding, centered-triangle-fold, noise-clamp, kick-comparator, detune-
  service-count, upload-page-transform, square/pulse-threshold, selector-
  factor, normalized-effect-class, waveform-output-shift, tilt-control-
  predicate, trit-max, counter-
  terminal, fold-final-selector, fold-publish-state, EA5-predicate, small-comparison, fade-prefix, organ-fold, aligned-
  record-base, boosted-gain, conditional-width, tilt-register, suffix-sharing,
  prefix-clamp, readback-bit, address-base, comparator-sharing, reciprocal-
  half-sum, gain-context, state-replay, divider, detune, delayed-tick,
  multiplier, soft-add-threshold, reverb-rounding, and R.84
  families.
- Required verification for any accepted hypothesis: focused algebraic or exhaustive
  proof, waveform/form tests, full structural PSG, 59-render exact regression,
  mapped resources, seed-1 placed LCs, both routed clocks, strict OpenSpec
  validation, and `git diff --check`.
- Blocked repeat families: R.40--R.42 lifetime aliases; R.44 pending-trigger
  EBR migration; R.63/R.64 multiplier
  adder sharing; R.67 parallel reciprocal port; R.68/R.69 partial schedule
  encodings; R.76--R.78 detune-result lifetimes; R.79 held CDC payload;
  R.80 reciprocal coefficient factoring; R.82 detune recomputation; R.83
  register-fed waveform services; all R.84 executor/controller work.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| H001 | accepted | Keep the exact narrow tilted-saw ceiling form; treat the mapped carry reduction as the durable physical result. |
| H002 | accepted | Keep the four-interval Boolean decode for `ceil(3*r/128)`; the deterministic result is 18 fewer LUT4s. |
| H003 | accepted | Keep the exact high-bit prefix test; the deterministic result is 19 fewer LUT4s and two fewer carries. |
| H004 | rejected | Do not narrow the square/pulse threshold comparator: Yosys already removes the aligned low bits. |
| H005 | accepted | Keep the five-bit page subtract and explicit upload-page decode; the durable result is nine fewer carries with no placed regression. |
| H006 | rejected | Keep the existing multiplier step-count ternary: it already maps to one LUT, while direct result-bit logic needs two. |
| H007 | accepted | Keep the CLK_HZ-derived signed width; it deterministically removes 46 LUT4s, 13 carries, and two flops. |
| H008 | rejected | Keep the two direct counter equalities: Yosys already shares their common high-nibble decode. |
| H009 | rejected | Keep the countdown form: the exact shift token is smaller alone but adds 36 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H010 | rejected | Keep the countdown form: the exact pending bit saves one local flop but adds 29 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H011 | rejected | Keep the subtract spelling: Yosys already maps `16'hffff - wx` exactly as `~wx`, with identical registered-use resources. |
| H012 | rejected | Keep the defensive true-busy OR: removing it is exact in-contract and locally smaller but adds 48 LUT4s, five carries, and 50 placed LCs globally. |
| H013 | rejected | Keep the 34-bit internal service form: the proved 29-bit recurrence removes two flops but adds 24 LUT4s, three carries, and 26 placed LCs. |
| H014 | rejected | Keep the nine-bit source contract: all values fit eight bits, but Yosys already prunes the unreachable position and both forms map identically. |
| H015 | rejected | Keep the explicit subtract qualifier: the unconditional form is exact but maps identically in the registered full-detune cone. |
| H016 | rejected | Keep the ten-bit restoring subtract: the nine-bit form is exact and locally -1 carry/+1 LUT, but globally adds 60 LUT4s, eight carries, and 67 LCs. |
| H017 | rejected | Keep separate new/old gain cones: full and scale-only sharing save carries locally/globally but both add LUT4s and placed LCs in the whole PSG. |
| H018 | rejected | Keep the 26-bit add-then-shift: the exact 25-bit half-sum saves one carry locally but globally adds 31 LUT4s, nine carries, and 38 LCs. |
| H019 | rejected | Keep per-operation state-memory selects: both whole-walk owner forms are exact and locally smaller, but globally add LUT4s/carries; the retained-OR form also fails to route promptly. |
| H020 | rejected | Keep the redundant audio-RAM busy export: removing it saves one local LUT4 but adds three LUT4s/three carries globally and one placed LC. |
| H021 | rejected | Keep the 32-arm filter table: its wrapped base-3 identity is exact, but ABC maps the table smaller than direct or staged arithmetic. |
| H022 | accepted | Keep the eight-bit live pitch sums and exact sign/high-bit saturation decode; they trade 17 LUT4s for 14 carries and one non-robust placed LC without changing behavior. |
| H023 | accepted | Keep the exact shared slide-octave prefix predicates; they remove ten LUT4s, six carries, and 24 non-robust placed LCs. |
| H024 | rejected | Keep the nested row-bound clamps: exact prefixes save carries but add 32 LUT4s and 19 placed LCs globally. |
| H025 | rejected | Keep the repeated fade expressions: formal equivalence passes, but Yosys already maps them identically to one explicit sum. |
| H026 | rejected | Keep the relational rollover predicate: the exact carry form saves 14 carries but adds 31 LUT4s and 14 placed LCs globally. |
| H027 | accepted | Keep the exact shared-helper noise clamp prefixes; they remove 69 carries and 61 seed-1 LCs for 21 LUT4s. |
| H028 | rejected | Keep the relational arpeggio-speed test: the exact prefix loses its carry saving globally and adds LUT4s/LCs. |
| H029 | rejected | Keep the current kick inequality: the exact affine margin saves carries but adds LUT4s and placed LCs globally. |
| H030 | accepted | Keep the exact foreground trigger-length prefix; it removes four LUT4s and two carries without a placement regression. |
| H031 | accepted | Keep the time-shared sequencer comparator; it removes one LUT4 and seven carries without a placement regression. |
| H032 | rejected | Keep the two precomputed record bases: selecting the record number first is locally smaller but globally adds 32 LUT4s and 32 LCs. |
| H033 | rejected | Keep the dynamic audible-slot readback: the exact paired activity bit maps identically in the complete registered consumer. |
| H034 | rejected | Keep the relational pattern-row saturation: the exact prefix removes two carries locally but adds 15 LUT4s, four carries, and 20 LCs globally. |
| H035 | rejected | Keep the independent suffix expressions: explicit nesting is exact but maps identically in the complete registered consumer. |
| H036 | rejected | Keep the parallel tilt quotient registers: preselection saves ten flops locally but adds 54 LUT4s/seven flops globally and does not route promptly. |
| H037 | rejected | Keep the ten-bit `/7` source width: the dead live-mode bit is already pruned and both registered consumers map identically. |
| H038 | rejected | Keep the two-stage boosted gain: the exact affine/residue form adds 28 LUT4s with carries/flops unchanged. |
| H039 | accepted | Keep the aligned 11-bit `rec_base()` transform; it removes five LUT4s for one added carry and no placement regression. |
| H040 | rejected | Keep the truncated organ-ramp negation: the exact explicit fold is locally smaller but globally adds LUT4s, carries, and LCs. |
| H041 | rejected | Keep the relational fade-length tests: the shared exact prefix saves carries but adds 11 LUT4s and nine placed LCs globally. |
| H042 | rejected | Keep the gated two-bit relation: its exact Boolean truth table is locally smaller but adds LUT4s, carries, and LCs globally. |
| H043 | rejected | Keep the direct EA5 comparisons: the named exact predicates map identically in the complete registered consumer. |
| H044 | accepted | Keep the proved terminal high-bit predicate; it removes nine LUT4s deterministically with no placement regression. |
| H045 | rejected | Keep the relational filter maxima: the exact trit form maps identically in the registered consumer. |
| H046 | rejected | Keep the raw publication decodes: normalized `e_fx` reuse saves three LUT4s alone but adds 27 LUT4s and 28 routed LCs globally. |
| H047 | accepted | Keep the selected final waveform shift; it removes 28 LUT4s, 33 carries, 27 floor cells, and 29 seed-1 routed LCs. |
| H048 | rejected | Keep the direct priority selector: factoring its two axes adds 16 LUT4s in the registered cone. |
| H049 | rejected | Keep the relational square/pulse thresholds: exact Boolean prefixes add LUT4s and placed LCs globally. |
| H050 | rejected | Keep the five-bit subtract: both exact Boolean transforms regress global LUT/floor/placement. |
| H051 | accepted | Keep the five-state XOR/shift detune-service count; it removes five mapped carries for three LUT4s and no seed-1 placement regression. |
| H052 | rejected | Keep the separate final-fold flag: selector state five adds three isolated LUT4s and maps the same total flops. |
| H053 | rejected | Keep the publication flop: state ten removes one FF but adds 22 global LUT4s and 19 floor/routed cells. |
| H054 | rejected | Keep the current complement/subtract/bias triangle fold: the exact centered-phase identity saves one isolated carry but adds eleven LUT4s. |
| H055 | rejected | Keep the shared positive/negative noise limbs: duplicated unified rounding doubles isolated carries, while the shared complement form does not complete seed-1 routing. |
| H056 | accepted | Keep `z_lin_r[15] ^ z_lin_r[14]` as the exact organ high-phase predicate; it retires one FF and one deterministic floor cell with no placement regression. |
| H057 | accepted | Keep exact reconstruction of `tilt_hi_r` from the same-edge registered controls; it removes 23 LUT4s, one FF, and 19 floor cells globally. |
| H058 | rejected | Keep the explicit state-RAM replay contract: its freeze is covered by `prun | fold_busy`, but removing one FF adds 24 LUT4s, five carries, 21 floor cells, and 31 placed LCs and does not route. |
| H059 | rejected | Keep the explicit registered organ quotient byte: exact full and partial reconstruction from `z_lin_r` retire flops locally but regress whole-PSG LUT4s, carries, floor, and placement; the partial form also fails to route. |
| H060 | rejected | Keep the explicit registered alternate-triangle `/4` payload: exact reconstruction from `z_lin_r` removes 16 mapped FF but adds 54 LUT4s, one carry, 50 floor cells, and 53 routed LCs globally. |
| H061 | rejected | Keep the explicit 16-bit fade accumulator: exact high-byte reconstruction removes eight FF but adds eight isolated LUT4s and six floor cells. |
| H062 | rejected | Keep the explicit old-noise activity flag: exact same-edge tuple reconstruction is locally -2 LUT4/-1 FF/-2 floor, but globally adds 55 LUT4s, 53 floor cells, and 57 routed LCs. |
| H063 | rejected | Keep the W15 old-arm sign snapshot: the source sign is invariant through W51 and direct use removes one FF locally, but globally adds 64 LUT4s, four carries, 62 floor cells, and 69 routed LCs. |
| H064 | rejected | Keep the parallel live/old noise-draw transforms: selecting LFSR bits before one exact shared XOR chain saves two isolated LUT4s, but globally adds 55 LUT4s, four carries, 54 floor cells, and 63 routed LCs. |
| H065 | rejected | Keep the signed 18-bit sample registers: every value fits signed 16 bits and contraction removes four FF/four carries, but globally adds 27 LUT4s, 27 floor cells, and 32 routed LCs. |
| H066 | rejected | Keep the explicit tilt-tail pipeline flag: reserved-index encoding is exact and removes one FF, but adds 42 LUT4s, four carries, 40 floor cells, 47 routed LCs, and misses fast timing. |
| H067 | rejected | Keep the explicit quotient slices: sharing their four-bit source prefix with `t_pre_r` is exact, but both complete isolated consumers map identically at 19 LUT4s and 29 FF. |
| H068 | rejected | Keep the committed DQ terminal result: retaining the pre-terminal recurrence saves six isolated LUT4s but adds one global carry, twelve unpackable flops, three floor cells, and six routed LCs. |
| H069 | accepted | Keep the exact post-shift negative-remainder correction in shared `tzs`; it removes ten global LUT4s, 33 carries, and nine floor cells without a seed-1 placement regression. |
| H070 | rejected | Keep the binary divider countdown: a 24-state LFSR saves one isolated LUT4/three carries but adds 23 global LUT4s/floor cells and 17 routed LCs. |
| H071 | rejected | Keep the pre-shift blend bias: post-shift correction saves eight isolated LUT4s/six carries but both whole-PSG spellings regress LUT4s and floor cells. |
| H072 | rejected | Keep the pre-shift dampen bias: selected post-shift correction removes carries but adds 26 global LUT4s and 24 floor cells. |
| H073 | rejected | Keep the source expression `8*dp + 1120`: the exact aligned 14-bit sum maps identically in the complete registered consumer. |
| H074 | rejected | Keep the full first affine-slide accumulation: its low-12 carry changes a reachable published increment at pitch 2/fraction 9,668. |
| H075 | accepted | Keep the exact operand-XOR and sign carry-in form; it removes 23 global LUT4s, eight carries, two unpackable flops, and 25 floor cells. |
| H076 | rejected | Keep the accepted `3*x`-then-subtract form: reassociation is locally -12 LUT4/-1 carry but globally +5 LUT4/+1 unpackable/+6 floor. |
| H077 | rejected | Keep the two source index expressions: the shared-adder form is exact but maps identically in the complete registered tilt consumer. |
| H078 | rejected | Keep the serial positive/negative soft-add probes: sign-selected fusion is exact in the legal fold domain but adds six isolated LUT4s. |
| H079 | rejected | Keep pre-shift bias in the two reverb combs: post-shift correction saves two isolated carries but adds 32 global LUT4/floor cells. |
| H080 | accepted | One sign-selected fractional-sample update adder removes 24 global LUT4s, 23 carries, and 24 deterministic floor cells. |
| H081 | rejected | Keep the two slide adders: exact scheduled sharing removes 25 carries but adds 20 isolated LUT4/floor cells. |
| H082 | rejected | Keep the dedicated slide-intermediate register: storage reuse removes 18 FF but adds 28 global LUT4s and ten floor cells. |
| H083 | rejected | Keep the nested live-gain sums: exact fusion removes three carries but adds 21 isolated LUT4/floor cells. |
| H084 | rejected | Keep binary `scnt`: exact three-token LFSR encoding removes six carries but adds 26 LUT4s and 32 floor cells globally. |
| H085 | rejected | Keep numerator bias: both exact output-correction placements regress complete isolated divider/caller floor. |
| H086 | rejected | Keep the two EA5 row incrementers: exact selected sharing removes seven global carries but adds seven LUT4s and eight floor cells. |
| H087 | rejected | Keep the signed vibrato case and absolute value: direct sign/magnitude bits add one isolated LUT4. |
| H088 | rejected | Keep dedicated tick/pre-tick flops: deriving both from registered state removes two FF but adds three LUT4s and two isolated floor cells. |
| H089 | accepted | Keep one state-selected current/arpeggiated pitch add-and-clamp cone; it removes 63 global LUT4s, 15 carries, and 60 deterministic floor cells. |
| H090 | rejected | Keep the two multiplier count decodes: deriving `seq_pad` from radix-2 `req_steps` is exact but adds one isolated LUT4. |
| H091 | rejected | Keep elapsed and target pattern counters: one saturated remaining counter completes early after a reachable pending-trigger wrap. |
| H092 | rejected | Keep the two comparator-result flops: one shared flop saves one LUT4/one FF alone but adds 20 global LUT4/floor cells and three carries. |
| H093 | rejected | Keep the nested DQ coefficient decoder: the exact grouped truth table adds three LUT4s in the complete registered service cone. |
| H094 | rejected | Keep separate transition inequalities: one packed comparison saves one isolated LUT4 but adds three global LUT4/floor cells. |
| H095 | accepted | Keep the exact foreground trigger-length overflow prefix on the direct lineage; it removes four global LUT4s, three carries, and four floor cells. |
| H096 | accepted | Consume the launched-channel worklist after selecting the pacing owner; this removes 31 LUT4s, one FF, and 28 deterministic floor cells on merged main. |
| H097 | rejected | Keep the dedicated `ml_cpu` provenance bit: `walk_tick` is equivalent and saves three LUT4s/one FF alone, but adds 18 LUT4s, four carries, 17 floor cells, and 20 routed LCs globally. |
| H098 | rejected | Keep the binary multiplier countdown: an exact LFSR token saves four LUT4s/two carries alone, but adds 20 LUT4s, 19 floor cells, and 16 routed LCs globally. |
| H099 | rejected | Keep the explicit filter base-copy writes: publication ownership saves 17 LUT4s alone, but both whole-PSG variants regress deterministic floor and placement. |
| H100 | rejected | Keep the eight-entry source array: music release bits are invariant zero, but Yosys already prunes them and the explicit four-entry form maps identically at 17 LUT4s/four FF. |
| H101 | rejected | Keep pending trigger row/length in FFs: a plain EBR is one cycle stale after a CPU write, while exact one-/two-EBR forwarding forms raise the isolated floor from 97 to 107/104 cells. |
| H102 | accepted | Encode wavetable bass in otherwise-dead `w_ins_fx[0]`; this removes four global LUT4s, one FF, one unpackable FF, and five deterministic floor cells. |
| H103 | rejected | Keep `ptick_seen`: the exact lower-launch-prefix replacement removes one FF but adds two LUT4s in the complete isolated pacing consumer. |
| H104 | rejected | Keep `{w_ins_on,w_ins_wt}`: direct one-hot `{SFX,wavetable}` mode state is exact but adds one LUT4 in the complete registered consumer. |
| H105 | rejected | Keep the four-bit record-transfer counter: the exact three-bit form removes one FF/two carries but adds 24 LUT4s in the complete isolated consumer. |
| H106 | rejected | Keep the separate upload-write and diagnostic-read pointer updates: exact factoring saves two LUT4s alone but adds 51 LUT4s, one unpackable FF, 52 floor cells, and 54 routed LCs globally. |
| H107 | rejected | Keep the unpacked `playing[]` storage plus exported packed view: direct `play_bits` storage removes six unpackable FFs but adds 79 LUT4s, two carries, 73 floor cells, and 79 routed LCs globally. |
| H108 | rejected | Keep the reverb-mode term in `blend_restart` even for `REVERB=0`: parameter-gating it adds 39 LUT4s, four carries, one unpackable FF, 40 floor cells, and 47 routed LCs globally. |
| H109 | rejected | Keep the sequencer FSM in binary encoding: forced one-hot is -6 LUT4/-5 unpackable/-11 floor and places three LCs lower, but adds 57 FF/four carries and cannot complete canonical routing. |
| H110 | rejected | Keep the explicit `join_stage` history bit: a same-edge `tick_en_d` publication plus join-pass start clears `bank_ready` while preserving `join_stage=1`. |
| H111 | rejected | Keep the readback pending assignments in their control arms: the unconditional next-state spelling is exact but maps identically at 14 LUT4s/nine flops. |
| H112 | rejected | Keep separate pending-trigger row/length arrays: one packed 11-bit FF array is exact but maps identically at 61 LUT4s/44 flops. |
| H113 | rejected | Keep the zero-idle OR payload merge: owner selection is transaction-exact and shrinks `req_a`/`req_b`, but adds 66 LUT4s, four carries, 66 floor cells, and 73 routed LCs globally. |
| H114 | rejected | Keep the implicit reciprocal-output width: an explicit exact signed-16-bit subtract adds 27 LUT4s, four carries, 25 floor cells, and 28 routed LCs globally. |
| H115 | rejected | Keep the comparator/mux filter joins: the exact bounded 0..2 max formula maps identically at six LUT4s/six flops in the complete three-field registered consumer. |
| H127 | rejected | Keep both phaser remainder thresholds: shared Boolean selection is +2 isolated LUT4s; a direct selected comparator is -3 LUT4/+6 carry locally but +50 LUT4/+49 floor cells globally. |
| H128 | rejected | Keep the repeated `rw` qualifiers inside `psg_seq`: the top-level write pulse makes them redundant, but Yosys already absorbs the implication and both registered decoders map identically at 9 LUT4s/4 FF. |
| H129 | rejected | Keep one eight-entry `sfx_id` FF array: fixed foreground/music bank partitioning is exact, but retains 48 unpackable FFs and adds ten LUT4s in the complete storage/read consumer. |
| H130 | rejected | Keep the all-channel status buses before CPU selection: direct addressed-channel/slot selection is exact but adds two LUT4s in the complete registered readback. |
| H131 | rejected | Keep `aud_sl(...) == c` at the row writer: the direct foreground-play XOR is exact but maps identically at 18 LUT4s/20 unpackable FF. |
| H136 | rejected | Keep `mxs_new`/`mxs_old` in the walker: the result token is exact, but two newly active CDC/result flops replace the two retired sign flops and the production-shaped isolated floor worsens 274 -> 275 cells. |
| H137 | rejected | Keep the shared-EBR fade-step lookup and replay boundary: direct 32-entry decode is -8 floor cells alone but adds 84 whole-PSG LUT4s, one carry and 72 floor cells. |
| H138 | rejected | Keep signed-18 live/old pre-clamp noise registers: signed-17 storage is exact and -6 floor cells alone, but adds 29 whole-PSG LUT4s and 28 floor cells despite removing seven carries and two flops. |
| H145 | rejected | Keep the parallel dampen path: sharing the widened fold ALU is exact and removes 35 carries/19 unpackable FFs alone, but adds 31 LUT4s and worsens the complete isolated floor 434 -> 446 cells; an `fmc`-encoded finish worsens it to 485. |
| H146 | rejected | Keep the three DQ ceiling incrementers: explicit selection is -13 LUT4/-11 carry alone, but adds 36 whole-PSG LUT4s, one carry, 36 floor cells and 43 routed LCs. |
| H147 | rejected | Keep 13-bit gain history: the 12-bit boundary is -5 LUT4/-2 FF alone, but globally +26 LUT4/+2 carry/+27 floor/+33 routed LCs and misses fast timing. |
| H155 | accepted | Keep the shared complemented negative noise limb `~nz_mag + !|frac|`: -5 pre-map gates, -3 LUT4/-6 floor/-3 placed LCs, and it restores the seed-1 route that clean `644d68f` lost. |
| H156 | rejected | Do not re-associate the `gz_filt_r` 1025-gain scale network: deleting it outright is only -52 pre-map cells, so the exact form is worth ~8. The largest never-examined cone in the design is empty. |
| H157 | rejected | Do not open another register-lifetime alias: the complete remaining pool is 17 flops (`wt_x1` 8, `fmc` 4, `fsel` 3, `last_mode_r` 2) and the six measured instances cost +1..+84 LUT4. Class closed by arithmetic. |
| H158 | rejected | Do not pursue the `q16` address-adder share, the `w_ch_*` maxima, or the `t_ix15` index add: bundled ablation ceiling is 76 cells with the behaviour deleted, honest content ~11. |
| H160 | rejected alone, accepted in H161 | Do not read alone: deleting the duplicated `fade_acc + fade_step` evaluations is -52 pre-map but **+31 floor**, because the duplicates were being fused into their consumers. Half of H161's -33. |
| H162 | rejected | H142/H153 retried under the doctrine: H142 retires 12 unpackable flops but buys +17 LUT4 (all deterministic instruments worse); H153 and the bundle are indistinguishable from zero in abc9 (p~0.36 / p~0.13). **classic-abc read -28/-49 on both and was wrong** - its spread-9 estimate came from n=6. |
| H161 | **accepted** | Land H159+H160 **together**: pre-map -133, `-noabc` floor -88 (spread 0), classic-abc -48, abc9 median -34.5 (U=378.5/400, p~7e-7). Individually 0 and +31. Evaluate families as bundles - one-at-a-time is biased, not just slow. |
| H159 | rejected alone, accepted in H161 | Do not read alone. Collapsing the four wavetable fetch adders into one index-selected add is exact by construction and **-81 pre-map / -20 carries**, but **flat on floor** alone (-2 LUT4, +2 unpackable). Carries can retire without their LUTs, so pre-map does not predict one abc9 draw. Landed in H161. |

## Hypothesis H001

- **ID:** H001.
- **Hypothesis:** spelling the two tilted-saw ceiling operations as a narrow
  quotient plus a non-zero-remainder increment will preserve every value,
  simplify the source contract, and may map smaller than a wide constant add
  followed by truncation.
- **Scope:** `rtl/psg_wave.sv`, an exhaustive proof command, waveform/form
  tests, full PSG fidelity gates, canonical standalone synthesis, and this
  ledger. No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** `PATH=/opt/homebrew/bin:$PATH make synth-psg` at `86d4fab`,
  fingerprint `92fc17f7dbd2`: 6,598 LUT4s, 1,597 carries, 1,478 flops, 14
  EBRs; seed-1 7,504 LCs; 145.99 MHz fast and 30.21 MHz PSG.
- **Change:** replace each wide add-then-shift ceiling expression with its
  explicit quotient plus one-bit non-zero-remainder increment.
- **Result:** exhaustive comparison of all 65,536 ramp values passed for both
  `/1024` and `/2048`; `tools/psg_hw_forms.py`, `make test-psg`, the 59-render
  18.75-MHz exact bytecheck, full/PREVIEW lint, `/4`, `/5`, `/6` budget tests,
  and `make test-clocks` all passed. P.1 Celeste preview checks at 1,275 and
  159 clocks/sample passed combined and masks 1/2/4 at 100%; P.2 synthetic
  and frozen-Celeste recovery passed. Exact hardware/PREVIEW SFX-10 renders
  were active and `click-v1` found zero clicks. A five-frame Celeste smoke had
  2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068 distinct
  levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,598 LUT4 / 1,597
  carry / 1,478 FF / 14 EBR / 7,504 placed LCs to 6,602 LUT4 / 1,577 carry /
  1,478 FF / 14 EBR / 7,495 placed LCs. Routed clocks changed from 145.99 and
  30.21 MHz to 150.53 and 30.71 MHz. The 20-carry reduction is deterministic;
  the nine-LC improvement is below placement sensitivity and is not overclaimed.
- **Decision:** accepted. It simplifies the arithmetic contract, improves a
  deterministic mapped resource, does not regress placed LCs, preserves all
  fidelity gates, and retains 14 EBRs.
- **Repeat only if:** a rejected spelling may be retried only after the
  waveform pipeline boundary, mapper arithmetic inference, or rounding
  representation changes materially.

## Hypothesis H002

- **ID:** H002.
- **Hypothesis:** the phaser detune remainder is only seven bits, so
  `ceil(3*r/128)` has four exact intervals: zero at `r=0`, one on 1--42, two
  on 43--85, and three on 86--127. Directly decoding those thresholds should
  remove the current `3*r` and round-up adders while making the bounded
  arithmetic contract explicit.
- **Scope:** `rtl/psg_wave.sv`, the `dq` proof in `tools/psg_hw_forms.py`,
  focused forms tests, complete H001 fidelity/physical gates, and this ledger.
  No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H001 commit `609f035`: 6,602 LUT4s, 1,577 carries,
  1,478 flops, 14 EBRs; seed-1 7,495 LCs; 150.53 MHz fast and 30.71 MHz PSG.
  Isolated `synth_ice40` reconnaissance maps the current remainder expression
  to 13 LUT4s / 7 carries and a direct Boolean threshold form to 7 LUT4s /
  zero carries; whole-PSG mapping remains authoritative.
- **Change:** remove the nine-bit `3*r` and round-up adders. Decode the lower-
  six-bit thresholds 43 and 22 as Boolean trees and drive the two-bit result
  directly; add the exact remainder and full-`dp13` proofs to `sec_dq()`.
- **Result:** the complete `tools/psg_hw_forms.py` passes, including all 128
  remainders and all 8,192 `dp13` values. Full/PREVIEW lint, `make test-psg`
  (93 analysis tests, every structural test, 524/850 sample clocks,
  4,008/5,103 tick clocks, zero late flips), 59/59 exact renders, and `/4`,
  `/5`, `/6` budget regressions passed. The budget runs retained 524 sample
  clocks and tick results 5,709/7,654, 4,689/6,123, and 4,008/5,103 with zero
  lost writes, overruns, or late flips. `make test-clocks` passed. All eight
  P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed at 95%
  agreement for combined and masks 1/2/4; both P.2 recovery probes passed.
  Exact hardware/PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke again had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,602 LUT4 / 1,577
  carry / 1,478 FF / 14 EBR / 7,495 placed LCs to 6,584 LUT4 / 1,577 carry /
  1,478 FF / 14 EBR / 7,478 placed LCs. Routed clocks changed from 150.53 and
  30.71 MHz to 138.48 and 29.89 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 18-LUT4 reduction is deterministic; the 17-LC
  improvement is below placement sensitivity and is not overclaimed.
- **Decision:** accepted. It exposes the exact four-interval contract, removes
  both remainder adders, improves a deterministic mapped resource, does not
  regress placed LCs, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** a rejected direct threshold decode may be retried only
  after the detune coefficient, remainder width, or mapper Boolean lowering
  changes materially.

## Hypothesis H003

- **ID:** H003.
- **Hypothesis:** the tilted-saw tail thresholds are exactly `0xE000` and
  `0xF000`; testing their one-prefix bits as `&wx[15:13] && (!tilt_hi ||
  wx[12])` is exact, simpler than two 16-bit comparisons, and should prevent
  the iCE40 mapper from retaining comparator carry cells.
- **Scope:** `rtl/psg_wave.sv`, an exhaustive prefix proof in
  `tools/psg_hw_forms.py`, focused forms tests, complete H002 fidelity/physical
  gates, and this ledger. No schedule, state, interface, EBR, R.84, or
  tolerance change.
- **Baseline:** accepted H002 commit `73921a5`: 6,584 LUT4s, 1,577 carries,
  1,478 flops, 14 EBRs; seed-1 7,478 LCs; 138.48 MHz fast and 29.89 MHz PSG.
  Isolated `synth_ice40` reconnaissance maps the current comparison to one
  LUT4 / two carries and the prefix form to two LUT4s / zero carries; whole-
  PSG mapping remains authoritative.
- **Change:** replace the two 16-bit comparisons with one three-bit prefix AND
  and the single distinguishing bit; add an exhaustive proof for both
  thresholds to the permanent hardware-forms gate.
- **Result:** the complete `tools/psg_hw_forms.py` passes, including all
  131,072 threshold/mode combinations. Full/PREVIEW lint, `make test-psg`
  (93 analysis tests, every structural test, 524/850 sample clocks,
  4,008/5,103 tick clocks, zero late flips), and the 59/59 exact render
  regression passed. The `/4`, `/5`, and `/6` budget runs retained 524 sample
  clocks and tick results 5,709/7,654, 4,689/6,123, and 4,008/5,103 with zero
  lost writes, overruns, or late flips. `make test-clocks` passed. All eight
  P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed at 95%
  agreement for combined and masks 1/2/4; both P.2 recovery probes passed.
  Exact hardware/PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke again had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,584 LUT4 / 1,577
  carry / 1,478 FF / 14 EBR / 7,478 placed LCs to 6,565 LUT4 / 1,575 carry /
  1,478 FF / 14 EBR / 7,453 placed LCs. Routed clocks changed from 138.48 and
  29.89 MHz to 131.72 and 30.51 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 19-LUT4 and two-carry reductions are
  deterministic; the 25-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It exposes the aligned-prefix contract, removes the
  wide comparisons, improves two deterministic mapped resources, does not
  regress placed LCs, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** a rejected prefix form may be retried only after the
  tail thresholds, phase width, or mapper comparison lowering changes.

## Hypothesis H004

- **ID:** H004.
- **Hypothesis:** all four square/pulse thresholds are aligned to 2^11, so
  comparing `wx[15:11]` against 16, 19, 22, or 25 may remove eleven comparator
  bits while keeping the threshold contract more explicit.
- **Scope:** exhaustive scratch proof and isolated `synth_ice40` comparison of
  the current and narrowed forms. Production RTL and fidelity gates are
  conditional on a deterministic isolated mapped reduction.
- **Baseline:** accepted H003 commit `68f9a35`; isolated current square/pulse
  selection maps to seven LUT4s and five carries.
- **Change:** scratch-only five-bit threshold and phase-high-word comparison;
  no production file changed.
- **Result:** all 1,048,576 waveform-selector, alternate-mode, and 16-bit phase
  combinations matched exactly. Isolated `synth_ice40` still mapped seven
  LUT4s and five carries: Yosys already proves the eleven aligned low bits
  irrelevant through the current 16-bit spelling.
- **Decision:** rejected before production RTL. The candidate changes source
  without changing the deterministic mapped netlist.
- **Repeat only if:** the thresholds lose their 2^11 alignment, comparator
  lowering changes, or a surrounding consumer prevents the current low-bit
  pruning.

## Hypothesis H005

- **ID:** H005.
- **Hypothesis:** the audio upload base `$3100` is byte-aligned, so its RAM
  address is exactly `{wraddr[12:8] - 17, wraddr[7:0]}`. The valid
  `$3100..$42ff` window is exactly pages `3:1..f` or `4:0..2`; spelling those
  two page prefixes directly should remove the current wide subtract/compare
  while making the port's address contract explicit.
- **Scope:** `rtl/psg_aram.sv`, an exhaustive all-65,536-address proof,
  isolated and whole-PSG iCE40 mapping, the complete H003 acceptance battery
  if the mapped result improves, and this ledger. No sequencer, walker,
  schedule, interface, EBR, R.84, or tolerance change.
- **Baseline:** production RTL remains accepted H003 commit `68f9a35` (plus
  docs-only H004 commit `d1373e8`): 6,565 LUT4s, 1,575 carries, 1,478 flops,
  14 EBRs; seed-1 7,453 LCs; 131.72 MHz fast and 30.51 MHz PSG.
- **Change:** replace the 16-bit base subtraction and 4,608-byte comparison
  with a five-bit page subtraction, retain the byte offset unchanged, and
  decode valid pages as `$31..$3f` or `$40..$42`. Add this full address-space
  equivalence to the permanent hardware-forms gate.
- **Result:** `tools/psg_hw_forms.py` exhausts all 65,536 addresses, selects
  exactly 4,608, and proves every valid index. Full and PREVIEW Verilator
  lint passed. `make test-psg` passed 93 analysis tests and the complete
  structural suite at 524/850 sample clocks and 4,008/5,103 tick clocks, with
  zero late flips. The 59-case 18.75-MHz regression was byte-exact. `/4`,
  `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654,
  572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks.
  `make test-clocks` passed. All eight canonical PREVIEW checks at 1,275 and
  159 clocks/sample passed at 36/38 voiced windows, rounded 95%, for masks
  7/1/2/4. Synthetic and reconstructed-Celeste recovery probes passed with
  no coalesced, delayed, or dropped samples. Exact hardware/PREVIEW SFX-10
  renders were active and `click-v1` found zero clicks. A five-frame Celeste
  smoke again had 2,179/3,668 off-centre samples, range -22,013..9,151, and
  1,068 distinct levels. Strict OpenSpec validation and `git diff --check`
  passed.
- **Rejected spelling:** writing the `$40..$42` suffix as `< 3` maps to 6,548
  LUT4s, 1,562 carries, 1,478 flops, 14 EBRs, and 7,417 placed LCs, but final
  routing reaches only 109.12 MHz on the 112.5-MHz fast clock. It is rejected
  despite its area win; evidence is `candidate-v1.{synth,pnr}.log`.
- **Physical result:** the retained `!= 3` spelling maps 6,568 LUT4s, 1,566
  carries, 1,478 flops, and 14 EBRs; seed-1 place-and-route uses 7,449 LCs and
  routes at 137.65 MHz fast / 31.16 MHz PSG. Relative to H003 this is +3
  LUT4s, -9 carries, and -4 placed LCs. The mapped carry reduction is durable;
  the placed delta remains inside sensitivity and is not overclaimed.
- **Decision:** accepted. The change makes the page-aligned port contract
  explicit, removes the wide subtract/compare, improves a deterministic mapped
  resource, does not regress placement, preserves every fidelity gate, and
  retains 14 EBRs with both routed clocks above constraint.
- **Repeat only if:** a rejected page-local decode may be retried only after
  the upload base/window, address width, or mapper constant-subtract lowering
  changes materially.

## Active DNR Index

- Selected arithmetic and service families: R.63, R.64, R.80, R.83.
- Lifetime and CDC payload families: R.40--R.42, R.76--R.79, R.82.
- Partial schedule/control encodings: R.68, R.69 and R.84 partial integration.
- Reciprocal memory topology: R.67.
- Sequencer fade-length predicate: H041.
- Triangle detune-1 residue comparison: H042.
- EA5 foreground-length predicate factoring: H043.
- Square/pulse threshold forms: H004 and H049.
- Audio-upload page transform: H050.
- State-RAM replay-flop retirement: H058.
- Launch/pacing fallback-state retirement: H103.
- Instrument-kind state encoding: H104.
- Record-transfer counter width: H105.
- Organ quotient-byte reconstruction: H059.
- Alternate-triangle `/4` payload reconstruction: H060.
- Fade-progress high-byte reconstruction: H061.
- Old-noise activity-flag reconstruction: H062.
- Old-arm gain-sign snapshot retirement: H063.
- Selected live/old noise-draw XOR sharing: H064.
- Sample-register width contraction: H065.
- Reciprocal-index tilt-tail sentinel: H066.
- Tilt-quotient shared-prefix storage: H067.
- Soft-add threshold-probe fusion: H078.
- Reverb comb post-shift rounding: H079.
- Inactive-bank join-mode reconstruction: H110.
- Registered readback pending-valid factoring: H111.
- Pending-trigger FF-array packing: H112.
- Top-level walker/sequencer multiplier-payload merge: H113.
- Reciprocal-output subtract width: H114.
- Bounded instrument/base filter-max spelling: H115.
- Effective-filter lifetime in inactive P_W2: H116.
- Walk-controller payload reset removal: H117.
- Sequencer volume-cone width contraction: H118.
- Elaboration-specific walk-phase counter width: H119.
- Fade-payload reset removal behind `fade_dir`: H120.
- Sequencer-credit state representation: H121.
- PC3 copy-zero live-state reconstruction: H122.
- Shared constants/control-ROM collision-token reconstruction: H126.
- Phaser remainder selected-threshold reconstruction: H127.
- `sfx_id` foreground/music FF-bank partitioning: H129.
- CPU status channel/slot selection order: H130.
- Audible-row owner predicate spelling: H131.
- Reciprocal spare-bit tail token via reserved address/plane: H132--H133.
- Direct combinational fade-step decode replacing the constants-EBR borrow:
  H137.
- Dedicated fade-step EBR reversing the constants-port consolidation: H148.
- Displaced-control token stored temporarily in `fstep_q[12]`: H149.
- Active fade-step low-twelve-bit zero encoding: H150.
- Live/old pre-clamp noise-register width contraction: H138.
- Live/old noise recurrence add/clamp sharing: H140.
- Soft-add underflow history in unused `fmc` states: H141.
- Old-noise pre-clamp storage in `mx_old`'s middle lifetime: H142.
- PCM reset-zero validity/payload representation: H143.
- Aligned record-base byte-offset addition: H144.
- W84 dampen accumulation/rounding through the fold ALU and dead
  `{mxs_old,smp_a}` scratch: H145.
- DQ `/64`/`/128`/`/256` selected ceiling incrementer: H146.
- Live/last/old gain-history width contraction: H147.

## Hypothesis H006

- **ID:** H006.
- **Hypothesis:** normal radix-4 multiplier counts are 4, 5, 6, 5 for modes
  0, 1, 2, 3, so spelling the result directly as
  `{1'b1, mode[1] && !mode[0], mode[0]}` should remove the duplicate mode-1
  and mode-3 comparisons in `psg_mulsvc.m_cnt` and `psg_mulmp.seq_pad`.
- **Scope:** exhaustive scratch truth-table proof and isolated registered iCE40
  synthesis. Production multiplier RTL and fidelity gates are conditional on
  an isolated deterministic mapped improvement.
- **Baseline:** accepted H005 commit `5a5a0db`. The isolated current registered
  ternary maps to one LUT4 and three flip-flops.
- **Change:** scratch-only direct count-bit expression; no production file
  changed.
- **Result:** all eight short-request/mode combinations match exactly. Isolated
  `synth_ice40` maps the direct expression to two LUT4s and three flip-flops,
  one LUT4 more than the existing ternary. Yosys already shares the equal
  mode-1 and mode-3 results through its current priority expression.
- **Decision:** rejected before production RTL. The apparent duplicate source
  comparisons are not duplicate mapped logic, and the direct bit form is
  strictly larger in the isolated authoritative metric.
- **Repeat only if:** request modes, step counts, mapper lowering, or the
  surrounding registered load contract changes materially.

## Hypothesis H007

- **ID:** H007.
- **Hypothesis:** `psg_timing.divd` always lies between
  `-(CLK_HZ-22050)` and 22,049, so `$clog2(CLK_HZ)+1` signed bits preserve the
  complete recurrence. The iCE40 target needs 26 bits at 18.75 MHz rather than
  the fixed 28, which should retire two accumulator flops and carry positions
  while making the parameter contract explicit.
- **Scope:** `rtl/psg_timing.sv`, a permanent range/recurrence proof over every
  configured PSG clock, focused timing tests, whole-PSG iCE40 mapping, the
  complete H005 acceptance battery if the mapped result improves, and this
  ledger. No sequencer, walker, waveform, interface, EBR, R.84, or tolerance
  change.
- **Baseline:** accepted H005 production commit `5a5a0db` plus docs-only H006
  `be8d984`: 6,568 LUT4s, 1,566 carries, 1,478 flops, 14 EBRs; seed-1 7,449
  LCs; 137.65 MHz fast and 31.16 MHz PSG.
- **Change:** derive the signed accumulator width as `$clog2(CLK_HZ)+1`,
  type both recurrence constants to that width, and address the sign bit by
  `DIV_W-1`. Add a permanent proof over every configured PSG clock.
- **Result:** the complete `tools/psg_hw_forms.py` passes. Its exact interval
  proof gives widths 23 at 3,506,580 Hz, 26 at 18.75/22.5/28.125 MHz, and 28
  at 112.5 MHz, and the recurrence remains inside its signed range. Full and
  PREVIEW lint passed. `make test-psg` passed the fidelity gate, 93 analysis
  tests, and the complete structural suite at 524/850 sample clocks and
  4,008/5,103 tick clocks with zero late flips. The 59-case 18.75-MHz
  regression was byte-exact. `/4`, `/5`, and `/6` budget runs passed at
  572/1,275 and 5,757/7,654, 572/1,020 and 4,737/6,123, and 524/850 and
  4,008/5,103 sample/tick clocks, with zero lost writes, overruns, or late
  flips. `make test-clocks` passed. All eight canonical PREVIEW checks at
  1,275 and 159 clocks/sample passed at 36/38 voiced windows, rounded 95%,
  for masks 7/1/2/4. Synthetic and reconstructed-Celeste recovery probes
  passed with no coalesced, delayed, or dropped samples. Exact hardware and
  PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. A
  five-frame Celeste smoke again had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,568 LUT4 / 1,566
  carry / 1,478 FF / 14 EBR / 7,449 placed LCs to 6,522 LUT4 / 1,553 carry /
  1,476 FF / 14 EBR / 7,392 placed LCs. Routed clocks changed from 137.65 and
  31.16 MHz to 134.70 and 30.95 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 46-LUT4, 13-carry, and two-flop reductions are
  deterministic; the 57-LC improvement remains just inside placement
  sensitivity and is not overclaimed.
- **Decision:** accepted. It makes the parameter-dependent range contract
  explicit, improves three deterministic mapped resources, reduces seed-1
  placement, preserves every fidelity gate, retains 14 EBRs, and keeps both
  routed clocks above constraint.
- **Repeat only if:** a rejected width derivation may be retried only after
  supported clock parameters, sample rate, recurrence representation, or
  mapper registered-width inference changes materially.

## Hypothesis H008

- **ID:** H008.
- **Hypothesis:** the only two non-trivial `scnt` equality decodes are 176
  (`8'hB0`) and 182 (`8'hB6`). Exposing their common high-nibble predicate
  once and decoding only the distinguishing low nibble should preserve the
  complete counter sequence while allowing iCE40 mapping to share the prefix.
- **Scope:** isolated registered decode synthesis first; `rtl/psg_timing.sv`,
  an exhaustive all-256-counter-value proof, whole-PSG mapping, and the H007
  acceptance battery only if the isolated and whole mapped results improve.
  No sequencer, walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5`: 6,522 LUT4s, 1,553 carries,
  1,476 flops, 14 EBRs; seed-1 7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** scratch-only explicit `scnt[7:4] == 4'hB` predicate plus low-
  nibble equality decodes; no production file changed.
- **Result:** exhaustive comparison over all 256 counter values passes for
  both the 176 and 182 predicates. Isolated registered `synth_ice40` maps the
  current direct equalities and the explicit shared-prefix form identically:
  four LUT4s and two flip-flops each.
- **Decision:** rejected before production RTL. Yosys already shares the
  common high-nibble term, so the candidate changes source without improving
  a deterministic mapped resource.
- **Repeat only if:** a rejected shared-prefix decode may be retried only after
  the tick cadence constants, counter range, mapper equality sharing, or
  surrounding counter-update control changes materially.

## Hypothesis H009

- **ID:** H009.
- **Hypothesis:** `tick_hold` reaches only 0, 1, and 2 at sample boundaries,
  with the exact sequence `2 -> 1 -> 0` after each tick. Representing that
  delay as a shift token `2'b10 -> 2'b01 -> 2'b00` makes `tick_en_d` a direct
  read of bit zero and should remove the decrement and equality decode while
  preserving every clock of the delayed strobe.
- **Scope:** exhaustive event-sequence proof and isolated registered synthesis
  first; `rtl/psg_timing.sv`, permanent timing proof, whole-PSG mapping, and
  the complete H007 acceptance battery only if mapping improves. No sequencer,
  walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008 `519a00e`:
  6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392 LCs;
  134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace `tick_hold`'s equality, decrement, and nonzero guard with
  a two-bit right-shifting token and direct bit-zero delayed-strobe output;
  add the ten-edge sequence proof to the timing forms gate for measurement.
- **Result:** all 59,049 ten-edge sequences over no-sample, sample, and tick
  events match exactly, including held clocks and tick-reload priority. The
  isolated registered form falls from five to three LUT4s with three flops
  unchanged. Canonical whole-PSG mapping instead moves from 6,522 LUT4 / 1,553
  carry / 1,476 FF / 14 EBR to 6,558 LUT4 / 1,558 carry / 1,476 FF / 14 EBR;
  seed-1 placement moves 7,392 to 7,428 LCs. Routed clocks remain above
  constraint at 123.50 MHz fast and 29.83 MHz PSG, but both mapped and placed
  area regress. Production RTL and the conditional permanent proof are
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The isolated local saving
  worsens the authoritative flattened mapping and violates the no-placement-
  regression gate.
- **Repeat only if:** a rejected shift-token form may be retried only after
  the delayed-tick depth, tick/sample ordering, mapper state lowering, or
  surrounding timing control changes materially.

## Hypothesis H010

- **ID:** H010.
- **Hypothesis:** after a tick resets `scnt` to zero, the delayed strobe must
  occur exactly when the next two sample edges see phases zero then one. A
  single pending bit set by the tick, held while `scnt[0]` is zero, and
  consumed while `scnt[0]` is one should replace `tick_hold`'s second flop,
  decrement, nonzero guard, and equality decode while preserving every edge.
- **Scope:** exact state/phase proof and isolated registered synthesis of the
  complete sample-counter/delayed-strobe cone first; `rtl/psg_timing.sv`, a
  permanent timing proof, whole-PSG mapping, and the complete H007 acceptance
  battery only if the isolated and whole mapped results improve. No sequencer,
  walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H009 through
  `6fdabb5`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace `tick_hold` with one pending bit. Set it when the tick
  resets `scnt` to zero, retain it through phase zero, then emit the delayed
  strobe and clear it when `scnt[0]` is one; add the complete reachable-state
  equivalence proof to the timing forms gate for measurement.
- **Result:** exhaustive state exploration from reset closes over all 185
  reachable paired states and 370 held/sample-enabled edges with identical
  `tick_en`, `tick_en_d`, `pre_tick`, and `scnt`. The isolated complete timing
  cone falls from 27 to 23 LUT4s and from 13 to 12 flops with six carries
  unchanged. Canonical whole-PSG mapping instead moves from 6,522 LUT4 / 1,553
  carry / 1,476 FF / 14 EBR to 6,551 LUT4 / 1,558 carry / 1,475 FF / 14 EBR;
  seed-1 placement moves 7,392 to 7,428 LCs. Routed clocks remain above
  constraint at 119.36 MHz fast and 29.97 MHz PSG, but the mapped and placed
  area gates fail. Production RTL and the conditional permanent proof are
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The local flop reduction
  does not offset the worse flattened covering, and this is the second neutral-
  or-worse delayed-tick variant, closing that family under the ledger stop rule.
- **Repeat only if:** a rejected phase-qualified pending bit may be retried
  only after the tick/sample ordering, `scnt` representation, delayed-tick
  depth, or mapper sequential lowering changes materially.

## Hypothesis H011

- **ID:** H011.
- **Hypothesis:** the tilted-saw tail reflects its unsigned 16-bit phase as
  `16'hffff - wx`, which is identically the bitwise complement `~wx`. Spelling
  the identity directly may prevent a subtractor/carry chain while making the
  exact reflection contract simpler.
- **Scope:** exhaustive all-phase proof and isolated registered-use iCE40
  synthesis first; `rtl/psg_wave.sv`, permanent waveform proof, whole-PSG
  mapping, and the complete H007 acceptance battery only if mapping improves.
  No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H010 through
  `032ff34`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** scratch-only replacement of `16'hffff - wx` with `~wx`; no
  production RTL or permanent proof changed.
- **Result:** exhaustive comparison passes all 65,536 unsigned 16-bit phases.
  Isolated synthesis including the complete registered `t_pre` consumer maps
  both forms identically to 93 LUT4s, 45 carries, and 19 flops. Yosys already
  canonicalizes the constant subtract, so no whole-PSG or fidelity battery is
  needed.
- **Decision:** rejected before production RTL. The alternative is source-
  equivalent but does not improve a deterministic mapped resource.
- **Repeat only if:** a rejected complement spelling may be retried only after
  the reflected-ramp width, tail arithmetic, mapper constant-subtract
  lowering, or surrounding consumer changes materially.

## Hypothesis H012

- **ID:** H012.
- **Hypothesis:** `psg_mulmp` already asserts that true transaction busy is
  never high when `seq_pad` is zero, while its transaction and relative-phase
  benches prove padded busy matches the shipped single-clock service. Under
  that closed-loop deadline, `m_busy || (seq_pad != 0)` equals `seq_pad != 0`;
  removing the redundant OR should simplify the sequencer-busy output cone.
- **Scope:** isolated output-cone synthesis first; `rtl/psg_mulmp.sv`, all
  multiplier transaction/relative-phase proofs, whole-PSG mapping, and the
  complete H007 acceptance battery only if mapping improves. No arithmetic,
  schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H011 through
  `a7e2488`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** remove `m_busy` from `m_seq_busy`, leaving the nonzero `seq_pad`
  predicate under the module's existing true-busy deadline assertion.
- **Result:** the Boolean identity holds in all 30 logical states satisfying
  the asserted `m_busy -> seq_pad!=0` invariant, and the isolated output cone
  falls from two LUT4s to one. The real multi-clock suite passes 6,020 boundary
  and randomized transactions for both radix variants; the padded-busy trace
  matches the shipped reference at all ten 1-ns relative phases. Canonical
  whole-PSG mapping nevertheless moves from 6,522 LUT4 / 1,553 carry / 1,476
  FF / 14 EBR to 6,570 LUT4 / 1,558 carry / 1,476 FF / 14 EBR; seed-1
  placement moves 7,392 to 7,442 LCs. Routed clocks pass at 145.99 MHz fast
  and 31.21 MHz PSG, but mapped and placed area regress. Production RTL is
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The exact local output
  simplification worsens flattened covering and violates both area gates.
- **Repeat only if:** a rejected busy-output simplification may be retried only
  after the CDC latency, padding contract, clock ratio/phase, mapper output
  factoring, or sequencer-busy consumer changes materially.

## Hypothesis H013

- **ID:** H013.
- **Hypothesis:** the earlier 34-bit service width predated the current live-
  request audit. Every A is now signed-18-bit-or-narrower, so `|A| <= 131072`;
  every legal B/count/landing combination yields at most 536,739,840, below
  `2^29`. At every step the accumulator stays below `2^17`, the radix-2 sum
  below `2^18`, and radix-4 sum below `2^19`. Narrowing both internal products
  to 29 bits and those sums to their proved widths should retire invisible
  sequential/arithmetic bits while the 34-bit public result remains aligned
  by five leading zeros.
- **Scope:** `rtl/psg_mulsvc.sv`, `rtl/psg_mulmp.sv`, permanent cycle-model
  bounds in `tools/psg_mul_model.py`, multiplier transaction/relative-phase
  proofs, whole-PSG mapping, and the complete H007 acceptance battery if the
  mapped result improves. No request count, schedule, state, public result
  width, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H012 through
  `516c176`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** first narrow both multiplier implementations to a 29-bit product,
  17-bit accumulator, 18-bit radix-2 sum, and 19-bit radix-4 sum while padding
  the public result with five zeros. Then attribute the result with a second
  form that restores `psg_mulsvc` byte-for-byte and narrows only the
  multipumped implementation instantiated by the HX8K target.
- **Result:** the exact model proves every live landing and named consume slice
  on 13,874 magnitudes, both signs, all modes, and both radices. The binding
  maxima are accumulator 131,008, radix-2 sum 262,080, radix-4 sum 524,160,
  and product 536,739,840, each below the proposed width. Both forms pass
  6,020 randomized/boundary transactions and all ten 1-ns relative phases,
  comparing the complete 34-bit public result. Both forms also map and place
  identically: 6,546 LUT4 / 1,556 carry / 1,474 FF / 14 EBR and 7,418 seed-1
  LCs, routed at 134.95 MHz fast / 33.10 MHz PSG. Relative to H007 this is +24
  LUT4, +3 carries, -2 flops, and +26 LCs. Production RTL and the conditional
  model extension are reverted byte-for-byte; the full fidelity battery is
  correctly skipped.
- **Decision:** rejected after two mapped variants. The invisible bound is
  mathematically sound but narrower sequential/arithmetic covering costs more
  logic and placement than the two realized flops save, closing this width
  family under the ledger stop rule.
- **Repeat only if:** a rejected internal-width form may be retried only after
  live A/B bounds, iteration counts, landing offsets, radix recurrence,
  mapper sequential-width inference, or result consumers change materially.

## Hypothesis H014

- **ID:** H014.
- **Hypothesis:** the widest detune correction is `ceil(6*dp/256)`, which
  reaches only 192 over all 8,192 `dp13` values; the `/64`, `/128`, and `/256`
  corrections reach 128, 64, and 32. Narrowing `dq_ceil6_256` and the shared
  `dq_corr` mux from nine bits to eight should remove one adder, mux, and final
  subtract position without changing any value.
- **Scope:** `rtl/psg_wave.sv`, exhaustive correction-range/equivalence proof
  in `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H013 through
  `f1f127e`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** narrow `dq_ceil6_256`, the shared correction mux, every extension
  arm, and the final subtract operand by one bit; add an exhaustive proof of
  all four correction maxima. Compare both forms in one registered full-detune
  harness containing every producer, selection arm, subtract, and output flop.
- **Result:** the exhaustive proof passes all 8,192 `dp13` values and reports
  maxima 192, 128, 64, and 32. The complete registered-use cone maps both the
  nine-bit baseline and eight-bit candidate identically to 189 LUT4s, 73
  carries, and 14 flops. Yosys already propagates the range and deletes the
  unreachable ninth bit through the existing source spelling. Production RTL
  and the conditional permanent proof are reverted byte-for-byte; whole-PSG
  synthesis and the fidelity battery are correctly skipped.
- **Decision:** rejected before production RTL. The source-visible width is
  redundant, but narrowing it does not improve any deterministic mapped
  resource and therefore cannot satisfy the acceptance gate.
- **Repeat only if:** a rejected correction-width form may be retried only
  after the detune coefficients, `dp13` range, correction mux, mapper width
  inference, or downstream subtract changes materially.

## Hypothesis H015

- **ID:** H015.
- **Hypothesis:** every branch that leaves `dq_sub` false also leaves
  `dq_corr` zero. Therefore `dq_sub ? (dq_base - dq_corr) : dq_base` is
  identically `dq_base - dq_corr`; deleting `dq_sub` and the final result mux
  should simplify both the source contract and registered output cone.
- **Scope:** `rtl/psg_wave.sv`, exhaustive waveform/mode/phase equivalence in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  arithmetic value, schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H014 through
  `837cfaf`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** remove `dq_sub` and write the final result as one unconditional
  subtraction; add an exhaustive proof over all 524,288 wavetable/wave/mode/
  `dp13` inputs. Compare both forms in the same registered full-detune harness.
- **Result:** the exhaustive proof establishes `dq_corr == 0` on every path
  where the baseline bypasses subtraction. Both registered-use cones map
  identically to 188 LUT4s, 73 carries, and 14 flops. Yosys already folds the
  conditional base path into the correction/subtract network. Production RTL
  and the conditional permanent proof are reverted byte-for-byte; whole-PSG
  synthesis and the fidelity battery are correctly skipped.
- **Decision:** rejected before production RTL. It removes a source signal but
  does not improve a deterministic mapped resource.
- **Repeat only if:** a rejected unconditional-subtract form may be retried
  only after the detune branch structure, correction defaults, mapper
  arithmetic/mux folding, or downstream consumer changes materially.

## Hypothesis H016

- **ID:** H016.
- **Hypothesis:** the restoring divider maintains `0 <= remainder < divisor`.
  After shifting one dividend bit, `rsh < 2*divisor`; a successful subtraction
  is therefore below 256, while a failed nine-bit subtraction wraps with bit 8
  set. The current ten-bit `d_sub` and bit-9 borrow test can narrow to nine bits
  and bit 8 without changing any reachable step, potentially removing one
  carry/LUT position from the only registered divider service.
- **Scope:** `rtl/psg_divsvc.sv`, exhaustive reachable-step proof in
  `tools/psg_hw_forms.py`, isolated full-service iCE40 synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  division latency, quotient/remainder value, schedule, interface, EBR, R.84,
  or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H015 through
  `c0afe6a`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus closed width experiments:** H013 changed stored
  multiplier recurrence widths and mapped worse; H014 exposed a combinational
  range already removed by Yosys. H016 instead changes the live borrow encoding
  using a sequential restoring invariant that synthesis cannot infer locally.
- **Change:** narrow `d_sub` from ten to nine bits and move the borrow test from
  bit 9 to bit 8. Add an exhaustive proof over all 65,280 reachable divisor,
  remainder, and incoming-dividend-bit transitions.
- **Result:** the proof establishes the restoring invariant and exact fit/next-
  remainder equivalence. Isolated full-service synthesis moves from 51 LUT4 /
  12 carry / 45 flop to 52 LUT4 / 11 carry / 45 flop. Canonical whole-PSG
  synthesis then regresses from 6,522 LUT4 / 1,553 carry / 1,476 FF / 14 EBR /
  7,392 LCs to 6,582 LUT4 / 1,561 carry / 1,476 FF / 14 EBR / 7,459 LCs.
  Routed clocks pass at 150.53 MHz fast and 32.42 MHz PSG, but both mapped and
  placed area gates fail. Production RTL and the conditional permanent proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The reachable-state width
  proof is sound, but the altered borrow covering is globally much worse.
- **Repeat only if:** a rejected nine-bit divider subtract may be retried only
  after the restoring recurrence, divisor width/domain, mapper subtract
  lowering, or downstream quotient/remainder contract changes materially.

## Hypothesis H017

- **ID:** H017.
- **Hypothesis:** full-schedule gain reconstruction has three mutually
  exclusive consumers: W27 uses the new non-wavetable context, W51 uses the
  new wavetable context or the old non-wavetable context. Selecting the narrow
  `{wave, sign}` context first should let one scale mux and negate feed both
  destination arms, replacing `gz_scaled`, `gz_old_scaled`, `mx_new_w51`, and
  `mx_old_w51` with one source-exact result and simpler code.
- **Scope:** `rtl/psg_walk.sv`, exhaustive W27/W51 context equivalence in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  arithmetic value, schedule/action, register lifetime, interface, EBR, R.84,
  or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H016 through
  `2bf1a29`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus prior grouping:** R.36/H007 grouped identical
  multiplier request operands before a wide request mux. H017 applies the same
  accepted narrow-selection law to a different, post-multiply gain consumer
  whose three schedule contexts are now explicit and mutually exclusive.
- **Change:** first select old/new wave and sign before one scale/negate chain.
  Then attribute the result with a scale-only variant that selects the wave
  before one scale mux but keeps sign selection at the destination arms.
- **Result:** all 768 valid W27/W51 context combinations match. Isolated full
  sharing moves 99 LUT4 / 30 carry / 34 flop to 59 / 15 / 34; whole-PSG
  mapping instead moves to 6,538 LUT4 / 1,547 carry / 1,476 FF / 14 EBR and
  7,428 LCs, with routed clocks 134.70 MHz fast / 30.27 MHz PSG. The scale-only
  form maps locally to 90 LUT4 / 15 carry / 34 flop, but globally to 6,533
  LUT4 / 1,547 carry / 1,476 FF / 14 EBR and 7,414 LCs, routed at 140.92 MHz
  fast / 26.11 MHz PSG. Relative to H007, v1 is +16 LUT4/-6 carry/+36 LCs and
  v2 is +11 LUT4/-6 carry/+22 LCs. Production RTL and the conditional proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after two whole-PSG variants. Selecting narrow context
  operands reduces the isolated cone, but its new schedule-control fanout
  worsens flattened destination covering and violates the placement gate.
- **Repeat only if:** a rejected selected-context gain form may be retried only
  after the W27/W51 schedule, gain reconstruction, sign ownership, mapper
  destination covering, or old/new lifetime changes materially.

## Hypothesis H018

- **ID:** H018.
- **Hypothesis:** `gz_171` currently forms the 26-bit sum `341*x + x` and then
  discards bit zero. The exact identity `floor((A+B)/2) = (A>>1) + (B>>1) +
  (A0 & B0)` can compute the same sibling with a 25-bit adder and one carry-in,
  potentially retiring one live carry position without changing truncation.
- **Scope:** `rtl/psg_walk.sv`, exhaustive live-limb proof in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  multiplier request/result, schedule, state, interface, EBR, R.84, or
  tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H017 through
  `cf9e8d3`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace the 26-bit `A+B` followed by `[25:1]` with the 25-bit
  sum `(A>>1) + (B>>1) + (A0 & B0)`; add an exhaustive proof over all 131,072
  live 17-bit limbs.
- **Result:** the exact proof passes. Isolated registered-use synthesis moves
  from 25 LUT4 / 25 carry / 25 flop to 26 LUT4 / 24 carry / 25 flop. Canonical
  whole-PSG synthesis instead moves to 6,553 LUT4 / 1,562 carry / 1,476 FF /
  14 EBR and 7,430 seed-1 LCs, or +31 LUT4/+9 carry/+38 LCs versus H007.
  Routed clocks pass at 121.82 MHz fast / 29.55 MHz PSG, but both mapped and
  placed area gates fail. Production RTL and the conditional permanent proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The smaller isolated carry
  chain worsens flattened covering and loses substantial fast-clock margin.
- **Repeat only if:** a rejected shifted-half-sum form may be retried only
  after the reciprocal identity, limb width, mapper carry lowering, or gain
  consumer changes materially.

## Hypothesis H019

- **ID:** H019.
- **Hypothesis:** `prun` already grants the sample walker exclusive ownership
  of the shared state memory for the complete walk. Selecting the read address,
  write address, write data, and write enable once by that owner should remove
  the walker's phase-qualified read request and per-operation write selects,
  while making the arbitration contract simpler and more explicit.
- **Scope:** `rtl/psg_state_mem.sv`, `rtl/psg_walk.sv`, `rtl/psg.sv`, focused
  ownership/replay proof, isolated state-store iCE40 synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  state layout/value, walk phase/action, sequencer operation, interface outside
  the PSG, EBR, R.84 executor/controller, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H018 through
  `a1364c5`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Ownership/replay proof obligation:** at the edge which starts a walk,
  pre-edge `prun` is still zero, so the sequencer owns and completes its current
  state-memory operation. While `prun` is one, `walk_frozen` makes `seq_hold`
  one, which forces both `eng_we` and `state_tick_we` low and therefore
  `etk_we == 0`; every `wlk_we` is already qualified by `prun`. At the final
  walk edge, the candidate may fetch an otherwise-unused walker word instead
  of the held sequencer address. The registered `state_replay <= prun` then
  holds the sequencer for the entire following reissue edge, when `prun` is
  zero and the sequencer address is fetched again. The sequencer can advance
  and consume `state_q` only on the next edge, after the reissued value is live.
- **Change:** remove `wlk_rd`/`state_sample_read`; first select the complete
  state-memory request bundle with `prun`, then attribute the result with a
  second form which retains the existing write-enable OR while selecting only
  read/write address and write data by whole-walk ownership.
- **Result:** the focused proof exhausts all four legal write-owner states, all
  29 walker words consumed across preview/hardware schedules, and the final-
  read/reissue/resume timeline. Full and PREVIEW lint pass. The complete-bundle
  form improves the isolated state-store cone from 67 LUT4 / 10 carry / 43 FF /
  two EBR to 65 / 5 / 43 / two EBR, but whole-PSG mapping moves to 6,570 LUT4 /
  1,560 carry / 1,476 FF / 14 EBR and 7,452 seed-1 LCs, or +48 LUT4/+7 carry/
  +60 LCs versus H007. Both clocks pass at 142.57 MHz fast / 32.87 MHz PSG.
  Retaining the write-enable OR improves the isolated cone further to 59 LUT4 /
  5 carry / 43 FF / two EBR, but whole-PSG mapping still regresses to 6,544
  LUT4 / 1,559 carry / 1,476 FF / 14 EBR, or +22 LUT4/+6 carry. Its seed-1
  router remains at two overused resources after more than 14,000 iterations
  and is stopped because the deterministic mapped gate has already failed.
  The complete fidelity battery is correctly skipped. All production RTL and
  the conditional proof are reverted byte-for-byte.
- **Decision:** rejected after two whole-PSG forms. Whole-walk ownership is a
  sound source simplification, but its higher-fanout owner select worsens the
  flattened mapping and neither form has a deterministic mapped improvement.
- **Repeat only if:** if rejected, retry only after the walk/replay ownership
  interval, state-memory port topology, mapper mux absorption, or sequencer
  write-gating contract changes materially.

## Hypothesis H020

- **ID:** H020.
- **Hypothesis:** audio-RAM synthesis reads are explicitly qualified by
  `prun`, and their registered one-cycle replay occurs while the walk is still
  active. Therefore `seq_frozen = syn_rd | replay` is already implied by the
  top-level `prun` hold. Removing that exported busy term while retaining the
  RAM's internal replay/reissue should simplify the hold cone without changing
  any address, data, FSM, credit, or sample clock.
- **Scope:** `rtl/psg_aram.sv`, `rtl/psg.sv`, focused phase/containment proof,
  isolated registered hold-cone synthesis, whole-PSG mapping, and the complete
  H007 acceptance battery if mapping improves. No RAM content/port operation,
  sequencer/walker action, arithmetic, state layout, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H020 setup
  through `f3e5f8d`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Containment proof obligation:** `psg_walk.syn_rd` is zero by default and
  can become one only inside `prun && !ctrl_stall`. In preview its last possible
  read is phase 13 versus `PLAST=23`; in multipumped hardware the last read is
  action W3 at phase 32 versus `PLAST=61`. Since `replay <= syn_rd`, every
  replay edge also occurs while `prun` remains one, including a stalled phase.
  Thus `syn_rd | replay` cannot add a held clock beyond `prun`; only the internal
  `aram_rd = syn_rd | replay | !seq_hold` reissue remains semantically live.
- **Change:** remove the redundant `seq_frozen` output and its top-level
  OR term, without changing `replay`, `aram_rd`, or the address mux.
- **Result:** the focused proof exhausts all six preview/hardware wavetable-read
  phases and proves their replay edges precede `PLAST`. Full and PREVIEW lint
  pass. The isolated registered hold cone falls from 13 to 12 LUT4s with six
  carries and nine flops unchanged. Canonical whole-PSG mapping instead moves
  from 6,522 LUT4 / 1,553 carry / 1,476 FF / 14 EBR / 7,392 LCs to 6,525 /
  1,556 / 1,476 / 14 / 7,393. Routed timing passes at 142.86 MHz fast / 28.95
  MHz PSG, but both deterministic mapping and no-placement-regression gates
  fail. The complete fidelity battery is correctly skipped. Both production
  RTL files are restored byte-for-byte.
- **Decision:** rejected after whole-PSG synthesis. The temporal redundancy is
  exact, but removing its explicit output changes flattened covering for the
  worse and has no accepted physical metric.
- **Repeat only if:** if rejected, retry only after wavetable-read phase,
  audio-RAM replay depth, walk termination, mapper busy-cone lowering, or
  sequencer-credit ownership changes materially.

## Hypothesis H021

- **ID:** H021.
- **Hypothesis:** `fdec(n)` is exactly the three base-3 digits of `n mod 27`,
  each stored in a two-bit field. Replacing its 32 explicit case arms with one
  wrap-at-27 step and two small quotient/remainder stages should make the
  filter contract much shorter and may share the narrow comparisons/subtracts
  better than the table mux.
- **Scope:** `rtl/psg_seq.sv`, exhaustive all-32-input equivalence, isolated
  registered decoder/consumer synthesis, whole-PSG mapping, and the complete
  H007 acceptance battery if mapping improves. No note data, filter value,
  FSM phase/action, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H021 setup
  through `5e0f19b`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus prior decode experiments:** task 5.3 explicitly
  leaves filter decode open. H021 replaces the entire 32-arm function using
  its arithmetic structure; it does not peel individual phase consumers from
  shared pph decode or add a new ROM/EBR.
- **Change:** exhaustively prove the identity and compare both direct `/`/`%`
  arithmetic and explicit two-stage threshold/subtract decompositions against
  the full registered table consumer. No production RTL is changed.
- **Result:** all 32 inputs match the packed base-3 digits of `n mod 27`. The
  existing table maps to 23 LUT4 / zero carry / 12 FF. Direct arithmetic maps
  to 28 LUT4 / 70 carry / 12 FF, while the staged form maps to 26 LUT4 / 11
  carry / 12 FF. Both candidates are strictly larger in the isolated complete
  consumer cone, so whole-PSG synthesis and the fidelity battery are correctly
  skipped.
- **Decision:** rejected before production RTL. The arithmetic structure is a
  useful specification, but the current truth table already receives superior
  Boolean covering from Yosys/ABC.
- **Repeat only if:** if rejected, retry only after the note filter encoding,
  consumer fields, mapper truth-table/arithmetic lowering, or constants-ROM
  port schedule changes materially.

## Hypothesis H022

- **ID:** H022.
- **Hypothesis:** for signed nine-bit `v`, clamping to unsigned 0..63 is exactly
  `v[8] ? 0 : |v[7:6] ? 63 : v[5:0]`. Spelling the sign and overflow prefixes
  directly should remove two relational comparisons from each inlined pitch
  clamp while making its saturation contract explicit.
- **Scope:** `rtl/psg_seq.sv`, exhaustive all-512-input proof, isolated
  registered synthesis of the three live clamp consumers, whole-PSG mapping,
  and the complete H007 acceptance battery if mapping improves. No pitch value,
  FSM phase/action, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H022 setup
  through `d703d5e`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus H004:** H004 narrowed one unsigned aligned waveform
  threshold which Yosys already pruned. H022 replaces both sides of a signed
  saturating clamp at three sequencer consumers using the sign/overflow prefix;
  it is a different cone and removes relational operators entirely.
- **Change:** replace the two relational comparisons in `pclamp` with the exact
  sign/high-bit decode at all three inlined consumers. Attribute the first
  whole-PSG result with a second form that also narrows the three live raw sums
  from nine to eight signed bits using their proved -24..102 range.
- **Attribution:** the general nine-bit form reduces the isolated live cone
  from 111 LUT4 / 37 carry / 18 FF to 96 / 24 / 18. Whole-PSG mapping instead
  moves to 6,546 LUT4 / 1,540 carry / 1,476 FF / 14 EBR and 7,398 seed-1 LCs,
  or +24 LUT4/-13 carry/+6 LCs versus H007. Timing passes at 150.53 MHz fast /
  30.83 MHz PSG, but placement fails the no-regression gate. The live-range
  eight-bit attribution form maps to 6,539 LUT4 / 1,539 carry / 1,476 FF / 14
  EBR and 7,391 seed-1 LCs, or +17 LUT4/-14 carry/-1 LC versus H007. Timing
  passes at 150.53 MHz fast / 29.86 MHz PSG. The carry improvement is
  deterministic; the one-LC placement change is inside sensitivity and is not
  claimed as robust.
- **Result:** exhaustive proofs cover all 512 signed-nine inputs and all 4,096
  live unsigned-six operand pairs, proving the live range -24..102 and exact
  signed-eight saturation. The complete `tools/psg_hw_forms.py`, full/PREVIEW
  lint, `make test-psg` (93 analysis tests and every structural test), and the
  59/59 exact 18.75-MHz frozen-render regression passed. The `/4`, `/5`, and
  `/6` demand tests retained 524 worst walk/sample clocks and tick results
  5,757/7,654, 4,737/6,123, and 4,008/5,103 with zero lost writes, overruns, or
  late flips. `make test-clocks` passed. All eight P.1 Celeste preview checks
  at 1,275 and 159 clocks/sample passed with 36/38 voiced windows, or 95%, for
  combined and masks 1/2/4; both P.2 recovery probes passed. Exact hardware
  and PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. The
  five-frame Celeste smoke had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H007's 6,522 LUT4 /
  1,553 carry / 1,476 FF / 14 EBR / 7,392 placed LCs to 6,539 LUT4 / 1,539
  carry / 1,476 FF / 14 EBR / 7,391 placed LCs. Routed clocks changed from
  134.70 and 30.95 MHz to 150.53 and 29.86 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The 14-carry reduction is deterministic; the
  one-LC placement improvement is inside sensitivity and is not overclaimed.
- **Decision:** accepted. It makes the proved -24..102 live range and
  saturation contract explicit, removes the signed relational comparisons,
  improves a deterministic mapped resource, does not regress placed LCs,
  preserves every fidelity gate, and retains 14 EBRs. The 17-LUT4 tradeoff is
  recorded rather than hidden.
- **Repeat only if:** if rejected, retry only after pitch operand bounds/width,
  saturation range, consumer count, or mapper signed-comparison lowering changes.

## Hypothesis H023

- **ID:** H023.
- **Hypothesis:** the six-bit slide pitch's octave thresholds have exact prefix
  predicates: `>=12`, `>=24`, `>=36`, `>=48`, and `>=60` depend only on
  compact combinations of bits 5:2. Replacing the five relational comparisons
  with those shared predicates should remove comparator carry chains while
  preserving both `sl_oct` and the existing `sl_chr = sl_int - 12*sl_oct`.
- **Scope:** scratch exhaustive proof and isolated registered synthesis of the
  complete octave/chromatic consumer cone. Production `rtl/psg_seq.sv`, the
  permanent hardware-forms proof, whole-PSG mapping, and the complete H022
  battery are conditional on a deterministic isolated mapped improvement. No
  pitch value, slide interpolation, FSM phase/action, service, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H022 commit `f569fa1`: 6,539 LUT4s, 1,539 carries,
  1,476 flops, 14 EBRs; seed-1 7,391 LCs; 150.53 MHz fast and 29.86 MHz PSG.
- **Changed condition versus H004:** H004 narrowed one unsigned square-wave
  threshold and mapped identically because Yosys already discarded aligned low
  bits. H023 replaces a five-threshold ladder, exposes shared prefix terms, and
  includes the downstream octave/remainder consumers in the isolated price.
- **Change:** replace the five six-bit relational thresholds with five exact
  shared prefix predicates over `sl_int[5:2]`; retain the priority encoding and
  chromatic subtract. Add all 64 octave/remainder cases to the permanent
  hardware-forms proof.
- **Result:** the scratch proof, permanent exhaustive proof, and full
  `tools/psg_hw_forms.py` passed. The isolated registered octave/chromatic cone
  changed from eight LUT4s / 12 carries / nine flops to seven LUT4s / one carry
  / nine flops. Full and PREVIEW lint, `make test-psg`, 59/59 exact renders,
  `/4`, `/5`, and `/6` budget regressions, and `make test-clocks` passed. All
  eight P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed with
  36/38 voiced windows, or 95%, for combined and masks 1/2/4; synthetic and
  frozen-Celeste recovery passed. Exact hardware and PREVIEW SFX-10 renders
  were active and `click-v1` found zero clicks. The five-frame Celeste smoke
  had 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068 distinct
  levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H022's 6,539 LUT4 /
  1,539 carry / 1,476 FF / 14 EBR / 7,391 placed LCs to 6,529 LUT4 / 1,533
  carry / 1,476 FF / 14 EBR / 7,367 placed LCs. Routed clocks changed from
  150.53 and 29.86 MHz to 122.23 and 30.64 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The ten-LUT4 and six-carry reductions are
  deterministic; the 24-LC placement improvement is inside sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the exact prefix structure explicit,
  improves two deterministic mapped resources, does not regress placed LCs,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after slide pitch width/range,
  octave thresholds, chromatic representation, or mapper comparison lowering
  changes materially.

## Hypothesis H024

- **ID:** H024.
- **Hypothesis:** both row-length bounds return the source value only on the
  exact interval 1--31 and return 32 otherwise. Expressing those intervals as
  non-zero low-five-bit values with zero upper prefixes should remove the two
  comparator carry cells and make the clamp contract explicit.
- **Scope:** exhaustive scratch proof and isolated registered synthesis of both
  row-bound consumers. Production `rtl/psg_seq.sv`, a permanent hardware-forms
  proof, whole-PSG mapping, and the complete H023 battery are conditional on a
  deterministic isolated mapped improvement. No row value, sequencer state,
  address, schedule, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
  Isolated reconnaissance maps the complete current pair to nine LUT4s / two
  carries / 14 flops and the prefix pair to nine LUT4s / zero carries / 14
  flops; whole-PSG mapping remains authoritative.
- **Changed condition versus H004:** H004 narrowed one already-aligned waveform
  threshold and mapped identically. H024 collapses two nested clamp/select
  expressions to exact interval predicates and the isolated complete consumer
  cone already removes two mapped carry cells.
- **Change:** replace both nested non-zero/range clamps with exact upper-prefix
  tests and direct zero-extension of `acc[4:0]`; add exhaustive permanent proof
  during measurement.
- **Result:** exhaustive comparison passed for all 65,536 `acc` values in the
  effect-end bound and all 65,536 low-byte/`seq_q` combinations in the pattern
  bound. The isolated registered pair changed from nine LUT4s / two carries /
  14 flops to nine LUT4s / zero carries / 14 flops. The whole-PSG mapped gate
  then failed, so the full fidelity battery was not run and both production and
  permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,561 LUT4 / 1,526
  carry / 1,476 FF / 14 EBR / 7,386 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 132.70 and 29.40 MHz; both pass, but the 32-LUT4 and
  19-LC regressions outweigh the seven-carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current nested clamps; the prefix spelling is locally smaller only
  in carry count and globally worse in both LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after row metadata semantics,
  clamp value, consumer sharing, or mapper comparison lowering changes.

## Hypothesis H025

- **ID:** H025.
- **Hypothesis:** fade advancement currently spells the same
  `fade_acc + fade_step` operation once at 17 bits for overflow and twice at
  16 bits for the next accumulator/gain. One explicit 17-bit sum should expose
  the shared carry chain, replace the constant comparison with its carry bit,
  and simplify all three consumers without changing fade behavior.
- **Scope:** scratch exact/formal equivalence and isolated registered synthesis
  of the complete fade consumer cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No fade rate,
  direction, stop behavior, tick cadence, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Change:** scratch one explicit 17-bit sum, use its carry as overflow, and
  use its low 16/high eight bits for the accumulator and gain consumers.
- **Result:** Yosys formal equivalence proved all 25 output bits. Isolated
  registered `synth_ice40` maps both the current repeated expressions and the
  explicit shared sum to 24 LUT4s / 16 carries / 25 flops. No production or
  permanent-proof file changed, and the whole-design/fidelity gates were not
  needed.
- **Decision:** rejected before production because it changes source spelling
  without changing the deterministic mapped cone.
- **Repeat only if:** if rejected, retry only after fade accumulator/step width,
  next-gain consumers, overflow contract, or mapper common-subexpression
  lowering changes materially.

## Hypothesis H026

- **ID:** H026.
- **Hypothesis:** the sequencer's shared rollover/loop/record predicate
  `(ta_a + 1) >= ta_b` is exactly the carry-out of
  `{0,ta_a} + {0,~ta_b} + 2`. Spelling that carry directly may merge the
  increment and comparison into one chain while making the inclusive bound
  contract explicit.
- **Scope:** exhaustive/formal scratch proof and isolated registered synthesis
  of the complete predicate cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No counter,
  loop, row, state, address, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Change:** scratch the raw two's-complement carry and then repair its sole
  `a=255,b=0` counterexample with an explicit `b==0` term. Promote the repaired
  form and exhaustive all-pairs proof for whole-PSG measurement.
- **Result:** formal equivalence refuted the raw carry at exactly the tenth-bit
  overflow corner; that form mapped to 15 LUT4s / seven carries / one flop.
  Formal equivalence and exhaustive enumeration then proved the repaired form
  for all 65,536 input pairs. The exact isolated registered cone changed from
  16 LUT4s / 16 carries / one flop to 16 LUT4s / seven carries / one flop. The
  whole-PSG mapped gate failed, so the full fidelity battery was not run and
  both production and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,560 LUT4 / 1,519
  carry / 1,476 FF / 14 EBR / 7,381 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 137.42 and 30.44 MHz; both pass, but the 31-LUT4 and
  14-LC regressions outweigh the 14-carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current relational predicate; the explicit carry is locally and
  globally carry-smaller but globally worse in LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after bound width/semantics,
  predicate consumers, or mapper compare/carry lowering changes materially.

## Hypothesis H027

- **ID:** H027.
- **Hypothesis:** the duplicated signed 18-bit noise clamps compare against
  exact boundaries +6144 and -6144. Direct positive and two's-complement
  negative prefix predicates may remove both comparator carry chains while
  making the saturation interval explicit.
- **Scope:** exhaustive all-18-bit proof and isolated registered synthesis of
  the complete clamp output. Production `rtl/psg_walk.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No noise value,
  clamp constant, live/old path, state, schedule, memory, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Changed condition versus H022:** H022's pitch clamp uses aligned sign/high-
  bit boundaries 0 and 64. H027 has the distinct unaligned symmetric audio
  interval -6143..6143, including an asymmetric two's-complement lower prefix,
  and the complete output mux is measured rather than only its predicates.
- **Change:** replace both signed relational clamp ladders with one shared helper
  that decodes the exact positive and two's-complement negative prefixes; add
  exhaustive permanent coverage of every signed 18-bit input.
- **Result:** Yosys formal equivalence and the permanent proof cover all
  262,144 inputs; full `tools/psg_hw_forms.py` passes. One isolated registered
  clamp changes from 23 LUT4s / 32 carries / 16 flops to 25 LUT4s / zero
  carries / 16 flops. Full and PREVIEW lint passed. `make test-psg` passed the
  PICO-8 noise-fidelity gate, all 93 analysis tests, and the complete structural
  suite at 524/850 sample clocks and 4,008/5,103 tick clocks with zero late
  flips. The 59-case 18.75-MHz frozen-render regression was byte-exact. `/4`,
  `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654, 572/1,020 and
  4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks, with zero lost
  writes, overruns, or late flips. `make test-clocks` passed. All eight P.1
  Celeste preview checks at 1,275 and 159 clocks/sample passed with 36/38 voiced
  windows, or 95%, for combined and masks 1/2/4. Synthetic and frozen-Celeste
  recovery passed with no coalesced, delayed, or dropped samples. Exact hardware
  and PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. The
  five-frame Celeste smoke had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,550 LUT4 / 1,464
  carry / 1,476 FF / 14 EBR / 7,306 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 146.69 and 32.99 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The 69-carry reduction is deterministic. The
  61-LC improvement is at the established roughly 60-LC sensitivity boundary
  and is recorded without claiming robustness; the 21-LUT4 tradeoff is explicit.
- **Decision:** accepted. It centralizes the duplicated saturation contract,
  removes both signed relational carry chains, improves the mapped carry count
  substantially, does not regress placement, preserves every fidelity gate,
  and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after noise width/range, clamp
  constant, live/old consumer structure, or mapper signed-comparison lowering
  changes materially.

## Hypothesis H028

- **ID:** H028.
- **Hypothesis:** the eight-bit arpeggio-speed test `eff_sp <= 8` is exactly
  zero in bits 7:4 with either bit 3 clear or all lower three bits clear.
  Exposing that prefix once for both fast/slow bit-slice selections may remove
  the relational comparator carry chain and simplify the selector contract.
- **Scope:** exhaustive scratch proof and isolated registered synthesis of the
  complete `arp_idx` consumer cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H027 battery are
  conditional on a deterministic isolated mapped improvement. No effect code,
  speed, tick counter, selected index, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H004/H024:** H004's aligned waveform threshold was
  already pruned, and H024's pair of clamp outputs regressed globally. H028 is
  one shared non-aligned predicate feeding two effect-dependent bit-slice muxes;
  the complete consumer cone is priced before production.
- **Change:** replace the duplicated relational test with one exact upper-prefix
  predicate and add exhaustive permanent proof during measurement.
- **Result:** Yosys formal equivalence proves both `arp_idx` output bits, and
  exhaustive enumeration proves the predicate for all 256 speed bytes. The
  isolated registered consumer changes from nine LUT4s / four carries / two
  flops to 11 LUT4s / zero carries / two flops. Whole-PSG mapping then fails the
  physical gate, so the full fidelity battery was not run and both production
  and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,558 LUT4 / 1,464
  carry / 1,476 FF / 14 EBR / 7,319 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 128.35 and 32.70 MHz; both pass, but the candidate
  adds eight LUT4s and 13 LCs without any global carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the relational test; the prefix is locally carry-smaller but globally
  worse in both LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after effect-speed semantics,
  counter slicing, consumer sharing, or mapper comparison lowering changes.

## Hypothesis H029

- **ID:** H029.
- **Hypothesis:** `3*nz_g <= nz_dp + 497` is exactly the non-negative sign of
  the 16-bit margin `nz_dp + 497 - 3*nz_g`; its full range is
  -24,076..8,688. Spelling the bounded margin directly may replace the current
  right-side add plus relational comparator with one shared subtract chain.
- **Scope:** formal scratch proof and isolated registered synthesis of the
  complete kick-enable cone, including the `3*nz_g` add. Production
  `rtl/psg_walk.sv`, a permanent hardware-forms range/boundary proof,
  whole-PSG mapping, and the complete H027 battery are conditional on a
  deterministic isolated mapped improvement. No noise step, kick probability,
  oscillator value, state, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H026:** H026 rewrote one incremented relational
  predicate and regressed globally. H029 fuses an affine constant add and
  variable three-times operand into one proved signed margin; the complete
  producer/consumer cone is priced before production.
- **Change:** replace the right-side add and relational comparison with the sign
  of the proved 16-bit margin `nz_dp + 497 - nz_g3`; add permanent range and
  per-`g` transition-boundary coverage during measurement.
- **Result:** Yosys formal equivalence proves the enable bit. The permanent
  proof establishes the exact signed range -24,076..8,688 and checks 24,574
  domain endpoints/transition neighbours. The isolated registered cone changes
  from 50 LUT4s / 40 carries / one flop to 28 LUT4s / 40 carries / one flop.
  Whole-PSG mapping then fails the placement gate, so the full fidelity battery
  was not run and both production and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,553 LUT4 / 1,442
  carry / 1,476 FF / 14 EBR / 7,327 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 132.57 and 29.82 MHz; both pass, but the candidate
  adds three LUT4s and 21 LCs despite saving 22 carries.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current inequality; the affine margin is locally LUT-smaller and
  globally carry-smaller, but regresses placed area.
- **Repeat only if:** if rejected, retry only after `nz_g`/`nz_dp` bounds,
  kick constant, producer sharing, or mapper affine-comparison lowering changes.

## Hypothesis H030

- **ID:** H030.
- **Hypothesis:** the foreground trigger-length write saturates an input byte to
  32, so `di > 32` is exactly any high bit 7:6 or bit 5 with a non-zero low
  suffix. Directly decoding that prefix may remove the comparator carry chain
  from the six-bit register input.
- **Scope:** exhaustive/formal scratch proof and isolated registered synthesis
  of the complete saturation consumer. Production `rtl/psg_seq.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H027
  battery are conditional on a deterministic isolated mapped improvement. No
  trigger row/length semantics, address decode, state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H024:** H024 changed two combinational row bounds
  feeding shared sequencer comparison/mux logic. H030 is one bus-write
  saturation feeding only a six-bit register, with no shared downstream bound;
  its complete registered cone is measured before production.
- **Change:** replace the byte-wide `di > 32` comparison with the exact high-bit
  and non-zero-suffix prefix; add permanent exhaustive coverage of all 256 input
  bytes.
- **Result:** Yosys formal equivalence proves all six registered result bits;
  exhaustive coverage proves every input byte. The isolated registered cone
  changes from three LUT4s / two carries / six flops to three LUT4s / zero
  carries / six flops. Full `tools/psg_hw_forms.py`, full and PREVIEW lint,
  `make test-psg` including 93 analysis tests, and the 59/59 frozen-render
  regression passed. `/4`, `/5`, and `/6` budget runs passed at 572/1,275 and
  5,757/7,654, 572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103
  sample/tick clocks, with zero lost writes or late flips. `make test-clocks`
  passed. All eight Celeste preview checks at 1,275 and 159 clocks/sample passed
  with 36/38 voiced windows, or 95%, for combined and masks 1/2/4. Synthetic
  and frozen-Celeste recovery passed with no coalesced, delayed, or dropped
  samples. Exact hardware and PREVIEW SFX-10 renders were active and `click-v1`
  found zero clicks. The five-frame Celeste smoke had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,546 LUT4 / 1,462
  carry / 1,476 FF / 14 EBR / 7,297 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 133.69 and 31.08 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The four-LUT4 and two-carry reductions are
  deterministic; the nine-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the exact saturation interval explicit,
  improves both deterministic mapped resources, does not regress placement,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative trigger-length form may be retried only
  after foreground length semantics, input/register width, write decode, or
  mapper comparison lowering changes.

## Hypothesis H031

- **ID:** H031.
- **Hypothesis:** the T_NL pattern-length test `acc[7:0] >= seq_q` is active in
  a state mutually exclusive with the EA2/EA4/EA5 row-bound test
  `ta_a + 1 >= ta_b`. Selecting T_NL's operands and a zero increment into that
  existing comparator should retire the separate eight-bit relation while
  preserving both contracts and making the time sharing explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of both
  registered predicate consumers. Production `rtl/psg_seq.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H030 battery are
  conditional on a deterministic isolated mapped improvement. No row/length,
  trigger, multiply, state, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H030 commit `a747493`: 6,546 LUT4s, 1,462 carries,
  1,476 flops, 14 EBRs; seed-1 7,297 LCs; 133.69 MHz fast and 31.08 MHz PSG.
- **Changed condition versus H026:** H026 changed the arithmetic spelling of
  the existing row-bound predicate and regressed globally. H031 retains that
  predicate exactly while folding a second, state-exclusive comparator into
  its operand/bias selection; the complete paired consumer cone is priced
  before production.
- **Change:** select T_NL's accumulator byte and pattern-length byte into the
  existing row-bound operands, select a zero rather than one increment in that
  state, and consume the shared predicate for `tnl_len_launch`. Add permanent
  exhaustive coverage of both selected relations over all byte pairs.
- **Result:** Yosys equivalence proves both registered consumer outputs. The
  permanent proof checks all 65,536 operand pairs. The isolated paired cone
  changes from 43 LUT4s / 24 carries / two flops to 43 LUT4s / 17 carries /
  two flops. Full hardware forms and full/PREVIEW lint passed. `make test-psg`
  including 93 analysis tests and the 59/59 frozen-render regression passed.
  `/4`, `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654,
  572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks,
  with zero lost writes or late flips. `make test-clocks` passed. All eight
  Celeste preview checks at 1,275 and 159 clocks/sample passed with 36/38
  voiced windows, or 95%, for masks 7/1/2/4. Synthetic and frozen-Celeste
  recovery passed with no coalesced, delayed, or dropped samples. Exact
  hardware and PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke had 2,179/3,668 off-centre samples,
  range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation
  and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changes H030's 6,546 LUT4 /
  1,462 carry / 1,476 FF / 14 EBR / 7,297 placed LCs to 6,545 LUT4 / 1,455
  carry / 1,476 FF / 14 EBR / 7,287 placed LCs. Routed clocks change from
  133.69 and 31.08 MHz to 150.53 and 31.35 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The one-LUT4 and seven-carry reductions are
  deterministic; the ten-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the mutually exclusive comparator sharing
  explicit, improves both deterministic mapped resources, does not regress
  placement, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative shared comparator may be retried only
  after T_NL/EA state exclusivity, row/length comparison semantics, comparator
  consumers, or mapper mux/carry lowering changes.

## Hypothesis H032

- **ID:** H032.
- **Hypothesis:** sequencer audio reads select between a channel SFX record and
  a custom-instrument record, but the current cone applies the identical
  `rec_base()` transform to both six-bit record numbers before selecting their
  13-bit results. Selecting the record number first should expose one base
  transform, reduce the address mux/add cone, and simplify the source.
- **Scope:** formal scratch proof and isolated synthesis of the complete
  registered audio-RAM address consumer. Production `rtl/psg_seq.sv`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  address schedule, record layout, memory, EBR, state, comparator, R.84
  executor, or tolerance change.
- **Baseline:** accepted H031 commit `35fd3b4`: 6,545 LUT4s, 1,455 carries,
  1,476 flops, 14 EBRs; seed-1 7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H017/H019:** those rows shared arithmetic across
  different downstream contexts or changed state-memory ownership and became
  globally worse. H032 moves one selector across two identical pure
  `rec_base()` calls inside a single address consumer; it changes neither
  ownership nor arithmetic semantics and prices the full registered cone
  before production.
- **Change:** select the six-bit channel or instrument record number before one
  `rec_base()` call instead of selecting two 13-bit transformed bases; add a
  permanent exhaustive proof over all 1,024 channel/instrument/select tuples
  for the whole-design measurement.
- **Result:** Yosys equivalence proves all 13 registered address bits over the
  full input domain. The complete isolated address cone changes from 78 LUT4s
  / 16 carries / 13 flops to 77 LUT4s / nine carries / 13 flops. The
  deterministic isolated improvement admits the production measurement.
  Permanent exhaustive forms and full/PREVIEW lint pass. Whole-PSG mapping
  then fails both deterministic area and placement gates, so the full behavior
  battery is not run and both production and permanent-proof edits are
  reverted. Strict OpenSpec validation and `git diff --check` pass after the
  revert.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,577 LUT4 / 1,448
  carry / 1,476 FF / 14 EBR / 7,319 placed LCs. Routed clocks change from
  150.53 and 31.35 MHz to 131.72 and 30.39 MHz; both pass, but the candidate
  adds 32 LUT4s and 32 LCs despite saving seven carries.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the two precomputed bases; the record-first form is simpler and locally
  smaller but globally area-worse.
- **Repeat only if:** retry only after `rec_base()`, record-number widths,
  audio-RAM address schedule, or mapper mux/add factoring changes.

## Hypothesis H033

- **ID:** H033.
- **Hypothesis:** `aud_sl(ch, play)` chooses the foreground slot when it is
  active and the paired music slot otherwise. Therefore the subsequent
  `play[aud_sl(ch, play)]` CPU readback bit is exactly
  `play[ch] | play[{1'b1,ch}]`. Spelling that invariant directly may replace
  the dynamic eight-slot lookup with two four-slot selects and one OR.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered CPU readback consumer. Production `rtl/psg.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  readback value, slot selection elsewhere, state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** docs-only H032 commit `925b0b5` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition:** no earlier continuation row rewrites the CPU readback
  activity bit. This is a local Boolean identity at one registered consumer,
  not state-memory ownership, address-base sharing, or comparator arithmetic.
- **Change:** replace both `play[aud_sl(ch, play)]` uses in a scratch copy of
  the complete registered CPU readback with `play[ch] | play[{1'b1,ch}]`.
- **Result:** exhaustive coverage proves the identity for all 1,024 channel /
  play-vector tuples. Yosys temporal induction proves all eight registered
  readback bits over the full input domain. Both complete consumers map to 85
  LUT4s and eight flops, so no production or permanent-proof file changes and
  no whole-PSG or behavior gate is warranted.
- **Decision:** rejected before production because it is mapping-identical.
  Keep the current helper-based spelling, which remains clearer at its other
  sequencer call sites.
- **Repeat only if:** retry only after `aud_sl()`, foreground/music pairing,
  CPU readback semantics, or mapper dynamic-index lowering changes.

## Hypothesis H034

- **ID:** H034.
- **Hypothesis:** `pat_rows` saturates a non-zero byte to 32 when `seq_q` is
  zero. Its `acc[7:0] < 32` relation is exactly the absence of any high bit
  7:5, so a direct prefix decode may remove the comparator carry chain from
  this single six-bit pattern-length producer.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered pattern-row consumer. Production `rtl/psg_seq.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  pattern length, product, state, schedule, memory, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** docs-only H033 commit `9a73699` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H024/general comparator closure:** H024 rewrote
  nested bounds feeding the shared row/end comparator and regressed globally.
  H030 subsequently accepted the same prefix principle at one six-bit
  saturation consumer. H034 is a second standalone six-bit saturation feeding
  only the pattern-length product, so H030 supplies new physical evidence for
  this bounded retry.
- **Change:** replace the standalone `< 32` relation with `|acc[7:5]`, after
  proving the complete registered consumer and measuring it in isolation.
- **Result:** Yosys equivalence proves all six registered result bits. Permanent
  exhaustive coverage proves all 65,536 accumulator/sequence-byte pairs. The
  isolated registered consumer changes from five LUT4s / two carries / six
  flops to six LUT4s / zero carries / six flops. Full hardware forms and full
  and PREVIEW lint pass. Whole-PSG mapping then fails both deterministic area
  and placement gates, so the complete behavior battery is not run and the
  production and permanent-proof edits are reverted. Strict OpenSpec and diff
  checks pass after the revert.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,560 LUT4 / 1,459
  carry / 1,476 FF / 14 EBR / 7,307 placed LCs. Routed clocks are 150.53 and
  31.34 MHz and pass, but the candidate adds 15 LUT4s, four carries, and 20
  placed LCs.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the relational spelling; the exact prefix is globally area-worse.
- **Repeat only if:** retry only after pattern-length semantics,
  `acc` width, product consumer, or mapper saturation lowering changes.

## Hypothesis H035

- **ID:** H035.
- **Hypothesis:** four exact detune corrections test whether the low two, six,
  seven, or eight bits of `dp13` are non-zero. The current independent
  reductions are strictly nested. Naming one monotone suffix chain may let the
  iCE40 mapper share its lower Boolean cones and simplify the source contract.
- **Scope:** formal scratch proof and isolated synthesis of the complete
  registered suffix/ceiling consumer. Production `rtl/psg_wave.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H031 battery are
  conditional on a deterministic isolated mapped improvement. No coefficient,
  quotient, rounding, wave/mode selection, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** docs-only H034 commit `b41aee0` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H025 and the closed prefix family:** H025 shared
  two repeated full additions that Yosys already factored. H035 instead exposes
  four strictly nested Boolean reductions whose distinct outputs are consumed
  together by the same detune service. It changes no comparison or saturation
  predicate.
- **Change:** define `nz2`, extend it through bits 5, 6, and 7, then consume the
  four named suffix predicates in place of the independent reductions.
- **Result:** Yosys equivalence proves all 22 registered result bits. The
  complete current and candidate consumers both map to 24 LUT4s, 18 carries,
  and 22 flops, so no production or permanent-proof file changes and no whole-
  PSG or behavior gate is warranted.
- **Decision:** rejected before production because the explicit sharing is
  mapping-identical. Keep the independent expressions, which state each
  ceiling formula directly.
- **Repeat only if:** retry only after detune correction widths,
  suffix consumers, coefficient forms, or mapper multi-output factoring changes.

## Hypothesis H036

- **ID:** H036.
- **Hypothesis:** the tilt `/7` and `/15` quotient terms are produced in
  mutually exclusive `tilt_hi` modes, registered on the same edge, and selected
  only after that boundary. Selecting `{0,t_h7}` or `t_h15` before one 11-bit
  register should remove ten flops and make the actual lifetime explicit.
- **Scope:** formal/exhaustive scratch proof and isolated synthesis of the
  complete registered quotient consumer. Production `rtl/psg_wave.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  quotient value, divisor, reciprocal EBR, pipeline edge, waveform result,
  state schedule, R.84 executor, or tolerance change.
- **Baseline:** docs-only H035 commit `790c2a6` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus R.40--R.42:** those rows aliased registers across
  unrelated operation families and lost their flop savings to D-input/fanout
  entanglement. H036 collapses two branches of one waveform calculation under
  the exact selector already registered beside them, with one downstream
  consumer and no cross-family payload.
- **Change:** select `t_h15` or zero-extended `t_h7` before one 11-bit pipeline
  register, then feed that register directly to the non-organ reconstruction.
- **Result:** a reset-constrained three-step Yosys SAT miter proves the complete
  registered consumer. Exhaustive permanent coverage proves all 4,194,304 raw
  quotient/mode tuples. The isolated cone changes from 27 LUT4s / 30 flops to
  22 LUT4s / 20 flops. Full hardware forms and full/PREVIEW lint pass. Whole-
  PSG mapping then fails the deterministic area gate, so the complete behavior
  battery is not run and the production/permanent-proof edits are reverted.
  Strict OpenSpec and diff checks pass after the revert.
- **Physical result:** canonical mapping changes H031's 6,545 LUT4 / 1,455
  carry / 1,476 FF / 14 EBR to 6,599 LUT4 / 1,455 carry / 1,483 FF / 14 EBR.
  Seed-1 router2 remains at two overused wires through iteration 14,424 and is
  stopped after the mapped gate has already failed; no placement or timing
  result is claimed.
- **Decision:** rejected and reverted. Keep the parallel mode-specific
  registers; preselection makes the global D-input/fanout partition worse.
- **Repeat only if:** retry only after tilt quotient widths,
  pipeline placement, mode selection, or mapper flop packing changes.

## Hypothesis H037

- **ID:** H037.
- **Hypothesis:** in `/7` mode, `t_h7 = t_pre >> 9` is at most 335 and therefore
  needs nine bits. Its tenth bit is reachable only in `/15` mode, when the
  parallel `t_h15_r` branch is selected instead. Narrowing only `t_h7` and
  `t_h7_r` should remove one flop without H036's pre-register mux/fanout cost.
- **Scope:** exhaustive source-domain proof and isolated synthesis of the
  complete registered quotient consumer. Production `rtl/psg_wave.sv`, a
  permanent hardware-forms bound, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  quotient value in its live mode, divisor, reciprocal EBR, pipeline edge,
  waveform result, schedule, R.84 executor, or tolerance change.
- **Baseline:** docs-only H036 commit `b131219` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H014 and H036:** H014's globally unreachable
  detune-correction bit was already pruned by Yosys. H037's bit is reachable in
  the shared combinational source but dead only under the exact registered
  `/7` selector, so the current ten-bit flop remains. Unlike H036, this keeps
  both mode-specific registers and introduces no new D-input mux.
- **Change:** narrow `t_h7` and `t_h7_r` from ten to nine bits, zero-extending
  by two bits at the existing post-register selector.
- **Result:** a reset-constrained three-step Yosys SAT miter proves the complete
  upstream arithmetic and registered consumer for every 16-bit `tramp` and
  both modes. The full input domain also bounds `/7` mode at 383, while the
  true waveform domain peaks at 335. Both complete consumers map identically
  to 78 LUT4s, 45 carries, and 12 flops, so no production/permanent-proof edit
  and no whole-PSG or behavior gate is warranted.
- **Decision:** rejected before production because Yosys already removes the
  conditionally dead stored bit. Keep the current width, which mirrors the
  common `t_pre` slice directly.
- **Repeat only if:** retry only after the `/7` numerator bound,
  mode correlation, pipeline placement, or mapper flop packing changes.

## Hypothesis H038

- **ID:** H038.
- **Hypothesis:** boosted oscillator gain is
  `floor(3*floor(5*a/4)/2)`. It equals `floor(15*a/8)` except residues 3, 6,
  and 7 are one lower; equivalently, `2*a - floor(a/8) - inc(a[2:0])`, where
  `inc` is 0, 1, or 2. This may replace two 13-bit adders with one 13-bit
  subtract and one narrow correction while documenting the nested rounding.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered gain consumer. Production `rtl/psg_walk.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H031 battery are
  conditional on a deterministic isolated mapped improvement. No amplitude,
  detune mode, wavetable selection, multiply request, state, schedule, R.84
  executor, or tolerance change.
- **Baseline:** docs-only H037 commit `8971069` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H017:** H017 shared live/old gain arithmetic across
  different downstream contexts and regressed globally. H038 changes only the
  internal arithmetic shape of the existing live boosted-gain consumer,
  retires its intermediate, and adds no context selector or shared lifetime.
- **Change:** replace the boosted branch's two rounded additions with
  `2*a - (a>>3) - inc`, where the two-bit increment is one for residues
  1/2/4/5, two for 3/6/7, and zero for residue 0.
- **Result:** Yosys equivalence proves all 13 registered result bits over the
  full input domain. The complete registered consumer changes from 26 LUT4s /
  24 carries / 13 flops to 54 LUT4s / 24 carries / 13 flops, so no production
  or permanent-proof file changes and no whole-PSG or behavior gate is
  warranted.
- **Decision:** rejected before production. Keep the nested shift-add form;
  the exact residue correction more than doubles its LUT cost.
- **Repeat only if:** retry only after gain ladder semantics,
  amplitude width, boost predicate, or mapper subtract lowering changes.

## Hypothesis H039

- **ID:** H039.
- **Hypothesis:** `rec_base(n) = 256 + 64*n + 4*n`, and every term is divisible
  by four. Factoring that alignment gives `(64 + 16*n + n) << 2`, so one
  11-bit adder can replace the visible 13-bit address additions while making
  the 68-byte record stride explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered base transform. Production `rtl/psg_common.svh`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  record number, layout, call placement, selector, address schedule, memory,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** docs-only H038 commit `04c9b76` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H032:** H032 moved the channel/instrument selector
  across two `rec_base()` calls and regressed globally. H039 leaves those calls
  and the selector untouched; it only factors the common low zeros within each
  pure transform, reducing the arithmetic width before measuring one complete
  registered transform.
- **Change:** compute the aligned word address as `64 + 16*n + n` in 11 bits,
  then append two zero address bits; retain every call, selector, offset, and
  consumer. Add all 64 record numbers to the permanent hardware-forms proof.
- **Result:** Yosys equivalence proves all 13 registered address bits. The
  permanent proof checks all 64 record numbers. The isolated registered
  transform changes from six LUT4s / six carries / 12 flops to six LUT4s / six
  carries / 11 flops. Full hardware forms and full/PREVIEW lint passed.
  `make test-psg`, including 93 analysis tests, and the 59/59 exact frozen-
  render regression passed. Correctly parameterized `/4`, `/5`, and `/6`
  budget runs passed at 572/1,275 and 5,757/7,654, 572/1,020 and 4,737/6,123,
  and 524/850 and 4,008/5,103 sample/tick clocks, with zero lost writes or late
  flips. `make test-clocks` passed. All eight Celeste preview checks at 1,275
  and 159 clocks/sample passed with 36/38 voiced windows, or 95%, for masks
  7/1/2/4. Synthetic and reconstructed-Celeste recovery passed with no
  coalesced, delayed, or dropped samples. Exact hardware and PREVIEW SFX-10
  renders were active and `click-v1` found zero clicks. The five-frame Celeste
  smoke had 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068
  distinct levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,540 LUT4 / 1,456
  carry / 1,476 FF / 14 EBR / 7,284 LCs. Routed clocks change from 150.53 and
  31.35 MHz to 142.57 and 29.18 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The five-LUT4 reduction is deterministic; the added
  carry is explicit, and the three-LC improvement is below placement
  sensitivity and is not overclaimed.
- **Decision:** accepted. It exposes the address alignment and record stride,
  improves a deterministic mapped resource, does not regress placement,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative aligned record-base form may be retried
  only after record stride/base, record-number width, call contexts, or mapper
  aligned-add lowering changes.

## Hypothesis H040

- **ID:** H040.
- **Hypothesis:** the organ half-cycle ramp ignores `wx[15]` and truncates the
  16-bit negation of `{wx[14], wx[13:0]}` to 15 bits. The exact fold is the
  15-bit sum `{1'b0, wx[13:0] ^ {14{wx[14]}}} + wx[14]`; making the 14-bit
  conditional complement and carry-in explicit may prevent a wider subtract
  while exposing the triangular-ramp contract.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered organ reciprocal-address inputs. Production
  `rtl/psg_wave.sv`, permanent hardware-forms coverage, whole-PSG mapping, and
  the complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No waveform values, reciprocal table, pipeline edge, schedule,
  state, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af`: 6,540 LUT4s, 1,456 carries,
  1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57 MHz fast and 29.18 MHz PSG.
- **Changed condition versus H011:** H011 replaced `16'hffff - wx` with its
  mapper-canonical bitwise complement. H040 instead removes an ignored source
  bit from a modulo-15-bit negation while preserving the carry-out required at
  the exact half-cycle boundary, and prices the complete registered organ
  consumer before production.
- **Change:** replace the truncated conditional 16-bit negation with the exact
  15-bit sum of a 14-bit conditional complement and the half-cycle bit; add
  permanent exhaustive coverage during the whole-design measurement.
- **Result:** Yosys equivalence proves all 55 internal and registered consumer
  bits. The isolated complete registered organ-address cone changes from 54
  LUT4s / 27 carries / 23 flops to 41 LUT4s / 28 carries / 23 flops. Full
  hardware forms and full/PREVIEW lint pass. Whole-PSG mapping then fails both
  deterministic mapped-resource and placement gates, so the complete fidelity
  battery is correctly skipped and both production and permanent-proof edits
  are reverted.
- **Physical result:** canonical seed-1 mapping changes H039's 6,540 LUT4 /
  1,456 carry / 1,476 FF / 14 EBR / 7,284 placed LCs to 6,553 LUT4 / 1,461
  carry / 1,476 FF / 14 EBR / 7,302 LCs. Routed clocks remain above constraint
  at 123.09 MHz fast and 31.13 MHz PSG, but the 13-LUT4, five-carry, and 18-LC
  regressions reject the candidate.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current truncated negation; the explicit exact fold is much smaller
  locally but globally worse in every area metric.
- **Repeat only if:** retry only after organ ramp width, reciprocal folding,
  pipeline consumers, or mapper negation lowering changes.

## Hypothesis H041

- **ID:** H041.
- **Hypothesis:** both music-control branches test `fade_len >= 8`, which is
  exactly `|fade_len[7:3]` for an unsigned byte. One named prefix predicate may
  remove relational lowering and duplicated decode while making the minimum
  non-immediate fade duration explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered fade-control consumer. Production `rtl/psg_seq.sv`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H039
  battery are conditional on a deterministic isolated mapped improvement. No
  fade semantics, accumulator arithmetic, music state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040 `e108538`:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H024/H030/H034:** those rows changed saturation or
  row-bound comparisons with arithmetic consumers. H041 is one shared Boolean
  eligibility predicate used by two mutually exclusive fade-control branches,
  and prices their complete registered outputs before production.
- **Change:** replace both relations with one named `|fade_len[7:3]` predicate.
  The scratch pair models every held register as a shared explicit prior-state
  input, then compares the unconditional next-state outputs.
- **Result:** Yosys proves all 42 next-state bits for arbitrary inputs and
  arbitrary prior state; exhaustive hardware-forms evaluation also proves the
  Boolean identity for all 256 unsigned-byte values. Isolated `synth_ice40`
  changes 15 LUT4 / four carry / 18 FF to 17 LUT4 / zero carry / 18 FF.
  Canonical whole-PSG mapping changes H039's 6,540 LUT4 / 1,456 carry / 1,476
  FF / 14 EBR / 7,284 placed LCs to 6,551 LUT4 / 1,451 carry / 1,476 FF / 14
  EBR / 7,293 LCs. Routed clocks pass at 133.69 MHz fast and 31.54 MHz PSG.
- **Decision:** rejected and reverted after the whole-design physical gate.
  The five-carry saving does not offset 11 added LUT4s and nine placed LCs, so
  no full fidelity battery was run and no production or permanent-proof edit
  remains.
- **Repeat only if:** if rejected, retry only after fade-length semantics,
  register width, control consumers, or mapper constant-bound lowering changes.

## Hypothesis H042

- **ID:** H042.
- **Hypothesis:** the triangle detune-1 correction predicate
  `r[1:0] != 0 && r[7:6] >= r[1:0]` is a complete four-input truth table. Its
  exact nested Boolean form may remove the two-bit relational lowering while
  preserving the existing `floor(193*r/256)` arithmetic.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered eight-bit residue consumer. Production
  `rtl/psg_wave.sv`, permanent `dq` forms coverage, whole-PSG mapping, and the
  complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No coefficient, quotient split, waveform value, pipeline edge,
  schedule, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040/H041:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H002:** H002 replaced the full phaser
  `ceil(3*r/128)` remainder arithmetic with four seven-bit intervals. H042
  changes only an existing one-bit correction inside the separate triangle
  `floor(193*r/256)` remainder, over two independent two-bit fields.
- **Change:** replace the gated two-bit relation with the exact nested Boolean
  truth table for residue values zero, one, two, and three.
- **Result:** exhaustive enumeration proves both the correction bit and the
  complete `floor(193*r/256)` split for all 256 residues; Yosys proves all ten
  exposed correction/result bits. Isolated `synth_ice40` changes 22 LUT4 / six
  carry / eight FF to 21 LUT4 / six carry / eight FF. Canonical whole-PSG
  mapping changes H039's 6,540 LUT4 / 1,456 carry / 1,476 FF / 14 EBR / 7,284
  placed LCs to 6,564 LUT4 / 1,460 carry / 1,476 FF / 14 EBR / 7,320 LCs.
  Routed clocks pass narrowly at 112.82 MHz fast and 29.04 MHz PSG.
- **Decision:** rejected and reverted after the whole-design physical gate.
  The one-LUT4 isolated saving becomes a 24-LUT4, four-carry, and 36-LC global
  regression, so no full fidelity battery was run and no production or
  permanent-proof edit remains.
- **Repeat only if:** if rejected, retry only after the triangle coefficient,
  residue split, correction consumer, or mapper small-comparison lowering
  changes.

## Hypothesis H043

- **ID:** H043.
- **Hypothesis:** EA5 classifies the foreground length as nonzero and equal to
  one in its transition, then repeats the same classification in the memory
  write enable. For an active six-bit length, `|length[5:1]` exactly means the
  row may advance; named active/advance predicates may share the two consumers
  and simplify the stop/advance contract.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered EA5 transition/write consumer. Production
  `rtl/psg_seq.sv`, permanent `seq` forms coverage, whole-PSG mapping, and the
  complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No length, row, release, stop, state-memory value/address,
  schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040--H042:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H031/H041:** H031 time-shared two arithmetic
  comparisons in mutually exclusive states, while H041 replaced a fade
  threshold spelling. H043 factors one exact zero/one classification already
  consumed twice in the same EA5 state, including its memory write enable.
- **Change:** scratch-only named active and advance predicates; no production
  file changed.
- **Result:** exhaustive enumeration proves active, stop, advance, and write-
  enable behavior for all 4,096 bank/length/row tuples; Yosys proves all nine
  exposed result bits. Isolated `synth_ice40` maps both complete registered
  consumers identically at 13 LUT4 / four carry / nine FF.
- **Decision:** rejected before production RTL because Yosys already performs
  the intended zero/one classification sharing; the candidate only changes
  source spelling.
- **Repeat only if:** if rejected, retry only after foreground-length semantics,
  EA5 transition/write consumers, row terminal value, or mapper equality
  sharing changes.

## Hypothesis H044

- **ID:** H044.
- **Hypothesis:** each persisted full-mode crossfade counter is initialized to
  zero and updated only by restart-to-zero or increment while not 64, so its
  live domain is exactly 0..64. Within that domain, bit six is the terminal
  predicate and may replace every repeated seven-bit equality/non-equality
  decode in blend selection, multiplier issue, and counter update.
- **Scope:** inductive/exhaustive scratch proof and isolated synthesis of the
  complete registered counter/terminal consumer. Production `rtl/psg_walk.sv`,
  permanent `blend` forms coverage, whole-PSG mapping, and the complete H039
  battery are conditional on a deterministic isolated mapped improvement. No
  blend value, duration, multiplier operand, oscillator record, schedule,
  memory layout, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040--H043:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H008/H041:** those rows rewrote unconstrained
  equality/range inputs and Yosys could retain or reconstruct their full
  decodes. H044 uses a persistent-state invariant to remove six provably dead
  counter states from all terminal consumers, with the initialized memory and
  update recurrence included in the proof.
- **Change:** add `blend_done = bl_cnt[6]` and use it at all five full-mode
  terminal consumers: final blend selection, product issue, counter update,
  early-consume assertion, and busy assertion. Add the initialized/restart/
  saturating recurrence proof to the permanent hardware forms.
- **Result:** exhaustive fixed-point enumeration reaches exactly 0..64 and
  proves bit six iff terminal; constrained Yosys SAT proves the complete
  registered consumer equivalent. Isolated `synth_ice40` changes 28 to 25
  LUT4s with five carries and 26 flops unchanged. Permanent hardware forms,
  full and PREVIEW lint, `make test-psg`, and all 59 frozen renders pass
  byte-exactly. Correctly parameterized `/4`, `/5`, and `/6` regressions pass
  at 572/1,275, 572/1,020, and 524/850 sample clocks and 5,757/7,654,
  4,737/6,123, and 4,008/5,103 tick clocks. All eight preview checks at
  28,125,000 and 3,506,580 Hz pass at 95% for masks 7/1/2/4; synthetic and
  Celeste recovery pass. Exact hardware/PREVIEW SFX-10 renders report zero
  `click-v1` clicks and are byte-identical to H039. The five-frame Celeste
  smoke reports 2,179/3,668 active samples, range -22,013..9,151, and 1,068
  distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes 6,540 LUT4 / 1,456
  carry / 1,476 FF / 14 EBR / 7,284 placed LCs to 6,531 LUT4 / 1,459 carry /
  1,476 FF / 14 EBR / 7,280 placed LCs. Routed clocks change from 142.57 and
  29.18 MHz to 148.77 and 30.25 MHz. The nine-LUT4 reduction is deterministic;
  the four-LC improvement is below placement sensitivity and is not
  overclaimed.
- **Decision:** accepted. It makes the bounded counter contract explicit,
  improves a deterministic mapped resource, does not regress placed LCs,
  preserves every fidelity/timing gate, and retains 14 EBRs.
- **Cross-lineage adjudication:** H044 is accepted only on its H039-derived
  lineage and is not a composing optimization claim. Applying the same RTL and
  permanent proof to clean D004 commit `34340b7` changes 6,519 to 6,546 LUT4s,
  keeps 1,441 carries and 1,460 flops, changes unpackable flops 504 to 503 and
  the LC floor 7,023 to 7,049, and routes at 7,298 rather than 7,273 LCs.
  Timing still passes at 138.97/30.70 MHz. Reverting and forcing a clean build
  exactly restores D004 at 6,519 LUT4 / 1,441 carry / 1,460 FF / 504
  unpackable / 14 EBR / floor 7,023 / 7,273 LCs / 135.46/31.52 MHz. No H044
  residue or commit remains on that lineage.
- **Repeat only if:** if rejected, retry only after crossfade duration, counter
  persistence/update, blend consumers, or mapper terminal-decode lowering
  changes.

## Hypothesis H045

- **ID:** H045.
- **Hypothesis:** `fdec()` emits three base-3 digits and therefore each filter
  mode is always 0, 1, or 2. The zero-initialized record store is written only
  from those digits or their maximum, so the invariant persists through
  `w_bf_det/rev/damp`. For trits `a,b`, `max(a,b)` is exactly `{a[1]|b[1],
  !(a[1]|b[1]) && (a[0]|b[0])}`. Using one named function for the three
  instrument/base filter merges should remove relational compare/mux lowering
  and make the base-3 contract explicit.
- **Scope:** exhaustive trit/source-closure proof and isolated synthesis of all
  three registered max consumers. Production `rtl/psg_seq.sv`, permanent
  hardware forms, whole-PSG mapping, and the complete H044 battery are
  conditional on a deterministic isolated mapped improvement. No filter value,
  instrument precedence, publication format, state address, schedule, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus H042:** H042 replaced one already compact gated
  two-bit relation and its isolated one-LUT4 win regressed globally. H045
  removes three complete relation-plus-result-mux consumers under a persistent,
  source-closed trit invariant, rather than respelling one predicate.
- **Change:** scratch-only OR-derived trit maximum and complete three-consumer
  registered synthesis probe; no production or permanent-proof file changed.
- **Result:** exhaustive enumeration proves all 32 `fdec()` outputs contain
  only digits 0..2, proves the OR-derived maximum equal to `max(a,b)` for all
  nine input pairs, and proves closure of the result. Constrained Yosys SAT
  proves all six registered result bits over three independent valid-trit
  pairs. Isolated `synth_ice40` maps both the relational and OR-derived forms
  identically at six LUT4s / six flops / zero carries.
- **Decision:** rejected before production because the source identity has no
  isolated physical result. Keep the relational maxima; no whole-PSG or
  behavior gate is warranted.
- **Repeat only if:** if rejected, retry only after filter-code radix/domain,
  base/instrument merge semantics, record-store provenance, or mapper small-
  relation lowering changes.

## Hypothesis H046

- **ID:** H046.
- **Hypothesis:** the three published effect-class flags redundantly decode
  raw current and instrument effects after `e_fx` has already applied their
  exact precedence. Exhaustively, the noise flag is `e_fx == 3`, the buzz
  flag is `(!w_ins_on || !w_ins_wt) && e_fx in {0,4,5}`, and the damp flag is
  `ins_use && fx_dfl && e_fx in {0,4,5}`. Naming the shared normalized class
  should remove duplicated raw-effect comparisons while simplifying the
  publication contract.
- **Scope:** all 256 combinations of instrument-on, wavetable, current effect,
  and instrument effect; constrained formal equivalence; isolated registered
  synthesis of the complete three-flag consumer; then, only after an isolated
  deterministic win, production `rtl/psg_seq.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H044 battery. No precedence, sounding
  word layout, effect arithmetic, state, schedule, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus H042/H045:** those rows respelled already-compact
  bounded relations. H046 removes multiple raw-effect decodes by reusing the
  already-live precedence result consumed throughout the sequencer.
- **Change:** replace the repeated raw current/instrument effect decodes with
  one shared `e_filter` predicate and the normalized `e_fx` identities; add
  the complete exhaustive identity to the permanent hardware forms.
- **Result:** exhaustive Python enumeration and unconstrained Yosys SAT prove
  all six exposed normalized-effect/result bits for all 256 input tuples.
  Isolated registered `synth_ice40` improves from 14 to 11 LUT4s with six
  flops and zero carries unchanged. Whole-PSG mapping instead changes 6,531 to
  6,558 LUT4s, keeps 1,459 carries and 1,476 flops, reduces unpackable flops
  521 to 518, raises the LC floor 7,052 to 7,076, and routes at 7,308 rather
  than 7,280 LCs. Both clocks pass at 121.60/31.45 MHz. Reverting and forcing
  a clean synthesis exactly restores H044 at 6,531 LUT4 / 1,459 carry / 1,476
  FF / 521 unpackable / 14 EBR / floor 7,052 / 7,280 LCs / 148.77/30.25 MHz.
- **Decision:** rejected and reverted because the global decode/fanout remap
  overwhelms the isolated saving and regresses both deterministic LUT4s and
  placed LCs. No fidelity gate is warranted after the physical failure.
- **Repeat only if:** if rejected, retry only after current/instrument effect
  precedence, wavetable gating, publication bit semantics, or mapper sharing
  across the `e_fx` cone changes.

## Hypothesis H047

- **ID:** H047.
- **Hypothesis:** waveform output scaling currently selects among three
  constant `tzs(z_prim, k)` networks plus an unshifted arm. The exact shift is
  `3/2` for triangle secondary/primary, `1` for every other secondary, and
  `0` otherwise. Selecting this two-bit `k` first and invoking `tzs` once,
  including its exact `k=0` identity, should share the bias/add/shift path and
  simplify the output contract.
- **Scope:** every signed 18-bit `z_prim` value and all four triangle/secondary
  contexts; unconstrained formal equivalence; isolated registered synthesis of
  the complete output consumer; then, only after an isolated deterministic
  win, production `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG
  mapping, and the complete H044 battery. No waveform value, reciprocal,
  detune, pipeline register, schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus the closed reciprocal/detune families:** H047
  leaves every waveform and increment expression intact and consolidates only
  the mutually exclusive final truncation-to-zero consumer after `z_prim`.
- **Change:** select `z_shift` from the triangle/secondary context and invoke
  `tzs(z_prim, z_shift)` once, including the exact zero-shift identity. Add the
  complete signed-18/context identity to the permanent hardware forms.
- **Result:** exhaustive comparison passes all 1,048,576 signed-18/context
  tuples, and unconstrained Yosys SAT proves the complete combinational result.
  Isolated registered synthesis changes 100 to 56 LUT4s and 51 to 18 carries,
  with 18 flops unchanged. Permanent hardware forms, full and PREVIEW lint,
  `make test-psg`, and all 59 frozen renders pass byte-exactly. Correctly
  parameterized `/4`, `/5`, and `/6` regressions pass at 572/1,275,
  572/1,020, and 524/850 sample clocks and 5,757/7,654, 4,737/6,123, and
  4,008/5,103 tick clocks. All eight preview checks at 28,125,000 and
  3,506,580 Hz pass 36/38 voiced windows for masks 7/1/2/4; synthetic and
  Celeste recovery pass. Exact hardware/PREVIEW SFX-10 renders report zero
  `click-v1` clicks and are byte-identical to H044. The five-frame Celeste
  smoke reports 2,179/3,668 active samples, range -22,013..9,151, and 1,068
  distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes H044's 6,531 LUT4 /
  1,459 carry / 1,476 FF / 14 EBR / 521 unpackable / 7,052-cell floor / 7,280
  routed LCs to 6,503 LUT4 / 1,426 carry / 1,476 FF / 14 EBR / 522 unpackable /
  7,025-cell floor / 7,251 routed LCs. Routed clocks change from 148.77 and
  30.25 MHz to 150.53 and 32.42 MHz. Independent direct-D004 adjudication is
  accepted as `a5052c1` atop `34340b7`: 6,519 to 6,517 LUT4s, 1,441 to 1,404
  carries, 1,460 flops unchanged, 504 to 503 unpackable flops, 7,023 to 7,020
  floor cells, and 7,273 to 7,259 routed LCs at 128.50/32.57 MHz. The D004
  placement delta is non-robust; the shared exact network and 37-carry saving
  are durable.
- **Decision:** accepted. It exposes one exact output-scale contract, improves
  deterministic mapped resources and the physical floor, reduces placed LCs,
  preserves every fidelity/timing gate, and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after waveform output-scale
  semantics, `tzs` lowering, `z_prim` width, or the final pipeline boundary
  changes.

## Hypothesis H048

- **ID:** H048.
- **Hypothesis:** the three wave-issue strobes are mutually exclusive schedule
  actions and describe four contexts: live primary, live secondary, old
  primary, and old secondary. Factoring them into independent `old` and
  `secondary` axes should replace the priority-shaped source selector with two
  orthogonal muxes before the unchanged first waveform-pipeline register.
- **Scope:** source-exact one-hot schedule audit; constrained formal equivalence
  for arbitrary phase, wave, alternate, and issue inputs; isolated registered
  synthesis of the complete first-stage selector; then, only after an isolated
  deterministic win, production `rtl/psg_wave.sv`, permanent proof, whole-PSG
  mapping, and the complete H047 battery. No waveform value, output scaling,
  reciprocal, pipeline register, action timing, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H047 commit `c1b4862`: 6,503 LUT4s, 1,426 carries,
  1,476 flops, 522 unpackable flops, 14 EBRs, 7,025-cell floor, seed-1 7,251
  LCs; 150.53 MHz fast and 32.42 MHz PSG.
- **Changed condition versus H017/R.83:** H017 shared post-multiply consumers
  across distant schedule destinations and regressed globally; R.83 replaced
  the complete waveform pipeline with a sequential service. H048 changes no
  arithmetic or destination: it only exposes the two Boolean axes already
  encoded by the four legal inputs to one existing register boundary.
- **Change:** scratch-only factorization of each issue context into independent
  old/live and primary/secondary axes; no production or permanent proof file
  changed.
- **Result:** the source-derived schedule proof passes all four legal hardware
  issue contexts, all 128 generated control words retain one-hot W1/W2/W3
  actions, and both PREVIEW contexts preserve the selector axes. Constrained
  Yosys SAT proves both combinational selectors equivalent for arbitrary phase,
  wave, alternate, and valid issue inputs. Isolated registered `synth_ice40`
  maps the current selector to 38 LUT4s, zero carries, and 21 flops, while the
  factored selector needs 54 LUT4s, zero carries, and 21 flops.
- **Decision:** rejected before production RTL. The exact factorization adds 16
  LUT4s in the complete registered cone, so it fails the deterministic isolated
  area gate; no whole-PSG or fidelity run is warranted.
- **Repeat only if:** if rejected, retry only after issue-strobe exclusivity,
  waveform-context ownership, first-stage register inputs, or mapper priority-
  mux lowering changes.

## Hypothesis H049

- **ID:** H049.
- **Hypothesis:** the square/pulse thresholds have high-five-bit values 16, 19,
  22, and 25. Their exact less-than relations are small nested prefix formulas;
  selecting those formulas directly should remove the comparator carry chain
  while preserving every phase and wave/alternate context.
- **Scope:** exhaustive and formal proof over all phase, wave, and alternate
  inputs; isolated registered synthesis of the complete signed constant-output
  consumer; then, only after a deterministic isolated win,
  `rtl/psg_wave.sv`, a permanent proof, whole-PSG mapping, and the complete
  H047 battery. No threshold, waveform amplitude, pipeline register, schedule,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H047 commit `c1b4862` plus H048 decision `dc28e97`:
  6,503 LUT4s, 1,426 carries, 1,476 flops, 522 unpackable flops, 14 EBRs,
  7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz fast and 32.42 MHz PSG.
- **Changed condition versus H004:** H004 retained a relational comparison and
  only shortened its operands to the aligned high five bits; Yosys already made
  that reduction. H049 removes the relational operator and tests the complete
  exact truth table selected by wave and alternate mode.
- **Change:** replace the selected relational threshold with four exact nested
  prefix formulas; add the exhaustive permanent proof for measurement.
- **Result:** all 1,048,576 phase/wave/alternate tuples pass in both the scratch
  and permanent proof, and unconstrained Yosys SAT proves the complete signed
  constant output equivalent. Isolated registered synthesis changes five LUT4s,
  five carries, and two flops to seven LUT4s, zero carries, and two flops.
  Whole-PSG mapping changes H047's 6,503 LUT4 / 1,426 carry / 1,476 FF / 522
  unpackable / 14 EBR / 7,025-cell floor / 7,251 placed LCs to 6,529 LUT4 /
  1,418 carry / 1,476 FF / 520 unpackable / 14 EBR / 7,049-cell floor / 7,261
  placed LCs. Initial placed timing estimates pass at 149.37/32.78 MHz, but
  the route remained at two overused wires and was stopped after both mapped
  and placed area gates had already failed. Production RTL and the conditional
  permanent proof are reverted byte-for-byte.
- **Decision:** rejected after whole-PSG mapping and placement. Eight fewer
  carries do not offset 26 more LUT4s, 24 more floor cells, or ten more placed
  LCs; the second square/pulse-threshold variant closes this family.
- **Repeat only if:** if rejected, retry only after square/pulse thresholds,
  wave/alternate selection, comparator lowering, or the registered consumer
  changes.

## Hypothesis H050

- **ID:** H050.
- **Hypothesis:** the retained five-bit upload-page subtract is modulo
  `x - 17 == x + 15`: decrement the low nibble and toggle the high bit exactly
  when that nibble is nonzero. Spelling its five output bits directly should
  remove the remaining constant-adder carry chain while preserving the complete
  audio-RAM index.
- **Scope:** exhaustive and formal proof over every five-bit page and low-byte
  input; isolated registered synthesis of the complete 13-bit index consumer;
  then, only after a deterministic isolated win, `rtl/psg_aram.sv`, permanent
  proof, whole-PSG mapping, and the complete H047 battery. No upload window,
  write enable, address, memory, schedule, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H047 commit `c1b4862` plus decisions through H049 and
  D004 coordination `33be1c8`: 6,503 LUT4s, 1,426 carries, 1,476 flops, 522
  unpackable flops, 14 EBRs, 7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz
  fast and 32.42 MHz PSG.
- **Changed condition versus H005:** H005 accepted the page-local five-bit
  subtract and window decode, but left the narrowed constant adder intact.
  H050 keeps that exact contract and removes only the modulo transform's carry
  representation; the accepted window decoder is unchanged.
- **Change:** variant 1 spells all five modulo output bits exactly over every
  page. Variant 2 uses the unchanged write-valid domain to reduce the fifth bit
  to `!page[4] && |page[1:0]`; both retain the same lower-nibble decrement.
- **Result:** exhaustive comparison and Yosys SAT prove variant 1 over all 8,192
  page/low-byte inputs and variant 2 over all 4,608 valid upload addresses.
  Isolated registered synthesis changes the current five LUT4 / three carry /
  13-flop index to six LUT4 / zero carry / 13 flops for variant 1 and five
  LUT4 / zero carry / 13 flops for variant 2. Whole-PSG variant 1 maps 6,523
  LUT4 / 1,423 carry / 1,476 FF / 519 unpackable / 14 EBR / 7,042-cell floor
  and routes in 7,266 LCs at 141.16/31.03 MHz. Variant 2 maps 6,520 LUT4 /
  1,423 carry / 1,476 FF / 521 unpackable / 14 EBR / 7,041-cell floor and
  routes in 7,265 LCs at 115.75/31.59 MHz. Against H047, even the local-optimum
  variant adds 17 LUT4s, 16 floor cells, and 14 placed LCs while saving only
  three carries. Production RTL and the conditional permanent proof are
  reverted byte-for-byte.
- **Decision:** both variants are rejected after the whole-PSG physical gate.
  The valid-domain fifth bit recovers the isolated LUT cost but not the global
  mapping/placement regression, so the upload-page transform family closes.
- **Repeat only if:** if rejected, retry only after upload base/window, page
  width, mapper constant-adder lowering, or the registered index consumer
  changes.

## Hypothesis H051

- **ID:** H051.
- **Hypothesis:** the detune service needs exactly five active iterations. The
  maximal-LFSR segment `6 -> 5 -> 2 -> 4 -> 1` preserves those five states,
  keeps zero idle and one terminal, and replaces the binary decrement with one
  XOR plus a shift. It should remove the countdown carry chain without changing
  arithmetic or request timing.
- **Scope:** exhaustive event/state proof including held, start, terminal-chain,
  and reset transitions; sequential formal equivalence of all public service
  signals and product values; isolated synthesis of the complete service; then,
  only after a deterministic win, `rtl/psg_dqsvc.sv`, permanent proof,
  whole-PSG mapping, and the complete H047 battery. No coefficient, product,
  request, result, schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H047 commit `c1b4862` plus decisions through H050
  `abd4884`: 6,503 LUT4s, 1,426 carries, 1,476 flops, 522 unpackable flops,
  14 EBRs, 7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz fast and 32.42 MHz
  PSG.
- **Changed condition versus H006/R.68/R.69:** H006 changed only the loaded
  multiplier latency value and regressed locally. R.68/R.69 partially recoded
  global schedule actions. H051 keeps the detune service's five clocks and all
  external actions fixed; only its private six-state iteration register changes
  representation.
- **Change:** load state six and advance the exact maximal-LFSR segment
  `6 -> 5 -> 2 -> 4 -> 1`; retain zero as idle and one as terminal. Decode
  readiness from the high two bits and add the state identity to the permanent
  hardware forms.
- **Result:** exhaustive transition proof covers every legal idle, active,
  terminal-chain, held, and reset case, and constrained Yosys SAT proves the
  state bijection, public busy/done/ready signals, next product state, and
  result recurrence. The complete detune service changes 120 LUT4 / 29 carry /
  28 FF to 120 LUT4 / 28 carry / 28 FF in isolation. `make test-psg-dq` passes
  524,288 arithmetic cases plus 57,344 exhaustive and chained transactions.
  Permanent hardware forms, full and PREVIEW lint, `make test-psg`, and all 59
  frozen renders pass byte-exactly. Correctly parameterized `/4`, `/5`, and
  `/6` regressions pass at 572/1,275, 572/1,020, and 524/850 sample clocks and
  5,757/7,654, 4,737/6,123, and 4,008/5,103 tick clocks, all with zero lost
  writes or late flips. All eight preview checks pass 36/38 voiced windows for
  masks 7/1/2/4 at both clocks; synthetic and Celeste recovery pass with no
  coalesced, delayed, or dropped samples. Exact hardware/PREVIEW SFX-10 renders
  are byte-identical to H047 and report zero `click-v1` clicks. The five-frame
  Celeste smoke again reports 2,179/3,668 active samples, range
  -22,013..9,151, and 1,068 distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes H047's 6,503 LUT4 /
  1,426 carry / 1,476 FF / 522 unpackable / 14 EBR / 7,025-cell floor / 7,251
  routed LCs to 6,506 LUT4 / 1,421 carry / 1,476 FF / 522 unpackable / 14 EBR /
  7,028-cell floor / 7,247 routed LCs. Routed clocks are 146.82 and 31.75 MHz
  against 112.50 and 18.75 MHz constraints. The five-carry reduction is
  deterministic; the four-LC improvement is below placement sensitivity and
  is not overclaimed.
- **Decision:** accepted. The private state contract is exact and simpler,
  removes mapped carries, preserves all behavioral and timing gates, and does
  not regress seed-1 placement despite the explicit three-LUT/floor trade.
- **Repeat only if:** if rejected, retry only after detune-service latency,
  terminal chaining, iteration arithmetic, or mapper sequential lowering
  changes.

## Hypothesis H052

- **ID:** H052.
- **Hypothesis:** full-mode fold finality need not be a separate `ffin` bit.
  The existing three-bit `fsel` has unused state five, whose operand-mux
  behavior is already the same as root state three. Encoding only the final
  root reduction as state five should preserve every reduction operand,
  destination, microstep, and `dry_valid` clock while removing one control
  flop and its update cone.
- **Scope:** exhaustive legal fold-controller transition proof, constrained
  formal equivalence of externally visible fold actions, isolated synthesis of
  the complete selector/controller consumer, then, only after a deterministic
  win, `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping, and the
  complete H051 battery. No arithmetic, visit/schedule cadence, `fmc`, `fpend`,
  EBR, interface, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be`: 6,506 LUT4s, 1,421 carries,
  1,476 flops, 522 unpackable flops, 14 EBRs, 7,028-cell floor, seed-1 7,247
  LCs; 146.82 MHz fast and 31.75 MHz PSG.
- **Changed condition versus R.68/R.69 and H044:** R.68/R.69 changed global
  schedule encodings, while H044 changed a persistent counter-terminal
  predicate. H052 leaves the visit schedule and fold microstep encoding fixed;
  it uses one otherwise-unused value of the existing private operand selector
  solely during the already-required final root node.
- **Change:** remove `ffin`; after selector state four, use selector state five
  for the final root reduction, retain state three for the non-final root, and
  pulse `dry_valid` exactly when state five completes.
- **Result:** exhaustive exploration proves all 323 legal controller
  transitions across 42 terminal paths, including every arbitrary sign branch,
  operand source, destination, pending-node transition, and publication event.
  Constrained Yosys SAT proves the legal-state relation, all operand/destination
  selections, next control state, and `dry_valid` event. Isolated complete-
  controller synthesis changes 120 LUT4 / 67 FF to 123 LUT4 / 67 FF, with no
  carries in either form. The removed `ffin` flop is replaced by an additional
  mapper-created `fsel` state bit: mapped selector flops grow from four to five.
- **Decision:** rejected before production RTL. The exact encoding is locally
  larger and removes no deterministic mapped resource, so the hypothesis gate
  forbids a whole-PSG edit or physical claim. Production RTL and permanent
  hardware forms remain unchanged.
- **Repeat only if:** if rejected, retry only after the fold selector width,
  reduction topology, terminal publication boundary, or mapper sequential
  encoding changes.

## Hypothesis H053

- **ID:** H053.
- **Hypothesis:** the full-mode `dry_valid` pulse is the one clock immediately
  after final fold completion and can be represented by unused `fmc=10`.
  Decoding that existing four-bit state while excluding it from `fold_busy`
  should preserve the external pulse and busy waveforms exactly, retain
  `ffin` and every arithmetic microstep, and remove the dedicated publication
  flop without adding state width.
- **Scope:** exhaustive full-mode fold/publication transition proof,
  constrained formal equivalence of externally visible fold busy/valid
  actions, isolated synthesis of the complete controller consumer, then, only
  after a deterministic win, `rtl/psg_walk.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H051 battery. PREVIEW retains its current
  pulse register. No arithmetic, visit cadence, selector, pending count, EBR,
  interface, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be` plus docs-only H052 `c432079`:
  6,506 LUT4s, 1,421 carries, 1,476 flops, 522 unpackable flops, 14 EBRs,
  7,028-cell floor, seed-1 7,247 LCs; 146.82 MHz fast and 31.75 MHz PSG.
- **Changed condition versus H052 and R.68/R.69:** H052 expanded the operand
  selector encoding and the mapper added a replacement selector state bit.
  H053 leaves that selector and all global schedule actions untouched; it uses
  an unused value of the already-four-bit private arithmetic counter solely to
  carry an existing registered output pulse.
- **Change:** on final fold completion set `fmc` to ten rather than zero; in
  full mode decode `dry_valid` from state ten, exclude state ten from
  `fold_busy`, and let the next controller edge return to idle zero. Keep the
  existing registered PREVIEW pulse unchanged.
- **Result:** exhaustive exploration proves exact `fold_busy` and `dry_valid`
  waveforms across 350 legal controller transitions and 42 terminal paths.
  Constrained Yosys SAT proves the state relation and next-state/public-action
  equivalence. The complete isolated controller changes 120 LUT4 / 67 FF to
  125 LUT4 / 66 FF. Canonical whole-PSG mapping changes H051's 6,506 LUT4 /
  1,421 carry / 1,476 FF / 522 unpackable / 14 EBR / 7,028-cell floor / 7,247
  routed LCs to 6,528 LUT4 / 1,422 carry / 1,475 FF / 519 unpackable / 14 EBR /
  7,047-cell floor / 7,266 routed LCs. Routed clocks pass at 147.89 and 31.01
  MHz against 112.50 and 18.75 MHz constraints.
- **Decision:** rejected and reverted. The one-flop saving costs 22 LUT4s, one
  carry, and 19 deterministic floor cells, and seed-1 placement also regresses
  by 19 LCs. Production RTL and the conditional permanent proof are restored
  byte-for-byte; the full fidelity battery is correctly skipped.
- **Repeat only if:** if rejected, retry only after the fold counter width,
  publication latency, busy contract, preview/full elaboration boundary, or
  mapper sequential encoding changes.

## Hypothesis H054

- **ID:** H054.
- **Hypothesis:** the primary triangle phase before the existing multiply by
  three is exactly a signed 15-bit centered lower phase, conditionally negated
  by the top phase bit. With `c = signed({~wx[14],wx[13:0]})`, the current
  expression equals `wx[15] ? -c : c` for all 65,536 phases. Keeping `c` at
  15 bits and only the conditional result at 16 bits should replace the
  current 17-bit complement/subtract/bias construction with a narrower exact
  fold while making the triangle symmetry explicit.
- **Scope:** exhaustive proof over all 65,536 phases, unconstrained Yosys SAT,
  isolated synthesis of the registered primary triangle consumer, then, only
  after a deterministic win, `rtl/psg_wave.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H051 battery. No organ fold, triangle
  detune residue, secondary presentation, output scaling, pipeline timing,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be` plus docs-only H052/H053 through
  `023bedd`: 6,506 LUT4s, 1,421 carries, 1,476 flops, 522 unpackable flops,
  14 EBRs, 7,028-cell floor, seed-1 7,247 LCs; 146.82 MHz fast and 31.75 MHz
  PSG. The isolated baseline is the complete registered triangle fold and its
  existing multiply-by-three consumer; whole-PSG mapping remains authoritative.
- **Changed condition versus H040, H042, and H047:** H040 changed the organ
  ramp, H042 changed the triangle detune-1 residue comparator, and H047 shared
  final output scaling. H054 changes only the primary triangle phase fold
  before its existing multiply by three; none of those earlier cones or their
  rejected spellings is retried.
- **Change:** build the 15-bit centered phase, sign-extend it to 16 bits,
  conditionally negate it from `wx[15]`, and retain the exact existing
  multiply-by-three and truncating `/4` consumers.
- **Result:** a scalar exhaustive proof covers all 65,536 phases and
  unconstrained Yosys SAT proves both the pre-scale value and multiply-by-three
  result exactly. Isolated synthesis of the complete registered primary
  triangle and `/4` consumers changes 60 LUT4 / 45 carry / 34 FF to 71 LUT4 /
  44 carry / 34 FF. Evidence is saved under `build/experiments/h054/`.
- **Decision:** rejected before production RTL. The one-carry reduction costs
  eleven LUT4s, so it fails the deterministic physical gate. Production RTL
  and permanent hardware forms remain unchanged; no whole-PSG or behavior
  claim is made.
- **Repeat only if:** if rejected, retry only after the primary triangle
  representation, pre-scale width, pipeline boundary, or mapper arithmetic
  lowering changes.

## Hypothesis H055

- **ID:** H055.
- **Hypothesis:** the pitched-noise multiplier yields an unsigned integer
  magnitude `m` and an eight-bit discarded fraction. Its signed rounded result
  is `m` for a positive random step and `-(m + fractional_nonzero)` for a
  negative step. This is exactly
  `(m ^ {18{negative}}) + (negative && !fractional_nonzero)`. Spelling the two
  branches as one conditional complement and carry-in may replace the current
  negative add/negate plus output mux while making truncation toward zero
  explicit.
- **Scope:** exhaustive proof over all 65,536 magnitudes, both fraction classes,
  and both signs; unconstrained Yosys SAT; isolated synthesis of the complete
  registered signed-noise consumer; then, only after a deterministic win,
  `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping on direct
  frontier `293a5f5`, and the complete acceptance battery. No multiplier,
  noise clamp, kick predicate, LFSR, schedule, state, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H051 commit `293a5f5`: 6,488 LUT4s, 1,403
  carries, 1,460 flops, 500 unpackable flops, 14 EBRs, 6,988-cell floor,
  seed-1 7,225 LCs; 147.12 MHz fast and 31.80 MHz PSG. The isolated baseline
  includes the magnitude/fraction slice, current positive/negative rounding,
  sign selection, and registered result; whole-PSG mapping remains
  authoritative.
- **Changed condition versus H011, H027, and H029:** H011 tested a constant
  tilted-saw reflection spelling, H027 replaced signed noise saturation
  comparators, and H029 rewrote the kick-enable inequality. H055 changes only
  post-multiply signed fractional rounding; none of those expressions or
  rejected mechanisms is retried.
- **Change:** test two exact spellings. The first inlines the unified
  conditional complement/carry at both independent live and old sign
  consumers. The second retains the shared positive/negative limbs but changes
  only the negative limb from `-(magnitude + fractional_nonzero)` to
  `~magnitude + !fractional_nonzero`.
- **Result:** scalar exhaustive comparison passes all 262,144 sign/magnitude/
  fraction-class cases, and unconstrained Yosys SAT proves both candidate
  forms. A misleading single-sign probe changes 38 LUT4 / 16 carry / 18 FF to
  36 / 16 / 18. The complete two-sign consumer exposes duplication: the
  inlined form changes 71 LUT4 / 16 carry / 36 FF to 71 / 32 / 36. The shared-
  limb form instead changes it to 70 / 16 / 34 and advances. On direct
  `293a5f5`, forced mapping changes 6,488 LUT4 / 1,403 carry / 1,460 FF / 500
  unpackable / floor 6,988 to 6,473 LUT4 / 1,404 carry / 1,460 FF / 501
  unpackable / floor 6,974. Seed-1 placement uses 7,213 LCs and passes placed
  timing at 141.62/32.15 MHz, but router2 remains fixed at two overused wires
  through 21,160 iterations and produces no routed design. Production RTL and
  permanent forms are restored; the direct continuation worktree is clean.
- **Decision:** rejected and reverted. The deterministic 15-LUT and 14-floor-
  cell reductions cannot be accepted without a canonical route, and the only
  other materially distinct form doubles carries in the complete consumer.
  The full behavior battery is correctly skipped because the physical gate
  failed first.
- **Repeat only if:** if rejected, retry only after the pitched-noise product
  slice, signed rounding contract, consumer pipeline boundary, or mapper
  arithmetic lowering changes.

## Hypothesis H056

- **ID:** H056.
- **Hypothesis:** the organ primary-output branch needs the registered top phase
  bit only when the alternate-secondary bypass is inactive. In that domain,
  the completed registered linear organ sample exactly satisfies
  `wx[15] == z_lin[15] ^ z_lin[14]` for all 65,536 phases. Reusing those two
  existing registered bits should remove `org_hi_r` and its update cone while
  making the surviving-state invariant explicit.
- **Scope:** exhaustive proof over every phase and both bypass classes;
  unconstrained Yosys SAT; isolated synthesis of the complete two-stage organ
  branch consumer; then, only after a deterministic win, `rtl/psg_wave.sv`,
  permanent hardware forms, whole-PSG mapping on direct frontier `293a5f5`,
  and the complete acceptance battery. No organ ramp arithmetic, reciprocal,
  waveform output scaling, phase selection, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H051 commit `293a5f5`: 6,488 LUT4s, 1,403
  carries, 1,460 flops, 500 unpackable flops, 14 EBRs, 6,988-cell floor,
  seed-1 7,225 LCs; 147.12 MHz fast and 31.80 MHz PSG. The isolated baseline
  includes linear-organ construction, the existing second-stage registers,
  bypass controls, div/output selection, and a registered consumer.
- **Changed condition versus H040 and R.40--R.42:** H040 rewrote the
  pre-register organ ramp and regressed globally. R.40--R.42 aliased unrelated
  cross-family register lifetimes and lost their savings to input mux/fanout.
  H056 changes no arithmetic and aliases no register: it proves the needed
  predicate is already encoded in a completed registered result.
- **Change:** committed as direct-frontier `ac15778`: remove `org_hi_r` and its
  stage-one update, derive the organ primary selector from
  `z_lin_r[15] ^ z_lin_r[14]`, and retain the exhaustive identity in
  `tools/psg_hw_forms.py`.
- **Result:** the 131,072-case phase/bypass proof and unconstrained Yosys SAT
  pass. The complete isolated branch changes 81 LUT4 / 15 carry / 38 FF to
  81 / 15 / 37. On direct `293a5f5`, forced HX8K mapping changes 6,488 LUT4 /
  1,403 carry / 1,460 FF / 500 unpackable / 14 EBR / floor 6,988 to 6,489 /
  1,403 / 1,459 / 498 / 14 / floor 6,987. Seed-1 routing changes 7,225 to
  7,224 LCs, explicitly below placement sensitivity; routed timing is
  116.37/32.96 MHz against 112.50/18.75 MHz constraints. Forced synthesis
  reproduces the result. Full hardware forms, full/PREVIEW lint,
  `make test-psg`, and all 59 frozen renders pass byte-exactly. Correctly
  parameterized `/4`, `/5`, and `/6` regressions pass at 572/1,275,
  572/1,020, and 524/850 sample clocks and 5,757/7,654, 4,737/6,123, and
  4,008/5,103 tick clocks, all with zero lost writes or late flips.
  `make test-clocks`, all eight preview checks, synthetic/Celeste recovery,
  byte-identical H051 hardware/PREVIEW SFX-10 renders with zero `click-v1`
  events, and the five-frame Celeste smoke pass. The smoke reports
  2,179/3,668 active samples, range -22,013..9,151, and 1,068 levels. Strict
  OpenSpec, `py_compile`, diff, staged-scope, and status audits pass.
- **Decision:** accepted. The source and state contract are simpler, one
  mapped flop and one deterministic floor cell retire, seed-1 placement does
  not regress, and the complete exact behavior and timing battery passes.
- **Repeat only if:** do not retry another spelling of this predicate unless
  the organ linear-output representation, alternate-secondary bypass,
  pipeline boundary, or mapper sequential lowering changes.

## Hypothesis H057

- **ID:** H057.
- **Hypothesis:** `tilt_hi_r` is redundant state. Its input is exactly
  `(wsel_r == 3'd1) && walt_r`, while `wsel_r2` and `walt_r2` capture those
  operands on the same edge. Reconstructing the next-stage predicate as
  `(wsel_r2 == 3'd1) && walt_r2` should preserve every cycle and remove one
  control flop plus its D-input logic.
- **Scope:** exhaustive two-state predicate proof, unconstrained sequential
  Yosys SAT, and isolated synthesis of the complete registered reciprocal
  recombination consumer. Production `rtl/psg_wave.sv`, permanent hardware
  forms, whole-PSG mapping on direct frontier `ac15778`, and the complete H056
  battery are conditional on a deterministic mapped or floor improvement. No
  quotient arithmetic, reciprocal contents, selector encoding, payload
  register, pipeline edge, waveform output, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H056 commit `ac15778`: 6,489 LUT4s, 1,403
  carries, 1,459 flops, 498 unpackable flops, 14 EBRs, 6,987-cell floor,
  seed-1 7,224 LCs; 116.37 MHz fast and 32.96 MHz PSG. The isolated baseline
  includes selector/control capture, the mode-specific quotient registers,
  reciprocal result, full recombination network, and a registered consumer.
- **Changed condition versus H036:** H036 inserted a mode mux before a wide
  quotient payload register and moved its D-input/fanout partition, producing
  a global LUT/flop regression despite an isolated saving. H057 neither moves
  nor aliases payload state: the exact control predicate is already encoded by
  two same-edge registers used throughout the existing downstream stage, so
  only a duplicated one-bit register is removed.
- **Change:** committed as direct-frontier `c9274fc`: remove `tilt_hi_r`, define
  `tilt_hi2 = (wsel_r2 == 3'd1) && walt_r2`, use it in the reciprocal-
  recombination consumers, and retain the state identity in
  `tools/psg_hw_forms.py`.
- **Result:** exhaustive control enumeration, an inductive SAT check, and a
  three-step arbitrary-defined-state sequential SAT miter pass. The isolated
  complete consumer changes 171 LUT4 / 25 carry / 88 FF to 182 / 25 / 87, so
  its local LUT trade is negative; the whole PSG shares the registered selector
  decodes and instead changes H056's 6,489 LUT4 / 1,403 carry / 1,459 FF / 498
  unpackable / 14 EBR / floor 6,987 to 6,466 / 1,403 / 1,458 / 502 / 14 /
  floor 6,968. Seed-1 routing changes 7,224 to 7,204 LCs, explicitly below
  placement sensitivity; timing is 116.37/30.42 MHz against 112.50/18.75 MHz
  constraints. Forced synthesis reproduces the JSON and ASC bit-for-bit. Full
  hardware forms, full/PREVIEW lint, `make test-psg`, and all 59 frozen renders
  pass byte-exactly. The exact `/4`, `/5`, and `/6` matrix passes at 572/1,275
  and 5,757/7,654 clocks, 572/1,020 and 4,737/6,123 clocks, and 524/850 and
  4,008/5,103 clocks, with zero lost writes, overruns, or late flips.
  `make test-clocks`, all eight preview checks, synthetic/Celeste recovery,
  exact same-tool H056 hardware/PREVIEW SFX-10 renders with zero `click-v1`
  events, and the five-frame Celeste smoke pass. The stored H056 preview WAV
  used Verilator 5.050 and is one sample offset; rebuilding H056 and H057 with
  the same 5.051 toolchain produces byte-identical WAVs. The smoke remains at
  2,179/3,668 active samples, range -22,013..9,151, and 1,068 levels. Strict
  OpenSpec, `py_compile`, diff, staged-scope, and post-commit audits pass.
- **Decision:** accepted. The state contract is simpler, 23 mapped LUT4s, one
  mapped flop, and 19 deterministic floor cells retire, placement does not
  regress, and the complete exact behavior and timing battery passes.
- **Repeat only if:** do not retry another spelling of this state identity unless
  selector/control pipeline placement, reciprocal-recombination consumers, or
  mapper sequential lowering changes materially.

## Hypothesis H058

- **ID:** H058.
- **Hypothesis:** `state_replay` is redundant in the composed PSG. It is the
  one-cycle delayed value of `prun`. During a walk it is covered by `prun`, and
  the edge that drops `prun` for the final voice unconditionally launches the
  reduction fold, making `fold_busy` true throughout the displaced state-RAM
  read's reissue interval in both full and PREVIEW elaborations. Therefore
  `state_replay -> (prun || fold_busy)` should hold on every reachable cycle;
  removing the replay flop, top-level OR term, and unused sequencer port should
  preserve the synchronous RAM value seen when the sequencer next advances.
- **Scope:** a source-exact transition proof for full and PREVIEW walk/fold
  control, a composed state-RAM/sequencer-read timing miter, and isolated/full
  iCE40 synthesis first. Production `rtl/psg_state_mem.sv`, `rtl/psg.sv`,
  `rtl/psg_seq.sv`, permanent hardware forms, module-structure specification,
  and the complete H057 battery are conditional on a deterministic mapped or
  floor improvement. No RAM contents, address/data/write mux, controller state,
  walk/fold schedule, sequencer state, arithmetic, EBR, R.84 executor, clock,
  public PSG interface, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H019 and R.84:** H019 changed the state-memory
  request-owner mux and kept the replay contract; it regressed globally. H058
  leaves that mux and both controllers unchanged, and tests only whether the
  already-required terminal fold interval subsumes the replay freeze. R.84
  replaces both controllers and is excluded from this worktree.
- **Change:** scratch-only remove `state_replay`, its resettable flop and
  `prun` input from `psg_state_mem`, its top-level busy/ARAM-hold OR terms, and
  its unused `psg_seq` port. The memory request muxes and both controllers stay
  byte-identical. Production RTL is restored byte-for-byte after measurement.
- **Result:** a symbolic Yosys SAT proof covers every full and PREVIEW control
  input and proves both `next_state_replay -> (next_prun || next_fold_busy)`
  and equality of the baseline/candidate hold signals. Full and PREVIEW lint
  pass. Canonical H057-to-candidate mapping changes 6,466 LUT4 / 1,403 carry /
  1,458 FF / 502 unpackable / 14 EBR / floor 6,968 to 6,490 / 1,408 / 1,457 /
  499 / 14 / floor 6,989. Seed-1 placement changes 7,204 to 7,235 LCs and
  passes placed timing at 144.43/32.63 MHz, but router2 remains fixed at two
  overused wires through 55,386 iterations and produces no routed design.
  This is substantially beyond H055's recorded 21,160-iteration route-failure
  threshold. The complete fidelity battery and permanent proof/spec edits are
  correctly skipped because mapped, floor, placement, and routing gates fail.
- **Decision:** rejected and reverted. The exact state simplification removes
  one flop but worsens every deterministic combinational/floor metric, placed
  area, and routability.
- **Repeat only if:** if containment or physical mapping fails, retry only after
  the final-voice fold launch, state-RAM synchronous-read timing, walk/fold
  overlap, or top-level freeze consumers change materially.

## Hypothesis H059

- **ID:** H059.
- **Hypothesis:** `org_h_r` is redundant state. Outside the existing organ
  alternate-secondary bypass, every 16-bit phase's folded reciprocal ramp satisfies
  `org_ramp = (z_lin + 8192) mod 2^15`. Therefore its registered high byte is
  exactly `{z_lin_r[14] ^ z_lin_r[13], ~z_lin_r[13], z_lin_r[12:7]}`: adding
  64 modulo 256 changes only the top two bits. Reconstructing that byte should
  retire eight flops and their D-input cone without moving a pipeline edge or
  adding an arithmetic carry chain. During the bypass the reciprocal result is
  unobserved, so its reconstructed quotient byte is a don't-care.
- **Scope:** exhaustive all-phase proof, unconstrained Yosys SAT, and isolated
  synthesis of the complete two-stage organ reciprocal consumer. Production
  `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG mapping on direct
  frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No organ-ramp arithmetic,
  reciprocal address/table/content, selector encoding, pipeline edge,
  waveform output, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H040 and H056:** H040 rewrote the pre-register
  organ fold and changed mapper arithmetic covering, regressing globally.
  H056 instead proved that the completed, already-registered `z_lin_r` carries
  the organ high-phase predicate and retained that representation. H059 leaves
  H040's source ramp byte-for-byte unchanged and tests a wider exact projection
  from the same completed result, removing only duplicated downstream state.
- **Change:** prove the byte identity in a scratch probe, then price both full
  retirement of `org_h_r` and a partial form retaining only its bypass-live
  bits. Both production variants were applied only in the dedicated direct-
  frontier worktree and reverted byte-for-byte after pricing.
- **Result:** the exhaustive 524,288-case proof and unconstrained Yosys SAT
  pass. Isolated baseline/full/partial synthesis is respectively 149/42/39,
  150/27/31, and 150/27/37 LUT4/carry/FF. Whole-PSG full retirement regresses
  H057's 6,466 LUT4 / 1,403 carry / 1,458 FF / floor 6,968 / 7,204 LCs to
  6,495 / 1,408 / 1,450 / floor 6,987 / 7,229 LCs. Partial retirement maps at
  6,477 LUT4 / 1,407 carry / 1,456 FF / floor 6,977 and places at 7,221 LCs,
  then stops routing with two overused wires after 7,255 iterations. Full and
  PREVIEW lint pass for both variants; the complete fidelity battery is
  correctly skipped because both fail deterministic physical area gates.
- **Decision:** rejected and reverted. The identity is exact and saves state,
  but full and partial retirement both worsen the whole-PSG physical result.
- **Repeat only if:** retry only
  after the organ linear-output representation, reciprocal quotient consumer,
  pipeline placement, or mapper sequential lowering changes materially.

## Hypothesis H060

- **ID:** H060.
- **Hypothesis:** `tri4_r` duplicates information already captured in
  `z_lin_r`. On the only live consumer, alternate primary triangle,
  `z_lin_r == tri_v`; therefore `tri4_r == tzs(z_lin_r, 2)` after the same
  pipeline edge. Reconstructing the `/4` term should retire 18 payload flops
  and their pre-register D cone without changing the triangle generator,
  pipeline timing, or waveform arithmetic.
- **Scope:** exhaustive all-phase/control proof, unconstrained sequential Yosys
  SAT, and isolated synthesis of the complete registered alternate-triangle
  consumer. Production `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG
  mapping on direct frontier `c9274fc`, and the complete H057 battery are
  conditional on a deterministic mapped or floor improvement. No triangle
  source fold, reciprocal arithmetic/table, selector encoding, pipeline edge,
  waveform output, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H054 and H059:** H054 rewrote the pre-register
  centered-triangle fold and added eleven isolated LUT4s. H060 leaves that
  source cone byte-for-byte unchanged and removes only a duplicate projection
  after proving its same-edge source identity. H059 tested the analogous organ
  quotient payload but regressed globally; this distinct triangle payload has
  a different width, rounding function, and consumer cone and is therefore
  priced independently.
- **Change:** remove `tri4_r` and reconstruct its only live value as
  `tzs(z_lin_r, 2)` at the existing downstream stage. The production variant
  was applied only in the dedicated direct-frontier worktree and reverted
  byte-for-byte after pricing.
- **Result:** all 262,144 phase/alternate/secondary cases pass, and the three-
  step sequential SAT miter proves the registered consumers equivalent. The
  isolated complete consumer changes 203 LUT4 / 79 carry / 39 FF / floor 210
  to 203 / 80 / 23 / floor 208. Whole-PSG mapping instead regresses H057's
  6,466 LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,520
  / 1,404 / 1,442 / 498 / floor 7,018. Seed-1 routing regresses 7,204 to 7,257
  LCs; both clocks still pass at 132.03/31.57 MHz. Full and PREVIEW lint pass;
  the complete fidelity battery is correctly skipped because deterministic
  mapped, floor, and routed area all fail.
- **Decision:** rejected and reverted. The identity is exact and removes 16
  mapped flops, but its downstream rounding cone destroys the physical win.
- **Repeat only if:** retry only
  after the triangle linear-output representation, alternate-triangle
  consumer, pipeline placement, or mapper sequential lowering changes
  materially.

## Hypothesis H061

- **ID:** H061.
- **Hypothesis:** the high byte of `fade_acc` is redundant after every active
  fade update. For fade-in it equals `mus_gain`; for established fade-out it
  equals `~mus_gain`. The currently unused `fade_dir == 3` can represent the
  fresh fade-out interval, where progress is zero but the prior gain must
  remain observable until the first `pre_tick`. Retaining only the low eight
  progress bits should remove eight flops while preserving every command-
  transient and tick-visible value.
- **Scope:** symbolic next-state and sequential-invariant proof covering fade-
  in, fresh/established fade-out, completion, idle, and command interruption;
  isolated synthesis of the complete registered fade-state consumer.
  Production `rtl/psg_seq.sv`, permanent hardware forms, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on
  a deterministic mapped or floor improvement. No fade step/table/content,
  command timing, gain value, music stop behavior, schedule, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H025 and H041:** H025 only named the repeated
  combinational fade sum and mapped identically; H041 rewrote the fade-length
  eligibility predicate and regressed globally. H061 changes neither cone. It
  proves a sequential representation invariant between the already-published
  gain and accumulator state, using an otherwise unreachable direction code
  to preserve the one interval where that invariant has not yet been
  established.
- **Change:** in the scratch probe, replace the 16-bit `fade_acc` with an eight-
  bit fraction, reconstruct established progress from `mus_gain`, and encode
  fresh fade-out as `fade_dir == 3` so its prior gain remains observable until
  the first `pre_tick`. Production RTL remains untouched.
- **Result:** exhaustive evaluation passes all 4,202,496 reachable active/fresh
  fade states across the 32 source-derived fade steps. Yosys SAT proves the
  symbolic next-state invariant for arbitrary commands and `pre_tick`,
  including completion and command priority. Isolated complete-consumer
  synthesis changes 41 LUT4 / 16 carry / 27 FF / four unpackable / floor 45
  to 49 / 16 / 19 / two unpackable / floor 51.
- **Decision:** rejected before production. Eight retired flops do not offset
  eight added LUT4s, and the deterministic isolated floor regresses by six.
- **Repeat only if:** retry only
  after fade command timing, accumulator/gain publication, direction encoding,
  or mapper sequential lowering changes materially.

## Hypothesis H062

- **ID:** H062.
- **Hypothesis:** `old_nz_r_on` duplicates the old sounding tuple after the
  visit-start edge. Its captured value is `run && old_nz_on`, where a restart
  selects `s_last_wave/last_alt_r`; that same edge copies those fields into
  `s_old_wave/old_alt_r`, while a non-restart retains the existing old tuple.
  The run predicate and copied tuple remain stable through all consumers, so
  reconstructing the flag should remove one control flop and its D cone with
  no arithmetic or payload remapping.
- **Scope:** exhaustive snapshot/control proof, arbitrary-defined-state
  sequential Yosys SAT, and isolated synthesis of the complete registered old-
  noise consumer. Production `rtl/psg_walk.sv`, permanent hardware forms,
  whole-PSG mapping on direct frontier `c9274fc`, and the complete H057 battery
  are conditional on a deterministic mapped or floor improvement. No noise
  arithmetic, old-phase state, restart predicate, snapshot timing, visit
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H057 and H058:** H057 accepted reconstruction of
  a duplicated one-bit predicate from two same-edge registered controls. H062
  applies that mechanism to a distinct walk snapshot whose selected source is
  copied into the lasting old tuple on the same edge. H058 removed a replay
  contract across a memory hold interval and regressed globally; H062 neither
  changes memory ownership nor recomputes a payload.
- **Change:** remove `old_nz_r_on` and reconstruct the downstream predicate as
  current-run active plus `s_old_wave == 6 && !old_alt_r`; retain the existing
  pre-edge `old_nz_on` only for the simultaneous old-phase seed. The production
  variant was applied only in the dedicated direct-frontier worktree and
  reverted byte-for-byte after pricing.
- **Result:** all 1,024 snapshot/control cases pass, combinational Yosys SAT
  proves the selected-source identity, and a four-step arbitrary-state miter
  proves every post-restart consumer. Isolated complete-consumer synthesis
  changes 23 LUT4 / zero carry / five FF / floor 27 to 21 / zero / four /
  floor 25. Whole-PSG mapping instead regresses H057's 6,466 LUT4 / 1,403
  carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,521 / 1,403 / 1,457 /
  500 / floor 7,021. Seed-1 routing regresses 7,204 to 7,261 LCs; both clocks
  still pass at 116.28/32.94 MHz. Full and PREVIEW lint pass; the complete
  fidelity battery is correctly skipped because mapped, floor, and routed area
  fail decisively.
- **Decision:** rejected and reverted. A two-LUT isolated win and one retired
  flop are overwhelmed by global D-input/fanout remapping.
- **Repeat only if:** retry only
  after old-tuple snapshot timing, restart inputs, old-noise consumers, or
  mapper sequential lowering changes materially.

## Hypothesis H063

- **ID:** H063.
- **Hypothesis:** `mxs_old` stores only the sign of `z_old_sel` at W15 and is
  consumed only when W51 signs the old-arm gain result. W15 executes this
  capture only for a built-in wave. In that branch `smp_b` is complete at W5,
  while the old-noise selector, old-noise output, and old increment are complete
  no later than W1 and remain unchanged through W51. Using the live
  `z_old_sel[17]` at W51 should therefore retire one sign flop and its assignment
  without recomputing an arithmetic payload.
- **Scope:** source-derived assignment/phase audit, exhaustive scheduled-event
  proof, arbitrary-defined-state sequential Yosys SAT, and isolated synthesis
  of the complete old-arm sign consumer. Production `rtl/psg_walk.sv`, a
  permanent hardware form, whole-PSG mapping on direct frontier `c9274fc`, and
  the complete H057 battery are conditional on a deterministic mapped or floor
  improvement. No sample arithmetic, noise state, gain scaling, multiplier
  request, action schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H058--H063 DNR families:** H063 does not remove a
  memory replay contract, reconstruct an old-noise eligibility flag, or derive
  a registered arithmetic payload. It removes a visit-local sign snapshot only
  after proving that the existing sign source itself is invariant across its
  sole capture-to-consume interval.
- **Change:** the direct-frontier experiment removed `mxs_old`, its W15
  assignment, and used `z_old_sel[17]` for the W51 old-gain sign. It was
  reverted byte-for-byte after pricing.
- **Result:** a source assignment audit passes and all 512 endpoint schedules
  agree. A 70-step Yosys SAT miter with arbitrary defined source state and
  arbitrary stalls proves the W15 snapshot equals the live W51 sign whenever
  the consumer is active. Isolated complete-consumer synthesis keeps 47 LUT4s
  and 15 carries while removing one FF. Under the same current Yosys, exact
  H057 remaps to 6,466 LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor
  6,968, while H063 maps to 6,530 / 1,407 / 1,457 / 500 / floor 7,030. H063
  routes at 7,273 LCs versus canonical H057's 7,204 and passes timing at
  122.46/31.52 MHz. Full and PREVIEW lint pass; the complete fidelity battery
  is correctly skipped because every physical area gate except FF count fails.
- **Decision:** rejected and reverted. One retired sign flop is overwhelmed by
  global covering and fanout remapping.
- **Repeat only if:** if rejected, retry only after the old-arm sample/noise
  lifetime, gain-consume action, or mapper sequential lowering changes
  materially.

## Hypothesis H064

- **ID:** H064.
- **Hypothesis:** the live and old nine-bit signed noise draws are two identical
  adjacent-XOR transforms of `lfsr[14:6]` and `lfsr2[14:6]`. Full mode selects
  between those complete draws only for disjoint old/live multiplier requests;
  its other consumers need only each draw's sign. Selecting the nine source
  bits before one shared adjacent-XOR transform, while retaining the individual
  top XORs for sign-only consumers, should remove duplicated random-draw logic
  without adding state or changing arithmetic.
- **Scope:** exhaustive selected-draw/sign proof, combinational Yosys SAT, and
  isolated synthesis of the complete registered request/sign consumer.
  Production `rtl/psg_walk.sv`, a permanent hardware form, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No LFSR recurrence, random value,
  noise rounding, multiplier cadence/mode, state, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H017, H027, H029, and H055:** H017 selected between
  complete gain arithmetic contexts and regressed globally; H027/H029/H055
  changed clamp, kick, or signed-rounding arithmetic. H064 changes none of
  those cones. It factors one identical bitwise transform across two disjoint
  request operands and leaves the independent sign observations explicit.
- **Change:** the direct-frontier experiment selected `lfsr[14:6]` versus
  `lfsr2[14:6]` before one adjacent-XOR chain, uses that shared signed draw for
  `nz_mag_req`, and replaces the two full-draw sign reads with their exact top
  XOR bits. Preview retains its existing live draw. The variant was reverted
  byte-for-byte after pricing.
- **Result:** NumPy exhaustively checks all 524,288 live/old/select tuples and
  combinational Yosys SAT proves the selected draw plus both sign identities.
  Isolated complete-consumer synthesis changes 28 LUT4 / seven carry / eleven
  FF to 26 / seven / eleven. Whole-PSG mapping instead changes H057's 6,466
  LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,521 /
  1,407 / 1,458 / 501 / floor 7,022. Seed-1 routing regresses 7,204 to 7,267
  LCs; both clocks pass at 139.82/32.62 MHz. Full and PREVIEW lint pass; the
  complete fidelity battery is correctly skipped because mapped, floor, and
  routed area fail decisively.
- **Decision:** rejected and reverted. The local two-LUT network saving is
  overwhelmed by flattened covering and fanout remapping; no spelling-only
  second variant is justified.
- **Repeat only if:** if rejected, retry only after noise request ownership,
  LFSR tap layout, sign consumers, or mapper XOR/mux lowering changes
  materially.

## Hypothesis H065

- **ID:** H065.
- **Hypothesis:** `smp_a` and `smp_b` are 18-bit pipeline registers, but every
  value stored in them is a single built-in/custom-wave result or the completed
  primary-plus-secondary sample. Exhaustive primitive ranges and exact
  truncation-toward-zero composition bounds place every such value in signed
  16 bits. Narrowing both registers to 16 bits and explicitly sign-extending
  all 18-bit arithmetic consumers should retire four flops plus their upper
  assignment mux logic while preserving every value.
- **Scope:** source-derived assignment/use audit, exhaustive built-in/custom
  waveform range proof, signed-width/SAT equivalence of every load and consumer,
  and isolated synthesis of the complete registered sample boundary.
  Production `rtl/psg_walk.sv`, a permanent hardware form, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No waveform formula, phase,
  noise state, sample schedule, multiplier request, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H013, H014, H037, and R.18/R.39:** H013/H014/H037
  tested multiplier/detune widths that Yosys already pruned or remapped worse;
  R.18/R.39 changed register ownership and fanout. H065 changes no lifetime or
  ownership: it contracts two existing sample registers at an exact value
  boundary and keeps their consumer widths explicit.
- **Change:** change `smp_a/smp_b` to signed 16-bit registers, introduce
  explicit sign-extended 18-bit views for
  sum/old/base consumers, and leave the nine-bit wavetable-delta slices
  unchanged.
- **Result:** the source audit and exact range proof bound all stored/composed
  built-in results to -18,429..18,427 and all 67,108,864 custom-wave tuples to
  -16,384..16,256. Yosys SAT with the source assumptions passes. The complete
  isolated registered boundary improves from 70 LUT4 / 33 carry / 36 FF to
  67 / 32 / 32. Full and PREVIEW lint pass. Canonical forced whole-PSG
  synthesis instead changes H057's 6,466 LUT4 / 1,403 carry / 1,458 FF / 502
  unpackable / floor 6,968 to 6,493 / 1,399 / 1,454 / 502 / floor 6,995.
  Seed-1 routing changes 7,204 to 7,236 LCs; both clocks pass at
  120.80/32.58 MHz. The complete fidelity battery is correctly skipped
  because deterministic mapped and floor area regress decisively.
- **Decision:** rejected and reverted byte-for-byte. Four fewer flops and
  carries do not compensate for 27 more LUT4s/floor cells; no second width
  spelling is justified on this mapping context.
- **Repeat only if:** if rejected, retry only after waveform/sample bounds,
  sample-register assignments, consumer widths, or mapper sequential lowering
  changes materially.

## Hypothesis H066

- **ID:** H066.
- **Hypothesis:** `tilt_tail_r` delays one predicate to choose the direct-tail
  result after the reciprocal RAM read, while `rc_h2_r` delays the folded
  reciprocal index for the mutually exclusive non-tail result. Exhaustive
  source arithmetic bounds every live tilt/organ `rc_h2` to 0..105, leaving
  `7'h7f` unreachable. Encoding the tail token as that reserved `rc_h2_r`
  value should remove one flop and its separate predicate path without adding
  state or changing any arithmetic.
- **Scope:** exhaustive source-derived `rc_h2` range and tail/result proof,
  sequential SAT equivalence of the two-stage consumer, isolated synthesis of
  the complete registered boundary, and conditional production
  `rtl/psg_wave.sv`, permanent hardware form, whole-PSG mapping, and complete
  H057 battery. No waveform value, reciprocal contents, schedule, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H003, H052, H053, and H057:** H003 simplified
  the source tail comparison but retained its pipeline state; H052/H053 added
  controller states; H057 reconstructed a predicate from same-edge control
  registers. H066 instead embeds mutually exclusive metadata in a provably
  unused code of an existing stage-aligned payload register.
- **Change:** planned direct-frontier experiment gives organ selection priority,
  writes `7'h7f` into `rc_h2_r` for non-organ tail cases, reconstructs the
  delayed tail predicate as `&rc_h2_r`, and removes `tilt_tail_r`.
- **Result:** exhaustive evaluation of 1,048,576 selector/phase cases proves
  every live tilt `rc_h2` is 0..105 and every organ value is 0..95, so 127 is
  unreachable; the tail selection and SAT induction pass. The complete
  isolated registered boundary changes 182 LUT4 / 25 carry / 87 FF to
  188 / 25 / 86. Full and PREVIEW lint pass with only existing warnings.
  Canonical forced whole-PSG synthesis changes H057's 6,466 LUT4 / 1,403
  carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,508 / 1,407 / 1,457 /
  500 / floor 7,008. Seed-1 routing changes 7,204 to 7,251 LCs; the PSG clock
  passes at 31.90 MHz, but the fast clock reaches only 111.26 MHz against the
  112.50-MHz constraint. The complete fidelity battery is correctly skipped.
- **Decision:** rejected and reverted byte-for-byte. The sentinel adds six
  isolated and 42 global LUT4s for one retired flop, worsens every area floor,
  and fails timing; no alternative reserved value is justified.
- **Repeat only if:** if rejected, retry only after reciprocal-index ranges,
  tail ownership, stage alignment, or mapper payload/predicate lowering
  changes materially.

## Hypothesis H067

- **ID:** H067.
- **Hypothesis:** `t_h7_r` and `t_h15_r` store 21 bits that are both exact
  slices of the same 19-bit `t_pre` captured beside them. Their low six and
  seven bits already survive in `t_pre_r[14:9]` and `[14:8]`; their remaining
  high four bits are the identical `t_pre[18:15]` prefix. Registering that
  prefix once and rebuilding both quotient views by wiring should retire 17
  flops and duplicated D paths without a selector or arithmetic.
- **Scope:** full-domain slice identity and sequential SAT proof, isolated
  synthesis of the complete registered reciprocal consumer, and conditional
  production `rtl/psg_wave.sv`, permanent hardware form, whole-PSG mapping,
  and complete H057 battery. No quotient value, reciprocal address/content,
  waveform arithmetic, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H036 and H037:** H036 inserted an 11-bit
  mode-selection mux before one register and globally remapped worse; H037
  tested one conditionally dead bit that Yosys already pruned. H067 has no
  mode selection and no unreachable-value claim: it factors the shared source
  bit positions across both quotient registers and an already-live sibling
  payload, retaining only the four genuinely missing bits.
- **Change:** planned direct-frontier experiment replaces the ten- and eleven-
  bit quotient registers with one four-bit `t_hi_r`, reconstructing
  `t_h7_r={t_hi_r,t_pre_r[14:9]}` and
  `t_h15_r={t_hi_r,t_pre_r[14:8]}`.
- **Result:** exhaustive evaluation of all 524,288 `t_pre` values proves both
  slice reconstructions, and the SAT induction proves current-state selection
  plus next-state mapping. The complete baseline and candidate registered
  consumers both synthesize to 19 LUT4s and 29 FF. Yosys already merges the
  duplicate source bits across the two declared quotient registers, so no
  production RTL, permanent proof, whole-PSG synthesis, or fidelity gate is
  warranted.
- **Decision:** rejected before production. The candidate is source-shorter
  but physically identical, and the existing spelling states the two quotient
  slices directly.
- **Repeat only if:** if rejected, retry only after `t_pre_r` ownership/width,
  quotient consumers, pipeline alignment, or mapper shared-slice lowering
  changes materially.

## Hypothesis H068

- **ID:** H068.
- **Hypothesis:** the DQ recurrence currently commits its fifth step into `p`
  only so the completed result remains visible after `done` falls. If the
  terminal no-chain edge instead holds the fourth-step state, the same fifth
  `step_next` value remains visible throughout idle and on the `done` edge.
  Exposing `step_next[21:8]` directly should remove the 14-bit done/idle result
  mux and the unnecessary terminal register write without changing any valid
  transaction, chained-start, latency, or walker-consumption behavior.
- **Scope:** exhaustive service transaction/chained-start proof, terminal-state
  SAT relation, isolated complete-service synthesis, and conditional production
  `rtl/psg_dqsvc.sv`, permanent hardware form, whole-PSG mapping, and complete
  H057 battery. No arithmetic, coefficient, phase schedule, public interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H051 and closed state families:** H051 recoded the
  five active count states but retained the recurrence/result contract. H068
  does not add or repurpose controller state: it removes a result selector by
  retaining the already-live pre-terminal recurrence only during idle. It is
  separate from the closed fold publication, delayed-tick, divider, multiplier-
  width, and detune-service-count families.
- **Change:** planned direct-frontier experiment assigns `result` from
  `step_next[21:8]` unconditionally and holds `p` on the terminal edge when no
  request chains; terminal chained starts still load the next transaction.
- **Result:** the global-NumPy transaction model passes all 57,344 reachable
  coefficient/input pairs, the terminal/idle SAT relation passes, and the
  existing service test passes 524,288 arithmetic formulas plus 57,344
  exhaustive/chained transactions. The complete isolated service improves
  120 -> 114 LUT4s with 28 carries and 28 flops unchanged. Canonical forced
  whole-PSG synthesis is unfavorable: 6,466 -> 6,457 LUT4s, 1,403 -> 1,404
  carries, 1,458 flops unchanged, 502 -> 514 unpackable flops, 14 EBRs
  unchanged, floor 6,968 -> 6,971, and seed-1 route 7,204 -> 7,210 LCs.
  Timing passes at 137.65/30.75 MHz, but the deterministic floor and placed
  area both regress, so the complete fidelity battery is not warranted.
- **Decision:** rejected and reverted byte-for-byte. The local result mux win
  globally changes packing classes and violates the no-floor/no-placement-
  regression gate.
- **Repeat only if:** if rejected, retry only after the DQ result consumer,
  terminal chaining contract, recurrence alignment, or mapper result-mux
  lowering changes materially.

## Hypothesis H069

- **ID:** H069.
- **Hypothesis:** signed division by `2^k` truncated toward zero is exactly an
  arithmetic right shift plus one iff the input is negative and any discarded
  bit is nonzero. Rewriting the shared `tzs(v,k)` helper in that quotient/
  remainder form should avoid the current full-width pre-shift sign-bias add
  across its five waveform/walk consumers and may simplify both source and
  mapped carry logic.
- **Scope:** exhaustive all-18-bit/all-four-shift proof, formal identity, isolated
  synthesis of the complete five-consumer helper context, and conditional
  production `rtl/psg_common.svh`, permanent hardware form, whole-PSG mapping,
  and complete H057 battery. No waveform value, schedule, register, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H001 and H055:** H001 optimized two unsigned
  tilted-saw ceilings at fixed widths; H055 tested paired signed noise-product
  limbs and closed that local rounding topology. H069 changes the shared exact
  power-of-two signed-division helper itself, including its variable-shift
  waveform consumer, without merging noise limbs or changing an arithmetic
  value.
- **Change:** compute `q = v >>> k`, decode the discarded remainder for k=0..3,
  and return `q + (v[17] && remainder)`.
- **Result:** the global-NumPy proof passes all 1,048,576 signed18/shift
  combinations and Yosys SAT proves the identity. The complete five-consumer
  isolated context changes 174 -> 144 LUT4s and 137 -> 97 carries. Permanent
  forms, full/PREVIEW lint, `make test-psg`, 59/59 frozen renders, the exact
  `/4`/`/5`/`/6` ordinary and multipumped cadence matrix, `make test-clocks`,
  and all eight preview checks pass. Synthetic and Celeste recovery have zero
  coalesced, delayed, or dropped samples. Hardware and PREVIEW SFX-10 WAVs are
  byte-identical to H057 and have zero `click-v1` events. The five-frame
  Celeste smoke retains 2,179/3,668 active samples, range -22,013..9,151, and
  1,068 levels. Canonical forced HX8K synthesis changes 6,466 -> 6,456 LUT4s,
  1,403 -> 1,370 carries, 1,458 -> 1,459 flops, 502 -> 503 unpackable flops,
  floor 6,968 -> 6,959, and seed-1 route 7,204 -> 7,199 LCs with 14 EBRs.
  Routed timing passes at 133.69/32.82 MHz, and the JSON/ASC reproduce exactly.
  Strict OpenSpec, `py_compile`, diff, and exact two-file scope audits pass.
- **Decision:** accepted. The shared arithmetic contract is explicit, mapped
  LUT4s, carries, and deterministic floor all improve, seed-1 placement does
  not regress, and the complete exact behavior and timing battery passes. The
  five-LC route reduction remains explicitly non-robust.
- **Repeat only if:** if rejected, retry only after the shared helper's consumer
  set, shift widths, mapper arithmetic-shift lowering, or rounding contract
  changes materially.

## Hypothesis H070

- **ID:** H070.
- **Hypothesis:** the restoring divider needs exactly 24 active iterations.
  The 24-state maximal-LFSR segment
  `12 -> 25 -> 19 -> ... -> 8 -> 16 -> 1` preserves that latency, keeps zero
  idle and one terminal, and replaces the five-bit binary decrement carry chain
  with one XOR and a shift.
- **Scope:** exhaustive state/latency proof, sequential SAT of every public
  divider output, and isolated complete-service synthesis; conditional
  production `rtl/psg_divsvc.sv`, permanent hardware form, whole-PSG mapping,
  and complete H069 battery. No dividend step, quotient, remainder, request,
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H016 and H051:** H016 changed the restoring
  subtract width and is closed; H070 leaves the divider datapath untouched and
  changes only its iteration token. H051 proved the same controller principle
  for a five-step detune service; H070 independently proves a distinct 24-step
  divider service with different width, recurrence, latency, and consumers.
- **Change:** scratch form loads count 12, advances
  `{count[3:0], count[4] ^ count[2]}`, and returns to zero after terminal state
  one. The current 24-to-one binary countdown is the reference.
- **Result:** exhaustive comparison proves all 50 idle/active input transitions
  and the exact 24-state sequence. Combinational SAT proves the mapped count,
  busy, quotient/remainder state, divisor state, load, and arithmetic-step next
  relations for every reachable count and arbitrary operands. The complete
  isolated divider improves 51 -> 50 LUT4s and 12 -> 9 carries with 45 flops
  unchanged. Whole-PSG synthesis is unfavorable: 6,456 -> 6,479 LUT4s,
  1,370 -> 1,363 carries, 1,459 flops and 503 unpackable flops unchanged,
  floor 6,959 -> 6,982, and seed-1 route 7,199 -> 7,216 LCs. Timing passes at
  131.94/32.06 MHz, but deterministic floor and placement both regress.
- **Decision:** rejected and reverted byte-for-byte. The isolated controller
  saving perturbs the full divider/consumer packing and violates both physical
  area gates, so the complete fidelity battery is not warranted.
- **Repeat only if:** if rejected, retry only after divider iteration count,
  request/terminal timing, counter width, or mapper LFSR/decrement lowering
  changes materially.

## Hypothesis H071

- **ID:** H071.
- **Hypothesis:** for signed 24-bit `v`, truncation toward zero after division
  by 64 is exactly `(v >>> 6) + (v < 0 && v[5:0] != 0)`. Applying that
  correction after the shift in the blend consumer should replace its
  conditional 24-bit `+63` with one remainder reduction and a narrower
  increment while preserving every bit.
- **Scope:** exhaustive NumPy and Yosys proof plus isolated synthesis of the
  complete registered blend consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No blend coefficient,
  schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H055 and H069:** H055 changed the two noise-step
  sign limbs and is closed. H069 proved the same rounding identity for five
  18-bit waveform shifts of zero through three; H071 applies it to a distinct
  24-bit blend result shifted by six, whose existing conditional `+63` remains
  source-visible and mapped.
- **Change:** replace `bl_acc + (negative ? 63 : 0)` followed by `>>> 6` with
  the arithmetic-shifted quotient plus one only for a negative nonzero six-bit
  remainder.
- **Result:** all 16,777,216 signed-24 values pass the global-NumPy exhaustive
  identity check, and Yosys proves all 83 points in the complete registered
  consumer. Isolated synthesis improves 137 -> 129 LUT4s and 78 -> 72 carries
  with 17 flops unchanged. The first whole-PSG spelling maps to 6,508 LUT4s,
  1,365 carries, 1,459 flops, 502 unpackable flops, and a 7,010-cell floor:
  versus H069 that is +52 LUT4s, -5 carries, and +51 floor cells. A second
  name-preserving spelling maps to 6,482 LUT4s, 1,364 carries, the same flops,
  and a 6,984-cell floor: still +26 LUT4s, -6 carries, and +25 floor cells.
- **Decision:** rejected and reverted byte-for-byte. Both allowed spellings
  violate the deterministic LUT/floor gate, so routing and the complete
  fidelity battery are not warranted.
- **Repeat only if:** if rejected, retry only after blend accumulator width,
  division/rounding contract, mapper shift/add lowering, or blend consumer
  topology changes materially.

## Hypothesis H072

- **ID:** H072.
- **Hypothesis:** dampen modes one and two/three truncate the signed 19-bit
  `dmp_acc` toward zero after division by two or four. Selecting the arithmetic
  shift first, then adding one only for a negative discarded remainder, is
  exactly equivalent to the current mode-selected pre-shift bias of one or
  three and may remove the wide conditional adder.
- **Scope:** exhaustive NumPy and Yosys proof plus isolated synthesis of the
  complete registered dampen consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No dampen coefficient,
  mode, schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H069 and H071:** H069 proved five signed-18
  waveform shifts of zero through three. H071's distinct signed-24 blend `/64`
  consumer is closed after global regressions. H072 targets the still-mapped
  signed-19 dampen consumer, with a two-mode selected shift and remainder width.
- **Change:** replace the mode-selected negative `+1`/`+3` followed by fixed
  slices with a selected arithmetic quotient plus one for a negative nonzero
  one- or two-bit remainder.
- **Result:** all 1,572,864 signed-19/mode tuples pass the global-NumPy
  exhaustive identity check, and Yosys proves all 89 points in the complete
  registered consumer. Isolated synthesis keeps 121 LUT4s and 17 flops while
  reducing 52 -> 50 carries. Whole-PSG synthesis maps to 6,482 LUT4s, 1,365
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, and a 6,983-cell floor.
  Versus H069 that is +26 LUT4s, -5 carries, and +24 floor cells.
- **Decision:** rejected and reverted byte-for-byte. The carry reduction does
  not compensate for the deterministic LUT/floor regression, so routing and
  the complete fidelity battery are not warranted.
- **Repeat only if:** if rejected, retry only after dampen accumulator width,
  mode contract, mapper shift/add lowering, or dampen consumer topology changes
  materially.

## Hypothesis H073

- **ID:** H073.
- **Hypothesis:** the shared noise-product operand is `8*dp + 1120`, and
  `1120 = 140*8`. Spelling it as the concatenation of the exact 14-bit
  `dp + 140` sum and three zero bits should remove three dead low positions
  from the mapped adder while simplifying the arithmetic contract.
- **Scope:** exhaustive/Yosys proof and isolated synthesis of the complete
  registered noise-request operand consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No noise distribution,
  multiplier request timing, schedule, state, interface, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition:** no prior continuation hypothesis rewrites the aligned
  `nz_j_req` offset. The noise-product scheduling and two-context operand
  sharing are unchanged; this tests only the source width of its surviving
  constant addition.
- **Change:** replace `{1'b0, nz_dp_req, 3'b0} + 17'd1120` with
  `{1'b0, nz_dp_req + 14'd140, 3'b0}`.
- **Result:** all 8,192 increments pass the exhaustive identity check, and
  Yosys proves all 42 points in the complete registered consumer. Both forms
  map identically at 11 LUT4s, ten carries, and 14 flops.
- **Decision:** rejected before production because Yosys already removes the
  three aligned low positions. No production or permanent-proof file changed,
  and no whole-PSG/fidelity gate is warranted.
- **Repeat only if:** if rejected, retry only after noise-product operand width,
  constant offset, multiplier request interface, or mapper aligned-add lowering
  changes materially.

## Hypothesis H074

- **ID:** H074.
- **Hypothesis:** the affine slide path retains only bits 29:12 of
  `r + frac*b_lo`, then adds the second product and discards another 17 bits.
  Omitting the first sum's low-12 carry changes the intermediate high limb by
  at most one; if that unit never crosses the final boundary over the complete
  reachable pitch/fraction domain, the source can replace its 30-bit add with
  one exact 18-bit high-limb add.
- **Scope:** exhaustive proof over all 64 pitches and 65,536 fractions using
  the permanent affine table/model; conditional isolated synthesis of the
  complete two-pass registered consumer, production `rtl/psg_seq.sv`,
  permanent `tools/psg_hw_forms.py` proof, whole-PSG mapping, and complete H069
  battery. No slide table, output increment, octave rule, schedule, state,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H023:** H023 changes only the six-bit octave and
  chromatic decode after interpolation. H074 leaves that accepted decode
  untouched and tests a previously unpriced precision boundary inside the
  two-pass affine interpolation itself.
- **Change:** compute the retained first limb from `r[28:12] + product[27:12]`
  without the carry from their low 12 bits, then leave the second accumulation
  and octave shift unchanged.
- **Result:** exhaustive reachable-domain checking finds the first
  counterexample at pitch two, fraction 9,668: current second-stage input
  2,097,152 versus carry-dropped 2,097,151, producing increment 220 versus 219.
- **Decision:** rejected before isolated or production synthesis because the
  low-12 carry is observably required. No production or permanent-proof file
  changed, and no physical/fidelity gate is warranted.
- **Repeat only if:** if rejected, retry only after affine-table coefficients,
  first/second discard positions, reachable fraction domain, or slide
  interpolation contract changes materially.

## Hypothesis H075

- **ID:** H075.
- **Hypothesis:** wavetable interpolation currently conditionally negates the
  unsigned multiplier magnitude, then adds that signed product to the shifted
  table base. XORing the magnitude operand with its sign and using that sign as
  the addition carry-in is the exact two's-complement add/sub form and should
  replace the negate and sum carry chains with one.
- **Scope:** exhaustive/formal proof and isolated synthesis of the complete
  registered wavetable interpolation consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG mapping,
  and complete H069 fidelity/physical battery. No multiplier request, product
  slice, interpolation fraction, table value, schedule, state, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus the historical blend update and H040:** the older
  blend consolidation operated on a 17/24-bit crossfade path and regressed
  placement; H040 changed organ-ramp complement semantics. H075 instead targets
  the distinct 20-bit wavetable base-plus-magnitude consumer whose separate
  product negate remains mapped before the sum.
- **Change:** replace signed `+/-m_res[20:2]` publication followed by the base
  add with `base + (magnitude XOR sign-mask) + sign`.
- **Result:** the global NumPy proof exhausts all 1,048,576 magnitude/sign
  tuples, the Yosys equivalence proof covers all 35 registered-consumer points,
  and the permanent full hardware forms pass. The complete isolated registered
  consumer falls from 61 to 36 LUT4s and 27 to 19 carries with 17 flops
  unchanged. Full and PREVIEW lint, `make test-psg`, the 59/59 frozen render
  regression, ordinary and multipumped `/4`--`/6` cadence, `make test-clocks`,
  all eight PREVIEW checks, synthetic/Celeste recovery, and exact SFX-10
  hardware/PREVIEW click checks pass. Same-tool H069 and H075 SFX-10 PREVIEW
  renders are byte-identical; the stored H069 PREVIEW WAV retains its known
  one-launch-sample historical tool offset. The five-frame Celeste smoke is
  unchanged at 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068
  distinct levels. Strict OpenSpec validation, `py_compile`, diff/scope audits,
  and a second forced canonical synthesis all pass; both JSON and ASC artifacts
  are bit-identical.
- **Physical result:** H069 to H075 changes 6,456 to 6,433 LUT4s, 1,370 to
  1,362 carries, 1,459 flops unchanged, 503 to 501 unpackable flops, 14 EBRs
  unchanged, and the deterministic floor from 6,959 to 6,934. Seed-1 routing
  changes 7,199 to 7,173 LCs and routed clocks 133.69/32.82 to 138.48/33.55
  MHz. The durable claim is -23 LUT4s, -8 carries, -2 unpackable flops, and
  -25 floor cells; the -26 routed LCs remain below placement sensitivity.
- **Decision:** accepted as direct commit `c634db2`. The source is shorter,
  exposes the exact add/sub contract, improves every deterministic area metric
  without an FF or EBR regression, and passes the complete H069 battery.
- **Repeat only if:** if rejected, retry only after wavetable product width,
  product landing slice, interpolation base width, or mapper add/sub lowering
  changes materially.

## Hypothesis H076

- **ID:** H076.
- **Hypothesis:** the current tilted-saw affine forms first build `3*x`, then
  evaluate `3*x-ceil(x/2048)` on the low branch or `6*x-ceil(x/1024)` on the
  high branch. Reassociating them as `2*x + (x-ceil)` and
  `4*x + (2*x-ceil)` preserves every bit while narrowing the first chain from
  the 18-bit `3*x` add to a branch-selected add/subtract no wider than 17 bits.
- **Scope:** exhaustive proof over all 65,536 ramp values and both tilt modes,
  then isolated synthesis of the complete registered tilt consumer. Production
  `rtl/psg_wave.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H075 battery are conditional on an isolated
  deterministic improvement. No ceiling value, ramp/tail selection,
  reciprocal address/table/recombine, pipeline stage, waveform output,
  schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H001 and H074:** H001 retained the exact narrow
  ceiling boundary but did not alter the surrounding affine chains; H076 keeps
  that accepted ceiling and reassociates the full tilted-saw consumer. H074
  concerned a distinct slide interpolation carry whose removal was inexact;
  H076 drops no carry or precision and is an algebraic identity.
- **Change:** conditionally replace `3*x` followed by scale/subtract with the
  exact narrow subtract limb followed by one shifted add.
- **Result:** exhaustive comparison proves both branches over all 131,072
  actual mode/phase tuples and proves the first limb fits unsigned 17 bits.
  The complete isolated registered tilt consumer falls from 129 to 117 LUT4s
  and 69 to 68 carries with 28 flops unchanged. Canonical whole-PSG mapping
  instead changes H075's 6,433 LUT4 / 1,362 carry / 1,459 FF / 501 unpackable
  / 14 EBR / 6,934 floor to 6,438 / 1,361 / 1,459 / 502 / 14 / 6,940.
  Routing and the complete fidelity battery are correctly skipped after the
  deterministic LUT4, unpackable-flop, and floor gates fail. Production RTL
  and the conditional permanent form are restored byte-for-byte.
- **Decision:** rejected after whole-PSG mapping. The narrower first chain is
  exact and locally smaller, but its reassociated mux/adder covering is
  globally worse on the H075 frontier.
- **Repeat only if:** if rejected, retry only after the tilted-saw affine
  coefficients, ceiling boundaries, ramp width, reciprocal input contract, or
  mapper add/sub lowering changes materially.

## Hypothesis H077

- **ID:** H077.
- **Hypothesis:** the tilt pipeline forms `t_ix7 = t_pre[18:9] + t_pre[8:0]`
  and `t_ix15 = t_pre[18:8] + t_pre[7:0]` in parallel, but `tilt_hi` selects
  exactly one reciprocal family. Selecting those narrow operands first and
  evaluating one zero-extended 11-bit sum should retire the unused 10-bit
  carry chain while preserving every reciprocal address bit.
- **Scope:** exhaustive comparison of the shared index and every derived
  `/7`/`/15` address field over all 19-bit `t_pre` values and both tilt modes,
  then isolated synthesis of the complete registered tilt consumer. Production
  `rtl/psg_wave.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H075 battery are conditional on an isolated
  deterministic improvement. No tilted-saw affine value, ceiling, reciprocal
  table/content/recombine, pipeline stage, waveform output, schedule, state,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H067 and reciprocal-coefficient factoring:** H067
  tried to reconstruct two registered quotient views from a shared source
  prefix and mapped identically. H077 leaves both registered quotient views
  intact and instead replaces the two following mutually exclusive index
  adders with one operand-selected adder; it does not alter or factor the
  downstream reciprocal coefficient network.
- **Change:** replace parallel `t_ix7`/`t_ix15` additions with one 11-bit sum
  over mode-selected zero-extended operands, then take the existing mode's
  high/remainder slices from that sum.
- **Result:** exhaustive comparison covers all 1,048,576 combinations of the
  19-bit source and both tilt modes, including the current 10/11-bit native
  wrap, and proves every selected high field, remainder field, and eight-bit
  reciprocal address identical. The complete isolated registered tilt
  consumer maps identically in both forms at 129 LUT4s, 69 carries, and 28
  flops. Production RTL and the permanent form are correctly skipped.
- **Decision:** rejected before production. Yosys already folds the exclusive
  parallel index expressions into the same mapped network, so the explicit
  shared adder offers no deterministic resource or source-simplicity win.
- **Repeat only if:** if rejected, retry only after the reciprocal fold width,
  `/7` or `/15` index split, tilt-mode exclusivity, pipeline boundary, or
  mapper operand-selection lowering changes materially.

## Hypothesis H078

- **ID:** H078.
- **Hypothesis:** the full-schedule soft-add engine probes `s - 24576` and, only
  when that is negative, probes `-24576 - s`. The sign of the registered sum
  already selects the only relevant orientation, so evaluating `s - 24576`
  for nonnegative sums or `-24576 - s` for negative sums in one state should
  preserve the exact excess while removing the second probe state and its
  operand/control decode.
- **Scope:** exhaustive algebraic comparison over the complete registered-sum
  domain, sequential/form proof over every legal signed-16 operand pair, then
  isolated synthesis of the complete registered soft-add fold engine.
  Production `rtl/psg_walk.sv`, a permanent `tools/psg_hw_forms.py` check,
  whole-PSG mapping, and the complete H075 battery are conditional on an
  isolated deterministic improvement. No soft-add threshold, `/5` quotient,
  rounding, reduction-tree order, leaf value, EBR content, sample schedule,
  state-memory contract, interface, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H040/H071/H072:** those rows changed organ-fold,
  blend-rounding, or dampen-rounding arithmetic. H078 leaves all three paths
  untouched and targets the distinct serialized mixer soft-add controller;
  it changes neither the compressed value nor the existing base-256 `/5`
  implementation.
- **Change:** capture the sum sign with the first add, select the positive or
  negative threshold-subtract orientation in the next state, and branch from
  that single result to the unchanged quotient path or linear completion. The
  negative-path state remains as a timing-only token so controller latency is
  unchanged.
- **Result:** exhaustive inspection of all 262,144 registered sums finds the
  baseline's modular first probe wraps across the illegal tail
  -131,072..-106,497. Actual leaves are signed-16, their pair sum is bounded to
  -65,536..65,534, and the existing soft-add maps that complete interval back
  into signed-16; the sign-selected form is exact and cycle-identical
  throughout that inductive domain. Yosys SAT proves the registered threshold
  controller over all 4,294,967,296 signed-16 operand pairs, and the existing
  quotient construction matches exact `/5` over all 131,072 excess values.
  The complete registered fold engine instead changes 336 to 342 LUT4s, with
  25 carries, 66 flops, and one EBR unchanged. Production RTL, permanent forms,
  whole-PSG synthesis, routing, and fidelity gates are correctly skipped.
- **Decision:** rejected before production. The exact sign-selected operand
  mux costs more than the removed arithmetic probe decode in the complete
  registered consumer.
- **Repeat only if:** if rejected, retry only after the soft-add threshold,
  fold operand width, quotient implementation, controller pipeline, or mapper
  operand-selection lowering changes materially.

## Hypothesis H079

- **ID:** H079.
- **Hypothesis:** both reverb combs implement signed round-toward-zero `/2` by
  adding a full-width one to every negative 19-bit accumulator before taking
  bits `[17:1]`. After the arithmetic shift, only a negative odd accumulator
  needs correction; moving that one-bit correction after the shift should
  replace two 19-bit bias carry chains with two narrower incrementers.
- **Scope:** exhaustive/formal proof over both complete comb input domains,
  then isolated synthesis of the complete registered dual-comb and blend-
  difference consumer. Production `rtl/psg_walk.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H075
  battery are conditional on an isolated deterministic improvement. No reverb
  tap, enable, ring memory, blend arithmetic, dampen arithmetic, multiplier
  request, schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus historical comb sharing and H069/H071/H072:** the
  earlier comb experiment tried to share the live/old networks and correctly
  found no realizable saving. H079 keeps both parallel combs and changes only
  their identical fixed-shift rounding identity. H069 changed the shared
  variable-shift waveform helper; H071 and H072 changed blend and dampen
  rounding, which remain byte-for-byte untouched here.
- **Change:** replace each `acc + sign` pre-shift bias with the exact arithmetic
  half plus `sign & odd`, retaining the existing 17-bit landing slice.
- **Result:** exhaustive comparison proves the identity for all 524,288
  signed-19 accumulators and confirms the declared dual-comb input range
  -163,840..163,837 cannot overflow. SAT independently proves both complete
  signed-17 sample by signed-16 tap input domains. The complete registered
  dual-comb/blend-difference consumer changes 139 LUT4s unchanged, 85 to 83
  carries, and 52 flops unchanged. Canonical whole-PSG mapping instead changes
  H075's 6,433 LUT4 / 1,362 carry / 1,459 FF / 501 unpackable / 14 EBR / 6,934
  floor to 6,465 / 1,358 / 1,459 / 501 / 14 / 6,966. Seed-1 routing changes
  7,173 to 7,198 LCs and routed clocks 138.48/33.55 to 118.06/31.24 MHz; both
  clocks still pass. The deterministic LUT/floor gates reject the candidate,
  so the complete fidelity battery is correctly skipped and both production
  files are restored byte-for-byte.
- **Decision:** rejected after whole-PSG mapping. The four-carry global saving
  does not compensate for 32 added LUT4s/floor cells; the 25-LC route increase
  remains below placement sensitivity and is not a durable claim.
- **Repeat only if:** if rejected, retry only after reverb accumulator width,
  tap width, rounding rule, comb enable/consumer, or mapper increment lowering
  changes materially.

## Hypothesis H080

- **ID:** H080.
- **Hypothesis:** the fractional sample clock updates one signed accumulator by
  subtracting `CLK_HZ - 22050` when nonnegative and adding `22050` when
  negative. The accepted H075 netlist contains a separate 23-carry chain for
  each branch. Selecting the signed constant first and applying one shared
  addition should preserve the exact recurrence while allowing one physical
  update chain to replace both.
- **Scope:** exhaustive and symbolic proof over the complete signed accumulator
  domain, then isolated synthesis of the complete registered `psg_timing`
  consumer. Production `rtl/psg_timing.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H075
  battery are conditional on an isolated deterministic improvement. No clock
  frequency, sample rate, accumulator width, reset value, 183-sample cadence,
  tick delay, pre-tick timing, schedule, state, interface, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG. Its mapped netlist
  attributes 23 carries to each of `psg_timing.sv`'s two accumulator-update
  branches.
- **Changed condition versus H007--H010:** H007 accepted only a
  `CLK_HZ`-derived accumulator width; H008 tested sharing the two sample-count
  terminal equalities; H009 and H010 changed the delayed tick representation.
  H080 preserves all of those accepted or retained structures and changes only
  the arithmetic spelling of the already width-bounded fractional accumulator
  update.
- **Change:** select `DIV_UP` or `-DIV_DOWN` from the current accumulator sign,
  then assign `divd + selected_delta` once outside the branch that controls
  sample and tick side effects.
- **Result:** exhaustive checking passes all 67,108,864 canonical signed
  accumulator states and the symbolic SAT miter proves the two update forms
  equivalent. The complete isolated registered `psg_timing` consumer falls
  from 86 to 45 LUT4s and 52 to 29 carries with its flops unchanged. Full
  hardware forms, full and PREVIEW lint, `make test-psg` including all 93
  analysis tests and the structural PSG test, 59/59 frozen renders, ordinary
  and multipumped `/4`--`/6` cadence, clock tests, all eight PREVIEW checks,
  synthetic/Celeste recovery, and hardware/PREVIEW SFX-10 click checks pass.
  A clean H075 PREVIEW rebuild is byte-identical to H080 at SHA-256
  `e2dcf238ef7ae0cc8d56d7a557e64d4c34d761b07cd331a7039aed00e2dba03a`;
  the earlier one-sample offset was a stored-artifact/tool-history issue. The
  five-frame Celeste smoke retains the exact H075 activity signature. Strict
  OpenSpec validation, permanent forms under the global NumPy installation,
  `py_compile`, diff/scope audits, and a second forced canonical synthesis all
  pass; both JSON and ASC artifacts are bit-identical.
- **Physical result:** H075 to H080 changes 6,433 to 6,409 LUT4s, 1,362 to
  1,339 carries, 1,459 flops and 501 unpackable flops unchanged, 14 EBRs
  unchanged, and the deterministic floor from 6,934 to 6,910. Seed-1 routing
  changes 7,173 to 7,147 LCs and routed clocks 138.48/33.55 to 134.44/32.36
  MHz. Both clocks remain above their 112.50/18.75-MHz constraints. The durable
  claim is -24 LUT4s, -23 carries, and -24 floor cells; the -26 routed LCs
  remain below placement sensitivity.
- **Decision:** accepted as direct commit `6458450`. The source exposes one
  exact recurrence update, improves every deterministic area metric without
  an FF or EBR regression, and passes the complete H075 battery.
- **Repeat only if:** if rejected, retry only after the sample-accumulator
  width, clock/sample constants, update consumer, or mapper constant-selection
  lowering changes materially.

## Hypothesis H081

- **ID:** H081.
- **Hypothesis:** slide interpolation currently maps a 30-bit first
  accumulation consumed only at K_SL6 and a separate 26-bit second
  accumulation consumed only at K_SL8. Zero-extending the second operands and
  selecting both operand pairs before one 30-bit add should preserve both exact
  sums while allowing their mutually exclusive carry chains to share one
  physical datapath.
- **Scope:** exhaustive and symbolic proof of both full-width sums, then
  isolated synthesis of the complete registered slide consumer including the
  state selector and final table-base addition. Production `rtl/psg_seq.sv`,
  a permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  slide coefficient, product slice, carry, rounding, table word, state,
  schedule, register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped netlist
  attributes 29 carries to the 30-bit K_SL6 sum and 25 carries to the 26-bit
  K_SL8 sum before the retained 13-bit final table-base addition.
- **Changed condition versus H074:** H074 removed the low-12 carry from the
  first slide accumulation and changed a reachable published increment. H081
  drops no precision or carry; it preserves both original sums and exploits
  their already scheduled K_SL6/K_SL8 mutual exclusivity.
- **Change:** select `{crom_q, sl_rlo}` versus zero-extended `sl_uhi` and the
  corresponding 28-bit versus 26-bit multiplier result before one 30-bit add;
  consume its full first result at K_SL6 and its low 26-bit second result at
  K_SL8 exactly as before.
- **Result:** Yosys SAT proves both selected results for every value of the
  76-bit input/selector domain. In the complete registered slide consumer, the
  baseline maps to 39 LUT4s, 66 carries, and 31 flops; the candidate maps to 59
  LUT4s, 41 carries, and 31 flops. The selected-operand mux removes 25 carries
  but adds 20 LUT4s and therefore 20 deterministic floor cells.
- **Decision:** rejected before production or whole-PSG synthesis. The LC-area
  gate is already decisively worse in the complete isolated consumer;
  `rtl/psg_seq.sv` and permanent proof files remain byte-identical to H080 and
  no fidelity or route claim is warranted.
- **Repeat only if:** if rejected, retry only after slide-accumulator widths,
  K_SL6/K_SL8 scheduling, retained register boundaries, final table-base
  consumer, or mapper selected-operand lowering changes materially.

## Hypothesis H082

- **ID:** H082.
- **Hypothesis:** `sl_bhi` is last consumed as the K_SL6 multiplier operand and
  `sl_rlo` is last consumed by the K_SL6 first accumulation. Nonblocking
  assignments read both old values on that edge, so their now-dead
  `{sl_bhi[1:0], sl_rlo}` storage can capture the 18-bit first result for K_SL8
  and retire the dedicated `sl_uhi` register without changing either adder.
- **Scope:** source-use audit, arbitrary-defined-state sequential proof across
  K_SL4--K_SL8, then isolated synthesis of the complete registered slide
  consumer. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No slide
  arithmetic, coefficient, product slice, carry, rounding, table word, state,
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The dedicated
  `sl_uhi` register is 18 flops; the source audit finds no `sl_bhi`, `sl_rlo`,
  or `sl_uhi` consumer outside their K_SL4--K_SL8 production/capture path.
- **Changed condition versus H081:** H081 retained all registers and added a
  selected-operand mux to share the two adders, which cost 20 isolated floor
  cells. H082 retains both original adders and changes only the non-overlapping
  storage allocation after both source operands are consumed.
- **Change:** at the existing K_SL6 capture edge assign the exact
  `sl_u[29:12]` result to `{sl_bhi[1:0], sl_rlo}`; form K_SL8's second sum from
  that concatenation and remove `sl_uhi`.
- **Result:** the source-use audit finds the expected closed K_SL4--K_SL8
  lifetime, SAT proves the same-edge storage transform for all arbitrary source,
  product, and final-table inputs, and exhaustive permanent checking covers all
  262,144 18-bit intermediate values. The complete isolated registered
  consumer changes 39 to 59 LUT4s, 66 carries unchanged, 65 to 47 flops, 35 to
  16 unpackable flops, and floor 74 to 75. Full and PREVIEW lint pass. In the
  whole PSG, H080 to H082 changes 6,409 to 6,437 LUT4s, 1,339 to 1,335 carries,
  1,459 to 1,441 flops, 501 to 483 unpackable flops, and floor 6,910 to 6,920;
  14 EBRs are unchanged. Seed-1 routing changes 7,147 to 7,145 LCs and clocks
  134.44/32.36 to 142.57/32.72 MHz. The two-LC route change is below placement
  sensitivity and cannot offset the ten-cell deterministic floor regression.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. Production `rtl/psg_seq.sv` and permanent `tools/psg_hw_forms.py`
  are identical to H080; no render or integration claim remains.
- **Repeat only if:** if rejected, retry only after the K_SL4--K_SL8 register
  lifetimes, first-result width, source-register packing, or mapper same-edge
  overwrite lowering changes materially.

## Hypothesis H083

- **ID:** H083.
- **Hypothesis:** the live gain first optionally evaluates
  `a = x + floor(x/4)`, then always returns `a + floor(a/2)`. For boosted gain
  this is exactly `2*x - ceil(x/8) - corr`, where `corr` is one only for
  `x[2:0]` equal to 3, 6, or 7; unboosted gain remains
  `x + floor(x/2)`. Selecting the base and signed correction before one
  add/sub chain should replace the two current carry chains.
- **Scope:** exhaustive proof over all 4,096 input gains and both boost states,
  symbolic proof of the selected add/sub form, then isolated synthesis of the
  complete registered gain consumer. Production `rtl/psg_walk.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  gain input, boost predicate, multiplier request, scaling, sign, schedule,
  state, register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The current gain cone
  contains the optional 13-bit 5/4 sum followed by the 13-bit 3/2 sum.
- **Changed condition versus H017:** H017 selected old/new waveform and sign
  context before the post-multiply scale/negate consumers and regressed global
  destination covering. H083 leaves those contexts and consumers untouched;
  it targets a distinct pre-multiply arithmetic identity inside `g_live`.
- **Change:** derive the boosted residue correction from the low three gain
  bits, select `x` versus `2*x` as the base and `floor(x/2)` versus the exact
  negative boosted correction as the second operand, then use one add/sub
  carry chain.
- **Result:** exhaustive checking passes all 8,192 input/boost states and Yosys
  SAT proves the selected add/sub form over the full bit-vector domain. The
  complete registered baseline maps to 26 LUT4s, 24 carries, and 13 flops; the
  candidate maps to 47 LUT4s, 21 carries, and 13 flops.
- **Decision:** rejected before production. The exact residue correction saves
  only three carries while adding 21 deterministic LUT4/floor cells;
  `rtl/psg_walk.sv` and permanent proof files remain byte-identical to H080 and
  no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after the live-gain width/domain,
  boost predicate, multiplier-request consumer, or mapper selected add/sub
  lowering changes materially.

## Hypothesis H084

- **ID:** H084.
- **Hypothesis:** `scnt` is an eight-bit binary counter whose only observable
  values are 3 (sequencer pending-tick release), 176 (`pre_tick`), and 182
  (tick publication/reset). A 183-state prefix of an eight-bit maximal LFSR can
  preserve those exact sample events while replacing the binary increment
  carry chain with one XOR feedback bit and three constant-token decodes.
- **Scope:** exhaustive token-sequence proof, clock-for-clock recurrence/cadence
  comparison across reset and multiple tick periods, then isolated synthesis
  of the complete registered `psg_timing` consumer plus the logical-three
  decode. Production `rtl/psg_timing.sv`, the one `rtl/psg_seq.sv` consumer, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H080 battery are conditional on an isolated
  deterministic improvement. No sample rate, fractional accumulator, 183-
  sample period, pre-tick offset, tick delay, state, schedule, external
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. H080's complete
  `psg_timing` scope maps to 55 LUT4s, 29 carries, 38 flops, two unpackable
  flops, and 57 floor cells; the remaining `scnt + 1` owns a seven-carry chain.
- **Changed condition versus H008 and H070:** H008 retained binary `scnt` and
  tested sharing its two terminal equalities. H070 replaced a distinct 24-step
  divider-service count whose busy/done/control consumers caused a global
  regression. H084 targets a wider decode-only counter with exactly three
  sparse internal observable tokens and no published numeric count.
- **Change:** seed an eight-bit maximal LFSR at token `8'h01`, advance it once
  per `sample_en`, substitute the token corresponding to logical 3 at the one
  sequencer consumer, assert `pre_tick` at the logical-176 token, and reset it
  to the seed at the logical-182 token.
- **Result:** the corrected source audit finds exactly three consumers at
  logical counts 3, 176, and 182. The maximal-period proof establishes all 255
  unique LFSR states and exact tokens 08/e9/66; simulation matches 3,660 sample
  states clock-for-clock across 20 periods. The complete isolated timing plus
  logical-three consumer changes 45 to 43 LUT4s and 26 to 20 carries with its
  flops unchanged. Full hardware forms and full/PREVIEW lint pass. In the whole
  PSG, H080 to H084 changes 6,409 to 6,435 LUT4s, 1,339 to 1,333 carries,
  1,459 flops unchanged, 501 to 507 unpackable flops, and floor 6,910 to 6,942;
  14 EBRs are unchanged. Seed-1 routing changes 7,147 to 7,175 LCs and clocks
  134.44/32.36 to 136.44/32.69 MHz.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. The local two-LUT/six-carry win becomes a decisive 32-cell global
  floor and 28-LC route regression. Production `rtl/psg_timing.sv`,
  `rtl/psg_seq.sv`, and permanent `tools/psg_hw_forms.py` are identical to
  H080; no render or integration claim remains.
- **Repeat only if:** if rejected, retry only after the sample-count period,
  observable token set, counter width, timing consumer, or mapper LFSR/decode
  lowering changes materially.

## Hypothesis H085

- **ID:** H085.
- **Hypothesis:** a ceiling division currently sends `n + d - 1` through the
  24-by-8 divider. Dividing unbiased `n = q*d + r` produces the same biased
  outputs as quotient `q + (r != 0)` and remainder
  `r == 0 ? d - 1 : r - 1`. Applying that exact correction after the fixed
  recurrence should replace the two wide pre-service numerator chains with
  arithmetic bounded by the actually consumed quotient and eight-bit
  remainder.
- **Scope:** symbolic quotient/remainder identity proof for arbitrary 24-bit
  numerator and nonzero eight-bit divisor, transaction-level divider proof,
  then isolated synthesis of the complete divider plus all caller-observable
  result slices. Production `rtl/psg_divsvc.sv`, `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No
  numerator value, quotient, remainder, divisor, 24-cycle latency, start/busy
  contract, state, schedule, interface width, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped caller
  attributes 23 carries to the 24-bit numerator sum and seven more to its
  selected `d-1`, before the retained nine-carry divider subtract.
- **Changed condition versus H016 and H070:** H016 narrowed the restoring
  subtract itself and regressed globally; H070 recoded only the divider's
  iteration counter. H085 retains both the accepted subtract and binary count,
  changing only where the already-required ceiling quotient/remainder transform
  is evaluated.
- **Change:** pass unbiased `div_base` plus the ceiling flag into the divider;
  retain the flag through the transaction and expose the exact corrected
  quotient/remainder when idle, leaving non-ceiling transactions unchanged.
- **Result:** 97,920 divisor/remainder/quotient-boundary states, an all-domain
  SAT transform proof, and 1,530 complete divider transactions pass. The
  complete registered baseline maps to 84 LUT4s, 42 carries, 45 flops, eight
  unpackable flops, and floor 92. Direct combinational output correction maps
  to 93 LUT4s, 33 carries, 46 flops, nine unpackable flops, and floor 102.
  Moving the same exact correction onto the terminal recurrence edge passes a
  second 1,530 transactions but maps to 116 LUT4s, 41 carries, 46 flops, nine
  unpackable flops, and floor 125.
- **Decision:** rejected after two isolated variants, before production. The
  correction arithmetic does not pack into the existing result boundary;
  `rtl/psg_divsvc.sv`, `rtl/psg_seq.sv`, and permanent proof files remain
  byte-identical to H080, and no whole-PSG, fidelity, or route claim is
  warranted.
- **Repeat only if:** if rejected, retry only after caller result widths,
  rounding modes, remainder consumers, divider recurrence/latency, or mapper
  output-correction lowering changes materially.

## Hypothesis H086

- **ID:** H086.
- **Hypothesis:** EA5 increments `w_row` when `abank` is clear and
  `w_ins_row` when it is set. Those five-bit values and destinations are
  mutually exclusive, so selecting the source before one incrementer should
  replace two carry chains while preserving each inactive register exactly.
- **Scope:** exhaustive scalar proof and arbitrary-prior-state registered
  equivalence of both row outputs, then isolated synthesis of the complete
  paired EA5 consumer. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No row
  value, bank predicate, destination enable, EA5 branch, state, schedule,
  memory, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped netlist
  retains separate three-carry families for `w_row` and `w_ins_row`.
- **Changed condition versus H031:** H031 accepted selected operands for two
  state-exclusive byte comparators. H086 targets two different five-bit
  incrementers in the same EA5 state, using the already-required `abank`
  destination selection and leaving H031's comparator unchanged.
- **Change:** define `row_inc = (abank ? w_ins_row : w_row) + 1` and use that
  exact result in the existing clear/set destination branches.
- **Result:** exhaustive checking proves all 4,096 arbitrary current-row,
  instrument-row, bank, and destination-enable states, and SAT independently
  proves the complete registered pair. The complete isolated consumer changes
  12 to 11 LUT4s, six to three carries, and keeps ten flops. Full permanent
  forms and full/PREVIEW lint pass. In the whole PSG, H080 to H086 changes
  6,409 to 6,416 LUT4s, 1,339 to 1,332 carries, 1,459 flops unchanged, 501 to
  502 unpackable flops, floor 6,910 to 6,918, and 14 EBRs unchanged. Seed-1
  routing changes 7,147 to 7,142 LCs and clocks 134.44/32.36 to 133.69/31.94
  MHz; both clocks pass. The five-LC route reduction is below placement
  sensitivity and cannot offset the eight-cell deterministic floor regression.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. Production `rtl/psg_seq.sv` and permanent
  `tools/psg_hw_forms.py` are identical to H080; no render or integration
  claim remains.
- **Repeat only if:** if rejected, retry only after EA5 bank exclusivity, row
  width, destination ownership, or mapper selected-increment lowering changes
  materially.

## Hypothesis H087

- **ID:** H087.
- **Hypothesis:** the eight-state vibrato LFO has magnitude zero, one, two,
  one across the low two counter bits and direction in the high counter bit.
  Its magnitude is therefore exactly
  `{eff_tcnt[1] & ~eff_tcnt[0], eff_tcnt[0]}`. Using `eff_tcnt[2]` as the
  direction even at zero magnitude leaves the final add/sub result unchanged
  and should retire the signed case plus absolute-value cone.
- **Scope:** exhaustive proof of the complete final vibrato increment over all
  eight counter phases and all 8,192 pitch increments, then isolated synthesis
  of the complete registered vibrato consumer. Production `rtl/psg_seq.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  vibrato sequence, magnitude, rounding, pitch value, state, schedule,
  register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG.
- **Changed condition versus the historical vibrato quotient rewrite:** that
  experiment moved the arithmetic into a narrower published quotient and
  regressed globally. H087 preserves the accepted full-width final add/sub and
  changes only how its existing three-bit LFO phase becomes sign and magnitude.
- **Change:** replace the signed LFO case and conditional absolute value with
  the direct direction bit and two-bit magnitude expression, retaining the
  existing multiply-by-zero/one/two wiring and rounded add/sub consumer.
- **Result:** exhaustive checking passes all 65,536 staged-counter/pitch
  combinations and SAT proves the complete final increment for every 16-bit
  input tuple. The complete isolated registered consumer changes 30 to 31
  LUT4s, with 12 carries and 13 flops unchanged, under the canonical Yosys
  build.
- **Decision:** rejected before production RTL. The direct Boolean magnitude
  does not replace the mapper's optimized signed-case cone;
  `rtl/psg_seq.sv` and permanent proof files remain byte-identical to H080 and
  no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after the LFO sequence, counter
  phase width, vibrato rounding, final add/sub consumer, or mapper Boolean
  lowering changes materially.

## Hypothesis H088

- **ID:** H088.
- **Hypothesis:** after a sample edge, the registered pair `sample_en &&
  scnt == 0` holds exactly while the current dedicated `tick_en` flop is high,
  and `sample_en && scnt == 177` holds exactly while `pre_tick` is high. These
  two strobes can therefore be derived from post-edge state, removing their
  output flops without changing what any same-clock consumer observes.
- **Scope:** reachable-state and arbitrary held/sample-edge sequence proof,
  then isolated synthesis of the complete registered `psg_timing` consumer.
  Production `rtl/psg_timing.sv`, a permanent `tools/psg_hw_forms.py` check,
  whole-PSG mapping, and the complete H080 battery are conditional on an
  isolated deterministic improvement. No sample accumulator, binary counter,
  183-sample cadence, delayed-tick state, pre-tick offset, state schedule,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG.
- **Changed condition versus H008--H010 and H084:** H008 only respelled the two
  pre-edge counter comparisons; H009/H010 recoded delayed-tick state; H084
  replaced the binary counter. H088 preserves every one of those retained
  structures and tests only whether the already registered post-edge state is
  the physical storage for two same-clock output strobes.
- **Change:** continuously drive `tick_en = sample_en && scnt == 0` and
  `pre_tick = sample_en && scnt == 177`, then remove only their reset and
  sequential assignments.
- **Result:** exhaustive transition exploration closes over all 370 reachable
  timing states and 68,822 explored held/sample edges, with both outputs
  identical. SAT independently proves the post-edge identities for every
  in-range counter value. The complete isolated timing consumer changes 45 to
  48 LUT4s, 29 carries unchanged, 39 to 37 flops, three to two unpackable
  flops, and floor 48 to 50.
- **Decision:** rejected before production RTL. Only one of the two retired
  output flops is physically binding, so three new combinational cells make
  the exact derived form strictly worse. `rtl/psg_timing.sv` and permanent
  proof files remain byte-identical to H080; no whole-PSG, fidelity, or route
  claim is warranted.
- **Repeat only if:** if rejected, retry only after sample-enable registration,
  counter update order, tick/pre-tick phases, output consumers, or mapper
  registered-output lowering changes materially.

## Hypothesis H089

- **ID:** H089.
- **Hypothesis:** the clamped current pitch and clamped arpeggiated pitch are
  never consumed together. Slide setup consumes only current pitch, while the
  pitch-ROM address selects the arpeggiated value only in K_PF0 and the
  effect-6/7 K_FX/P_W0/P_W1 states. Selecting the two six-bit addends before
  one signed add-and-clamp cone should preserve both results while retiring
  the second arithmetic/clamp implementation.
- **Scope:** exhaustive proof of current, arpeggiated, and state-selected pitch
  results across the complete operand/control/state domain, symbolic proof of
  the complete selected output, then isolated synthesis of the registered
  pitch-address and slide consumers. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic floor improvement. No
  pitch value, saturation interval, previous-pitch calculation, arpeggio
  phase, effect decode, ROM address, slide arithmetic, state, schedule,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. Source and netlist audit
  finds distinct current-pitch and arpeggiated-pitch signed add/clamp cones;
  `e_pitch` reaches slide setup and non-arpeggio ROM addresses, while `e_arp`
  reaches only arpeggio-selected ROM addresses.
- **Changed condition versus H022, H046, and H048:** H022 retained all three
  raw pitch sums and replaced each clamp relation with the accepted prefix
  saturation form. H046 globally normalized effect-class decodes and H048
  factored waveform-selector axes. H089 retains those accepted/retained
  decodes and arithmetic semantics, and instead exploits the sequencer-state
  exclusivity of two pitch values before their identical add/clamp operator.
- **Change:** define whether the active ROM-address consumer needs arpeggiated
  pitch, select `arp_p` versus `w_cur_pitch` as the first operand and
  `w_cur_pitch` versus `w_ins_pitch` as the second operand under the existing
  `e_insfx` rule, then apply the existing `ins_use` add/subtract-24 and
  `pclamp` operation once. Preserve the separate previous-pitch cone and use
  the shared selected result for both slide current pitch and pitch-ROM
  address selection.
- **Result:** all 2,097,152 selected operand/control tuples and all 512
  state/effect selections pass exhaustively; unconstrained Yosys SAT proves the
  shared selected result. Permanent hardware forms pass. The complete isolated
  registered consumer changes 159 to 116 LUT4s and 40 to 28 carries with 19
  flops unchanged. Full and PREVIEW lint, Python compilation, `make test-psg`
  including 93 analysis tests and the structural PSG test, 59/59 frozen
  renders, correctly parameterized ordinary and multipumped `/4`, `/5`, and
  `/6` cadence, and `make test-clocks` pass. All eight PREVIEW checks pass
  36/38 voiced windows at both 1,275 and 159 clocks/sample for masks 7/1/2/4.
  Synthetic and Celeste recovery report no coalesced, delayed, or dropped
  samples. Four-second hardware and PREVIEW SFX-10 renders have zero `click-v1`
  events. The five-frame Celeste smoke reports 2,179/3,668 active samples,
  range -22,013..9,151, and 1,068 levels. Strict OpenSpec validation and
  `git diff --check` pass.
- **Physical result:** canonical forced H080-to-H089 HX8K mapping changes 6,409
  to 6,346 LUT4s, 1,339 to 1,324 carries, 1,459 flops unchanged, 501 to 504
  unpackable flops, 14 EBRs unchanged, floor 6,910 to 6,850, and seed-1 route
  7,147 to 7,073 LCs. Routed timing is 115.14/31.54 MHz versus 112.50/18.75
  MHz constraints; the fast margin is only 2.64 MHz. Two forced builds are
  bit-identical: JSON SHA-256
  `0a75e0feddf08fee675d1a174526d65b1a555a4e2a848de4d67d85995a70e7ad`
  and ASC SHA-256
  `bb54e280b47335f62174126dfa219e16b913bcd18c713fe47bb2e73e6ef6ddef`.
- **Decision:** accepted. It makes schedule exclusivity explicit, removes 60
  deterministic floor cells, passes every exactness/fidelity/physical gate,
  and retains 14 EBRs. The 74-LC route reduction is not treated as an
  independent robust claim.
- **Repeat only if:** retry the pitch-selection family only if sequencer state
  ownership, arpeggio effect decode, pitch-ROM consumer timing, or arithmetic
  mapper lowering changes materially.

## Hypothesis H090

- **ID:** H090.
- **Hypothesis:** with the production multiplier fixed to radix-2, its true
  fast-step count is 6 for short requests and 8, 10, 12, or 9 for normal modes
  0--3. The separately decoded slow-domain `seq_pad` count is exactly
  `ceil(req_steps / 2)`: 3, 4, 5, 6, or 5. Decoding `req_steps` once and deriving
  `seq_pad` from it should preserve both CDC deadlines while removing duplicate
  registered-load logic and simplifying the count contract.
- **Scope:** exhaustive proof over both supported radix parameters and all
  short/mode inputs, then isolated iCE40 synthesis of the complete registered
  `req_steps`/`seq_pad` load and countdown cone. Production
  `rtl/psg_mulmp.sv`, permanent hardware forms, whole-PSG mapping, and the
  complete H089 battery are conditional on a deterministic isolated floor
  improvement. No iteration count, result value, fast recurrence, CDC toggle,
  consume gap, request mode, schedule, interface, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. `psg_mulmp` currently
  spells `req_steps` and `seq_pad` as two separate mode/short ternaries.
- **Changed condition versus H006:** H006 priced a standalone direct bit
  expression for the radix-4 normal count `{4,5,6,5}` and found it one LUT4
  larger than the existing ternary. H090 does not respell that count in
  isolation: production now instantiates `RADIX_BITS=1`, exposing the exact
  cross-count relation between its radix-2 `req_steps` and preserved radix-4
  `seq_pad`, so one decoded count may feed both registered consumers.
- **Change:** define one next-step count from `RADIX_BITS`, short, and mode;
  load `req_steps` directly, and derive the matching `seq_pad` count from it
  while preserving radix-4 parameter behavior.
- **Result:** all 16 radix/short/mode tuples match exhaustively and Yosys SAT
  proves both supported radix forms for arbitrary controls. The complete
  production-radix registered load and countdown cone changes 16 to 17 LUT4s;
  three carries and seven flops are unchanged.
- **Decision:** rejected before production. The apparent source duplication is
  already cheaper than materializing the ceil-half relation in the complete
  registered cone. `rtl/psg_mulmp.sv` and permanent proof files remain
  byte-identical to H089; no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after supported radix values,
  mode/short step counts, slow consume gaps, registered-load boundaries, or
  mapper lowering changes materially.

## Hypothesis H091

- **ID:** H091.
- **Hypothesis:** music pattern completion stores both a 13-bit elapsed counter
  `pticks` and a 13-bit target `ptick_tgt`, then compares the incremented
  elapsed count with the target. The asynchronous pattern-length product is
  captured while K_FX remains stalled on `m_busy`, before the visit can reach
  W_MUS and advance `pticks`. A single 13-bit remaining-ticks counter, loaded
  from the same target and decremented/saturated at W_MUS, should therefore
  preserve the completion edge and pending-trigger delay while retiring one
  register bank and the wide elapsed-versus-target comparator.
- **Scope:** exact event-model proof across the complete 1..8,160 target range,
  launch/product replacement ordering, pending-trigger delays, and terminal
  completion behavior; symbolic equivalence of the legal counter transition;
  then isolated iCE40 synthesis of the complete registered baseline/candidate
  consumer. Production `rtl/psg_seq.sv`, permanent hardware forms, whole-PSG
  mapping, and the complete H089 battery are conditional on a deterministic
  isolated floor improvement. No pattern length, speed, trigger ownership,
  music stop/loop behavior, walk cadence, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The completion consumer
  retains 26 counter/target bits plus a 13-bit increment and comparison cone.
- **Changed condition versus H053, H058, H061--H063, H065, and H082:** those
  rows retired pipeline, replay, sample, or effect-lifetime storage and were
  rejected when reconstruction enlarged their live consumers. H091 targets a
  distinct monotone elapsed/deadline pair and relies on the already-shipped
  K_FX multiplier stall to prove the final target is installed before the
  first decrement, so no removed value is reconstructed downstream.
- **Change:** replace `pticks`/`ptick_tgt` with one remaining-ticks register;
  load the same initial/final target before W_MUS, saturate at terminal while
  trigger requests remain, and complete on the same first trigger-free tick.
- **Result:** refuted by target 8,160 with a trigger held through 8,192 tick
  advances. On the first trigger-free tick after wrap, the baseline elapsed
  count is one and its `elapsed >= target` predicate is false, while the
  candidate remaining count is saturated at zero and completes immediately.
  Repeated CPU SFX writes can keep `trig_req` nonzero for this interval, so the
  counterexample is reachable through the public interface rather than an
  unconstrained illegal state.
- **Decision:** rejected before isolated synthesis or production. Exact
  arbitrary-trigger behavior needs both the deadline and elapsed/wrap
  information; `rtl/psg_seq.sv` and permanent proof files remain byte-identical
  to H089, and no physical or fidelity claim is warranted.
- **Repeat only if:** if rejected, retry only after target-load timing, K_FX
  multiplier stall behavior, trigger-clear bound, pattern duration, counter
  wrap semantics, completion consumers, or mapper registered-state lowering
  changes materially.

## Hypothesis H092

- **ID:** H092.
- **Hypothesis:** accepted H031 time-shares one `ta_ge` comparator across EA2,
  EA4, and EA5 but retains two result flops. `froll` is written in EA2 and read
  only in immediately following EA3; `ge_lpe` is written in EA4 and read only
  in immediately following EA5. One shared predicate flop should preserve both
  values, make their non-overlapping lifetime explicit, and retire one stored
  bit without reconstructing any downstream value.
- **Scope:** exhaustive state/value transition proof and unconstrained symbolic
  equivalence of both registered consumers, then isolated iCE40 synthesis of
  the complete comparator/result/EA3/EA5 cone. Production `rtl/psg_seq.sv`,
  permanent hardware forms, whole-PSG mapping, and the complete H089 battery
  are conditional on a deterministic isolated floor improvement. No compare
  operand, row/loop result, state transition, schedule, memory, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The shared comparator
  still drives independent `froll` and `ge_lpe` flops.
- **Changed condition versus H031, H053, H063, and H068:** H031 accepted the
  shared arithmetic comparator but did not merge its disjoint registered
  results. H053/H063/H068 removed values whose downstream consumers then
  needed selection or reconstruction and regressed globally. H092 keeps the
  already-shared `ta_ge` value and replaces two adjacent-state holders with one
  holder, so no consumer-side reconstruction or new source mux is introduced.
- **Change:** replace `froll` and `ge_lpe` with one `ta_ge_r`, capture it in EA2
  and EA4, and consume it unchanged in EA3 and EA5.
- **Result:** exhaustive checking passes all four EA2/EA4 predicate histories,
  SAT equivalence passes, and the complete isolated cone improves 20->19 LUT4,
  17 carries unchanged, and 2->1 FF. The saving does not compose: canonical
  whole-PSG mapping changes 6,346->6,366 LUT4, 1,324->1,327 carries,
  1,459->1,458 FF, 504 unpackable FF unchanged, and floor 6,850->6,870.
  Seed-1 placement changes 7,073->7,098 LCs, within placement sensitivity;
  timing still passes at 129.92/32.71 MHz. Production and permanent-form edits
  are reverted byte-for-byte before fidelity gates.
- **Decision:** rejected; the isolated storage saving causes a deterministic
  whole-design LUT/carry/floor regression.
- **Repeat only if:** if rejected, retry only after EA2--EA5 state order,
  comparator operands, result consumers, register enables, or mapper flop-
  packing/lowering changes materially.

## Hypothesis H093

- **ID:** H093.
- **Hypothesis:** the DQ service coefficient is selected from only seven
  constants over the exact 32 `{wt,wave,mode}` combinations. A grouped
  `casez` truth table with the common 255/256 defaults should expose shared
  output bits more directly than the nested relational decoder and reduce the
  LUT fabric feeding the registered serial-service request.
- **Scope:** exhaustive comparison of all 64 raw selector tuples (including
  `wt` dominance), unconstrained SAT equivalence, then isolated iCE40 synthesis
  of the complete coefficient/load/first-recurrence cone. Production
  `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping, and the full
  H089 battery are conditional on a deterministic isolated floor improvement.
  No coefficient value, DQ recurrence, count, result publication, phase,
  schedule, state, memory, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. `dq_coeff` uses nested
  `wt`, waveform, and mode comparisons before loading `psg_dqsvc.start_k`.
- **Changed condition versus H021, H046, H051, and H067:** H021 priced the
  unrelated 32-arm filter table against arithmetic; H046 normalized effect
  classes globally and lost to fanout; H051 changed the DQ iteration token;
  H067 factored quotient prefixes after arithmetic. H093 changes only the
  small constant coefficient selection at the DQ request boundary, retaining
  every consumer, register, and recurrence.
- **Change:** replace the nested coefficient function in a scratch complete
  request cone with a grouped exact `casez` table and synthesize both forms.
- **Result:** exhaustive checking passes all 64 raw selector tuples and SAT
  equivalence passes. In the complete registered DQ coefficient/load/
  recurrence cone, the grouped table changes 134->137 LUT4 while 28 carries
  and 28 FF remain unchanged. The deterministic isolated floor therefore adds
  three cells. No production or permanent-proof file changed, and downstream
  gates are correctly skipped.
- **Decision:** rejected before production; the exact grouped spelling is
  locally larger than the nested decoder.
- **Repeat only if:** if rejected, retry only after the coefficient set,
  waveform/mode domain, DQ request boundary, or mapper truth-table lowering
  changes materially.

## Hypothesis H094

- **ID:** H094.
- **Hypothesis:** full-mode `blend_restart` separately compares six live/last
  fields and ORs their inequality results. Concatenating those same fields and
  evaluating one packed inequality is algebraically identical, makes the
  transition signature explicit, and may let ABC cover the shared XOR/
  reduction tree with fewer LUT4s.
- **Scope:** exhaustive structural tuple proof, unconstrained SAT equivalence,
  then isolated iCE40 synthesis of the complete restart/counter/snapshot
  consumer. Production `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG
  mapping, and the full H089 battery are conditional on a deterministic
  isolated floor improvement. No compared bit, noise-trigger term, play gate,
  counter, snapshot, waveform, arithmetic, schedule, state, memory, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The restart predicate
  uses six independent `!=` expressions before their common OR consumer.
- **Changed condition versus H031, H035, H043, and H046:** H031 time-shared
  arithmetic comparisons across sequencer phases; H035 nested common suffixes
  that Yosys already shared; H043 named EA5 predicates; H046 normalized effect
  classes with wider fanout. H094 neither shares a comparator across phases nor
  adds a reusable predicate: it exposes one existing same-cycle packed tuple
  comparison at its sole restart consumer.
- **Change:** replace the six separately ORed field inequalities in a scratch
  complete restart cone with one inequality over their exact concatenation.
- **Result:** all 64 field-equality patterns pass, SAT equivalence passes, and
  the complete isolated restart/counter cone improves 51->50 LUT4 with five
  carries and seven FF unchanged. The saving does not compose: canonical
  whole-PSG mapping changes 6,346->6,349 LUT4, 1,324->1,323 carries, 1,459 FF
  and 504 unpackable FF unchanged, and floor 6,850->6,853. Seed-1 placement
  changes 7,073->7,076 LCs, within placement sensitivity; timing passes at
  136.28/30.27 MHz. Production and permanent-form edits are reverted byte-for-
  byte before fidelity gates.
- **Decision:** rejected; the isolated one-LUT4 saving causes a deterministic
  three-LUT4/three-floor-cell whole-design regression.
- **Repeat only if:** if rejected, retry only after the transition tuple,
  restart consumer, blend-counter update, or mapper reduction lowering changes
  materially.

## Hypothesis H095

- **ID:** H095.
- **Hypothesis:** accepted H030's exact foreground trigger-length overflow
  prefix never reached the direct H089 lineage. Replacing the unsigned
  greater-than-32 comparison with its high-prefix/non-zero-suffix decode should
  retain exact saturation while removing comparator carry logic in the current
  whole-design context.
- **Scope:** exhaustive proof over all 256 input bytes, Yosys equivalence, and
  isolated synthesis of the registered six-bit saturation consumer, followed
  by production `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage,
  whole-PSG synthesis, and the complete H089 acceptance battery. No register
  value, address, state, schedule, memory, interface, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG.
- **Changed condition versus H030:** H030 was accepted on an older source
  lineage whose merge base with H089 is `e3823f5`; it was absent from H089,
  whose sequencer and mapping context changed materially. H095 therefore
  re-prices the exact same narrow mechanism rather than assuming its old
  four-LUT4/two-carry saving composes.
- **Change:** define `trg_len_over = (|di[7:6]) || (di[5] && |di[4:0])` and use
  it to select 32 versus `di[5:0]` for foreground trigger-length writes; add
  permanent exhaustive coverage for all byte values.
- **Result:** all 256 values match `min(di, 32)` and Yosys proves all six result
  bits. The isolated registered consumer remains three LUT4s/six FF while
  removing both carries. Full hardware forms, full/PREVIEW lint, Python
  compilation, `make test-psg` including 93 analysis tests and the structural
  PSG test, 59/59 frozen renders, ordinary and multipumped `/4`, `/5`, and `/6`
  cadence, and `make test-clocks` pass. All eight PREVIEW checks pass 36/38
  voiced windows at both 1,275 and 159 clocks/sample for masks 7/1/2/4.
  Synthetic and Celeste recovery report zero coalesced, delayed, or dropped
  samples. Four-second hardware and PREVIEW SFX-10 renders have zero
  `click-v1` events. The five-frame Celeste smoke reports 2,179/3,668 active
  samples, range -22,013..9,151, and 1,068 levels.
- **Physical result:** forced H089-to-H095 HX8K mapping changes 6,346 to 6,342
  LUT4s, 1,324 to 1,321 carries, 1,459 flops and 504 unpackable flops
  unchanged, 14 EBRs unchanged, floor 6,850 to 6,846, and seed-1 route 7,073
  to 7,066 LCs. Routed timing is 133.69/32.79 MHz versus 112.50/18.75 MHz
  constraints. Two forced builds are bit-identical: JSON SHA-256
  `e4b26eb1cc4150a090811d8212c9ce0f62336d8f4d5d7e67238456c56ead1bf0`
  and ASC SHA-256
  `ed29d5d010a9a94015a197fc506ffea119090be1b9da66aa549aad38c23cdc17`.
- **Decision:** accepted as direct commit `3d7a2e2`. It preserves the source-
  exact saturation contract, removes four deterministic floor cells, passes
  every proof/fidelity/physical gate, and retains 14 EBRs. The seven-LC route
  reduction is not treated as an independent robust claim.
- **Repeat only if:** retry only after the trigger-length write consumer,
  comparator-sharing context, or mapper lowering changes materially.

## Hypothesis H096

- **ID:** H096.
- **Hypothesis:** `tch_seen` only remembers that the current pattern launch has
  already accepted its left-most launched non-looping channel. At that event,
  `ptick_seen` has necessarily already latched the left-most launched channel's
  default speed, and no later `launched` bit can affect either pattern pacing
  result. Consuming the launch worklist by clearing `launched` at the accepted
  pattern-length request should therefore retire `tch_seen` and its high-fanout
  compare/control cone while making the one-shot ownership explicit.
- **Scope:** symbolic/exhaustive proof of the complete T_NL launch/pacing state
  transition, followed by isolated and whole-PSG mapping. Production
  `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage, and the complete
  merged-main acceptance battery are conditional on an early deterministic
  mapped improvement. No pattern selection, channel ordering, speed/row value,
  multiplier request, state schedule, memory, interface, EBR, R.84 executor,
  diagnostic ARAM, or tolerance change.
- **Baseline:** merged clean `main` commit `a84dbff`: canonical forced HX8K
  6,395 LUT4s, 1,321 carries, 1,460 flops, 506 unpackable flops, 14 EBRs,
  6,901-cell floor, seed-1 7,120 routed LCs; 140.92 MHz fast and 32.41 MHz PSG.
- **Changed condition versus H031 and H095:** H031 shared T_NL's byte comparator
  with another state-exclusive relation, while H095 changed an unrelated CPU
  trigger-length saturation spelling. H096 preserves those accepted arithmetic
  forms and instead retires the separate persistent one-shot state by consuming
  the already-existing launch worklist after its final live use.
- **Change:** remove `tch_seen`; define the T_NL pattern-length request from the
  current `launched[c]` bit and the accepted shared relation; when that request
  fires, clear `launched` while queueing `ptick_pend`. Add permanent proof that
  the old and new protocols issue identical requests and pacing updates over
  every launch/order/qualifier state admitted by the four-channel scan.
- **Result:** the permanent form exhausts all 256 four-channel launch/qualifier
  masks and preserves the request trace, fallback source, `ptick_seen`, and
  pending-product outcome. Full forms, full/PREVIEW lint, Python compilation,
  the default H095-bound R.84 model, `make test-psg` including 93 analysis tests
  and the structural PSG test, and the 59/59 frozen renders pass. Ordinary and
  multipumped `/4`, `/5`, and `/6` cadence passes at 572/1,275, 572/1,020, and
  572/850 ordinary sample clocks and 524/1,275, 524/1,020, and 524/850
  multipumped sample clocks; tick windows are 5,757/7,654, 4,737/6,123, and
  4,056/5,103 ordinary, and 5,709/7,654, 4,689/6,123, and 4,008/5,103
  multipumped, with zero late flips. Clock-divider checks pass. All eight
  Celeste music-0 PREVIEW checks at 1,275 and 159 clocks/sample for masks
  7/1/2/4 pass at 25/27 voiced windows (93%). Music-30 has no stable pitch
  windows on merged main, but H096's four-second PREVIEW WAV is byte-identical
  to clean `a84dbff` at SHA-256 `c4f2179d...`. Synthetic and Celeste recovery
  report zero coalesced, delayed, or dropped samples. Four-second hardware and
  PREVIEW SFX-10 renders have zero `click-v1` events. The five-frame Celeste
  smoke reports 2,079/3,668 active samples, range -21,544..7,711, and 1,014
  levels. Strict OpenSpec, diff and scope checks pass.
- **Physical result:** two forced HX8K builds reproduce JSON SHA-256
  `da8f01f61f5b915cea2f73dad6d87c6f1dc762edf6ce490989fbb3f354b55772`
  and ASC SHA-256
  `519dabc769d00349bf006af63dfa6232ac417aa00c830ae397d472a47df46d00`.
  Merged main to H096 changes 6,395 to 6,364 LUT4s, 1,321 carries unchanged,
  1,460 to 1,459 flops, 506 to 509 unpackable flops, 14 EBRs unchanged, floor
  6,901 to 6,873, and seed-1 route 7,120 to 7,095 LCs. Routed timing improves
  from 140.92/32.41 to 151.17/33.09 MHz versus 112.50/18.75-MHz constraints.
  The 31-LUT4, one-FF, and 28-floor reductions are deterministic; the 25-LC
  route reduction remains below placement sensitivity and is not overclaimed.
- **Decision:** accepted as generic RTL/proof commit `a647185`. I002 now
  satisfies the required R.84 source-certificate and C2-C-C live-value rebind;
  H096 changes no R.84 executor artifact and starts no B2 work.
- **Repeat only if:** retry this launch-worklist/state family only if music
  channel ordering, T_NL visitation, pacing fallback ownership, launched-bit
  consumers, or multiplier-request scheduling changes materially.

## Hypothesis H097

- **ID:** H097.
- **Hypothesis:** `ml_cpu` records only which path entered `ML_STOP`. Every
  automatic entry from `W_MUS` or its `MS_RD/MS_CK` loop-back scan is dominated
  by `walk_tick=1`, and the CPU-launch entry from `S_IDLE` can write
  `walk_tick=0`. No state between either entry and `ML_STOP` changes that bit,
  so the existing `walk_tick` register can select immediate versus delayed
  music stops and the dedicated provenance flop can be retired.
- **Scope:** exact transition/source-closure proof over every `ML_STOP` entry,
  an isolated registered provenance consumer, then `rtl/psg_seq.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H096 battery only after an isolated deterministic win. No launch worklist,
  pattern pacing, audio value, state-memory layout, schedule, interface, EBR,
  diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H096 and the lifetime DNR families:** H096 changes
  the launched-channel worklist and pacing-owner state; R.40--R.42 and
  R.76--R.79 alias arithmetic/service payload storage. H097 changes neither.
  It reuses a controller bit only after its tick-walk meaning has already
  selected the automatic music-completion path and proves all entry paths
  before changing production RTL.
- **Change:** scratch proof and measured production probe removed `ml_cpu`, wrote `walk_tick=0` when `S_IDLE` claimed
  a CPU music launch, retain the already-one bit across automatic completion
  and loop-back scan, and select `mus_stop(2'd2)` exactly when `walk_tick` is
  one at `ML_STOP`.
- **Result:** 603 direct, loop-back scan, and held-path cases preserve the
  immediate/delayed stop class. The complete isolated provenance consumer
  falls from six to three LUT4s and two to one FF. Canonical whole-PSG mapping
  instead changes 6,364 to 6,382 LUT4s, 1,321 to 1,325 carries, 1,459 to 1,458
  flops, 509 to 508 unpackable flops, floor 6,873 to 6,890, and seed-1 route
  7,095 to 7,115 LCs. Timing passes at 136.50/32.82 MHz, but all authoritative
  area gates except FF count regress.
- **Decision:** rejected after whole-PSG synthesis. Production RTL and the
  conditional permanent proof are reverted byte-for-byte; no fidelity gate or
  accepted area claim remains.
- **Repeat only if:** if rejected, retry only after `ML_STOP` entry topology,
  `walk_tick` lifetime, CPU-launch arbitration, loop-back scan, stop classes,
  or mapper sequential lowering changes materially.

## Hypothesis H098

- **ID:** H098.
- **Hypothesis:** the multi-pumped multiplier needs exactly 3, 4, 5, 6, 8,
  9, 10, or 12 active fast-clock steps across its two supported radix
  parameters. Each duration can be a start point on one four-bit maximal-LFSR
  segment ending at terminal state one, with zero retained as idle. A shift
  plus one XOR should replace the private binary decrement carry chain without
  changing any request, product, acknowledge, or slow-domain busy clock.
- **Scope:** exhaustive token/duration proof, transaction equivalence for both
  radix parameters and all request modes, isolated synthesis of the complete
  registered count/load/terminal consumer, then `rtl/psg_mulmp.sv`, permanent
  multiplier proofs, whole-PSG mapping, and the complete H096 battery only
  after an isolated deterministic win. No multiplier recurrence, operand,
  product, CDC synchronizer, request/acknowledge edge, sequencer padding,
  schedule, interface, EBR, diagnostic ARAM, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H006, H051, H070, and H090:** H006 and H090
  respelled or shared the loaded duration decoder while retaining binary
  decrement; H051 accepted a separate three-bit fixed-five-step DQ token;
  H070's 24-state divider token was tested in a different service. H098 keeps
  both existing duration decoders and `seq_pad` independent, changing only the
  four-bit fast-domain multiplier iteration representation across its actual
  variable duration set.
- **Change:** the measured production probe used the primitive four-bit
  `x^4+x^3+1` maximal-LFSR recurrence,
  bind each legal duration to the unique start token that reaches one on its
  final active edge, and retain the current terminal acknowledge action.
- **Result:** 418,608 radix/mode/freeze traces preserve every busy and terminal
  edge for both supported masks; the selected `x^4+x^3+1` form passes all
  6,020 two-radix CDC transactions. Its complete isolated count consumer falls
  from 14 to ten LUT4s and two to zero carries, with five FF unchanged.
  Canonical whole-PSG mapping instead changes 6,364 to 6,384 LUT4s, 1,321 to
  1,319 carries, 1,459 flops unchanged, 509 to 508 unpackable flops, floor
  6,873 to 6,892, and seed-1 route 7,095 to 7,111 LCs. Timing passes at
  137.14/32.70 MHz, but every authoritative area metric except carries
  regresses.
- **Decision:** rejected after whole-PSG synthesis. Production multiplier,
  transaction bench, and conditional permanent proof are reverted byte-for-
  byte; no fidelity gate or accepted area claim remains.
- **Repeat only if:** if rejected, retry only after legal multiplier duration
  set, fast recurrence, terminal acknowledge, radix parameter, request-load
  decoder, or mapper sequential lowering changes materially.

## Hypothesis H099

- **ID:** H099.
- **Hypothesis:** `w_ch_{damp,rev,det,buzz,noiz}` is the effective filter tuple
  only while a custom instrument is active. On trigger without an instrument
  and on an instrument-to-ordinary-note exit, the tuple is synchronously
  rewritten from `w_bf_*` and later published unchanged. Selecting `w_bf_*`
  at `P_W2` whenever `w_ins_on=0` should remove both eight-bit register-write
  arms while retaining the stored effective tuple and all instrument maxima.
- **Scope:** exhaustive tuple/transition/publication proof over trigger,
  ordinary-note, retained-instrument, and new-instrument paths; isolated
  synthesis of the complete registered eight-bit filter/publication consumer;
  then `rtl/psg_seq.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H096 battery only after an isolated deterministic
  win. No filter code, trit maximum, base/instrument precedence, active-bank
  storage, publication format, schedule, interface, EBR, diagnostic ARAM,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H045 and the lifetime DNR families:** H045 kept
  all tuple writes and only respelled the three trit maxima, mapping
  identically in isolation. H099 retains those relational maxima and every
  stored bit. It changes ownership of two redundant base-copy writes and the
  publication source, not an arithmetic/service payload lifetime alias.
- **Change:** select `w_bf_*` at publication when `w_ins_on=0`. Variant one
  removes the base-copy assignments in both `T_SP` and ordinary `K_LD`;
  variant two restores `T_SP` initialization and removes only the ordinary
  `K_LD` exit writes.
- **Result:** the transition proof passes all 4,224 legal two-operation paths,
  and the complete isolated registered consumer improves from 29 to 12 LUT4s
  with 17 FF unchanged. Variant one maps at 6,371 LUT4s / 1,321 carries /
  1,459 FF / 508 unpackable / floor 6,879 and routes at 7,100 LCs with
  144.30/32.26 MHz timing: +7 LUT4s, -1 unpackable, +6 floor cells, and +5
  routed LCs versus H096. Variant two maps at 6,398 LUT4s / 1,322 carries /
  1,459 FF / 509 unpackable / floor 6,907 and routes at 7,128 LCs with
  131.10/31.89 MHz timing: +34 LUT4s, +1 carry, +34 floor cells, and +33
  routed LCs. Both pass timing but fail every authoritative deterministic area
  gate except FF count.
- **Decision:** rejected after the two permitted whole-PSG variants; production
  RTL and the conditional permanent form are reverted byte-for-byte.
- **Repeat only if:** if rejected, retry only after filter tuple ownership,
  instrument-active state, trigger/exit topology, publication source, stored
  effective tuple, or mapper register-enable lowering changes materially.

## Hypothesis H100

- **ID:** H100.
- **Hypothesis:** only CPU foreground slots can execute the sole
  `released[...] <= 1` assignment. Music-slot triggers clear their dynamic
  array element, but music slots can never make it non-zero. Restricting
  `released` to four foreground bits and treating every music slot as not
  released should remove four unreachable FFs and the upper dynamic-write
  targets without changing loop/release behavior.
- **Scope:** exhaustive state-transition proof across reset, trigger clear,
  simultaneous CPU release, foreground/music slot selection, instrument-bank
  selection, and the EA5 loop predicate; isolated synthesis of the complete
  registered state/consumer; then `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` invariant, canonical whole-PSG synthesis, and the
  complete H096 battery only after deterministic isolated and global wins. No
  release command, loop condition, trigger ordering, slot count, schedule,
  interface, EBR, diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus lifetime/storage DNR families:** H037 tested a
  combinationally dead detune source bit; H062/H063 reconstructed live stored
  waveform/noise values; H092 merged two reachable result flops. H100 instead
  removes four array elements with no set transition and retains every
  reachable foreground bit plus the exact same-edge CPU-write precedence.
- **Change:** in the scratch consumer, replace the eight-entry `released`
  array with four
  foreground entries, clear it only on foreground trigger, and make the EA5
  release guard true for every music slot.
- **Result:** exhaustive induction covers 2,560 reset-reachable combinations
  of current foreground state, foreground/music slot, trigger clear,
  same-edge CPU release, and instrument-bank loop selection. The production
  JSON contains only `released[0]` through `released[3]`: Yosys already proves
  the four music elements constant. Source-matched isolated reference and
  explicit four-entry candidate both map to 17 LUT4s / zero carries / four
  FFs.
- **Decision:** rejected before production RTL because the desired state and
  logic pruning is already present in the mapped netlist; no permanent form or
  production file changed.
- **Repeat only if:** if rejected, retry only after slot partitioning, CPU
  release addressing, trigger ordering, loop/release semantics, or mapper
  dynamic-array lowering changes materially.

## Hypothesis H101

- **ID:** H101.
- **Hypothesis:** the four foreground `trg_row` and `trg_len` arrays consume 44
  unpackable FFs even though the engine holds `c[1:0]` stable throughout the
  eight-cycle `V_LD` prelude before `T_FL`. A four-entry block RAM can prefetch
  both pending fields without a new state; eight resettable valid bits retain
  the current reset/consume-to-zero contract. One EBR plus eight FFs should
  reduce the deterministic LC floor materially.
- **Scope:** isolated synthesis of the complete CPU-write, synchronous-read,
  valid-bit, consume-clear, and row/length output consumer; exact proof of
  reset, read-address settling, independent field writes, consume, and
  same-edge CPU-write precedence; then `rtl/psg_seq.sv`, permanent
  `tools/psg_hw_forms.py` schedule/transition checks, canonical whole-PSG
  synthesis, and the complete H096 battery only after deterministic isolated
  and global wins. At most two memory spellings. No trigger value/clamp,
  command ordering, channel mapping, `T_FL` cadence, state-memory layout,
  diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks. `trg_row` and
  `trg_len` account for 20 and 24 unpackable FFs respectively.
- **Changed condition versus state-memory DNR families:** none. The initial
  active-index audit compared only H019 and missed legacy R.44, which had
  already tested this exact pending-trigger EBR migration with valid bits,
  `V_LD` prefetch, and CPU collision bypass. H101's isolated result independently
  reproduces R.44's reason for rejection and closes the indexing gap.
- **Change:** pack row and length into one four-entry synchronous RAM;
  use independent per-field write masks if they infer one EBR, otherwise test
  two narrow EBRs as the sole fallback. Clear only valid bits at consumption.
- **Result:** the source FF consumer maps at 53 LUT4s / zero carries / 44 FFs /
  44 unpackable / zero EBRs, for a 97-cell floor. A plain packed EBR maps at
  44 LUT4s / two carries / 36 FFs / 26 unpackable / one EBR, for a 70-cell
  floor, but its registered read returns the old field for one cycle after a
  same-address CPU write. A concrete previous-cycle-write/`T_FL` trace gives
  reference row 2 and RAM row 1. The required shared `{field,slot,data}`
  write-through state maps at 78 LUT4s / two carries / 46 FFs / 29 unpackable /
  one EBR, floor 107. The two-EBR fallback maps at 75 LUT4s / two carries /
  46 FFs / 29 unpackable / two EBRs, floor 104. Both exact forms are locally
  larger than the FF reference.
- **Decision:** rejected before production RTL; no permanent form or
  production file changed. Do not repeat R.44/H101 unless its explicit repeat
  condition is met.
- **Repeat only if:** if rejected, retry only after trigger register semantics,
  CPU/engine ordering, `V_LD` prefetch cadence, iCE40 RAM write-mask inference,
  EBR budget, or mapper memory lowering changes materially.

## Hypothesis H102

- **ID:** H102.
- **Hypothesis:** `w_ins_bass` is consumed only when `w_ins_wt=1`. In that
  mode, I_TR4 forces `w_ins_fx=0`, `ins_use=0`, and every effect consumer
  ignores `w_ins_fx`; in non-wavetable mode bass is ignored and I_LD supplies
  the real effect. Encoding bass in `w_ins_fx[0]` should retire one working FF
  while keeping the record reload and all externally visible values exact.
- **Scope:** exhaustive mode/trigger/note/store/reload proof; isolated synthesis
  of the complete registered bass/effect load/store/publication consumer; then
  `rtl/psg_common.svh`, `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, canonical whole-PSG synthesis, and the complete
  H096 battery only after deterministic isolated and global wins. No wavetable
  bass behavior, custom-instrument effect, state address/width, schedule,
  interface, EBR, diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus storage/lifetime DNR families:** H082 aliased two
  wide slide pipeline roles and paid a new D-input/fanout mux. H102 encodes one
  Boolean in an existing field that is semantically fixed at zero in the only
  mode where the Boolean is observable; the same three-bit field and record
  word already survive across every required boundary.
- **Change:** capture bass in `w_ins_fx[0]`; for wavetable instruments
  retain it while clearing the upper effect bits, publish bass from that bit,
  and use the same bit in record word 3 so record word 9 reload remains the
  authoritative complete effect/encoded-bass field.
- **Result:** the permanent form exhausts all 1,024 old/new mode, bass, effect,
  store, and reload tuples. The complete isolated registered consumer improves
  from 21 LUT4s / five FFs to 18 LUT4s / four FFs. Full forms, full/PREVIEW
  lint, Python compilation, the default H095-bound R.84 model, `make test-psg`,
  and all 59 frozen renders pass. Ordinary `/4`, `/5`, and `/6` cadence remains
  572 clocks, while multipumped cadence remains 524 clocks; all six tick
  windows retain zero late flips. Clock-divider checks pass. All eight explicit
  Celeste music-0 PREVIEW checks at 1,275 and 159 clocks/sample for masks
  7/1/2/4 pass at 25/27 voiced windows (93%). Synthetic and Celeste recovery
  report zero coalesced, delayed, or dropped samples. Four-second hardware and
  PREVIEW SFX-10 renders have zero `click-v1` events. A freshly rebuilt
  five-frame Celeste smoke reports 2,079/3,668 active samples, range
  -21,544..7,711, and 1,014 levels; its compile uses the same
  `WIDTHTRUNC` waiver as the PSG gates because the console target omits that
  waiver for three pre-existing `psg_walk` warnings. Strict OpenSpec, diff, and
  scope checks pass.
- **Physical result:** two forced HX8K builds reproduce JSON SHA-256
  `1b48d1ca5a757c47088dfec051651d2b018c9a4aee166b4881dae8fb6fad7cd9`
  and ASC SHA-256
  `008a579edd06b6503363f9cddb1b93600db2f034a1328f20b5538162a5b78f09`.
  H096 to H102 changes 6,364 to 6,360 LUT4s, 1,321 carries unchanged, 1,459 to
  1,458 flops, 509 to 508 unpackable flops, 14 EBRs unchanged, floor 6,873 to
  6,868, and seed-1 route 7,095 to 7,087 LCs. Routed timing changes from
  151.17/33.09 to 140.92/32.65 MHz versus 112.50/18.75-MHz constraints. The
  four-LUT4, one-FF, one-unpackable, and five-floor reductions are deterministic;
  the eight-LC route reduction remains below placement sensitivity and is not
  overclaimed.
- **Decision:** accepted as generic RTL/proof commit `ccfb2a0`. Because H102
  changes both `rtl/psg_common.svh` and `rtl/psg_seq.sv`, the companion must
  regenerate its source certificate and C2-C-C live-value lineage before
  integration; H102 makes no R.84/B2 proof or integration claim.
- **Repeat only if:** if rejected, retry only after wavetable/effect mode
  exclusivity, record packing, trigger stage ordering, effect consumers, or
  mapper D-input lowering changes materially.

## Hypothesis H103

- **ID:** H103.
- **Hypothesis:** H096 leaves the launch mask unchanged until the first
  non-looping pacing owner and then clears it completely. Because T_NL visits
  music slots in ascending order, a marked channel with no lower marked music
  slot is exactly the first launched channel and therefore the unique fallback-
  speed owner. Deriving that priority certificate from the existing mask should
  retire `ptick_seen` without adding state or changing pacing.
- **Scope:** exhaustive launch/qualifier/scan proof over all 256 masks;
  isolated synthesis of the complete registered launch/pacing consumer; then
  `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage, canonical
  whole-PSG synthesis, and the complete H102 battery only after deterministic
  isolated and global wins. No pattern speed/length, channel order, launch
  mask, multiplier request, schedule, interface, memory, EBR, diagnostic ARAM,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus H096's launch-worklist/state family:** H096 is now
  accepted and permanently proves that the mask remains intact before the
  owner and becomes zero after it. H103 consumes that new post-H096 mask
  contract to replace the separate fallback one-shot; it does not retry the
  accepted request-ownership transform or a rejected spelling.
- **Change:** in an isolated probe, replace `!ptick_seen` with an exact lower-
  launch-prefix predicate for music slots 4--7 and remove the flag's reset,
  set, and launch-clear assignments.
- **Result:** exhaustive evaluation passes all 256 launch/qualifier masks. The
  complete registered launch/pacing consumer changes from 26 LUT4s and 18 FFs
  to 28 LUT4s and 17 FFs. Retiring the flag therefore costs two LUT4s and fails
  the deterministic isolated area gate; no production RTL, permanent proof,
  whole-PSG synthesis, or fidelity run is warranted.
- **Decision:** rejected before production; the probe remains ignored under
  `build/experiments/h103/`, and no production or permanent-proof residue
  remains.
- **Repeat only if:** if rejected, retry only after music-slot ordering, T_NL
  visitation, launch-mask clearing, fallback-speed ownership, or mapper dynamic-
  index/prefix lowering changes materially.

## Hypothesis H104

- **ID:** H104.
- **Hypothesis:** the instrument working state has only three legal kinds:
  ordinary note/off, custom-SFX instrument, and wavetable instrument. The
  current `{w_ins_on,w_ins_wt}` code makes the latter two hot predicates
  `w_ins_on & ~w_ins_wt` and `w_ins_on & w_ins_wt`. Storing those predicates
  directly as one-hot `{w_ins_wt,w_ins_use}` should keep the same two state bits
  while removing repeated decoding and simplifying the record contract.
- **Scope:** exhaustive kind-transition and store/reload proof; isolated
  synthesis of the complete registered kind/record/publication consumer; then
  `rtl/psg_common.svh`, `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py`
  coverage, canonical whole-PSG synthesis, and the complete H102 battery only
  after deterministic isolated and global wins. No instrument semantics,
  record width, effect priority, publication payload, schedule, interface,
  memory/EBR count, diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus H100 and lifetime DNR families:** H100 partitioned
  a release array whose dead music entries Yosys already pruned. H104 changes
  neither array topology nor lifetime aliasing; it re-encodes a live three-state
  scalar protocol so the two existing mutually exclusive consumers become the
  stored bits themselves.
- **Change:** in an isolated probe, replace stored `w_ins_on` with `w_ins_use`, retain
  `w_ins_wt`, derive `w_ins_on = w_ins_use | w_ins_wt`, and store/reload the
  one-hot pair without changing record width or visible publication values.
- **Result:** 53,254 exhaustive transition, record, mode-control, and boundary-
  data checks pass. The complete registered kind/record/publication consumer
  changes from 138 LUT4s, eight carries, and two FFs to 139 LUT4s, eight carries,
  and two FFs. Direct mode predicates do not repay the derived `on` decode and
  changed state-input mux, so the candidate fails the deterministic isolated
  area gate; no production RTL, permanent proof, whole-PSG synthesis, or
  fidelity run is warranted.
- **Decision:** rejected before production; all probe files remain ignored
  under `build/experiments/h104/`, and no production or permanent-proof residue
  remains.
- **Repeat only if:** if rejected, retry only after instrument-kind reachability,
  trigger/fetch transitions, record packing, mode consumers, or mapper decode
  sharing changes materially.

## Hypothesis H105

- **ID:** H105.
- **Hypothesis:** the record-transfer counter `vcnt` is declared four bits, but
  V_LD resets at 7 and V_ST resets at 4; every load/store address helper and
  record-pack selector therefore consumes only values 0--7. The H102 netlist
  still contains four `vcnt` flip-flops and high-bit D logic. Narrowing the
  protocol and helper inputs to three bits should retire real mapped state and
  simplify the counter without changing any visited word or hold behavior.
- **Scope:** exhaustive V_LD/V_ST/hold transition and address proof; isolated
  synthesis of the complete registered counter/address/record-select consumer;
  then `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage, canonical
  whole-PSG synthesis, and the complete H102 battery only after deterministic
  isolated and global wins. No schedule state, transfer count, record layout,
  address value, hold/replay contract, interface, memory/EBR count, diagnostic
  ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus H007, H014, H037, and H065:** H007 accepted a
  clock-derived arithmetic width; H014/H037 found source bits that Yosys already
  pruned; H065 contracted live sample payloads and globally regressed. H105
  targets a separately mapped control flop whose complete reachable protocol
  is bounded by explicit terminal states, not a data-range estimate.
- **Change:** in an isolated probe, narrow `vcnt`, `tick_issue`, and the two tick-word helper
  inputs/constants from four to three bits while preserving every state update
  and address value.
- **Result:** 960 exhaustive V_LD/V_ST, bank, hold, address, selector, terminal,
  and repeated hold-pattern checks pass. The complete registered counter,
  address, and record-select consumer changes from 81 LUT4s, three carries, and
  four FFs to 105 LUT4s, one carry, and three FFs. The one-FF/two-carry saving
  does not offset 24 added LUT4s, so the candidate fails the deterministic
  isolated area gate; no production RTL, permanent proof, whole-PSG synthesis,
  or fidelity run is warranted.
- **Decision:** rejected before production; all probe files remain ignored
  under `build/experiments/h105/`, and no production or permanent-proof residue
  remains.
- **Repeat only if:** if rejected, retry only after V_LD/V_ST terminal counts,
  hold compensation, tick-word addressing, record packing, or mapper counter
  lowering changes materially.

## Hypothesis H106

- **ID:** H106.
- **Hypothesis:** main's later diagnostic ARAM composition added a second
  `wraddr <= wraddr + 1` branch after the upload-data branch. CPU writes retain
  priority, so exactly one predicate covers both cases: address `$02` on a CPU
  write, or a diagnostic read when no CPU write is active. Factoring that
  transaction should expose one pointer update/enable path and simplify the
  source while preserving the write side effect and H005 address transform.
- **Scope:** exhaustive pointer/control/address-class transition proof;
  isolated synthesis of the complete registered pointer and memory-write
  consumer; then `rtl/psg_aram.sv`, permanent `tools/psg_hw_forms.py` coverage,
  canonical whole-PSG synthesis, and the complete H102 battery only after
  deterministic isolated and global wins. No upload index/window, pointer
  value, CPU priority, memory write, diagnostic read, ARAM replay/hold,
  interface, EBR count, R.84 executor, or tolerance change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus H005 and H050:** those experiments predate main's
  diagnostic CPU-read auto-increment and changed only the upload index/window
  transform. H106 retains accepted H005 exactly and factors the newly composed
  mutually exclusive pointer-update branches around it.
- **Change:** defined one priority-correct upload-advance predicate,
  perform the optional address-$02$ memory write inside that transaction, and
  retain address-$00/$01$ partial pointer writes in the non-advance CPU-write
  arm.
- **Result:** exhaustive checking passes all 6,291,456 pointer/control/data
  transitions, the ARAM hold test passes, and the Verilator readback verifies
  all 4,608 actual bytes through `$42ff`. The complete registered pointer/write
  consumer falls from 51 to 49 LUT4s with 17 carries and 16 FF unchanged; full
  and PREVIEW lint pass. Canonical forced HX8K mapping then changes H102's
  6,360 LUT4 / 1,321 carry / 1,458 FF / 508 unpackable / 14 EBR / floor 6,868 /
  7,087 routed LCs to 6,411 / 1,321 / 1,458 / 509 / 14 / floor 6,920 / 7,141.
  Both clocks still pass at 148.70/30.71 MHz. The complete fidelity battery is
  skipped because the deterministic LUT/floor and placement gates fail.
- **Decision:** rejected and reverted. Production RTL and permanent proof are
  restored exactly; ignored evidence remains under `build/experiments/h106/`.
- **Repeat only if:** if rejected, retry only after CPU-write/read priority,
  diagnostic pointer semantics, pointer update consumers, or mapper enable/mux
  lowering changes materially.

## Hypothesis H107

- **ID:** H107.
- **Hypothesis:** `psg_seq` stores eight playback-active bits in the unpacked
  `playing[]` array, then continuously repacks the same bits into the exported
  `play_bits` vector. Internal and external consumers dynamically index those
  two source spellings. Making `play_bits` the sole packed register should
  remove the redundant representation, simplify the RTL, and may give Yosys a
  cheaper common mux/storage form.
- **Scope:** replace only `playing[i]`, `playing[c]`, and `playing[fg_sl]` with
  the identically indexed `play_bits` storage and remove the repacking assign;
  then canonical whole-PSG synthesis before any broader proof/fidelity battery.
  No playback transition, status/debug output, slot selection, trigger, stop,
  release, R.84 executor, image, Tang, tolerance, or interface change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus H100:** H100 restricted unreachable elements of
  the separate `released[]` array, which Yosys already pruned. H107 instead
  removes the live unpacked-to-packed alias used by both dynamic internal
  indexing and module outputs; no state domain is restricted.
- **Change:** used the output `play_bits` vector itself as the canonical
  eight-bit playback register and eliminate `playing[]` plus its repacking
  assignment.
- **Result:** full and PREVIEW lint pass. Canonical forced HX8K mapping changes
  H102's 6,360 LUT4 / 1,321 carry / 1,458 FF / 508 unpackable / 14 EBR /
  floor 6,868 / 7,087 routed LCs to 6,439 / 1,323 / 1,458 / 502 / 14 /
  floor 6,941 / 7,166. Both clocks still pass at 151.17/33.76 MHz. The six-
  unpackable-FF improvement does not offset 79 added LUT4s, two carries, 73
  floor cells, or 79 routed LCs, so the complete fidelity battery is skipped.
- **Decision:** rejected and reverted. `psg_seq.sv` is restored exactly;
  ignored synthesis evidence remains under `build/experiments/h107/`.
- **Repeat only if:** if rejected, retry only after the playback-state domain,
  dynamic slot consumers, module interface, or Yosys array/vector lowering
  changes materially.

## Hypothesis H108

- **ID:** H108.
- **Hypothesis:** the HX8K target deliberately instantiates `REVERB=0`, and
  Yosys already proves both zero-ring comb expressions equal their dry inputs.
  The live/prior reverb-mode comparison nevertheless remains in
  `blend_restart`, retaining disabled-feature control and record state. Gating
  only that comparison with the elaboration-time `REVERB` parameter should
  remove the surviving control cone while leaving `REVERB=1` textually exact.
- **Scope:** add only `REVERB &&` to the reverb-mode inequality in
  `blend_restart`; first run canonical whole-PSG synthesis. If mapping improves,
  prove current-versus-candidate `REVERB=0` PCM byte equivalence across focused
  mode transitions and the complete render corpus before any acceptance claim.
  No enabled-reverb datapath, ring contents/address, blend arithmetic, other
  restart predicate, schedule, state layout, R.84 executor, image, Tang,
  tolerance, or interface change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus R.26 and H079:** R.26 established that the two
  zero-ring comb datapaths are already mapper identities; H079 respelled
  enabled reverb rounding. H108 changes neither. It targets the separate mode-
  change restart predicate that survives only because disabled reverb state is
  still treated as audibly relevant.
- **Change:** qualified `s_ch_rev != last_rev_r` with `REVERB` inside the
  otherwise unchanged restart predicate.
- **Result:** full, PREVIEW, and explicit `REVERB=0` lint pass. Canonical forced
  HX8K mapping changes H102's 6,360 LUT4 / 1,321 carry / 1,458 FF /
  508 unpackable / 14 EBR / floor 6,868 / 7,087 routed LCs to 6,399 / 1,325 /
  1,458 / 509 / 14 / floor 6,908 / 7,134. Both clocks still pass at
  144.80/32.83 MHz. The deterministic mapping and placement gates fail, so
  focused and complete `REVERB=0` PCM equivalence work is not warranted.
- **Decision:** rejected and reverted. `psg_walk.sv` is restored exactly;
  ignored synthesis evidence remains under `build/experiments/h108/`.
- **Repeat only if:** if rejected, retry only after the `REVERB=0` contract,
  blend-restart consumers, prior-tuple state, or mapper parameter folding
  changes materially.

## Hypothesis H109

- **ID:** H109.
- **Hypothesis:** Yosys explicitly reports that it does not mark the sequencer's
  60-state, six-bit `sst` register for automatic FSM recoding because its
  heuristic predicts no benefit. The state nevertheless drives a large number
  of equality-selected next-state and datapath cones. Forcing one-hot encoding
  may trade roughly 54 extra flops for a larger LUT/decode reduction and a
  lower iCE40 logic-cell floor.
- **Scope:** add only a Yosys `fsm_encoding="one-hot"` attribute to `sst`; run
  canonical whole-PSG mapping and judge `LUT4 + unpackable FF` before any long
  correctness battery. No state transition, numeric enum value consumed by
  RTL, state count, schedule, datapath, R.84 executor, image, Tang, tolerance,
  or interface change.
- **Baseline:** accepted H102 commit `ccfb2a0`: 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, seed-1 7,087
  LCs, and 140.92/32.65 MHz routed clocks.
- **Changed condition versus R.68/R.69 and H104:** R.68/R.69 moved the walk's
  phase decode into new or overlaid control-ROM payloads. H104 hand-reencoded a
  two-flop instrument-kind state. H109 changes neither source protocol: it asks
  the synthesizer to recode the complete, much larger sequencer FSM while
  retaining the same RTL transitions and outputs.
- **Change:** forced one-hot synthesis encoding on `sst` only.
- **Result:** canonical mapping changes H102's 6,360 LUT4 / 1,321 carry /
  1,458 FF / 508 unpackable / 14 EBR / floor 6,868 to 6,354 / 1,325 /
  1,515 / 503 / 14 / floor 6,857. Placement uses 7,084 LCs versus H102's
  7,087, explicitly below placement sensitivity, and its preliminary clocks
  pass at 137.68/34.55 MHz. Router2 then plateaus on one overused wire and does
  not complete through 29,349 canonical seed-1 iterations; the bounded run is
  stopped after more than five minutes. No routed timing or ASC exists, so the
  complete correctness/fidelity battery is skipped.
- **Decision:** rejected and reverted. `psg_seq.sv` is restored exactly;
  ignored mapping/routing evidence remains under `build/experiments/h109/`.
- **Repeat only if:** if rejected, retry only after the sequencer state graph,
  decoder fanout, state consumers, or Yosys FSM extraction/encoding changes
  materially.

## Hypothesis H110

- **ID:** H110.
- **Hypothesis:** `join_stage` records that a visit started while a completed
  inactive bank was waiting to publish. During such a visit `bank_ready` is
  held, `walk_tick` is false, and the controller is neither `S_IDLE` nor the
  post-visit `W_MUS`; every other reachable combination makes `join_stage`
  false. Reconstructing that exact pass-mode predicate should retire one flop
  and its next-state mux without changing publication, trigger-join, or music
  timing.
- **Scope:** first prove the reachable reduced controller invariant and
  synthesize the complete registered join/publication consumer. Only if that
  gate improves may `rtl/psg_seq.sv` remove `join_stage`, followed by canonical
  whole-PSG synthesis and the full acceptance battery. Do not change the bank
  handshake, visit/FSM transitions, trigger or music semantics, R.84 executor,
  image, Tang paths, tolerances, or interfaces.
- **Baseline:** accepted H102/I003 at `39b79cb` reproduces 6,360 LUT4s, 1,321
  carries, 1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, and
  7,087 routed LCs at 140.92/32.65 MHz. `u_seq` owns 1,859 LUT4s, 527 flops,
  249 unpackable flops, one EBR, and a 2,108-cell deterministic floor.
- **Changed condition versus H096/H103/H109 and R.84:** H096/H103 changed
  launch-worklist pacing state, H109 changed synthesis encoding of the complete
  sequencer FSM, and R.84 owns stored-state executor replacement. H110 changes
  none of those: it targets the separate inactive-bank publication/join mode
  and retains the existing binary `sst` encoding and controller transitions.
- **Change:** modeled the exact assignment ordering for `bank_ready`,
  `join_stage`, `walk_tick`, and the reduced controller classes before any
  production edit.
- **Result:** the reachable-state proof refutes the proposed invariant. From
  `S_IDLE` with `join_stage=0`, `walk_tick=1`, and `bank_ready=1`, a
  simultaneous `tick_en_d` plus pending-trigger visit start schedules
  `bank_ready<=0`, `join_stage<=1`, `walk_tick<=0`, and `sst<=V_LD`. The
  candidate predicate is therefore zero while the required historical join
  mode is one. Isolated and whole-PSG synthesis are skipped because the exact
  behavioral gate fails; production RTL is untouched.
- **Decision:** rejected before production. Ignored counterexample and probe
  sources remain under `build/experiments/h110/`.
- **Repeat only if:** if rejected, retry only after the bank-ready publication
  protocol, join-pass entry/exit states, tick-boundary handling, or mapper
  sequential lowering changes materially.

## Hypothesis H111

- **ID:** H111.
- **Hypothesis:** every non-reset branch of the registered CPU readback assigns
  `aram_rd_pending` to the current `aram_cpu_rd`, even though the source spells
  that same next state in three control arms. Hoisting the assignment to one
  unconditional site should remove redundant pending-valid mux logic while
  preserving synchronous `$02` capture and every other readback value.
- **Scope:** exhaustive next-state/output proof and isolated synthesis of the
  complete registered readback consumer first. Only after a deterministic
  isolated win may `rtl/psg.sv` change, followed by canonical whole-PSG
  synthesis and the full acceptance battery. Do not change CPU address/data
  semantics, audio-RAM arbitration or pointer advancement, channel readback,
  interfaces, R.84, images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 at `c4f7c2b` reproduces 6,360 LUT4s, 1,321
  carries, 1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, and
  7,087 routed LCs at 140.92/32.65 MHz.
- **Changed condition versus H033/H106:** H033 respelled the audible activity
  bit selected into ordinary channel reads; H106 factored upload/write and
  diagnostic/read pointer advancement inside `psg_aram`. H111 changes neither:
  it targets only the top-level registered one-cycle `$02` response-valid
  next-state spelling.
- **Change:** hoist `aram_rd_pending<=aram_cpu_rd` into the common non-reset
  branch while preserving the existing output priority and hold behavior.
- **Result:** exhaustive bitwise checking passes all 128 control/data
  transitions. Both complete registered baseline and candidate consumers map
  identically to 14 LUT4s and nine flops, so the source-only simplification
  cannot improve the whole PSG. Production RTL is untouched and no broader
  fidelity or physical gate is warranted.
- **Decision:** rejected before production; Yosys already recovers the common
  pending-valid next state. Ignored proof/probe evidence remains under
  `build/experiments/h111/`.
- **Repeat only if:** if rejected, retry only after the registered readback
  priority, audio-RAM response latency, pending-valid consumers, or mapper
  sequential lowering changes materially.

## Hypothesis H112

- **ID:** H112.
- **Hypothesis:** pending trigger row and length are stored in two separately
  indexed four-entry FF arrays, but the sequencer reads and clears both fields
  together for the same foreground slot. Packing each channel's fields into
  one 11-bit metadata entry may share index/clear decoding and reduce the 44
  currently unpackable trigger flops without changing independent CPU writes.
- **Scope:** exhaustive field-write/consume-priority proof and isolated
  synthesis of the complete registered dynamic-index consumer first. Only
  after a deterministic isolated win may `rtl/psg_seq.sv` pack the FF arrays,
  followed by canonical whole-PSG synthesis and the full acceptance battery.
  Do not move pending metadata into EBR, change same-edge CPU priority, trigger
  semantics, interfaces, R.84, images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 at `b17aa4d` reproduces 6,360 LUT4s, 1,321
  carries, 1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, and
  7,087 routed LCs at 140.92/32.65 MHz. The mapped unpackable census attributes
  24 flops to `trg_len` and 20 to `trg_row`.
- **Changed condition versus H101:** H101 moved the tuple into synchronous EBR
  and required costly forwarding to preserve immediate CPU-write visibility.
  H112 keeps the exact asynchronous FF read and same-edge field priority; only
  the two source arrays' FF packing and shared dynamic-index decode change.
- **Change:** pack each entry as `{trg_len,trg_row}`, retain field-selective CPU
  writes, and clear the whole entry on foreground-trigger consumption.
- **Result:** exhaustive checking passes all 6,291,456 row/length/data,
  field-write, same-index, and consume-priority transitions. Both complete
  registered baseline and packed dynamic-index consumers map identically to
  61 LUT4s and 44 flops. Production RTL is untouched and no broader fidelity
  or physical gate is warranted.
- **Decision:** rejected before production; Yosys already shares the available
  FF-array decode. Ignored proof/probe evidence remains under
  `build/experiments/h112/`.
- **Repeat only if:** if rejected, retry only after pending-trigger field
  ownership, CPU/consume priority, dynamic-index consumers, or mapper array
  lowering changes materially.

## Hypothesis H113

- **ID:** H113.
- **Hypothesis:** `psg.sv` currently merges the walker and sequencer multiplier
  request payloads with bitwise OR even though `wmul_start` and `smul_start`
  are mutually exclusive and every inactive client drives a zero bundle. Keep
  `mul_start = wmul_start | smul_start`, but select all payload fields from the
  active owner. The explicit owner mux may preserve common selection structure
  through the flattened `req_a` and `req_b` cones and reduce whole-PSG LUT4s.
- **Scope:** prove exact captured-transaction equivalence for all legal owner
  combinations and arbitrary active payload bits, verify the producers'
  zero-when-idle contract, then change only the five combinational payload
  assignments in `rtl/psg.sv`. Run full/PREVIEW lint and canonical forced
  whole-PSG synthesis/census first. Run routing and the complete H102 fidelity
  battery only after a deterministic mapped/floor improvement. Do not change
  multiplier state, arithmetic, mode widths, request/consume timing, CDC
  payload lifetime, walker/sequencer interfaces, R.84 executor/proofs, images,
  Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 at `a25f488` reproduces 6,360 LUT4s, 1,321
  carries, 1,458 flops, 508 unpackable flops, 14 EBRs, 6,868-cell floor, and
  7,087 routed LCs at 140.92/32.65 MHz. Source-contract v5 is SHA-256
  `d54dde5d...`, with all twelve bound source hashes matching.
- **Changed condition versus H017, R.36, R.63--R.64, and R.79:** those rows
  factored operand logic inside one requester, changed request-time arithmetic,
  or introduced/retired held CDC payload state. H113 leaves both requesters and
  the multiplier boundary unchanged; it replaces only the top-level merge of
  two already-exclusive, zero-when-idle bundles with owner selection and adds
  no state or arithmetic.
- **Change:** retain the ORed start signal; assign A, B, mode, and short from
  the walker bundle when `wmul_start` is asserted, otherwise from the sequencer
  bundle. Preserve the existing simultaneous-request assertion.
- **Result:** the all-domain Yosys SAT proof passes for arbitrary 40-bit active
  payloads under the no-dual-owner contract, and both producer blocks retain
  their zero-when-idle defaults. Full multi-pump and PREVIEW Verilator lint
  pass. Canonical forced mapping changes 6,360 LUT4 / 1,321 carry / 1,458 FF /
  508 unpackable / 14 EBR / floor 6,868 to 6,426 / 1,325 / 1,458 / 508 / 14 /
  floor 6,934. The formerly dominant `req_a` and `req_b` families shrink
  from 376/279 to 165/234 LUT4s, but owner fanout reshapes other cones and the
  global LUT gain is lost. Router2 completes at 7,160 LCs versus 7,087, with
  both clocks passing at 151.17/32.35 MHz. The complete fidelity battery is
  skipped because every binding area gate fails.
- **Decision:** rejected and production RTL reverted byte-for-byte. Ignored
  proof and physical evidence remains under `build/experiments/h113/`.
- **Repeat only if:** if rejected, retry only after requester exclusivity,
  zero-when-idle payloads, multiplier capture semantics, top-level ownership,
  or mapper mux/OR lowering changes materially.

## Hypothesis H114

- **ID:** H114.
- **Hypothesis:** `psg_wave.div_out` subtracts either 8,192 or 12,286 from
  an unsigned 15-bit `t_div` using an 18-bit signed expression. Across the
  complete input domain, the result is -12,286..24,575 and therefore fits
  signed 16 bits exactly. Performing the subtract at 16 bits and sign-extending
  its result may retire two carry stages and their covering logic.
- **Scope:** exhaustively prove both constants over all 32,768 input values,
  prove the bit-vector transform symbolically, then change only the width of
  the final reciprocal subtract and its explicit sign extension in
  `rtl/psg_wave.sv`. Run full/PREVIEW lint and canonical forced whole-PSG
  synthesis/census first. Route and run the complete H102 fidelity battery
  only after a deterministic mapped improvement with no floor regression. Do
  not change reciprocal contents, tail selection, quotient/remainder math,
  waveform rounding, pipeline registers, schedule, interfaces, EBRs, R.84
  executor/proofs, images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `2082ca7` maps
  6,360 LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs,
  floor 6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Source-contract
  v5 remains SHA-256 `d54dde5d...` with all twelve live hashes matching.
- **Changed condition versus H066--H067 and H076--H077:** those experiments
  encoded the tail predicate, repacked registered reciprocal payloads,
  reassociated the pre-divide affine, or shared reciprocal-index adders. H114
  leaves every such source and register unchanged; it makes only the already
  bounded post-selection subtract width explicit.
- **Change:** compute a signed 16-bit `div_out_n` from `{1'b0,t_div}` and
  the selected 16-bit constant, then sign-extend it to the existing 18-bit
  `div_out` interface.
- **Result:** exhaustive checking passes all 65,536 input/constant cases with
  exact range -12,286..24,575, and Yosys SAT proves the bit-vector transform
  for every 15-bit input and both modes. Full multi-pump and PREVIEW lint pass.
  Canonical forced mapping changes 6,360 LUT4 / 1,321 carry / 1,458 FF /
  508 unpackable / 14 EBR / floor 6,868 to 6,387 / 1,325 / 1,458 / 506 / 14 /
  floor 6,893. Router2 completes at 7,115 LCs versus 7,087, with both clocks
  passing at 134.95/32.57 MHz. The complete fidelity battery is skipped
  because the deterministic floor and routed area both regress.
- **Decision:** rejected and production RTL reverted byte-for-byte. Yosys's
  implicit width reduction is physically better than the explicit bound;
  ignored proof and physical evidence remains under
  `build/experiments/h114/`.
- **Repeat only if:** if rejected, retry only after the `t_div` range,
  subtract constants, signed result range, consumer width, or mapper carry
  lowering changes materially.

## Hypothesis H115

- **ID:** H115.
- **Hypothesis:** `f_det`, `f_rev`, `f_damp` and their stored base-filter
  counterparts are reachable only as 0, 1, or 2. At `I_TR1`, three separate
  two-bit `>` comparator/mux expressions compute their numeric maxima. On
  this closed domain, max has high bit `a[1] | b[1]` and low bit
  `~high & (a[0] | b[0])`; spelling that bound explicitly may reduce the
  complete registered join.
- **Scope:** prove the 0..2 source domain from the complete `fdec` table and
  base-field write/reload cycle, exhaustively compare the bounded formula,
  then synthesize all three registered joins in isolation. Touch
  `rtl/psg_seq.sv` and run whole-PSG/fidelity gates only after a deterministic
  isolated LUT/floor improvement. Do not change filter codes, stored record
  layout, publication values, effect/instrument precedence, schedule, state,
  interfaces, EBRs, R.84 executor/proofs, images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `95fe4cc` maps
  6,360 LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs,
  floor 6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Source-contract
  v5 remains SHA-256 `d54dde5d...` with all twelve live hashes matching.
- **Changed condition versus H021 and H099:** H021 replaced the complete
  32-entry base-3 filter decoder with arithmetic and was locally larger. H099
  changed the source used for sounding-filter publication and regressed
  globally. H115 preserves both the table and publication ownership and
  changes only the three bounded maxima when a custom instrument joins its
  base SFX filter tuple.
- **Change:** conditionally add one `max_filter` function implementing the
  proven 0..2 truth table and use it for detune, reverb, and dampen at
  `I_TR1`.
- **Result:** the complete 32-entry `fdec` table yields exactly levels
  {0,1,2}; exhaustive comparison passes all nine operand pairs. The complete
  three-field registered baseline and bounded candidates both synthesize to
  six LUT4s and six flops, with no carries. Production RTL and downstream
  physical/fidelity gates are not warranted.
- **Decision:** rejected before production; Yosys already recovers the bounded
  truth table from each comparator/mux join. Ignored proof/probe evidence
  remains under `build/experiments/h115/`.
- **Repeat only if:** if rejected, retry only after filter-level domain,
  base-field writers, instrument join semantics, registered consumer context,
  or mapper comparator lowering changes materially.

## Hypothesis H116

- **ID:** H116.
- **Hypothesis:** the eight `w_ch_{damp,rev,det,buzz,noiz}` flops hold only the
  effective filter field eventually written to inactive-bank P_W2. The field
  can instead live in that already-existing EBR word: copy active P_W2 to the
  inactive bank while V_LD consumes it outside a join pass; overwrite the
  filter field with base filters at T_SP or ordinary K_LD and with the exact
  base/instrument join at I_TR1; pre-read inactive P_W2 during terminal K_FX;
  then preserve its filter field while P_W2 installs the now-known effect-1
  bit. Reissue that address while P_W2 is held. This removes eight flops
  without a new state, register, schedule cycle, or memory.
- **Scope:** prove all filter/effect path classes, join/non-join ownership, and
  synchronous read/replay timing; then change only filter lifetime and the
  existing state-memory read/write schedules in `rtl/psg_seq.sv`. Run full and
  PREVIEW lint plus canonical forced whole-PSG mapping first. Route and run the
  complete H102 fidelity battery only after a deterministic mapped/floor win.
  Do not change filter decoding, trit maximum semantics, effect semantics,
  publication layout, bank-flip ordering, state-memory ports, sample/tick
  deadline, interfaces, EBR count, R.84 executor/proofs, images, Tang paths,
  or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `1fdb2ae` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Fresh source-contract v5
  validation convicts all thirteen mutations; SHA-256 remains
  `d54dde5d...`, with all twelve live source hashes matching.
- **Changed condition versus H099 and H115:** H099 retained all eight effective
  filter flops and changed only their two base-copy write arms/publication
  source; both whole-PSG variants regressed. H115 retained the same storage
  and publication ownership while respelling only the three maxima. H116
  removes the entire FF lifetime, uses the existing inactive EBR word as the
  owner, preserves the relational maxima, and adds neither equivalent
  temporary storage nor a publication mux.
- **Change:** both variants copy active P_W2 during non-join V_LD, replace its
  filter field at ordinary K_LD or I_TR1, read inactive P_W2 in K_FX/P_W2,
  and preserve `state_q[13:6]` while updating the late effect bit. Variant one
  reads only at terminal K_FX and also performs a redundant T_SP base write;
  variant two removes that write and reads throughout K_FX to remove the
  terminal-state decode.
- **Result:** the exhaustive proof passes 279,936 semantic cases across all
  108 legal filter tuples plus 125 synchronous-read/replay timelines. Full and
  PREVIEW lint pass for both variants. Variant one maps 6,380 LUT4 / 1,325
  carry / 1,450 FF / 509 unpackable / 14 EBR / floor 6,889 and routes in 7,117
  LCs at 149.34/32.50 MHz: -8 FF, but +20 LUT4, +4 carries, +21 floor cells,
  and +30 routed LCs. Variant two maps 6,411 / 1,321 / 1,450 / 509 / 14 /
  floor 6,920 and routes in 7,140 LCs at 140.94/32.62 MHz: -8 FF, but +51
  LUT4, +52 floor cells, and +53 routed LCs. Both clocks pass; the fidelity
  battery is skipped because every binding physical area gate fails.
- **Decision:** rejected after the two permitted variants. Production RTL is
  restored byte-for-byte; ignored proof and physical evidence remains under
  `build/experiments/h116/`.
- **Repeat only if:** if rejected, retry only after effective-filter lifetime,
  inactive-bank ownership, join-pass authority, P_W2 layout/timing, state-port
  replay, or mapper EBR/FF lowering changes materially.

## Hypothesis H117

- **ID:** H117.
- **Hypothesis:** `prun` is reset to zero and gates every walk-controller side
  effect. On the first accepted sample edge, the same sequential block sets
  `prun=1`, `pc_ch=0`, and `pph=0`; the old values of `pc_ch`/`pph` are not
  consumed on that edge. Their explicit reset assignments therefore add ten
  synchronous-reset controls without defining observable behavior. Removing
  only those assignments may improve iCE40 FF packing/control fanout while the
  validity reset remains unchanged.
- **Scope:** prove reset-to-first-sample dominance and all side-effect gates,
  then remove only `pc_ch <= 0` and `pph <= 0` from the reset arm in
  `rtl/psg_walk.sv`. Run full/PREVIEW lint and canonical forced whole-PSG
  mapping first. Route and run the complete H102 fidelity battery only after a
  deterministic mapped/floor win. Do not change `prun`, controller states or
  widths, schedule/control ROM, sample acceptance, arithmetic, persistent
  oscillator state, interfaces, EBRs, R.84 executor/proofs, images, Tang
  paths, or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `9c3a523` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Fresh source-contract v5
  validation convicts all thirteen mutations; SHA-256 remains
  `d54dde5d...`, with all twelve live source hashes matching.
- **Changed condition versus controller/schedule DNR families:** H109 changed
  the synthesis encoding of the 60-state sequencer, and R.68--R.69 changed
  partial schedule/control representations. H117 changes no encoding, state
  transition, or valid cycle; it removes reset only from payload counters whose
  complete consumer cone is dominated by the separately reset `prun` valid
  bit. No active DNR row tests this reset-control boundary.
- **Change:** variant one removes reset from all ten `pc_ch`/`pph` bits.
  Variant two restores the seven-bit `pph` reset and removes only the three-bit
  `pc_ch` reset, attributing variant one's six-new-unpackable-FF result.
- **Result:** exhaustive exploration passes 48,144 transitions from every
  arbitrary post-reset `pc_ch`/`pph` payload across repeated reset, sample, and
  stall sequences; seven source gates confirm that no payload side effect is
  visible outside `prun`. Full and PREVIEW lint pass for both variants.
  Variant one maps 6,394 LUT4 / 1,325 carry / 1,458 FF / 514 unpackable /
  14 EBR / floor 6,908 and routes in 7,131 LCs at 151.17/32.61 MHz: +34
  LUT4, +4 carries, +6 unpackable, +40 floor cells, and +44 routed LCs.
  Variant two maps 6,416 / 1,326 / 1,458 / 508 / 14 / floor 6,924 and routes
  in 7,151 LCs at 150.42/33.00 MHz: +56 LUT4, +5 carries, +56 floor cells,
  and +64 routed LCs. Both clocks pass; the fidelity battery is skipped because
  every binding physical area gate fails.
- **Decision:** rejected after the two permitted variants. Production RTL is
  restored byte-for-byte; ignored proof and physical evidence remains under
  `build/experiments/h117/`.
- **Repeat only if:** if rejected, retry only after walk validity, first-sample
  initialization, controller side-effect gating, reset topology, or mapper
  reset/enable lowering changes materially.

## Hypothesis H118

- **ID:** H118.
- **Hypothesis:** every direct note/instrument volume endpoint is `0..7 << 8`,
  hence at most 1,792. Effect-1 interpolation stays between its two endpoints;
  fade effects 4/5 multiply by `fcnt` or `sp-fcnt` and divide by `sp`;
  instrument scaling multiplies by a `0..7` volume and divides by seven; and
  music gain multiplies by `1..256` then divides by 256. Therefore `vol_r`,
  `fxv_next`, `a_post`, and their direct endpoint wires fit unsigned eleven
  bits, while Yosys retains all twelve declared `vol_r` flops. Narrowing that
  complete cone may remove one FF and the high limb from several shared-
  service operand/select paths.
- **Scope:** prove all direct, interpolation, fade, instrument, and music-gain
  ranges; synthesize a complete registered volume cone if useful; then narrow
  only the volume-local wires/register and explicitly zero-extend at the
  unchanged 12-bit service/publication boundaries in `rtl/psg_seq.sv`. Run
  full/PREVIEW lint and canonical forced whole-PSG mapping first. Route and run
  the complete H102 fidelity battery only after a deterministic mapped/floor
  win. Do not change rounding, effect counters, divider/multiplier semantics,
  amplitude publication width, sample datapath widths, schedule, interfaces,
  EBRs, R.84 executor/proofs, images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `449e3fc` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Fresh source-contract v5
  validation convicts all thirteen mutations; SHA-256 remains
  `d54dde5d...`, with all twelve live source hashes matching. The accepted
  JSON contains twelve physical `vol_r` flops, so this is not an already-
  pruned source-only bit.
- **Changed condition versus H065 and width DNR families:** H065 narrowed the
  signed sample registers feeding waveform/noise arithmetic and regressed
  globally. H118 leaves every sample/arithmetic register untouched and closes
  a separate unsigned sequencer volume invariant across all of its producers
  and unchanged 12-bit boundaries. No active DNR row tests this volume cone.
- **Change:** variant one narrows `vol_r`, direct/previous endpoints,
  interpolation, fade and instrument post-scale wires to eleven bits and
  zero-extends only at the original service/publication boundaries. Variant
  two restores every arithmetic wire to twelve bits and narrows only the
  physical `vol_r` register, explicitly slicing/zero-extending its assignments.
- **Result:** the bound proof passes 2,707,216 direct, interpolation, fade,
  instrument-scaling, and music-gain checks with a hard maximum of 1,792.
  Full and PREVIEW lint pass for both variants. Variant one maps 6,395 LUT4 /
  1,323 carry / 1,457 FF / 508 unpackable / 14 EBR / floor 6,903 and routes in
  7,128 LCs at 143.88/33.55 MHz: +35 LUT4, +2 carries, -1 FF, +35 floor cells,
  and +41 routed LCs. Variant two maps 6,420 / 1,323 / 1,457 / 505 / 14 /
  floor 6,925 and routes in 7,153 LCs at 139.57/33.16 MHz: +60 LUT4, +2
  carries, -1 FF, -3 unpackable, +57 floor cells, and +66 routed LCs. Both
  clocks pass; the fidelity battery is skipped because every binding physical
  area gate fails.
- **Decision:** rejected after the two permitted variants. Production RTL is
  restored byte-for-byte; ignored proof and physical evidence remains under
  `build/experiments/h118/`.
- **Repeat only if:** if rejected, retry only after note/instrument volume
  range, effect counter invariant, scaling divisors, music-gain landing,
  publication width, or mapper volume-cone lowering changes materially.

## Hypothesis H119

- **ID:** H119.
- **Hypothesis:** `psg_walk.pph` is declared seven bits for every elaboration,
  and the accepted H102 netlist retains all seven physical counter flops. The
  PREVIEW schedule visits only phases 0..23, while the canonical
  `MULTIPUMP=1` hardware schedule visits only 0..61; both domains fit six
  bits. Only the `REALTIME_PREVIEW=0, MULTIPUMP=0` compatibility schedule
  reaches phase 67 and requires seven bits. Deriving the counter width from
  those elaboration parameters may retire one mapped hardware flop and its
  high-bit counter/decode fabric without changing a visited phase.
- **Scope:** exhaustively prove start, advance, arbitrary repeated
  `ctrl_stall`, terminal wrap, slot advance, and final-walk close for PREVIEW,
  multi-pumped, and single-clock compatibility schedules; then change only
  the width of `pph`, `pph_nxt`, the compatibility schedule input, and their
  width casts in `rtl/psg_walk.sv`. Run full multi-pump and PREVIEW lint plus
  canonical forced whole-PSG synthesis/census first. Route and run the
  complete H102 fidelity battery only after a deterministic mapped/floor win.
  Do not change schedule landmarks, control-ROM contents or addresses,
  controller transitions, reset semantics, sample acceptance, arithmetic,
  persistent oscillator state, interfaces, EBRs, R.84 executor/proofs,
  images, Tang paths, or tolerances.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `379db7b` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Fresh source-contract v5
  validation convicts all thirteen mutations; SHA-256 remains
  `d54dde5d...`, with all twelve live source hashes matching. The accepted
  JSON retains seven physical `pph` flops.
- **Changed condition versus H105, H117, and R.68--R.69:** H105 narrowed the
  separate V_LD/V_ST transfer counter `vcnt` and regressed its complete
  consumer; H117 removed reset from `pph` without changing its width and
  regressed globally; R.68--R.69 changed schedule-decode storage/encoding
  while retaining the counter. H119 changes no reset or decode ownership and
  instead exploits elaboration-specific terminal bounds on the phase counter
  itself. No DNR row tests this mechanism.
- **Change:** derive `PPH_W = (!REALTIME_PREVIEW && !MULTIPUMP) ? 7 : 6`, use
  it for `pph` and `pph_nxt`, and replace fixed seven-bit phase casts/constants
  with `PPH_W`-sized forms. Preserve the compatibility schedule's seven-bit
  function input and all three exact terminal values.
- **Result:** the proof covers 39,520 state-transition pairs and 39,520
  combinational pairs across PREVIEW, canonical multi-pump, and compatibility
  schedules, including starts, arbitrary stalls and skips, terminal wraps,
  slot advances, and the final close. All three lint modes pass with only the
  pre-existing `WIDTHTRUNC` class suppressed. Canonical synthesis maps 6,395
  LUT4s, 1,316 carries, 1,457 flops, 507 unpackable flops and 14 EBRs; the
  deterministic floor is 6,902 cells and seed-1 router2 completes in 7,119
  LCs at 145.99 MHz fast / 32.50 MHz PSG. Relative to H102 this is +35 LUT4s,
  -5 carries, -1 FF, -1 unpackable FF, +34 floor cells, and +32 routed LCs.
  The fidelity battery is intentionally skipped because every binding area
  gate fails.
- **Decision:** rejected and reverted byte-for-byte. The ignored proof and
  physical evidence remain under `build/experiments/h119/`.
- **Repeat only if:** if rejected, retry only after a schedule terminal,
  elaboration-mode contract, phase consumer, controller reset/stall behavior,
  or mapper counter/decode lowering changes materially.

## Hypothesis H120

- **ID:** H120.
- **Hypothesis:** `psg_seq.fade_acc` and `fade_step` are transaction payloads
  whose sole validity state is `fade_dir != 0`. Reset clears `fade_dir`; every
  CPU `$20` path that changes `fade_dir` from idle to fade-in or fade-out also
  assigns `fade_acc = 0` and the complete table-derived `fade_step` on that
  same edge. The only payload reads occur inside the `pre_tick && fade_dir !=
  0` arm. Removing their 29 synchronous-reset bits may simplify the sequencer
  reset/control cover without exposing an uninitialized value.
- **Scope:** exhaustively prove reset, arbitrary idle clocks, `$22` table
  capture, immediate and delayed `$20` fade starts, active pre-tick advances,
  terminal stop, and restart for the complete `{fade_dir,fade_acc,fade_step}`
  transition. Synthesize the complete registered fade consumer in isolation
  before changing production. If it improves, remove only `fade_acc <= 0` and
  `fade_step <= 0` from the reset arm in `rtl/psg_seq.sv`; retain `fade_dir`
  reset, every non-reset assignment, arithmetic, table port/replay, CPU
  priority, state schedule, publication, interfaces, EBRs, R.84 executor and
  tolerances. Run full multi-pump and PREVIEW lint, then canonical forced
  whole-PSG synthesis/census. Route and run the complete H102 fidelity battery
  only after a deterministic mapped/floor win.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `8a14afc` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. Fresh H120 generation
  reproduces source-contract v5 byte-for-byte at SHA-256 `d54dde5d...`; all
  twelve live source hashes match. The accepted census attributes thirteen
  unpackable flops to `fade_step`; `fade_acc` feeds the 17-bit fade update.
- **Changed condition versus H117 and the historical reset audit:** H117
  removed reset from the walk controller's `pc_ch`/`pph` payload and regressed
  globally. H120 touches a disjoint 29-bit sequencer transaction payload with
  an explicit `fade_dir` validity bit and same-edge initialization of every
  payload bit before its first consumer. The earlier streamed/datapath reset
  audit predates this isolated continuation and does not record a physical
  test of this complete fade-validity boundary. No active DNR row tests it.
- **Change:** remove the reset assignments only in the isolated complete fade
  consumer; production RTL remains unchanged because the early gate fails.
- **Result:** the inductive model covers all 60 direction/pre-tick/terminal/CPU
  command classes and proves the invariant that visible state is equal and
  payloads are equal whenever `fade_dir` is active. A four-edge Yosys SAT
  miter independently proves arbitrary post-reset command sequences. The
  complete isolated baseline maps 79 LUT4s, 16 carries and 41 FFs, with 13
  unpackable `fade_step` flops and a 92-cell floor. The resetless candidate
  maps 80 LUT4s, 16 carries and the same 41 FFs/13 unpackable flops, for a
  93-cell floor. No physical reset cell retires, so production lint, global
  synthesis, routing, and fidelity gates are intentionally skipped.
- **Decision:** rejected before production RTL. Ignored proof, SAT, source-
  contract, and isolated synthesis evidence remains under
  `build/experiments/h120/`.
- **Repeat only if:** if rejected, retry only after fade validity, CPU command
  priority, table replay/capture, payload initialization, pre-tick arithmetic,
  reset semantics, or mapper reset-control lowering changes materially.

## Hypothesis H121

- **ID:** H121.
- **Hypothesis:** the canonical `SEQ_BUDGET == 272` limiter stores nine bits as
  an eight-bit `seq_count` plus sticky `seq_phase`, seeds them as `{0,239}` at
  every reset/sample boundary, and stops at `{1,255}`. Its complete reachable
  progression is therefore exactly the ordinary nine-bit sequence 239..511.
  One nine-bit counter seeded at 239 and stopped on reduction-AND should
  preserve every credit, freeze, reset and terminal cycle while removing the
  sticky-phase update mux and its separate decode ownership.
- **Scope:** exhaustively prove the baseline/candidate transition relation for
  reset, sample restart, arbitrary `walk_busy` freezes, all 272 permitted
  advances and terminal hold. Synthesize the complete registered limiter and
  a registered terminal consumer in isolation before changing production. If
  it improves a deterministic isolated resource, replace only the specialized
  `g_seq_budget_272` representation in `rtl/psg.sv`; retain `SEQ_BUDGET`, all
  clocks, walk ownership, sequencer cadence, interfaces, arithmetic, EBRs,
  PREVIEW behavior, R.84 executor files and tolerances. Run full/PREVIEW lint
  and canonical forced whole-PSG synthesis/census; route and run fidelity only
  after a deterministic mapped/floor win.
- **Baseline:** accepted H102/I003 RTL at docs checkpoint `ff38782` maps 6,360
  LUT4s, 1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor
  6,868, and routes in 7,087 LCs at 140.92/32.65 MHz. The specialized limiter
  uses eight `seq_count` flops and one `seq_phase` flop, seeds count 239, sets
  phase on count wrap, and decodes terminal as phase plus count all-ones.
- **Changed condition versus H051, H090, and the R.54 clock contract:** H051
  recoded the detune service's private six-state iteration token; H090 tested
  the unrelated multiplier request step-count decoder. R.54 established the
  exact 272-credit behavior and introduced the current split representation
  but did not record an isolated physical comparison against the algebraically
  identical single nine-bit register. H121 changes no credit or sample clock.
- **Change:** replace the split state with one nine-bit counter seeded at 239;
  after the isolated win, apply the same representation only inside
  `g_seq_budget_272` for canonical mapping, then revert it byte-for-byte when
  the whole-design area gate fails.
- **Result:** all 4,096 state/input transition classes pass, including every
  raw nine-bit state, reset/sample priority, arbitrary freeze, the 272-advance
  reachable run and terminal hold. A four-edge reset-bounded Yosys SAT miter
  passes. The complete isolated limiter changes 16 LUT4 / 6 carry / 9 FF / one
  unpackable FF / floor 17 to 15 LUT4 / 7 carry / 9 FF / zero unpackable FF /
  floor 15. Full and PREVIEW lint pass. Canonical whole-PSG mapping changes
  6,360 LUT4 / 1,321 carry / 1,458 FF / 508 unpackable / floor 6,868 to 6,373
  LUT4 / 1,326 carry / 1,458 FF / 504 unpackable / floor 6,877, with 14 EBRs
  unchanged. Routing and fidelity are intentionally skipped because every
  deterministic combinational/floor gate regresses.
- **Decision:** rejected and reverted byte-for-byte. Ignored proof, SAT,
  isolated synthesis and whole-PSG mapping evidence remains under
  `build/experiments/h121/`.
- **Repeat only if:** if rejected, retry only after the 272-credit value,
  sample-boundary seed, freeze/terminal behavior, or mapper counter/reset/decode
  lowering changes materially.

## Hypothesis H122

- **ID:** H122.
- **Hypothesis:** `psg_seq.cpz` has one consumer, the low-byte zeroing decision
  in PC3, and exactly three routes to that consumer. K_ADV's copy/skip route
  assigns `cpz=!playing[c]`; if `playing[c]` is true that route requires
  `walk_tick=0`. The two EA5 stop routes are reachable only after K_ADV entered
  evaluation with `walk_tick && playing[c]`, and both set `pend_stop[c]=1`
  alongside `cpz=1`. Therefore the consumed value is exactly
  `!playing[c] || (walk_tick && pend_stop[c])`; reconstructing it at PC3 may
  remove the dedicated flag and its multi-state update cone.
- **Scope:** prove all legal K_ADV/EA5-to-K_ROT/PC0..PC3 path classes, arbitrary
  prior `pend_stop`, intervening holds, and the same-edge stop write. Synthesize
  the complete registered route/consumer cone in isolation before changing
  production. If it improves a deterministic isolated resource, remove only
  `cpz` and its three assignments from `rtl/psg_seq.sv` and use the exact
  derived predicate at PC3. Retain playing/stop semantics, bank ownership,
  state-memory address/data and write clocks, sequencer schedule, interfaces,
  EBRs, PREVIEW, R.84 executor files and tolerances. Run full/PREVIEW lint and
  canonical forced whole-PSG synthesis/census; route and run the complete H102
  fidelity battery only after a deterministic mapped/floor win.
- **Baseline:** accepted H102/I003 RTL at commit `824a3cc` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. `cpz` maps as one settable/enabled
  flop and feeds only PC3's copied-amplitude low-byte mux.
- **Changed condition versus H097, H110, and the lifetime DNR families:** H097
  replaced `ml_cpu` with a different historical controller flag and regressed
  globally; H110 attempted to reconstruct `join_stage` but lost a same-edge
  bank-publication history bit. H122 does not alias storage or infer history
  from bank state: every legal edge to its sole consumer establishes one of
  two current-state predicates, and both EA5 stop paths preserve their value in
  the already-required `pend_stop` vector.
- **Change:** proof-only live-state reconstruction; production RTL unchanged.
- **Result:** the static route inventory confirms only the three expected
  K_ROT entries, but the time-domain proof refutes the hypothesis. A reachable
  non-tick pass can take K_ADV's active-slot copy route and capture `cpz=0`;
  foreground CPU control remains active while the PC chain runs, so a stop can
  clear `playing[c]` before PC3. The candidate predicate then becomes one and
  changes a nonzero copied amplitude byte from `0x55` to zero, while the
  registered baseline deliberately preserves it. `pend_stop` does not repair
  the case because this CPU stop path leaves it clear. Isolated synthesis and
  every downstream gate are skipped.
- **Decision:** rejected before synthesis or production RTL. The executable
  counterexample remains under `build/experiments/h122/`.
- **Repeat only if:** if rejected, retry only after K_ADV/EA5 route topology,
  delayed-stop ownership, playing visibility, PC3 publication, or mapper
  sequential/dynamic-index lowering changes materially.

## Hypothesis H123

- **ID:** H123.
- **Hypothesis:** `psg_walk.spar_last` is updated at every sample edge only to
  generate the registered `nz_tick_r` bank-change pulse consumed during that
  sample's eight-slot walk. Keep `spar_last` unchanged until the terminal slot
  has consumed the pulse and derive the pulse live as
  `spar_bank != spar_last`; this may retire `nz_tick_r`, its reset/update mux,
  and part of its nineteen-LUT fanout cone while preserving the same
  effect-noise restart samples.
- **Scope:** exhaustively model reset, arbitrary legal between-sample and
  same-sample-edge bank flips, accepted and skipped PREVIEW starts, held walk
  cycles, all eight slot consumers, and terminal history commit before any
  RTL edit. Only if every consumer sees the same pulse, synthesize an isolated
  registered consumer and then change `rtl/psg_walk.sv`. Retain bank
  publication, sample/tick cadence, noise arithmetic and alternation, restart
  timing, state memory, interfaces, EBRs, R.84 files and tolerances. Whole-PSG
  mapping, routing and the H102 fidelity battery remain conditional on a
  deterministic area win.
- **Baseline:** accepted H102/I003 RTL at commit `852e1b5` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. `spar_last` is one unpackable flop;
  `nz_tick_r` is one additional flop whose named fanout cone contains nineteen
  LUT4s in H113's source-identical baseline JSON.
- **Changed condition versus H009/H010, H058, H062 and H110:** H009/H010
  recoded the timing module's delayed-tick generator; H058 removed a state-RAM
  replay token; H062 reconstructed a per-slot old-noise activity flag; H110
  reconstructed sequencer join history and lost a same-edge publication case.
  H123 preserves all those states and tests only the walker's global sampled
  parameter-bank history, explicitly including same-edge publication rather
  than assuming it away.
- **Change:** proof-first live bank-delta reconstruction; production RTL is
  unchanged until the edge-order model passes.
- **Result:** all eight reset/history/bank/same-edge-flip transition classes
  confirm that the live delta matches only when no publication occurs on the
  sample-start edge. A reachable `last=0`, pre-edge bank zero, same-edge flip
  to bank one produces baseline pulse zero but live pulse one, moving the
  noise restart one sample early. All sixteen two-sample dropped-PREVIEW
  classes were also enumerated: if the bank changes before a dropped start,
  baseline advances its history despite having no consumer, while the
  terminal-commit candidate retains the old history and emits a stale restart
  on the next accepted walk. Isolated synthesis and downstream gates are
  skipped.
- **Decision:** rejected before synthesis or production RTL. The executable
  edge-order counterexample remains under `build/experiments/h123/`.
- **Repeat only if:** if rejected, retry only after parameter-bank publication
  sites, same-edge sample/start ordering, PREVIEW drop behavior, restart
  consumption, or mapper sequential lowering changes materially.

## Hypothesis H124

- **ID:** H124.
- **Hypothesis:** every reachable published amplitude is in 0..1,792, so
  `psg_walk.s_eff_a[11]` is always zero, yet H113's source-identical netlist
  maps all twelve walker amplitude flops plus the dedicated full-mode
  `s_clr_tog` flop. Load one twelve-bit packed register as
  `{state_q[13],state_q[10:0]}`, expose the numeric amplitude as
  `{1'b0,packed[10:0]}`, and use packed bit 11 as the unchanged clear token.
  This should retire one physical register without narrowing or rewriting any
  amplitude consumer.
- **Scope:** prove the complete direct-publication and copied-bank producer
  domain, every 2,048-amplitude/two-toggle load tuple, zero/nonzero and slice
  consumers, clear comparison, PREVIEW's independent clear-token ownership,
  and registered load/hold behavior. Synthesize a complete isolated
  registered consumer before changing production. If deterministic area
  improves, change only `rtl/psg_walk.sv`, add a permanent exactness check to
  `tools/psg_hw_forms.py`, run full/PREVIEW lint and canonical forced
  whole-PSG synthesis/census. Route and run the complete H102 fidelity battery
  only after mapped/floor area improves. Retain publication words, parameter
  bank addresses, amplitude values, clear timing, noise/filter updates,
  schedule, interfaces, EBRs, R.84 files and tolerances.
- **Baseline:** accepted H102/I003 RTL at commit `e6df2da` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. H113's source-identical JSON maps
  twelve `s_eff_a` DFFEs and one separate unpackable `s_clr_tog` DFFE.
- **Changed condition versus H102, H116, H118 and reset/lifetime DNRs:** H102
  packed a wavetable-only instrument flag into a sequencer working field;
  H116 moved eight effective-filter values through the inactive bank; H118
  narrowed the complete sequencer/walker volume cone and regressed globally.
  H124 neither changes the bank format nor narrows a numeric register: it
  packs one already-loaded walker control bit into one otherwise-zero bit of
  the same-edge walker payload and preserves the old twelve-bit amplitude
  interface as an explicit zero-extended wire.
- **Change:** variant one renames the physical payload, then exposes the old
  twelve-bit amplitude name as a zero-extended wire. Variant two preserves the
  `s_eff_a` register name and masks only the high bit at its zero tests,
  gain operand, and PREVIEW product. Both pack `state_q[13]` into stored bit 11
  and remove the dedicated clear-toggle register.
- **Result:** 32,768 exhaustive load/consumer checks pass over all 4,096
  legal amplitude/toggle tuples, and four-cycle SAT proves arbitrary load/hold
  sequences. The complete mapper-visible isolated cone improves from 175
  LUT4s / 24 carries / 13 DFFEs to 146 / 23 / 12. Full multi-pump and PREVIEW
  lint pass for both production spellings. Both whole-PSG variants map
  identically at 6,399 LUT4s, 1,323 carries, 1,457 flops, 508 unpackable flops,
  14 EBRs and floor 6,907: +39 LUT4s, +2 carries, -1 FF and +39 floor cells
  versus H102. Routing and fidelity gates are skipped because the binding
  deterministic area gate fails; production RTL is restored byte-for-byte.
- **Decision:** rejected after the two permitted spellings. The local state
  packing win does not survive flattened global covering.
- **Repeat only if:** if rejected, retry only after the amplitude domain,
  P_W3 layout, clear-token ownership, walker consumer set, or mapper
  register/enable lowering changes materially.

## Hypothesis H125

- **ID:** H125.
- **Hypothesis:** `psg_walk.s_ch_noiz` is loaded from P_W2 on the same edge as
  the unreachable `s_eff_a[11]` amplitude bit loaded from P_W3, before either
  is consumed. Pack `state_q[6]` into stored amplitude bit 11, derive
  `s_ch_noiz` from that bit, and explicitly restrict only numeric amplitude
  consumers to bits 10:0. This retires one unpackable high-fanout flop and may
  let its 92-LUT named cone cover better than H124's low-fanout clear token.
- **Scope:** prove all 8,192 amplitude/noiz/load tuples, arbitrary holds,
  every noiz consumer (noise refresh and buzz/brown selection), every
  amplitude zero/slice/gain/PREVIEW consumer, and the one-cycle P_W2-to-P_W3
  load order. Synthesize the complete registered consumer first. If it saves
  deterministic local resources, change only `rtl/psg_walk.sv`, run full
  multi-pump and PREVIEW lint, then canonical forced whole-PSG mapping/census.
  Route and run the H102 fidelity battery only after mapped/floor area wins.
  Retain parameter-bank words, amplitude/noiz values, noise/filter behavior,
  schedule, interfaces, EBRs, R.84 files and tolerances.
- **Baseline:** accepted H102/I003 RTL at commit `c6105c5` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. H113's source-identical JSON maps
  all twelve `s_eff_a` DFFEs and one separate unpackable `s_ch_noiz` DFFE;
  its named downstream family contains 92 LUT4s.
- **Changed condition versus H124:** H124's packed clear token drove only a
  seven-LUT named cone and both source spellings regressed globally despite
  the one-FF retirement. H125 changes the packed payload and its entire
  consumer topology: `s_ch_noiz` is unpackable and participates in a 92-LUT
  refresh/brown-noise cone. The unchanged amplitude mask is not itself the
  hypothesized saving.
- **Change:** load `state_q[6]` into `s_eff_a[11]` during P_W2, load only
  `state_q[10:0]` during P_W3, derive `s_ch_noiz` from stored bit 11, and mask
  bit 11 at the unchanged amplitude consumers.
- **Result:** 32,768 exhaustive checks pass over all 4,096 amplitude/noiz
  tuples, including both refresh outcomes, buzz/brown selection and numeric
  consumers. Five-cycle SAT proves the P_W2/P_W3 split load followed by
  arbitrary holds. The complete mapper-visible isolated cone improves from
  181 LUT4s / 24 carries / 13 DFFEs to 150 / 23 / 12. Full multi-pump and
  PREVIEW lint pass. Canonical whole-PSG mapping instead moves to 6,405 LUT4s,
  1,323 carries, 1,457 flops, 14 EBRs and floor 6,913: +45 LUT4s, +2 carries,
  -1 FF and +45 floor cells. Routing and fidelity are skipped because the
  deterministic area gate fails; production RTL is restored byte-for-byte.
- **Decision:** rejected. The high-fanout payload is globally worse than
  H124's already-rejected low-fanout packing, so the amplitude dead-bit family
  closes under the two-variant stop rule.
- **Repeat only if:** if rejected, retry only after noiz/buzz semantics,
  amplitude domain, P_W2/P_W3 load order, walker consumer set, or mapper
  register/enable lowering changes materially.

## Hypothesis H126

- **ID:** H126.
- **Hypothesis:** `psg_seq.ctrl_displaced` is set only by
  `fade_issue && ctrl_read` and is consumed one cycle later as the walker's
  `ctrl_stall`. The companion `crom_replay` bit already records
  `fade_issue`; derive the stall as `crom_replay && prun` on the replay cycle
  and retire the separate history flop while preserving every real displaced
  control read.
- **Scope:** exhaustively model reset, idle and existing walks, every phase
  including terminal close, a sample walk starting on the same edge as the
  fade lookup, accepted and dropped PREVIEW starts, replay, arbitrary holds,
  and adjacent `$22/$20` writes. Compare the registered baseline stall,
  walker phase/address evolution, ROM owner/address, `crom_q`, `fstep_q`, and
  `$20` fade-step consumption against the derived form before any RTL edit.
  Only if every trace is identical, synthesize the complete registered
  collision consumer in isolation and then change only `rtl/psg_seq.sv`.
  Retain shared-ROM priority, sequencer holds, sample/tick cadence, full and
  PREVIEW schedules, interfaces, EBRs, R.84 files and tolerances. Whole-PSG
  mapping, routing and the H102 fidelity battery remain conditional on a
  deterministic mapped/floor win.
- **Baseline:** accepted H102/I003 RTL at commit `f9669f9` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. `ctrl_displaced` is one registered
  collision-history bit; `crom_replay` independently records every fade-table
  lookup so the following cycle captures `fstep_q` and holds the sequencer.
- **Changed condition versus H058, H110, H117, H121 and the control-encoding
  DNRs:** H058 tested a state-RAM replay token, H110 reconstructed bank/join
  history, H117 removed validity-dominated walk payload resets, and H121
  recoded the sequencer-credit state. H126 changes none of those domains and
  does not alter a control word or schedule encoding. It tests only whether
  the existing fade-replay bit plus the live walker-valid bit contains the
  exact prior-cycle collision fact.
- **Change:** proof-first replacement of the registered collision-history bit
  with `crom_replay && prun`; production RTL remains unchanged until the
  edge-order model passes.
- **Result:** exhaustive one-edge enumeration covers every phase of the
  61-phase multi-pumped, 67-phase compatibility, and 23-phase PREVIEW walks,
  both replay values, accepted/dropped starts, terminal close, fold-busy
  state, and no-op/`$22`/`$20` commands. Of 3,768 comparable transition
  classes, 3,750 agree. Ten accepted idle-start classes refute the candidate:
  pre-edge `prun=0` means the fade lookup displaced no control read, but the
  same edge starts the walk, so next-cycle `crom_replay && prun=1` invents a
  stall. In the concrete adjacent-write trace, the baseline advances phase
  0 -> 1 and prefetches control word 1 while the candidate holds phase 0 and
  fetches the empty word 0. Both forms correctly consume the fade word on the
  adjacent `$20`, localizing the mismatch to walker cadence/control prefetch.
  Eight terminal-close classes show the converse history mismatch. Synthesis
  and production RTL are skipped.
- **Decision:** rejected before synthesis or production RTL. The executable
  edge-order counterexample remains under `build/experiments/h126/`.
- **Repeat only if:** if rejected, retry only after sample-walk start/finish
  ordering, `ctrl_read` ownership, fade lookup priority, replay duration,
  adjacent `$22/$20` consumption, or mapper sequential lowering changes
  materially.

## Hypothesis H127

- **ID:** H127.
- **Hypothesis:** phaser detune-1 computes
  `ceil(3*dp13[6:0]/128)`. Its current quotient decoder builds both
  `dp13[5:0] >= 43` and `dp13[5:0] >= 22`, then selects their contribution
  with `dp13[6]`. Select the active threshold first, compute one shared
  predicate, and reconstruct both quotient bits from that predicate,
  `dp13[6]`, and low-remainder nonzero. This should retire duplicated
  threshold logic without changing the accepted R.57 arithmetic or any
  register, service, or schedule.
- **Scope:** exhaustively compare the current and candidate quotient for all
  128 remainders and all downstream `dq_ceil6_256` sums; prove the
  combinational relation with SAT; synthesize a complete registered decoder
  in isolation before touching production RTL. Only if isolation improves,
  change `rtl/psg_wave.sv`, run full/PREVIEW lint, and force canonical
  whole-PSG mapping from H113's source-identical baseline. Route and run the
  H102 fidelity battery only after a deterministic mapped/floor win. Preserve
  all R.84/B2 executor files, images, Tang paths, tolerances, and EBR topology.
- **Baseline:** accepted H102/I003 RTL at commit `2d0d6a0`; H113's
  source-identical `build/experiments/h113/baseline.json` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. The complete `u_wave` scope maps
  732 LUT4s, 250 carries, 96 flops, 46 unpackable flops, and one EBR.
- **Changed condition versus H042, H051, R.57 and H093:** H042 tested the
  triangle detune-1 two-bit residue comparison; H051 recoded the separate
  visit-local DQ service count; R.57 introduced the accepted phaser
  quotient/remainder identity; H093 regrouped the service coefficient table.
  H127 changes none of those relations, coefficients, state encodings, or
  services. It targets only duplicated threshold selection inside R.57's
  already-accepted combinational phaser remainder decoder.
- **Change:** proof-first selected threshold and one shared predicate; no
  production RTL changes until exhaustive/SAT equivalence and isolated
  registered-consumer synthesis both pass.
- **Result:** exhaustive Python covers all 8,192 `dp13` values and all 128
  remainders; both Yosys SAT miters pass. The complete registered reference is
  49 LUT4s, 19 carries and 25 flops. Explicit Boolean sharing maps to 51/19/25.
  Direct threshold selection maps to 46/25/25 and therefore qualifies for the
  global gate, but canonical whole-PSG mapping changes 6,360 LUT4s, 1,321
  carries, 1,458 flops, 508 unpackable flops, 14 EBRs and floor 6,868 to 6,410,
  1,321, 1,458, 507, 14 and floor 6,917. Full and PREVIEW lint pass. Production
  RTL is restored byte-for-byte; routing and fidelity gates are skipped after
  the hard deterministic mapped/floor failure.
- **Decision:** rejected and reverted. Keep the two existing threshold
  predicates; the mapper covers them materially better in whole-design
  context than either shared form.
- **Repeat only if:** if rejected, retry only after the phaser remainder
  formula/domain, R.57 quotient split, downstream DQ correction selection, or
  mapper threshold/comparator lowering changes materially.

## Hypothesis H128

- **ID:** H128.
- **Hypothesis:** `psg_seq` receives the already-qualified one-cycle write
  pulse `cs_wr = cs && rw && !cs_wr_q`, but every foreground, music, fade and
  mask decoder tests `cs && rw` again. At this module boundary `cs -> rw` is
  invariant, so removing only the redundant internal `rw` terms and port may
  simplify the shared write-decode cone without changing any accepted bus
  edge, address, data, priority, or sequencer action.
- **Scope:** prove the top-level implication and all five write-event classes
  for every `cs/rw/cs_wr_q/addr` tuple with exhaustive enumeration and a Yosys
  SAT miter; synthesize the complete registered event decoder in isolation.
  Only if that deterministic isolated gate improves may `rtl/psg_seq.sv` and
  its `rtl/psg.sv` instantiation change, followed by full/PREVIEW lint and a
  forced canonical whole-PSG map. Routing and the H102 fidelity battery remain
  conditional on deterministic mapped/floor improvement. Keep the public PSG
  bus, `psg_aram` wrapper, state/ARAM ownership, schedule, EBRs, R.84/B2 files,
  images, Tang paths, and all tolerances unchanged.
- **Baseline:** accepted H102/I003 RTL at commit `4cbd3bb`; H113's
  source-identical `build/experiments/h113/baseline.json` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs, floor 6,868, and
  routes in 7,087 LCs at 140.92/32.65 MHz. The live source has five
  `psg_seq` write-decode sites that all repeat `rw` after `cs_wr` qualification.
- **Changed condition versus H106, H111 and H126:** H106 factored ARAM pointer
  updates, H111 hoisted a registered readback next-state assignment, and H126
  tested control-ROM replay history. H128 changes no pointer, readback, replay,
  or control-history mechanism; it tests only a Boolean implication created by
  the composed top-level write-pulse boundary.
- **Change:** proof-first registered event-decoder comparison; production RTL
  remains unchanged until the isolated deterministic gate passes.
- **Result:** exhaustive enumeration covers all 2,048
  `cs/rw/cs_wr_q/addr` tuples and proves `cs_wr -> rw` plus equality of all
  five event classes; the unconstrained Yosys SAT miter also passes. The
  complete registered baseline and candidate event decoders both map to nine
  LUT4s, zero carries and four packed flops. Yosys already absorbs the repeated
  `rw` through the composed pulse expression, so production RTL, lint,
  whole-PSG mapping, routing and fidelity gates are skipped.
- **Decision:** rejected before production RTL. Keep the explicit qualifiers;
  removing them changes source and module shape without changing a
  deterministic mapped resource.
- **Repeat only if:** if rejected, retry only after the PSG bus write-pulse
  contract, `psg_seq` module boundary, write-event classes, or mapper
  cross-module Boolean simplification changes materially.

## Hypothesis H129

- **ID:** H129.
- **Hypothesis:** all `sfx_id` accesses encode the slot bank in index bit two:
  CPU writes target foreground slots, music launches target music slots, the
  trigger path reads the current bank, and status selects one member of each
  channel pair. Splitting the live eight-entry FF array into foreground and
  music four-entry banks may replace eight-way read/write steering with two
  four-entry banks and a final bank mux, reducing the 45 unpackable `sfx_id`
  flops or its selection cone without changing any stored bit.
- **Scope:** prove reset, independent/simultaneous foreground and music writes,
  current-slot reads, and all four audible channel reads over arbitrary stored
  values; synthesize the complete registered storage/read consumer in
  isolation. Only after exactness and a deterministic isolated floor win may
  `rtl/psg_seq.sv` change, followed by full/PREVIEW lint and forced canonical
  whole-PSG mapping. Route and run the H102 fidelity battery only after a
  deterministic mapped/floor win. Preserve all IDs, write priorities, status
  timing, public interfaces, schedule, EBRs, R.84/B2 files, images, Tang paths,
  and tolerances.
- **Baseline:** accepted H102/I003 RTL at docs commit `af9e2a2`; H113's
  source-identical `build/experiments/h113/baseline.json` maps 6,360 LUT4s,
  1,321 carries, 1,458 flops, 508 unpackable flops, 14 EBRs and floor 6,868;
  `sfx_id` accounts for 45 unpackable flops and 20 named LUT4s.
- **Changed condition versus R.6b/R.38 and H100:** R.6b/R.38 priced moving or
  serializing `sfx_id` through the state record, while H100 partitioned four
  invariant-zero `released` entries that Yosys had already pruned. H129 keeps
  all 48 live `sfx_id` bits in FFs and every combinational observation; it only
  exposes the fixed foreground/music bank already present in every index.
- **Change:** proof-first two-bank storage/read consumer; production RTL remains
  unchanged until the isolated deterministic gate passes.
- **Result:** the control/index model passes 16,384 reset, independent and
  simultaneous write, current-slot, and audible-select cases. The Yosys SAT
  miter proves next-state and all reads equal for arbitrary 48-bit stored
  state and arbitrary six-bit write data. The complete registered baseline
  maps to 76 LUT4s, zero carries, 48 flops and 48 unpackable cells; the split
  candidate maps to 86 LUT4s, zero carries, 48 flops and 48 unpackable cells.
  Production RTL, lint, whole-PSG mapping, routing and fidelity are skipped at
  the failed deterministic isolated gate.
- **Decision:** rejected before production RTL. Keep one eight-entry array;
  the bank split adds ten LUT4s without retiring any mapped or unpackable flop.
- **Repeat only if:** if rejected, retry only after `sfx_id` access topology,
  slot-bank ownership, read/write collision classes, or mapper array lowering
  changes materially.

## Hypothesis H130

- **ID:** H130.
- **Hypothesis:** CPU status readback currently builds all four channel-wide
  `aud_sfx_bits` and `aud_row_bits` payloads in `psg_seq`, then dynamically
  selects one channel in `psg.sv`. Selecting the addressed channel and its
  audible foreground/music slot before reading the payload may remove the
  intermediate 44-bit status bus and late mux while preserving the existing
  activity bit and byte format.
- **Scope:** prove both row/SFX address classes, all four channels, all 256
  play masks, and arbitrary ID/row payloads with an unconstrained SAT miter;
  synthesize the complete registered readback consumer in isolation. Only if
  exactness and a deterministic isolated floor win both pass may a selected
  status output be added to `rtl/psg_seq.sv`/`rtl/psg.sv`, retaining the
  existing all-channel data for `DBG_PORT=1`. Then run full/PREVIEW lint and a
  forced canonical whole-PSG map; route and run the H102 fidelity battery only
  after deterministic mapped/floor improvement. Preserve read latency and
  bytes, debug content, interfaces outside `psg`, schedule, EBRs, R.84/B2
  files, images, Tang paths, and tolerances.
- **Baseline:** accepted H102/I003 RTL at docs commit `0e58bbb`; H113's
  source-identical baseline maps 6,360 LUT4s, 1,321 carries, 1,458 flops, 508
  unpackable flops, 14 EBRs and floor 6,868. The mapped census attributes 86
  LUT4s to `dout`, 20 to `sfx_id`, and 20 unpackable flops to `aud_row`.
- **Changed condition versus H033 and H129:** H033 replaced only the activity
  bit with its paired-slot OR and mapped identically; H129 repartitioned the
  stored ID FF array and was larger. H130 leaves both representations intact
  and changes only the payload-selection order across the internal module
  boundary.
- **Change:** proof-first direct selected-status registered consumer;
  production RTL remains unchanged until the isolated deterministic gate
  passes.
- **Result:** the control/index model passes all 2,048 play-mask, channel and
  row/SFX-class cases. The unconstrained Yosys SAT miter proves byte equality
  for arbitrary 48-bit ID and 20-bit row payloads. The complete registered
  baseline maps to 61 LUT4s, zero carries and seven packed flops; the direct
  selected candidate maps to 63 LUT4s, zero carries and seven packed flops.
  Production RTL, lint, whole-PSG mapping, routing and fidelity are skipped at
  the failed deterministic isolated gate.
- **Decision:** rejected before production RTL. Keep the all-channel buses and
  late selection; ABC covers that form two LUT4s smaller in the full consumer.
- **Repeat only if:** if rejected, retry only after the status interface,
  channel/slot selection topology, debug consumers, or mapper cross-module mux
  lowering changes materially.

## Hypothesis H131

- **ID:** H131.
- **Hypothesis:** at `V_ST`, `aud_sl(c[1:0], play_bits) == c` is exactly
  `play_bits[{1'b0,c[1:0]}] != c[2]`: a foreground slot owns the audible row
  only while it plays, and its music partner owns it otherwise. Spelling this
  one-bit relation directly may simplify the enables feeding all twenty
  `aud_row` flops without changing which slot publishes each channel row.
- **Scope:** prove every slot/play-mask/phase tuple and arbitrary prior/new row
  values with SAT; synthesize the complete four-entry resettable row writer in
  isolation. Only after exactness and a deterministic isolated floor win may
  the one predicate in `rtl/psg_seq.sv` change, followed by full/PREVIEW lint
  and forced canonical whole-PSG mapping. Route and run the H102 fidelity
  battery only after a deterministic mapped/floor win. Preserve row values,
  write clocks, CPU/debug status, slot pairing, schedule, EBRs, R.84/B2 files,
  images, Tang paths, and tolerances.
- **Baseline:** accepted H102/I003 RTL at docs commit `f91da55`; H113's
  source-identical baseline maps 6,360 LUT4s, 1,321 carries, 1,458 flops, 508
  unpackable flops, 14 EBRs and floor 6,868; `aud_row` accounts for twenty
  unpackable flops.
- **Changed condition versus H033 and H130:** H033 changed the CPU readback
  activity bit and mapped identically; H130 reordered status payload selection
  and was larger. H131 touches neither readback nor payload selection: it tests
  the same slot-pair invariant at the distinct registered row-writer enable.
- **Change:** proof-first direct ownership predicate; production RTL remains
  unchanged until the isolated deterministic gate passes.
- **Result:** exhaustive enumeration covers all 65,536 reset, phase, slot and
  play-mask tuples. The unconstrained Yosys SAT miter proves next-row-state
  equality for arbitrary prior rows and write data. Both complete resettable
  four-entry row writers map to 18 LUT4s, zero carries, twenty flops and twenty
  unpackable cells. Production RTL, lint, whole-PSG mapping, routing and
  fidelity are skipped at the mapping-identical isolated gate.
- **Decision:** rejected before production RTL. Keep `aud_sl(...) == c`; Yosys
  already lowers it to the same registered write enables as the direct XOR.
- **Repeat only if:** if rejected, retry only after audible-slot pairing,
  `V_ST` publication timing, row-mirror storage, or mapper dynamic-index/equality
  lowering changes materially.

## Hypothesis H132

- **ID:** H132.
- **Hypothesis:** the reciprocal lookup is physically one 256x16 iCE40 EBR but
  stores only fifteen quotient bits. All non-tail `/3`, `/7`, and `/15`
  second-fold addresses are at most 118, while the direct tilted/triangle tail
  ignores the lookup result. Override only a live non-organ tail lookup to
  unused address 255 and store a one there in the spare EBR output bit. That
  stage-aligned bit can replace `tilt_tail_r` without adding a memory, port,
  register, result selector, or decoded arithmetic-payload sentinel.
- **Scope:** prove every wave/alternate/secondary/phase context, the complete
  reciprocal address bound, one-cycle token alignment, and unchanged waveform
  output with exhaustive and SAT checks; synthesize the complete registered
  waveform consumer in isolation first. Only after exactness and a
  deterministic isolated floor win may `rtl/psg_wave.sv` change, followed by
  full/PREVIEW lint and a forced canonical whole-PSG map. Route and run the
  H102 fidelity battery only after a deterministic whole-PSG mapped/floor win.
  Preserve the reciprocal quotient contents and latency, all waveform values,
  DQ logic, schedule, interfaces, 14-EBR topology, R.84/B2 files, images, Tang
  paths, and tolerances.
- **Baseline:** accepted H102/I003 RTL at docs commit `5c31106`; production RTL
  is byte-identical to H102 `ccfb2a0`. H113's source-identical
  `build/experiments/h113/baseline.json` maps 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs and floor 6,868, and routes in
  7,087 LCs at 140.92/32.65 MHz. A fresh all-context source audit bounds every
  ordinary reciprocal address to 0..118 and confirms address 255 is unused.
- **Changed condition versus H066 and R.67:** H066 encoded the token in
  `rc_h2_r=7'h7f`, paid a new all-bits decoder on a live arithmetic payload,
  and globally added 42 LUT4s/four carries/40 floor cells. R.67 added a second
  registered reciprocal port and two EBRs. H132 changes neither payload nor
  port topology: it uses the existing EBR's otherwise-unused sixteenth data
  bit and an address whose quotient outputs are don't-care on the tail path,
  directly targeting both physical costs that rejected H066/R.67.
- **Change:** proof-first spare-bit EBR token with reserved address 255;
  production RTL remains unchanged until exactness and isolated physical gates
  pass.
- **Result:** the exhaustive model covers all 2,097,152
  wave/alternate/secondary/phase contexts and proves the complete output
  unchanged. Ordinary addresses are exactly 0..118, discarded tail addresses
  are 0..75, and address 255 is unreachable without the token override. The
  combinational address SAT proof and one-edge registered `t_div` SAT proof
  both pass. Both complete consumers retain one EBR. The candidate retires one
  FF and one carry, but grows 696 -> 701 LUT4s; unpackable FFs fall only
  66 -> 65, so the deterministic floor worsens 762 -> 766 cells.
- **Decision:** rejected before production RTL. The spare EBR output bit is
  physically available and exact, but moving the non-organ predicate onto the
  reciprocal address plus consuming the new EBR bit costs four net floor
  cells. Production RTL, lint, whole-PSG mapping, routing and fidelity are
  skipped at the failed isolated gate.
- **Repeat only if:** if rejected, retry only after reciprocal EBR width,
  reachable address domains, tail-result ownership, pipeline alignment, or
  mapper EBR-output lowering changes materially.

## Hypothesis H133

- **ID:** H133.
- **Hypothesis:** H132 paid an eight-bit mux to force the reserved address
  `8'hff`, even though every ordinary reciprocal address is below 128 and the
  quotient payload is ignored on every token transaction. Preserve the seven
  ordinary low address bits and set only the otherwise-unreachable address
  MSB from the non-organ tail predicate. Program the reciprocal EBR's spare
  data bit as the address MSB across addresses 128..255. The registered spare
  output bit remains the exact tail token while the address override shrinks
  from eight selected bits to one.
- **Scope:** adapt H132's all-context exhaustive proof and registered SAT miter
  to the high-half token plane, then synthesize the same complete registered
  waveform consumer in isolation. Only after exactness and a deterministic
  isolated floor win may `rtl/psg_wave.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H102 fidelity
  battery only after a deterministic whole-PSG mapped/floor win. Preserve the
  reciprocal quotient payloads for every ordinary address, pipeline latency,
  all waveform values, DQ logic, schedule, interfaces, one-EBR topology,
  R.84/B2 files, images, Tang paths, and tolerances.
- **Baseline:** accepted H102/I003 production RTL at docs commit `03da590`;
  H113's source-identical whole-PSG baseline is 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs and floor 6,868, routed in 7,087
  LCs at 140.92/32.65 MHz. H132's complete isolated consumer is 696 LUT4s,
  250 carries, 96 FF, 66 unpackable and floor 762 with one EBR.
- **Changed condition versus H066, R.67, and H132:** H066 decoded a sentinel
  in the live arithmetic payload; R.67 added a registered memory port and two
  EBRs; H132 selected all eight address bits to one reserved word and worsened
  the isolated floor by four. H133 changes only the existing address MSB and
  uses all 128 unreachable high-half words as one token plane, directly
  removing the seven low-bit muxes that made H132 lose. This is the second and
  final current spare-bit-token form under the two-variant stop rule.
- **Change:** proof-first one-bit address-MSB token plane; production RTL
  remains unchanged until exactness and isolated physical gates pass.
- **Result:** the all-context proof again covers 2,097,152 tuples and proves
  the complete output unchanged. Ordinary addresses remain exactly 0..118;
  token transactions map to 128..203 with the low seven address bits
  preserved. Address-domain and registered `t_div` SAT proofs pass. Both
  complete consumers retain one EBR. The candidate retires one FF and one
  carry, but grows 696 -> 699 LUT4s; unpackable FFs fall 66 -> 65, so the
  deterministic floor worsens 762 -> 764 cells.
- **Decision:** rejected before production RTL. The one-bit address overlay
  recovers two of H132's four lost floor cells but remains a net regression.
  Production RTL, lint, whole-PSG mapping, routing and fidelity are skipped at
  the failed isolated gate. H132 and H133 close the current reciprocal
  spare-bit tail-token family under the two-variant stop rule.
- **Repeat only if:** if rejected, close reciprocal spare-bit tail tokens until
  reciprocal EBR width, reachable address domains, tail-result ownership,
  pipeline alignment, or mapper EBR-output lowering changes materially.

## Hypothesis H134

- **ID:** H134.
- **Hypothesis:** the two signed wavetable neighbour bytes have disjoint,
  adjacent lifetimes. `wt_p1` is loaded at W2 and consumed by the W4
  interpolation request on the same edge that `wt_q1` is loaded; `wt_q1` is
  then consumed at W15. Store both in one eight-bit register. Select `smp_a`
  at W4 or `smp_b` at W15 before one shared nine-bit subtract, replacing the
  two parallel `wt_pd`/`wt_qd` subtracts and their result selector while
  preserving the request and sign-capture edges.
- **Scope:** prove all signed-byte/sample-low-bit arithmetic and the W2 -> W4
  -> W15 registered sequence with exhaustive and SAT checks; synthesize the
  complete registered wavetable-byte/request/sign consumer in isolation. Only
  after an isolated deterministic floor win may `rtl/psg_walk.sv` change,
  followed by full/PREVIEW lint and a forced canonical whole-PSG map. Route
  and run the H102 fidelity battery only after a deterministic whole-PSG
  mapped/floor win. Preserve wavetable reads, phase fractions, request modes
  and timing, interpolation rounding, all sample values, schedule, interfaces,
  EBR topology, R.84/B2 files, images, Tang paths, and tolerances.
- **Baseline:** accepted H102/I003 production RTL at docs commit `0bd30dc`;
  H113's source-identical whole-PSG baseline is 6,360 LUT4s, 1,321 carries,
  1,458 flops, 508 unpackable flops, 14 EBRs and floor 6,868, routed in 7,087
  LCs at 140.92/32.65 MHz. The fresh isolated consumer baseline will be
  recorded before any production edit.
- **Changed condition versus design 5c and lifetime DNR families:** design 5c
  retired both `wt_pf`/`wt_qf` phase-fraction registers and lengthened live
  phase cones, producing -20 FF but +99 LUT4/+70 placed LCs. H134 leaves both
  fractions and their timing untouched. It aliases two consecutive sample
  bytes inside one interpolation family and removes one complete subtract plus
  the existing result selector, so arithmetic leaves with the eight FFs and
  no new downstream selector is introduced. Both bytes refresh on every
  wavetable visit regardless of play/amplitude, covering the persistent
  zero-amplitude class that blocks fraction aliasing.
- **Change:** merge `wt_p1`/`wt_q1` into `wt_x1`, select the live `smp_a` or
  `smp_b` base before one nine-bit `wt_d` subtract, and feed both interpolation
  requests plus their sign capture from that result. Keep simulation-only
  `wt_p1`/`wt_q1` trace aliases after all hardware logic and behind
  `ifndef SYNTHESIS` so the established value-lineage schema still elaborates
  without perturbing synthesis ordering.
- **Result:** the source-bound exhaustive model passes all 131,072 signed-byte/
  signed-nine-bit arithmetic cases and 917,504 W2 -> W4 -> W15 sequence checks;
  the corrected four-step nonblocking SAT miter also passes. The complete
  isolated consumer improves 46 -> 20 LUT4s, 16 -> 8 carries and 25 -> 17
  flops. The whole PSG keeps 6,360 LUT4s and 14 EBRs while moving 1,321 ->
  1,317 carries, 1,458 -> 1,450 flops, 508 -> 500 unpackable flops and floor
  6,868 -> 6,860 cells. Seed-1 router2 places 7,086 LCs and routes at
  133.92 MHz fast / 33.04 MHz PSG. The simulation aliases initially changed
  synthesis ordering when placed above the datapath; moving them after the
  final sequential block restores the 6,360-LUT map, and the final ASC is
  byte-identical to the pre-alias candidate at SHA-256
  `b4c0f70e1b48e705dbe312ee96dac8a97745d950b473498fd872e5fdc127d601`.
  Full/PREVIEW lint and `make test-psg` pass; the latter retains 524/850 walk
  clocks and 4,008/5,103 tick clocks with zero late flips. All 59 frozen
  renders are byte-identical. Ordinary `/4`, `/5`, `/6` cadence remains 572
  clocks and multipumped cadence remains 524, with every tick window clean.
  All eight active PREVIEW checks at 1,275 and 159 clocks/sample pass, recovery
  reports no coalesced/delayed/dropped samples, and both four-second SFX-10
  renders contain zero `click-v1` events. Clock-divider checks pass. The fresh
  five-frame Celeste smoke reports 2,079/3,668 off-centre samples, range
  -21,544..7,711, and 1,014 levels.
- **Decision:** accepted. H134 saves four deterministic carries, eight flops,
  eight unpackable/floor cells and one routed LC without changing any render,
  schedule, interface, EBR, R.84/B2, Tang, image or tolerance surface.
- **Repeat only if:** revisit only after wavetable byte-read phases,
  interpolation request timing, sample-byte persistence, subtract ownership,
  or mapper register-input/arithmetic sharing changes materially.

## Hypothesis H135

- **ID:** H135.
- **Hypothesis:** `smp_b` is last consumed at phase 44, on the same edge that
  the non-wavetable path first writes `mx_new`; the wavetable path does not
  need `mx_new` until its phase-54 write, also after `smp_b` is dead. Store the
  signed 17-bit current-arm result in `smp_b[16:0]`, sign-extend both result
  writes into the existing 18-bit register, and expose the late role as its
  signed low slice. This should retire the complete 17-bit `mx_new` lifetime
  without adding a new control phase or downstream result selector.
- **Scope:** prove every full/PREVIEW wavetable, non-wavetable, audible and
  hidden path across the phase-44 same-edge consume/write boundary and the
  phase-54 delayed write; synthesize a complete registered sample/result
  consumer in isolation first. Only after an exact proof and deterministic
  isolated floor win may `rtl/psg_walk.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H134 battery
  only after a deterministic whole-PSG mapped/floor win. Preserve sample and
  gain arithmetic, stage-leaf timing, current/old-arm selection, reverb,
  filtering, mixing, schedule, interfaces, 14-EBR topology, R.84/B2 files,
  Tang paths, images and tolerances.
- **Baseline:** accepted H134 commit `b96536d`: 6,360 LUT4s, 1,317 carries,
  1,450 flops, 500 unpackable flops, 14 EBRs and floor 6,860, routed in 7,086
  LCs at 133.92/33.04 MHz. The fresh isolated registered consumer baseline
  will be recorded before any production edit.
- **Changed condition versus R.40--R.42:** R.40 merged late `mx_filt` into
  `smp_b`, R.41 merged `mx_new` into `nz_old_out_r`, and the three failures
  closed unchanged register/fanout pairings. None tested `mx_new` in `smp_b`.
  H134 has now replaced `smp_b`'s dedicated wavetable subtract with a shared
  selected-base subtract, materially changing the host cone, and proved that
  a same-edge adjacent lifetime can retire both state and arithmetic. H135 is
  therefore a new host/guest pair under a changed fanout condition, not a
  retry of the rejected spellings.
- **Change:** proof-first adjacent `smp_b`/`mx_new` storage role; production
  RTL remained unchanged pending exactness and isolated physical gates.
- **Result:** the exhaustive model passes all 262,144 sample representations
  and 262,144 independent phase-44/phase-54 result transactions. Separate
  nine-step non-wavetable and wavetable SAT miters prove the reset, sample
  writes, same-edge phase-44 consume/result write, delayed phase-54 result
  write and phase-59 mix output for arbitrary payloads. The complete isolated
  registered consumer changes 58 -> 95 LUT4s, 34 carries unchanged and 72 ->
  55 flops. Packing improves from 53 packed/19 unpackable to 54 packed/one
  unpackable, but the deterministic floor still worsens 77 -> 96 cells.
- **Decision:** rejected before production RTL. The shared host removes the
  intended seventeen flops, but combining the early sample and late current-
  arm fanout creates 37 LUT4s and nineteen net floor cells. Production RTL,
  lint, whole-PSG mapping, routing and fidelity are skipped at the failed
  isolated gate.
- **Repeat only if:** retry only after `smp_b` or `mx_new` write/
  consume phases, current-arm result width, wavetable/non-wavetable ownership,
  or mapper register-input/fanout lowering changes materially.

## Hypothesis H136

- **ID:** H136.
- **Hypothesis:** every ordinary shared-multiplier request already carries its
  arithmetic sign redundantly in `mul_start_a[23]` and `[24]`, while the
  complete magnitude result leaves `m_res[33]` constant zero. Preserve the
  request sign in that result bit. For the live/old gain paths, copy the prior
  result token into bit 23 of the numerically positive `x*341` request so the
  second transaction retains the original waveform sign. The wavetable
  interpolation and gain consumers can then read the transaction-aligned
  result token directly, retiring both full-schedule `mxs_new` and `mxs_old`;
  PREVIEW keeps a separate local sign because it uses its own parallel product.
- **Scope:** first prove every walker/sequencer request arm's bit-23 token,
  every single-clock and multi-pumped multiplier transaction, the chained
  reciprocal token, and the W4/W15/W26/W27/W40/W51 consumers. Synthesize the
  complete registered multiplier-plus-sign consumer in isolation. Only after
  exactness and a deterministic isolated floor win may `rtl/psg_mulsvc.sv`,
  `rtl/psg_mulmp.sv`, and `rtl/psg_walk.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H134 battery
  only after a deterministic whole-PSG mapped/floor win. Preserve multiplier
  magnitudes, result slices, iteration counts, request/consume phases,
  interpolation and gain rounding, PREVIEW behavior, interfaces, 14-EBR
  topology, R.84/B2 files, Tang paths, images and tolerances.
- **Baseline:** accepted H134 commit `b96536d`: 6,360 LUT4s, 1,317 carries,
  1,450 flops, 500 unpackable flops, 14 EBRs and floor 6,860, routed in 7,086
  LCs at 133.92/33.04 MHz. The fresh isolated service/sign-consumer baseline
  will be recorded before any production edit.
- **Changed condition versus H063, H132/H133, and H135:** H063 reconstructed
  only `mxs_old` from a later live value and its one-FF retirement regressed
  globally. H132/H133 moved `tilt_tail_r` into a reciprocal-EBR token and paid
  address/output selection. H135 combined unrelated early-sample and late-mix
  fanout in one register. H136 instead attaches the sign to the multiplication
  transaction that already produces the magnitude, uses a currently dead
  result position, preserves the token explicitly through the one chained
  request, and removes two sign lifetimes without merging their fanout into a
  sample or mix register.
- **Change:** proof-first multiplier result-token and full-schedule sign-state
  retirement; production RTL remains unchanged until the exactness and
  isolated physical gates pass.
- **Result:** the source-bound exhaustive proof covers all 262,144 signed-18
  inputs, 12,582,912 transaction/mode/corner combinations and 524,288 chained
  sign cases. Radix-2, radix-4 and request-load SAT miters pass, and both
  isolated forms lint clean apart from expected scratch/source warnings. The
  first shared-magnitude probe changes 194 -> 158 LUT4s, 75 -> 56 carries and
  keeps 117 flops, but increases unpackable flops 25 -> 62 and the floor 219
  -> 220. A second production-shaped probe gives the interpolation, live-gain
  and old-gain consumers distinct arithmetic and one mutually exclusive
  consume selector. It changes 249 -> 251 LUT4s, keeps 86 carries and 128
  flops, reduces unpackable flops 25 -> 24, and still worsens the floor 274 ->
  275. The missing state saving is structural: radix-2 baseline `req_b[12]`
  and `m_p[33]` are both constant/pruned, while the candidate must activate
  both to cross and retain the sign token, exactly replacing the two retired
  walker sign flops.
- **Decision:** rejected before production RTL. Exactness is established, but
  neither complete isolated consumer meets the deterministic floor gate.
  `rtl/psg_mulsvc.sv`, `rtl/psg_mulmp.sv`, `rtl/psg_walk.sv`, whole-PSG
  synthesis, routing and the fidelity battery remain untouched/skipped.
- **Repeat only if:** if rejected, retry only after multiplier result width,
  request signedness, reciprocal chaining, sign-consumer phases, or mapper
  cross-domain/result-bit lowering changes materially.

## Hypothesis H137

- **ID:** H137.
- **Hypothesis:** the constants EBR words 112..143 serve only the music fade
  lookup. A `$22` write already stores the complete eight-bit `fade_len`, and
  a later `$20` command only needs the exact function `4096 / fade_len[7:3]`
  for values 1..31. Decode that 32-entry function directly at the `$20`
  commit edge. This should retire the 13-bit `fstep_q`, `crom_replay`,
  `ctrl_displaced`, the fade lookup address arm and the control-word replay
  stall without adding persistent state or changing `fade_step` itself.
- **Scope:** prove all 256 `$22` values, both `$20` start/stop forms, adjacent
  and delayed writes, reset/readback state, and the absence of a control-ROM
  collision once `$22` no longer borrows its port. Synthesize a complete
  registered fade-command/control consumer in isolation first. Only after an
  exact proof and deterministic isolated floor win may `rtl/psg_seq.sv` and
  `tools/gen_psg_tables.py` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the H134 fidelity battery only after
  a deterministic whole-PSG mapped/floor win. Preserve CPU-visible `$20`/
  `$22` semantics, fade progression, sequencer/walker control words, sample
  and tick cadence, interfaces, 14-EBR topology, R.84/B2 files, Tang paths,
  images and tolerances.
- **Baseline:** accepted H134 commit `b96536d`: 6,360 LUT4s, 1,317 carries,
  1,450 flops, 500 unpackable flops, 14 EBRs and floor 6,860, routed in 7,086
  LCs at 133.92/33.04 MHz. The fresh isolated registered consumer baseline
  will be recorded before any production edit.
- **Changed condition versus R.15 and H126:** R.15 retained the shared-EBR
  lookup to eliminate a dedicated fade-table EBR, paying a borrow/replay mux
  and `fstep_q`. H126 tried to reconstruct only `ctrl_displaced` while keeping
  the collision; its same-edge counterexample therefore remains valid. H137
  removes the fade lookup from the EBR entirely, so `$22` cannot displace a
  walker control read and neither replay token has a remaining event to
  represent. It keeps R.15's one-EBR topology and does not alter the walker's
  control-store contents.
- **Change:** proof-first direct fade-step decoder and complete command/control
  consumer; production RTL remains unchanged until exactness and isolated
  physical gates pass.
- **Result:** the source-bound table proof confirms all 32 generated words,
  2,560 adjacent/delayed start/stop command cases and 512 ordered control-word
  cases; the all-index SAT miter passes after memory flattening. Both isolated
  forms lint clean. The complete registered consumer keeps one EBR and 20
  carries while changing 106 -> 125 LUT4s, 62 -> 47 flops and 28 -> one
  unpackable flop, so its deterministic floor improves 134 -> 126 cells.
  After the minimal `psg_seq.sv` patch, full/PREVIEW lint passes with only the
  pre-existing warnings. The canonical whole-PSG map instead changes 6,360 ->
  6,444 LUT4s, 1,317 -> 1,318 carries, 1,450 -> 1,448 flops, 500 -> 488
  unpackable flops, keeps 14 EBRs, and worsens the floor 6,860 -> 6,932 cells.
- **Decision:** rejected and reverted before routing or fidelity work. The
  flattened sequencer/control cover pays 84 LUT4s for the small decode despite
  the isolated state/packing win. `rtl/psg_seq.sv` is byte-identical to H134;
  no generator, route, render, cadence, image, Tang, tolerance or R.84/B2 file
  changed.
- **Repeat only if:** if rejected, retry only after fade-step quantization,
  `$22`/`$20` command timing, constants/control-ROM port ownership, or mapper
  small-ROM lowering changes materially.

## Hypothesis H138

- **ID:** H138.
- **Hypothesis:** `nz_out_r` and `nz_old_out_r` store the live and old
  pre-clamp noise sums only so their arithmetic-right-shifted values can be
  scaled on the following phases. The clamped persistent state is within
  +/-6,143, the exact shared-product noise step is within +/-33,324, and the
  optional kick is within -6,160..+6,167. Even their conservative independent
  sum is -45,627..45,634, which fits signed 17 bits. Narrow both registers and
  sign-extend only at their unchanged signed-18 shift/scale consumers.
- **Scope:** derive the bounds from the live RTL widths and exhaustive LFSR
  draw domains, prove every signed-17 round trip and both shifted/scaled
  consumers with SAT, and synthesize the complete registered boundary in
  isolation. Only after exactness and a deterministic isolated floor win may
  `rtl/psg_walk.sv` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the H134 fidelity battery only after
  a deterministic whole-PSG mapped/floor win. Preserve noise arithmetic,
  clamp limits, random sequences, request/consume phases, all sample values,
  schedule, interfaces, 14-EBR topology, R.84/B2 files, Tang paths, images and
  tolerances.
- **Baseline:** accepted H134 commit `b96536d`: 6,360 LUT4s, 1,317 carries,
  1,450 flops, 500 unpackable flops, 14 EBRs and floor 6,860, routed in 7,086
  LCs at 133.92/33.04 MHz. The fresh isolated registered consumer baseline
  will be recorded before any production edit.
- **Changed condition versus H027, H062 and H065:** H027 retained the 18-bit
  combinational inputs and replaced their signed clamp comparisons; H062
  reconstructed only the old-noise activity flag; H065 narrowed the general
  `smp_a`/`smp_b` waveform boundary to 16 bits and regressed globally. H138
  keeps both clamp inputs and every sum at 18 bits, contracts only two
  post-sum/pre-scale registers to their distinct proved 17-bit domain, and
  restores the original width immediately at their sole consumers.
- **Change:** narrow both registered boundaries to signed 17 bits and restore
  explicit signed-18 values only at the two unchanged shift/scale consumers.
- **Result:** the source-derived exhaustive proof covers draws -880..881, the
  maximum-magnitude step 33,324, the complete stored range
  -45,627..45,634, and 182,524 scaled-consumer cases. Unconstrained SAT proves
  signed-17 round-trip plus both shifted/scaled consumers, and full/PREVIEW
  lint reaches only the baseline warning set. The complete isolated registered
  consumer improves 78 -> 72 LUT4s, 44 -> 40 carries, 56 -> 54 flops and
  floor 106 -> 100 cells. The forced canonical whole-PSG map instead changes
  H134's 6,360 LUT4s, 1,317 carries, 1,450 flops, 500 unpackable flops and
  6,860-cell floor to 6,389 LUT4s, 1,310 carries, 1,448 flops, 499 unpackable
  flops and a 6,888-cell floor, with 14 EBRs unchanged. The +29 LUT4/+28 floor
  regression rejects composition despite -7 carries/-2 flops; route and the
  H134 fidelity battery are intentionally skipped. `rtl/psg_walk.sv` is
  restored byte-identically to H134.
- **Decision:** rejected and reverted at the whole-PSG area gate. The narrower
  storage entangles signed-extension/scale selection with the full walker cone
  more expensively than it saves state.
- **Repeat only if:** if rejected, retry only after clamped-noise bounds,
  multiplier step range, kick range, stored pre-clamp consumers, or mapper
  signed-extension lowering changes materially.

## Hypothesis H139

- **ID:** H139.
- **Hypothesis:** `nz_z` and `nz_old_z` apply the same arithmetic-right-shift
  followed by exact `x*68` or `x*80` scale to the live and old registered
  pre-clamp noise sums. In full mode the live result is consumed only at W4,
  while the old result is consumed only for its sign at W15 and its complete
  value at W27. Select `{nz_out_r,einc}` versus
  `{nz_old_out_r,s_old_inc}` from those existing control phases before one
  shared scale tree, replacing both parallel trees without adding state.
- **Scope:** audit every `z_new_c`/`z_old_sel` consumer in full and PREVIEW
  elaborations; exhaustively prove the selected signed shift/scale arithmetic
  and the W4/W15/W27 output contract; prove the complete registered consumer
  with SAT; and synthesize that consumer in isolation. Only after exactness
  and a deterministic isolated floor win may `rtl/psg_walk.sv` change,
  followed by full/PREVIEW lint and a forced canonical whole-PSG map. Route
  and run the H134 fidelity battery only after a deterministic whole-PSG
  mapped/floor win. Preserve both noise registers and their widths, clamp and
  kick arithmetic, live/old values, request/consume phases, random sequences,
  PREVIEW behavior, schedule, interfaces, 14-EBR topology, R.84/B2 files,
  Tang paths, images and tolerances.
- **Baseline:** accepted H134 commit `b96536d`: 6,360 LUT4s, 1,317 carries,
  1,450 flops, 500 unpackable flops, 14 EBRs and floor 6,860, routed in 7,086
  LCs at 133.92/33.04 MHz. The fresh isolated registered consumer baseline
  will be recorded before any production edit.
- **Changed condition versus H017, H064 and H138:** H017 selected complete
  gain contexts and globally regressed; H064 selected the pre-multiply LFSR
  draw before one XOR transform and globally regressed; H138 narrowed the two
  stored pre-clamp values and regressed globally. H139 changes no stored value
  or draw transform. It selects two schedule-exclusive post-clamp scale
  consumers before one identical shift/add tree, so a complete arithmetic
  instance leaves with the selection rather than merely shortening a width or
  retiring a register.
- **Change:** select the old scale only in full mode, for non-wavetable W15 or
  W27; otherwise select the live scale. Feed the selected registered signed-18
  value and only the selected increment bit 13 through one arithmetic-right-
  shift and exact x68/x80 tree, then retain the original `nz_z`/`nz_old_z`
  consumer names and phases.
- **Result:** the exhaustive model checks all 262,144 signed-18 values and
  1,048,576 selected live/old/increment cases; the unconstrained Yosys SAT
  miter passes. Full multi-pump and PREVIEW lint retain only the established
  warning classes. A generic isolated spelling changes floor 108 -> 111
  because its harness preserves duplicate destinations, while the complete
  production-shaped registered consumer decisively improves 95 -> 52 LUT4s,
  44 -> 22 carries, keeps 42 flops, and moves floor 120 -> 81 cells.

  Canonical whole-PSG mapping at RTL fingerprint `41bf50aae6d2` changes H134's
  6,360 LUT4s, 1,317 carries, 1,450 flops, 500 unpackable flops and 6,860-cell
  floor to **6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops and
  floor 6,800**, with 14 EBRs unchanged. Seed-1 router2 completes in **7,018
  LCs (-68)** at **142.63 MHz fast / 31.17 MHz PSG**, clearing both clocks.

  `make test-psg` passes with the unchanged 524/850 walk deadline and
  4,008/5,103 tick pre-run, 1,095 spare and zero late flips. All 59 frozen
  renders are byte-identical. Ordinary `/4`, `/5`, `/6` cadence remains 572
  clocks and multi-pumped cadence remains 524, with every write, sample
  boundary and tick window clean. All eight active PREVIEW checks at 1,275 and
  159 clocks/sample pass; recovery reports no coalesced/delayed/dropped
  samples; both four-second SFX-10 paths retain zero `click-v1` events and are
  byte-identical to H134. Clock-divider checks pass. The rebuilt five-frame
  Celeste smoke retains 2,079/3,668 off-centre samples, range -21,544..7,711,
  1,014 levels, and a byte-identical frame. Forced repeat mapping and routing
  reproduce JSON SHA-256 `4f7c4af1...` and ASC SHA-256 `cca305c1...` exactly.
- **Decision:** accepted. One complete duplicate noise-scale arithmetic tree
  retires with no state, schedule, sample, interface, EBR, R.84/B2, Tang,
  image or tolerance change.
- **Repeat only if:** if rejected, retry only after live/old scale formulas,
  W4/W15/W27 consumer phases, registered noise-value ownership, increment
  selection, or mapper mux/shift-add lowering changes materially.

## Hypothesis H140

- **ID:** H140.
- **Hypothesis:** the live noise recurrence consumed at CAP_W0 and the old-arm
  recurrence consumed at CAP_W1 each form a signed-18 sum followed by the same
  exact `noise_clamp`. The phases are disjoint, and CAP_W0's old-context
  snapshot is visible to CAP_W1. Selecting the base, step and optional live
  kick from the existing consume phase before one add/clamp cone should retire
  the duplicate old recurrence arithmetic without adding state.
- **Scope:** audit live/old recurrence ownership across CAP_W0/CAP_W1,
  transition restarts, clears, PREVIEW elaboration and every consumer;
  exhaustively prove both signed sums and clamp results, prove the complete
  registered consumer with unconstrained SAT, and synthesize that consumer in
  isolation. Only after exactness and a deterministic isolated floor win may
  `rtl/psg_walk.sv` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the H139 fidelity battery only after
  a deterministic whole-PSG mapped/floor win. Preserve both recurrence state
  registers and widths, random draws, multiplier results, kicks, clamp
  boundaries, capture phases, PREVIEW behavior, schedule, interfaces, 14-EBR
  topology, R.84/B2 files, Tang paths, images and tolerances.
- **Baseline:** accepted H139 commit `d76241f`, RTL fingerprint
  `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable
  flops, 14 EBRs and floor 6,800, routed in 7,018 LCs at 142.63/31.17 MHz.
  The complete registered-consumer baseline will be recorded before any
  production edit.
- **Changed condition versus H027, H062, H064 and H138:** H027 changed the
  clamp predicate spelling but retained both clamp consumers; H062 retired an
  old-noise activity flag; H064 selected random-draw bits before the multiply;
  H138 narrowed the stored pre-clamp values. H140 changes none of those
  representations. It selects two schedule-exclusive complete recurrence
  inputs before one identical accumulation and clamp, so a full arithmetic
  instance may leave rather than merely moving a flag, draw or width.
- **Change:** select the old recurrence only in full mode at CAP_W1; otherwise
  select the live recurrence. Feed the selected signed-18 base, conditional
  step and live-only kick through one signed sum and exact clamp, retaining the
  two original registered destinations and capture phases.
- **Result:** the exhaustive model proves all 262,144 clamp inputs and 524,288
  selected recurrence cases; the unconstrained Yosys SAT miter passes. Full
  multi-pump and PREVIEW lint retain only the established warning classes.
  The complete registered consumer changes 150 -> 142 LUT4s, 33 -> 16
  carries, keeps 68 flops, moves 36 -> 39 unpackable flops, and improves its
  estimated floor 186 -> 181 cells.

  Canonical whole-PSG mapping at RTL fingerprint `6e1933f0cc32` instead changes
  H139's 6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops and
  6,800-cell floor to **6,332 LUT4s, 1,275 carries, 1,450 flops, 501
  unpackable flops and floor 6,833**, with 14 EBRs unchanged. Seed-1 router2
  completes in **7,054 LCs (+36)** at 140.67 MHz fast / 31.66 MHz PSG; both
  clocks pass, but every authoritative area measure except carries regresses.
  Production is reverted byte-for-byte to H139. The hard physical gate fails,
  so structural, render, cadence, PREVIEW-recovery, click and smoke batteries
  are intentionally skipped.
- **Decision:** rejected and reverted. The input-selection mux and its
  entanglement with the live kick/old state cones cost more global LUT and
  packing area than the duplicate recurrence arithmetic.
- **Repeat only if:** if rejected, retry only after CAP_W0/CAP_W1 ordering,
  transition snapshot ownership, live/old recurrence formulas, clamp bounds,
  or mapper mux/add/clamp lowering changes materially.

## Hypothesis H141

- **ID:** H141.
- **Hypothesis:** full-mode soft-add microsteps 4--7 follow the same arithmetic
  sequence for positive overflow and negative underflow; only the transition
  after microstep 7 differs, with underflow taking correction step 8. The
  four-bit `fmc` has unused states 12--15 whose low bits already name steps
  4--7. Encoding the underflow path there should retire `f_under` without
  changing an operand, write, cycle, destination or publication edge.
- **Scope:** exhaustively prove the related baseline/candidate controller
  states, operation labels, write enables, busy/done events and next-state
  relation for both comparator outcomes; prove the relation with unconstrained
  SAT; synthesize the complete registered fold controller and operand decode in
  isolation. Only after a deterministic isolated floor win may
  `rtl/psg_walk.sv` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the H139 fidelity battery only after
  a deterministic whole-PSG mapped/floor win. Preserve fold arithmetic,
  `fdiv5` contents/read phase, stack values/destinations, visit schedule,
  `fold_busy`, `dry_valid`, interfaces, 14-EBR topology, R.84/B2 files, Tang
  paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and current docs
  commit `55f47f5`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291
  carries, 1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed
  in 7,018 LCs at 142.63/31.17 MHz. The complete fold-controller baseline
  will be recorded before any production edit.
- **Changed condition versus H052, H053 and H078:** H052 encoded final-fold
  ownership in `fsel`; H053 encoded publication in state 10; H078 fused the
  positive/negative threshold probes and changed the arithmetic decode. H141
  changes none of those boundaries. It uses four still-unused encodings only
  while an already-active fold executes the identical steps 4--7, replacing a
  one-bit history flop with the existing state's high bit.
- **Change:** map baseline underflow states 4--7 to candidate states 12--15;
  decode the same operations from both state ranges, transition state 15 to
  correction state 8, transition positive state 7 directly to state 9, and
  remove `f_under`.
- **Result:** exhaustive related-state checking covers all 40 legal
  state/history/comparator transitions, operation labels, writes, busy/done
  events and next-state relations; the unconstrained Yosys SAT miter passes.
  The complete registered fold controller keeps 93 LUT4s and zero carries,
  changes 23 -> 22 flops and 19 -> 18 unpackable flops, and improves its
  estimated floor 112 -> 111 cells.

  Canonical whole-PSG mapping at RTL fingerprint `55b5904db174` instead
  changes H139's 6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops
  and 6,800-cell floor to **6,326 LUT4s, 1,295 carries, 1,449 flops, 494
  unpackable flops and floor 6,820**, with 14 EBRs unchanged. Seed-1 router2
  completes in **7,049 LCs (+31)** at 123.30 MHz fast / 31.77 MHz PSG; both
  clocks pass, but every authoritative area measure except state count
  regresses. Production is reverted byte-for-byte to H139. The hard physical
  gate fails, so structural, render, cadence, PREVIEW-recovery, click and smoke
  batteries are intentionally skipped.
- **Decision:** rejected and reverted. Activating four additional state codes
  expands the flattened controller/operand covering more than the single
  history flop saves.
- **Repeat only if:** if rejected, retry only after the soft-add microstep
  sequence, state width/occupancy, underflow correction, operand decode, or
  mapper FSM/stack covering changes materially.

## Hypothesis H142

- **ID:** H142.
- **Hypothesis:** accepted R.37 stores the old noise step in signed-17
  `mx_old` from PNZ_LIVE through its only recurrence read at CAP_W1. The same
  edge can overwrite `mx_old` with `nz_old_pre`, whose signed-17 range H138
  proved, for H139's W15/W27 scale consumers. W51 already overwrites `mx_old`
  with the old gain before its final mix consumer. These three ordered roles
  should retire all eighteen `nz_old_out_r` flops without adding a phase or a
  result selector.
- **Scope:** audit and prove PNZ_LIVE -> CAP_W1 step ownership, same-edge
  recurrence-read/pre-sum overwrite, W15/W27 sign/scale consumers, W51 gain
  overwrite and final mix consumption in full and PREVIEW elaborations;
  exhaustively prove the signed-17 sum range and every scale result, prove the
  three-role representation with unconstrained SAT, and synthesize the
  complete registered consumer in isolation. Only after exactness and a
  deterministic isolated floor win may `rtl/psg_walk.sv` change, followed by
  full/PREVIEW lint and a forced canonical whole-PSG map. Route and run the
  H139 fidelity battery only after a deterministic whole-PSG mapped/floor win.
  Preserve recurrence/gain arithmetic, clamp and scale values, role phases,
  random sequences, schedule, interfaces, 14-EBR topology, R.84/B2 files,
  Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and current docs
  commit `8d82eb5`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291
  carries, 1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed
  in 7,018 LCs at 142.63/31.17 MHz. The complete three-role registered
  consumer baseline will be recorded before any production edit.
- **Changed condition versus R.37, R.40--R.42, H138 and H139:** R.37 already
  accepted `mx_old` for the earlier old-noise step; R.41 tested the reverse
  and cross-family pairing `mx_new` into `nz_old_out_r`, which joined early
  noise and late current-arm fanout and regressed. H142 extends R.37's same
  register within the same old-noise pipeline, then returns it to its existing
  old-gain role. H138 newly proves `nz_old_pre` fits signed 17 bits, and H139
  newly centralizes the only scale tree. This exact host/guest order and
  consumer cone were not present in the rejected lifetime rows.
- **Change:** proof-first three-role alias and complete registered-consumer
  synthesis; production RTL remains unchanged until both gates pass.
- **Result:** the lifetime audit confirms `mx_old`'s old-step write at phase 24,
  read/overwrite at phase 30, and gain overwrite at phase 54; the retired
  `nz_old_out_r` is written at phase 30 and last read at phase 44. The old
  pre-clamp range is signed-17 (`-45,627..45,634`). Exhaustive proof covers
  182,524 scale cases and 131,072 role transactions, and the arbitrary-state
  SAT miter passes. The complete registered-consumer baseline maps to 69 LUT4s,
  22 carries and 91 flops, of which 61 are unpackable, for a 130-cell floor.
  The candidate maps to 86 LUT4s, 22 carries and 80 flops, of which 50 are
  unpackable, for a 136-cell floor: -11 flops/unpackable cells but +17 LUT4s
  and a six-cell deterministic floor regression.
- **Decision:** rejected before production RTL. `rtl/psg_walk.sv` remains
  byte-identical to accepted H139, so no whole-PSG map, route, fidelity or
  cadence gate remains.
- **Repeat only if:** if rejected, retry only after PNZ_LIVE/CAP_W1/W27/W51
  ordering, old pre-clamp range, `mx_old` gain ownership, H139 scale consumer,
  or mapper register-input/fanout lowering changes materially.

## Hypothesis H143

- **ID:** H143.
- **Hypothesis:** `pcm` is a sixteen-bit externally visible committed payload
  whose reset value is required, but its data flops do not themselves need
  reset if one resettable validity token gates the output to zero until the
  first `dry_valid` commit. Store `dry16` in a resetless payload register,
  set validity on the same commit edge, and expose zero while invalid. This
  preserves every reset/commit/output edge while replacing sixteen resettable,
  unpackable H139 flops with sixteen potentially packable payload flops and
  one validity flop.
- **Scope:** prove arbitrary reset, hold, first-commit, subsequent-commit and
  restart sequences; synthesize the complete registered PCM output plus a
  registered parity sink matching `target_psg` in isolation. Only after a
  deterministic isolated floor win may `rtl/psg.sv` change, followed by full
  multi-pump/PREVIEW lint and a forced canonical whole-PSG map. Route and run
  the H139 fidelity/cadence battery only after a deterministic whole-PSG
  mapped/floor win. Preserve synchronous reset priority, zero output before
  first commit, `dry16`/`dry_valid` timing, every PCM value and hold interval,
  interfaces, schedule, 14-EBR topology, R.84/B2 files, Tang paths, images and
  tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `89f247d`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The H139 census attributes sixteen unpackable flops
  to `pcm`; the complete isolated registered consumer will be recorded before
  any production edit.
- **Changed condition versus task 2.6, R.49, H117 and H120:** task 2.6 retained
  reset on externally visible state; H117/H120 simply removed reset from
  already-invalid internal payloads and did not change the mapped reset cells.
  H143 preserves the required external reset value through a new one-bit
  validity representation and specifically targets a measured sixteen-cell
  unpackable family. R.49 retired the upstream full-mode `dry16` handoff but
  deliberately retained the `pcm` commit boundary; H143 changes neither that
  result source nor its commit edge.
- **Change:** proof-first validity/payload representation and complete
  registered-consumer synthesis; production RTL remains unchanged until both
  gates pass.
- **Result:** exhaustive bitwise transition checking proves every related
  reset/hold/commit class, and a six-edge arbitrary-16-bit SAT miter passes
  after synchronous reset. The complete registered parity-sink baseline maps
  to 6 LUT4s and 17 flops, of which sixteen `pcm` flops are unpackable, for a
  22-cell floor. The candidate maps to 8 LUT4s and 18 flops: the sixteen
  payload flops become ordinary enabled flops but remain unpackable, while the
  resettable validity token is also unpackable, for a 25-cell floor. This is
  +2 LUT4s, +1 FF/unpackable and +3 deterministic floor cells.
- **Decision:** rejected before production RTL. `rtl/psg.sv` remains
  byte-identical to accepted H139, so no full/PREVIEW lint, whole-PSG map,
  route, fidelity or cadence gate remains.
- **Repeat only if:** if rejected, retry only after PCM reset observability,
  commit timing, output consumers, target sink, or mapper reset/enable packing
  changes materially.

## Hypothesis H144

- **ID:** H144.
- **Hypothesis:** accepted H039 makes every `rec_base()` result explicitly
  four-byte aligned, but `psg_seq` still forms record reads as a visible
  thirteen-bit `sa_base + sa_off`. Since the base's low two bits are zero,
  this is exactly `{sa_base[12:2] + sa_off[7:2], sa_off[1:0]}`. Exposing that
  boundary should retire two carry stages from the record-address cone without
  changing either precomputed base, the channel/instrument selector, or the
  pattern-address branch.
- **Scope:** exhaustively prove all 64 record numbers and 256 offsets, prove
  arbitrary aligned bases and the complete pattern/record selector with SAT,
  and synthesize the complete registered address consumer in isolation. Only
  after a deterministic isolated LUT/carry/floor win may `rtl/psg_seq.sv`
  change, followed by full multi-pump/PREVIEW lint and a forced canonical
  whole-PSG map. Route and run the H139 fidelity/cadence battery only after a
  deterministic whole-PSG mapped/floor win. Preserve every address, record
  selection, state and audio-RAM cycle, synchronous-read timing, interfaces,
  schedule, 14-EBR topology, R.84/B2 files, Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `f60aea7`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete scheduled address consumer baseline
  will be recorded before any production edit.
- **Changed condition versus H032, H039 and the address/storage DNR:** H032
  selected a record number before one `rec_base()` call and globally regressed;
  H144 retains both accepted call sites and their existing 13-bit selector.
  H039 accepted the aligned transform inside each pure base calculation but
  deliberately left the final offset addition unchanged. H144 consumes that
  newly explicit alignment at the distinct downstream byte-offset boundary;
  it changes no RAM ownership, record storage, replay, or CPU-visible address.
- **Change:** proof-first aligned byte-offset addition and complete registered-
  consumer synthesis; production RTL remains unchanged until both gates pass.
- **Result:** exhaustive checking covers all 16,384 record-number/offset pairs
  and the complete address range 256..4,795; the arbitrary aligned-base,
  channel/instrument, pattern/record selector SAT miter also passes. Both
  complete registered consumers map to 38 LUT4s, 16 carries and 13 fully
  packed flops, for the same 38-cell floor. Yosys already propagates the two
  aligned low bits and performs the same narrowed carry lowering through the
  accepted expression.
- **Decision:** rejected before production RTL. `rtl/psg_seq.sv` remains
  byte-identical to accepted H139, so no full/PREVIEW lint, whole-PSG map,
  route, fidelity or cadence gate remains.
- **Repeat only if:** if rejected, retry only after record-base alignment,
  offset range/ownership, pattern/record selection, RAM address registering,
  or mapper carry lowering changes materially.

## Hypothesis H145

- **ID:** H145.
- **Hypothesis:** at W84 the preceding slot's fold is complete, so the shared
  fold ALU is idle. The current dampen path still instantiates two signed-19
  adders: one for `blend_y + dmp_mul`, then one for its toward-zero bias.
  Execute those two adds on consecutive late phases through one signed-19
  extension of the fold ALU. `smp_a` is dead after phase 44 and `mxs_old` is
  dead after phase 54, so their existing 18+1 bits can hold the exact
  intermediate without new payload state; delaying only the two late `s_lp`
  state writes by one phase preserves the completed value and leaves eight
  clocks of the 48-clock `/6` margin.
- **Scope:** prove the signed ranges, all four dampen-mode arithmetic results,
  the split 19-bit intermediate, same-edge scratch overwrite, fold/dampen ALU
  selection and two late write phases with exhaustive and SAT checks. First
  synthesize the complete registered fold/dampen/scratch consumer in isolation.
  Only after a deterministic isolated LUT/carry/floor win may
  `rtl/psg_walk.sv`, `tools/gen_psg_ctrl.py` and the generated constants table
  change, followed by full multi-pump/PREVIEW lint, generator checks and a
  forced canonical whole-PSG map. Route and run the H139 fidelity/cadence
  battery only after a deterministic whole-PSG mapped/floor win. Preserve
  every dampen/fold value, PCM sequence, parameter publication, multiplier and
  fold transaction, interfaces, 14-EBR topology, R.84/B2 files, Tang paths,
  images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `4ce4b47`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The accepted schedule is 530+272 clocks against the
  850-clock minimum. The complete isolated consumer will be recorded before
  any production edit.
- **Changed condition versus task 4.3, H072, H081 and lifetime DNRs:** task
  4.3 still names dampen migration onto shared arithmetic but has no retained
  implementation. H072 kept the parallel path and only moved its rounding
  correction after the shift. H081 selected two slide adders before one chain
  but added twenty LUT4s; H145 removes two wider dampen chains, uses an ALU
  already idle at these phases, and reuses two source-derived dead scratch
  lifetimes instead of adding a result register. The rejected lifetime rows
  joined unrelated long-lived fanout cones; H145's scratch role ends before
  the next slot reloads either host.
- **Change:** proof-first two-step shared-ALU representation and complete
  registered-consumer synthesis; production RTL remains unchanged until both
  gates pass.
- **Result:** `dampen_fold_proof.py` exhausts all 524,288 signed-19 scratch
  values in four modes, 5,242,880 complete operand-boundary cases, every fold
  operation over boundary-rich data, and the shifted late-write schedule.
  Arbitrary-input SAT proves all four dampen modes, exact 19-bit split and
  reconstruction, wrapped 18-bit fold preservation, and the sequential
  W84/round/write timing. The complete registered baseline maps to 315 LUT4s,
  77 carries, 175 FFs (119 unpackable), one EBR and floor 434. The direct
  two-phase candidate maps to 346 LUT4s, 42 carries, 175 FFs (100 unpackable),
  one EBR and floor 446: -35 carries and -19 unpackable FFs, but +31 LUT4s and
  +12 floor cells. A materially different variant that encodes the rounding
  phase in `fmc=10` maps to 385 LUT4s, 42 carries, the same 175/100 FF split,
  one EBR and floor 485. The independent finish selector is therefore not the
  cause of the failed floor gate.
- **Decision:** rejected before production RTL. `rtl/psg_walk.sv`,
  `tools/gen_psg_ctrl.py`, generated constants and accepted H139 artifacts
  remain byte-identical, so no lint, whole-PSG map/route, cadence or fidelity
  gate remains.
- **Repeat only if:** if rejected, retry only after W84/fold overlap, dampen
  ranges or rounding, scratch lifetimes, late-write slack, fold-ALU width, or
  mapper selected-operand lowering changes materially.

## Hypothesis H146

- **ID:** H146.
- **Hypothesis:** `psg_wave` computes three separate narrow ceiling values for
  `ceil(dp/64)`, `ceil(dp/128)`, and `ceil(dp/256)`, but the DQ mode/wave
  decode selects exactly one of them for `dq_corr`. Select the matching
  quotient and remainder-nonzero predicate first, then use one eight-bit
  incrementer and zero-extend its selected result. This may retire two carry
  chains without changing the existing `dq_193` or phaser-mode-1 arithmetic.
- **Scope:** exhaust every 13-bit increment, wavetable bit, wave and detune
  mode; prove arbitrary-input correction/result equivalence with SAT; and
  synthesize the complete registered DQ correction consumer in isolation.
  Only after a deterministic isolated LUT/carry/floor win may
  `rtl/psg_wave.sv` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the complete H139 fidelity/cadence
  battery only after a deterministic whole-PSG mapped/floor win. Preserve
  every DQ value, phase, schedule, interface, 14-EBR topology, R.84/B2 file,
  Tang path, image and tolerance.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `dda16f5`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete isolated DQ consumer will be recorded
  before any production edit.
- **Changed condition versus H001, H081 and selected-adder DNRs:** H001 made
  each tilted-wave ceiling narrow but did not share DQ corrections. H081
  selected two registered slide accumulations with unrelated operands and
  added twenty LUT4s. H146 targets three combinational ceiling incrementers
  sourced from adjacent slices of the same `dp13`, after the existing
  mutually exclusive wave/mode decision and before the existing `dq_corr`
  extension. No prior row tests this complete DQ correction selection.
- **Change:** proof-first selected ceiling incrementer and complete registered-
  consumer synthesis; production remains unchanged until both gates pass.
- **Result:** exhaustive comparison passes all 524,288
  `{dp13,wavetable,wave,mode}` cases and arbitrary-input SAT proves the
  complete DQ result. `make test-psg-dq` passes 524,288 model cases plus
  57,344 exhaustive/chained/held service transactions; full and PREVIEW lint
  contain no errors. The complete registered consumer improves 190 -> 177
  LUT4s and 73 -> 62 carries with fourteen packed FFs unchanged, so the
  isolated floor falls 190 -> 177. The forced canonical whole PSG reverses
  that result: 6,302 -> 6,338 LUT4s, 1,291 -> 1,292 carries, 1,450 FFs and 498
  unpackable FFs unchanged, 14 EBRs unchanged, and floor 6,800 -> 6,836.
  Seed-1 routing completes at 7,061 LCs versus 7,018 and passes timing at
  146.07/31.28 MHz. The netlist scope attribution also changes broadly, so
  the isolated selected-adder win does not survive flattening.
- **Decision:** rejected and reverted before fidelity work. `rtl/psg_wave.sv`
  is byte-identical to accepted H139 and no render, cadence, recovery, click,
  smoke, image, Tang, tolerance or R.84/B2 file changed.
- **Repeat only if:** if rejected, retry only after DQ mode/wave ownership,
  correction widths, quotient/remainder boundaries, consumer selection, or
  mapper selected-adder lowering changes materially.

## Hypothesis H147

- **ID:** H147.
- **Hypothesis:** the accepted volume-domain proof bounds `s_eff_a` to
  0..1,792. The boosted gain ladder therefore reaches at most 3,360, so
  `g_live[12]`, `s_last_G[12]`, and `s_old_G[12]` are invariant zero. The
  multiplier already consumes `12'(g_live)`. Narrow only the live/last/old
  gain-history boundary to twelve bits while preserving the two zero bit-12
  positions in the streamed oscillator record; this may retire two flops and
  high-bit compare/mux logic without changing arithmetic or memory layout.
- **Scope:** reuse and extend the complete reachable volume proof through the
  boosted gain ladder; exhaust history store/reload/restart/zero decisions;
  prove the registered consumer under the reachable amplitude contract; and
  synthesize that complete consumer in isolation. Only after a deterministic
  isolated LUT/FF/floor win may `rtl/psg_walk.sv` change, followed by full and
  PREVIEW lint and a forced canonical whole-PSG map. Route and run the H139
  fidelity/cadence battery only after a whole-PSG mapped/floor win. Preserve
  every gain, restart, state-record bit position, multiplier request, schedule,
  interface, 14-EBR topology, R.84/B2 file, Tang path, image and tolerance.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `8904bdc`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete isolated gain-history consumer will
  be recorded before any production edit.
- **Changed condition versus H038, H083 and H118:** H038/H083 respelled the
  boosted gain arithmetic and added LUTs; H147 leaves both accepted adders
  unchanged and removes only their proved-zero stored high bit. H118 narrowed
  the upstream sequencer volume/interpolation state to eleven bits and
  regressed globally; H147 keeps that 12-bit interface and uses H118's
  retained 0..1,792 proof only to bound the downstream gain-history payload.
  No prior row prices this 13-to-12-bit streamed-state boundary.
- **Change:** proof-first gain-history width contraction and complete
  registered-consumer synthesis; production remains unchanged until both
  gates pass.
- **Result:** the stronger complete eleven-bit amplitude domain proves
  `g_live` is 0..3,837, so bit 12 is zero; streamed record positions,
  store/reload/restart, zero test, comparison and multiplier payload checks
  pass, as does arbitrary-input SAT over the valid twelve-bit history domain.
  The complete isolated consumer improves 80 -> 75 LUT4s and 26 -> 24 packed
  FFs with 22 carries unchanged, reducing floor 80 -> 75. Full and PREVIEW
  lint contain no errors. The forced canonical whole PSG instead changes
  6,302 -> 6,328 LUT4s, 1,291 -> 1,293 carries, 1,450 -> 1,448 FFs, 498 ->
  499 unpackable FFs, keeps 14 EBRs, and worsens floor 6,800 -> 6,827.
  Seed-1 routing completes at 7,051 LCs versus 7,018; the PSG clock passes at
  31.93 MHz but the fast clock reaches only 112.13 MHz against 112.50 MHz.
- **Decision:** rejected and reverted before fidelity work. `rtl/psg_walk.sv`
  is byte-identical to accepted H139, so no render, cadence, recovery, click,
  smoke, image, Tang, tolerance or R.84/B2 file changed.
- **Repeat only if:** if rejected, retry only after the published-amplitude
  bound, boosted gain ladder, last/old history consumers, streamed-record
  layout, or mapper high-bit pruning changes materially.

## Hypothesis H148

- **ID:** H148.
- **Hypothesis:** the current 14-EBR design has one block available under the
  OpenSpec 15-EBR ceiling. Reversing only the fade-step part of design section
  9's constants-port consolidation should let a dedicated 32x13 synchronous
  ROM retain its result internally, removing the external thirteen-bit
  `fstep_q` lifetime and the fade/address mux while preserving every accepted
  CPU/sequencer/walker edge.
- **Scope:** exhaust all 32 quantized fade lengths, adjacent and delayed
  `$22`/`$20` writes, ordinary pitch/control reads, and sample-walk control-port
  collisions; prove the externally observed step, sequencer hold, displaced
  walker stall, and post-replay control word cycle-exact. Synthesize the
  complete baseline and candidate port/controller in isolation before any
  production edit. Only after an isolated LUT/FF/floor win may
  `rtl/psg_seq.sv` and a generated fade-table artifact change, followed by
  full/PREVIEW lint and a forced canonical whole-PSG map. Route and run the
  H139 fidelity/cadence battery only after a whole-PSG mapped/floor win.
  Preserve all fade values and visibility, the accepted hold/replay timing,
  schedules, interfaces, R.84/B2 files, Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `52a19e9`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete isolated shared-port consumer will be
  measured before production changes.
- **Changed condition versus design section 9, R.67, H126 and H137:** design
  section 9 accepted one extra block of headroom in exchange for 29 LUT4s,
  fourteen flops and 47 placed cells when the then-binding EBR count fell;
  H139 now has a measured spare block under the normative 15-EBR ceiling.
  R.67 added a parallel partial `/7` reciprocal port while retaining most of
  the old quotient selection and regressed; H148 removes a complete fade-port
  selection and result lifetime. H126 tried to derive a displaced-control
  token with wrong same-edge semantics, and H137 replaced the complete lookup
  with a large combinational decoder. H148 preserves both accepted tokens and
  uses a synchronous table, changing neither collision timing nor arithmetic.
- **Change:** proof and isolated synthesis first, followed by the minimal
  production port split only after both gates passed.
- **Result:** the source-derived table matches constants words 112..143, and
  exhaustive checking passes all 81,920 adjacent/delayed command and
  control-collision edge sequences. The complete isolated baseline maps to 33
  LUT4s, 28 flops (27 unpackable), one EBR and a 60-cell floor; the dedicated
  ROM candidate maps to 11 LUT4s, 15 flops (14 unpackable), two EBRs and a
  25-cell floor. This is -22 LUT4s, -13 flops and -35 floor cells for one
  additional EBR. Full multi-pump and PREVIEW lint retain only the established
  warning classes.

  Forced canonical whole-PSG synthesis at RTL fingerprint `d4d9e96b3d62`
  reverses the isolated result. H139's 6,302 LUT4s, 1,291 carries, 1,450 flops,
  498 unpackable flops, 14 EBRs and floor 6,800 become **6,321 LUT4s, 1,295
  carries, 1,437 flops, 484 unpackable flops, 15 EBRs and floor 6,805**.
  Seed-1 router2 completes in **7,031 LCs (+13)** at 130.28 MHz fast / 34.26
  MHz PSG; both clocks pass, but mapped LUT, carry, floor and routed area all
  regress. Production RTL, the generator and generated files are restored
  byte-for-byte to H139. The hard physical gate fails, so `make test-psg`,
  render/cadence, PREVIEW/recovery/click and Celeste smoke gates are
  intentionally skipped.
- **Decision:** rejected and reverted. The dedicated block removes the local
  read-address mux and output lifetime, but flattening re-covers the remaining
  constants/control port and wider design five floor cells larger.
- **Repeat only if:** if rejected, retry only after the fade-step table
  contents, constants/control port arbitration, accepted EBR ceiling,
  hold/replay timing, or mapper RAM-output lowering changes materially.

## Hypothesis H149

- **ID:** H149.
- **Hypothesis:** `ctrl_displaced` is a one-cycle fact consumed only on the
  replay cycle, while `fstep_q[12]`'s preceding fade-step value is
  unobservable on that same cycle because an adjacent `$20` consumes the
  newly returned `crom_q` word directly. Capture the exact prior-edge
  `fade_issue && ctrl_read` fact temporarily in `fstep_q[12]`, then overwrite
  all thirteen bits with `crom_q[12:0]` on the replay edge. This should retire
  one resettable collision-history flop without changing the shared ROM,
  replay duration, fade value, control address or walk cadence.
- **Scope:** exhaust reset, every full/multi-pumped/PREVIEW walk phase,
  idle-start and terminal-finish collisions, accepted and dropped starts,
  consecutive `$22` writes, adjacent and delayed `$20` writes, arbitrary
  ordinary pitch/control reads and every fade index. Compare sequencer hold,
  displaced-control stall, walker phase/address evolution, ROM owner/address,
  `crom_q`, retained `fstep_q`, and committed `fade_step` cycle-exact; prove
  the complete registered baseline/candidate controller with SAT and
  synthesize it in isolation. Only after exactness and a deterministic
  isolated floor win may `rtl/psg_seq.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H139
  fidelity/cadence battery only after a whole-PSG mapped/floor win. Preserve
  the 14-EBR shared constants/control store, schedules, interfaces, R.84/B2
  files, Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `50cec7d`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete isolated shared-port/controller
  baseline will be measured before any production edit.
- **Changed condition versus H120, H126, H137 and H148:** H120 removed reset
  from fade payloads guarded by `fade_dir` but did not touch the collision
  token. H126 reconstructed the token from post-edge `prun` and failed on
  same-edge walk start/finish; H149 retains the exact pre-edge `ctrl_read`
  fact and changes only its temporary storage. H137 removed the lookup and
  replaced it with a globally expensive decoder, while H148 split it into a
  fifteenth EBR and regressed. H149 keeps the accepted lookup, shared port,
  two-cycle hold and 14-EBR topology unchanged.
- **Change:** proof and complete isolated synthesis first; production RTL
  remains unchanged until both gates pass.
- **Result:** the source-bound table audit passes all 32 fade words. The
  inductive model passes 6,594,000 transitions over every phase of the
  multi-pumped, compatibility and PREVIEW schedules, including idle starts,
  terminal finishes, reset, holds and all command classes. A further 16,155
  traces cover adjacent/delayed `$20`, consecutive `$22`, reset and every fade
  index. The eight-cycle arbitrary-input SAT miter also passes from reset,
  comparing ROM address/data, replay/hold, displaced stall and every qualified
  fade-step observation.

  The complete isolated baseline maps to 33 LUT4s, 28 flops (27 unpackable),
  one EBR and floor 60; the candidate maps to 35 LUT4s, 27 flops (13
  unpackable), one EBR and floor 48. Although this retires one flop and wins
  twelve isolated floor cells, forced canonical whole-PSG synthesis reverses
  it: H139's 6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops and
  floor 6,800 become **6,360 LUT4s, 1,296 carries, 1,449 flops, 487 unpackable
  flops and floor 6,847**, with 14 EBRs unchanged. Seed-1 router2 completes in
  **7,076 LCs (+58)** at 121.92 MHz fast / 33.16 MHz PSG. Both clocks pass,
  but every binding area metric except flop count regresses. Full/PREVIEW lint
  retains the established warning classes. `rtl/psg_seq.sv` is restored
  byte-identically to H139 at fingerprint `41bf50aae6d2`; render, cadence,
  recovery, click, smoke, image, Tang, tolerance and R.84/B2 files remain
  unchanged.
- **Decision:** rejected and reverted at the whole-PSG physical gate. Packing
  the token makes the isolated fade-step output flops share LUTs, but the
  flattened sequencer cover adds 58 LUT4s and 47 deterministic floor cells.
- **Repeat only if:** if rejected, retry only after `fstep_q` value lifetime,
  adjacent/consecutive command timing, collision-token reset semantics,
  shared-port replay duration, or mapper mixed-reset slice lowering changes
  materially.

## Hypothesis H150

- **ID:** H150.
- **Hypothesis:** a fade starts only when `fade_len >= 8`, so the captured
  table index is 1..31. Index 1 is the sole value with bit 12 set (`4096`),
  and every other eligible step is nonzero and below 4096. Store only the low
  twelve bits in `fade_step`; reconstruct the exact thirteen-bit addend as
  `{~|fade_step, fade_step}` while `fade_dir` makes the payload observable.
  This should retire one unpackable fade-step flop without changing the table,
  lookup/replay timing, accumulator width, gain publication or fade cadence.
- **Scope:** bind the 32 generated table words; prove that index zero never
  starts a fade and that the low-twelve-bit encoding is bijective over indices
  1..31. Exhaust reset, fade-in/out start, interruption, every active
  accumulator value, `pre_tick` update/completion and all 31 eligible steps;
  prove the complete registered fade-state consumer with SAT and synthesize it
  in isolation. Only after exactness and a deterministic isolated floor win
  may `rtl/psg_seq.sv` change, followed by full/PREVIEW lint and a forced
  canonical whole-PSG map. Route and run the H139 fidelity/cadence battery only
  after a whole-PSG mapped/floor win. Preserve `$20`/`$22` timing and readback,
  shared-ROM collision behavior, all fade values, schedules, 14 EBRs,
  interfaces, R.84/B2 files, Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `0885d54`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The complete registered fade-state consumer will be
  measured before any production edit.
- **Changed condition versus H025, H061, H118, H120 and H147:** H025 only
  named the repeated fade sum; H061 reconstructed eight `fade_acc` bits from
  published gain and regressed; H120 removed reset from guarded fade payloads
  but retired no mapped flop. H118 and H147 narrowed volume/gain histories in
  wider fanout cones. H150 leaves accumulator, gain, direction and reset
  ownership intact and contracts only the table-derived active step, using a
  source-bound nonzero-domain encoding at its unchanged addend boundary.
- **Change:** proof and complete isolated synthesis first; production RTL
  remains unchanged until both gates pass.
- **Result:** the source-bound table audit proves all 31 eligible steps are
  nonzero, index 1's 4096 uniquely encodes as a zero low field, and decoding
  every stored value returns the exact generated step. Exhaustive checking
  passes 4,063,232 active accumulator/direction/step cases and 4,536
  simultaneous tick/command/interruption cases. The eight-cycle
  arbitrary-input SAT miter passes from reset for every sequence whose fade
  commands remain in the proved eligible-step domain.

  The complete registered fade-state baseline maps to 79 LUT4s, 16 carries,
  41 flops (thirteen unpackable) and floor 92. The candidate maps to 82 LUT4s,
  16 carries, 40 flops (twelve unpackable) and floor 94. The zero detector and
  reconstructed high addend cost three LUT4s to retire one unpackable flop, so
  the deterministic isolated floor regresses by two cells. Production RTL,
  lint, whole-PSG map/route and fidelity gates are skipped.
- **Decision:** rejected before production RTL. Keep the exact thirteen-bit
  active fade step; its stored high bit is cheaper than reconstructing the
  unique 4096 value in the complete consumer.
- **Repeat only if:** if rejected, retry only after the fade-step table/domain,
  fade eligibility, accumulator consumer, payload reset/validity, or mapper
  zero-detect/sequential lowering changes materially.

## Hypothesis H151

- **ID:** H151.
- **Hypothesis:** `psg_divsvc.d_d` captures eight divisor bits even though the
  sequencer holds the divisor owner for every complete 24-cycle transaction.
  Normal slide/volume/effect requests use the stable staged `eff_sp`. The sole
  constant-seven instrument request advances from `K_FX/xs=9` to the existing
  `K_FX/xs=10` wait state, where `ins_use` remains true until `d_busy` clears.
  Select seven in that launch/wait context and otherwise feed live `eff_sp`
  directly to the restoring subtract, retiring all eight `d_d` flops without
  adding state or changing the divider recurrence.
- **Scope:** audit every divider launch/wait/consume path, including both slide
  transactions, effect-3, all volume effects, instrument scaling, sequencer
  holds and the terminal busy edge. Exhaust all nonzero eight-bit divisors,
  numerators and 24 restoring iterations; prove captured-versus-live divisor,
  quotient, remainder, busy and owner-state evolution cycle-exact with SAT.
  Synthesize the complete registered provider/wait-state/divider consumer in
  isolation. Only after exactness and a deterministic isolated floor win may
  `rtl/psg_divsvc.sv` and `rtl/psg_seq.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H139
  fidelity/cadence battery only after a whole-PSG mapped/floor win. Preserve
  every numerator, rounding rule, 24-cycle latency, result slice, schedule,
  interface except the private divider port ownership, 14 EBRs, R.84/B2 files,
  Tang paths, images and tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `d32f598`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The H139 census attributes eight unpackable flops
  to `d_d`; the complete provider/divider baseline will be measured before any
  production edit.
- **Changed condition versus H016, H070 and H085:** H016 narrowed the
  restoring subtract and regressed, H070 recoded only the 24-step iteration
  token and regressed globally, and H085 moved numerator rounding around the
  unchanged service. H151 changes no arithmetic width, count, numerator or
  rounding. It removes a complete captured operand whose owner is now proved
  stable in the current pre-run sequencer, including the otherwise exceptional
  constant-seven wait state.
- **Change:** proof and complete isolated synthesis first; production RTL
  remains unchanged until both gates pass.
- **Result:** the source-owner audit and cycle model pass 13,592 transactions
  across the two slide requests, effect-3, volume effects 1/4/5 and the
  constant-seven instrument request. Launch plus all 24 busy cycles preserve
  the captured divisor for every class. A 30-cycle arbitrary-input SAT miter
  from reset also proves quotient, remainder, busy and owner-state equivalence.

  The complete isolated baseline maps to 71 LUT4s, fourteen carries, 60 flops
  (eighteen unpackable) and floor 89. The candidate maps to 76 LUT4s, fourteen
  carries, 52 flops (ten unpackable) and floor 86. Although all eight `d_d`
  flops retire and the isolated floor improves by three cells, forced canonical
  whole-PSG synthesis reverses the result: H139's 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops and floor 6,800 become **6,333 LUT4s,
  1,295 carries, 1,442 flops, 492 unpackable flops and floor 6,825**, with 14
  EBRs unchanged. Seed-1 router2 completes in **7,050 LCs (+32)** at 121.62
  MHz fast / 31.54 MHz PSG. Both clocks pass, but every binding area metric
  except flop count regresses. Full multi-pump/PREVIEW lint reaches only the
  established warning classes. `rtl/psg_divsvc.sv` and `rtl/psg_seq.sv` are
  restored byte-identically to H139; render, cadence, recovery, click, smoke,
  image, Tang, tolerance and R.84/B2 files remain unchanged.
- **Decision:** rejected and reverted at the whole-PSG physical gate. Feeding
  the live provider through the flattened divider trades eight operand flops
  for a wider cross-module selection/fanout cover, adding 25 deterministic
  floor cells and 32 routed LCs.
- **Repeat only if:** if rejected, retry only after divider requester states,
  `eff_sp` lifetime, constant-seven ownership, hold/busy ordering, divider
  latency, or mapper cross-module operand lowering changes materially.

## Hypothesis H152

- **ID:** H152.
- **Hypothesis:** `w_bf_{damp,rev,det,buzz,noiz}` and
  `w_ch_{damp,rev,det,buzz,noiz}` retain separate eight-bit base and effective
  filter tuples for a slot. The base tuple already has persistent ownership in
  record words 4/5, while only the effective tuple is needed between note
  transitions and P_W2 publication. Let the existing `w_bf_*` working tuple
  hold the effective value, preserve the base fields in their existing record
  words during V_ST, and pre-read those words during K_NL/K_NH so K_LD can
  restore base only when a note exits or retriggers an instrument. Fresh
  triggers refresh the record fields during existing T_SP/T_LS/T_LE cycles.
  This should retire all eight `w_ch_*` flops and their duplicate load/copy/join
  cones without a new state, EBR, persistent register, or sequencer cycle.
- **Scope:** prove reset/load, fresh trigger, ordinary note, same-instrument
  continuation, instrument exit/retrigger, base/instrument maximum, V_ST
  preservation, P_W2 publication, synchronous state-read timing, holds and
  same-cycle write precedence. Synthesize the complete registered base/effective
  ownership consumer in isolation. Only after exactness and a deterministic
  isolated floor win may `rtl/psg_seq.sv` change, followed by full/PREVIEW
  lint and a forced canonical whole-PSG map. Route and run the H139
  fidelity/cadence/recovery/click/Celeste battery only after a whole-PSG
  mapped/floor win. Preserve all filter values, note/instrument decisions,
  record and sounding layouts, five V_ST cycles, publication timing, state
  ports, schedules, 14 EBRs, interfaces, R.84/B2 files, Tang paths, images and
  tolerances.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `860f117`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The H139 census attributes 152 LUT4s to
  `w_ch_rev`'s flattened family; the complete ownership consumer will be
  measured before any production edit.
- **Changed condition versus H099, H115 and H116:** H099 retained both tuples
  and changed only base-copy/publication selection; H115 retained both tuples
  and respelled the bounded maxima; H116 moved the effective lifetime into
  inactive P_W2 and paid new bank-read/replay selection. H152 instead removes
  the duplicate tuple, makes no P_W2 read, and uses the existing persistent
  base record plus otherwise-idle note-transition read slots. The sole
  temporary base-word capture reuses `acc`, which is dead after EA5 and is
  overwritten before its next ordinary consumer.
- **Change:** the source-bound ownership model was proved first and the complete
  registered ownership consumer was synthesized in isolation. After both gates
  passed, the production candidate removed `w_ch_*`, published `w_bf_*`, kept
  the persistent base tuple in record words 4/5, refreshed it during T_SP/T_LS,
  recovered it through K_NL/K_NH/K_LD reads using dead `acc[5:0]`, and merged
  the persistent fields during V_ST without changing the five-cycle store.
- **Result:** 10,089,360 semantic ownership cases and 1,024 hold/replay
  timelines pass. The complete isolated baseline maps to 51 LUT4s, 32 flops
  and floor 67; the candidate maps to 46 LUT4s, 24 flops and floor 62. Full and
  PREVIEW lint reach only the established warning classes. Forced canonical
  whole-PSG synthesis at RTL fingerprint `a70eddb86252` reverses the isolated
  result: H139's 6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops,
  14 EBRs and floor 6,800 become **6,374 LUT4s, 1,295 carries, 1,442 flops,
  498 unpackable flops, 14 EBRs and floor 6,872**. The eight removed flops were
  all packed, while the added state-port/replay and record-merge selection
  raises both binding mapped metrics by 72 cells. Production RTL is restored
  byte-identically to H139; routing and the fidelity/cadence battery are skipped
  after the hard mapped-area failure.
- **Decision:** rejected and reverted at the whole-PSG area gate. The persistent
  record reads avoid duplicate storage locally, but their global address,
  replay and merge cones cost substantially more than the eight packed flops.
- **Repeat only if:** if rejected, retry only after base/effective tuple
  ownership, note-transition states, record-word layout, state-port schedule,
  V_ST merge timing, instrument-retrigger topology, or mapper state-read/FF
  lowering changes materially.

## Hypothesis H153

- **ID:** H153.
- **Hypothesis:** `cpz` is a one-bit historical copy-zero decision written only
  on K_ADV's skipped-slot route or EA5's two stop routes and consumed only at
  PC3. `note_lo[7:0]` is written at T_NH/K_NH/I_NH, consumed completely at the
  immediately following T_LD/K_LD/I_LD state, and then dead on every route to
  K_ADV/EA5 and PC3. Store the copy-zero decision in dead `note_lo[7]` instead
  of a standalone flop. This should retire one unpackable FF and its independent
  write-enable cone without reconstructing the historical value.
- **Scope:** prove all trigger/ordinary/instrument note-load and consumer pairs,
  K_ADV skip classes, both EA5 stop classes, evaluation continuations, holds,
  intervening CPU `playing` changes, and PC3 zero/nonzero publication. Synthesize
  the complete registered note/copy consumer in isolation. Only after exactness
  and a deterministic isolated floor win may `rtl/psg_seq.sv` change, followed
  by full/PREVIEW lint and a forced canonical whole-PSG map. Route and run the
  H139 fidelity/cadence/recovery/click/Celeste battery only after a whole-PSG
  mapped/floor win. Preserve every note field, copy value, stop/playing timing,
  state-port operation, sequencer state/cycle, interface, 14-EBR topology,
  R.84/B2 file, Tang path, image and tolerance.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `c904c25`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The H139 census attributes eight unpackable flops
  to `note_lo`, one unpackable flop and 38 LUT4-family labels to `cpz`.
- **Changed condition versus H102, H122 and R.40--R.42:** H102 successfully
  reused a mode-dead working bit but did not touch copy publication. H122 tried
  to remove `cpz` by reconstructing it from live `playing`/`pend_stop`; a CPU
  stop between K_ADV and PC3 made that inexact. H153 retains the captured value
  and changes only its physical bit. R.40--R.42 joined wide arithmetic roles
  with different fanout and closed that mechanism family after three losses;
  H153 aliases one adjacent sequencer flag into a byte whose note role is fully
  consumed before any copy-zero write and whose PC role has one consumer.
- **Change:** the proof models note load/consume, K_ADV capture, both EA5 stop
  classes, hold/replay intervals, PC3 consumption and arbitrary intervening
  live-playing changes. The complete registered probe compares the standalone
  flag with the phase-disjoint `note_lo[7]` role under the production reset and
  enable shapes. Production RTL remains unchanged.
- **Result:** 1,441,792 semantic note/copy cases and 245,760 hold/CPU-change
  timelines pass. The complete isolated baseline maps to 25 LUT4s, 25 flops,
  eight unpackable flops and floor 33. The candidate maps to 26 LUT4s, 24
  flops, seven unpackable flops and the same floor 33. Reusing the bit retires
  `cpz`, but adds exactly one LUT4 to select its additional writes; no binding
  deterministic resource improves.
- **Decision:** rejected before production RTL. Keep the explicit historical
  flag because its one unpackable cell is exchanged one-for-one for a LUT cell
  in the complete mapper-visible consumer.
- **Repeat only if:** if rejected, retry only after note-load/consume ordering,
  K_ADV/EA5-to-PC3 routing, copy-zero consumers, `note_lo` storage/packing,
  CPU stop visibility, or mapper register-enable lowering changes materially.

## Hypothesis H154

- **ID:** H154.
- **Hypothesis:** the production multi-pumped multiplier uses radix 2 and
  carries five exact fast-step classes: short/6, mode-0/8, mode-3/9,
  mode-1/10 and mode-2/12. Their multiplier bounds are respectively six,
  eight, nine, ten and twelve live `B` bits. Keep the twelve-step payload
  unchanged under a zero thirteenth bit; for every shorter class, set that
  otherwise-dead thirteenth bit and encode the class in payload bits 11:10,
  which are above even the widest ten-bit shorter operand. The fast domain can
  mask only those two tag bits when the thirteenth bit is set and reconstruct
  the iteration count from the three-bit prefix, retiring the separate
  four-bit `req_steps` bundled payload. This should exchange one newly-live
  payload flop and a narrow decode for four source-domain count flops.
- **Scope:** prove every live request arm's mode/short `B` bound, all five tag
  encodings, exact value recovery, exact fast-step reconstruction, every
  radix-2 result/acknowledge transaction and unchanged supported radix-4
  behavior. Synthesize the complete registered request-payload, request-toggle,
  fast-load and countdown consumer in isolation. Only after exactness and a
  deterministic isolated floor win may `rtl/psg_mulmp.sv` change, followed by
  full/PREVIEW lint and a forced canonical whole-PSG map. Route and run the
  H139 fidelity/cadence/recovery/click/Celeste battery only after a whole-PSG
  mapped/floor win. Preserve every multiplier value, result position,
  transaction latency, padded sequencer-busy duration, CDC toggle, schedule,
  interface, 14-EBR topology, R.84/B2 file, Tang path, image and tolerance.
- **Baseline:** accepted H139 production at commit `d76241f` and docs commit
  `40e9f60`, RTL fingerprint `41bf50aae6d2`: 6,302 LUT4s, 1,291 carries,
  1,450 flops, 498 unpackable flops, 14 EBRs and floor 6,800, routed in 7,018
  LCs at 142.63/31.17 MHz. The H139 census attributes 24 unpackable flops and
  221 LUT4-family labels to `req_b`; a fresh complete payload/countdown
  consumer baseline will be recorded before any production edit.
- **Changed condition versus H006, H090, H102 and H136:** H006 respelled only
  the radix-4 count bits and H090 derived `seq_pad` from a still-separate
  `req_steps`; neither removed the count payload. H102 successfully packed a
  mode-exclusive bit into dead payload storage, but on a sequencer record
  boundary. H136 activated `req_b[12]` and `m_p[33]` to carry a result sign,
  exactly replacing the two sign flops it sought to retire. H154 activates
  only `req_b[12]`, reuses already-live `req_b[11:10]` as class bits only when
  their operand positions are proved zero, leaves the result word untouched,
  and removes four count flops from the same CDC request boundary.
- **Change:** exhaust every tag/value/count relation and representative signed
  transaction, then compare the complete dual-clock registered service before
  changing production. After the isolated gate passed, encode prefix 0xx as
  the twelve-step payload and 100/101/110/111 as the 10/9/8/6-step classes in
  `rtl/psg_mulmp.sv`; mask bits 11:10 only for a tagged short class and decode
  the fast counter from the prefix. Keep the original payload/count path under
  `RADIX_BITS == 2`.
- **Result:** all 5,952 legal payload/value classes and 53,568 signed
  transaction checks pass. The existing cycle-exact multiplier gate passes,
  and the integrated dual-clock bench passes 6,020 radix-2/radix-4/freeze
  transactions with unchanged true-busy bounds. Full and PREVIEW lint exactly
  reproduce H139's 52/49 established warning counts. The complete isolated
  service changes 126 -> 130 LUT4s, keeps 38 carries, retires three flops
  (78 -> 75), reduces unpackable flops 22 -> 16, and improves floor 148 ->
  146 cells.

  Forced canonical whole-PSG synthesis reverses that local result: H139's
  6,302 LUT4s, 1,291 carries, 1,450 flops, 498 unpackable flops, 14 EBRs and
  floor 6,800 become **6,353 LUT4s, 1,290 carries, 1,447 flops, 499
  unpackable flops, 14 EBRs and floor 6,852**. The three retired source flops
  do not repay the tagged request-load/decode cover, and one more remaining
  flop becomes unpackable. Production is restored byte-for-byte to H139; a
  forced restored map reproduces 6,302/1,291/1,450/498/14/floor 6,800 exactly.
  Routing and the fidelity/cadence battery are skipped after the hard mapped-
  area failure.
- **Decision:** rejected and reverted at the whole-PSG area gate. Keep the
  explicit `req_steps` payload; its four flops pack more cheaply in the full
  design than the class prefix and fast-load decode.
- **Repeat only if:** if rejected, retry only after multiplier operand bounds,
  radix/count classes, request payload width, fast-load boundary, supported
  radix set, or mapper payload/countdown lowering changes materially.

## Hypothesis H155

- **ID:** H155.
- **Hypothesis:** H055's shared-limb signed-noise rounding -- respell the
  negative limb `-(nz_mag + |frac|)` as the exact `~nz_mag + !|frac|` --
  becomes acceptable on the H139 lineage. H055 measured a deterministic
  -15 LUT4/-14 floor whole-PSG win and was rejected only because seed-1
  router2 stayed at two overused wires for 21,160 iterations on the H051-era
  netlist. H134/H139 have since restructured the pitched-noise consumer (one
  shared live/old scale tree, shared `wt_x1` storage) and removed 68 routed
  LCs, meeting H055's "consumer pipeline boundary changes" repeat condition.
- **Scope:** the single `nz_neg` limb in `rtl/psg_walk.sv`; exhaustive proof
  and unconstrained SAT before the edit; permanent form in
  `tools/psg_hw_forms.py`; whole-PSG pre-map, canonical map, seed-1 route,
  and the complete behavior battery. No multiplier, noise clamp, kick
  predicate, LFSR, schedule, state, interface, EBR, or tolerance change.
- **Baseline:** clean `644d68f` (rtl `23c2bbe7dc6e`), yosys 0.67
  (`b8e7da6f`, installed 15 Jul) and nextpnr-ice40 0.10 (installed 1 May) --
  the toolchain is unchanged since before H139, so all deltas are
  source-attributable. Pre-map 13,487 cells (1,433 carry wrappers, 1,450
  flops); canonical map 6,333 LUT4s, 1,291 carries, 1,450 flops, 501
  unpackable, floor 6,834, 14 EBRs; seed-1 placement 7,055 LCs; router2 does
  NOT complete -- overuse flatlines at two wires through 18,052 iterations,
  H055's recorded failure signature. This differs from accepted H139's
  retained 6,302 LUT4s/498 unpackable/floor 6,800/7,018 routed LCs: the
  C-series clarity passes changed source text and line numbers, abc9's
  covering is order- and name-sensitive (the documented +-60 band), and
  C010's "unchanged by construction" inference bound the canonicalized token
  stream rather than the physical artifact. Clean HEAD had therefore silently
  lost the routable canonical build.
- **Changed condition versus H055:** the consumer pipeline boundary named in
  H055's repeat condition changed (H134's shared wavetable interpolation
  state, H139's single shared noise scale tree replacing `nz_z`/`nz_old_z`),
  and the router's starting point changed twice -- H139 removed 68 routed LCs,
  then the clarity passes reshuffled the covering. No other H055 mechanism is
  retried; the rejected duplicated-inline variant stays rejected.
- **Change:** replace `-(nz_mag + 18'(|nz_m[7:0]))` with
  `~nz_mag + 18'(!(|nz_m[7:0]))` at the sole negative rounding limb in
  `rtl/psg_walk.sv`, with a comment stating the identity; add the
  `noise.round_shared_limb` permanent form to `tools/psg_hw_forms.py`.
- **Result:** the 262,144-case scalar enumeration and the unconstrained SAT
  miter (`sat -prove ok 1 -verify`, minisat, no model) both prove the
  identity; `python3 tools/psg_hw_forms.py noise` reports all forms PROVED.
  Pre-map 13,487 -> 13,482 (-3 `$_AND_`, -2 `$_XOR_`; carries, MUX/NOT/OR,
  flops, EBRs unchanged) -- real gates leave the netlist in the honest ~1:1
  arithmetic family. Canonical map 6,330 LUT4s (-3), 1,292 carries (+1),
  1,450 flops, 498 unpackable (-3), floor 6,828 (-6), 14 EBRs. Seed-1
  placement 7,052 LCs (-3); router2 COMPLETES at 7,052 routed LCs,
  33.50 MHz PSG / 138.20 MHz fast, both constraints passing, where the
  baseline produces no routed design. Full and PREVIEW lint hold the three
  established width warnings. `make test-psg` ALL PASSED (PICO-8 statistical
  fidelity, fold, 524,288 dq formulas + 57,344 transactions, 93
  audio-analysis and 13 visualizer tests, structural simulation). All 59
  frozen renders at the explicit 18.75 MHz sweep are byte-identical to the
  adopt-exact anchor and diagnostic-clean. `make test-clocks` passes /4, /5
  and /6. PREVIEW P.1 passes at 1,275 and 159 clocks/sample (91% voiced
  agreement, 85% floor; combined levels/activity PASS). Synthetic and
  Celeste recovery pass with zero coalesced/delayed/dropped samples. Both
  click renders report zero `click-v1` events. The five-frame Celeste smoke
  is byte-identical at SHA-256 `3d4933a9...` with 2,079/3,668 off-centre
  samples, range -21,544..7,711, 1,014 distinct levels. A forced canonical
  rebuild reproduces the JSON/ASC byte-identically. Incidental finding: the
  five stale foreign-machine Verilator objdirs under `build/` were removed to
  run the battery, and `make shot`'s console rule fatals on the three
  established width warnings after any clean rebuild (pre-existing; the smoke
  here used the rule's command plus the established `-Wno-WIDTHEXPAND
  -Wno-WIDTHTRUNC`).
- **Decision:** accepted.
- **Repeat only if:** the pitched-noise product slice, signed rounding
  contract, or consumer pipeline boundary changes again.

## ROW SCHEMA -- mandatory from 2026-08-04

Every row from H163 onward MUST record the fields below. The A001 audit and
H162 exist because the first 162 rows recorded a **single abc9 build** as the
verdict, and that number carries +-30 cells of naming noise. Nine of eleven
audited acceptances were real but their magnitudes were wrong by up to 8x; two
were worth exactly zero; and no rejected row's margin can be re-checked because
pre-map was never written down. Do not repeat that.

```
- **Instruments** (fill every line; "n/r" only if genuinely not run):
    pre-map cells      <base> -> <cand>  <delta>    [deterministic]
    -noabc floor       <base> -> <cand>  <delta>    [deterministic, spread 0]
    unpackable flops   <base> -> <cand>  <delta>    [reliable]
    LUT4               <base> -> <cand>  <delta>    [NOISY - never the verdict]
    abc9 floor         median <base> -> <cand>, n=<N> per arm,
                       Mann-Whitney U=<u>/<max>, p=<p>   [statistic named BEFORE looking]
    EBR                <base> -> <cand>              [<=14 unless recompacted]
    placed / Fmax      <...>                         [one draw; context only]
```

Rules that make those numbers mean something:

1. **A single abc9 build is never a verdict.** Not for acceptance, not for
   rejection. It is one draw from a distribution ~72 cells wide.
2. **pre-map and `-noabc` decide direction.** If they disagree in sign with
   each other, sample the shipped mapper -- do not pick the proxy you prefer
   (H162's classic-abc read -28/-49 on changes abc9 could not distinguish from
   zero).
3. **Record unpackable flops separately from LUT4.** Flops are reliable, LUT4
   is where the noise lives: H142 predicted -12 flops and delivered exactly
   -12, while its LUT4 moved +17.
4. **Isolated synthesis is not a verdict either** -- it has *more* covering
   variance than whole-design, not less. H081 and H145 were both rejected on
   isolated numbers alone and remain untested.
5. **State the decision rule before measuring**, and if the data later suggests
   a better statistic, say so and re-register rather than substituting it.

## Hypothesis H156

- **ID:** H156.
- **Hypothesis:** the `gz_filt_r` cone is the largest never-examined structure
  in the design -- 259 named LUT4s and 106 carries, the second-largest carry
  family after `req_a` -- and no row in H001--H155 names it. Its live-gain
  scale network spells `floor((1025*A + G) / 2^20)` (with `A = m_res>>3`,
  `G = gz_filt_r`) as a 26-bit add feeding a 34-bit add, of which the low nine
  bits of the second add are pure pass-through. Re-associating it to
  `(A + ((A + G) >> 10)) >> 10` should retire a wide carry chain.
- **Scope:** pre-map ablation pricing first; only on a ceiling clearing the
  band would the exactness proof (the `m_res[28:3]` versus `m_res[27:3]`
  truncation is not free -- the identity holds only if `m_res[28]` is provably
  zero at both consume points) and production RTL follow. Preserve wave-6
  arm selection, the W15/W40/W84 register roles, and the 14-EBR topology.
- **Baseline:** `c1ad243`, rtl `1a76c4596af2`: pre-map 13,482 cells / 1,433
  carry wrappers / 1,450 flops; 6,330 LUT4s, 1,292 carries, 498 unpackable,
  floor 6,828, placed 7,052, 14 EBR, 33.50/138.20 MHz.
- **Changed condition versus prior rows:** none needed -- this family had never
  been opened. It was found by attributing carry cells to net families, which
  `tools/psg_ff_census.py` does not report; the LUT4-only ranking had hidden
  it behind `req_a`, `tilt_tail_r` and `mx_old`, all of which are closed.
- **Change:** ablation only. `{2'b0, gz_q3acc[33:19]}` replaced by
  `{2'b0, m_res[27:13]}` at both consume sites, deleting `gz_171_twice`,
  `gz_171` and `gz_q3acc` outright. Run in an isolated `git archive HEAD`
  tree copy; production RTL never touched.
- **Result:** the entire scale network prices at **13,482 -> 13,430 pre-map
  cells, 1,433 -> 1,382 carries** -- a ceiling of 52 cells with the arithmetic
  deleted, not replaced. The exact re-association retires one 34-bit add in
  favour of a 26-bit add, recovering roughly eight of those cells. Gates 2--5
  never ran.
- **Decision:** not landed alone; **held for composition**. The exact
  re-association is worth about eight pre-map cells. Pre-map is deterministic,
  so that eight is real and banks -- the original "cannot resolve against the
  +-60 band" reading was wrong (see the band note in Current State). Too small
  to justify its own stage and its own proof; carry it into a bundle.
- **Repeat only if:** the W15/W40 product slices, the 1025 gain coefficient, or
  the wave-6 bypass arm change materially, or the two adds acquire a shared
  consumer that makes them retire together.

## Hypothesis H157

- **ID:** H157.
- **Hypothesis:** the register-lifetime alias family still has unmined pairs;
  `make psg-lifetimes` derives them from the RTL rather than from reading, and
  the reference file calls it the most reliable small lever.
- **Scope:** pool-time triage only, per SKILL.md section 6 ("reject or bundle
  anything under the noise band at pool time").
- **Baseline:** as H156.
- **Changed condition versus H134/H135/H142/H152/H153/H154:** none. Those rows
  are the measured instances of this family; this row prices what remains of
  it as a whole rather than opening another instance.
- **Change:** none. `make psg-lifetimes` enumerated the complete candidate set
  on the 62-phase walk visit.
- **Result:** the entire remaining pool is four guests -- `wt_x1` (8 flops),
  `fmc` (4), `fsel` (3), `last_mode_r` (2) -- 17 flops in total even if every
  alias landed simultaneously and cost nothing. The six measured instances of
  this exact family went the other way: H153 +1 LUT4, H142 +17, H145 +31,
  H154 +51 LUT4 and +52 floor, H152 +72 LUT4 and +72 floor, H137 +84 LUT4.
- **Decision:** rejected at pool time; the class is closed by arithmetic. Its
  best case is below the band and its measured mean is strongly positive.
- **Repeat only if:** the walk visit gains phases, a register family's live
  range changes materially, or an alias mechanism is found that does not buy
  new selection hardware (THE LAW, section 4).

## Hypothesis H158

- **ID:** H158.
- **Hypothesis:** the remaining never-examined families hold recoverable
  arithmetic: `q16`'s two `syn_addr` adds differ only by `+1` on a six-bit
  field and could share one adder given a proved non-wrap bound (an invisible
  bound, the richest class); the three `w_ch_*` effective-filter maxima carry
  39 attributed carries; and `t_ix15`'s eleven-bit index add is unexamined.
- **Scope:** bundled pre-map ablation, since each is individually below the
  band and section 6 requires bundling before spending anything.
- **Baseline:** as H156.
- **Changed condition versus H115:** H115 closed the *bounded filter-max
  spelling*; this row prices the max network's whole removable mass together
  with two unrelated unexamined adds, to test whether the bundle clears the
  band. It does not propose a new spelling for any of them.
- **Change:** ablation only, all three at once, in the isolated tree copy --
  `q16[15:10] + 6'd1` shared with the first add, the three `w_ch_det/rev/damp`
  maxima reduced to their foreground arms, `t_ix15` reduced to `t_h15`.
- **Result:** **13,482 -> 13,406 pre-map cells, 1,433 -> 1,409 carries** --
  a 76-cell ceiling with all three behaviours deleted. Almost none of it is
  recoverable: the maxima are semantically required, and `t_ix15` is
  load-bearing for the accepted `/15` split identity. Only the `q16` share is
  a real candidate, worth about eleven carries and requiring a proof that
  `q16[15:10] != 63` at the second issue site.
- **Decision:** split. The `w_ch_*` maxima and `t_ix15` are **rejected** --
  both are semantically required, so their ablation ceiling is not recoverable
  at all. The `q16` adder share is **held for composition**: about eleven
  carries, real and deterministic, gated on proving `q16[15:10] != 63` at the
  second issue site.
- **Repeat only if:** the wavetable address issue sites, the effective-filter
  maximum contract, or the tilt index identity change materially.

## Hypothesis H159

- **ID:** H159.
- **Hypothesis:** all four wavetable fetch sites in `psg_walk.sv` (:321--341)
  spell `s_snd_wtb + {7'b0, <six-bit index>}` under a priority chain, so four
  13-bit adders sit under a result mux. Selecting the six-bit index first and
  adding once is the "select the operands, not the result" corollary that
  previously won -168 pre-map / -54 placed.
- **Scope:** `rtl/psg_walk.sv` combinational fetch block only. Preserve arm
  priority, the `REALTIME_PREVIEW` two-arm form, `syn_rd` timing and the
  six-bit wrap.
- **Baseline:** rtl `1a76c4596af2` -- pre-map 13,482 / 1,433 carries; 6,330
  LUT4, 498 unpackable, floor 6,828, placed 7,052, 33.50/138.20 MHz.
- **Changed condition versus H144 and the aligned-record-base family:** those
  exploited record alignment at the *final* addition. H159 does not change any
  address value; it changes only how many adders exist to produce them.
- **Change:** hoisted `syn_a0..syn_a3`, derived `syn_use_q` and `syn_plus1`
  from the original chain's priority, formed
  `syn_ix = (syn_use_q ? q16[15:10] : s_phase[15:10]) + (syn_plus1 ? 1 : 0)`,
  and left one `s_snd_wtb + {7'b0, syn_ix}`. Exact **by construction**: the
  `+1` stays inside six bits, so the 63->0 wrap is preserved, and no bound on
  `q16` or `s_phase` is needed. All four arms verified against the original
  priority table.
- **Result:** pre-map 13,482 -> 13,401 (**-81 cells, -20 carries**), but
  mapped LUT4 6,330 -> 6,328 (-2), unpackable 498 -> **500 (+2)**, **floor
  6,828 -> 6,828 (0)**, placed 7,052 -> 7,053 (+1), Fmax 33.50 -> 30.79 MHz.
  Rtl fingerprint `12c211eb6e1d`. Gates 3--5 never ran.
- **Decision:** rejected **alone**; **accepted as part of H161**. Alone the
  floor is flat, not merely sub-band -- the operand mux cost back exactly what
  the retired adders saved. Composed with H160 it is half of a -33 floor win.
  Do not cite this row as a refutation of the transform.
- **Repeat only if:** the fetch sites stop sharing `s_snd_wtb`, or an arm is
  removed so the index select gets cheaper than the adder it replaces.

**THE CALIBRATION THIS BOUGHT, which is worth more than the hypothesis.**
A **-81 pre-map / -20 carry** change produced **exactly zero floor movement**.
Pre-map is deterministic, but it is *not a proxy for the floor*: on iCE40 a
carry unit lives inside a logic cell that also holds a LUT, so retiring carry
chains pays only when the LUTs retire with them. Two consequences:

1. **CORRECTED by H161 and the doctrine block -- read that, not this.** The
   original wording here said pre-map "is not a proxy for the floor" and that
   candidates must be re-priced on mapped floor. That over-generalised from one
   point. What is true: a pre-map delta does not predict a *single abc9 draw*,
   because that draw carries 62-72 cells of naming noise. What is false: that
   pre-map is uninformative. On H161, pre-map (-133) agreed in sign and rank
   with every deterministic instrument -- `-noabc` (-88, spread 0) and
   classic-abc (-48) -- and only the noisy abc9 number disagreed. Pre-map is
   the cheapest naming-invariant measure of complexity available; read it as
   evidence about where the distribution sits, not about one build.
2. **"Select the operands, not the result" is site-dependent, not a law.** It
   won -168/-54 once on a seven-arm 25-bit mux where several arms wanted the
   same expression. Here, on four arms over a 13-bit base, it is zero: the
   mapper was already sharing the adders, and the select had to be bought.
   The distinguishing feature is arm *width* and duplication, not arm count.

## Hypothesis H160

- **ID:** H160.
- **Hypothesis:** `fade_acc + fade_step` is evaluated four times at two widths
  in `rtl/psg_seq.sv` -- 17-bit for the wrap test at :1233, 16-bit for the
  accumulate at :1243 and the gain byte at :1245/:1246. One 17-bit sum serves
  all four: `[16]` is the wrap, `[15:0]` the accumulator, `[15:8]` the byte.
- **Scope:** `rtl/psg_seq.sv` fade advance only. Exact by construction.
- **Baseline:** rtl `1a76c4596af2`.
- **Change:** one `wire [16:0] fade_sum = {1'b0, fade_acc} + {4'b0, fade_step}`
  replacing the four separate evaluations.
- **Result:** pre-map 13,482 -> 13,430 (**-52 cells, -16 carries**), but mapped
  LUT4 6,330 -> **6,359 (+29)**, carries +3, unpackable +2, **floor 6,828 ->
  6,859 (+31)**, placed +31. Deleting a duplicated adder made the design
  *larger*: the duplicates were being fused into their consumers' cones, and
  forcing one materialised net broke all three fusions.
- **Decision:** rejected **alone**; **accepted as part of H161**. Do not read
  this row without H161 -- in isolation it is a regression, in composition it
  is half of a -33 floor win.
- **Repeat only if:** n/a; superseded by H161.

## Hypothesis H161

- **ID:** H161.
- **Hypothesis:** H159 (four wavetable-fetch adders -> one index-selected add)
  and H160 (one shared 17-bit fade sum) are unrelated arithmetic respellings
  that individually measure floor **0** and **+31**. Noise is not additive, so
  the composition is not the sum: measure the bundle, not the parts.
- **Scope:** `rtl/psg_walk.sv` fetch block and `rtl/psg_seq.sv` fade advance.
  Both exact by construction -- no value bound is relied on anywhere.
- **Baseline:** rtl `1a76c4596af2` @ `452d3b2`.
- **Changed condition versus H159/H160:** neither is changed; only their
  *joint* evaluation is new. This row exists because one-at-a-time evaluation
  is **biased**, not merely slow, when effects do not compose.
- **Result, pre-registered before measurement** (primary `-noabc`, PASS iff
  candidate < baseline; any deterministic instrument disagreeing in sign
  forces revert; confirmatory abc9 n=20/arm, one-sided Mann-Whitney,
  alpha=0.01, named in advance):

  | Instrument | baseline | candidate | delta | deterministic |
  | -- | -- | -- | -- | -- |
  | pre-map cells | 13,482 | 13,349 | **-133** | yes |
  | **`-noabc` floor** | 8,879 | 8,791 | **-88** | **yes, spread 0** |
  | classic-abc floor | 6,947 | 6,899 | **-48** | spread 9 |
  | abc9 floor, median of 20 | 6,842.0 | 6,807.5 | **-34.5** | no |

  abc9 rank test: **U = 378.5 / 400, z = 4.83, p ~ 7e-7**. Every instrument
  agrees in sign, and the two provably noise-free ones show the largest effect.
- **Gates:** `sweep`/`models`/`mul`/`oracle` PASS -- all 59 frozen renders
  byte-identical. `pico8` fails **identically to the unmodified baseline**:
  a pre-existing regression bisected elsewhere to `24a465a` (multi-pump
  latency advancing the `!m_busy`-gated micro-PC), not this change. Note
  `oracle` is structurally blind to that class, since its cases do not chain
  music patterns -- 59/59 is necessary evidence here, not sufficient.
- **Decision:** accepted.
- **Repeat only if:** n/a. **The transferable result is the method:** two
  changes that each fail alone can pass together, so evaluate families as
  bundles. Fmax fell 2.7 MHz on the one placement measured and still needs a
  seed distribution.

## Hypothesis H162 -- H142/H153 retried under the doctrine

- **ID:** H162.
- **Hypothesis:** H142 and H153 were both decided on **isolated** synthesis
  (floor +6, and "floor unchanged"), never on a whole-design measurement, and
  both magnitudes sit far inside the 62--72 cell abc9 noise. Retry them
  against the deterministic instruments, individually and as a bundle, since
  H161 showed two individually-failing changes can pass together.
- **Scope:** re-implement both from the recorded transforms; decide on
  `detfloor.sh` plus an abc9 distribution. No new proof work -- H142's
  exactness was already established (131,072 role transactions plus a SAT
  miter).
- **Baseline:** accepted H161 at `417e954`, rtl `e004a57e4ee8`: pre-map
  13,349, `-noabc` floor 8,791, classic-abc floor 6,899, abc9 floor median
  6,811.5 (n=16, spread 72).
- **Changed condition versus H142/H153:** only the instrument. Neither
  transform is altered.
- **Result:**

  | arm | pre-map | `-noabc` | classic-abc | abc9 median (n=16) |
  | -- | -- | -- | -- | -- |
  | H142 | **+18** | **+5** | +2 | not run |
  | H153 | +3 | +1 | **-28** | 6,804.0 (U=137.5/256, **p~0.36**) |
  | H142+H153 | +21 | **+6** | **-49** | 6,799.0 (U=157.5/256, **p~0.13**) |

  H142 retires the twelve unpackable flops it promised (509 -> 497) and buys
  **+17 LUT4** doing it; all three deterministic instruments agree it is worse.
  H153 and the bundle move nothing abc9 can distinguish from zero.
- **Decision:** all rejected and reverted.
- **Two findings worth more than the hypotheses:**
  1. **The original H142 verdict was right; its evidence was not.** An isolated
     floor of +6 could never have established it, and the deterministic
     instruments now do. Re-testing the sub-100 tail will **confirm** rows as
     well as overturn them -- that tail is unestablished, not wrong.
  2. **classic-abc is not a trustworthy proxy.** It read **-28 / -49** on
     changes abc9 cannot distinguish from zero (p~0.36 / p~0.13). Its
     "spread 9" came from **n=6** and is very likely an underestimate. Use
     `-noabc` (spread 0, measured) and pre-map as the deterministic
     instruments; treat classic-abc as decoration until its spread is
     characterised at n>=30.
- **Repeat only if:** the `mx_old` role schedule or the `note_lo`/`cpz`
  lifetimes change materially. Do **not** retry on a classic-abc signal alone.

## Hypothesis H163 -- the top rejected rows by plausibility, re-tested

- **ID:** H163.
- **Hypothesis:** rank the rejected rows by the part of their record that is
  *trustworthy* -- unpackable flops and carries retired, not LUT4 -- and
  re-test the ones whose kill margin sits inside the noise. Pre-map was never
  recorded before H155, so it cannot be used; `(unpackable retired) - (LUT4
  added)` is the best available proxy, and only H148 (-5) and H145 (-12) had
  margins inside +-30.
- **Baseline:** accepted H161 at `417e954`, rtl `e004a57e4ee8`: pre-map 13,349,
  `-noabc` floor 8,791 (LUT4 8,282 / 509 unpackable).
- **Instruments:**

  | candidate | pre-map | `-noabc` floor | LUT4 | unpack |
  | -- | -- | -- | -- | -- |
  | H145 saving *(delete both dampen adders -- a CEILING)* | **-39** | **-38** | -38 | 0 |
  | H145 cost *(two extra arms on the fold operand mux only)* | **+84** | **+34** | +34 | 0 |
  | H081 *(full transform, one 30-bit selected add)* | +5 | **+31** | +22 | **+9** |

  abc9 distribution: n/r -- no candidate reached a deterministic improvement.
  EBR: unchanged (14) for H145/H081; H148 requires 15.
- **Decision:** all three rejected; original verdicts confirmed.
  - **H145** ceilings at **-4 floor**: its entire saving is 38 cells and two
    operand-mux arms alone cost 34, before the signed-19 ALU widening and the
    two-phase state machinery it also needs. Dead without implementing it.
  - **H081** is **+31 floor** whole-design -- and its unpackable count *rises*
    by nine, because the operand mux needs staging. It was rejected on an
    isolated +20; the whole-design number is worse, not better.
  - **H148** is dead on the constraint, not the arithmetic: it needs a
    fifteenth EBR and its net logic is +19 LUT4 / +5 floor, so it fails the
    "recompaction must buy positive net logic" rule in both terms. Its table
    already lives in `crom`; the transform moves it *out* to a dedicated block,
    so freeing `crom` words cannot rescue it. (An earlier suggestion in this
    session that it could was a misreading of the transform's direction.)
- **The reusable number:** **two arms on a shared 18-bit ALU cost 34 floor
  cells**, measured directly. That is the exchange rate for "serialize through
  a shared ALU", and it is why every candidate in that class has charged. A
  serialization must retire more than ~17 cells per arm it adds to break even.
- **Repeat only if:** the fold ALU stops being shared, or a serialization
  appears that adds no operand arms at all.

## Audit A001 -- the eleven accepted rows inside the noise, re-priced

Every accepted row whose claim sat under ~100 cells, measured as **landing
commit vs its parent** on the two trustworthy deterministic instruments. No
re-implementation: these are all in the tree already, so the measurement is
`git archive` plus two yosys runs per side.

| H | landing commit | recorded claim | pre-map | `-noabc` floor | verdict |
| -- | -- | -- | -- | -- | -- |
| H089 | `996ee40` | -63 LUT4 | **-86** | **-58** | real, large |
| H027 | `9c4a1ac` | -69 carries, -61 LC | **-68** | -12 | real; carry-heavy, so the floor shows less |
| H022 | `f569fa1` | "trade 17 LUT4" | **-59** | **-29** | real, **larger** than recorded |
| H080 | `6458450` | -24 LUT4, -23 carries | **-48** | **-47** | real, large |
| H047 | `c1b4862` | -28 LUT4, -33 carries | **-39** | **-46** | real, large |
| H069 | `d3ce9a6` | -10 LUT4 | -24 | -26 | real |
| H075 | `c634db2` | -23 LUT4 | -11 | -10 | real, small |
| H007 | `48f0ef5` | -46 LUT4, -13 carries | -6 | -6 | real but **~8x smaller** |
| H155 | `78b8bec` | -6 floor | -5 | -2 | real, small (priced earlier) |
| **H057** | `c9274fc` | -23 LUT4 | **+1** | **0** | **nothing** |
| **H096** | `a647185` | -31 LUT4 | **+1** | **0** | **nothing** |

The measurements chain: H007's landed state is H022's parent, H069's landed is
H075's parent, H080's landed is H089's parent. Consecutive commits line up
exactly, which is a check on the method as well as the numbers.

**Nine of eleven are real, totalling ~236 floor cells.** The accepted lineage
is sound; the campaign did not build on sand.

**What was wrong was magnitude, not sign.** H007 claimed -46 LUT4 and delivers
-6. H022 was recorded as a 17-LUT4 *trade* and delivers -29 floor. Every
recorded figure was a single abc9 draw, so it carried +-30 of noise on top of
whatever the transform actually did.

**H057 and H096 delivered exactly zero** on both deterministic instruments.
They are not harmful -- both are principled respellings and neither costs
anything -- but their recorded area justifications (-23 and -31 LUT4) were
noise. Do not cite either as evidence that its mechanism pays.

**The asymmetry against the rejected tail is the useful part.** Accepted rows
survive re-pricing 9/11; the two rejections re-tested so far (H142, H153) both
*confirmed*. The plausible reason is that these transforms were principled --
exact algebraic identities, clamp respellings, adder sharing -- and principled
transforms tend to be genuinely smaller. Noise corrupted the recorded size, not
the decision. That lowers the expected yield from re-running the rejected tail:
it is unestablished, but it is not obviously a pile of missed wins.

## Hypothesis H164 -- the open composition stage's cheap half, priced exactly

- **ID:** H164.
- **Hypothesis:** the 2026-08-04 open composition stage (Current State) plus a
  fresh ten-candidate pool grouped by lever class: (A) exact carry arithmetic
  -- the held H156 `gz` re-association, the `16'd65535 - wx_r == ~wx_r` wave
  reflection identity, a shared `pticks + 1` sum; (B) storage/decode -- H4'
  state-mem migration, H1' control-ROM decode; (C/D) the never-opened carry
  families `dq_live_r`, `s_last_G`, `divd`, `wx_r` tail, `w_clr_tog`/`old_q0`
  width audit. Speculated aggregate ~120-150 pre-map cells (~25-40 carries),
  against a ~100 LUT/carry goal gate, carries prioritised.
- **Scope:** gate-1 pricing of every group-A/C/D member against the exact
  proposed replacement in isolated `git archive HEAD` tree copies; production
  RTL untouched by any rejected member. Groups B deferred to their own
  transactions (build cost is session-sized).
- **Baseline:** rtl `e004a57e4ee8` @ `a121c03` (accepted H161): pre-map 13,349
  cells / 1,389 carry wrappers / 1,450 flops; `-noabc` floor 8,791 (LUT4 8,282
  / 509 unpackable); classic-abc floor 6,899; canonical abc9 map 6,300 LUT4 /
  1,272 carries / 499 unpackable / floor 6,799; **placed 7,027 @ 31.35/128.35
  MHz, 14 EBR** (first placed vector recorded for the H161 lineage).
- **Changed condition versus H156/H158/H160:** H156/H158 were ablation
  ceilings ("held for composition"), never priced as exact replacements; this
  row prices them. The `pticks` share is a new instance of the H160 shape
  inside a bundle, which H161 licenses.
- **Change:** four isolated A/B pre-map measurements; no production RTL kept.
- **Result:**

  ```
  (i)   gz re-association (held from H156):
        pre-map 13,349 -> 13,349, carries 1,389 -> 1,389 -- BIT-IDENTICAL
        across every gate type. wreduce already splits the {B,9'b0}+{9'b0,x}
        shifted-operand form; the "34-bit add" was never physically 34 bits.
        H156's ~-8 was an unmeasured estimate. Measured: exactly 0.
        (The re-association itself needs no m_res[28] proof: keeping
        B = m_res[27:3] in the outer term, floor((B*2^10+y)/2^20) ==
        floor((B + floor(y/2^10))/2^10) unconditionally. Moot at 0.)
  (ii)  q16 second-address adder share (held from H158): ALREADY LANDED --
        subsumed by H159/H161's single index add (`syn_plus1` folds the +1
        into the 6-bit index select at HEAD). Struck from the composition
        list; do not carry it forward.
  (iii) wave reflection identity (65535 - wx_r -> ~wx_r, psg_wave.sv:52):
        pre-map 13,349 -> 13,349. opt_expr already folds all-ones-minus-x.
        Measured: exactly 0.
  (iv)  pticks shared increment (psg_seq.sv:1170/:1172):
        pre-map 13,349 -> 13,352 (+3), carries 1,389 -> 1,390 (+1). REJECTED.
  (v)   dq_live_r / s_last_G / wx_r tail / widths: closed by inspection --
        the dq service is an already-minimal radix-4 shift-add engine,
        g_live is one 13-bit shift-add, s_old_phase/old_q0 already narrowed.
        No removable spelling identified; no measurement spent.
  (vi)  H1' control-ROM decode: REJECTED AT POOL TIME by precedent
        arithmetic -- its measured replaceable core (-41 pre-map) is smaller
        than the pph fabric's -75, which mapped +21 LUT4 and cost a block;
        the unpriced prefetch register and stall handling only add.
  ```

  abc9 distribution: n/r -- no candidate reached a deterministic improvement.
- **Decision:** all of groups A/C/D rejected or closed at gate 1; H1' closed
  at pool time. **The open composition stage's bundle total collapses from
  "about -48 floor" to H4' alone (~-29 floor screened)** -- the only surviving
  byte-exact candidate, unbuilt, wash-risk documented (sfx_id staging).
- **Repeat only if:** (i)/(iii) never -- synthesis performs them; (iv) only
  inside a bundle whose other members clear the band; (vi) only if a control
  word is found that replaces >=100 pre-map cells of decode with no new
  stall/prefetch state.

**Instrument fix landed with this row:** every fingerprint site (`Makefile`
`synth-<unit>`, `tools/psg_area_gate.sh`, `tools/psg_area_dist.sh`,
`scripts/premap.sh`, `scripts/detfloor.sh`) hashed `rtl/*.v` including the
**generated, gitignored `rtl/pll.v`**, so two identical source trees could
fingerprint differently. All five now exclude it; the corrected formula
reproduces the ledger's `e004a57e4ee8` at `a121c03`, restoring cross-tree
comparability.

## Operation Cost Catalog (2026-08-04)

Derived, not read: a scope census plus 45 ablation runs (31 from a clean-room
agent given no access to this ledger, 14 from a walker schedule sweep). It
exists so the next session inherits the ranking instead of re-deriving it.

Baseline for every number below is rtl `1a76c4596af2` -- pre-map 13,482 cells
/ 1,433 carries / 1,450 flops; 6,330 LUT4, 1,292 carries, 498 unpackable,
floor 6,828, placed 7,052, 14 EBR. Captured at `c1ad243` and still current at
`452d3b2`, which committed only the area-gate tooling and left `rtl/`
byte-identical. Quote the fingerprint, not the commit: `452d3b2` landed
mid-session and the distinction is what makes these numbers still valid.

**Disjoint decomposition -- this one sums to the 6,828 floor.**

| Scope | LUT4 | carry | unpack | LC floor |
| -- | -- | -- | -- | -- |
| `u_walk` | 2,356 | 509 | 124 | 2,480 |
| `u_seq` | 1,921 | 263 | 247 | 2,168 |
| `u_wave` (all of it in `u_ctx`) | 733 | 250 | 46 | 779 |
| `u_mul` (multipump) | 716 | 171 | 9 | 725 |
| `u_state` | 166 | 0 | 18 | 184 |
| `u_aram` | 149 | 22 | 25 | 174 |
| `u_div` | 112 | 42 | 8 | 120 |
| `u_timing` | 53 | 29 | 2 | 55 |

**Operation ablation ceilings (vs 13,482 cells / 1,433 carries).** These are
constant ablations, so each folds everything downstream with it -- that cascade
is deliberately included, and it is why they **do not sum**.

| Operation | dcells | dcarry | dff |
| -- | -- | -- | -- |
| multiplier operand plumbing, both sides | -1,171 | -48 | -53 |
| computed wave shaper, whole | -1,137 | -259 | -54 |
| -- sequencer side of that plumbing | -751 | -30 | -33 |
| -- exact /3, /7, /15 shapes | -730 | -120 | -35 |
| sequencer state-mem write decode | -454 | -22 | -1 |
| -- walker side of that plumbing | -427 | -18 | -20 |
| pitched noise | -423 | -59 | -25 |
| exact slide interpolation | -354 | -87 | -59 |
| preceding-arm (old voice) consumers | -315 | -102 | 0 |
| reciprocal recombination adder | -223 | +2 | -1 |
| soft-add 5:1 compression | -202 | -8 | 0 |
| aRAM address decode | -143 | -4 | -1 |
| `sfx_id`+`trg_row`+`trg_len`+`aud_row` | -130 | 0 | **-90** |
| crossfade blend | -116 | -63 | 0 |
| /3 gain accumulation | -51 | -51 | 0 |
| wavetable lerp | -39 | -20 | 0 |

**Walker schedule slots (same baseline).**

| Slot | dcells | dcarry | Role |
| -- | -- | -- | -- |
| `CAP_W0` | -1,701 | -156 | LFSR + phase advance + crossfade snapshot |
| `CAP_W84` | -328 | -119 | dampen filter, `filt_y` write |
| `CAP_W1` | -273 | -18 | old-arm noise, wavetable phase |
| `CAP_W5` | -232 | -35 | old-arm phase advance |
| `CAP_W2` | -125 | 0 | transition-detect tuple (`s_last_*`) |
| `CAP_W15` | -122 | -15 | wavetable z / /3 limb capture |
| `CAP_W51` | -94 | -15 | final mix scale |
| `CAP_W6` | -87 | -17 | secondary oscillator advance |
| `CAP_W75` | -87 | 0 | crossfade blend multiply |
| `CAP_W3` | -56 | 0 | second sample point |
| `CAP_W4` | -52 | 0 | sample/wavetable point, leaf stage |
| `CAP_W26` | -39 | 0 | wavetable `smp_b` |
| `CAP_W27` | -17 | 0 | live gain consume |
| `CAP_W40` | **-1** | 0 | second /3 accumulation write |

**The four calibration constants everything above should be read through.**

1. **Deleting one multiplier mux arm costs -38 cells; merging two arms
   algebraically costs +4.** Measured twice independently (-38 clean-room,
   -44 for the `/3` client with its cascade). So the -1,171 of multiplier
   plumbing is collectable only by deleting *requesters*, never by
   restructuring. There is no algebraic path to it.
2. **The shared multiplier's plumbing is ~9x its arithmetic.** Inside `u_mul`
   the recurrence `m_p` is 49 LUT4 / 19 carries / 34 flops; the request path is
   621 LUT4 / 149 carries. This is the quantitative statement of why fabric,
   not features, dominates the netlist -- and, with (1), why that fact is not
   by itself a lever.
3. **The slot ceilings sum to -3,214 against a `u_walk` floor of 2,480.** The
   catalog over-attributes by more than the module contains. Each operation
   really does carry downstream fabric with it, but those shares are shared,
   so each can be collected only once. `CAP_W0`'s -1,701 is the extreme case
   and is an artefact: deleting the phase advance stops the oscillator.
4. **Aggregate composition:** 29.0% `$_MUX_`, 56.6% AND/OR/NOT, 10.6% carry,
   3.5% XOR. The arithmetic that computes audio is ~11-14% of the netlist.

**What the catalog says the remaining levers are.** Not restructuring. Area is
proportional to the number of distinct scheduled operations, at roughly 38
cells of fabric per retired operation *plus* that operation's own logic. The
old-voice/crossfade arm is the largest removable cluster and four independent
slices agree on it: `CAP_W1` -273, `CAP_W5` -232, `CAP_W75` -87, `oldarm`
-315, `xfade` -116, plus the `mx_old` census family at 295 LUT4 / 77 carries.
The long-standing ~-220 working estimate for crossfade removal is too low;
400-600 is the defensible range once its arms, modes, staging flops and
mix-side consumers retire together. That remains a fidelity decision, not an
RTL one.

## Clean-room Candidate Pool (2026-08-04)

Ten hypotheses from an agent deliberately denied this ledger, the skill's
closed-verdict catalogue and the memory files, then priced against them. Kept
as a pool per the ranked-pool discipline; none has been run as a hypothesis.

| # | Candidate | Claimed | Standing against the record |
| -- | -- | -- | -- |
| H4' | `sfx_id`/`trg_row`/`trg_len`/`aud_row` into the unreachable `psg_state_mem` words 33..63 | -70..-90 LC floor, -90 flops | **Best of the ten.** Address-selected storage is the one sharing mechanism with no per-bit input muxes and the class that has won every time. Adjacent to H101/H112/H129 but the mechanism differs where it matters: free already-instantiated storage on existing V_LD/V_ST traffic, not a new EBR with forwarding. The known killer is unchanged -- async CPU `$10-$13` writes need staging, which priced `sfx_id` as a wash before (24 staging flops against 46 saved). |
| H1' | Control-ROM the sequencer's four replicated 60-state decodes | -250..-400 | **Genuinely untried** -- no ledger row for microcode/microword/sst decode, and `crom[64..255]` was reserved as its home. But its case rests on a pre-map ceiling for pure mux fabric, and the closest measured precedent inverted: the pph address fabric as a control word read -75 pre-map and mapped **+21 LUT4** while costing a block. |
| H2' | Widen the reciprocal ROM so the double fold disappears | -250..-350 | Costs 9-12 EBR against the preserved 14-EBR topology (23-26 of 32). Violates a scope property every hypothesis has held; the property is self-imposed, so this is a user call, not a refutation. |
| H3' | Piecewise-linear wave ROM replacing `psg_wave_ctx` | -600..-800 | Render-changing, and the slopes for waves 1/5 are non-dyadic. Precedent exists for accepting a render-changing wave stage with a re-frozen baseline, so it is admissible -- but it is the largest-blast-radius item here. |
| H5' | Four-leaf mixer: at most 4 of 8 leaves are ever non-zero | -40..-80 | The bound is a real invisible bound, the richest class. Exactness hinges entirely on `soft_add(x,0) == x`, which **fails** for `|x| >= 24576` (`psg_walk.sv:764`) -- and leaves come from a 17-bit `gz_filt_r`. Very likely render-changing; one simulator run over a Celeste track settles it. |
| H6' | Replace the literal `x341` reciprocal with the base-256 split | area-neutral | Confirmed area-neutral by two measurements (arm -38/-44, `gz3` -51, new shift-add ~+90). Its product is schedule slack, not cells. |
| H7' | Time-share the duplicated `noise_clamp` | -80..-140 | `noise-clamp` is already a closed family, and H139 accepted sharing the noise scale tree. Also buys an operand mux to save a clamp -- the shape that has charged every time. |
| H8' | Slide's two divisions via a `1/sp` reciprocal ROM | ~-175 | Exactness is the whole risk and PICO-8 slides are audibly pitch-sensitive; the affine-slide-carry family is closed and H074 showed a low-carry change moving a reachable published increment. |
| H9' | Read the preceding arm from the inactive parameter bank instead of `s_last_*` | -100..-180 | Depends on the inactive bank being a stable previous tuple, which the publication window breaks. Adjacent to blocked R.40--R.42 lifetime aliases. |
| H10' | Merge `psg_divsvc` into `psg_mulmp` | -60..-90 | Probably dead on its own evidence: `psg_seq.sv` xs=5 issues `div_start` **and** `mul_go`, so merging serialises them and `SEQ_BUDGET = 272` must be re-derived. Also a shared-ALU shape (R.63/R.64 blocked). |

**Structural oddities the same pass turned up, none yet actioned:** 48% of
`psg_state_mem` is unreachable (`PSG_VSTR` 64 vs highest address `PSG_V_SEQ`
32); `crom[144..205]` encodes 14 events in 62 words and `crom[206..255]` is
unused; `psg_wave.sv:247--327` is a whole second `floor(K*dp/256)`
implementation live only under PREVIEW (swapping the serial engine for it
measures **+123**); `ring_rp` is declared and incremented outside its own
`if (REVERB)` generate; `pph` is `[6:0]` with `PLAST = 61`; `s_phase2` is 24
bits carrying 17 live ones; forcing `sst`'s `fsm_encoding` costs **+315** and
`one_hot`/`binary` give byte-identical results, so the default `fsm` pass is
worth that much and should not be touched.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `build/experiments/h155/baseline-head.{json,pnr.log}` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` at clean `644d68f` | Clean-HEAD canonical map (floor 6,834) and the stuck seed-1 route (overuse=2 through 18,052 iterations). |
| `build/experiments/h155/premap-{baseline,candidate}.log` | `yosys ... synth_ice40 -run :map_luts; stat` | Pre-map A/B: 13,487 -> 13,482 cells. |
| `build/experiments/h155/candidate.{json,asc}` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H155 | Accepted canonical build; a forced rebuild reproduces both byte-identically. |
| `build/experiments/h155/oracle-matrix.log` | `tools/psg_oracle_matrix.py ... --clock 18750000` | 59/59 byte-identical, 59/59 diagnostic-clean. |
| `build/experiments/h155/{test-psg,test-clocks,preview,recovery,clicks}.log` | the named make targets | Complete behavior battery, all PASS. |
| `build/experiments/h155/smoke.ppm` + `smoke-run.log` | five-frame headless Celeste run | Byte-identical smoke, SHA-256 `3d4933a9...`. |
| `build/experiments/h001/baseline.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` at `86d4fab` | H001 baseline mapping. |
| `build/experiments/h001/baseline.pnr.log` | same | H001 baseline seed-1 placement and timing. |
| `build/experiments/h001/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H001 | H001 accepted mapping. |
| `build/experiments/h001/candidate.pnr.log` | same | H001 accepted seed-1 placement and timing. |
| `build/experiments/h001/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h001/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h002/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H002 | H002 accepted mapping. |
| `build/experiments/h002/candidate.pnr.log` | same | H002 accepted seed-1 placement and timing. |
| `build/experiments/h002/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h002/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h003/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H003 | H003 accepted mapping. |
| `build/experiments/h003/candidate.pnr.log` | same | H003 accepted seed-1 placement and timing. |
| `build/experiments/h003/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h003/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h005/candidate-v1.{synth,pnr}.log` | canonical synthesis with the rejected `< 3` spelling | Smaller map and placement, but routed fast-clock timing failure. |
| `build/experiments/h005/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with retained H005 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h005/candidate-v2.{synth,pnr}.log` | retained-spelling synthesis checkpoint | Pre-canonical retained mapping and placement evidence. |
| `build/experiments/h005/celeste-audio.{hex,bin}` | reconstructed from `src/celeste/audio.inlay.asm` | 4,608-byte recovery-probe audio image. |
| `build/experiments/h005/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h005/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h007/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H007 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h007/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h007/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h009/candidate.{synth,pnr}.log` | canonical synthesis with the rejected shift token | Exact isolated win, but whole-PSG mapped and placed regression. |
| `build/experiments/h010/candidate.{synth,pnr}.log` | canonical synthesis with the rejected pending bit | Exact isolated flop/LUT win, but whole-PSG mapped and placed regression. |
| `build/experiments/h012/candidate.{synth,pnr}.log` | canonical synthesis with the rejected sequencer-busy output | CDC proofs pass, but whole-PSG mapped and placed area regress. |
| `build/experiments/h013/candidate.{synth,pnr}.log` | canonical synthesis with both services narrowed | Exact width proof, but whole-PSG mapped and placed area regress. |
| `build/experiments/h013/candidate-v2.{synth,pnr}.log` | canonical synthesis with only the multipumped service narrowed | Mapping-identical attribution variant; rejected. |
| `build/experiments/h014/isolated-{baseline,candidate}.log` | registered full-detune `synth_ice40` comparison | Both forms map identically; production patch rejected. |
| `build/experiments/h015/isolated-{baseline,candidate}.log` | registered full-detune `synth_ice40` comparison | Unconditional subtract maps identically; production patch rejected. |
| `build/experiments/h016/isolated-{baseline,candidate}.log` | full registered divider `synth_ice40` comparison | Exact nine-bit form trades one carry for one LUT locally. |
| `build/experiments/h016/candidate.{synth,pnr}.log` | canonical synthesis with the nine-bit restoring subtract | Whole-PSG mapped and placed area regress; rejected. |
| `build/experiments/h017/isolated-{baseline,candidate}.log` | registered gain-consumer synthesis | Full context sharing is locally much smaller. |
| `build/experiments/h017/isolated-candidate-v2.log` | registered gain-consumer synthesis | Scale-only attribution form; locally smaller. |
| `build/experiments/h017/candidate-v1.{synth,pnr}.log` | canonical synthesis with full context sharing | Mapped and placed area regress; rejected. |
| `build/experiments/h017/candidate-v2.{synth,pnr}.log` | canonical synthesis with scale-only sharing | Smaller regression, but placement still exceeds H007; rejected. |
| `build/experiments/h018/isolated-{baseline,candidate}.log` | registered reciprocal half-sum synthesis | Exact 25-bit form trades one carry for one LUT locally. |
| `build/experiments/h018/candidate.{synth,pnr}.log` | canonical synthesis with the shifted half-sum | Whole-PSG mapped and placed area regress; rejected. |
| `build/experiments/h019/isolated-{baseline,candidate,candidate-v2}.log` | state-store ownership synthesis with target schedule qualifiers | Both whole-walk forms are locally smaller. |
| `build/experiments/h019/owner-{proof.py,proof.log}` | exhaustive legal-owner and replay-timeline proof | All write states, consumed reads, and replay observation points agree. |
| `build/experiments/h019/candidate-v1.{synth,pnr}.log` | canonical synthesis with complete-bundle ownership | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h019/candidate-v2.{synth,pnr}.log` | canonical synthesis with retained write-enable OR | Whole-PSG map regresses; router stopped after the mapped gate failed. |
| `build/experiments/h020/containment-{proof.py,proof.log}` | exhaustive wavetable-read/replay containment proof | All six possible read phases and following replay edges remain inside `prun`. |
| `build/experiments/h020/isolated-{baseline,candidate}.log` | registered audio-RAM/top-level hold cone | Exact candidate saves one local LUT4. |
| `build/experiments/h020/candidate.{synth,pnr}.log` | canonical synthesis without exported `seq_frozen` | Whole-PSG map and seed-1 placement regress; rejected. |
| `build/experiments/h021/filter-{proof.py,proof.log}` | exhaustive wrapped-base-3 proof | All 32 filter codes agree. |
| `build/experiments/h021/isolated-{baseline,arith,staged}.log` | complete registered filter decoder/consumer synthesis | Both arithmetic forms are larger than the case table. |
| `build/experiments/h022/clamp_proof.py` and `clamp-proof.log` | exhaustive signed clamp and live-range proof | All signed-nine inputs and live signed-eight sums agree. |
| `build/experiments/h022/candidate-v2.{synth,pnr}.log` | canonical synthesis with the accepted eight-bit prefix clamp | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h022/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h022/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h023/octave_proof.py` | exhaustive scratch octave/chromatic proof | All 64 slide pitches agree with quotient/remainder. |
| `build/experiments/h023/isolated-{baseline,candidate}.log` | registered octave/chromatic `synth_ice40` comparison | Candidate removes one LUT4 and 11 carries locally. |
| `build/experiments/h023/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H023 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h023/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h023/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h024/row_bound_probe.sv` | registered pair of current and prefix row bounds | Isolated comparison source. |
| `build/experiments/h024/isolated-{baseline,candidate}.log` | `synth_ice40` comparison of both registered bounds | Exact prefix pair removes two carries with identical LUT4/FF counts. |
| `build/experiments/h024/candidate.{synth,pnr}.log` | canonical synthesis with the rejected prefix pair | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h025/fade_sum_probe.sv` | current repeated fade adds versus one explicit sum | Formal and isolated-synthesis source. |
| `build/experiments/h025/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 25 output equivalence cells proved. |
| `build/experiments/h025/isolated-{baseline,candidate}.log` | registered fade-consumer `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h026/ta_ge_probe.sv` | current relation and two carry-out variants | Formal and isolated-synthesis source. |
| `build/experiments/h026/equiv-v1.log` | Yosys equivalence of the raw carry | Refuted by the `a=255,b=0` tenth-bit overflow corner. |
| `build/experiments/h026/equiv.log` | Yosys equivalence of the repaired carry | Exact form proved. |
| `build/experiments/h026/isolated-{baseline,candidate-v1,candidate}.log` | registered predicate `synth_ice40` comparison | Repaired form saves nine carries with identical LUT4/FF counts. |
| `build/experiments/h026/candidate.{synth,pnr}.log` | canonical synthesis with the repaired carry | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h027/noise_clamp_probe.sv` | current relational and exact signed-prefix clamps | Formal and isolated-synthesis source. |
| `build/experiments/h027/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 16 result bits proved for the full signed-18 domain. |
| `build/experiments/h027/isolated-{baseline,candidate}.log` | registered clamp `synth_ice40` comparison | Candidate removes all 32 carries for two LUT4s. |
| `build/experiments/h027/candidate.{synth,pnr}.log` | canonical synthesis with H027 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h027/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h027/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h028/arp_speed_probe.sv` | relational and exact-prefix `arp_idx` consumers | Formal and isolated-synthesis source. |
| `build/experiments/h028/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Both output bits proved. |
| `build/experiments/h028/isolated-{baseline,candidate}.log` | registered selector `synth_ice40` comparison | Candidate removes four carries for two LUT4s locally. |
| `build/experiments/h028/candidate.{synth,pnr}.log` | canonical synthesis with the exact prefix | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h029/noise_kick_probe.sv` | relational kick cone and bounded signed margin | Formal and isolated-synthesis source. |
| `build/experiments/h029/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Enable bit proved over the full input domain. |
| `build/experiments/h029/isolated-{baseline,candidate}.log` | registered kick cone `synth_ice40` comparison | Candidate removes 22 LUT4s locally. |
| `build/experiments/h029/candidate.{synth,pnr}.log` | canonical synthesis with the affine margin | Whole-PSG placement regresses; rejected. |
| `build/experiments/h030/trigger_length_probe.sv` | relational and exact-prefix registered saturation consumers | Formal and isolated-synthesis source. |
| `build/experiments/h030/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All six registered result bits proved. |
| `build/experiments/h030/isolated-{baseline,candidate}.log` | registered saturation `synth_ice40` comparison | Candidate removes both carries with identical LUT4/FF counts. |
| `build/experiments/h030/candidate.{synth,pnr}.log` | canonical synthesis with H030 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h030/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h030/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h031/tnl_compare_probe.sv` | registered current and shared comparator consumers | Formal and isolated-synthesis source. |
| `build/experiments/h031/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Both registered consumer outputs proved. |
| `build/experiments/h031/isolated-{baseline,candidate}.log` | registered paired-comparator `synth_ice40` comparison | Candidate removes seven carries with identical LUT4/FF counts. |
| `build/experiments/h031/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H031 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h031/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h031/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h032/record_base_probe.sv` | registered current and record-first address consumers | Formal and isolated-synthesis source. |
| `build/experiments/h032/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered address bits proved. |
| `build/experiments/h032/isolated-{baseline,candidate}.log` | registered audio-address `synth_ice40` comparison | Candidate removes one LUT4 and seven carries locally. |
| `build/experiments/h032/candidate.{synth,pnr}.log` | canonical synthesis with the record-first address | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h033/readback_activity_probe.sv` | registered current and paired-bit CPU readback consumers | Formal and isolated-synthesis source. |
| `build/experiments/h033/{equiv-induct,exhaustive}.log` | temporal-induction and all-tuple identity proofs | All eight registered outputs and 1,024 Boolean cases proved. |
| `build/experiments/h033/isolated-{baseline,candidate}.log` | registered CPU-readback `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h034/pattern_rows_probe.sv` | relational and exact-prefix registered saturation consumers | Formal and isolated-synthesis source. |
| `build/experiments/h034/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All six registered result bits proved. |
| `build/experiments/h034/isolated-{baseline,candidate}.log` | registered pattern-row `synth_ice40` comparison | Candidate removes two carries for one LUT4 locally. |
| `build/experiments/h034/candidate.{synth,pnr}.log` | canonical synthesis with the exact prefix | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h035/detune_suffix_probe.sv` | independent and explicitly nested suffix/ceiling consumers | Formal and isolated-synthesis source. |
| `build/experiments/h035/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 22 registered result bits proved. |
| `build/experiments/h035/isolated-{baseline,candidate}.log` | registered suffix/ceiling `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h036/tilt_quotient_probe.sv` | parallel and preselected registered quotient consumers | Formal and isolated-synthesis source. |
| `build/experiments/h036/equiv.log` | reset-constrained three-step Yosys SAT miter | Complete registered outputs proved after reset. |
| `build/experiments/h036/isolated-{baseline,candidate}.log` | registered quotient `synth_ice40` comparison | Candidate removes five LUT4s and ten flops locally. |
| `build/experiments/h036/candidate.synth.log` | canonical mapping with the selected register | Adds 54 LUT4s and seven flops globally; rejected. |
| `build/experiments/h036/candidate.pnr.log` | canonical seed-1 router2 attempt | Stopped at two overused wires after iteration 14,424. |
| `build/experiments/h037/tilt_h7_width_probe.sv` | ten-bit and live-mode-nine-bit quotient consumers | Formal and isolated-synthesis source. |
| `build/experiments/h037/equiv.log` | reset-constrained three-step Yosys SAT miter | Complete upstream/registered outputs proved. |
| `build/experiments/h037/isolated-{baseline,candidate}.log` | registered quotient `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h038/boost_gain_probe.sv` | nested shift-add and affine/residue gain consumers | Formal and isolated-synthesis source. |
| `build/experiments/h038/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered result bits proved. |
| `build/experiments/h038/isolated-{baseline,candidate}.log` | registered gain `synth_ice40` comparison | Candidate adds 28 LUT4s with carries/flops unchanged. |
| `build/experiments/h039/rec_base_probe.sv` | original and aligned registered record-base transforms | Formal and isolated-synthesis source. |
| `build/experiments/h039/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered address bits proved. |
| `build/experiments/h039/isolated-{baseline,candidate}.log` | registered record-base `synth_ice40` comparison | Candidate removes one isolated flop with LUT4/carry counts unchanged. |
| `build/experiments/h039/candidate.{synth,pnr}.log` | canonical synthesis with aligned `rec_base()` | Accepted mapping, seed-1 placement, and routed timing. |
| `build/experiments/h039/budget-{28125000,22500000}.log` | correctly parameterized `/4` and `/5` budget regressions | Both pass at the established H031 cadence. |
| `build/experiments/h039/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h039/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h040/org_ramp_probe.sv` | truncated negation and explicit conditional-complement organ consumers | Formal and isolated-synthesis source. |
| `build/experiments/h040/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 55 internal and registered consumer bits proved. |
| `build/experiments/h040/isolated-{baseline,candidate}.log` | registered organ-address `synth_ice40` comparison | Candidate removes 13 LUT4s locally for one carry. |
| `build/experiments/h040/candidate.{synth,pnr}.log` | canonical synthesis with explicit organ fold | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h041/fade_length_probe.sv` | registered consumers plus explicit-prior-state next-state pair | Exact scratch proof and isolated-synthesis source. |
| `build/experiments/h041/fade_length_proof.py` | exhaustive unsigned-byte enumeration | The threshold identity passes all 256 values. |
| `build/experiments/h041/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 42 next-state bits proved for arbitrary shared prior state. |
| `build/experiments/h041/isolated-{baseline,candidate}.log` | complete registered fade-control consumer | Candidate trades two LUT4s for four carries locally. |
| `build/experiments/h041/candidate.{synth,pnr}.log` | canonical synthesis with the shared exact prefix | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h042/dq_r193_{probe.sv,proof.py}` | formal/synthesis source and exhaustive residue proof | The correction and complete split pass all 256 residues. |
| `build/experiments/h042/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All ten correction/result bits proved. |
| `build/experiments/h042/isolated-{baseline,candidate}.log` | complete registered triangle-remainder consumer | Candidate removes one LUT4 locally. |
| `build/experiments/h042/candidate.{synth,pnr}.log` | canonical synthesis with the exact Boolean carry | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h043/ea5_length_{probe.sv,proof.py}` | formal/synthesis source and exhaustive tuple proof | Active/stop/advance behavior passes all 4,096 tuples. |
| `build/experiments/h043/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All nine exposed result bits proved. |
| `build/experiments/h043/isolated-{baseline,candidate}.log` | complete registered EA5 consumer | Both forms map identically. |
| `build/experiments/h044/blend_counter_{probe.sv,proof.py}` | recurrence, formal, and isolated-synthesis source | Reachable domain is exactly 0..64; bit six is exactly terminal. |
| `build/experiments/h044/formal.log` | constrained Yosys SAT | Complete registered terminal consumers proved equivalent. |
| `build/experiments/h044/isolated-{baseline,candidate}.log` | registered crossfade-counter consumer | Candidate removes three LUT4s with carry/FF counts unchanged. |
| `build/experiments/h044/candidate.{synth,pnr}.log` | canonical synthesis with terminal high bit | Accepted mapping, seed-1 placement, and routed timing. |
| `build/experiments/h044/budget-*.log` | correctly parameterized `/4`, `/5`, and `/6` regressions | All sample/tick deadlines pass with zero late flips. |
| `build/experiments/h044/preview-*.log` | hardware/PREVIEW cadence checks at both clocks | All masks pass the 95% gate. |
| `build/experiments/h044/{recovery-*,click-*,celeste-smoke*}` | recovery, exact click renders, and five-frame smoke | Recovery passes, zero clicks, and active nonconstant audio. |
| `build/experiments/h045/filter_trit_{probe.sv,proof.py}` | complete three-consumer source and exhaustive trit proof | `fdec` and max closure pass over the full bounded domains. |
| `build/experiments/h045/formal.log` | constrained Yosys SAT | All six registered output bits prove equivalent for valid trits. |
| `build/experiments/h045/isolated-{baseline,candidate}.log` | registered filter-maximum `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h046/effect_class_{probe.sv,proof.py}` | complete normalized-effect source and exhaustive 256-input proof | All three flags and the already-live `e_fx` result agree. |
| `build/experiments/h046/formal.log` | unconstrained Yosys SAT | All six exposed result bits prove equivalent over the complete input domain. |
| `build/experiments/h046/isolated-{baseline,candidate}.log` | registered publication-consumer `synth_ice40` comparison | Candidate removes three LUT4s with carry/FF counts unchanged. |
| `build/experiments/h046/candidate.{synth,pnr}.log` | canonical whole-PSG synthesis | Global LUT4, LC-floor, and routed-LC regression; rejected. |
| `build/experiments/h047/wave_scale_{probe.sv,proof.py}` | formal/synthesis source and exhaustive signed proof | All 1,048,576 signed-18/context tuples agree. |
| `build/experiments/h047/formal.log` | unconstrained Yosys SAT | The complete selected-shift output proves equivalent. |
| `build/experiments/h047/isolated-{baseline,candidate}.log` | registered final-waveform consumer | Candidate removes 44 LUT4s and 33 carries. |
| `build/experiments/h047/candidate.{synth,pnr}.log` | canonical whole-PSG synthesis | Accepted mapping, 7,025-cell floor, 7,251 routed LCs, and passing timing. |
| `build/experiments/h047/{budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete cadence, fidelity, and smoke battery | All gates pass; exact click WAVs match H044. |
| `build/experiments/h048/wave_context_{probe.sv,proof.py}` | source-exact selector proof and formal/synthesis source | All legal hardware/PREVIEW contexts and generated control words pass. |
| `build/experiments/h048/{proof,formal}.log` | exhaustive schedule audit and constrained Yosys SAT | Selector axes and arbitrary valid-input outputs prove equivalent. |
| `build/experiments/h048/isolated-{baseline,candidate}.log` | registered selector `synth_ice40` comparison | Candidate adds 16 LUT4s with carry/FF counts unchanged. |
| `build/experiments/h049/square_threshold_{probe.sv,proof.py}` | exhaustive/formal source and registered synthesis probe | All 1,048,576 tuples and the complete signed output agree. |
| `build/experiments/h049/{exhaustive,formal}.log` | exhaustive enumeration and unconstrained Yosys SAT | Exact threshold relations pass. |
| `build/experiments/h049/isolated-{baseline,candidate}.log` | registered constant-output `synth_ice40` comparison | Candidate trades two LUT4s for five carries locally. |
| `build/experiments/h049/candidate.{synth,pnr}.log` | canonical whole-PSG mapping and bounded seed-1 placement/route | LUT/floor/placed area regress; route stopped at two overused wires. |
| `build/experiments/h049/candidate.census.log` | mapped flop-packing census | 6,529 LUT4, 520 unpackable, 7,049-cell floor. |
| `build/experiments/h050/upload_page_{probe.sv,proof.py}` | exhaustive/formal source and registered synthesis probe | All-page and valid-domain index identities pass. |
| `build/experiments/h050/{exhaustive,formal,formal-valid}.log` | exhaustive enumeration and Yosys SAT | Both exact domains prove. |
| `build/experiments/h050/isolated-{baseline,candidate-v1,candidate-v2}.log` | registered 13-bit index synthesis | Variant 2 removes three carries with LUT4/FF counts unchanged. |
| `build/experiments/h050/candidate-v1.{synth,pnr}.log` | canonical whole-PSG synthesis with all-page Boolean outputs | LUT/floor/placed area regress; rejected. |
| `build/experiments/h050/candidate-v2.{synth,pnr}.log` | canonical synthesis with valid-domain fifth bit | Smaller regression, but still fails LUT/floor/placement. |
| `build/experiments/h050/candidate-v{1,2}.census.log` | mapped flop-packing census | Exact mapped floors for both rejected variants. |
| `build/experiments/h051/dq_count_{probe.sv,proof.py}` | constrained formal source and exhaustive state proof | The six reachable binary states map exactly to idle plus the five LFSR states. |
| `build/experiments/h051/{formal,isolated-baseline,isolated-candidate,test-psg-dq}.log` | constrained SAT, isolated synthesis, and exhaustive service tests | Public state/product behavior is exact and the complete service removes one carry. |
| `build/experiments/h051/candidate.{synth,pnr}.log` and `candidate.census.log` | forced canonical whole-PSG synthesis | 6,506 LUT4, 1,421 carries, 7,028-cell floor, 7,247 routed LCs, and passing timing. |
| `build/experiments/h051/{budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete cadence, fidelity, and smoke battery | All gates pass; exact click WAVs match H047. |
| `build/experiments/h052/fold_final_{probe.sv,proof.py}` | legal-state formal source and exhaustive controller proof | All operands, destinations, transitions, and publication events agree. |
| `build/experiments/h052/{formal,isolated-baseline,isolated-candidate}.log` | constrained SAT and complete-controller `synth_ice40` comparison | Candidate adds three LUT4s with mapped flops unchanged; rejected. |
| `build/experiments/h053/fold_publish_{probe.sv,proof.py}` | legal-state formal source and exhaustive controller proof | Full-mode busy and publication waveforms agree on every legal path. |
| `build/experiments/h053/{formal,isolated-baseline,isolated-candidate}.log` | constrained SAT and complete-controller `synth_ice40` comparison | Candidate removes one FF for five LUT4s locally. |
| `build/experiments/h053/candidate.{synth,pnr}.log` and `candidate.census.log` | forced canonical whole-PSG synthesis | LUT/floor/placement regress despite the one-FF saving; rejected. |
| `build/experiments/h054/triangle_fold_{probe.sv,proof.py}` | exact centered-triangle identity, registered consumers, and exhaustive proof | All 65,536 phases and unconstrained SAT pass. |
| `build/experiments/h054/isolated-{baseline,candidate}.log` | registered primary triangle and `/4` consumer `synth_ice40` comparison | Candidate changes 60/45/34 LUT4/carry/FF to 71/44/34. |
| `build/experiments/h055/noise_round_{probe.sv,proof.py}` | exact signed product-rounding forms and exhaustive proof | All 262,144 cases and unconstrained SAT pass. |
| `build/experiments/h055/isolated-{baseline,candidate,candidate-shared}.log` | complete dual-sign registered consumer `synth_ice40` comparison | Inlining doubles carries; shared limbs save one LUT4 and expose two duplicate sign flops. |
| `/private/tmp/fpga-psg-area-direct-continuation/build/targets/psg.{json,pnr.log}` | forced direct-frontier H055 synthesis and seed-1 route | Map/floor improve, but route is stopped after 21,160 iterations fixed at two overused wires. |
| `build/experiments/h056/organ_hi_{probe.sv,proof.py}` and `formal.log` | exhaustive phase/bypass proof plus unconstrained Yosys SAT | All 131,072 cases and the arbitrary-input two-stage selector prove equivalent. |
| `build/experiments/h056/isolated-{baseline,candidate}.log` | complete two-stage organ branch synthesis | Candidate changes 81/15/38 LUT4/carry/FF to 81/15/37. |
| `build/experiments/h056/candidate.{synth,pnr}.log` and `candidate.census.log` | twice-forced canonical direct-frontier synthesis | 6,489 LUT4, 1,403 carries, 1,459 FF, 498 unpackable, floor 6,987, 7,224 routed LCs, and passing timing. |
| `build/experiments/h056/preview-*.log` | hardware/PREVIEW pitch checks at both clocks and masks 7/1/2/4 | All eight checks pass with 95% or 100% voiced-window agreement. |
| `build/experiments/h056/{recovery-*,click-*,celeste-smoke*}` | recovery, exact click renders, and five-frame smoke | Recovery passes, click WAVs are H051-byte-identical with zero clicks, and Celeste audio is active/nonconstant. |
| `build/experiments/h057/{formal,sequential,isolated-*,forms-*,hw-forms}.log` | exhaustive, SAT, isolated synthesis, and permanent forms | State reconstruction is exact; isolated mapping is +11 LUT4/-1 FF. |
| `build/experiments/h057/candidate{,-first}.{synth.log,pnr.log,json,asc}` | forced canonical HX8K synthesis | Both runs reproduce 6,466 LUT4 / 1,403 carry / 1,458 FF / floor 6,968 / 7,204 LCs and identical JSON/ASC. |
| `build/experiments/h057/{test-psg,bytecheck,budget-*,test-clocks,preview-*}.log` | complete structural, render, cadence, clock, and preview battery | All exact gates pass at the recorded demand and 95% preview agreement. |
| `build/experiments/h057/{recovery-*,click-*,celeste-smoke*}` | recovery, same-tool exact click renders, and five-frame smoke | Recovery passes, click WAVs are H056-byte-identical with zero clicks, and Celeste audio is active/nonconstant. |
| `build/experiments/h058/{state_replay_probe.sv,state-replay-formal.log}` | symbolic full/PREVIEW transition and hold-equivalence proof | Replay containment and baseline/candidate hold equality pass for all inputs. |
| `build/experiments/h058/candidate.{json,synth.log,pnr.log,census.log}` | canonical H057-based mapping and seed-1 route attempt | Candidate maps at 6,490 LUT4 / 1,408 carry / 1,457 FF / floor 6,989, places at 7,235 LCs, and remains unrouted at two overused wires through 55,386 iterations. |
| `build/experiments/h059/{organ_h_probe.sv,organ_h_proof.py,exhaustive.log,formal.log}` | exhaustive 524,288-case proof plus unconstrained Yosys SAT | Exact full and partial reconstruction of the organ quotient byte from registered `z_lin_r`. |
| `build/experiments/h059/isolated-{baseline,candidate,candidate-partial}.log` | complete registered organ reciprocal consumer synthesis | Full/partial reconstruction retire eight/two FF and 15 carries, but each adds one LUT4 locally. |
| `build/experiments/h059/candidate-{full,partial}.{json,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG mapping and seed-1 route | Both variants regress deterministic area; full routes at 7,229 LCs and partial remains at two overused wires after 7,255 iterations. |
| `build/experiments/h060/{tri4_probe.sv,tri4_proof.py,exhaustive.log,formal.log}` | exhaustive 262,144-case proof plus three-step sequential Yosys SAT | Exact reconstruction of the alternate-triangle `/4` payload from registered `z_lin_r`. |
| `build/experiments/h060/isolated-{baseline,candidate}.{json,log}` | complete registered alternate-triangle consumer synthesis | Candidate is equal in LUT4s, +1 carry, -16 FF, and -2 floor cells locally. |
| `build/experiments/h060/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +54 LUT4, +1 carry, -16 FF, +50 floor, and +53 routed LCs with both clocks passing. |
| `build/experiments/h061/{fade_state_probe.sv,fade_state_proof.py,exhaustive.log,formal.log}` | exhaustive 4,202,496-transition proof plus symbolic Yosys SAT | Active, fresh fade-out, completion, idle, and command-interruption state all preserve gain and stop behavior. |
| `build/experiments/h061/isolated-{baseline,candidate}.{json,log}` | complete registered fade-state consumer synthesis | Compression removes eight FF but adds eight LUT4s and six deterministic floor cells; rejected before production. |
| `build/experiments/h062/{old_noise_probe.sv,old_noise_proof.py,exhaustive.log,formal.log,sequential.log}` | exhaustive snapshot proof plus combinational and four-step sequential Yosys SAT | Same-edge old-tuple reconstruction is exact for all restart and retained-tuple cases. |
| `build/experiments/h062/isolated-{baseline,candidate}.{json,log}` | complete registered old-noise selector consumer synthesis | Candidate is -2 LUT4, -1 FF, and -2 floor cells locally. |
| `build/experiments/h062/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +55 LUT4, -1 FF, +53 floor, and +57 routed LCs with both clocks passing. |
| `build/experiments/h063/{old_sign_probe.sv,old_sign_proof.py,sequential.log}` | source assignment audit, 512 endpoint schedules, and 70-step arbitrary-stall Yosys SAT | The captured W15 old-arm sign equals the live W51 sign for every active built-in-wave consumer. |
| `build/experiments/h063/isolated-{baseline,candidate}.{json,log}` | complete old-arm sign consumer synthesis | Candidate keeps 47 LUT4/15 carry and removes one FF locally. |
| `build/experiments/h063/{baseline-current,candidate}.{json,synth.log,census.log}` and `candidate.{asc,pnr.log}` | same-current-Yosys mapped comparison plus canonical seed-1 candidate route | Candidate is +64 LUT4, +4 carry, -1 FF, +62 floor, and +69 routed LCs with both clocks passing. |
| `build/experiments/h064/{noise_draw_probe.sv,noise_draw_proof.py,formal.log}` | NumPy-exhaustive 524,288-case proof plus combinational Yosys SAT | Selected-source adjacent-XOR draw and both individual signs are exact. |
| `build/experiments/h064/isolated-{baseline,candidate}.{json,log}` | complete registered noise request/sign consumer synthesis | Candidate is -2 LUT4 with carries and FF unchanged. |
| `build/experiments/h064/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +55 LUT4, +4 carry, +54 floor, and +63 routed LCs with both clocks passing. |
| `build/experiments/h065/{sample_width_probe.sv,sample_width_proof.py,formal.log}` | exact range proof over all built-in/composed values and 67,108,864 custom-wave tuples plus Yosys SAT | Every stored sample fits signed 16 bits and every widened consumer is equivalent. |
| `build/experiments/h065/isolated-{baseline,candidate}.{json,log}` | complete registered sample-boundary synthesis | Candidate is -3 LUT4, -1 carry, and -4 FF locally. |
| `build/experiments/h065/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +27 LUT4, -4 carry, -4 FF, +27 floor, and +32 routed LCs with both clocks passing. |
| `build/experiments/h066/{tail_sentinel_probe.sv,tail_sentinel_proof.py,exhaustive.log,formal.log}` | exhaustive 1,048,576-case range/selection proof plus SAT induction | Live payloads are at most 105 and the reserved 127 sentinel preserves every tail choice. |
| `build/experiments/h066/isolated-{baseline,candidate}.{json,log}` | complete registered reciprocal-tail consumer synthesis | Candidate is +6 LUT4 and -1 FF with carries unchanged. |
| `build/experiments/h066/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +42 LUT4, +4 carry, -1 FF, +40 floor, +47 routed LCs, and fails fast timing. |
| `build/experiments/h067/{tilt_prefix_probe.sv,tilt_prefix_proof.py,exhaustive.log,formal.log}` | exhaustive 524,288-value slice proof plus SAT induction | Both registered quotient views reconstruct exactly from one four-bit prefix and `t_pre_r`. |
| `build/experiments/h067/isolated-{baseline,candidate}.{json,log}` | complete registered quotient consumer synthesis | Both forms map identically at 19 LUT4s and 29 FF. |
| `build/experiments/h068/{dq_hold_probe.sv,dq_hold_proof.py,exhaustive.log,formal.log}` | 57,344-case global-NumPy transaction proof plus terminal/idle SAT relation | The held pre-terminal recurrence preserves valid results under the walker's stable-operand lifetime. |
| `build/experiments/h068/isolated-{baseline,candidate}.{json,log}` | complete DQ-service synthesis | Candidate is -6 LUT4 with carries/flops unchanged. |
| `build/experiments/h068/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is -9 LUT4, +1 carry, +12 unpackable FF, +3 floor, and +6 routed LCs. |
| `build/experiments/h069/{tzs_probe.sv,tzs_proof.py,exhaustive.log,formal.log}` | exhaustive 1,048,576-case global-NumPy proof plus Yosys SAT | Arithmetic shift plus negative nonzero-remainder correction is exact for every signed18 value and shift 0..3. |
| `build/experiments/h069/isolated-{baseline,candidate}.{json,log}` | complete five-consumer shared-helper synthesis | Candidate is -30 LUT4 and -40 carries. |
| `build/experiments/h069/candidate{,-first}.{json,asc,synth.log,pnr.log,census.log}` | two canonical forced H057-based whole-PSG builds | Both builds are byte-identical at -10 LUT4, -33 carry, +1 FF, +1 unpackable, -9 floor, and -5 routed LCs. |
| `build/experiments/h069/{test-psg.log,bytecheck.log,budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete H057 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; hardware/PREVIEW SFX-10 WAVs are byte-identical to H057. |
| `build/experiments/h070/{div_count_probe.sv,div_count_proof.py,exhaustive.log,formal.log}` | 50-transition exhaustive proof plus complete next-state SAT relation | The 24-state token preserves busy, load, arithmetic-step, quotient, and remainder timing exactly. |
| `build/experiments/h070/isolated-{baseline,candidate}.log` | complete restoring-divider synthesis | Candidate is -1 LUT4 and -3 carries with flops unchanged. |
| `build/experiments/h070/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H069-based whole-PSG synthesis and seed-1 route | Candidate is +23 LUT4, -7 carry, +23 floor, and +17 routed LCs with both clocks passing. |
| `build/experiments/h071/{blend_round_probe.sv,blend_round_proof.py,exhaustive.log,formal.log}` | exhaustive signed-24 proof plus complete registered-consumer equivalence | All 16,777,216 values and 83 formal points pass. |
| `build/experiments/h071/isolated-{baseline,candidate}.log` | complete registered blend-consumer synthesis | Candidate is -8 LUT4 and -6 carries with flops unchanged. |
| `build/experiments/h071/candidate{,-v2}.{json,synth.log,census.log}` | two canonical H069-based whole-PSG mappings | Both regress LUT4s and deterministic floor, so neither is routed. |
| `build/experiments/h072/{dampen_round_probe.sv,dampen_round_proof.py,exhaustive.log,formal.log}` | exhaustive signed-19/mode proof plus complete registered-consumer equivalence | All 1,572,864 tuples and 89 formal points pass. |
| `build/experiments/h072/isolated-{baseline,candidate}.log` | complete registered dampen-consumer synthesis | LUT4/FF identical; candidate removes two carries. |
| `build/experiments/h072/candidate.{json,synth.log,census.log}` | canonical H069-based whole-PSG mapping | Candidate is +26 LUT4, -5 carry, and +24 floor cells, so it is not routed. |
| `build/experiments/h073/{noise_offset_probe.sv,noise_offset_proof.py,exhaustive.log,formal.log}` | exhaustive 13-bit proof plus complete registered-consumer equivalence | All 8,192 inputs and 42 formal points pass. |
| `build/experiments/h073/isolated-{baseline,candidate}.log` | complete registered noise-request operand synthesis | Both forms map identically at 11 LUT4/10 carry/14 FF. |
| `build/experiments/h074/{slide_carry_proof.py,exhaustive.log}` | complete reachable-domain affine-slide precision check | Refuted at pitch 2/fraction 9,668 before synthesis. |
| `build/experiments/h075/{wavetable_sign_probe.sv,wavetable_sign_proof.py,formal.log,forms.log}` | exhaustive 1,048,576-tuple proof, 35-point Yosys equivalence, and permanent forms | Operand inversion plus sign carry-in exactly replaces conditional negation before the base add. |
| `build/experiments/h075/isolated-{baseline,candidate}.log` | complete registered wavetable consumer synthesis | Candidate is -25 LUT4 and -8 carries with 17 flops unchanged. |
| `build/experiments/h075/candidate{,-second}.{json,asc,synth.log,pnr.log}` | two canonical forced H069-based whole-PSG builds | Both builds are bit-identical at -23 LUT4, -8 carry, -2 unpackable FF, -25 floor, and -26 routed LCs. |
| `build/experiments/h075/{test-psg.log,bytecheck.log,budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete H069 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; same-tool H069/H075 SFX-10 PREVIEW and hardware WAVs are byte-identical. |
| `build/experiments/h076/{tilt_affine_proof.py,exhaustive.log}` | exhaustive actual-domain affine proof | Both branches match for all 131,072 mode/phase tuples and the first limb fits unsigned17. |
| `build/experiments/h076/{tilt_affine_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered tilt-consumer synthesis | Candidate is -12 LUT4 and -1 carry with 28 flops unchanged. |
| `build/experiments/h076/candidate.{json,synth.log,census.log}` | canonical H075-based whole-PSG mapping | Candidate is +5 LUT4, -1 carry, +1 unpackable FF, and +6 floor cells, so it is not routed. |
| `build/experiments/h077/{tilt_index_proof.py,exhaustive.log}` | exhaustive selected-index/address proof | All 1,048,576 mode/source tuples match, including native-width wrap. |
| `build/experiments/h077/{tilt_index_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered tilt-consumer synthesis | Both forms map identically at 129 LUT4, 69 carry, and 28 FF. |
| `build/experiments/h078/{soft_add_threshold_proof.py,exhaustive.log}` | exhaustive registered-sum and quotient proof | Legal signed-16 fold domain and controller cycles match; the illegal wrapped tail is recorded explicitly. |
| `build/experiments/h078/{soft_add_threshold_formal.sv,formal.log}` | SAT over arbitrary signed-16 operand pairs | All 2^32 operand pairs prove the registered threshold join. |
| `build/experiments/h078/{soft_add_fold_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered fold-engine synthesis | Candidate is +6 LUT4 with 25 carry, 66 FF, and one EBR unchanged. |
| `build/experiments/h079/{reverb_round_proof.py,exhaustive.log,reverb_round_formal.sv,formal.log}` | exhaustive and SAT dual-comb identity proof | All signed19 accumulator values and both complete input tuples match. |
| `build/experiments/h079/{reverb_round_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered dual-comb/blend consumer | Candidate is -2 carry with 139 LUT4 and 52 FF unchanged. |
| `build/experiments/h079/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H075-based whole-PSG synthesis and seed-1 route | 6465 LUT4 / 1358 carry / 1459 FF / 501 unpackable / floor6966 / 7198 LCs, 118.06/31.24 MHz. |
| `build/experiments/h080/{timing_update_proof.py,timing_update_formal.sv,formal.log,forms-final.log}` | all-state exhaustive proof, SAT equivalence, and permanent forms | The sign-selected delta exactly reproduces both recurrence arms. |
| `build/experiments/h080/isolated-{baseline,candidate}.log` | complete registered `psg_timing` synthesis | Candidate is -41 LUT4 and -23 carries with flops unchanged. |
| `build/experiments/h080/candidate{,-second}.{json,asc}` and `{candidate,repro}.{synth,pnr}.log` | two canonical forced H075-based whole-PSG builds | Both builds are bit-identical at -24 LUT4, -23 carry, -24 floor, and -26 routed LCs. |
| `build/experiments/h080/{click-*,celeste-smoke*,celeste-audio.*}` plus completed gate output | complete H075 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; clean same-tool H075/H080 SFX-10 PREVIEW WAVs are byte-identical. |
| `build/experiments/h081/{slide_adder_formal.sv,formal.log,slide_adder_probe.sv,isolated-*.log}` | all-domain SAT proof and complete registered slide-consumer synthesis | Exact, but +20 LUT4/floor cells despite -25 carries; rejected before production. |
| `build/experiments/h082/{slide_storage_formal.sv,formal.log,slide_storage_probe.sv,isolated-*}` | all-domain lifetime proof and complete registered slide-consumer synthesis | Exact; isolated -18 FF but +20 LUT4 and +1 floor. |
| `build/experiments/h082/candidate.{json,asc,synth.log,pnr.log}` | canonical H080-based whole-PSG build | -18 FF/-4 carry but +28 LUT4/+10 floor; rejected and reverted. |
| `build/experiments/h083/{gain_chain_proof.py,exhaustive.log,gain_chain_formal.sv,formal.log,gain_chain_probe.sv,isolated-*.log}` | exhaustive/SAT proof and complete registered live-gain synthesis | Exact, but +21 LUT4/floor cells for -3 carries; rejected before production. |
| `build/experiments/h084/{scnt_token_proof.py,sequence.log,scnt_token_probe.sv,scnt_token_tb.sv,cadence.log,isolated-*.log}` | maximal-sequence/cadence proof and complete registered timing synthesis | Exact and locally -2 LUT4/-6 carries. |
| `build/experiments/h084/candidate.{json,asc,synth.log,pnr.log}` | canonical H080-based whole-PSG build | +26 LUT4/+6 unpackable/+32 floor/+28 route; rejected and reverted. |
| `build/experiments/h085/{div_round_proof.py,exhaustive.log,div_round_formal.sv,formal.log,div_round_probe.sv,div_round*_tb.sv,transactions*.log,isolated-*}` | exhaustive/SAT/transaction proofs and two complete divider/caller synthesis variants | Both exact; v1 floor +10, terminal v2 floor +33; rejected before production. |
| `build/experiments/h086/{row_inc_proof.py,row_inc_formal.sv,exhaustive.log,formal.log,isolated-*}` | exhaustive/SAT proof and complete paired EA5 consumer synthesis | Exact; isolated -1 LUT4/-3 carries with flops unchanged. |
| `build/experiments/h086/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H080-based whole-PSG synthesis and seed-1 route | +7 LUT4/-7 carries/+1 unpackable/+8 floor/-5 route; rejected and reverted. |
| `build/experiments/h087/{vibrato_decode_proof.py,vibrato_decode_formal.sv,exhaustive.log,formal.log,vibrato_decode_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered vibrato-consumer synthesis | Exact, but candidate is +1 LUT4 with carries/flops unchanged. |
| `build/experiments/h088/{timing_strobe_proof.py,timing_strobe_formal.sv,exhaustive.log,formal.log,timing_strobe_probe.sv,isolated-*}` | reachable-state/SAT proof and complete timing-consumer synthesis | Exact; candidate -2 FF/-1 unpackable but +3 LUT4/+2 floor. |
| `build/experiments/h089/{pitch_select_proof.py,pitch_select_formal.sv,exhaustive.log,formal.log}` | exhaustive selected-pitch proof and unconstrained SAT equivalence | All 2,097,152 operand/control tuples and 512 state/effect selections pass. |
| `build/experiments/h089/isolated-{baseline,candidate}.log` | complete registered pitch-address and slide-consumer synthesis | Candidate is -43 LUT4 and -12 carries with 19 flops unchanged. |
| `build/experiments/h089/candidate{,-second}.{json,asc,synth.log,pnr.log}` | two canonical forced H080-based whole-PSG builds | Both are bit-identical at -63 LUT4, -15 carry, -60 floor, and -74 routed LCs. |
| `build/experiments/h089/{preview-*,recovery-*,click-*,celeste-smoke*}` plus completed gate output | complete H080 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; 59/59 renders are byte-exact and both SFX-10 paths have zero clicks. |
| `build/experiments/h090/{step_count_proof.py,step_count_formal.sv,exhaustive.log,formal.log,step_count_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered count-load/countdown synthesis | Exact for both radix forms, but production-radix candidate is +1 LUT4 with carry/FF unchanged. |
| `build/experiments/h091/{remaining_counter_refutation.py,refutation.log}` | reachable pending-trigger counterexample | Target 8,160 diverges on the first trigger-free tick after the 13-bit elapsed counter wraps. |
| `build/experiments/h092/{predicate_lifetime_proof.py,predicate_lifetime_formal.sv,exhaustive.log,formal.log,predicate_lifetime_probe.sv,isolated-*,candidate.*}` | exhaustive/SAT proof, complete isolated synthesis, and canonical whole-PSG synthesis | Exact and -1 LUT4/-1 FF alone, but globally +20 LUT4/+3 carries/+20 floor cells. |
| `build/experiments/h093/{dq_coeff_proof.py,dq_coeff_formal.sv,exhaustive.log,formal.log,dq_coeff_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered DQ service synthesis | Exact, but the grouped table adds three LUT4s with carry/FF unchanged. |
| `build/experiments/h094/{transition_tuple_proof.py,transition_tuple_formal.sv,exhaustive.log,formal.log,transition_tuple_probe.sv,isolated-*,candidate.*}` | structural/SAT proof, complete isolated synthesis, and canonical whole-PSG synthesis | Exact and -1 LUT4 alone, but globally +3 LUT4/+3 floor cells. |
| `build/experiments/h095/{forms*,equiv.log,isolated-*,candidate*,cadence-*,preview-*,recovery-*,click-*,celeste-smoke*}` | exhaustive/formal proof, isolated and two forced whole-PSG builds, and complete acceptance battery | Accepted direct composition at -4 LUT4/-3 carries/-4 floor cells; all fidelity, timing, and reproducibility gates pass. |
| `build/experiments/h096/{budget-*,preview-*,recovery*,clicks*,celeste-smoke*,clocks*,bytecheck*}` plus `build/targets/psg.{json,asc}` | exhaustive protocol proof, two forced whole-PSG builds, and complete merged-main acceptance battery | Accepted `a647185` at -31 LUT4/-1 FF/-28 floor cells; all generic fidelity, timing, and reproducibility gates pass. |
| `build/integration-h096-r84/` | deterministic A/B v4 source certificates plus unchanged R.84 artifacts and independent structural/value audits | I002 accepted at source SHA-256 `2af2c61f...`; nine mutations convicted and both 192,896-pair value audits pass. |
| `build/integration-h102-r84/` | deterministic A/B v5 source certificates plus unchanged R.84 artifacts and independent structural/value audits | I003 accepted at source SHA-256 `d54dde5d...`; thirteen mutations convicted and both 192,896-pair value audits pass. |
| `build/experiments/h097/{provenance_proof.py,provenance-proof.log,provenance_probe.sv,isolated-*,candidate.*}` | exact path proof, complete isolated provenance synthesis, and canonical whole-PSG synthesis | Exact and -3 LUT4/-1 FF alone, but globally +18 LUT4/+4 carries/+17 floor cells/+20 routed LCs. |
| `build/experiments/h098/{count_proof.py,count-proof.log,count_probe.sv,count_*_r1.*,mulmp.log,candidate.*}` | exact token/freeze proof, isolated count synthesis, 6,020-transaction CDC bench, and canonical whole-PSG synthesis | Exact and -4 LUT4/-2 carries alone, but globally +20 LUT4/+19 floor cells/+16 routed LCs. |
| `build/experiments/h099/{filter_owner_proof.py,filter-owner-proof.log,filter_owner_probe.sv,filter_owner_*.json,filter_owner_*.log,candidate*}` | exhaustive ownership proof, complete isolated registered-consumer synthesis, and two canonical whole-PSG variants | Exact across 4,224 legal paths and -17 LUT4 alone, but both whole-PSG variants regress deterministic floor and seed-1 placement. |
| `build/experiments/h100/{released_domain_proof.py,released-domain-proof.log,released_domain_probe.sv,isolated-*-v2.*}` | exhaustive transition proof, source-matched release-array synthesis, and explicit foreground-only synthesis | Exact across 2,560 transition/consumer cases; both forms map identically at 17 LUT4s/four FF. |
| `build/experiments/h101/{trigger_pending_probe.sv,isolated-*,write_read_counterexample.py,write-read-counterexample.log}` | complete source/one-EBR/two-EBR storage synthesis and exact write/read timing counterexample | Plain EBR floor is smaller but stale for one cycle; exact forwarding raises the 97-cell reference floor to 107/104 cells. |
| `build/experiments/h102/{bass_fx_proof.py,bass-fx-proof.log,bass_fx_probe.sv,isolated-*,candidate*,forms*,test-psg.log,bytecheck.log,budget-*,preview-*,recovery.log,clicks*,celeste-*}` plus `build/targets/psg.{json,asc}` | exhaustive mode/store/reload proof, isolated synthesis, two forced whole-PSG builds, and complete H096 acceptance battery | Accepted `ccfb2a0` at -4 LUT4/-1 FF/-1 unpackable/-5 floor cells; all fidelity, timing, and reproducibility gates pass. |
| `build/experiments/h103/{first_launch_proof.py,first-launch-proof.log,first_launch_probe.sv,isolated-*}` | exhaustive first-launch ownership proof and complete registered pacing-consumer synthesis | Exact across all 256 launch/qualifier masks, but the candidate is +2 LUT4/-1 FF and fails the isolated gate. |
| `build/experiments/h104/{instrument_kind_proof.py,instrument_kind_probe.sv,isolated-*}` | exhaustive semantic/record/consumer proof and complete registered instrument-kind synthesis | Exact across 53,254 checks, but the candidate is +1 LUT4 with eight carries/two FF unchanged. |
| `build/experiments/h105/{vcnt_width_proof.py,vcnt_width_probe.sv,isolated-*}` | exhaustive transfer/hold/address proof and complete registered counter consumer synthesis | Exact across 960 checks and -1 FF/-2 carries, but the candidate adds 24 LUT4s and fails the isolated gate. |
| `build/experiments/h106/{wraddr_advance_proof.py,wraddr_advance_probe.sv,isolated-*,candidate*}` | exhaustive upload/read pointer proof, complete registered-consumer synthesis, ARAM hold/readback checks, and forced whole-PSG synthesis | Exact across 6,291,456 transitions and -2 LUT4 alone, but the candidate is +51 LUT4/+52 floor/+54 routed LCs globally. |
| `build/experiments/h107/candidate*` | forced whole-PSG synthesis of direct packed playback-state storage | Source-exact alias removal and -6 unpackable FF, but +79 LUT4/+2 carry/+73 floor/+79 routed LCs globally. |
| `build/experiments/h108/candidate*` | forced whole-PSG synthesis of the `REVERB=0` restart specialization | Enabled-reverb source remains unchanged, but the HX8K candidate is +39 LUT4/+4 carry/+1 unpackable/+40 floor/+47 routed LCs. |
| `build/experiments/h109/{candidate.json,candidate.synth.log,candidate.pnr.log}` | forced one-hot sequencer mapping and bounded canonical seed-1 route | -6 LUT4/-5 unpackable/-11 floor and -3 placed LCs, but +57 FF/+4 carries and one unresolved wire through 29,349 router2 iterations. |
| `build/experiments/h110/{join_stage_proof.py,join_stage_probe.sv}` | reachable reduced-controller proof and unrun synthesis probe | Refuted by same-edge bank publication plus join-pass start before production RTL or synthesis. |
| `build/experiments/h111/{readback_pending_proof.py,readback_pending_probe.sv,isolated-*}` | exhaustive bit/control proof and complete registered readback synthesis | Exact across 128 transitions; both forms map identically at 14 LUT4s/nine flops. |
| `build/experiments/h112/{trigger_meta_proof.py,trigger_meta_probe.sv,isolated-*}` | exhaustive field/priority proof and complete registered dynamic-index synthesis | Exact across 6,291,456 transitions; both forms map identically at 61 LUT4s/44 flops. |
| `build/experiments/h113/{merge_capture_proof.sv,capture-proof.log,baseline.*,candidate.*}` | all-domain SAT proof, source-contract audit, full/PREVIEW lint, and canonical forced whole-PSG synthesis/route | Transaction-exact, but the candidate is +66 LUT4/+4 carry/+66 floor/+73 routed LCs and is rejected. |
| `build/experiments/h114/{div_out_proof.py,div_out_formal.sv,formal.log,baseline.*,candidate.*}` | 65,536-case exhaustive proof, all-domain SAT proof, full/PREVIEW lint, and canonical forced whole-PSG synthesis/route | Exact signed-16-bit range, but +27 LUT4/+4 carry/+25 floor/+28 routed LCs globally. |
| `build/experiments/h115/{filter_max_proof.py,filter_max_probe.sv,isolated-*}` | complete decoder-domain proof, exhaustive bounded-max proof, and isolated three-field registered-consumer synthesis | Exact over levels 0..2; both forms map identically at six LUT4s/six flops. |
| `build/experiments/h116/{filter_bank_proof.py,candidate*,candidate-v2*}` | exhaustive bank-lifetime/replay proof, full/PREVIEW lint, and two canonical forced whole-PSG builds | Exact and -8 FF, but variants add 20/51 LUT4s, 21/52 floor cells, and 30/53 routed LCs. |
| `build/experiments/h117/{reset_dominance_proof.py,candidate*,candidate-v2*}` | exhaustive validity/reset proof, source-gate audit, full/PREVIEW lint, and two canonical forced whole-PSG builds | Exact with unchanged state count, but variants add 34/56 LUT4s, 40/56 floor cells, and 44/64 routed LCs. |
| `build/experiments/h118/{volume_width_proof.py,candidate*,candidate-v2*}` | 2,707,216-case range proof, full/PREVIEW lint, and two canonical forced whole-PSG builds | Exact and -1 FF, but variants add 35/60 LUT4s, 35/57 floor cells, and 41/66 routed LCs. |
| `build/experiments/h119/{pph_width_proof.py,candidate*}` | 79,040 schedule/transition checks, all three lint modes, and canonical forced whole-PSG synthesis/route | Exact and -1 FF/-5 carries, but +35 LUT4s, +34 floor cells, and +32 routed LCs. |
| `build/experiments/h120/{fade_reset_proof.py,fade_reset_probe.sv,formal.log,isolated-*,sources-probe.json}` | inductive validity proof, reset-bounded SAT miter, complete registered-consumer synthesis, and fresh v5 source audit | Exact, but reset removal adds one isolated LUT4 with 41 FFs, 13 unpackable flops, and all carries unchanged. |
| `build/experiments/h121/{seq_credit_proof.py,seq_credit_probe.sv,formal.log,isolated-*,candidate*}` | all-state transition proof, reset-bounded SAT miter, complete limiter synthesis, full/PREVIEW lint, and canonical whole-PSG mapping | Exact and -2 floor cells locally, but +13 LUT4/+5 carry/+9 floor cells globally; production reverted. |
| `build/experiments/h122/cpz_counterexample.py` | reachable K_ADV-to-PC3 control interleaving | Refutes live-state reconstruction when a CPU stop lands during the copy chain; no RTL changed. |
| `build/experiments/h123/bank_history_counterexample.py` | exhaustive same-edge publication and dropped-PREVIEW history model | Refutes a live bank delta before RTL: same-edge flips move restart early and dropped starts leave stale history. |
| `build/experiments/h124/{packed_clear_proof.py,packed_clear_probe.sv,formal.log,isolated-*,candidate*}` | complete legal-domain proof, SAT, registered-consumer synthesis, full/PREVIEW lint, and two forced whole-PSG maps | Exact and locally -29 LUT4/-1 carry/-1 FF, but both global spellings are +39 LUT4/+2 carry/+39 floor; production reverted. |
| `build/experiments/h125/{packed_noiz_proof.py,packed_noiz_probe.sv,formal.log,isolated-*,candidate*}` | split-load proof, SAT, registered-consumer synthesis, full/PREVIEW lint, and forced whole-PSG mapping | Exact and locally -31 LUT4/-1 carry/-1 FF, but globally +45 LUT4/+2 carry/+45 floor; production reverted. |
| `build/experiments/h126/ctrl_displaced_counterexample.py` | exhaustive three-schedule edge-order and adjacent `$22/$20` model | Refutes `crom_replay && prun` before RTL: a same-edge walk start invents a replay stall and shifts control prefetch by one phase. |
| `build/experiments/h127/{phaser_threshold_proof.py,phaser_threshold_probe.sv,formal*,isolated-*}` | exhaustive/SAT proof and two complete registered phaser-decoder maps | Both candidates are exact; Boolean sharing is +2 LUT4, direct comparison is -3 LUT4/+6 carry locally. |
| `build/experiments/h127/candidate-v2.{json,synth.log}` | canonical H102 whole-PSG map of the direct selected comparator | Candidate is +50 LUT4/-1 unpackable/+49 floor cells with carry/FF/EBR counts unchanged; production reverted and no route ran. |
| `build/experiments/h128/{write_qualifier_probe.sv,write_qualifier_proof.py,exhaustive.log,formal.log,isolated-*}` | exhaustive/SAT proof and complete registered event-decoder synthesis | All 2,048 tuples and SAT pass; baseline/candidate are mapping-identical at 9 LUT4s/4 packed FF. |
| `build/experiments/h129/{sfx_partition_probe.sv,sfx_partition_proof.py,exhaustive.log,formal.log,isolated-*}` | control/index proof, arbitrary-state SAT, and complete registered storage/read synthesis | Exact, but candidate retains 48 unpackable FFs and grows 76 -> 86 LUT4s. |
| `build/experiments/h130/{status_select_probe.sv,status_select_proof.py,exhaustive.log,formal.log,isolated-*}` | control/index proof, arbitrary-payload SAT, and complete registered readback synthesis | Exact, but direct selection grows 61 -> 63 LUT4s with seven packed FF in both. |
| `build/experiments/h131/{aud_row_owner_probe.sv,aud_row_owner_proof.py,exhaustive.log,formal.log,isolated-*}` | exhaustive ownership proof, arbitrary-state SAT, and complete row-writer synthesis | Exact and mapping-identical at 18 LUT4s/20 unpackable FF. |
| `build/experiments/h132/{tail_token_proof.py,tail_token_formal.sv,wave_consumer_probe.sv,exhaustive.log,formal-*,isolated-*}` | all-context exhaustive proof, address and registered-token SAT, and complete registered waveform-consumer synthesis | Exact with one EBR in both forms, but -1 carry/-1 FF changes 696 -> 701 LUT4s and worsens the floor 762 -> 766 cells. |
| `build/experiments/h133/{tail_plane_proof.py,tail_plane_formal.sv,wave_consumer_probe.sv,exhaustive.log,formal-*,isolated-*}` | all-context high-half-plane proof, address and registered-token SAT, and complete registered waveform-consumer synthesis | Exact with one EBR in both forms, but -1 carry/-1 FF changes 696 -> 699 LUT4s and worsens the floor 762 -> 764 cells. |
| `build/experiments/h134/{wavetable_byte_proof.py,wavetable_byte_probe.sv,exhaustive.log,formal.log,lint-*,isolated-*,candidate*,postalias2*}` plus completed acceptance output and `clicks/`, `celeste-smoke.ppm` | source-bound exhaustive/SAT proof, complete registered-consumer synthesis, canonical map/route reproducibility and the full H102 fidelity/cadence/PREVIEW/recovery/click/smoke battery | Accepted: exact, -4 carries/-8 FF/-8 unpackable and floor cells, 7,086 routed LCs; final ASC is byte-identical after simulation-only trace aliases. |
| `build/experiments/h135/{sample_result_proof.py,sample_result_probe.sv,exhaustive.log,formal-*,isolated-*}` | exhaustive representation proof, two full-path nine-step SAT miters and complete registered-consumer synthesis | Exact and -17 FF/-18 unpackable locally, but +37 LUT4 worsens the isolated floor 77 -> 96 cells; production remains unchanged. |
| `build/experiments/h136/{sign_token_proof.py,sign_token_formal.sv,sign_token_probe.sv,exhaustive.log,formal-*,lint-*,isolated-*}` | exhaustive transaction/chaining proof, three SAT miters, lint and two complete isolated service/sign-consumer comparisons | Exact, but both isolated floors regress by one cell; the production-shaped form is +2 LUT4/-1 unpackable with carry/FF unchanged because two token flops replace two walker sign flops. |
| `build/experiments/h137/{fade_decode_proof.py,fade_decode_formal.sv,fade_decode_probe.sv,exhaustive.log,formal.log,lint-*,isolated-*,candidate*}` | source-bound table/command proof, SAT, complete registered-consumer synthesis, full/PREVIEW lint and canonical whole-PSG mapping | Exact and -8 floor cells alone, but globally +84 LUT4/+1 carry/-2 FF/-12 unpackable/+72 floor; production reverted and route/fidelity skipped. |
| `build/experiments/h138/{noise_width_proof.py,noise_width_formal.sv,noise_width_probe.sv,exhaustive.log,formal.log,lint-*,isolated-*,candidate*}` | source-derived range proof, SAT, complete registered-consumer synthesis, full/PREVIEW lint and canonical whole-PSG mapping | Exact and -6 floor cells alone, but globally +29 LUT4/-7 carries/-2 FF/-1 unpackable/+28 floor; production reverted and route/fidelity skipped. |
| `build/experiments/h139/{noise_scale_proof.py,noise_scale_formal.sv,noise_scale_probe.sv,formal.log,lint-*,isolated-*,candidate*,repro*}` plus complete acceptance logs, `clicks/`, and `celeste-smoke.ppm` | exhaustive/SAT proof, two registered-consumer probes, canonical map/route reproducibility and full H134 fidelity/cadence/PREVIEW/recovery/click/smoke battery | Accepted: -58 LUT4/-26 carry/-2 unpackable/-60 floor/-68 routed LCs, unchanged FF/EBR, exact renders and passing timing. |
| `build/experiments/h140/{noise_recurrence_proof.py,noise_recurrence_formal.sv,noise_recurrence_probe.sv,formal.log,isolated-*,candidate*}` | exhaustive clamp/selection proof, arbitrary-input SAT, complete registered-consumer synthesis, full/PREVIEW lint and canonical whole-PSG map/route | Exact and -8 LUT4/-17 carry/-5 floor cells alone, but globally +30 LUT4/+3 unpackable/+33 floor/+36 routed LCs; production reverted and fidelity skipped. |
| `build/experiments/h141/{fold_under_state_proof.py,fold_under_state_formal.sv,fold_under_state_probe.sv,formal.log,isolated-*,candidate*}` | exhaustive related-state proof, arbitrary-state SAT, complete registered fold-controller synthesis, full/PREVIEW lint and canonical whole-PSG map/route | Exact and -1 FF/-1 unpackable/floor cell alone, but globally +24 LUT4/+4 carry/+20 floor/+31 routed LCs; production reverted and fidelity skipped. |
| `build/experiments/h142/{old_noise_role_proof.py,old_noise_role_formal.sv,old_noise_role_probe.sv,formal.log,isolated-*}` | source-derived lifetime/range audit, exhaustive scale/role proof, arbitrary-state SAT and complete registered-consumer synthesis | Exact and -11 FF/-11 unpackable locally, but +17 LUT4 worsens the isolated floor 130 -> 136 cells; production remains unchanged. |
| `build/experiments/h143/{pcm_reset_proof.py,pcm_reset_probe.sv,formal.log,isolated-*}` | exhaustive bitwise transition proof, arbitrary-16-bit sequential SAT and complete registered output/parity-sink synthesis | Exact, but +2 LUT4/+1 FF/+1 unpackable worsens the isolated floor 22 -> 25 cells; production remains unchanged. |
| `build/experiments/h144/{aligned_offset_proof.py,aligned_offset_probe.sv,formal.log,isolated-*}` | exhaustive record/offset proof, arbitrary scheduled-address SAT and complete registered-consumer synthesis | Exact and mapping-identical at 38 LUT4/16 carry/13 packed FF; production remains unchanged. |
| `build/experiments/h145/*` | exhaustive/SAT arithmetic, scratch, fold, timing and complete-consumer evidence | Exact; -35 carries/-19 unpackable FFs, but +31 LUT4s worsens floor 434 -> 446. |
| `build/experiments/h146/*` | exhaustive/SAT DQ proof, focused service test, lint, isolated synthesis and canonical map/route | Exact and -13 LUT4/-11 carry alone, but globally +36 LUT4/+1 carry/+36 floor/+43 routed LCs. |
| `build/experiments/h147/*` | exhaustive/SAT gain bound/history proof, lint, isolated synthesis and canonical map/route | Exact and -5 LUT4/-2 FF alone, but globally +26 LUT4/+2 carry/+27 floor/+33 routed LCs with fast timing failure. |
| `build/experiments/h148/*` | 81,920-sequence fade/control proof, isolated port synthesis, full/PREVIEW lint and canonical map/route | Exact and -22 LUT4/-13 FF/-35 floor alone, but globally +19 LUT4/+4 carry/-13 FF/+5 floor/+13 routed LCs while spending EBR 15. |
| `build/experiments/h149/*` | 6,594,000-transition relation, 16,155 command traces, SAT, complete isolated port synthesis, full/PREVIEW lint and canonical map/route | Exact and -1 FF/-12 floor alone, but globally +58 LUT4/+5 carry/-1 FF/-11 unpackable/+47 floor/+58 routed LCs; production reverted. |
| `build/experiments/h150/*` | source-bound domain proof, 4,063,232 active arithmetic cases, 4,536 command cases, SAT and complete isolated fade-state synthesis | Exact and -1 FF/-1 unpackable, but +3 LUT4 worsens the isolated floor 92 -> 94; production unchanged. |
| `build/experiments/h151/*` | seven-class transaction proof, 30-cycle arbitrary-input SAT, complete provider/divider synthesis, full/PREVIEW lint and canonical map/route | Exact and -8 FF/-3 floor alone, but globally +31 LUT4/+4 carry/-8 FF/-6 unpackable/+25 floor/+32 routed LCs; production reverted. |
| `build/experiments/h152/*` | 10,089,360-case ownership proof, 1,024 hold/replay timelines, complete registered ownership synthesis, full/PREVIEW lint and forced canonical whole-PSG mapping | Exact and -5 LUT4/-8 FF/-5 floor alone, but globally +72 LUT4/+4 carries/-8 packed FF/+72 floor with unpackable FF and EBR counts unchanged; production reverted and route/fidelity skipped. |
| `build/experiments/h153/*` | 1,441,792 semantic note/copy cases, 245,760 hold/CPU-change timelines and complete registered note/copy consumer synthesis | Exact and -1 FF/-1 unpackable, but +1 LUT4 leaves the isolated floor unchanged at 33; production never changed. |
| `build/experiments/h154/*` | 5,952 payload classes, 53,568 signed transactions, 6,020 dual-clock service transactions, isolated synthesis, full/PREVIEW lint and forced candidate/restored canonical mapping | Exact and -3 FF/-6 unpackable/-2 floor alone, but globally +51 LUT4/-1 carry/-3 FF/+1 unpackable/+52 floor; production reverted, the restored map reproduces H139, and route/fidelity were skipped. |

## Handoff

- Area optimization is closed at accepted and R.84-bound H139. H155 remains a
  reserved, unstarted ID rather than the next task. The next goal is a
  behavior- and area-preserving source-clarity refactor; it must keep the H139
  physical, fidelity, cadence, render, PREVIEW, recovery, click and Celeste
  gates as its acceptance envelope. H149, H151, H152 and H154 improve their
  isolated floors but add 47, 25, 72 and 52 whole-PSG floor cells respectively;
  H150 and H153 fail their isolated floors. Do not retry any of them without
  its repeat-condition change.
- Blocked/rejected mechanisms: the Active DNR index above and all companion-
  owned R.84 work.
- `build/targets/psg.{json,synth.log}` now contains H154's forced restored H139
  map, while `build/targets/psg.{asc,pnr.log}` still contains the accepted H139
  route; use `build/experiments/h139/candidate.*` as the durable accepted
  physical baseline. I004's complete regenerated merge evidence is in
  `build/integration-h139-r84/` and reproduces those accepted JSON/ASC bytes.
- Verification still missing: none for accepted H001--H003, H005, or H007.
  H004 and H006 were rejected before production RTL; H005's timing-failing
  spelling remains rejected. H008 was rejected before production RTL. H009
  was rejected after exact proof and whole-PSG synthesis. H010 failed the same
  full-design gate; both RTL/proof patches are reverted and the delayed-tick
  representation family is closed unless its mapped context changes. H011 was
  rejected before production because its exact spelling maps identically.
  H012 CDC proofs pass, but its global map regresses and production RTL is
  reverted. H013's two width variants are exact but physically worse; all
  production/proof changes are reverted and the multiplier-width family closes.
  H014's correction bound is exact but mapping-identical; its production/proof
  patches are reverted and no behavior or physical gate remains.
  H015's output qualifier is exact but mapping-identical; its production/proof
  patches are reverted and no behavior or physical gate remains.
  H016's nine-bit restoring subtract is exact but globally worse; its
  production/proof patches are reverted and no behavior gate remains.
  H017's two context-sharing variants are exact but globally worse; all
  production/proof patches are reverted and the family closes.
  H018's shifted half-sum is exact but globally worse; its production/proof
  patches are reverted and no behavior gate remains.
  H019's whole-walk memory ownership is exact but both mapped forms are
  globally worse; all production/proof changes are reverted and the family
  closes.
  H020's redundant audio-RAM busy export is exact but globally worse; both
  production files are reverted and the family closes.
  H021's filter-code arithmetic is exact but locally larger than the current
  table in both measured forms; no production file changed and the family
  closes.
  H022's exact bounded pitch clamp passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. H023's exact slide-
  octave prefix predicates pass the same complete battery; no verification is
  missing for either accepted RTL/proof change. Because H023 changes
  `rtl/psg_seq.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H024's prefix row bounds are exact but globally worse; both production and
  permanent-proof changes are reverted and no behavior gate remains.
  H025's explicit shared fade sum is formally exact but mapping-identical; no
  production or permanent-proof file changed.
  H026's repaired rollover carry is exact but globally worse; production and
  permanent-proof changes are reverted and no behavior gate remains.
  H027's exact signed-prefix noise clamp passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_walk.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H028's exact arpeggio-speed prefix is globally worse; production and
  permanent-proof changes are reverted and no behavior gate remains.
  H029's exact affine noise-kick margin is globally placement-worse; production
  and permanent-proof changes are reverted and no behavior gate remains.
  H030's exact trigger-length prefix passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_seq.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H031's shared comparator passes the same complete battery and also changes
  `rtl/psg_seq.sv`; eventual integration has the same proof-regeneration and
  cadence/render obligation.
  H032's record-first audio address is formally exact and locally smaller but
  globally worse; production and permanent-proof edits are reverted and no
  behavior gate remains.
  H033's paired CPU activity bit is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed.
  H074's first affine-slide carry is required by a reachable exact boundary;
  no production or permanent-proof file changed.
  H034's standalone pattern-row prefix is exact and removes carries locally but
  regresses every whole-PSG area metric; production and permanent-proof edits
  are reverted and no behavior gate remains.
  H035's explicit nested detune suffixes are exact but mapping-identical in the
  complete registered consumer; no production or permanent-proof file changed.
  H036's preselected tilt quotient register is exact and locally smaller but
  globally adds LUT4s/flops and does not route promptly; production and
  permanent-proof edits are reverted and no behavior gate remains.
  H037's nine-bit live-mode `/7` register is exact but mapping-identical in the
  complete registered consumer; no production or permanent-proof file changed.
  H038's collapsed boosted-gain arithmetic is exact but adds 28 LUT4s in the
  complete registered consumer; no production or permanent-proof file changed.
  H039's aligned record-base transform passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  shared address logic in `rtl/psg_common.svh`, eventual integration with C2-C-C
  or R.84 must regenerate and rerun the live-value proof plus the complete
  cadence/render battery.
  H040's explicit organ fold is formally exact and locally smaller but globally
  worse; production and permanent-proof edits are reverted and no behavior
  gate remains.
  H041's shared fade-length prefix is exact and locally saves carries but adds
  LUT4s and placed LCs globally; production and permanent-proof edits are
  reverted and no behavior gate remains.
  H042's four-input triangle-residue truth table is exact and locally removes
  one LUT4 but adds LUT4s, carries, and LCs globally; production and permanent-
  proof edits are reverted and no behavior gate remains.
  H043's shared EA5 active/advance predicates are exact but mapping-identical in
  the complete registered consumer; no production or permanent-proof file
  changed.
  H044's terminal high-bit predicate passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_walk.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery. H044 is
  lineage-specific and regresses clean D004 `34340b7`; do not compose or
  cherry-pick it onto that lineage.
  H045's trit-max identity is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed.
  H046's normalized effect-class reuse is exact and locally smaller but adds
  LUT4s and placed LCs globally; production and permanent-proof edits are
  reverted and no behavior gate remains.
  H047's selected final waveform shift passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate on the H044-derived
  lineage. Because it changes `rtl/psg_wave.sv`, eventual integration with
  C2-C-C/R.84 must regenerate and rerun the live-value proof plus the complete
  cadence/render battery. Direct-D004 composition is independently accepted as
  `a5052c1`, with the 37-carry reduction durable and the 14-LC delta non-robust.
  H048's selector-axis factorization is exact but locally larger; no production
  or permanent-proof file changed.
  H049's exact square/pulse prefix formulas remove carries but regress the
  whole-PSG LUT, floor, and placed counts; production and permanent-proof edits
  are reverted, and the square/pulse-threshold family closes.
  H050's two exact upload-page transforms remove three carries locally and
  globally, but both regress LUT4s, floor, and placement; production and
  permanent-proof edits are reverted, and the transform family closes.
  H051's exact five-state service count passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_dqsvc.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H052's exact selector-state final token adds three LUT4s and removes no mapped
  flops in the complete isolated controller; no production or permanent-proof
  file changed, and the fold-final-selector family closes.
  H053's exact fold-state publication token removes one FF but adds 22 LUT4s,
  one carry, and 19 floor/routed cells globally; production and permanent-proof
  edits are reverted, and the fold-publish-state family closes.
  H054's exact centered primary-triangle fold saves one carry but adds eleven
  LUT4s in the complete isolated registered consumer; no production or
  permanent-proof file changed, and the centered-triangle-fold family closes.
  H055's duplicated unified signed-noise rounding doubles isolated carries;
  its shared-limb form removes 15 global LUT4s and 14 floor cells but does not
  complete the canonical seed-1 route. Both production and permanent-proof
  edits are reverted in the clean direct-continuation worktree, and the signed-
  noise-rounding family closes.
  H056's completed-linear-sample predicate passes every proof, physical,
  fidelity, timing, preview, recovery, click, and Celeste-smoke gate. Because
  it changes `rtl/psg_wave.sv`, eventual integration with C2-C-C/R.84 must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. No verification remains for direct commit `ac15778`.
  H057's same-edge registered-control predicate passes every proof, physical,
  fidelity, timing, preview, recovery, click, and Celeste-smoke gate. Because
  it changes `rtl/psg_wave.sv`, eventual integration with C2-C-C/R.84 must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. No verification remains for direct commit `c9274fc`.
  H058's replay-containment proof passes, but all physical area gates regress
  and seed 1 does not route; the scratch RTL is reverted byte-for-byte and the
  complete fidelity battery is intentionally skipped.
  H059's organ quotient reconstructions are exact but regress the whole-PSG
  map; H060's exact triangle payload reconstruction does the same. H061's fade
  compression is already larger in the complete isolated consumer. H062's
  old-noise flag and H063's old-arm sign lifetime proofs pass, but both one-FF
  retirements trigger decisive global LUT/floor/route regressions. H064's exact
  shared random-draw transform also saves locally and regresses globally.
  H065's exact sample-register contraction removes four mapped flops and
  carries but adds 27 LUT4s/floor cells and 32 routed LCs. H066's exact tail
  sentinel adds 42 LUT4s and fails fast timing. All eight direct-frontier RTL
  variants are reverted byte-for-byte; no fidelity gate or accepted area claim
  remains for H059--H066. H067 is exact but mapping-identical before production;
  no production or permanent-proof file changed. H069's exact shared `tzs`
  rewrite passes the complete battery and forced reproducibility check as
  direct commit `d3ce9a6`. Because it changes `rtl/psg_common.svh`, eventual
  C2-C-C/R.84 integration must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. H070's divider-count proof passes and its isolated service
  is smaller, but the whole-PSG floor and placement regress; production and
  permanent-proof edits are reverted byte-for-byte and no fidelity gate or
  accepted area claim remains. H071's blend-rounding identity passes exhaustive
  and formal proof and saves locally, but both global spellings regress the
  deterministic floor; production and permanent-proof edits are reverted
  byte-for-byte and no route/fidelity claim remains. H072's dampen-rounding
  identity passes exhaustive and formal proof and removes carries locally and
  globally, but adds 26 LUT4s and 24 floor cells; production and permanent-
  proof edits are reverted byte-for-byte and no route/fidelity claim remains.
  H073's aligned noise offset is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed. H075's
  wavetable sign fold passes every exactness, physical, fidelity, timing,
  preview, recovery, click, Celeste-smoke, and forced-reproducibility gate as
  direct commit `c634db2`. Because it changes `rtl/psg_walk.sv`, eventual
  C2-C-C/R.84 integration must regenerate and rerun the live-value proof plus
  the complete cadence/render/physical battery. H076's tilt-affine
  reassociation is exact and locally smaller but regresses the whole-PSG LUT,
  unpackable-flop, and floor counts; its production/permanent-proof edits are
  reverted byte-for-byte and no route or fidelity claim remains. H077's shared
  reciprocal-index adder is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed. The two
  tilt-family variants are closed unless their recorded conditions change.
  H078's sign-selected soft-add threshold join is exact and cycle-identical
  across the complete legal consumer domain, but adds six LUT4s in the complete
  registered engine; no production or permanent-proof file changed, and the
  soft-add threshold family closes.
  H079's dual reverb round-toward-zero rewrite is exact and saves isolated
  carries, but adds 32 whole-PSG LUT4/floor cells; production and permanent-
  proof edits are reverted byte-for-byte, no fidelity claim remains, and the
  reverb-rounding family closes. H080's shared sample-accumulator update passes
  every exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as direct commit `6458450`.
  It touches only `rtl/psg_timing.sv` and `tools/psg_hw_forms.py`; no R.84
  live-value regeneration is required by this change itself. H081's exact
  scheduled slide-adder sharing is rejected before production because its
  selected operands add 20 isolated LUT4/floor cells despite removing 25
  carries. H082's exact storage reuse is also rejected and reverted: retiring
  18 global flops adds 28 LUT4s and ten deterministic floor cells.
  H083's exact live-gain fusion is rejected before production because it adds
  21 isolated LUT4/floor cells for only three removed carries. H084's exact
  three-token LFSR is also rejected and reverted because its local win becomes
  a 32-cell global floor regression. H085's two exact divider-rounding
  relocation variants are rejected before production because both regress the
  complete isolated floor. H086's selected EA5 incrementer is exact and
  smaller in isolation, but adds seven whole-PSG LUT4s and eight deterministic
  floor cells; it is rejected and reverted before fidelity gates. H087's
  direct vibrato sign/magnitude decode is exact but adds one isolated LUT4, so
  no production file changes or downstream gates remain. H088's two derived
  timing strobes are exact but add two isolated floor cells; no production
  file changes or downstream gates remain. H089's state-selected pitch cone
  passes every exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as direct commit `996ee40`.
  Because it changes `rtl/psg_seq.sv`, eventual C2-C-C/R.84 integration must
  regenerate and rerun the live-value proof plus the complete
  cadence/render/physical battery. H090's shared step-count decode is exact but
  adds one isolated LUT4; no production or permanent-proof file changed, and
  the count-sharing family closes. H091's remaining-ticks compression is
  refuted by a reachable pending-trigger counter wrap; no production or
  permanent-proof file changed, and the pattern-counter compression family
  closes. H092's exact shared comparator-result flop saves one LUT4 and one FF
  alone, but adds 20 whole-PSG LUT4/floor cells and three carries; production
  and permanent-form edits are reverted byte-for-byte, and the EA2/EA4 result-
  lifetime family closes. H093's grouped DQ coefficient table is exact but
  adds three isolated LUT4s; no production or permanent-proof file changed,
  and the coefficient-decoder spelling family closes. H094's exact packed
  transition inequality saves one isolated LUT4 but adds three whole-PSG LUT4/
  floor cells; production and permanent-form edits are reverted byte-for-byte,
  and the transition-comparison spelling family closes. H095's exact trigger-
  length prefix composes on H089 and passes every proof, physical, fidelity,
  timing, preview, recovery, click, Celeste-smoke, and forced-reproducibility
  gate as direct commit `3d7a2e2`; I001 completed its required R.84 rebind and
  acceptance battery. H096 consumes the
  launch worklist after selecting the pacing owner and passes every generic
  exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as commit `a647185`. It
  changes `rtl/psg_seq.sv`; I002 regenerated and validated source-contract v4
  plus the unchanged C2-C-C live-value lineage. H102 encodes the wavetable bass
  flag in the otherwise-dead wavetable effect field and passes every generic
  exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as commit `ccfb2a0`. It changes
  both `rtl/psg_common.svh` and `rtl/psg_seq.sv`; I003 regenerated and validated
  source-contract v5 plus the unchanged C2-C-C live-value lineage. No R.84 B2
  claim is made. H127's selected phaser-threshold forms are exact but one is
  locally larger and the locally smaller comparator adds 50 whole-PSG LUT4s
  and 49 floor cells; production is restored and no downstream gate remains.
  H128's redundant write qualifier is exact but mapping-identical in the
  complete registered decoder; production is unchanged and no downstream gate
  remains. H129's fixed-bank `sfx_id` partition is exact but adds ten isolated
  LUT4s without changing 48 unpackable flops; production is unchanged and no
  downstream gate remains. H130's direct status selection is exact but adds
  two LUT4s in the complete registered readback; production is unchanged and
  no downstream gate remains. H131's direct row-owner XOR is exact but
  mapping-identical at 18 LUT4s/twenty unpackable flops; production is
  unchanged and no downstream gate remains. H132's spare reciprocal-EBR tail
  token is exact and retains one EBR, but adds five LUT4s for one fewer carry,
  FF, and unpackable cell; production is unchanged and no downstream gate
  remains. H133's one-bit address-MSB token plane is also exact and recovers
  two of H132's lost floor cells, but still adds three LUT4s for one fewer
  carry, FF, and unpackable cell; production is unchanged, no downstream gate
  remains, and the current spare-bit token family is closed. H134 merges the
  adjacent wavetable sample-byte lifetimes and shares their subtract; every
  exactness, physical, fidelity, cadence, preview, recovery, click and Celeste
  gate passes at 6,860 floor cells and 7,086 routed LCs. It changes
  `rtl/psg_walk.sv`, so no R.84/B2 source-certificate or lineage equivalence is
  claimed from this isolated loop. H135's adjacent `smp_b`/`mx_new` role is
  exact and removes seventeen isolated flops, but adds 37 LUT4s and worsens
  the isolated floor by nineteen cells; production is unchanged and no
  downstream gate remains. H136's multiplier sign token is exact, but the
  multi-pumped boundary activates two previously pruned token flops and the
  production-shaped isolated floor worsens by one cell; production is
  unchanged and no downstream gate remains. H137's direct fade-step decode is
  exact and wins eight isolated floor cells, but adds 84 global LUT4s and 72
  floor cells; production is byte-identical to H134 after reversion and no
  downstream route/fidelity gate remains. H138's signed-17 live/old pre-clamp
  noise storage is exact and wins six isolated floor cells, but adds 29 global
  LUT4s and 28 floor cells; production is byte-identical to H134 after
  reversion and no downstream route/fidelity gate remains. H139 shares the
  schedule-exclusive live/old noise scale tree and passes every exactness,
  physical, fidelity, cadence, preview, recovery, click, Celeste-smoke and
  forced-reproducibility gate at 6,800 floor cells and 7,018 routed LCs. It
  changes `rtl/psg_walk.sv`, so no R.84/B2 source-certificate or lineage
  equivalence is claimed from this isolated loop. H142's same-family middle-
  lifetime alias is exact and removes eleven unpackable flops in isolation,
  but adds seventeen LUT4s and worsens the complete isolated floor by six
  cells; production remains unchanged and no downstream gate remains. H143's
  reset-valid PCM representation is exact, but adds two LUT4s plus one
  unpackable validity flop and worsens the isolated floor by three cells;
  production remains unchanged and no downstream gate remains. H144's aligned
  byte-offset spelling is exact but mapping-identical in the complete
  registered address consumer; production remains unchanged and no downstream
  gate remains. H145's serialized dampen/fold arithmetic is exact and removes
  35 carries plus nineteen unpackable FFs in isolation, but adds 31 LUT4s and
  worsens the complete floor by twelve cells; the `fmc`-encoded variant is
  larger again, production remains unchanged, and no downstream gate remains.
  H146's selected DQ ceiling incrementer is exact and wins thirteen isolated
  LUT4s plus eleven carries, but globally adds 36 LUT4s, one carry, 36 floor
  cells and 43 routed LCs; production is restored byte-for-byte and no
  fidelity gate remains. H147's twelve-bit gain-history boundary is exact and
  wins five isolated LUT4s plus two FFs, but globally adds 26 LUT4s, two
  carries, 27 floor cells and 33 routed LCs while failing fast timing;
  production is restored byte-for-byte and no fidelity gate remains.
  H148's dedicated fade-step ROM is exact and wins 35 isolated floor cells,
  but globally adds nineteen LUT4s, four carries, five floor cells and thirteen
  routed LCs while spending the fifteenth EBR; production is restored and no
  fidelity gate remains. H149's collision-token packing is exact and wins
  twelve isolated floor cells, but globally adds 58 LUT4s, five carries, 47
  floor cells and 58 routed LCs; production is restored and no fidelity gate
  remains. H150's twelve-bit fade-step encoding is exact but worsens the
  complete isolated floor by two cells, so production never changed. H151's
  live divider operand is exact and retires eight flops with a three-cell
  isolated floor win, but globally adds 31 LUT4s, four carries, 25 floor cells
  and 32 routed LCs; production is restored byte-for-byte and no fidelity gate
  remains. H152's unified filter tuple is exact and retires eight packed flops
  with a five-cell isolated floor win, but globally adds 72 LUT4s, four carries
  and 72 floor cells while leaving the unpackable count unchanged; production
  is restored byte-for-byte and no route or fidelity gate remains. H153's
  `cpz` lifetime in dead `note_lo[7]` is exact and retires one unpackable flop,
  but adds one LUT4 and leaves the complete isolated floor unchanged;
  production never changed and no downstream gate remains. H154's radix-2
  iteration-class prefix is exact and retires three flops with a two-cell
  isolated floor win, but globally adds 51 LUT4s, one unpackable flop and 52
  floor cells; production is restored byte-for-byte, a forced map reproduces
  H139, and no route or fidelity gate remains.
  H155's shared complemented noise limb passes every exactness, physical,
  fidelity, cadence, PREVIEW, recovery, click, Celeste-smoke and
  forced-reproducibility gate, and restores the routable seed-1 canonical
  build that clean `644d68f` had silently lost to the clarity passes'
  source-text sensitivity. It changes `rtl/psg_walk.sv`, so any future
  R.84/B2 integration must regenerate and rerun the live-value proof plus the
  complete cadence/render/physical battery.
- Files to avoid staging after H155: executor/controller proof files, R.84/B2
  artifacts, Tang paths, images, tolerances and unrelated changes.

## Analysis A002 -- the selection census: residual mux fabric measured directly (2026-08-04)

Baseline `e004a57e4ee8 @ a121c03` (H161 tip). New instrument
`tools/psg_mux_census.py` (registered in the skill's psg-project.md): classifies
every SB_LUT4's truth table (cofactoring constant-tied inputs -- LUT_INIT is
variable-width, and skipping that step reads everything as 4-input logic) and
attributes pure-mux cells to their select net. Run it on the deterministic
`-noabc` JSON for a rank-stable, cleanly-named attribution.

**The headline numbers.** Pre-map: 3,877 of 13,349 cells (29%) are `$_MUX_`.
`-noabc` floor (8,282 LUT, spread 0): **2,008 pure 2:1-mux LUTs (24.2%)**,
1,483 half-absorbed (`s ? literal : g(two vars)`), 445 wires. Shipped abc9
(6,300 LUT): **997 pure-mux (15.8%)** + 382 with an inverted arm. abc9 absorbs
about half the floor's muxes; ~1,000 shipped cells remain pure selection.

**Structural facts that close whole escape shapes:**

- Only **16 of 2,034** pure muxes are register hold-muxes (D <- mux(Q, new)):
  yosys' enable extraction is already complete, so the "map hold-muxes onto
  DFFE" lever class is empty. The rest is genuine phase-scheduled *data*
  selection.
- Residual selection is NOT refundable selection. In a serial engine most
  surviving muxes are the time-multiplexing itself; the census localises cost,
  it does not promise a refund.

**Per-family attribution (select-net scope, -noabc) and dispositions:**

| family | pure-mux LUTs | disposition |
| -- | -- | -- |
| u_walk (total) | 910 (45%) | the serial engine is the fabric |
| u_walk.old_rev_r + old_alt_r | 211 + 63 | CLOSED: this is the `cmb_old` family; honest price 0 (its -158 was the constant-ablation artefact) |
| u_wave.u_ctx | 207 | unpriced; wave-mode shaping, blend-family prior (poor) |
| u_wave dq/q old-ctx steering | ~62 | **MEASURED this analysis: ablated to the new-context arm in an isolated `git archive` tree, pre-map 13,349 -> 13,319 = -30 ceiling.** Below band; dead as a standalone family. Census attribution and ablation price differ 2x: attribution counts cells whose select *net* derives from the family, not cells the family's removal refunds |
| u_seq.c (voice counter) | 76 | per-voice steering; adjacent closed rows (H107 play_bits +79, sfx_id wash); BRAM escape blocked by the two-async-writer staging cost |
| u_walk.cap capture mask | 68 | data steering by phase (not enables); operand-side already; unpriced |
| u_walk.bl_cnt | 51 | CLOSED: blend family (+31/+35/+132 three shapes) |
| mul request/start muxes | 83 | mined: operand-side selection landed (-168); landing-law constraints pin the rest |
| u_aram.u_core | 82 | RDATA-keyed unpacking; unpriced |
| addr/readback + top-level misc | ~341 total | readback mined (H033/H111/H106); play_bits closed (H107) |

**Relation to the Operation Cost Catalog (correction, same day).** An earlier
draft of this section called u_ctx/cap/aram "unpriced"; the catalog's 45
ablations already price all three (wave shaper -1,137, per-CAP-slot ceilings,
aRAM decode -143) as constant-ablation ceilings. What A002 adds is the
*mapped* layer and the *to-replacement* calibration:

- The catalog's constant-ablation ceilings over-attribute badly where arms and
  consumers fold together: old-voice steering reads -315 by constant ablation
  and **-30 by ablation to its replacement**. Read the catalog's table as
  ceilings-of-ceilings, per its own calibration constant 3.
- The census's mapped-layer number (16% pure-mux shipped) is the quantitative
  form of the catalog's headline: ~38 cells/operation of fabric is mostly this
  residual selection, and it is the serialization itself, not removable
  routing. The hold-mux result closes the one mapping-level escape (DFFE
  enables) that the catalog's pre-map view could not test.
- Both instruments agree the largest refundable cluster is the
  old-voice/crossfade arm (fidelity decision, -400..-600), and the census's
  escape-shape taxonomy points the same way the clean-room pool's best row
  does: H4' (address-selected storage) is the only exact-fidelity shape with a
  winning class record.

**Repeat only if:** the census fractions move materially (a new engine, a
schedule change), or a hypothesis needs per-select-net attribution or a
to-replacement calibration of a catalog ceiling before committing to a build.

## Hypothesis H165

- **ID:** H165.
- **Hypothesis:** a CPU wait-state contract (65C02 RDY held low, SN76489/
  Yamaha-style) lets state-memory-resident registers commit through the
  sequencer's idle port with ZERO staging flops — the frozen CPU is the
  staging register — unblocking the address-selected-storage class that the
  async-writer staging cost killed every prior time (sfx_id wash: 24 staging
  flops vs 46 saved). Stage 1 migrates sfx_id (8x6 fabric register file) into
  per-voice state word PSG_V_SFX=33, in the unreachable half of the stride.
- **Scope:** rtl/psg_seq.sv, psg.sv, psg_common.svh, chip.sv (internal RDY
  wiring only — no new chip.sv port), target_psg.sv (rdy joins the probe
  reduction), tang top, three TBs, sim/psg_wav.cpp (harness respects rdy).
  Preserved: 14-EBR topology, walk schedule, all consumer values. CHANGED BY
  DESIGN: CPU write/read timing to $10-$17 can stall (bounded by one engine
  service, <1% duty); the write-vs-trigger-service interleaving race is
  impossible by construction.
- **Baseline:** `e004a57e4ee8 @ 67c30f6` — premap 13,349; -noabc floor 8,791
  (spread 0); classic 6,899; abc9 floor n=16 median 6,811.5 (6,777–6,849);
  placed 7,027; 499 unpackable (abc9 census); 14 EBR; 31.35/128.35 MHz.
- **Changed condition versus prior attempts:** H101/H112/H129 bought a NEW
  EBR plus forwarding; the sfx_id-only attempt paid 24 staging flops. The RDY
  contract (user-authorized interface change, 2026-08-04) eliminates staging
  entirely and uses existing storage and traffic.
- **Change:** committed as `41ab202` on branch `h165-rdy-waitstates`
  (worktree). V_LD +1 cycle (word 33 -> w_sfx working reg); ml_launch writes
  ride the eng_we lane (new eng_va voice override); CPU commits gated on
  S_IDLE && !wlk_we via a cpu_stall/RDY handshake whose predicate deliberately
  omits rw (65C02 gates WE with RDY — reading rw is a combinational loop);
  $14-$17 readback is a stalled 2-cycle BRAM read (rb_done trails rb_valid one
  cycle so dout captures before release); DBG_PORT==1 keeps a snooped shadow.
- **Result** (rtl `978a95ce0aff @ 67c30f6`):

  ```
  pre-map cells      13,349 -> 13,340  -9    [deterministic]
  -noabc floor        8,791 ->  8,709  -82   [deterministic, spread 0]
  classic-abc floor   6,899 ->  6,815  -84
  unpackable (noabc)    509 ->    473  -36   [reliable]
  abc9 floor         median 6,811.5 -> 6,730.0, n=16/arm, ZERO overlap
                     (cand max 6,763 < base min 6,777) — p < 1e-8 any rank test
  EBR 14 -> 14; placed 7,027 -> 6,965 (-62, one draw); 31.11/143.64 MHz PASS
  ```

  test-psg ALL PASSED (incl. PICO-8 statistical fidelity; tick budget worst
  4,008/5,103 — the +8 clk/service V_LD extension fits with 1,095 spare).
  Gates sweep/models/mul/clicks/recovery PASS. Simulator-top lint identical to
  baseline (5 pre-existing warnings). **Oracle: 58/59 byte-identical; DIFFERS:
  mix-four** — the four-trigger burst serialises behind trigger services and
  the mixed onset lands exactly one sample (~45 µs) later; values track in
  parallel thereafter (no corruption). This is the contract's documented
  delta, not a defect.
- **Perceptual ruling (user-accepted, 2026-08-04):** the one-sample onset
  shift is inaudible by ~three orders of magnitude, and the mix-four anchor
  re-freeze is authorized on these grounds:
  - Onset-displacement detection needs ~10–20 ms even for trained listeners
    (~5–10 ms for rhythm experts). 45 µs is ~400x below that floor.
  - The only µs-scale human sensitivity is interaural time difference
    (~10–20 µs) — inapplicable: the whole mono mix shifts together, so no
    binaural cue exists.
  - Comb filtering from a 45 µs offset (~11 kHz notch) would require mixing
    against the un-shifted copy — nothing does; it is a pure translation,
    and the four channels stay mutually aligned on the sample grid.
  - PICO-8 itself quantizes sfx() triggers to frame boundaries (tens of ms):
    the delta is ~2–3 orders finer than the source platform's own trigger
    granularity, so no PICO-8 cart ever encoded meaning at this timescale.
  The byte gate did its job — it flagged the change for a human ruling; the
  ruling is that byte-exactness yields here, fidelity does not.
- **Decision:** stage 1 measured CANDIDATE on every instrument; the mix-four
  delta is accepted and its anchor re-freeze authorized (not yet executed).
  **Merged to main at `2aa1c43` (2026-08-04), after edd1178 fixed the pico8
  desync independently.** Composition validated on merged main: test-psg
  PASS, oracle 58/59 with only the expected mix-four delta; the authorized
  anchor re-freeze was then executed (pre-H165 anchor preserved at
  /tmp/mix-four-pre-h165.wav) and oracle passes 59/59 at rtl
  `4a1836c30279 @ 2aa1c43`. H166 merged in the same session. pico8 full-track
  stage **PASS** post-merge at rtl `4a1836c30279 @ 2aa1c43` — the RDY
  contract's trigger-timing delta does not move the full-track fidelity
  metrics, and edd1178's desync fix holds through the H165/H166 composition.
  Stage 2 (trg_row/trg_len/aud_row via the same lane, ~64 more flops incl.
  the V_ST aud_row write and banked-word readback) is designed, not built.
- **Repeat only if:** n/a — active. If rejected, the RDY plumbing reverts
  with it (branch h165-rdy-waitstates holds the whole change).

## Hypothesis H166

- **ID:** H166.
- **Hypothesis:** the fractional sample-clock accumulator `divd` only ever
  holds multiples of gcd(CLK_HZ, 22050); dividing the Bresenham constant pair
  by that gcd at elaboration shrinks the adder/register from spanning CLK_HZ
  to CLK_HZ/g with a cycle-identical strobe sequence.
- **Scope:** rtl/psg_timing.sv only. Exactness is algebraic, not empirical: by
  induction divd_reduced == divd/g at every clock (init and both steps scale
  uniformly; sign is scale-invariant), so sample_en/scnt/tick_en are
  bit-identical per cycle for every CLK_HZ.
- **Baseline:** `e004a57e4ee8 @ 67c30f6` — premap 13,349; -noabc floor 8,791;
  classic 6,899.
- **Change:** committed as `fce497c` on branch `h166-timing-gcd` (independent
  of H165). Elaboration-time Euclid in Verilog-2005 constant-function style —
  yosys's frontend rejects `return`/`int unsigned` in functions (first
  attempt died on TOK_ID); assign to the function name instead. Widths:
  26→18 bits at 18.75 MHz (g=150), 23→14 at the default clock (g=630).
- **Result** (rtl `6e41ef7e065c @ 67c30f6`): pre-map 13,349 → 13,342 (−7);
  -noabc floor 8,791 → **8,784 (−7**, spread 0, unpack 509 unchanged — the
  accumulator flops were packable); classic floor 6,899 → **6,859 (−40**,
  LUT4 −39) — the narrower carry chain pays more under classic covering.
  test-psg ALL PASSED; test-clocks /4 /5 /6 PASS (the gate that
  re-parameterizes this exact module); oracle 59/59 byte-identical.
- **Decision:** accepted on the deterministic instruments (small but real,
  H155-class); kept on its own branch pending merge order vs H165.
- **Repeat only if:** n/a — landed.

## Sizing Audit (opened 2026-08-04, H166 is entry 1)

First-principles review of every ticks/samples/clocks bookkeeping width:
replace "sized by what was convenient" with "sized by what the value needs",
one exact micro-hypothesis at a time. Not chasing big wins — building the
inventory of why each width is what it is.

| # | site | today | needed | status |
| -- | -- | -- | -- | -- |
| 1 | `psg_timing.divd` | clog2(CLK_HZ)+1 | clog2(CLK_HZ/gcd)+1 | **H166 landed** |
| 2 | `psg_timing.scnt` compares (==182, ==176) | two 8-bit equalities | down-counter sign bit | open; scnt is an exported port the sequencer schedules against — blast radius beyond the module |
| 3 | `s_phase2` | 24 bits | 17 live (clean-room oddity list) | **CLOSED 2026-08-04: already optimal.** Netlist check: only [16:0] are flopped — yosys const-folds [23:17] in hardware builds ([23:17] is live only under REALTIME_PREVIEW's 24-bit accumulate). The 24-bit declaration costs zero cells; do not respell (C-series source-text sensitivity). |
| 4 | `pph` | [6:0] | PLAST=61 (MULTIPUMP) fits [5:0] | **CLOSED 2026-08-04: real but not taken.** All 7 bits ARE flopped — a genuine invisible bound (counter reachability is not statically provable), but the prize is ~2-4 cells and it lives in psg_walk.sv, whose source-text sensitivity has unrouted the canonical build before. Risk/reward negative at this size. |
| 5 | `fade_acc`/`fade_step` vs fade_sum[16] bound | — | — | open: derive the real range |
| 6 | `s_eff_inc`/`s_old_inc` (dp) and the dq datapath | 14 bits | **14 — TIGHT** | **CLOSED 2026-08-05: H168 attempted and REFUTED by the fidelity battery.** The analytical bound was wrong by one octave: `dx_for_note`'s reference octave is 3, not 4 (psg_binary_model.py:94), so dp_max = 7,394 and the published `2*dp` reaches **14,788 — bit 13 is live for every pitch >= 60**. A one-bit narrowing measured −110 pre-map / −84 floor and passed lint, but the PICO-8 statistical gates failed within minutes (pitch-60 noise: >4 kHz share 0.69x, rms/centroid trends 0.68x — the too-slow-LFSR signature) and the change was reverted whole. **Lesson: an amplitude-plausible width reduction was refuted only by the fidelity corpus; never land a width cut on the analytical bound alone.** pclamp's pitch<=63 bound is real; the table scale was the error. |
| 7 | `dq17` result bus | named 17, carries 14 | 14 live (top 3 = 3'b0 by construction) | noted 2026-08-05: naming over-states width; likely const-folded (netlist check first); rename-with-localparam is C-series material |
| 8 | counter family: `scnt` (==182/==176 compares), `bl_cnt` 0..64, `vcnt`, `m_cnt` | — | terminal-value encodings | queued (chapter B) |
| 9 | `m_res` 34-bit multiplier bus | 34 | **CLOSED 2026-08-05: proven optimal.** Twelve consumer slices inventoried; the union stops at bit 28, consistent with |P| < 2^29 (18-bit x 12-bit magnitudes). Netlist: [33:31] const-folded already (the mulsvc comment's "public alignment" costs zero cells); [30:29] are flopped but LIVE — partial-sum staging the recurrence consumes via m_acc = m_p[30:12], shifting down each iteration. No dead flops. Chapter C's alignment-aware reading also CORRECTED a chapter-A note: the music-gain path is mode 1 (product lands <<2), so m_res[20:10] = P>>8 — **exact unity at mus_gain 255** (a*256/256 = a), not the "/4, <=448" previously recorded; the <=1,792 bound conclusion was unaffected. Remaining chapter C value is documentation: the full slice-x-mode alignment table (gz mode 2 and music mode 1 verified; wt/nz/blend/slide/div/ptick/chained-mode-3 pairings unwritten). |
| 10 | state-word layout census | 64x16 stride | constant/pad bits uncounted | queued (chapter D): inventory pad bits across pack sites — free storage for future H4'-style migrations (words 33-35 are precedent) |

**Chapter A (opened 2026-08-05): the amplitude/gain chain** — the third of
the voice triad (phase and increment are done). Targets: `a`/A0, `G =
tz(3a/2)`, scale divisors 3072 vs 2048, the +-6143 clamps, kick /1792, tilt
skew 24572/12286, `vol_r`/`a_pub` 12 bits, `mus_gain` 8, `gz_filt_r` 17,
`s_old_G`/`s_last_G` 13. Post-H168 rule in force: the analytical bound
proposes, the fidelity corpus disposes.

**Chapter A first findings (2026-08-05), constants decoded from the RE
model:**
- `a = vol << 8`, vol 0..7 → **a <= 1,792 — the noise kick's /1792 is
  max-amplitude normalization.**
- `scale(z) = tz(G*z/3072)` with `G = tz(3a/2)`: **the 3s cancel** —
  G/3072 = a/2048. 3072 = 3*1024 exists so the x3/2-then-divide
  factorization keeps every intermediate truncation integer-exact.
- Noise's /2048 against the same G: 3a*z/4096 = **1.5x hotter per
  amplitude unit than tones**, by design.
- The 6,143 family: tri_raw spans +-49,152 = 8*6,144; /4 primary and /8
  secondary land on the +-6,144 full-scale unit; the square's +-6143,
  the accumulator clamp, R(12286)=2*6143 noise, and the tilt skew's
  12286/24572 are all 1-2-4x that unit minus/around one LSB.
- **Two width questions raised (H168-class, corpus-gated):** `vol_r`/
  `s_eff_a` are 12 bits for values bounded by 1,792 (11 bits) — and the
  noise gain tap `s_eff_a[10:8]` recovers vol as if bit 11 were dead;
  `s_old_G`/`s_last_G` are 13 bits for G <= 3,360 with boost (12 bits).
  Both need the instrument-volume division path (`d_res[11:0]`) bounded
  before any cut, and the full fidelity battery regardless.

**Chapter A, d_res bound and netlist checks (2026-08-05):** every vol_r
writer is bounded — instrument scaling is `vol * ins_vol / 7` (div_d = 7,
result <= operand), music gain is mode-1-aligned `P>>8` — exact unity at
mus_gain 255, bound = a <= 1,792 (mechanism corrected by chapter C),
fades/slides interpolate within endpoints <= 1,792, and the source bound
`A0 = vol << 8` with a 3-bit volume field is instruction-verified. Netlist
(merged main, -noabc): vol_r[11], s_eff_a[11], s_old_G[12], s_last_G[12]
are ALL real flops — BRAM round-trips make them untrimmable. **H169
candidate: narrow the volume/G chain one bit** (vol_r/a_pub/s_eff_a/fade
datapath 12->11; g_a/g_live/s_old_G/s_last_G 13->12; pack slots follow),
est. 15-30 cells plus folded consumers of s_eff_a[11]. Gate protocol
(post-H168 rule): implement in an isolated worktree with NO concurrent
gate runs; detfloor; then the FULL battery including pico8 statistical
fidelity BEFORE any ledger claim — the volume bound rests on a 3-bit cart
field rather than an octave-scaled table, but the corpus still disposes.
gz_filt_r's 17-bit bound is chapter A's remaining derivation.

**gz_filt_r exploration (2026-08-05, fact sheet — derivation open):**
- Producer: `gz_filt_r <= m_res[26:10]` from the mode-2 shared multiply of
  `z_new_c/z_old_sel` (18-bit signed wave value, tri_v spans +-49,152) by
  `12'(g_live)`/`12'(s_old_G)` — the exact mode-2 product scaling (where
  scale()'s /3 lands) is the open piece; the landing law
  (psg-mul-alignment memory) governs the [26:10] slice.
- Rough bound via the cancelled form a*z/2048: |gz| <= ~16,128 for the
  mixed tri arms — which would make 17 bits one over (15+sign suffices),
  BUT this is exactly an H168-shaped trap until mode 2 is pinned.
- Three consumers already treat it as 16-bit: the reverb ring stores
  gz_filt_r[15:0] (psg_walk.sv:897), one path sign-extends [15:0]
  ({gz_filt_r[15], gz_filt_r[15:0]}, :736), and the noise arm halves
  ([16:1], :608). One consumer uses the full 17 ({gz_filt_r[16], ...},
  :769) and the filter feedback adds it into m_res[28:3] (:603).
- Netlist: all 17 bits flopped (BRAM-opaque via the oscillator words).
- **Mode 2 PINNED (2026-08-05):** the service has one accumulator
  boundary; an N-iteration request lands the exact product shifted left
  by (12−N) — mode 2 retires all 12 multiplier bits, so it is the PLAIN
  product at natural alignment (tools/psg_mul_model.py docstring is the
  authority). No scaling hides in the multiply.
- **The /3072 decomposes across the consumers:** gz_filt_r <= m_res[26:10]
  is z*G >> 10. The TONE arm then applies x(2/3) via the gz_171
  reciprocal recombination (171 ~ 2/3 * 256; shift-add slices of the
  product summed into gz_q3acc) and consumes only gz_q3acc[33:19] — 15
  bits — giving G*z/3072 exactly. The NOISE arm skips the /3: it halves
  the raw register ({1'b0, gz_filt_r[16:1]} = z*G/2048), matching the RE
  doc's noise divisor. **The noise arm alone sizes the register:** tones
  use <=15 bits of it, so the 17-vs-16 question reduces to
  max|z_noise * G| / 1024 — one unknown, the noise sample bound,
  entangled with the deliberate int16 wrap the RE doc documents at high
  pitch. **DERIVED (2026-08-05), chapter A closes: 17 bits is TIGHT and
  semantically exact — it is PICO-8's int16 noise buffer, one bit up.**
  The chain: nz_out_r holds the PRE-clamp accumulator (the RE doc's
  "output reads r before the clamp"), |nz_pre| <= 6,143 + J/2 (J = 8dp
  + 1120 <= 60,272) + kick <= ~42,400; >>6 then the exact x80/x68
  shift-add (the k = 2048/den + 48 table; einc[13] selects the
  high-pitch x68 arm — the very bit H168 tried to delete) gives
  |nz_z| <= ~53,000; times G <= 3,360, >>10 gives up to ~174,000 —
  which EXCEEDS 2^17. That overflow is not a bug: the [26:10] slice
  truncation reproduces PICO-8's documented int16 WRAP ("which big kick
  escapes at high pitch", movw). gz_filt_r holds 2y where y is the
  int16-wrapped noise sample (the noise consumer halves [16:1]), so
  **17 = 1 + 16: the pre-halved representation of a wrapping int16.
  Not a dead bit — a semantic width.** The amplitude triad is complete:
  every per-voice quantity (phase 16/17, increment 14/14, amplitude
  11/12/17) now has a first-principles answer, and chapter A produced
  one landed win (H169), one refutation (H168), and three proofs of
  existing tightness.

Each entry needs the H166 treatment: state the invariant that bounds the
value, prove the reduction exact against it, land only on a deterministic
verdict. The Operation Cost Catalog prices whole operations; this table
prices their bookkeeping.

## Clarity C012 — width intent for pph and s_phase2 (2026-08-05)

Sizing-audit intent capture, user-directed ("the source should capture the
intent even where synthesis already trims"). `PPH_W = $clog2(PLAST+1)` sizes
the walk phase counter (6 under MULTIPUMP, 7 otherwise); `PH2_W =
REALTIME_PREVIEW ? 24 : 17` is declared with the psg_walk/psg_wave
parameters because the s_phase2 port needs it, with a zero-extended
`ph2_pad` view keeping the PREVIEW-only wide slices width-stable in both
elaborations. tools/psg_viz.py's PPH_VALUE_RE/ARM_RE now accept named
localparam width casts, per its own renames-are-source-only doctrine.
Verified vs merged main `4a1836c30279`: pre-map −18, -noabc floor −9,
classic +3 (neutral within instrument spread); routes at 6,986 LC / 14 EBR /
31.66/131.93 MHz; test-psg, test-clocks, oracle 59/59, psg_viz 13/13; lint
at the five established warnings. Merged at `6cb0539`.

**The 17 in PH2_W is now proven, not transcribed** (session discussion,
2026-08-05, recorded in docs/hardware-gaps.md "Voice architecture"): an odd
dq is coprime to 2^17, the orbit has period 2^17 samples, tri_raw is not
2^16-periodic over the extended domain, so no 16-bit-state generator can
emit the sequence — the bit is irreducible, and dither reformulations
merely relocate it. It is also NOT a clean fixed-point split: a fractional-
precision design would read q0[16:1]; PICO-8 reads [15:0] for u16 waves and
all 17 bits (LSB into amplitude) for triangle/phaser.

## Hypothesis H167

- **ID:** H167.
- **Hypothesis:** stage 2 of the H165 lane — trg_row/trg_len into per-voice
  words PSG_V_TROW=34/PSG_V_TLEN=35 (CPU wait-state writes, V_LD-loaded
  working copies, T_FL/T_SP clears through the engine lane), and aud_row
  DELETED: word PSG_V_SEQ[4:0] of the audible voice equals it at every
  CPU-observable instant because reads only commit while the engine idles.
- **Baseline:** merged main `4a1836c30279 @ 4e231a7` — premap 13,363
  (edd1178 added ~+50 over the pre-merge floor); -noabc floor 8,761;
  classic 6,840; C012 tip premap 13,345 / floor 8,752 / classic 6,843.
- **Change:** branch `h167-trg-aud` (worktree), commits `<stage2>` +
  dqsvc K-table comment. V_LD extends to vcnt 10 (+16 clk/service; tick
  budget margin measured 1,171 spare, IMPROVED vs stage 1's 1,095).
- **Result** (rtl `4e1b0c8e377b`, pre-nudge): pre-map 13,345 → 13,281
  (−64); -noabc floor 8,752 → **8,645 (−107**, unpack 503 → **450, −53**);
  classic 6,843 → **6,721 (−122)**. Placed seed-1 **6,884 LC (−102)**.
  test-psg ALL PASSED; test-clocks PASS; **oracle 59/59 byte-identical**
  (trg writes precede their triggers — the stall window never engages, so
  unlike stage 1 there is no anchor delta at all). Lint clean.
- **Physical:** routes under seed1+router1 (34.32/147.15 MHz PASS) and
  seed2+router2 (33.26/137.89 MHz PASS). The canonical seed1+router2 draw
  wedges at overuse=1 (the H055/H155 single-wire router2 oscillation),
  robust to one source nudge; second nudge (dqsvc comment) in flight.
  **Placement is identical and healthy (6,884 LC); this is a router
  pathology, not a netlist defect.**
- **Decision:** the canonical seed1+router2 draw wedged identically across
  THREE source texts (overuse=1, wires=83442) — the text lottery does not
  converge here. The user amended the contract (2026-08-05) with the
  dual-evidence fallback now in the ROUTABILITY DOCTRINE above; H167's
  routability is satisfied by seed-1 router1 (34.32/147.15 MHz PASS) +
  seed-2 router2 (33.26/137.89 MHz PASS), canonical placed 6,884 LC.
  A first pico8 full-track run failed from mid-run contamination by the
  since-refuted H168 edits (the harness rebuilds from source); the clean
  rerun on unmodified stage 2 PASSED. **Accepted and merged to main at
  `824d18b` (2026-08-05).** Combined H165+H167 against the pre-campaign
  8,791 floor: state memory now holds what four fabric register files held,
  the CPU wait-state lane is the established mechanism, and the register-
  interface-to-BRAM class has two landed wins and a proven lane for more.
- **Repeat only if:** n/a — active.

## Sizing Audit — Chapter E: the mixer (2026-08-05)

The last quarter of the architecture: 8 slot leaves (18-bit signed) reduce
through a serial binary tree of seven soft_adds on ONE shared 18-bit ALU
with a 3-level stack (fstk[0:2] — minimal for an 8-leaf tree); dry16 is
the final [15:0]. H164 already mined the composition stage's cheap half.

**The constants are a joint fixed-point design, derived:** soft_add is
linear inside +-24,576 and compresses the excess 5:1 (exact nearest /5 via
the t0/t1/t2 shift-add chain). 24,576 = 0.75 x 32,768, and solving
B = 24,576 + (2B - 24,576)/5 gives **B = 32,768 exactly**: the knee at 75%
of full scale with 5:1 compression makes the reduction SELF-LIMITING at
precisely int16 range for any number of voices. Neither constant is
arbitrary; they are two unknowns solving "converge to full scale."

**Width verdicts:** 18-bit leaves (the noise arm's sign-extended 17-bit
wrapped sample sets the floor); 19-bit sum inside soft_add (tight);
18-bit stack (the fixed-point bound); dry16's [15:0] slice justified by
the same bound, with a one-LSB boundary question (an exact +-32,768 hit
rounds to the int16 edge) left open but corpus-covered.

**Closed candidates re-affirmed:** H5' (four-leaf mixer, at most 4 of 8
leaves audible) stays blocked by soft_add's non-identity on zero —
soft_add(x, 0) re-compresses any |x| >= 24,576, so dropping zero leaves
changes loud renders; the catalog's -202 compression ceiling is the
architecture, not fabric. Radix-4 question (same day, conversational):
the multiply core's radix is width-invariant to first order (product
bound dominates; staging = radix_bits), the 3a pre-adder rides a carry
chain while Booth recode would ride LUT selection (the LAW), the
schedule pins mode latencies, and the multipump already doubles
effective radix in time — radix-4 magnitude-only is fabric-optimal;
closed as a question (H154's +51 is the adjacent measured refutation).

**Chapter E addendum — the crossfade optimization pocket (2026-08-05,
user-directed after ruling out removal):**
- **Old-arm steering is irreducible by lifetime overlap (probe 3, closed).**
  make psg-lifetimes (anchor fixed for C012): nz_old_out_r lives 30..44,
  smp_a/smp_b 30..44, mx_new 44..59, mx_old 54..59 — the old and new arms
  are SIMULTANEOUSLY live between capture and blend inside every walk, so
  write-side register sharing (the cheap alternative to read-side steering)
  is structurally unavailable. The -400..-600 attribution is the
  serialization law, now with lifetime evidence.
- **The old_/last_ dual generation is a pipeline, not duplication (probe 1,
  closed).** last_* detects tuple changes and becomes the next blend
  source; old_* feeds the live blend; the `blend_restart ? last : old`
  muxes are single-cycle WRITE FORWARDING of the pending old_ <= last_
  copy, not dual storage — removable only by deferring the dq/nz request
  phases (a load-bearing schedule change). Both generations are already
  BRAM-streamed. Yield ~0 without schedule surgery.
- **Actionable remainder (sub-band, riders only):** bl_cnt as a 6-bit
  counter + wrap-carry blend_done flag (the ==64/!=64 comparators collapse
  to one flag bit; the multiply operand k is 0..63 and takes the counter
  directly) ~4-6 LUTs; plus the lifetimes tool's incidental packing
  candidates (wt_x1 into mx_new's dead window 8 flops; fmc/fsel rehoming
  4+3 flops) — the "reliable but least predictable" class. Bundle with the
  next psg_walk-touching hypothesis; never as standalone sub-band rows.

With chapters A, C and E closed and B/D queued as documentation, every
arithmetic quarter of the PSG — oscillators, voices, magnitude, mixer —
now has a first-principles width story.

## Hypothesis H169

- **ID:** H169.
- **Hypothesis:** the volume/G chain carries one dead bit end-to-end: A0 =
  vol<<8 with a 3-bit cart volume field bounds every writer at 1,792
  (instrument /7, music gain >>10 <= 448, fades within endpoints), so
  vol_r/a_pub/s_eff_a/fade datapath narrow 12->11 and g_a/g_live/
  s_old_G/s_last_G narrow 13->12. State layouts keep the retired bits as
  explicit zero pads — BRAM contents byte-identical.
- **Baseline:** merged main `5031762` — floor 8,645; classic 6,721; placed
  6,884 (H167 dual-evidence).
- **Change:** branch `h169-volume-width`, merged at `a55b349`. One
  consumer (`12'(g_live)`) had already truncated the dead bit; the
  `vol_r[11:8]` digit extractor became [10:8].
- **Result** (rtl `80c6ff7add23`): pre-map 13,281 -> 13,240 (−41);
  -noabc floor 8,645 -> **8,621 (−24**, spread 0); classic 6,721 ->
  **6,643..6,662** across the consumer-fix respin. **Placed 6,853 (−31),
  canonical seed-1 router2 completing normally** — 31.15/138.89 MHz PASS,
  14 EBR (the H167 wedge was netlist-specific). test-psg ALL PASSED incl.
  the statistical fidelity stage that refuted H168; test-clocks PASS;
  oracle 59/59; pico8 full-track PASS. Lint at the five established
  warnings.
- **Decision:** accepted and merged. Chapter A of the sizing audit closes
  with it: phase (16/17, orbit theorem), increment (14/14, tight via the
  octave-3 reference), amplitude (11/12/17, this row plus the gz_filt_r
  wrap-semantics proof).
- **Repeat only if:** the volume field ever exceeds 3 bits (a cart-format
  change), or a new writer bypasses the pclamp/divider paths.

## Hypothesis H170 — OPENED (orientation verdict, 2026-08-05)

- **ID:** H170 = the clean-room pool's H1' (control-ROM the sequencer
  decodes into crom[64..255]).
- **Orientation findings:**
  1. **The naive ceiling is unusable.** Constant-stubbing the four big
     `case (sst)` decoders (pub_wd, eng_rd/eng_word, eng_we bundle, smul
     request) measures −2,242 pre-map — CAP_W0-artifact class: it kills
     the sequencer's entire output and folds the engine. Do not cite it.
  2. **The crom port is contended three ways:** the walk owns it during
     prun (ctrl_addr = 144 + pph_nxt), the seq's pitch reads own it via
     pinc_addr otherwise, and replay reuses held words. The engine holds
     under seq_hold ~= prun, so control-word prefetch cycles exist only
     on engine-advancing cycles whose state does not consume pinc_q —
     a per-state port schedule must be proven before any conversion.
  3. **The decoders are NOT pure constant tables.** Arms mix static
     per-state constants (word ids 0..8, PSG_V_* addresses) with runtime
     terms (abank/e_insfx/seq_hold selects, par_cpy+k adders). The viable
     shape is a SPLIT conversion: ROM fields for the static constants
     (e.g. both abank arms as two fields + one retained runtime 2:1;
     par_cpy + ROM field through ONE shared adder), runtime muxes kept.
  4. **The FSM computes next-state in the clocked block** — a one-cycle-
     ahead control fetch needs next_sst exposed combinationally: a real
     restructuring, the same class the pph precedent priced at
     −75 pre-map / **+21 mapped** plus a block.
- **Gate-1 plan (next session):** prototype the SMALLEST decoder only
  (eng_rd/eng_word, 31 lines, 7 control bits) with the split-conversion
  shape and an explicit port-schedule proof; deterministic floor verdict
  decides whether the class scales to the other three. No claims before
  that lands. Riders to bundle with any accepted H170 build: wt_x1 into
  mx_new's window, fmc/fsel rehoming (see chapter E addendum).
- **Status: REFUTED BY MEASUREMENT (2026-08-05), no build required.**
  The netlist check that should precede any decode-conversion design:
  `sst` is fsm-encoded into **6 bits** (not one-hot), and only **15
  LUT4s in the whole design consume any sst bit directly** — the first
  level of ALL nine case(sst) decoders together. The fsm pass + abc9
  already share the state-decode terms; everything downstream is data
  steering the split-conversion would retain. The replaceable fabric is
  ~an order of magnitude below the −250..−400 claim, which rested on
  the pre-map-ceiling illusion its own pool note flagged. The pph
  precedent was the same phenomenon, now understood: **fsm-encoded
  state decode is already a compressed control store; a ROM re-adds
  the staging that compression removed.** Closed verdict for the whole
  microcode/control-ROM class on this design.
- bl_cnt rider landed independently (floor 8,618, placed 6,838).
- **Goal implication:** with H170 dead and crossfade removal vetoed, no
  identified structural door remains for the goal's last 192; the pool's
  surviving items are user-decision doors (H2' EBR-topology change, H3'
  render-changing wave ROM) plus sub-band riders (~15-25).
