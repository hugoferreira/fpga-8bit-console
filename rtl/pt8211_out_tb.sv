`timescale 1ns/1ps

// Framing check for rtl/pt8211_out.sv.
//
// The point of this bench is the one thing that cannot be eyeballed and that
// no board here can yet report: that the stream is LSB-JUSTIFIED and not
// Philips. It decodes exactly as a PT8211 does - sampling DIN on the FALLING
// edge of BCK, taking the 16 bits that follow the WS edge - and compares the
// word. A Philips stream (what rtl/i2s_out.sv emits) fails this bench, which is
// the check that matters: swap i2s_out in as the DUT and its WS-phase assertion
// trips first, and with that assertion removed 16'sh1234 decodes as 16'shdcbb.
// The one-BCK LRCK lead puts the decode window across a slot boundary, so what
// comes out is not a quiet sample or a slightly wrong one - it is unrelated.
//
//   iverilog -g2012 -s pt8211_out_tb -o build/pt8211_out_tb \
//     rtl/pt8211_out_tb.sv rtl/pt8211_out.sv && vvp build/pt8211_out_tb
module pt8211_out_tb;
  localparam int HALF = 40;

  logic clk = 1'b0;
  logic reset = 1'b1;
  logic signed [15:0] pcm = 16'sh1234;
  logic bck, ws, din;

  pt8211_out #(.HALF(HALF), .ATTEN_SHIFT(0)) dut(
    .clk, .reset, .pcm, .bck, .ws, .din);

  always #1 clk = ~clk;

  // BCK period, in serializer clocks, measured between rising edges.
  integer clock_edges = 0;
  integer last_bck_edge = -1;
  always @(posedge clk)
    clock_edges <= clock_edges + 1;

  always @(posedge bck) begin
    if (!reset && last_bck_edge >= 0
        && clock_edges - last_bck_edge != 2 * HALF) begin
      $error("BCK period is %0d serializer clocks, expected %0d",
             clock_edges - last_bck_edge, 2 * HALF);
      $fatal;
    end
    last_bck_edge = clock_edges;
  end

  // WS must move on the same clock as the MSB it selects, so counting BCK
  // periods between WS edges also proves the frame is 32 BCK with the split in
  // the middle.
  integer last_ws_edge = -1;
  integer ws_edges = 0;
  always @(ws) begin
    if (!reset) begin
      if (last_ws_edge >= 0
          && clock_edges - last_ws_edge != 16 * 2 * HALF) begin
        $error("WS half-period is %0d serializer clocks, expected %0d",
               clock_edges - last_ws_edge, 16 * 2 * HALF);
        $fatal;
      end
      last_ws_edge = clock_edges;
      ws_edges = ws_edges + 1;
    end
  end

  // Decode one frame the way the part does: DIN is sampled on the falling edge
  // of BCK, and the first such edge after WS moves carries the MSB. There is no
  // skipped bit here - that skip is exactly what makes Philips framing wrong
  // for this DAC.
  task automatic capture_frame(input logic signed [15:0] expected_word);
    logic [15:0] got_left, got_right;
    integer i;
    begin
      @(negedge ws);                       // start of the left slot
      got_left = '0;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge bck);
        got_left = {got_left[14:0], din};
      end
      got_right = '0;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge bck);
        got_right = {got_right[14:0], din};
      end
      if (got_left !== expected_word || got_right !== expected_word) begin
        $error("decoded left=%04x right=%04x, expected %04x",
               got_left, got_right, expected_word);
        $fatal;
      end
      // The right slot must have been the high half of WS throughout.
      if (ws !== 1'b1) begin
        $error("WS is %b at the end of the right slot, expected 1", ws);
        $fatal;
      end
    end
  endtask

  initial begin
    repeat (12) @(posedge clk);
    reset = 1'b0;

    // A frame is sampled one slot before it is sent, so the first full frame
    // after reset carries whatever `hold` had; skip it and check the next.
    capture_frame(16'sh1234);
    capture_frame(16'sh1234);

    pcm = -16'sh2345;
    // The sample is latched at slot 31 of the frame in flight, so the change
    // lands on the frame after the one currently going out.
    capture_frame(16'sh1234);
    capture_frame(-16'sh2345);

    if (ws_edges < 6) begin
      $error("only %0d WS edges seen, expected at least 6", ws_edges);
      $fatal;
    end

    $display("PASS: LSB-justified frames decode exactly; BCK=/%0d, WS=BCK/32",
             2 * HALF);
    $finish;
  end
endmodule
