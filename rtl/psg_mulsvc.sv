// Shared unsigned-magnitude radix-4 multiplier. Requesters provide signed A,
// retain its sign, and consume the magnitude returned in m_res.

`ifndef PSG_MULSVC_SV
`define PSG_MULSVC_SV

module psg_mulsvc (input  bit          clk,
                   input  bit          reset,

                   // One-cycle request; operands remain internal after launch.
                   input  logic        mul_start,
                   input  logic signed [24:0] mul_start_a,
                   input  logic [11:0] mul_start_b,
                   input  logic [1:0]  mul_start_mode,
                   input  logic        mul_start_short,

                   // Result view and busy flag derived from recurrence state.
                   output logic [33:0] m_res,
                   output logic        m_busy);

  // Every live request supplies a signed 18-bit-or-narrower A and B < 2^12.
  // m_res keeps its 34-bit public alignment; the upper three product bits are
  // constant zero under this tighter magnitude boundary.
  logic [17:0] m_a;
  logic [33:0] m_p;
  logic [2:0]  m_cnt;

  // m_p has a fixed 12-bit multiplier field. Each step consumes two low
  // multiplier bits and shifts the accumulated sum down by two.
  wire  [18:0] m_acc = m_p[30:12];

  wire  [1:0]  m_d   = m_p[1:0];
  wire  [19:0] m_add = (m_d == 2'd0) ? 20'd0
                     : (m_d == 2'd1) ? {2'b0, m_a}
                     : (m_d == 2'd2) ? {1'b0, m_a, 1'b0}
                     :                 ({2'b0, m_a} + {1'b0, m_a, 1'b0});
  wire  [20:0] m_sum = {2'b0, m_acc} + {1'b0, m_add};

  assign m_res  = m_p;
  assign m_busy = (m_cnt != 0);

  always_ff @(posedge clk) begin
    if (reset)
      m_cnt <= 0;
    else if (m_cnt != 0) begin
      m_p   <= {3'b0, m_sum, m_p[11:2]};
      m_cnt <= m_cnt - 1;
    end else if (mul_start) begin

      // Convert A to magnitude once; callers restore the saved sign.
      m_a    <= mul_start_a[24] ? (18'd0 - mul_start_a[17:0])
                                : mul_start_a[17:0];

      // Normal modes retire 8, 10, 9, or 12 effective multiplier bits.
      // Mode 3 pre-shifts its odd-width operand so five radix-4 steps retain
      // the same product alignment as the other request classes.
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
