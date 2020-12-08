module font_pico8(input [10:0] addr, output [7:0] data);
    reg  [3:0] font [0:2047];    
    wire [3:0] bits;
    assign bits = font[addr];
    assign data = { bits[3], bits[3], bits[2], bits[2], bits[1], bits[1], bits[0], bits[0] };

    initial $readmemh("font_pico8.hex", font);
endmodule