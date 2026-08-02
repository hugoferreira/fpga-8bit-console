`timescale 1ns/1ps

module pcm_trace_telemetry_tb;
  logic clk = 0;
  logic reset = 1;
  logic enable = 0;
  logic commit = 0;
  logic signed [15:0] pcm = 0;
  logic [63:0] debug;
  logic [63:0] debug_skip;

  always #5 clk = ~clk;

  pcm_trace_telemetry #(.WORD_COUNT(6), .PAGE_CYCLES(20)) dut(.*);
  pcm_trace_telemetry #(
    .WORD_COUNT(3), .START_WORD(4), .PAGE_BASE(1), .PAGE_CYCLES(20)
  ) dut_skip(
    .clk, .reset, .enable, .commit, .pcm, .debug(debug_skip));

  task automatic send(input logic signed [15:0] value);
    @(negedge clk);
    pcm = value;
    commit = 1;
    @(negedge clk);
    commit = 0;
  endtask

  initial begin
    repeat (3) @(negedge clk);
    reset = 0;
    enable = 1;

    send(16'sd0);
    send(16'sh1234);
    send(-16'sd2);
    send(16'sd0);
    send(16'sh7fff);
    send(-16'sd32768);
    send(16'sd42);

    if (debug !== 64'ha500_1234_fffe_0000) begin
      $error("page 0 mismatch: %016x", debug);
      $fatal;
    end
    if (debug_skip !== 64'ha501_7fff_8000_002a) begin
      $error("offset window mismatch: %016x", debug_skip);
      $fatal;
    end

    while (debug[55:48] != 8'd1) @(negedge clk);
    if (debug !== 64'ha501_7fff_8000_002a) begin
      $error("page 1 mismatch: %016x", debug);
      $fatal;
    end

    while (debug[55:48] != 8'd0) @(negedge clk);
    if (debug !== 64'ha500_1234_fffe_0000) begin
      $error("page wrap mismatch: %016x", debug);
      $fatal;
    end

    enable = 0;
    @(negedge clk);
    if (debug !== 64'ha500_0000_0000_0000) begin
      $error("disable reset mismatch: %016x", debug);
      $fatal;
    end
    if (debug_skip !== 64'ha501_0000_0000_0000) begin
      $error("offset disable reset mismatch: %016x", debug_skip);
      $fatal;
    end

    $display("PASS: exact PCM trace capture and paging");
    $finish;
  end
endmodule
