module addressdecoder(
  input logic clk,        // Add clock input
  input logic [15:0] addr,
  input logic rw, 
  input logic [7:0] tb_do,
  input logic [7:0] sp_do,
  input logic [7:0] ram_do,  
  output logic [7:0] cpu_di,
  output logic tb_cs,
  output logic sp_cs,
  output logic ram_cs
);

  // Memory map:
  // $0000-$0FFF: Main RAM (4KB)
  // $1000-$1FFF: Reserved for future expansion
  // $2000-$2FFF: Reserved for future expansion
  // $3000-$3FFF: Reserved for future expansion
  // $4000-$40FF: Sprite RAM (256 bytes)
  // $4100-$4FFF: Reserved for future I/O
  // $5000-$EFFF: Reserved for future expansion
  // $F000-$F3FF: Text Buffer Character RAM (1KB)
  // $F400-$F7FF: Text Buffer Attribute RAM (1KB)
  // $F800-$FFFB: Reserved for future expansion
  // $FFFC-$FFFF: Vector area (4 bytes)

  // Compute chip select signals with non-overlapping regions
  wire vector_area = (addr >= 16'hFFFC);                        // $FFFC-$FFFF
  wire text_attr_area = (addr >= 16'hF400) && (addr < 16'hF800);  // $F400-$F7FF
  wire text_char_area = (addr >= 16'hF000) && (addr < 16'hF400);  // $F000-$F3FF
  wire sprite_area = (addr >= 16'h4000) && (addr < 16'h4100);     // $4000-$40FF
  wire ram_area = (addr < 16'h1000) ||                            // $0000-$0FFF
                 (addr >= 16'hFFFC);                              // Vectors

  // Register all outputs to avoid combinational loops
  always_ff @(posedge clk) begin
    // Assign chip selects
    tb_cs <= text_char_area || text_attr_area;  // Text buffer (character or attribute)
    sp_cs <= sprite_area;                       // Sprite RAM
    ram_cs <= ram_area;                         // Main RAM and vectors

    // Select the correct data output
    if (vector_area) begin
      // During vector reads, always select RAM data
      cpu_di <= ram_do;
    end
    else if (text_char_area && !rw) begin
      cpu_di <= tb_do;
    end
    else if (text_attr_area && !rw) begin
      cpu_di <= tb_do;
    end
    else if (sprite_area && !rw) begin
      cpu_di <= sp_do;
    end
    else if (ram_area && !rw) begin
      cpu_di <= ram_do;
    end
    else begin
      cpu_di <= 8'hFF; // Default to FF for undriven bus
    end
    
    /*
    if (vector_area) begin
      $display("Address Decoder: Vector access at $%04X (ram_cs=%b, rw=%b)", addr, ram_cs, rw);
    end
    if (text_char_area) begin
      $display("Address Decoder: Text character RAM access at $%04X", addr);
    end
    if (text_attr_area) begin
      $display("Address Decoder: Text attribute RAM access at $%04X", addr);
    end
    if (sprite_area) begin
      $display("Address Decoder: Sprite RAM access at $%04X", addr);
    end
    */
  end

endmodule
