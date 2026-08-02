`timescale 1ns/1ps

module pcm_signature_tb;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic enable = 1'b0;
  logic commit = 1'b0;
  logic signed [15:0] pcm = '0;
  logic [31:0] signature;
  logic [12:0] count;
  logic done;

  pcm_signature #(.WORD_COUNT(4)) dut(.*);
  always #1 clk = ~clk;

  task automatic send(input logic signed [15:0] word);
    begin
      @(negedge clk);
      pcm = word;
      commit = 1'b1;
      @(negedge clk);
      commit = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    reset = 1'b0;
    enable = 1'b1;

    send(16'sh0000); // ignored lead-in
    send(16'sh1234);
    send(-16'sh2345);
    send(16'sh7f01);
    send(16'sh0000); // counted after the signature starts
    repeat (2) @(posedge clk);

    if (!done || count != 13'd4 || signature != 32'he3fd7067) begin
      $error("signature done=%0d count=%0d value=%08x",
             done, count, signature);
      $fatal;
    end
    $display("PASS: committed PCM signature is exact");
    $finish;
  end
endmodule
