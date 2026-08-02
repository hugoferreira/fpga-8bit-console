`timescale 1ns/1ps

module psg_aram_readback_tb;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic cs = 1'b0;
  logic rw = 1'b1;
  logic [7:0] addr = '0;
  logic [7:0] di = '0;
  logic [7:0] dout;
  logic signed [15:0] pcm;

  always #1 clk = ~clk;

  psg #(.CLK_HZ(18_750_000), .REVERB(0), .DBG_PORT(0),
        .SEQ_BUDGET(0), .MULTIPUMP(0)) dut(
    .clk, .fastclk(clk), .reset, .cs, .rw, .addr, .di, .dout, .pcm,
    .dbg());

  task automatic write_reg(input logic [7:0] a, input logic [7:0] d);
    begin
      @(negedge clk);
      addr = a;
      di = d;
      rw = 1'b1;
      cs = 1'b1;
      @(negedge clk);
      cs = 1'b0;
    end
  endtask

  task automatic read_audio(output logic [7:0] d);
    begin
      @(negedge clk);
      addr = 8'h02;
      rw = 1'b0;
      cs = 1'b1;
      @(negedge clk);
      cs = 1'b0;
      rw = 1'b1;
      // Audio RAM is synchronous; dout commits on the following rising edge.
      @(negedge clk);
      d = dout;
    end
  endtask

  task automatic set_audio_addr(input logic [15:0] a);
    begin
      write_reg(8'h00, a[7:0]);
      write_reg(8'h01, a[15:8]);
    end
  endtask

  logic [7:0] got;
  logic [7:0] expected [0:4607];
  integer i;

  initial begin
    for (i = 0; i < 4608; i = i + 1)
      expected[i] = 8'((i * 73) + (i >> 3) + 8'h5a);

    repeat (8) @(posedge clk);
    reset = 1'b0;

    set_audio_addr(16'h3100);
    for (i = 0; i < 4608; i = i + 1)
      write_reg(8'h02, expected[i]);

    // Change the bus data so the check cannot accidentally observe a shadow
    // of the most recent write rather than the inferred audio RAM itself.
    di = 8'h00;
    set_audio_addr(16'h3100);
    for (i = 0; i < 4608; i = i + 1) begin
      read_audio(got);
      if (got !== expected[i]) begin
        $error("audio RAM byte %0d read %02x, expected %02x",
               i, got, expected[i]);
        $fatal;
      end
    end

    $display("PASS: PSG bus verified all 4,608 actual audio-RAM bytes through $42ff");
    $finish;
  end
endmodule
