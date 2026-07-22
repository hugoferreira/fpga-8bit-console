module textbuffer(input logic clk, input logic reset, 
                  input logic cs, input logic rw, input logic [$clog2(WIDTH*HEIGHT):0] addr, input logic [7:0] di, output logic [7:0] dout, 
                  input logic [7:0] hpos, input logic [6:0] vpos, input logic vsync, input logic hsync, 
                  output logic [3:0] color,
                  // New DMA interface
                  input logic dma_active,
                  input logic dma_write,
                  input logic [9:0] dma_addr,
                  input logic [7:0] dma_data);
  
  localparam WIDTH = 20, HEIGHT = 15;
  
  // Local dual-port memory for character and attribute data
  // Port A: CPU/DMA access
  // Port B: Video rendering
  logic [7:0] charram [0:(1<<9)-1];   // nomem2reg
  logic [7:0] attrram [0:(1<<9)-1];   // nomem2reg
  logic [7:0] fontrom [0:(1<<11)-1];  // nomem2reg

  initial $readmemh("./rtl/videoram.hex", charram);
  initial $readmemh("./rtl/attrram.hex",  attrram);
  initial $readmemh("./rtl/font_cp437_8x8.hex", fontrom);

  enum logic [1:0] { ram_addr, fetch_ram, fetch_rom, display } state;

  logic [$clog2(WIDTH*HEIGHT)-1:0] pos;
  logic [10:0] char;
  logic [7:0]  attr;
  logic [7:0]  bits;
  logic        sel;
  logic [8:0]  address;

  assign { sel, address } = addr;
  
  // Video rendering state machine - Port B of dual-port memory
  // This continues to run regardless of CPU or DMA activity
  always_ff @(posedge clk)
  begin
    if (reset) begin
      state <= ram_addr;
    end else begin
      case (state)
        ram_addr: state <= fetch_ram;
        fetch_ram: state <= fetch_rom;
        fetch_rom: state <= display;
        display: state <= ram_addr;
      endcase
      
      case (state)  
        ram_addr:  
          pos <= vpos[6:3] * 20 + { 4'b0000, hpos[7:3] };

        fetch_ram: 
        begin
          char <= { charram[pos], vpos[2:0] };
          attr <= attrram[pos];
        end

        fetch_rom: 
          bits <= fontrom[char];
        
        display: 
          color <= bits[~hpos[2:0]] ? attr[3:0] : attr[7:4];
      endcase
    end
  end

  // Memory access logic - Port A of dual-port memory
  // Handles both CPU and DMA access
  logic [7:0] read_attr, read_char;
  assign dout = sel ? read_attr : read_char;
  
  // Character RAM access
  always_ff @(posedge clk) begin
    // DMA write has priority over CPU access
    if (dma_active && dma_write && dma_addr[9] == 0) begin
      // DMA writing to character RAM (lower 512 bytes)
      charram[dma_addr[8:0]] <= dma_data;
      $display("TextBuffer DMA: Writing char 0x%02X to address 0x%03X", dma_data, dma_addr);
    end else if (cs & ~rw & ~sel) begin
      // CPU reading from character RAM
      read_char <= charram[address];
      $display("TextBuffer: CPU reading character at $%04X = %02X", address, charram[address]);
    end else if (cs & rw & ~sel) begin
      // CPU writing to character RAM
      charram[address] <= di;
      $display("TextBuffer: CPU writing character at $%04X = %02X", address, di);
    end
  end

  // Attribute RAM access
  always_ff @(posedge clk) begin
    // DMA write has priority over CPU access
    if (dma_active && dma_write && dma_addr[9] == 1) begin
      // DMA writing to attribute RAM (upper 512 bytes)
      attrram[dma_addr[8:0]] <= dma_data;
      $display("TextBuffer DMA: Writing attr 0x%02X to address 0x%03X", dma_data, dma_addr);
    end else if (cs & ~rw & sel) begin
      // CPU reading from attribute RAM
      read_attr <= attrram[address];
      $display("TextBuffer: CPU reading attribute at $%04X = %02X", address, attrram[address]);
    end else if (cs & rw & sel) begin
      // CPU writing to attribute RAM
      attrram[address] <= di;
      $display("TextBuffer: CPU writing attribute at $%04X = %02X", address, di);
    end
  end
endmodule