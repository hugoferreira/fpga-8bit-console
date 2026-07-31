// PSG multiply service: the one shift-add multiplier the whole chip shares.
//
// Every product the effect unit and the synthesis walk need is a magnitude
// times a small unsigned multiplier, so one unit serves them all: 8/10/12
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
                   output logic [31:0] m_res,
                   output logic [33:0] m_res_wide,
                   output logic [27:0] m_res12,
                   output logic        m_busy);

  // 21 bits, not 24: the widest |A| any arm supplies is base_inc, whose
  // pitch-table ceiling is 0x1CE0 << 8 = 1,892,352 < 2^21; the signed arms
  // peak at 18 bits. The accumulator and product register narrow with it
  // (products peak at 22 bits real, 33 structural).
  logic [20:0] m_a;
  logic [33:0] m_p;                  // accumulator plus 8/10/12-bit multiplier
  logic [3:0]  m_cnt;
  logic [1:0]  m_mode;
  // Reset contract: m_cnt is validity/control state and resets to idle.
  // m_a/m_p are datapath: every one is overwritten by the six-op program
  // before it is observed.
  wire  [21:0] m_acc = (m_mode == 2'd2) ? m_p[33:12]
                     : (m_mode == 2'd1) ? m_p[31:10]
                     : (m_mode == 2'd3) ? m_p[30:9] : m_p[29:8];
  wire  [22:0] m_sum = {1'b0, m_acc} + (m_p[0] ? {2'b0, m_a} : 23'd0);

  // m_res holds the product IN PLACE: bit k is product bit k. The
  // microinstruction contract's "volumes use m_res[15:8]" is a semantic Q8
  // scale, not a placement offset - reading a product from the wrong slice
  // shortens every music pattern and fires 44 oracle diagnostics.
  assign m_res      = m_p[31:0];
  assign m_res_wide = m_p[33:0];
  assign m_res12    = m_p[27:0];
  assign m_busy     = (m_cnt != 0);

  always_ff @(posedge clk) begin
    if (reset)
      m_cnt <= 0;
    else if (m_cnt != 0) begin
      m_p   <= (m_mode == 2'd2) ? {m_sum, m_p[11:1]}
             : (m_mode == 2'd1) ? {2'b0, m_sum, m_p[9:1]}
             : (m_mode == 2'd3) ? {3'b0, m_sum, m_p[8:1]}
                                : {4'b0, m_sum, m_p[7:1]};
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
      m_mode <= mul_start_mode;
      m_cnt  <= (mul_start_mode == 2'd2) ? 4'd12
              : (mul_start_mode == 2'd1) ? 4'd10
              : (mul_start_mode == 2'd3) ? 4'd9 : 4'd8;
    end
  end

endmodule

`endif
