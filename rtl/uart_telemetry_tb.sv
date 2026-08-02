`timescale 1ns/1ps

module uart_telemetry_tb;
  localparam integer CLK_HZ = 1_000_000;
  localparam integer BAUD = 100_000;
  localparam integer BIT_CLKS = CLK_HZ / BAUD;

  logic clk = 1'b0;
  logic reset = 1'b1;
  logic [4:0] state = 5'h17;
  logic [7:0] flags = 8'ha5;
  logic [12:0] index = 13'h1234;
  logic [7:0] data = 8'hbc;
  logic [1:0] failure_stage = 2'd2;
  logic [31:0] pcm_signature = 32'h89abcdef;
  logic [12:0] pcm_count = 13'h0123;
  logic pcm_done = 1'b1;
  logic [63:0] psg_debug = 64'h0123456789abcdef;
  logic tx;

  always #1 clk = ~clk;

  uart_telemetry #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .REPORT_HZ(1000)) dut(
    .clk, .reset, .state, .flags, .index, .data, .failure_stage,
    .pcm_signature, .pcm_count, .pcm_done, .psg_debug, .tx);

  task automatic receive_byte(output logic [7:0] value);
    integer i;
    begin
      @(negedge tx);
      // Move from the start-bit edge to the center of data bit zero.
      repeat (BIT_CLKS + BIT_CLKS/2) @(posedge clk);
      for (i = 0; i < 8; i = i + 1) begin
        value[i] = tx;
        repeat (BIT_CLKS) @(posedge clk);
      end
      if (tx !== 1'b1) begin
        $error("UART stop bit is not high");
        $fatal;
      end
    end
  endtask

  logic [7:0] expected [0:67];
  logic [7:0] got;
  integer i;

  initial begin
    expected[0] = "S"; expected[1] = "="; expected[2] = "1";
    expected[3] = "7"; expected[4] = " "; expected[5] = "F";
    expected[6] = "="; expected[7] = "A"; expected[8] = "5";
    expected[9] = " "; expected[10] = "I"; expected[11] = "=";
    expected[12] = "1"; expected[13] = "2"; expected[14] = "3";
    expected[15] = "4"; expected[16] = " "; expected[17] = "D";
    expected[18] = "="; expected[19] = "B"; expected[20] = "C";
    expected[21] = " "; expected[22] = "E"; expected[23] = "=";
    expected[24] = "2"; expected[25] = " "; expected[26] = "C";
    expected[27] = "="; expected[28] = "8"; expected[29] = "9";
    expected[30] = "A"; expected[31] = "B"; expected[32] = "C";
    expected[33] = "D"; expected[34] = "E"; expected[35] = "F";
    expected[36] = " "; expected[37] = "N"; expected[38] = "=";
    expected[39] = "0"; expected[40] = "1"; expected[41] = "2";
    expected[42] = "3"; expected[43] = " "; expected[44] = "V";
    expected[45] = "="; expected[46] = "1"; expected[47] = " ";
    expected[48] = "G"; expected[49] = "="; expected[50] = "0";
    expected[51] = "1"; expected[52] = "2"; expected[53] = "3";
    expected[54] = "4"; expected[55] = "5"; expected[56] = "6";
    expected[57] = "7"; expected[58] = "8"; expected[59] = "9";
    expected[60] = "A"; expected[61] = "B"; expected[62] = "C";
    expected[63] = "D"; expected[64] = "E"; expected[65] = "F";
    expected[66] = 8'h0d; expected[67] = 8'h0a;

    repeat (8) @(posedge clk);
    reset = 1'b0;

    for (i = 0; i < 68; i = i + 1) begin
      receive_byte(got);
      if (got !== expected[i]) begin
        $error("telemetry byte %0d read %02x, expected %02x",
               i, got, expected[i]);
        $fatal;
      end
      // A transmitted line must retain its initial snapshot.
      if (i == 0) begin
        state = 0;
        flags = 0;
        index = 0;
        data = 0;
        failure_stage = 0;
        pcm_signature = 0;
        pcm_count = 0;
        pcm_done = 0;
        psg_debug = 0;
      end
    end

    $display("PASS: UART telemetry decoded exact stable ASCII snapshot");
    $finish;
  end
endmodule
