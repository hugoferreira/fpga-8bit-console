module addressdecoder(input logic [15:0] addr, input logic rw, 
                      input logic [7:0] tb_do, input logic [7:0] sp_do, input logic [7:0] ram_do,  
                      output logic [7:0] cpu_di,
                      output logic tb_cs, output logic sp_cs, output logic ram_cs);

  // First, compute the chip select signals
  assign tb_cs  = (addr[15:12] == 4'b1111) && !(addr[15:2] == 14'b11111111111111); // $F000-$FFFF except $FFFC-$FFFF
  assign sp_cs  = addr[15:12] == 4'b0100; // $4000-$4FFF
  assign ram_cs = (addr[15:12] == 4'b0000) || // $0000-$0FFF
                  (addr[15:2] == 14'b11111111111111); // $FFFC-$FFFF (reset/interrupt vectors)

  // Then compute output enables
  wire tb_oe  = ~rw & tb_cs;
  wire sp_oe  = ~rw & sp_cs;
  wire ram_oe = ~rw & ram_cs;

  // Finally, select the correct data output
  always @(*) begin
    if (tb_oe)
      cpu_di = tb_do;
    else if (sp_oe)
      cpu_di = sp_do;
    else if (ram_oe)
      cpu_di = ram_do;
    else
      cpu_di = 8'b0;
  end
endmodule
