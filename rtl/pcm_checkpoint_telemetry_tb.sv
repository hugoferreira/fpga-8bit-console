`timescale 1ns/1ps

module pcm_checkpoint_telemetry_tb;
  logic clk = 0;
  logic reset = 1;
  logic enable = 0;
  logic commit = 0;
  logic signed [15:0] pcm = 0;
  logic [63:0] debug;

  logic [31:0] expected [0:6];
  integer page_index;
  integer sample_index;

  always #5 clk = ~clk;

  pcm_checkpoint_telemetry #(.PAGE_CYCLES(20)) dut(.*);

  task automatic send(input logic signed [15:0] value);
    @(negedge clk);
    pcm = value;
    commit = 1;
    @(negedge clk);
    commit = 0;
  endtask

  function automatic logic [15:0] page_count(input integer index);
    case (index)
      0: page_count = 16'd64;
      1: page_count = 16'd128;
      2: page_count = 16'd256;
      3: page_count = 16'd512;
      4: page_count = 16'd1024;
      5: page_count = 16'd2048;
      default: page_count = 16'd4096;
    endcase
  endfunction

  initial begin
    expected[0] = 32'h27e93b30;
    expected[1] = 32'hc79adb43;
    expected[2] = 32'h310c2dd5;
    expected[3] = 32'h72f26e2b;
    expected[4] = 32'h0c4b1092;
    expected[5] = 32'h5c0340da;
    expected[6] = 32'h3b44279d;

    repeat (3) @(negedge clk);
    reset = 0;
    enable = 1;

    // Leading zero commits do not start the signature window.
    send(16'sd0);
    for (sample_index = 1; sample_index <= 4096; sample_index = sample_index + 1)
      send($signed(sample_index * 37 - 20000));

    for (page_index = 0; page_index < 7; page_index = page_index + 1) begin
      while (debug[54:48] != page_index[6:0]) @(negedge clk);
      if (debug[63:56] !== 8'ha6 || !debug[55] ||
          debug[47:32] !== page_count(page_index) ||
          debug[31:0] !== expected[page_index]) begin
        $error("page %0d mismatch: %016x", page_index, debug);
        $fatal;
      end
      @(negedge clk);
    end

    while (debug[54:48] != 7'd0) @(negedge clk);
    if (debug !== {8'ha6, 1'b1, 4'b0, 3'd0, 16'd64, expected[0]}) begin
      $error("page wrap mismatch: %016x", debug);
      $fatal;
    end

    enable = 0;
    @(negedge clk);
    if (debug !== {8'ha6, 1'b0, 4'b0, 3'd0, 16'd64, 32'b0}) begin
      $error("disable reset mismatch: %016x", debug);
      $fatal;
    end

    $display("PASS: rolling PCM checkpoint capture and paging");
    $finish;
  end
endmodule
