// Byte-wide controller for the 64 Mbit, 32-bit SDR SDRAM inside the
// Tang Nano 20K's GW2AR-18C system-in-package.
//
// The geometry and command timing follow the public GW2AR-18C examples:
// 2K rows x 256 32-bit words x 4 banks. Every access uses auto-precharge,
// leaving callers responsible only for issuing a refresh at least every
// 15 us. At the deliberately conservative 18.75 MHz used by the PSG player,
// all datasheet timing minima have several cycles of margin.
module sdram_tangnano20k #(
    parameter integer CLK_HZ = 18_750_000
  ) (
    input  logic        clk,
    input  logic        reset,

    input  logic        rd,
    input  logic        wr,
    input  logic        refresh,
    input  logic [22:0] addr,
    input  logic [7:0]  din,
    output logic [7:0]  dout,
    output logic        data_ready,
    output logic        busy,
    output logic        initialized,

    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  wire [31:0]  IO_sdram_dq,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [3:0]  O_sdram_dqm
  );

  localparam logic [2:0] CMD_MRS       = 3'b000;
  localparam logic [2:0] CMD_REFRESH   = 3'b001;
  localparam logic [2:0] CMD_PRECHARGE = 3'b010;
  localparam logic [2:0] CMD_ACTIVE    = 3'b011;
  localparam logic [2:0] CMD_WRITE     = 3'b100;
  localparam logic [2:0] CMD_READ      = 3'b101;
  localparam logic [2:0] CMD_NOP       = 3'b111;

  // 200 us power-up delay, rounded up. 16 bits covers this at 18.75 MHz.
  localparam integer INIT_CYCLES = (CLK_HZ + 4_999) / 5_000;

  typedef enum logic [3:0] {
    ST_POWERUP,
    ST_PRECHARGE,
    ST_PRECHARGE_WAIT,
    ST_INIT_REFRESH_1,
    ST_INIT_REFRESH_1_WAIT,
    ST_INIT_REFRESH_2,
    ST_INIT_REFRESH_2_WAIT,
    ST_MODE,
    ST_MODE_WAIT,
    ST_IDLE,
    ST_READ,
    ST_WRITE,
    ST_REFRESH,
    ST_ERROR
  } state_t;

  state_t state;
  logic [15:0] init_count;
  logic [3:0]  cycle;
  logic [22:0] addr_q;
  logic [7:0]  din_q;
  logic        dq_oe;
  logic [31:0] dq_out;
  wire  [31:0] dq_in = IO_sdram_dq;

  assign IO_sdram_dq = dq_oe ? dq_out : 32'bz;

  // The SDRAM samples commands and data half a controller cycle after they
  // are registered. At 18.75 MHz the resulting 26.7 ns setup interval is far
  // larger than the device requires.
  assign O_sdram_clk = ~clk;
  assign O_sdram_cke = 1'b1;
  assign O_sdram_cs_n = 1'b0;

  always_ff @(posedge clk) begin
    if (reset) begin
      state          <= ST_POWERUP;
      init_count     <= 0;
      cycle          <= 0;
      addr_q         <= 0;
      din_q          <= 0;
      dout           <= 0;
      data_ready     <= 1'b0;
      busy           <= 1'b1;
      initialized    <= 1'b0;
      dq_oe          <= 1'b0;
      dq_out         <= 0;
      O_sdram_addr   <= 0;
      O_sdram_ba     <= 0;
      O_sdram_dqm    <= 4'b0000;
      {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_NOP;
    end else begin
      data_ready <= 1'b0;
      dq_oe      <= 1'b0;
      O_sdram_dqm <= 4'b0000;
      {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_NOP;

      case (state)
        ST_POWERUP: begin
          if (init_count == INIT_CYCLES - 1) begin
            cycle <= 0;
            state <= ST_PRECHARGE;
          end else begin
            init_count <= init_count + 1'b1;
          end
        end

        ST_PRECHARGE: begin
          O_sdram_addr <= 11'b100_0000_0000; // A10=1: all banks
          {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_PRECHARGE;
          cycle <= 0;
          state <= ST_PRECHARGE_WAIT;
        end

        ST_PRECHARGE_WAIT: begin
          if (cycle == 2) begin
            cycle <= 0;
            state <= ST_INIT_REFRESH_1;
          end else cycle <= cycle + 1'b1;
        end

        ST_INIT_REFRESH_1: begin
          {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_REFRESH;
          cycle <= 0;
          state <= ST_INIT_REFRESH_1_WAIT;
        end

        ST_INIT_REFRESH_1_WAIT: begin
          if (cycle == 4) begin
            cycle <= 0;
            state <= ST_INIT_REFRESH_2;
          end else cycle <= cycle + 1'b1;
        end

        ST_INIT_REFRESH_2: begin
          {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_REFRESH;
          cycle <= 0;
          state <= ST_INIT_REFRESH_2_WAIT;
        end

        ST_INIT_REFRESH_2_WAIT: begin
          if (cycle == 4) begin
            cycle <= 0;
            state <= ST_MODE;
          end else cycle <= cycle + 1'b1;
        end

        ST_MODE: begin
          // CAS=2, sequential burst, burst length 1.
          O_sdram_addr <= 11'h020;
          {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_MRS;
          cycle <= 0;
          state <= ST_MODE_WAIT;
        end

        ST_MODE_WAIT: begin
          if (cycle == 2) begin
            busy        <= 1'b0;
            initialized <= 1'b1;
            state       <= ST_IDLE;
          end else cycle <= cycle + 1'b1;
        end

        ST_IDLE: begin
          if (refresh) begin
            busy <= 1'b1;
            cycle <= 0;
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_REFRESH;
            state <= ST_REFRESH;
          end else if (rd || wr) begin
            busy   <= 1'b1;
            addr_q <= addr;
            din_q  <= din;
            O_sdram_ba   <= addr[22:21];
            O_sdram_addr <= addr[20:10];
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_ACTIVE;
            cycle <= 0;
            state <= rd ? ST_READ : ST_WRITE;
          end
        end

        ST_READ: begin
          cycle <= cycle + 1'b1;
          if (cycle == 0) begin
            // A10=1 requests auto-precharge; A9:A8 are zero and A7:A0
            // select one of the 256 words in the row.
            O_sdram_addr <= {1'b1, 2'b00, addr_q[9:2]};
            O_sdram_dqm  <= 4'b0000;
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_READ;
          end else if (cycle == 3) begin
            case (addr_q[1:0])
              2'd0: dout <= dq_in[7:0];
              2'd1: dout <= dq_in[15:8];
              2'd2: dout <= dq_in[23:16];
              2'd3: dout <= dq_in[31:24];
            endcase
            data_ready <= 1'b1;
          end else if (cycle == 4) begin
            busy  <= 1'b0;
            state <= ST_IDLE;
          end
        end

        ST_WRITE: begin
          cycle <= cycle + 1'b1;
          if (cycle == 0) begin
            O_sdram_addr <= {1'b1, 2'b00, addr_q[9:2]};
            case (addr_q[1:0])
              2'd0: O_sdram_dqm <= 4'b1110;
              2'd1: O_sdram_dqm <= 4'b1101;
              2'd2: O_sdram_dqm <= 4'b1011;
              2'd3: O_sdram_dqm <= 4'b0111;
            endcase
            dq_out <= {4{din_q}};
            dq_oe  <= 1'b1;
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_WRITE;
          end else if (cycle == 4) begin
            busy  <= 1'b0;
            state <= ST_IDLE;
          end
        end

        ST_REFRESH: begin
          if (cycle == 4) begin
            busy  <= 1'b0;
            state <= ST_IDLE;
          end else cycle <= cycle + 1'b1;
        end

        default: begin
          busy  <= 1'b1;
          state <= ST_ERROR;
        end
      endcase
    end
  end
endmodule
