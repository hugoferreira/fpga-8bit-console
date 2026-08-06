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
  input  logic cpu_write_pend,      // ...the same, before the RDY gate
  input  logic [7:0] cpu_data_out,  // Data from CPU to memory
  output logic [7:0] cpu_data_in,   // Data from memory to CPU
  output logic cpu_rdy,             // CPU ready signal (1=ready, 0=halt)
  
  // Memory interfaces
  output logic ram_cs,              // RAM chip select
  output logic tb_cs,               // Tilemap chip select ($F000 window)
  output logic sp_cs,               // PPU register chip select
  output logic ovl_cs,              // Overlay chip select ($E000 window)
  output logic psg_cs,              // PSG chip select ($4100 window)
  output logic [15:0] mem_addr,     // Memory address bus
  output logic mem_write,           // Memory write signal
  // `mem_write` before the RDY gate. Identical to `mem_write` except while the
  // CPU is stalled, where `mem_write` reads 0 for a write that has not
  // committed yet and this holds the true intent. Only a slave that produces
  // RDY may use it - a write enable driven from this would commit repeatedly
  // for the whole stall. See rtl/cpu6502_core.sv's WE_PEND.
  output logic mem_write_pend,
  output logic [7:0] mem_data_out,  // Data to memory
  input  logic [7:0] ram_data_in,   // Data from RAM
  input  logic [7:0] tb_data_in,    // Data from text buffer
  input  logic [7:0] sp_data_in,    // Data from sprites
  input  logic [7:0] psg_data_in,   // Data from the PSG
  
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
    end
  end
  
  // Determine CPU ready state.
  //
  // Halt the CPU only while DMA actually owns the bus. Halting on vblank
  // itself glitched RDY for one cycle every frame even with DMA idle.
  //
  // The other half of this comment used to record a CPU limitation: the Arlet
  // core did not survive an RDY stall during a write, so a vsync-paced program
  // streaming register writes right after vblank had the stall land mid-write
  // and eventually derailed the PC. **That limitation is gone.** The core is
  // now rtl/cpu6502_core.sv, which holds every register on RDY, gates WE with
  // it, and latches the data bus so a stall cannot destroy a pending read;
  // 1,510,000 conformance cases pass with 5,470,098 stall cycles injected at
  // arbitrary points (`make test-65x02 STALL=3`).
  //
  // So `dma_active` no longer has to wait for vblank. It still does, because
  // letting DMA steal cycles mid-frame changes what the display sees and there
  // is no test covering DMA at all - refactor-cpu-core task 6.4 is the place
  // to make that change deliberately, with something watching.
  assign cpu_rdy = !dma_active;
  assign dma_active = dma_request && vblank;
  
  // Memory bus multiplexing
  // Select between CPU and DMA for memory access
  always_comb begin
    if (reset) begin
      // During reset, drive default values
      mem_addr = 16'h0000;
      mem_write = 0;      // Read during reset
      mem_write_pend = 0;
      mem_data_out = 8'h00;
    end else if (dma_active) begin
      // DMA has control of memory bus during VBLANK
      mem_addr = dma_addr;
      mem_write = dma_write;
      // The DMA is never stalled by RDY, so intent and gated value coincide.
      mem_write_pend = dma_write;
      mem_data_out = dma_data_out;
    end else begin
      // CPU has control of memory bus during normal operation
      mem_addr = cpu_addr;
      mem_write = cpu_write;
      mem_write_pend = cpu_write_pend;
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
    psg_cs = 0;
    
    if (!reset) begin  // Don't assert chip selects during reset
      // Device windows carved out of a 64KB RAM map. (The old decode only
      // exposed $0000-$0FFF of RAM, which silently open-bussed any program
      // larger than 4KB - the Breakout port's level data was the first
      // thing to cross the line.)
      if (mem_addr >= 16'h4000 && mem_addr < 16'h4100) begin
        // PPU registers
        sp_cs = 1;
      end else if (mem_addr >= 16'h4100 && mem_addr < 16'h4200) begin
        // PSG registers
        psg_cs = 1;
      end else if (mem_addr >= 16'hE000 && mem_addr < 16'hEA00) begin
        // Overlay bitmap (write-only)
        ovl_cs = 1;
      end else if (mem_addr >= 16'hF000 && mem_addr < 16'hF800) begin
        // Tilemap (write-only)
        tb_cs = 1;
      end else begin
        ram_cs = 1;
      end
    end
  end
  
  // CPU data input multiplexing
  // All memories register their read data, so it corresponds to the address
  // issued one cycle earlier. The mux select must therefore be the REGISTERED
  // chip-select from that same cycle. Using the live chip-selects here also
  // created a combinational loop (cpu_addr -> cs -> cpu_data_in -> the core's AB
  // -> cpu_addr) that made Verilator's settle loop diverge.
  logic ram_sel_q, tb_sel_q, sp_sel_q, psg_sel_q;
  always_ff @(posedge clk) begin
    if (reset) begin
      ram_sel_q <= 0;
      tb_sel_q <= 0;
      sp_sel_q <= 0;
      psg_sel_q <= 0;
    end else begin
      ram_sel_q <= ram_cs;
      tb_sel_q <= tb_cs;
      sp_sel_q <= sp_cs;
      psg_sel_q <= psg_cs;
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
    end else if (psg_sel_q) begin
      cpu_data_in = psg_data_in;
    end else begin
      cpu_data_in = 8'hFF; // Default to FF for undriven bus
    end
  end

endmodule

/* verilator lint_on UNSIGNED */ 