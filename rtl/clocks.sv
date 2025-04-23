module clocks(input bit clk, output bit reset, output bit masterclk, output bit videoclk, output bit cpuclk);
  // Use synchronized reset with longer period
  logic [7:0] reset_counter = 8'hFF;  // Start with reset active
  
  always_ff @(posedge clk) begin
    if (reset_counter != 0) begin
      reset_counter <= reset_counter - 1;
      if (reset_counter == 1) begin
        $display("Clocks: Reset period complete. CPU should now start execution.");
      end
    end
  end
  
  // For simulation, use a single clock domain
  assign reset = (reset_counter != 0);  // Reset active during counter period
  assign masterclk = clk;
  assign videoclk = clk;
  assign cpuclk = clk;
endmodule 
