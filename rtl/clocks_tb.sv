`timescale 1ns/1ps

`include "clocks.sv"

module clocks_tb;
  bit clk = 0;
  always #5 clk = ~clk;

  bit reset4, master4, video4, cpu4, psg4;
  bit reset5, master5, video5, cpu5, psg5;
  bit reset6, master6, video6, cpu6, psg6;

  clocks #(.PSGDIV(4)) div4(
    .clk, .reset(reset4), .masterclk(master4), .videoclk(video4),
    .cpuclk(cpu4), .psgclk(psg4));
  clocks #(.PSGDIV(5)) div5(
    .clk, .reset(reset5), .masterclk(master5), .videoclk(video5),
    .cpuclk(cpu5), .psgclk(psg5));
  clocks #(.PSGDIV(6)) div6(
    .clk, .reset(reset6), .masterclk(master6), .videoclk(video6),
    .cpuclk(cpu6), .psgclk(psg6));

  int rises4 = 0, rises5 = 0, rises6 = 0;
  int pos_count = 0, neg_count = 0;
  int last_rise4 = 0, last_rise5 = 0, last_rise6 = 0;
  int last_fall5 = 0, last_fall6 = 0;

  always @(posedge clk) pos_count++;
  always @(negedge clk) neg_count++;

  always @(posedge psg4) begin
    if (last_rise4 != 0 && pos_count - last_rise4 != 4)
      $fatal(1, "/4 period is %0d source clocks, expected 4",
             pos_count - last_rise4);
    last_rise4 = pos_count;
    rises4++;
  end

  always @(posedge psg5) begin
    if (clk !== 1'b0)
      $fatal(1, "/5 rising edge did not land on the PLL falling phase");
    if (last_rise5 != 0 && neg_count - last_rise5 != 5)
      $fatal(1, "/5 period is %0d source clocks, expected 5",
             neg_count - last_rise5);
    if (last_fall5 != 0 && neg_count - last_fall5 != 3)
      $fatal(1, "/5 low time is %0d source clocks, expected 3",
             neg_count - last_fall5);
    last_rise5 = neg_count;
    rises5++;
  end

  always @(negedge psg5) begin
    if (clk !== 1'b0)
      $fatal(1, "/5 falling edge did not land on the PLL falling phase");
    if (last_rise5 != 0 && neg_count - last_rise5 != 2)
      $fatal(1, "/5 high time is %0d source clocks, expected 2",
             neg_count - last_rise5);
    last_fall5 = neg_count;
  end

  always @(posedge psg6) begin
    if (clk !== 1'b0)
      $fatal(1, "/6 rising edge did not land on the PLL falling phase");
    if (last_rise6 != 0 && neg_count - last_rise6 != 6)
      $fatal(1, "/6 period is %0d source clocks, expected 6",
             neg_count - last_rise6);
    if (last_fall6 != 0 && neg_count - last_fall6 != 3)
      $fatal(1, "/6 low time is %0d source clocks, expected 3",
             neg_count - last_fall6);
    last_rise6 = neg_count;
    rises6++;
  end

  always @(negedge psg6) begin
    if (clk !== 1'b0)
      $fatal(1, "/6 falling edge did not land on the PLL falling phase");
    if (last_rise6 != 0 && neg_count - last_rise6 != 3)
      $fatal(1, "/6 high time is %0d source clocks, expected 3",
             neg_count - last_rise6);
    last_fall6 = neg_count;
  end

  initial begin
    wait (rises4 >= 20 && rises5 >= 20 && rises6 >= 20);
    if (master4 !== master5 || master5 !== master6 ||
        video4 !== video5 || video5 !== video6 ||
        cpu4 !== cpu5 || cpu5 !== cpu6)
      $fatal(1, "PSGDIV changed a CPU/video/master clock");
    $display("clocks_tb: /4, /5 and /6 periods, duty and phase PASS");
    $finish;
  end
endmodule
