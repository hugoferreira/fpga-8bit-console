`timescale 1ns/1ps

module psg_dqsvc_tb;
  bit clk = 0;
  bit reset = 1;
  always #5 clk = ~clk;

  logic start = 0;
  logic [12:0] start_a = 0;
  logic [8:0] start_k = 0;
  logic start_tag = 0;
  logic [13:0] result;
  logic result_tag, done, busy, start_ready;

  psg_dqsvc dut(
    .clk(clk), .reset(reset),
    .start(start), .start_a(start_a), .start_k(start_k),
    .start_tag(start_tag),
    .result(result), .result_tag(result_tag), .done(done),
    .busy(busy), .start_ready(start_ready));

  task automatic launch(input logic [12:0] a,
                        input logic [8:0] k,
                        input logic tag);
    while (!start_ready) @(negedge clk);
    start_a = a;
    start_k = k;
    start_tag = tag;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
  endtask

  task automatic await_result(input logic [12:0] a,
                              input logic [8:0] k,
                              input logic tag);
    logic [21:0] expected_product;
    while (!done) @(negedge clk);
    expected_product = a * k;
    if (result !== expected_product[21:8] || result_tag !== tag)
      $fatal(1,
             "dq mismatch a=%0d k=%0d tag=%0b: got %0d/%0b expected %0d/%0b",
             a, k, tag, result, result_tag, expected_product[21:8], tag);
    while (done) @(negedge clk);
  endtask

  int coeffs[0:6] = '{193, 250, 254, 255, 256, 384, 508};
  int kidx;
  int aval;
  initial begin
    repeat (3) @(negedge clk);
    reset = 0;

    // Exhaust every reachable coefficient and 13-bit input.
    for (kidx = 0; kidx < 7; kidx++) begin
      for (aval = 0; aval < 8192; aval++) begin
        launch(13'(aval), 9'(coeffs[kidx]), aval[0]);
        await_result(13'(aval), 9'(coeffs[kidx]), aval[0]);
      end
    end

    // Exercise the terminal-cycle handoff used by phases 19 and 24.
    launch(13'd8191, 9'd508, 1'b0);
    while (!(busy && start_ready)) @(negedge clk);
    start_a = 13'd7331;
    start_k = 9'd193;
    start_tag = 1'b1;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    await_result(13'd8191, 9'd508, 1'b0);
    await_result(13'd7331, 9'd193, 1'b1);

    $display("psg_dqsvc_tb: PASS (57,344 exhaustive + chained transactions)");
    $finish;
  end
endmodule
