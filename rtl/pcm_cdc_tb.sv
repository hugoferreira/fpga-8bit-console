`timescale 1ns/1ps

module pcm_cdc_tb;
  logic src_clk = 1'b0;
  logic dst_clk = 1'b0;
  logic reset = 1'b1;
  logic signed [15:0] src_pcm = '0;
  logic signed [15:0] dst_pcm;

  pcm_cdc dut(.*);

  always #3 src_clk = ~src_clk;
  always #1 dst_clk = ~dst_clk;

  logic signed [15:0] old_word;
  logic signed [15:0] next_word;
  logic pending = 1'b0;

  always @(posedge dst_clk) begin
    if (!reset && pending && dst_pcm !== old_word && dst_pcm !== next_word) begin
      $error("CDC exposed mixed word %04x between %04x and %04x",
             dst_pcm, old_word, next_word);
      $fatal;
    end
  end

  task automatic transfer(input logic signed [15:0] value);
    integer timeout;
    begin
      @(negedge src_clk);
      old_word = dst_pcm;
      next_word = value;
      pending = 1'b1;
      src_pcm = value;
      timeout = 0;
      while (dst_pcm !== value && timeout < 20) begin
        @(posedge dst_clk);
        timeout = timeout + 1;
      end
      if (dst_pcm !== value) begin
        $error("CDC timed out transferring %04x; got %04x", value, dst_pcm);
        $fatal;
      end
      pending = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge dst_clk);
    reset = 1'b0;
    transfer(16'sh1234);
    transfer(-16'sh2345);
    transfer(16'sh7f01);
    transfer(16'sh0000);
    $display("PASS: PCM CDC transfers exact stable signed words");
    $finish;
  end
endmodule
