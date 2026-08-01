// PSG multiply service: the one shift-add multiplier the whole chip shares.
//
// Every product the effect unit and the synthesis walk need is a magnitude
// times a small unsigned multiplier, so one unit serves them all: 3/4/5/6
// radix-4 steps of a 24-bit add, against the ~1500 LUTs parallel array
// multipliers cost. An effect evaluation runs six of them, four channels 120
// times a second - about 240 clocks in a tick.
//
// The requesters keep their own request selection and present ONE merged
// bundle here (psg.sv forms it from the walk's and the sequencer's bundles).
// This module owns nothing but the engine, which is the point: single
// instance, single write site, and the schedule that keeps the two
// requesters off each other lives with the requesters.
`ifndef PSG_MULSVC_SV
`define PSG_MULSVC_SV

module psg_mulsvc (input  bit          clk,
                   input  bit          reset,
                   // The merged request. `a` is raw signed; the service
                   // strips the sign, and each requester keeps its own saved
                   // sign for its consume step.
                   input  logic        mul_start,
                   input  logic signed [24:0] mul_start_a,
                   input  logic [11:0] mul_start_b,
                   input  logic [1:0]  mul_start_mode,  // 0: 8-bit B, 3: 9, 1: 10, 2: 12
                   input  logic        mul_start_short, // three steps
                   // ONE view of the accumulator. The three former ports
                   // (32/34/28 bits) were the same register sliced three ways,
                   // and picking the wrong one is the bug class the comments
                   // below keep warning about.
                   output logic [33:0] m_res,
                   output logic        m_busy);

  // 21 bits, not 24: the widest |A| any arm supplies is base_inc, whose
  // pitch-table ceiling is 0x1CE0 << 8 = 1,892,352 < 2^21; the signed arms
  // peak at 18 bits. The accumulator and product register narrow with it
  // (products peak at 22 bits real, 33 structural).
  logic [20:0] m_a;
  logic [33:0] m_p;                  // accumulator plus the 12-bit multiplier
  logic [2:0]  m_cnt;
  // Reset contract: m_cnt is validity/control state and resets to idle.
  // m_a/m_p are datapath: every one is overwritten by the six-op program
  // before it is observed.

  // ONE accumulator boundary for every request. The mode used to move the
  // boundary WITH the iteration count so that each product landed at bit 0
  // regardless of how many steps it took - which meant this engine was the
  // same shift-add spelled four times: a 22-bit four-way mux on the read and
  // a 34-bit four-way mux on the write-back, both pure alignment.
  //
  // Fixing the boundary at 12 makes a product land as many places short of
  // bottom as there are multiplier bits still unretired, so its value is the
  // exact product shifted LEFT by that count:
  //
  //     m_p after M steps = |A| * B * 2^(12 - RADIX_BITS*M)
  //
  // THAT IS WHAT MAKES THE RADIX FREE. A radix-4 step retires TWO multiplier
  // bits, so M = N/2 lands exactly where the radix-2 N-step request did and
  // NO consumer slice moves: 12->6, 10->5, 8->4, 6->3 steps. Mode 3's nine is
  // odd and has no exact half; loading `B << 1` for that one mode puts its
  // landing back, and mode 3's B < 2^9 contract leaves room for the shift.
  // Average latency falls 10.0 -> 5.6 cycles. Proven against the shipped
  // radix-2 engine, every mode, every corner B, the whole |A| sweep and both
  // signs, by tools/psg_mul_model.py.
  //
  // Every call site has a fixed step count, so its consumer's offset is a
  // constant and the compensation is WIRING - no gate was added and every
  // consumed value is bit-identical. The mode names a step count and nothing
  // else; `mul_start_short` was already the same idea, generalised here.
  //
  // The width still fits: |A| < 2^21 and a mode contracts B below its own
  // retired-bit count, so every landed product stays under 2^33.
  wire  [21:0] m_acc = m_p[33:12];
  // Two multiplier bits per step. 3A is COMBINATIONAL on purpose: registering
  // it costs 23 flops to save one adder, which measured both larger and
  // slower (282 LC / 99.7 MHz against 259 / 118.9 standalone).
  wire  [1:0]  m_d   = m_p[1:0];
  wire  [22:0] m_add = (m_d == 2'd0) ? 23'd0
                     : (m_d == 2'd1) ? {2'b0, m_a}
                     : (m_d == 2'd2) ? {1'b0, m_a, 1'b0}
                     :                 ({2'b0, m_a} + {1'b0, m_a, 1'b0});
  wire  [23:0] m_sum = {2'b0, m_acc} + {1'b0, m_add};

  // Bit k of m_res is bit k of the product shifted as above. The
  // microinstruction contract's "volumes use m_res[15:8]" is a semantic Q8
  // scale, not a placement offset - reading a product from the wrong slice
  // shortens every music pattern and fires 44 oracle diagnostics.
  assign m_res  = m_p;
  assign m_busy = (m_cnt != 0);

  always_ff @(posedge clk) begin
    if (reset)
      m_cnt <= 0;
    else if (m_cnt != 0) begin
      m_p   <= {m_sum, m_p[11:2]};
      m_cnt <= m_cnt - 1;
    end else if (mul_start) begin
      // The one place signs are stripped: requesters pass raw signed
      // values and keep their own saved sign for the consume step, so
      // the per-source magnitude networks retire. Truncation points are
      // unchanged - the product is formed and scaled in the magnitude
      // domain exactly as before.
      m_a    <= mul_start_a[24] ? (21'd0 - mul_start_a[20:0])
                                : mul_start_a[20:0];
      // Mode 3 alone loads B << 1; see the landing note above.
      m_p    <= (mul_start_mode == 2'd3 && !mul_start_short)
                  ? {21'b0, mul_start_b, 1'b0} : {22'b0, mul_start_b};
      m_cnt  <= mul_start_short ? 3'd3
              : (mul_start_mode == 2'd2) ? 3'd6
              : (mul_start_mode == 2'd1) ? 3'd5
              : (mul_start_mode == 2'd3) ? 3'd5
              : 3'd4;
    end
  end

endmodule

`endif
