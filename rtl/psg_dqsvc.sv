// Visit-local secondary-increment service.
//
// Every PICO-8 detune form used by the full renderer is exactly
//
//     floor(K * dp / 256),
//
// where dp is 13 bits and K is one of 193, 250, 254, 255, 256, 384, or 508.
// One five-step radix-4 recurrence therefore replaces the parallel correction
// network. A new request may be accepted on the terminal step, allowing the
// live and preceding-voice transactions to occupy consecutive five-cycle
// windows without changing the sample schedule.

`ifndef PSG_DQSVC_SV
`define PSG_DQSVC_SV

module psg_dqsvc (
    input  bit          clk,
    input  bit          reset,
    input  logic        start,
    input  logic [12:0] live_a,
    input  logic [12:0] old_a,
    input  logic [8:0]  start_k,
    input  logic        start_old,
    output logic [13:0] result,
    output logic        done,
    output logic        busy,
    output logic        start_ready
);

  // Ten multiplier positions cover the nine-bit coefficient plus its leading
  // zero. The upper 14 bits hold the partial accumulator; three guard bits
  // carry the radix-4 sum before the combined register shifts by two.
  logic [26:0] p;
  logic [2:0]  count;

  wire [12:0] step_a = p[26] ? old_a : live_a;
  wire [13:0] acc = p[23:10];
  wire [1:0]  digit = p[1:0];
  wire [14:0] addend = (digit == 2'd0) ? 15'd0
                       : (digit == 2'd1) ? {2'b0, step_a}
                       : (digit == 2'd2) ? {1'b0, step_a, 1'b0}
                       : ({2'b0, step_a}
                          + {1'b0, step_a, 1'b0});
  wire [15:0] sum = {2'b0, acc} + {1'b0, addend};
  wire [26:0] step_next = {p[26], 2'b0, sum, p[9:2]};

  assign busy = count != 0;
  assign start_ready = count == 0 || count == 1;
  // The walker already owns the destination registers.  Present the terminal
  // recurrence directly so it can capture on this edge instead of registering
  // an otherwise unconsumed result and copying it one clock later.
  assign result = done ? step_next[21:8] : p[21:8];
  assign done = count == 1;

  always_ff @(posedge clk) begin
    if (reset) begin
      count <= 3'd0;
    end else begin
      if (count != 0) begin
        if (count == 1) begin
          if (start) begin
            p     <= {start_old, 16'b0, 1'b0, start_k};
            count <= 3'd5;
          end else begin
            p     <= step_next;
            count <= 3'd0;
          end
        end else begin
          p     <= step_next;
          count <= count - 1'b1;
        end
      end else if (start) begin
        p     <= {start_old, 16'b0, 1'b0, start_k};
        count <= 3'd5;
      end
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk)
    if (!reset && start && !start_ready)
      $fatal(1, "psg_dqsvc: request while service cannot accept one");
`endif

endmodule

`endif
