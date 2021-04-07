module addressdecoder(input logic [15:0] addr, input logic rw, 
                      input logic [7:0] tb_do, input logic [7:0] sp_do, input logic [7:0] ram_do,  
                      output logic [7:0] cpu_di,
                      output logic tb_cs, output logic sp_cs, output logic ram_cs);

  function [7:0] p_do(input logic [2:0] peripheral);
    case (peripheral)
        3'b001  : p_do = ram_do;
        // 3'b010  : p_do = sp_do;
        3'b100  : p_do = tb_do;
        default : p_do = 8'b0;
    endcase
  endfunction

  assign cpu_di = p_do({ tb_oe, sp_oe, ram_oe });

  assign tb_cs  = addr[15:12] == 04'b1111;
  assign sp_cs  = addr[15:04] == 12'b1110_1111_1111;
  assign ram_cs = addr[15:12] == 04'b0000;

  logic tb_oe  = ~rw & tb_cs;
  logic sp_oe  = ~rw & sp_cs;
  logic ram_oe = ~rw & ram_cs;
endmodule
