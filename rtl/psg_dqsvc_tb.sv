`timescale 1ns/1ps

module psg_dqsvc_tb;
  bit clk = 0;
  bit reset = 1;
  always #5 clk = ~clk;

  logic start = 0;
  logic ce = 1;
  logic [12:0] live_a = 0;
  logic [12:0] old_a = 0;
  logic [8:0] start_k = 0;
  logic start_old = 0;
  logic [13:0] result;
  logic done, busy, start_ready;
  logic [26:0] saved_p;
  logic [2:0] saved_count;
  logic [13:0] saved_result;
  logic saved_busy, saved_done, saved_ready;

  psg_dqsvc_core dut(
    .clk(clk), .reset(reset), .ce(ce),
    .start(start), .live_a(live_a), .old_a(old_a),
    .start_k(start_k), .start_old(start_old),
    .result(result), .done(done),
    .busy(busy), .start_ready(start_ready));

  task automatic launch(input logic [12:0] a,
                        input logic [8:0] k);
    while (!start_ready) @(negedge clk);
    live_a = a;
    start_k = k;
    start_old = 1'b0;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
  endtask

  task automatic await_result(input logic [12:0] a,
                              input logic [8:0] k);
    logic [21:0] expected_product;
    while (!done) @(negedge clk);
    expected_product = a * k;
    if (result !== expected_product[21:8])
      $fatal(1,
             "dq mismatch a=%0d k=%0d: got %0d expected %0d",
             a, k, result, expected_product[21:8]);
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
        launch(13'(aval), 9'(coeffs[kidx]));
        await_result(13'(aval), 9'(coeffs[kidx]));
      end
    end

    // Exercise the terminal-cycle handoff used by phases 19 and 24.
    launch(13'd8191, 9'd508);
    while (!(done && busy && start_ready)) @(negedge clk);
    if (result !== 14'd16254)
      $fatal(1, "dq chained first result mismatch: got %0d", result);
    old_a = 13'd7331;
    start_k = 9'd193;
    start_old = 1'b1;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    await_result(13'd7331, 9'd193);

    // With no following request, the terminal recurrence remains the result
    // store until the walker consumes the old-voice value five phases later.
    repeat (5) begin
      @(negedge clk);
      if (busy || done || result !== 14'd5526)
        $fatal(1, "dq idle result did not hold: busy=%0b done=%0b result=%0d",
               busy, done, result);
    end

    // Freeze each nonterminal recurrence state and the terminal chained
    // handoff.  The core must neither age nor accept a new request while its
    // executor is held, and must resume on the exact interrupted step.
    for (int freeze_count = 5; freeze_count > 0; freeze_count--) begin
      launch(13'(16'h123 + freeze_count), 9'(coeffs[freeze_count]));
      while (dut.count != 3'(freeze_count)) @(negedge clk);
      saved_p = dut.p;
      saved_count = dut.count;
      saved_result = result;
      saved_busy = busy;
      saved_done = done;
      saved_ready = start_ready;
      ce = 1'b0;
      start = 1'b1;
      repeat (3) begin
        @(negedge clk);
        if (dut.p !== saved_p || dut.count !== saved_count
            || result !== saved_result || busy !== saved_busy
            || done !== saved_done || start_ready !== saved_ready)
          $fatal(1, "dq hold aged state count=%0d", freeze_count);
      end
      start = 1'b0;
      ce = 1'b1;
      await_result(13'(16'h123 + freeze_count),
                   9'(coeffs[freeze_count]));
    end

    $display("psg_dqsvc_tb: PASS (57,344 exhaustive + chained + held transactions)");
    $finish;
  end
endmodule
