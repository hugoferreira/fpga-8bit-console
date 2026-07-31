# Handover: noise fidelity — COMPLETE

Status 2026-07-31. The three defects below are explained, fixed in RTL,
measured, and protected by the synthetic noise-sweep gates. Every Celeste
music entry point (0, 10, 20, 30 and 40) is also a provenance-bound full-track
gate; together they traverse all music patterns used by the cart. Entries 10,
20, 30 and 40 pass. Entry 0 retains a known post-pattern-3 high-band mismatch
for a later PICO-8 fidelity pass; the frozen 59-render matrix is the
render-exact regression gate for the RTL optimizations.

## Post-closeout correction: the first full-track comparison was stale

The side-by-side spectrogram showed the PICO-8 reference darkening much more
than the candidate during quiet passages. The old full-track report still passed:
total RMS ratio 1.00, loudness contour 0.995, timbre contour 0.983, and spectrum
cosine 0.996. Those statistics preserve trajectory or normalized shape and can
therefore hide a persistent absolute band-level error.

`tools/psg_ref_check.py` now measures four absolute power bands in overlapping
one-second windows. It reports integrated whole-track level, median local level,
and the median over the quietest 35% of reference windows. Bands carrying less
than 0.5% of reference-window power are excluded, true silence is ignored, and
the fixed guard is +/-1.5 dB. Unpitched material is aligned by its smoothed power
envelope rather than meaningless waveform correlation.

The new metric correctly failed `hw28-30-v3.wav`:

- 250 Hz-1 kHz whole-track: -1.63 dB;
- 4-8 kHz whole-track: +2.98 dB;
- 4-8 kHz quiet windows: +3.95 dB.

That last value is nearly 2.5x reference power, but it was not a remaining RTL
defect: `hw28-30-v3.wav` was written at 17:43, while the final noise fixes in
`rtl/psg_walk.sv` were written at 22:48. The image labelled a five-hour-old
intermediate render as "Current RTL". A fresh render from the actual source
passes: -0.09/+0.16/+0.07/+0.14 dB whole-track across the four bands, with
-0.04 dB in the quiet-window 4-8 kHz band.

`tools/psg_track_gate.py` prevents that provenance error. It always renders the
current hardware-schedule RTL, fingerprints every PSG source plus the cart audio
and reference, writes those hashes beside the candidate WAV, and then invokes
the full-track comparison. The single-track diagnostic command is:

```sh
make test-psg-track \
  CART=~/Stuff/carts/celeste-15133.p8.png \
  MUSIC=30 \
  PSG_REFERENCE=build/p8ref/pico8-30.wav
```

The final integration gate is:

```sh
make test-psg-celeste-tracks \
  CART=~/Stuff/carts/celeste-15133.p8.png
```

It renders entry points 0, 10, 20, 30 and 40 from the current RTL, verifies
candidate provenance, and compares each against
`build/p8ref/pico8-{0,10,20,30,40}.wav`.

`tools/test_psg_ref_check.py` protects the analysis with an equal-RMS
spectral-tilt case, a quiet-only excess that passes the whole-track average,
inactive-band handling, envelope alignment, and process-level exit status
checks.

## The three defects (all fixed in rtl/psg_walk.sv)

1. **Publication bug — the entire measured residual.** `noise_filt_step`
   updates `s_noise_lp` and advances the LFSR at CTRL_W0 (pph 19); the mixer
   consumed the COMBINATIONAL `nz_pre` on later cycles, by which time it had
   re-evaluated as (updated accumulator + a FRESHLY DRAWN step on the same
   toggle arm). Every step-parity sample carried two different steps; holds
   never reached the output. Proof: on the fidelity probe, tog=0 samples
   matched the stored walk 97.6%, tog=1 samples 3.5%, and the phantom term
   was uniform up to exactly J/2. A Python replica of the bug (R0) reproduces
   the old RTL's signature to 3 significant figures (centroid 1.192 vs
   measured 1.193, HF share 2.001 vs 2.040, repeats collapsed). Fix: the
   output now reads registers `nz_out_r`/`nz_old_out_r` written at CTRL_W0 —
   the same trap class as a_pub ("publication must be a register").
2. **Kick emasculated.** The gate compare `{lfsr[14:7],lfsr[4:0]} < thresh`
   and the magnitude draw shared the same lfsr bits, so firing FORCED the
   top slice toward zero: every kick was ±<700 (traced values 96, 480)
   instead of the listing's ±6143 amp-scaled impulse. That is why "kick
   disabled entirely" measured as a no-op — it effectively was one. Fix:
   second maximal 15-bit LFSR `lfsr2` (x^15+x^11, seed 0x5117, advanced at
   all three lfsr sites); draw = t11 − t11/8 − t11/64 (±880 base unit) from
   lfsr2[12:2]; kick = draw·q with q = s_eff_a[10:8] (exact at whole
   volumes, staircase inside fades; q=7 lands ±6160).
3. **Missing per-tick blend for noise.** The binary copies the WHOLE osc
   state EVERY tick and crossfades 64 samples against the copy
   (RE write-up "Per-tick smoothing", listing 0x1000f1c87–0x1000f1d70). For
   deterministic waves the unchanged-tick copy renders identically — the
   RTL's params-changed-only copy was byte-equivalent there — but for noise
   the copy and the live walk draw different randoms and DIVERGE. That
   two-walk blend is where PICO-8's repeated-sample slope (29%→6% across the
   pitch sweep) and its tick-rate variance averaging come from. Fix: when
   the old arm renders plain noise, the old walk LIVES IN the s_old_phase
   word (record grows by nothing); steps from lfsr2's advanced slice on the
   SHARED toggle; takes the SAME kick value as the live walk; restarts from
   the live accumulator at every bank flip (`nz_tick_r` = spar_bank edge at
   the sample boundary). `z_old_sel` muxes it into the arm-4'd6 launch and
   the CTRL_W17 sign capture; CTRL_W5's old-phase advance is suppressed via
   `old_nz_r_on` while the alias is live. Blend restart = the params-changed
   condition extended with `(wave==6 && !wt && !buzz && nz_tick_r)`.

## Listing facts settled this session (pico8.x86_64.asm)

- Legacy walk decoded instruction-by-instruction at 0x1000f08bd..0x1000f0b14;
  the write-up's prose had the clamp order WRONG — the listing reads r
  pre-clamp (`sarl $6` on a copy taken before the clamp cmovs), clamps only
  the stored state. HEAD already had this right.
- The kick-arm guard `-0x50(%rbp)` is `state[0x54]` = the BUZZ flag: legacy
  noise under buzz runs kick-free. Not the old-block flag it was guessed to be.
- `_codo_random` verbatim: H = rol32(H,16)+L; L += H; R(m) = H mod m,
  unsigned, R(0)=0.
- k = max(16, 2048/den)+48, den = pitch<48 ? 64 : pitch+16. Exact k was
  modelled (variant R3): NO measurable gain over the RTL's 80/68 two-level
  form. Do not spend record bits on it.

## Model work (tools/psg_binary_model.py, modified, uncommitted)

Wave-6 legacy noise is now IN the byte-exact model: `render_noise` is
instruction-exact from the listing, driven by the real shared RNG
(`codo_random`, module state RNG_STATE), runs at g==0 (muted voices consume
draws), int16-wraps the buffer cell. OscState carries nz_r/nz_tog/nz_pitch/
nz_amp; both calc_tick paths set them. On the fidelity probe the model
matches the recorded reference at rms 0.995 / centroid 0.997 / repeat curve
exact / escapes exact / band shares within 5% — the decoded mechanism IS
PICO-8's. Deterministic sweep unaffected (noise was previously out of scope;
g==0 wave-6 output is unchanged zero).

## Where the fixed RTL measures (vs tests/psg/pico8-noise-sweep.wav)

repeats 29/28/26/23/20/16/11/7 vs ref 29/27/25/24/20/15/10/6; rms 1.002,
centroid 0.998, HF-share 1.022, LF-share 0.984; all 16 per-pitch rows within
rms 0.92–1.06 and centroid 0.97–1.03; trends 0.98 (rms) / 0.94 (centroid).
Scratch harness (session scratchpad noise_variants.py, results reproduced in
this doc): R2f = the shipped design.

## Final verification

- `psg_oracle_bytecheck`: **59/59 unchanged** after deliberately re-freezing
  `wave-6-noise` to SHA-256 `1294cd1069c0839369b2ef209e5d0adabab503d633bc065466ae0fdeea5f473d`.
  The frozen set is under ignored `build/`, so this is a local regression
  baseline, not fidelity evidence.
- The complete real-PICO-8 oracle matrix is **59/59 diagnostic-clean**.
- `psg_tb` **ALL TESTS PASSED**, including the schedule-budget check. TRAP: the
  memorized build command lacks `-Irtl` and dies on includes; piping through
  `tail` masks the failure and a STALE binary "passes". Use:
  `verilator --binary --timing -Irtl -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
  -Wno-PINMISSING -o psg_tb_bin rtl/psg_tb.sv rtl/psg.sv rtl/dsigma.sv
  --Mdir build/obj_psgtb`
- `make test-psg-preview CART=~/Stuff/carts/celeste-15133.p8.png`: PASS 36/38.
- Lint clean, both flavours.
- `python3 tools/psg_binary_model.py sweep`: 57/57 deterministic cases
  byte-exact; the two shared-RNG cases are correctly skipped.

## Fidelity-gate closeout

`tools/psg_fidelity_gate.py` now uses 2205-sample centroid windows at a
441-sample hop and the standard deviation of all overlapping windows. The
reference measures 59.4/39.3 Hz at volumes 7/1; twelve exact-model RNG seeds
span 47.8–62.0/31.4–41.9 Hz; current RTL measures 59.1/34.3 Hz. The target is
1.10x and the regression guard 1.25x, calibrated above the model's measured
upper spread rather than raised around an RTL result.

Two sharp gates now protect the defect class:

- repeat-rate ratios: 1.03x / 1.00x at volumes 7/1;
- >4 kHz power-share ratios: 0.98x / 0.98x.

Both use a deliberately broad 0.75–1.25x guard. An isolated rebuild of git
`HEAD` (the buggy publication path) must-failed at 0.05x/0.04x repeats and
1.50x/1.96x HF share. It also failed low-volume wander at 1.92x. The fixed RTL
passes every fidelity check.

## Area result and deliberate cleanup

`make synth-psg`, RTL fingerprint `1018ab414436`, reports 8,327/7,680 iCE40
logic cells (108%) and 22/32 RAM blocks; placement fails on logic. This is the
requested delta measurement for the area campaign. The target still builds
with REVERB=1, so compare it with the memory note's REVERB caveat before
attributing the whole number to noise.

The `PSG_NOISE_DEBUG` `$display` was removed after the must-fail proof. The
three project memory notes were updated with the fixed mechanism, final gates,
and instruction-exact model boundary.

## Re-examine before trusting: the old refuted list

EVERY experiment in the previous handover's "Refuted — do not re-run" table
was measured THROUGH the publication bug, whose double-step dominated every
statistic those experiments read. Known now-invalid conclusions: "kick
magnitude scaled by amplitude: no change" (kicks were near-zero regardless);
"kick disabled entirely: no effect" (same reason); the second-generator
centroid trade (measured on the whitened spectrum). The trap note about
periodic noise scoring better on wander remains TRUE and matters for the
gate rework.

## Recording-path facts (for anyone re-recording the reference)

The reference is PICO-8's own recorder = engine-true samples; ~65-sample
lead-in; a small drifting DC (~−82) puts VALUES off the 105-per-quantum
lattice while preserving deltas and repeats. Two recordings are
byte-identical (deterministic RNG from startup), so the reference is ONE
realization of a heavy-tailed estimator — which is the whole wander story.
