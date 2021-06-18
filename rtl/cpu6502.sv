 /*
 * SystemVerilog model of 6502 CPU.
 *
 * (C) Hugo Sereno, <bytter@gmail.com>
 *
 * Feel free to use this code in any project (commercial or not), as long as you
 * keep this message, and the copyright notice. This code is provided "as is", 
 * without any warranties of any kind. 
 * 
 * Note that this is a "functional" model for embedding 6502 code; the timings 
 * and undocumented opcodes will probably not match a real 6502, which will 
 * probably render it unsuitable for emulation purposes.
 *
 */

module cpu6502(
  input  bit         clk,
  input  bit   	     reset,
  output logic [15:0] address,
  input  logic [7:0] data_in,
  output logic [7:0] data_out,
  output bit         write
);
  
  enum logic [3:0] { 
    S_RESET, 
    S_SELECT, 
    S_DECODE, 
    S_COMPUTE, 
    S_READ_PCL, 
    S_READ_PCH, 
    S_READ_REL, 
    S_READ_ABSL,
    S_READ_ABSH 
  } state;
  
  logic [15:0] PC;
  logic [7:0]  opcode;
  logic [7:0]  A;
  logic [7:0]  Y;
  logic [7:0]  _PCL;
  
  logic f_zero = (Y == 8'b0);
  
  always_ff @(posedge clk)
    if (reset) begin
      state <= 0;
      write <= 0;
      A <= 0;
      Y <= 0;
    end else begin
      case (state)
        // state 0: reset
        S_RESET: begin
          PC <= 16'h00;
          write <= 0;
          state <= S_SELECT;
        end

        // state 1: select opcode address
        S_SELECT: begin
          address <= PC;
          PC <= PC + 1;
          write <= 0;
          state <= S_DECODE;
        end
        
        // state 2: read/decode opcode
        S_DECODE: begin
          opcode <= data_in;
          casez(data_in)
            8'b11101010: begin	// NOP
              state <= S_SELECT;
            end
            8'b01001100: begin	// JMP
              PC <= PC + 1;
              address <= PC;
              state <= S_READ_PCL;
            end
            8'b11010000: begin	// BNE
              PC <= PC + 1;
              address <= PC;
              state <= S_READ_REL;
            end
            8'b10?01101: begin	// LDA, STA address
              PC <= PC + 1;
              address <= PC;
              state <= S_READ_ABSL;
            end
            8'b10100000: begin  // LDY immediate
              PC <= PC + 1;
              address <= PC;
              state <= S_COMPUTE;
            end
            8'b10001000: begin  // DEY implicit
              state <= S_COMPUTE;
            end
            8'b?1101001: begin 	// ADC, SBC immediate
              PC <= PC + 1;
              address <= PC;
              state <= S_COMPUTE;
            end
            default: state <= S_SELECT;
          endcase
        end

        // state 3: perform computation
        S_COMPUTE: begin
          casez(opcode) 
            8'b10101101: begin	// LDA address
              A <= data_in;
              state <= S_SELECT;
            end
            8'b10100000: begin  // LDY immediate
              Y <= data_in;
              state <= S_SELECT;              
            end
            8'b10001000: begin  // DEY immediate
              Y <= Y - 1;
              state <= S_SELECT;
            end
            8'b10001101: begin	// STA address
              write <= 1;
              data_out <= A;
              state <= S_SELECT;
            end
            8'b01101001: begin 	// ADC immediate
              A <= A + data_in;
              state <= S_SELECT;
            end
            8'b11101001: begin  // SBC immediate
              A <= A - data_in;
              state <= S_SELECT;
            end
             default: state <= S_SELECT;
          endcase
        end
        
        // state 4: read absolute address 
        S_READ_PCL: begin
          PC <= PC + 1;
          address <= PC;
          _PCL <= data_in;
          state <= S_READ_PCH;
        end

        S_READ_PCH: begin
          PC <= { _PCL, data_in };
          state <= S_DECODE;
        end
        
        S_READ_REL: begin
          if (f_zero == 0) begin
            PC[7:0] <= PC[7:0] + $signed(data_in);
            state <= S_DECODE;
          end else begin
            state <= S_SELECT;
          end
        end

        S_READ_ABSL: begin
          PC <= PC + 1;
          address <= PC;
          _PCL <= data_in;
          state <= S_READ_ABSH;
        end
        
        S_READ_ABSH: begin
          address <= { _PCL, data_in };
          state <= S_COMPUTE;
        end

        default: begin end
      endcase
    end
endmodule