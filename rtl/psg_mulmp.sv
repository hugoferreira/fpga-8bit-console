// Related-clock, closed-loop multi-pumped PSG multiplier.
//
// The request/result buses are bundled multi-cycle paths: the PSG domain
// captures them before toggling req and keeps them stable until the returned
// acknowledge has passed through two synchronizer stages. Only the toggle
// bits are synchronized independently. The fast domain may therefore use the
// stable request payload directly and hold m_p as the result until the next
// transaction. Timing constraints must cut the protected cross-domain paths
// while retaining the fast m_p -> m_p recurrence at 112.5 MHz.

`ifndef PSG_MULMP_SV
`define PSG_MULMP_SV

module psg_mulmp_core #(parameter int RADIX_BITS = 1) (
    input  bit                 clk,
    input  bit                 fastclk,
    input  bit                 reset,
    input  logic               freeze,

    input  logic               mul_start,
    input  logic signed [24:0] mul_start_a,
    input  logic [11:0]        mul_start_b,
    input  logic [1:0]         mul_start_mode,
    input  logic               mul_start_short,

    output logic [33:0]        m_res,
    output logic               m_busy,
    output logic               m_seq_busy
);

  initial begin
    if (RADIX_BITS != 1 && RADIX_BITS != 2)
      $error("psg_mulmp: RADIX_BITS must be 1 or 2");
  end

  // Slow-domain contract for the six-fast-clocks-per-PSG-clock boundary. The
  // result is consumed only after the returned
  // acknowledge: normal requests are safe at launch+5, short requests at
  // launch+4. Keep these named values source-visible so schedule tooling and
  // the transaction bench verify the same CDC contract.
  localparam int NORMAL_CONSUME_GAP = 5;
  localparam int SHORT_CONSUME_GAP  = 4;

  // Source-domain transaction storage. req_a is stable for the complete
  // transaction, so the fast recurrence needs no duplicate A flop bank. req_b
  // is the initial 13-bit
  // multiplier field (mode 3 uses B<<1 only in radix 4), and req_steps is the
  // exact number of fast iterations.
  logic [17:0] req_a;
  logic [12:0] req_b;
  logic [3:0]  req_steps;
  logic        req_tgl;
  logic [2:0]  seq_pad;

  logic ack_tgl;
  (* async_reg = "true" *) logic ack_meta, ack_sync;
  (* async_reg = "true" *) logic req_meta, req_sync;

  assign m_busy     = req_tgl != ack_sync;
  assign m_seq_busy = m_busy || (seq_pad != 0);

  always_ff @(posedge clk) begin
    if (reset) begin
      req_tgl  <= 1'b0;
      ack_meta <= 1'b0;
      ack_sync <= 1'b0;
      seq_pad  <= 3'd0;
    end else if (!freeze) begin
      ack_meta <= ack_tgl;
      ack_sync <= ack_meta;

      if (seq_pad != 0)
        seq_pad <= seq_pad - 1'b1;

      if (mul_start) begin
        // Convert A to magnitude once at the transaction boundary. Every live
        // request is signed-18-bit-or-narrower; callers retain the sign.
        req_a <= mul_start_a[24] ? (18'd0 - mul_start_a[17:0])
                                 : mul_start_a[17:0];

        if (RADIX_BITS == 2 && mul_start_mode == 2'd3
                            && !mul_start_short)
          req_b <= {mul_start_b, 1'b0};
        else
          req_b <= {1'b0, mul_start_b};

        if (RADIX_BITS == 2)
          req_steps <= mul_start_short ? 4'd3
                     : (mul_start_mode == 2'd2) ? 4'd6
                     : (mul_start_mode == 2'd1) ? 4'd5
                     : (mul_start_mode == 2'd3) ? 4'd5
                     : 4'd4;
        else
          req_steps <= mul_start_short ? 4'd6
                     : (mul_start_mode == 2'd2) ? 4'd12
                     : (mul_start_mode == 2'd1) ? 4'd10
                     : (mul_start_mode == 2'd3) ? 4'd9
                     : 4'd8;

        // Present a fixed radix-4-equivalent busy duration to the sequencer.
        // The true acknowledge may arrive earlier but never later.
        seq_pad <= mul_start_short ? 3'd3
                 : (mul_start_mode == 2'd2) ? 3'd6
                 : (mul_start_mode == 2'd1) ? 3'd5
                 : (mul_start_mode == 2'd3) ? 3'd5
                 : 3'd4;
        req_tgl <= ~req_tgl;
      end
    end
  end

  logic [33:0] m_p;
  logic [3:0]  m_cnt;

  // Radix-2 recurrence: one multiplier bit per fast clock.
  wire [18:0] r2_acc  = m_p[30:12];
  wire [19:0] r2_sum  = {1'b0, r2_acc}
                      + (m_p[0] ? {2'b0, req_a} : 20'd0);
  wire [33:0] r2_next = {3'b0, r2_sum, m_p[11:1]};

  // Radix-4 consumes two multiplier bits per fast clock. RADIX_BITS selects it
  // through the same request/acknowledge boundary as the radix-2 recurrence,
  // so both modes share transaction storage and CDC timing.
  wire [18:0] r4_acc = m_p[30:12];
  wire [1:0]  r4_d   = m_p[1:0];
  wire [19:0] r4_add = (r4_d == 2'd0) ? 20'd0
                     : (r4_d == 2'd1) ? {2'b0, req_a}
                     : (r4_d == 2'd2) ? {1'b0, req_a, 1'b0}
                     :                   ({2'b0, req_a}
                                        + {1'b0, req_a, 1'b0});
  wire [20:0] r4_sum  = {2'b0, r4_acc} + {1'b0, r4_add};
  wire [33:0] r4_next = {3'b0, r4_sum, m_p[11:2]};

  wire [33:0] step_next = (RADIX_BITS == 2) ? r4_next : r2_next;

  assign m_res = m_p;

  always_ff @(posedge fastclk) begin
    if (reset) begin
      req_meta <= 1'b0;
      req_sync <= 1'b0;
      ack_tgl  <= 1'b0;
      m_cnt    <= 4'd0;
    end else if (!freeze) begin
      req_meta <= req_tgl;
      req_sync <= req_meta;

      if (m_cnt != 0) begin
        m_p <= step_next;
        if (m_cnt == 1) begin
          m_cnt   <= 4'd0;
          ack_tgl <= req_sync;
        end else begin
          m_cnt <= m_cnt - 1'b1;
        end
      end else if (req_sync != ack_tgl) begin
        m_p   <= {21'b0, req_b};
        m_cnt <= req_steps;
      end
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (!reset && !freeze && mul_start && m_busy)
      $fatal(1, "psg_mulmp: request while a transaction is outstanding");
    if (!reset && !freeze && seq_pad == 0 && m_busy)
      $fatal(1, "psg_mulmp: true result missed the padded sequencer deadline");
  end
`endif

endmodule

// Always-enabled adapter for the top-level PSG. Hold-aware composition uses
// the core directly so both clock domains freeze at one transaction boundary.
// Consume-gap constants remain visible to schedule tooling and tests.
module psg_mulmp #(parameter int RADIX_BITS = 1) (
    input  bit                 clk,
    input  bit                 fastclk,
    input  bit                 reset,

    input  logic               mul_start,
    input  logic signed [24:0] mul_start_a,
    input  logic [11:0]        mul_start_b,
    input  logic [1:0]         mul_start_mode,
    input  logic               mul_start_short,

    output logic [33:0]        m_res,
    output logic               m_busy,
    output logic               m_seq_busy
);
  localparam int NORMAL_CONSUME_GAP = 5;
  localparam int SHORT_CONSUME_GAP  = 4;

  psg_mulmp_core #(.RADIX_BITS(RADIX_BITS)) u_core(
    .clk(clk), .fastclk(fastclk), .reset(reset), .freeze(1'b0),
    .mul_start(mul_start), .mul_start_a(mul_start_a),
    .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
    .mul_start_short(mul_start_short), .m_res(m_res), .m_busy(m_busy),
    .m_seq_busy(m_seq_busy));
endmodule

`endif
