// PSG multiply service: the one shift-add multiplier the whole chip shares.
//
// Every product the effect unit and the synthesis walk need is a magnitude
// times a small unsigned multiplier, so one unit serves them all: 6/8/9/10/12
// iterations of a 23-bit add, against the ~1500 LUTs parallel array
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
                   input  logic        mul_start_short, // six steps
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
  logic [3:0]  m_cnt;
  // Reset contract: m_cnt is validity/control state and resets to idle.
  // m_a/m_p are datapath: every one is overwritten by the six-op program
  // before it is observed.

  // ONE accumulator boundary for every request. The mode used to move the
  // boundary WITH the iteration count so that each product landed at bit 0
  // regardless of how many steps it took - which meant this engine was the
  // same shift-add spelled four times: a 22-bit four-way mux on the read and
  // a 34-bit four-way mux on the write-back, both pure alignment.
  //
  // Fixing the boundary at 12 makes an N-step product land N steps short of
  // bottom, so its value is the exact product shifted LEFT by (12 - N):
  //
  //     m_p after N iterations = |A| * B * 2^(12-N)      (N = 6, 8, 9, 10, 12)
  //
  // proven over the whole |A| sweep by tools/psg_mul_model.py. Every call site
  // has a fixed iteration count, so its consumer's shift is a constant and the
  // compensation is WIRING - the slices below moved, no gate was added, and
  // every consumed value is bit-identical. The mode now names an iteration
  // count and nothing else; `mul_start_short` was already the same idea (six
  // steps at mode 1's boundary, landing four bits left), generalised here.
  //
  // The width still fits: |A| < 2^21 and a mode-N request contracts B < 2^N,
  // so |A|*B*2^(12-N) < 2^33 for every N.
  wire  [21:0] m_acc = m_p[33:12];
  wire  [22:0] m_sum = {1'b0, m_acc} + (m_p[0] ? {2'b0, m_a} : 23'd0);

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
      m_p   <= {m_sum, m_p[11:1]};
      m_cnt <= m_cnt - 1;
    end else if (mul_start) begin
      // The one place signs are stripped: requesters pass raw signed
      // values and keep their own saved sign for the consume step, so
      // the per-source magnitude networks retire. Truncation points are
      // unchanged - the product is formed and scaled in the magnitude
      // domain exactly as before.
      m_a    <= mul_start_a[24] ? (21'd0 - mul_start_a[20:0])
                                : mul_start_a[20:0];
      m_p    <= {22'b0, mul_start_b};
      m_cnt  <= mul_start_short ? 4'd6
              : (mul_start_mode == 2'd2) ? 4'd12
              : (mul_start_mode == 2'd1) ? 4'd10
              : (mul_start_mode == 2'd3) ? 4'd9
              : 4'd8;
    end
  end

endmodule

`endif
