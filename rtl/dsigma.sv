// First-order delta-sigma modulator: turns the PSG's 16-bit signed PCM into a
// 1-bit density-coded stream at the master clock. An off-board RC low-pass
// reconstructs the analogue waveform (the average high-bit density over a
// window tracks the PCM level). One accumulator, no memory.
//
// 16 bits in, not 8: the modulator runs at the 25 MHz master clock against a
// 22050 Hz signal, an oversampling ratio of ~1134. A first-order modulator at
// that ratio carries on the order of 14 bits in the audio band, so feeding it
// 8 bits was throwing away resolution the output stage already had. That
// headroom is what lets the mixer use PICO-8's quarter-scale channels without
// the quiet notes collapsing - see docs/hardware-gaps.md.
module dsigma(input bit clk, input bit reset,
              input logic signed [15:0] pcm,
              output logic out);
  logic [16:0] acc;
  wire [15:0] u = pcm + 16'sh8000;      // signed -> unsigned for the accumulator
  always_ff @(posedge clk) begin
    if (reset) begin
      acc <= 17'd0;
      out <= 1'b0;
    end else begin
      acc <= {1'b0, acc[15:0]} + {1'b0, u};
      out <= acc[16];
    end
  end
endmodule
