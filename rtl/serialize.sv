// Parameters ahead of the ports: the ports reference WIDTH, and declaring it
// afterwards is accepted by yosys and Verilator but not by iverilog, which is
// what the benches use. See the same note in rtl/lcd.sv.
module serialize #(parameter SCL_MODE = 1,
                   parameter WIDTH = 8)
                (input bit cin, input bit reset, input bit irdy,
                 input logic [WIDTH-1:0] data,
                 output bit sda, output bit scl, output bit ordy);

  localparam COUNTER_WIDTH = $clog2(WIDTH);
  localparam COUNTER_MAX = { COUNTER_WIDTH{1'b1} };
  
  logic [COUNTER_WIDTH-1:0] counter = COUNTER_MAX;

  assign sda = data[counter];
  assign scl = SCL_MODE ? (cin & ~ordy) : (~cin | ordy);
  
  always_ff @(posedge cin)
    begin
      if (reset) begin
        ordy <= 1;
        counter <= COUNTER_MAX;
      end
      else
        case (ordy)
          1: if (irdy) begin
              ordy <= 0;
              counter <= COUNTER_MAX;
             end

          0: if (counter == 0) ordy <= 1;
             else counter <= counter - 1;
        endcase
    end
endmodule