// DMA Controller Module
// Handles memory transfers between system RAM and local video memory during VBLANK
// Coordinates with memory arbiter to halt CPU during transfers

/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module dma_controller(
  input logic clk,            // System clock
  input logic reset,          // System reset
  input logic vblank_start,   // Start of VBLANK period
  
  // Memory arbiter interface
  output logic dma_request,         // Request memory access
  output logic [15:0] dma_addr,     // Memory address
  output logic dma_write,           // Write signal
  output logic [7:0] dma_data_out,  // Data to write
  input  logic [7:0] dma_data_in,   // Data read from memory
  input  logic dma_active,          // DMA is active
  
  // Text buffer interface
  output logic tb_dma_active,       // Text buffer DMA active
  output logic tb_dma_write,        // Text buffer DMA write
  output logic [9:0] tb_dma_addr,   // Text buffer address (10 bits)
  output logic [7:0] tb_dma_data,   // Data to text buffer
  
  // Sprite interface
  output logic sp_dma_active,       // Sprite DMA active
  output logic sp_dma_write,        // Sprite DMA write
  output logic [3:0] sp_dma_addr,   // Sprite address (4 bits)
  output logic [7:0] sp_dma_data    // Data to sprite
);

  parameter ENABLE_SHADOW_COPY = 0;

  // DMA state machine
  typedef enum {
    IDLE,            // Waiting for VBLANK
    TB_CHAR_SETUP,   // Setup for text buffer character RAM transfer
    TB_CHAR_READ,    // Read character data from system RAM
    TB_CHAR_WRITE,   // Write character data to text buffer
    TB_ATTR_SETUP,   // Setup for text buffer attribute RAM transfer
    TB_ATTR_READ,    // Read attribute data from system RAM
    TB_ATTR_WRITE,   // Write attribute data to text buffer
    SPRITE_SETUP,    // Setup for sprite data transfer
    SPRITE_READ,     // Read sprite data from system RAM
    SPRITE_WRITE,    // Write sprite data to sprite memory
    COMPLETE         // DMA complete
  } dma_state_t;
  
  dma_state_t state, next_state;
  
  // Transfer counters and addresses
  logic [10:0] tb_char_counter;  // Text buffer character transfer counter, now 11 bits to hold 1024
  logic [10:0] tb_attr_counter;  // Text buffer attribute transfer counter, now 11 bits to hold 1024
  logic [3:0] sprite_counter;   // Sprite transfer counter
  
  // Text buffer character and attribute RAM base addresses
  localparam TB_CHAR_BASE = 16'hF000;  // Text buffer character RAM
  localparam TB_ATTR_BASE = 16'hF400;  // Text buffer attribute RAM
  localparam SPRITE_BASE  = 16'h4000;  // Sprite registers
  
  // Constants for transfer sizes
  localparam TB_CHAR_SIZE = 11'd1024;  // 1KB character RAM (now 11 bits)
  localparam TB_ATTR_SIZE = 11'd1024;  // 1KB attribute RAM (now 11 bits)
  localparam SPRITE_SIZE  = 4'd10;     // 10 sprite registers
  
  // State machine
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
      dma_request <= 0;
      tb_char_counter <= 0;
      tb_attr_counter <= 0;
      sprite_counter <= 0;
      tb_dma_active <= 0;
      sp_dma_active <= 0;
    end else begin
      state <= next_state;
      
      // Handle VBLANK start
      // ENABLE_SHADOW_COPY: the vblank copy currently reads from $F000+/$4000+,
      // which the arbiter decodes back to the video devices themselves, not
      // system RAM - a self-copy that (via address truncation) zeroes the
      // attribute RAM every frame, blacking out all text. Disabled until the
      // copy sources from a real RAM shadow; the CPU writes these devices
      // directly through the arbiter in the meantime.
      if (ENABLE_SHADOW_COPY && vblank_start && state == IDLE) begin
        dma_request <= 1;
        tb_char_counter <= 0;
        tb_attr_counter <= 0;
        sprite_counter <= 0;
      end
      
      // Handle counter increments based on state
      case (state)
        TB_CHAR_WRITE: begin
          tb_char_counter <= tb_char_counter + 1;
          tb_dma_active <= 1;
        end
        
        TB_ATTR_WRITE: begin
          tb_attr_counter <= tb_attr_counter + 1;
          tb_dma_active <= 1;
        end
        
        SPRITE_WRITE: begin
          sprite_counter <= sprite_counter + 1;
          sp_dma_active <= 1;
        end
        
        COMPLETE: begin
          dma_request <= 0;
          tb_dma_active <= 0;
          sp_dma_active <= 0;
        end
        
        default: begin
          // Keep signals stable in other states
        end
      endcase
    end
  end
  
  // Next state logic
  always_comb begin
    // Default: stay in current state
    next_state = state;
    
    case (state)
      IDLE:
        if (ENABLE_SHADOW_COPY && vblank_start)
          next_state = TB_CHAR_SETUP;
      
      TB_CHAR_SETUP: 
        if (dma_active) 
          next_state = TB_CHAR_READ;
      
      TB_CHAR_READ: 
        next_state = TB_CHAR_WRITE;
      
      TB_CHAR_WRITE: 
        if (tb_char_counter >= TB_CHAR_SIZE - 1) 
          next_state = TB_ATTR_SETUP;
        else 
          next_state = TB_CHAR_READ;
      
      TB_ATTR_SETUP: 
        next_state = TB_ATTR_READ;
      
      TB_ATTR_READ: 
        next_state = TB_ATTR_WRITE;
      
      TB_ATTR_WRITE: 
        if (tb_attr_counter >= TB_ATTR_SIZE - 1) 
          next_state = SPRITE_SETUP;
        else 
          next_state = TB_ATTR_READ;
      
      SPRITE_SETUP: 
        next_state = SPRITE_READ;
      
      SPRITE_READ: 
        next_state = SPRITE_WRITE;
      
      SPRITE_WRITE: 
        if (sprite_counter >= SPRITE_SIZE - 1) 
          next_state = COMPLETE;
        else 
          next_state = SPRITE_READ;
      
      COMPLETE: 
        next_state = IDLE;
    endcase
  end
  
  // DMA address and control signal generation
  always_comb begin
    // Default values
    dma_addr = 16'h0000;
    dma_write = 0;
    dma_data_out = 8'h00;
    
    tb_dma_write = 0;
    tb_dma_addr = 10'h000;
    tb_dma_data = 8'h00;
    
    sp_dma_write = 0;
    sp_dma_addr = 4'h0;
    sp_dma_data = 8'h00;
    
    case (state)
      TB_CHAR_READ: begin
        dma_addr = TB_CHAR_BASE + {5'b0, tb_char_counter[9:0]};  // Explicitly extend to 16 bits
        dma_write = 0;
      end
      
      TB_CHAR_WRITE: begin
        tb_dma_addr = tb_char_counter[9:0];
        tb_dma_write = 1;
        tb_dma_data = dma_data_in;
      end
      
      TB_ATTR_READ: begin
        dma_addr = TB_ATTR_BASE + {5'b0, tb_attr_counter[9:0]};  // Explicitly extend to 16 bits
        dma_write = 0;
      end
      
      TB_ATTR_WRITE: begin
        tb_dma_addr = 10'h400 + tb_attr_counter[9:0]; // Offset for attribute RAM
        tb_dma_write = 1;
        tb_dma_data = dma_data_in;
      end
      
      SPRITE_READ: begin
        dma_addr = SPRITE_BASE + {12'b0, sprite_counter};  // Explicitly extend to 16 bits
        dma_write = 0;
      end
      
      SPRITE_WRITE: begin
        sp_dma_addr = sprite_counter;
        sp_dma_write = 1;
        sp_dma_data = dma_data_in;
      end
    endcase
  end
  
  // Debug logging
  always_ff @(posedge clk) begin
    case (state)
      IDLE: 
        if (next_state == TB_CHAR_SETUP) 
          $display("DMA Controller: Starting DMA transfer");
      
      TB_CHAR_SETUP: 
        $display("DMA Controller: Starting text buffer character transfer");
      
      TB_ATTR_SETUP: 
        $display("DMA Controller: Starting text buffer attribute transfer");
      
      SPRITE_SETUP: 
        $display("DMA Controller: Starting sprite register transfer");
      
      COMPLETE: 
        $display("DMA Controller: DMA transfer complete");
    endcase
  end

endmodule

/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */ 