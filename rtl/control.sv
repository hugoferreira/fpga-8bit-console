module control(input bit clk, input bit reset, input bit vsync, 
               output logic [15:0] addr, output logic [7:0] data, 
               input logic [7:0] din, output bit rw);

  logic [7:0] letter;
  logic [3:0] color;
  logic [7:0] pos;
  logic [2:0] state;
  
  always_ff @(posedge clk)
  begin
    if (reset) begin
      state   <= 0;
      rw      <= 0;
      letter  <= 0;
      color   <= 0;
    end else begin
      if (vsync) begin
        if (state != 3'b110) state <= state + 1;

        // Update Character RAM
        case (state) 
          3'b000: begin
            addr <= 16'h0000;
            rw <= 0;
          end
          3'b001: begin
            pos <= din;
          end
          3'b010: begin
            addr <= 16'hEFF8;
            pos <= pos - 1;
            data <= pos;
            rw <= 1;
          end
          3'b011: begin
            addr <= 16'hF003 + 16'h200;
            color <= color + 1;
            data <= { 4'b0000, color };
            rw <= 1;
          end 
          3'b100: begin
            addr <= 16'h0000;
            data <= pos;
            rw <= 1;
          end
          3'b101: begin
            addr <= 16'hF005;
            letter <= letter + 1;
            data <= letter;
            rw <= 1;
          end
          default: rw <= 0;
        endcase
      end else state <= 0;
    end
  end  
endmodule