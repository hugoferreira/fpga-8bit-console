// First-order delta-sigma modulator: turns the PSG's 8-bit unsigned PCM
// into a 1-bit density-coded stream at the master clock. An off-board RC
// low-pass reconstructs the analogue waveform (the average high-bit
// density over a window tracks the PCM level). One accumulator, no memory.
module dsigma(input bit clk, input bit reset,
              input logic [7:0] pcm,
              output logic out);
  logic [8:0] acc;
  always_ff @(posedge clk) begin
    if (reset) begin
      acc <= 9'd0;
      out <= 1'b0;
    end else begin
      acc <= {1'b0, acc[7:0]} + {1'b0, pcm};
      out <= acc[8];
    end
  end
endmodule
