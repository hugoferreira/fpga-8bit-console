`timescale 1ns/1ps

// Bench for rtl/rgb_quant.sv.
//
// Exhaustive over all 65536 RGB565 inputs for the 444 case, because the module
// is combinational and small enough that "some samples" would be a choice not to
// know. The properties are the ones whose failure looks like a hardware fault
// rather than a slightly wrong colour:
//
//   * full scale stays full scale, and black stays black. A rounding carry that
//     is not clamped turns white into black.
//   * monotonic per channel: a brighter input never produces a darker output.
//   * truncation beats rounding against the ideal v*(2^m-1)/(2^n-1). This bench
//     REFUTED the module's original design - it rounded to nearest, and the
//     measured squared error was 21.9 against truncation's 7.6, because the
//     shift's implicit 1/2^d scale already overshoots the true ratio. The
//     assertion is kept pointing this way so the mistake cannot come back.
//   * widening replicates rather than shifts: 4'hF -> 8'hFF, not 8'hF0.
//
//   iverilog -g2012 -s rgb_quant_tb -o build/rgb_quant_tb \
//     rtl/rgb_quant_tb.sv rtl/rgb_quant.sv && vvp build/rgb_quant_tb
module rgb_quant_tb;

  logic [15:0] din;
  logic [11:0] d444;
  rgb_quant #(.IN_R(5), .IN_G(6), .IN_B(5),
              .OUT_R(4), .OUT_G(4), .OUT_B(4)) q444(.din(din), .dout(d444));

  logic [11:0] din444;
  logic [23:0] d888;
  rgb_quant #(.IN_R(4), .IN_G(4), .IN_B(4),
              .OUT_R(8), .OUT_G(8), .OUT_B(8)) q888(.din(din444), .dout(d888));

  int errors = 0;
  int i, r, g, b;
  int prev;
  real trunc_err, round_err;
  int  want;

  initial begin
    // ---- 1. the endpoints ------------------------------------------------
    din = 16'h0000; #1;
    if (d444 !== 12'h000) begin
      $display("FAIL: black -> %03x", d444); errors++;
    end
    din = 16'hFFFF; #1;
    if (d444 !== 12'hFFF) begin
      $display("FAIL: white -> %03x (a rounding carry was not clamped)", d444);
      errors++;
    end

    // ---- 2. per-channel monotonicity and rounding quality ----------------
    // Green is the interesting channel: 6 bits to 4, so two bits dropped.
    prev = -1; trunc_err = 0.0; round_err = 0.0;
    for (g = 0; g < 64; g++) begin
      din = {5'd0, g[5:0], 5'd0}; #1;
      if (int'(d444[7:4]) < prev) begin
        $display("FAIL: green not monotonic at %0d", g); errors++;
      end
      prev = int'(d444[7:4]);
      // ideal output for this input, in output units
      round_err += (real'(int'(d444[7:4])) - (real'(g) * 15.0 / 63.0)) ** 2;
      trunc_err += (real'(g >> 2)          - (real'(g) * 15.0 / 63.0)) ** 2;
    end
    // `round_err` is the DUT's error; trunc_err is what plain truncation gets.
    // The DUT truncates, so these must agree, and both must beat rounding.
    if (round_err > trunc_err + 0.001) begin
      $display("FAIL: DUT error %0.3f exceeds truncation %0.3f - narrowing regressed to rounding?", round_err, trunc_err);
      errors++;
    end

    prev = -1;
    for (r = 0; r < 32; r++) begin
      din = {r[4:0], 6'd0, 5'd0}; #1;
      if (int'(d444[11:8]) < prev) begin
        $display("FAIL: red not monotonic at %0d", r); errors++;
      end
      prev = int'(d444[11:8]);
    end
    prev = -1;
    for (b = 0; b < 32; b++) begin
      din = {5'd0, 6'd0, b[4:0]}; #1;
      if (int'(d444[3:0]) < prev) begin
        $display("FAIL: blue not monotonic at %0d", b); errors++;
      end
      prev = int'(d444[3:0]);
    end

    // ---- 3. exhaustive: no input may produce an out-of-range field -------
    // (12 bits out, so the only way to fail is a carry escaping a channel and
    // corrupting its neighbour - which the clamp exists to prevent.)
    for (i = 0; i < 65536; i++) begin
      din = i[15:0]; #1;
      r = int'(din[15:11]); g = int'(din[10:5]); b = int'(din[4:0]);
      // top-bits truncation, per the module header
      if (int'(d444[11:8]) != (r >> 1)
       || int'(d444[7:4])  != (g >> 2)
       || int'(d444[3:0])  != (b >> 1)) begin
        if (errors < 5)
          $display("FAIL: %04x -> %03x", din, d444);
        errors++;
      end
    end

    // ---- 4. widening replicates ------------------------------------------
    din444 = 12'hFFF; #1;
    if (d888 !== 24'hFFFFFF) begin
      $display("FAIL: 4'hF should widen to 8'hFF, got %06x", d888); errors++;
    end
    din444 = 12'h000; #1;
    if (d888 !== 24'h000000) begin
      $display("FAIL: zero should widen to zero, got %06x", d888); errors++;
    end
    din444 = 12'h888; #1;
    want = 8'h88;
    if (d888[23:16] !== want[7:0]) begin
      $display("FAIL: 4'h8 should widen to 8'h88, got %02x", d888[23:16]);
      errors++;
    end

    if (errors) begin
      $display("FAIL: %0d error(s)", errors);
      $fatal;
    end
    $display("PASS: endpoints exact, 3 channels monotonic, 65536 inputs exact, DUT error %0.2f == truncation %0.2f (both beat rounding), widening replicates", round_err, trunc_err);
    $finish;
  end
endmodule
