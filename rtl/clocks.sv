module clocks(input bit clk, output bit reset, output bit masterclk, output bit videoclk, output bit cpuclk);
  // Use a much shorter reset period for simulation
  logic [15:0] reset_counter = 16'hFFFF;  // Start with reset active
  logic reset_complete = 0;
  
  always_ff @(posedge clk) begin
    if (reset_counter != 0) begin
      reset_counter <= reset_counter - 1;
      
      // Print progress messages
      if (reset_counter == 16'hFFFF)
        $display("Clocks: Reset period starting.");
      else if (reset_counter == 16'h8000)
        $display("Clocks: Reset period 50%% complete.");
      else if (reset_counter == 16'h0100)
        $display("Clocks: Reset period 99%% complete.");
      else if (reset_counter == 1) begin
        $display("Clocks: Reset period complete. CPU should now start execution.");
        reset_complete <= 1;
      end
    end else if (reset_complete) begin
      // Reset is complete, print a message just once
      $display("Clocks: System running with clean clocks.");
      reset_complete <= 0;
    end
  end
  
  // For simulation, use a single clock domain
  assign reset = (reset_counter != 0);  // Reset active during counter period
  assign masterclk = clk;
  assign videoclk = clk;
  assign cpuclk = clk;
endmodule 
