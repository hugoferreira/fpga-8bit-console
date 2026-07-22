// Memory Arbiter Module
// Controls access to memory between CPU and video components
// Implements VBLANK-based memory access control and CPU halting

/* verilator lint_off UNSIGNED */

module memory_arbiter(
  input logic clk,            // System clock
  input logic reset,          // System reset
  input logic vsync,          // Vertical sync signal
  
  // CPU interface
  input  logic [15:0] cpu_addr,     // CPU address bus
  input  logic cpu_write,           // CPU write signal (1=write, 0=read)
  input  logic [7:0] cpu_data_out,  // Data from CPU to memory
  output logic [7:0] cpu_data_in,   // Data from memory to CPU
  output logic cpu_rdy,             // CPU ready signal (1=ready, 0=halt)
  
  // Memory interfaces
  output logic ram_cs,              // RAM chip select
  output logic tb_cs,               // Tilemap chip select ($F000 window)
  output logic sp_cs,               // PPU register chip select
  output logic ovl_cs,              // Overlay chip select ($E000 window)
  output logic [15:0] mem_addr,     // Memory address bus
  output logic mem_write,           // Memory write signal
  output logic [7:0] mem_data_out,  // Data to memory
  input  logic [7:0] ram_data_in,   // Data from RAM
  input  logic [7:0] tb_data_in,    // Data from text buffer
  input  logic [7:0] sp_data_in,    // Data from sprites
  
  // DMA interface
  output logic dma_active,          // DMA is active (CPU is halted)
  input  logic dma_request,         // DMA requests access to memory
  input  logic [15:0] dma_addr,     // DMA address bus
  input  logic dma_write,           // DMA write signal
  input  logic [7:0] dma_data_out   // Data from DMA to memory
);

  // VBLANK detection
  logic vblank;
  logic vsync_prev;
  
  // Store previous values for edge detection in debug
  logic vblank_prev;
  logic cpu_rdy_prev;

  // Initialize all state at reset
  always_ff @(posedge clk) begin
    if (reset) begin
      // Initialize all state
      vsync_prev <= 0;
      vblank <= 0;
      vblank_prev <= 0;
      cpu_rdy_prev <= 1;  // CPU starts ready
      
      // Output debug message
      $display("Memory Arbiter: Reset - initializing all state");
    end else begin
      vsync_prev <= vsync;
      
      // VBLANK starts on falling edge of VSYNC
      if (vsync_prev && !vsync) begin
        vblank <= 1;
      end
      
      // DMA request completes VBLANK
      if (vblank && !dma_request) begin
        vblank <= 0;
      end
      
      // Store previous values for edge detection
      vblank_prev <= vblank;
      cpu_rdy_prev <= cpu_rdy;
      
      // Debug information
      if (vblank && !vblank_prev) $display("Memory Arbiter: VBLANK started");
      if (!vblank && vblank_prev) $display("Memory Arbiter: VBLANK ended");
      if (!cpu_rdy) $display("Memory Arbiter: CPU halted (RDY=0)");
      if (cpu_rdy && !cpu_rdy_prev) $display("Memory Arbiter: CPU resumed (RDY=1)");
    end
  end
  
  // Determine CPU ready state
  // Halt the CPU only while DMA actually owns the bus. Halting on vblank
  // itself glitched RDY for one cycle every frame even with DMA idle, and
  // the Arlet core does not support RDY stalls during write cycles - a
  // vsync-paced program streams register writes right after vblank, so the
  // stall landed mid-write and eventually derailed the CPU (PC ended up in
  // empty memory). Note the same limitation applies when DMA is re-enabled:
  // dma_request must not assert while the CPU may be mid-write.
  assign cpu_rdy = !dma_active;
  assign dma_active = dma_request && vblank;
  
  // Memory bus multiplexing
  // Select between CPU and DMA for memory access
  always_comb begin
    if (reset) begin
      // During reset, drive default values
      mem_addr = 16'h0000;
      mem_write = 0;      // Read during reset
      mem_data_out = 8'h00;
    end else if (dma_active) begin
      // DMA has control of memory bus during VBLANK
      mem_addr = dma_addr;
      mem_write = dma_write;
      mem_data_out = dma_data_out;
    end else begin
      // CPU has control of memory bus during normal operation
      mem_addr = cpu_addr;
      mem_write = cpu_write;
      mem_data_out = cpu_data_out;
    end
  end
  
  // Memory chip select logic
  // This determines which memory is being accessed
  always_comb begin
    // Default: nothing selected
    ram_cs = 0;
    tb_cs = 0;
    sp_cs = 0;
    ovl_cs = 0;
    
    if (!reset) begin  // Don't assert chip selects during reset
      // Address decoding - use the same memory map as in addressdecoder.sv
      if ((mem_addr < 16'h1000) || (mem_addr >= 16'hFFFA)) begin
        // RAM and vectors - rewritten to avoid >= 16'h0000 warning
        ram_cs = 1;
      end else if (mem_addr >= 16'hF000 && mem_addr < 16'hF800) begin
        // Text buffer (character and attribute RAM)
        tb_cs = 1;
      end else if (mem_addr >= 16'h4000 && mem_addr < 16'h4100) begin
        // PPU registers
        sp_cs = 1;
      end else if (mem_addr >= 16'hE000 && mem_addr < 16'hEA00) begin
        // Overlay bitmap (write-only)
        ovl_cs = 1;
      end
    end
  end
  
  // CPU data input multiplexing
  // All memories register their read data, so it corresponds to the address
  // issued one cycle earlier. The mux select must therefore be the REGISTERED
  // chip-select from that same cycle. Using the live chip-selects here also
  // created a combinational loop (cpu_addr -> cs -> cpu_data_in -> Arlet AB
  // -> cpu_addr) that made Verilator's settle loop diverge.
  logic ram_sel_q, tb_sel_q, sp_sel_q;
  always_ff @(posedge clk) begin
    if (reset) begin
      ram_sel_q <= 0;
      tb_sel_q <= 0;
      sp_sel_q <= 0;
    end else begin
      ram_sel_q <= ram_cs;
      tb_sel_q <= tb_cs;
      sp_sel_q <= sp_cs;
    end
  end

  always_comb begin
    if (reset) begin
      // During reset, drive valid data for all reset vector reads
      cpu_data_in = 8'h00;
    end else if (ram_sel_q) begin
      cpu_data_in = ram_data_in;
    end else if (tb_sel_q) begin
      cpu_data_in = tb_data_in;
    end else if (sp_sel_q) begin
      cpu_data_in = sp_data_in;
    end else begin
      cpu_data_in = 8'hFF; // Default to FF for undriven bus
    end
  end

endmodule

/* verilator lint_on UNSIGNED */ 