`timescale 1ns/1ps

module i2s_out_tb;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic signed [15:0] pcm = 16'sh1234;
  logic bclk, lrck, din;

  i2s_out #(.HALF(40), .ATTEN_SHIFT(2), .BOOST_50_PERCENT(1)) dut(
    .clk, .reset, .pcm, .bclk, .lrck, .din);

  always #1 clk = ~clk;

  integer clock_edges = 0;
  integer last_bclk_edge = -1;
  always @(posedge clk)
    clock_edges <= clock_edges + 1;

  always @(posedge bclk) begin
    if (!reset && last_bclk_edge >= 0 && clock_edges - last_bclk_edge != 80) begin
      $error("BCLK period is %0d serializer clocks, expected 80",
             clock_edges - last_bclk_edge);
      $fatal;
    end
    last_bclk_edge = clock_edges;
  end

  task automatic capture_frame(input logic signed [15:0] expected_word);
    logic [15:0] got_left, got_right;
    integer i;
    begin
      // Philips I2S changes LRCK one bit before the next word. The first
      // rising BCLK after the falling edge still samples the preceding
      // right-channel LSB; the following rising edge starts the left MSB.
      @(negedge lrck);
      @(posedge bclk);
      got_left = '0;
      for (i = 0; i < 16; i = i + 1) begin
        @(posedge bclk);
        got_left = {got_left[14:0], din};
      end
      got_right = '0;
      for (i = 0; i < 16; i = i + 1) begin
        @(posedge bclk);
        got_right = {got_right[14:0], din};
      end
      if (got_left !== expected_word || got_right !== expected_word) begin
        $error("decoded left=%04x right=%04x, expected %04x",
               got_left, got_right, expected_word);
        $fatal;
      end
    end
  endtask

  function automatic logic signed [15:0] expected_scaled(
      input logic signed [15:0] sample);
    logic signed [16:0] atten;
    begin
      atten = sample >>> 2;
      expected_scaled = (atten * 3) >>> 1;
    end
  endfunction

  initial begin
    repeat (12) @(posedge clk);
    reset = 1'b0;

    // The left slot takes the attenuated PCM sample and the right slot repeats
    // it. LRCK low is left and high is right for standard Philips I2S.
    capture_frame(expected_scaled(16'sh1234));

    pcm = -16'sh2345;
    capture_frame(expected_scaled(-16'sh2345));

    $display("PASS: 3/8-scale I2S frames decode exactly; BCLK=/80 and LRCK=BCLK/32");
    $finish;
  end
endmodule
