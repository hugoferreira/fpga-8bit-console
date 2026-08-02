// Periodic ASCII state telemetry over an ordinary 8-N-1 UART.
//
// One stable snapshot is rendered as:
//   S=ss F=ff I=iiii D=dd E=e C=cccccccc N=nnnn V=v G=gggggggggggggggg\r\n
`ifndef UART_TELEMETRY_SV
`define UART_TELEMETRY_SV

module uart_telemetry #(
    parameter integer CLK_HZ = 18_750_000,
    parameter integer BAUD = 115200,
    parameter integer REPORT_HZ = 10
  ) (
    input  logic        clk,
    input  logic        reset,
    input  logic [4:0]  state,
    input  logic [7:0]  flags,
    input  logic [12:0] index,
    input  logic [7:0]  data,
    input  logic [1:0]  failure_stage,
    input  logic [31:0] pcm_signature,
    input  logic [12:0] pcm_count,
    input  logic        pcm_done,
    input  logic [63:0] psg_debug,
    output logic        tx
  );

  localparam integer INTERVAL = CLK_HZ / REPORT_HZ;
  localparam integer CW = $clog2(INTERVAL);

  logic [CW-1:0] count;
  logic [6:0] pos;
  logic sending;
  logic [4:0] state_q;
  logic [7:0] flags_q;
  logic [12:0] index_q;
  logic [7:0] data_q;
  logic [1:0] failure_q;
  logic [31:0] pcm_signature_q;
  logic [12:0] pcm_count_q;
  logic        pcm_done_q;
  logic [63:0] psg_debug_q;

  function automatic logic [7:0] hex_digit(input logic [3:0] value);
    if (value < 4'd10)
      hex_digit = 8'h30 + value;
    else
      hex_digit = 8'h41 + (value - 4'd10);
  endfunction

  logic [7:0] byte_data;
  always_comb begin
    byte_data = 8'h3f;
    case (pos)
      5'd0:  byte_data = "S";
      5'd1:  byte_data = "=";
      5'd2:  byte_data = hex_digit({3'b0, state_q[4]});
      5'd3:  byte_data = hex_digit(state_q[3:0]);
      5'd4:  byte_data = " ";
      5'd5:  byte_data = "F";
      5'd6:  byte_data = "=";
      5'd7:  byte_data = hex_digit(flags_q[7:4]);
      5'd8:  byte_data = hex_digit(flags_q[3:0]);
      5'd9:  byte_data = " ";
      5'd10: byte_data = "I";
      5'd11: byte_data = "=";
      5'd12: byte_data = hex_digit({3'b0, index_q[12]});
      5'd13: byte_data = hex_digit(index_q[11:8]);
      5'd14: byte_data = hex_digit(index_q[7:4]);
      5'd15: byte_data = hex_digit(index_q[3:0]);
      5'd16: byte_data = " ";
      5'd17: byte_data = "D";
      5'd18: byte_data = "=";
      5'd19: byte_data = hex_digit(data_q[7:4]);
      5'd20: byte_data = hex_digit(data_q[3:0]);
      5'd21: byte_data = " ";
      5'd22: byte_data = "E";
      5'd23: byte_data = "=";
      5'd24: byte_data = hex_digit({2'b0, failure_q});
      6'd25: byte_data = " ";
      6'd26: byte_data = "C";
      6'd27: byte_data = "=";
      6'd28: byte_data = hex_digit(pcm_signature_q[31:28]);
      6'd29: byte_data = hex_digit(pcm_signature_q[27:24]);
      6'd30: byte_data = hex_digit(pcm_signature_q[23:20]);
      6'd31: byte_data = hex_digit(pcm_signature_q[19:16]);
      6'd32: byte_data = hex_digit(pcm_signature_q[15:12]);
      6'd33: byte_data = hex_digit(pcm_signature_q[11:8]);
      6'd34: byte_data = hex_digit(pcm_signature_q[7:4]);
      6'd35: byte_data = hex_digit(pcm_signature_q[3:0]);
      6'd36: byte_data = " ";
      6'd37: byte_data = "N";
      6'd38: byte_data = "=";
      6'd39: byte_data = hex_digit({3'b0, pcm_count_q[12]});
      6'd40: byte_data = hex_digit(pcm_count_q[11:8]);
      6'd41: byte_data = hex_digit(pcm_count_q[7:4]);
      6'd42: byte_data = hex_digit(pcm_count_q[3:0]);
      6'd43: byte_data = " ";
      6'd44: byte_data = "V";
      6'd45: byte_data = "=";
      6'd46: byte_data = hex_digit({3'b0, pcm_done_q});
      6'd47: byte_data = " ";
      6'd48: byte_data = "G";
      6'd49: byte_data = "=";
      6'd50: byte_data = hex_digit(psg_debug_q[63:60]);
      6'd51: byte_data = hex_digit(psg_debug_q[59:56]);
      6'd52: byte_data = hex_digit(psg_debug_q[55:52]);
      6'd53: byte_data = hex_digit(psg_debug_q[51:48]);
      6'd54: byte_data = hex_digit(psg_debug_q[47:44]);
      6'd55: byte_data = hex_digit(psg_debug_q[43:40]);
      6'd56: byte_data = hex_digit(psg_debug_q[39:36]);
      6'd57: byte_data = hex_digit(psg_debug_q[35:32]);
      6'd58: byte_data = hex_digit(psg_debug_q[31:28]);
      6'd59: byte_data = hex_digit(psg_debug_q[27:24]);
      6'd60: byte_data = hex_digit(psg_debug_q[23:20]);
      6'd61: byte_data = hex_digit(psg_debug_q[19:16]);
      6'd62: byte_data = hex_digit(psg_debug_q[15:12]);
      6'd63: byte_data = hex_digit(psg_debug_q[11:8]);
      7'd64: byte_data = hex_digit(psg_debug_q[7:4]);
      7'd65: byte_data = hex_digit(psg_debug_q[3:0]);
      7'd66: byte_data = 8'h0d;
      7'd67: byte_data = 8'h0a;
      default: byte_data = 8'h3f;
    endcase
  end

  wire accepted;
  uart_tx #(.MAIN_CLK(CLK_HZ), .BAUD(BAUD)) tx0(
    .clk, .reset, .tx_req(sending), .tx_ready(accepted),
    .tx_data(byte_data), .uart_tx(tx));

  always_ff @(posedge clk) begin
    if (reset) begin
      // Trigger the first snapshot immediately when reset is released.
      count     <= CW'(INTERVAL - 1);
      pos       <= 0;
      sending   <= 1'b0;
      state_q   <= 0;
      flags_q   <= 0;
      index_q   <= 0;
      data_q    <= 0;
      failure_q <= 0;
      pcm_signature_q <= 0;
      pcm_count_q <= 0;
      pcm_done_q <= 0;
      psg_debug_q <= 0;
    end else if (sending) begin
      if (accepted) begin
        if (pos == 7'd67) begin
          pos     <= 0;
          sending <= 1'b0;
        end else begin
          pos <= pos + 1'b1;
        end
      end
    end else if (count == INTERVAL - 1) begin
      count     <= 0;
      pos       <= 0;
      sending   <= 1'b1;
      state_q   <= state;
      flags_q   <= flags;
      index_q   <= index;
      data_q    <= data;
      failure_q <= failure_stage;
      pcm_signature_q <= pcm_signature;
      pcm_count_q <= pcm_count;
      pcm_done_q <= pcm_done;
      psg_debug_q <= psg_debug;
    end else begin
      count <= count + 1'b1;
    end
  end
endmodule

`endif
