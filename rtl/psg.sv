// PSG v2: a PICO-8-equivalent audio chip.
//
// The chip holds PICO-8's audio RAM image verbatim: 64 music patterns
// (PICO-8 $3100-$31FF, 4 bytes each) and 64 SFX records ($3200-$42FF,
// 68 bytes each: 32 x 16-bit notes {custom[15], fx[14:12], vol[11:9],
// wave[8:6], pitch[5:0]}, then filter/speed/loop-start/loop-end). Cart
// bytes upload unchanged through the auto-increment port, which takes
// PICO-8 addresses.
//
// Timing is PICO-8's: a fractional divider derives a 22050 Hz virtual
// sample rate from CLK_HZ, and a sequencer tick fires every 183 samples
// (~120.49 Hz). An SFX row lasts `speed` ticks. Loop semantics follow the
// record: loop rows [start,end) when start < end; when end = 0 and
// start > 0, start is the SFX length in rows; else 32 rows and stop.
//
// Synthesis: 8 waveforms (four non-trivial shapes from a generated wave
// ROM, exact square/pulse phase thresholds, pitched sample-and-hold LFSR
// noise and dual-oscillator phaser) and all 8 note effects evaluated per
// tick (slide, vibrato, drop, fade in/out, fast/slow arpeggio). Channels
// are serialized through one datapath between samples; the mix clips
// PICO-8-style (one full-volume triangle = half scale).
//
// A note with bit 15 set plays through a custom instrument: SFX 0-7,
// picked by the note's waveform field, runs as a second playhead on the
// channel. Its row supplies the waveform, its pitch adds to the note's
// relative to pitch 24 (C-2), its volume multiplies the note's and its
// filter byte is folded into the channel's filters. The playhead is only
// retriggered when the note's pitch changes, the previous note's volume
// was 0, or the note carries effect 3 (which means "retrigger", not
// "drop"). An instrument SFX whose loop-start byte has bit 7 set is a
// 64-sample wavetable read straight out of audio RAM instead, an octave
// down when its speed byte has bit 0 set.
//
// The music sequencer is hardware: writing a pattern number fetches the
// 4 pattern bytes, launches the enabled channels' SFX, ends the pattern
// by the left-most non-looping channel rule, and follows the loop-start /
// loop-back / stop flag bits with zero CPU work.
//
// Registers (byte window at $4100):
//   $00/$01 upload address lo/hi (PICO-8 address), $02 data (auto-inc)
//   $03 (read) playing bits [3:0], music playing bit 7
//   $10+c write: play SFX n (0-63) on channel c; $80 stops the channel,
//                $81 releases it from looping
//         read: {playing, 2'b0, row}
//   $14+c write: start row for the next trigger on channel c (auto-clears)
//         read: {playing, 1'b0, sfx number}
//   $18+c write: rows to play for the next trigger, 0 = whole record
//                (auto-clears; a nonzero length overrides the loop points)
//   $20 write: start music at pattern m (0-63); $80 stops music
//       read: current pattern
//   $21 channels reserved for music (advisory: the CPU consults it when
//       auto-picking a channel for an SFX; reset $00)
//   $22 music fade length in 16 ms units, applied to the next music start
//       (fade in) or stop (fade out), then cleared
//
// MODULE MAP. This file is the composition; every register is written by
// exactly one submodule, cross-module reads travel on ports, and there are
// no cross-module writes.
//
//   psg_timing     u_timing  the fractional divider, scnt, the five strobes
//   psg_aram       u_aram    the PICO-8 image, the upload port, the ONE
//                            shared read port and its borrow/replay contract
//   psg_mulsvc     u_mul     the one shift-add multiplier
//   psg_divsvc     u_div     the one restoring divider (sequencer only)
//   psg_state_mem  u_state   the scheduled record store and its two-owner
//                            port priority
//   psg_wave       u_wave    the computed wave layer: z_eval, dq17, q16
//   psg_walk       u_walk    the per-sample synthesis walk; owns prun/pph
//   psg_seq        u_seq     the per-tick sequencer; owns the FSM, the
//                            records, the effects and the control writes
//   psg           (this)     ports, wiring, walk_frozen, the multiply
//                            merge, the PCM register, the CPU read mux, dbg
//
// The shared-resource invariants are the interfaces, not comments: one
// multiply service behind one merged request bundle, one divider, one
// state_m port pair behind two owner bundles, one aram read port. The
// walk-freeze contract is formed HERE because its four terms belong to
// three different owners and this is the only scope that sees them all.

// Slot counts, the scheduled record's word layout and the audible-slot rule,
// at compilation-unit scope so the functional submodules share one copy.
`include "psg_common.svh"

// The functional submodules. Every consumer of the PSG composes it with a
// single `include "psg.sv"` (chip.sv, target_psg.sv), so the module set has
// to arrive through this file; each is include-guarded, so listing one
// explicitly alongside psg.sv stays harmless.
`include "psg_timing.sv"
`include "psg_aram.sv"
`include "psg_mulsvc.sv"
`include "psg_divsvc.sv"
`include "psg_state_mem.sv"
`include "psg_wave.sv"
`include "psg_walk.sv"
`include "psg_seq.sv"

module psg #(parameter CLK_HZ = 32'd3_506_580, parameter REVERB = 1,
             parameter REALTIME_PREVIEW = 0, parameter DBG_PORT = 1)
          (input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           output logic signed [15:0] pcm,
           // Verification only: per-channel state for the simulator's
           // --psg-trace. Nothing on hardware reads it, so DBG_PORT=0
           // removes the cone that drives it rather than relying on the
           // synthesiser to notice the port is unconnected - which also
           // stops it constraining what the per-slot state may become
           // (it is the only reader that ever wanted four slots at once).
           // Exists because there was no way to tell whether an audio
           // fidelity complaint was allocation, sequencing or synthesis
           // without seeing inside.
           output logic [63:0] dbg);

  // ------------------------------------------------------------------
  // Timing: 22050 Hz virtual sample rate, sequencer tick every 183
  // ------------------------------------------------------------------
  // All five strobes come from u_timing (rtl/psg_timing.sv), which owns the
  // fractional divider and the sample counter.
  //
  // pre_tick fires one sample before tick_en (task 3.0): the tick program
  // EVALUATES during the preceding sample interval into the inactive bank,
  // and the boundary edge itself only flips spar_bank. That hands the tick
  // microprogram a full sample interval instead of sharing the boundary
  // sample's 1,275 clocks with synthesis. A CPU write landing inside the
  // pre-run window is observed one tick evaluation later than before -
  // accepted deliberately, see design section 3.
  //
  // tick_en has no RTL consumer: the sequencer runs off pre_tick and
  // tick_en_d. It stays because psg_tb measures the tick window with it.
  logic        sample_en;
  logic [7:0]  scnt;
  logic        tick_en, tick_en_d;
  logic        pre_tick;

  psg_timing #(.CLK_HZ(CLK_HZ)) u_timing(
    .clk(clk), .reset(reset),
    .sample_en(sample_en), .tick_en(tick_en), .tick_en_d(tick_en_d),
    .pre_tick(pre_tick), .scnt(scnt));

  // Audio RAM read port, shared: u_aram (rtl/psg_aram.sv) owns the array and
  // the borrow/replay contract; these are the wires the two requesters and
  // the freeze aggregation below need.
  wire  [12:0] seq_addr;
  wire  [7:0]  seq_q;
  wire         syn_rd;
  wire  [12:0] syn_addr;
  wire         seq_frozen;
  // u_state's export: the sequencer's synchronous read was displaced by a
  // sample and has to be re-issued.
  wire         state_replay;
  // The walk-freeze contract itself, and the reason it is formed HERE: its
  // four terms come from three different owners (u_aram's borrow, u_walk's
  // sample pass and fold chain, u_state's replay), so the top level is the
  // only place that can see all of them. Every consumer reads it from here.
  wire         prun, fold_busy;
  wire         walk_frozen = seq_frozen | prun | state_replay | fold_busy;

  psg_aram u_aram(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  // ------------------------------------------------------------------
  // The shared services: one multiplier, one divider, both in their own
  // modules (u_mul, u_div). Requesters keep their request selection; these
  // are the response wires the consume steps read.
  // ------------------------------------------------------------------
  wire  [31:0] m_res;
  wire  [33:0] m_res_wide;
  wire  [27:0] m_res12;
  wire         m_busy;

  // The divider's request comes from the sequencer alone, so there is no
  // merge to make: div_start / div_n / div_d go straight to u_div.
  wire         div_start;
  logic [23:0] div_n;
  logic [7:0]  div_d;
  wire  [23:0] d_res;
  wire  [7:0]  d_rem;
  wire         d_busy;

  psg_divsvc u_div(
    .clk(clk), .reset(reset),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy));

  // The store, and the fixed sample-walk-first priority between the two
  // owner bundles above.
  psg_state_mem u_state(
    .clk(clk), .reset(reset),
    .wlk_rd(state_sample_read), .wlk_ra(wlk_ra),
    .wlk_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .prun(prun), .state_replay(state_replay), .state_q(state_q));

  // ---- the per-sample synthesis walk ---------------------------------
  // u_walk (rtl/psg_walk.sv) runs one pass over the eight slots per sample.
  // It owns prun and pph - the signals the freeze contract is written
  // against - and every streaming oscillator register.
  psg_walk #(.REVERB(REVERB), .REALTIME_PREVIEW(REALTIME_PREVIEW)) u_walk(
    .clk(clk), .reset(reset), .sample_en(sample_en),
    .play_bits(play_bits), .mus_playing(mus_playing),
    .spar_bank(spar_bank), .clr_tog(clr_tog), .clr_ack(clr_ack),
    .seq_q(seq_q), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .state_q(state_q),
    .state_sample_read(state_sample_read), .wlk_ra(wlk_ra),
    .state_sample_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .m_res(m_res), .m_res_wide(m_res_wide), .m_res12(m_res12),
    .m_busy(m_busy),
    .wmul_start(wmul_start), .wmul_a(wmul_a), .wmul_b(wmul_b),
    .wmul_mode(wmul_mode),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase(s_phase), .s_phase2(s_phase2),
    .s_eff_inc(s_eff_inc), .s_old_wave(s_old_wave),
    .s_old_phase(s_old_phase), .s_old_inc(s_old_inc),
    .old_mode_r(old_mode_r), .old_alt_r(old_alt_r), .old_q0(old_q0),
    .z_eval(z_eval), .dq17(dq17), .q16(q16),
    .prun(prun), .fold_busy(fold_busy),
    .dry16(dry16), .dry_valid(dry_valid));

  // The walk's own wires: its state_m owner bundle, its multiply request,
  // the wave-layer context, and the two terms it contributes to the freeze.
  wire        state_sample_read, state_sample_we;
  wire [PSG_VADR-1:0] wlk_ra, wlk_wa;
  wire [15:0] wlk_wd;
  wire        wmul_start;
  wire signed [24:0] wmul_a;
  wire [11:0] wmul_b;
  wire [1:0]  wmul_mode;
  wire        iss_sec, iss_om, iss_os, dq_old_ctx;
  wire [2:0]  s_snd_wave, s_old_wave;
  wire        s_snd_wt, s_ch_buzz;
  wire [1:0]  s_ch_det, old_mode_r;
  wire        old_alt_r;
  wire [23:0] s_phase, s_phase2, s_old_phase;
  wire [20:0] s_eff_inc, s_old_inc;
  wire [16:0] old_q0;
  wire [PSG_NV-1:0] clr_ack;
  wire signed [15:0] dry16;
  wire        dry_valid;

  // ---- the computed wave layer (adoption 2.2) ------------------------
  // One evaluation pipe serves the three per-visit reads: main (issued at
  // PWORK, captured +1), secondary q view (issued +1, captured +2), old
  // continuation (issued +2, captured +3). Phase/wave/flags register at
  // issue; the cone evaluates during the following cycle. Every constant
  // multiply is a proven reciprocal form (psg_hw_forms) - yosys lowers
  // them to the priced CSD adder networks; the fabric has no DSP.
  //
  // u_walk supplies the evaluation context and the live/old voice fields;
  // u_wave returns the three values the walk consumes.
  psg_wave #(.REALTIME_PREVIEW(REALTIME_PREVIEW)) u_wave(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase_hi(s_phase[23:8]), .s_phase2(s_phase2),
    .s_eff_inc_hi(s_eff_inc[20:8]),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase[23:8]),
    .s_old_inc_hi(s_old_inc[20:8]), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0[15:0]),
    .z_eval(z_eval), .dq17(dq17), .q16(q16));

  wire signed [17:0] z_eval;
  wire [16:0] dq17;
  wire [15:0] q16;

  // The service's single request port. The two bundles are DISJOINT, not
  // merely prioritised - the walk arm needs `prun`, the sequencer arm needs
  // `!walk_frozen`, and walk_frozen subsumes prun - and every arm in both
  // blocks writes its operands and its start bit together, so the silent
  // bundle is all-zero. A bitwise OR is therefore the exact merge, and the
  // one that costs nothing: a 40-bit selecting mux here measured +34 cells
  // against the anchor where the OR measures -8.
  //
  // The assertion is the guard on that argument: it is what makes a future
  // arm that sets an operand without its start bit, or an arm that escapes
  // the freeze contract, fail loudly in simulation instead of quietly
  // OR-ing two live requests together.
  wire        mul_start = wmul_start | smul_start;
  wire signed [24:0] mul_start_a = wmul_a | smul_a;
  wire [11:0] mul_start_b        = wmul_b | smul_b;
  wire [1:0]  mul_start_mode     = wmul_mode | smul_mode;
`ifndef SYNTHESIS
  always @(posedge clk) if (!reset && wmul_start && smul_start)
    $fatal(1, "psg: both multiply requesters asserted in the same cycle");
`endif

  psg_mulsvc u_mul(
    .clk(clk), .reset(reset),
    .mul_start(mul_start), .mul_start_a(mul_start_a),
    .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
    .m_res(m_res), .m_res_wide(m_res_wide), .m_res12(m_res12),
    .m_busy(m_busy));

  // ---- the tick sequencer --------------------------------------------
  // u_seq (rtl/psg_seq.sv) is the 120.49 Hz half: the FSM, the per-slot
  // note and instrument records, the effect microprogram, the music flow
  // and the CPU's control writes.
  psg_seq u_seq(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .play_bits(play_bits), .trig_req(trig_req),
    .aud_sfx_bits(aud_sfx_bits), .aud_row_bits(aud_row_bits),
    .mus_playing(mus_playing), .mus_pat(mus_pat), .mus_mask(mus_mask),
    .fade_len(fade_len),
    .sample_en(sample_en), .tick_en_d(tick_en_d), .pre_tick(pre_tick),
    .scnt(scnt),
    .walk_frozen(walk_frozen), .spar_bank(spar_bank),
    .clr_tog(clr_tog), .clr_ack(clr_ack), .bank_ready(bank_ready),
    .seq_addr(seq_addr), .seq_q(seq_q),
    .state_q(state_q), .state_replay(state_replay),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .m_res(m_res), .m_busy(m_busy),
    .smul_start(smul_start), .smul_a(smul_a), .smul_b(smul_b),
    .smul_mode(smul_mode),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy));

  // The sequencer's own wires: its record-store owner bundle, its multiply
  // request, the walk handshakes and the fields the CPU read mux answers
  // from. bank_ready has no RTL consumer outside u_seq - psg_tb measures the
  // tick pre-run's completion with it, the way it does with tick_en.
  wire [PSG_NV-1:0] play_bits, trig_req, clr_tog;
  wire [PSG_NCH*6-1:0] aud_sfx_bits;
  wire [PSG_NCH*5-1:0] aud_row_bits;
  wire        mus_playing, spar_bank, bank_ready;
  wire [5:0]  mus_pat;
  wire [3:0]  mus_mask;
  wire [7:0]  fade_len;
  wire [15:0] state_q;
  wire [PSG_VADR-1:0] etk_ra, etk_wa;
  wire [15:0] etk_wd;
  wire        etk_we;
  wire        smul_start;
  wire signed [24:0] smul_a;
  wire [11:0] smul_b;
  wire [1:0]  smul_mode;

  // Output stage: the mixed sum is the PCM - the adopted reverb is
  // per-voice, pre-mix (the rings above); the old shared post-mix
  // delay is gone.
  always_ff @(posedge clk) begin
    if (reset) pcm <= 16'sd0;
    else if (dry_valid) pcm <= dry16;
  end

  // ------------------------------------------------------------------
  // CPU interface: music mask and status reads
  // ------------------------------------------------------------------
  // Only the READ mux is left up here: the upload port ($00/$01/$02) is
  // u_aram's, because it writes the array and so owns the address register
  // that walks it, and every control write ($10-$1F, $20, $21, $22) is
  // u_seq's. What the mux needs are u_seq's status exports.
  always_ff @(posedge clk) begin
    if (reset) begin
      dout <= 0;
    end else if (cs && !rw) begin
      case (addr)
        // Bits 0-3 are the FOREGROUND slots, which is exactly what software
        // auto-pick wants: a channel is available for a sound effect whenever
        // its foreground slot is idle, regardless of the song. A pending
        // trigger (written this cycle, not yet serviced) already reads as busy,
        // so back-to-back sfx() calls never collide on the same channel.
        8'h03: dout <= {mus_playing, 3'b0,
                        play_bits[3:0] | trig_req[3:0]};
        8'h20: dout <= {2'b0, mus_pat};
        // Low nibble: the channels the cart reserved, as written. High nibble
        // now reads 0 and is retained only so the register keeps its shape.
        //
        // It used to report the channels the song occupied, because software
        // auto-pick had to steer around them. With a music slot per channel
        // there is nothing to steer around: every foreground slot is always
        // available to a sound effect, whatever the song is doing. Reporting
        // occupancy here would make unmodified software refuse channels that
        // are in fact free, so it deliberately reports none.
        8'h21: dout <= {4'b0, mus_mask};
        8'h22: dout <= fade_len;
        default:
          if (addr[7:4] == 4'h1)
            // $10-$13 report the row, $14-$17 the SFX. Both answer for the
            // AUDIBLE slot of the channel - the foreground effect if one is
            // playing, otherwise the song underneath it - which is the
            // ownership state a cart can actually observe.
            dout <= (addr[3:2] == 2'd1)
                      ? {play_bits[aud_sl(addr[1:0], play_bits)], 1'b0,
                         aud_sfx_bits[addr[1:0]*6 +: 6]}
                      : {play_bits[aud_sl(addr[1:0], play_bits)], 2'b0,
                         aud_row_bits[addr[1:0]*5 +: 5]};
          else
            dout <= 8'h00;
      endcase
    end
  end
  // {music, pattern, foreground playing, music playing, per-channel sfx/row}.
  // The sfx/row fields report the audible slot, so --psg-trace keeps its
  // four-channel shape and tools/p8_music_trace.py comparisons still work;
  // dbg[15:12] now says which channels are hearing the song rather than which
  // are "owned" by it, which under the pairing is the same question.
  generate
  if (DBG_PORT) begin : g_dbg
    always_comb begin
      dbg = 64'b0;
      dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
      dbg[11:8]  = play_bits[3:0];
      dbg[15:12] = play_bits[7:4];
      for (int ch = 0; ch < PSG_NCH; ch++) begin
        dbg[16 + ch*6 +: 6] = aud_sfx_bits[ch*6 +: 6];
        dbg[40 + ch*6 +: 6] = {1'b0, aud_row_bits[ch*5 +: 5]};
      end
    end
  end else begin : g_no_dbg
    always_comb dbg = 64'b0;
  end
  endgenerate

endmodule

// This file is `include'd by chip.sv and the synthesis targets; keep the
// record-layout macros psg_common.svh defines from leaking into whatever is
// compiled after it. Undefining them here rather than in the header is
// deliberate: they have to survive every submodule include above, and this
// is the one place that is past all of them.
`undef PSG_REC_W3
`undef PSG_REC_W4
`undef PSG_REC_W5
`undef PSG_REC_W9
`undef PSG_OSC_W14
`undef PSG_OSC_W17
`undef PSG_OSC_W22
