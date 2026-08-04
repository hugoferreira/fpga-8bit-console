`include "pll_gowin_psg_sdram.v"
`include "sdram_tangnano20k.sv"
`include "psg.sv"
`include "pcm_cdc.sv"
`include "pcm_signature.sv"
`include "pcm_trace_telemetry.sv"
`include "i2s_out.sv"
`include "uart_tx.v"
`include "uart_telemetry.sv"

// Standalone Tang Nano 20K demo:
//   1. copy Celeste's 4,608-byte PICO-8 audio image into SiP SDRAM;
//   2. read and verify it byte-for-byte while uploading it to the PSG;
//   3. start Celeste music pattern 0 (the initial climb) on channels 0..2;
//   4. send the PCM stream to the onboard MAX98357A speaker amplifier.
module top_psg #(
    parameter AUDIO_HEX = "build/gowin_psg/celeste-audio.hex"
  ) (
    input  logic        clk,
    output logic        led_playing,
    output logic        led_error,
    output logic        i2s_bclk,
    output logic        i2s_lrck,
    output logic        i2s_din,
    output logic        pa_en,
    output logic        uart_tx_o,

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

  localparam integer PSG_CLK_HZ = 18_750_000;
  localparam integer AUDIO_BYTES = 4_608;
  localparam integer REFRESH_CYCLES = 250; // 13.3 us at 18.75 MHz

  logic fastclk, psgclk, pll_locked;
  pll_gowin_psg_sdram pll0(
    .clock_in(clk), .fastclk(fastclk), .slowclk(psgclk), .locked(pll_locked));

  // Hold every state machine reset for 65,536 slow clocks after PLL lock.
  logic [15:0] reset_count = 0;
  always_ff @(posedge psgclk) begin
    if (!pll_locked)
      reset_count <= 0;
    else if (!(&reset_count))
      reset_count <= reset_count + 1'b1;
  end
  wire reset = !(&reset_count);

  logic [7:0] audio_rom [0:AUDIO_BYTES-1];
  initial $readmemh(AUDIO_HEX, audio_rom);

  logic        sdram_rd, sdram_wr, sdram_refresh;
  logic [22:0] sdram_addr;
  logic [7:0]  sdram_din, sdram_dout;
  logic        sdram_data_ready, sdram_busy, sdram_initialized;

  sdram_tangnano20k #(.CLK_HZ(PSG_CLK_HZ)) sdram0(
    .clk(psgclk), .reset(reset),
    .rd(sdram_rd), .wr(sdram_wr), .refresh(sdram_refresh),
    .addr(sdram_addr), .din(sdram_din), .dout(sdram_dout),
    .data_ready(sdram_data_ready), .busy(sdram_busy),
    .initialized(sdram_initialized),
    .O_sdram_clk, .O_sdram_cke, .O_sdram_cs_n,
    .O_sdram_cas_n, .O_sdram_ras_n, .O_sdram_wen_n,
    .IO_sdram_dq, .O_sdram_addr, .O_sdram_ba, .O_sdram_dqm);

  logic        psg_cs, psg_rw;
  logic [7:0]  psg_addr, psg_di;
  logic [7:0]  psg_dout;
  logic signed [15:0] pcm;
  logic [63:0] psg_dbg;

  /* verilator lint_off PINCONNECTEMPTY */
  psg #(.CLK_HZ(PSG_CLK_HZ), .REVERB(1), .DBG_PORT(2), .MULTIPUMP(0)) psg0(
    .clk(psgclk), .fastclk(fastclk), .reset(reset),
    .cs(psg_cs), .rw(psg_rw), .addr(psg_addr), .di(psg_di),
    .dout(psg_dout), .rdy(), .pcm(pcm), .dbg(psg_dbg));
  /* verilator lint_on PINCONNECTEMPTY */

  // The onboard amplifier is aggressive with the supplied small speaker.
  // Start from 12 dB attenuation, then apply the requested 3/2 boost: the
  // resulting 3/8-scale PCM is 50% louder than the previous quiet image.
  // Hold each source word stable across a toggle handshake before the fast
  // serializer sees it. This keeps the proven 43.945 kHz I2S framing without
  // sampling the PSG's 16-bit output directly across a clock boundary.
  logic signed [15:0] pcm_fast;
  pcm_cdc pcm_bridge(
    .src_clk(psgclk), .dst_clk(fastclk), .reset,
    .src_pcm(pcm), .dst_pcm(pcm_fast));

  i2s_out #(.HALF(40), .ATTEN_SHIFT(2), .BOOST_50_PERCENT(1)) i2s0(
    .clk(fastclk), .reset(reset), .pcm(pcm_fast),
    .bclk(i2s_bclk), .lrck(i2s_lrck), .din(i2s_din));

  typedef enum logic [4:0] {
    ST_WAIT_SDRAM,
    ST_WRITE_REQ,
    ST_WRITE_WAIT,
    ST_ADDR_LO,
    ST_ADDR_LO_GAP,
    ST_ADDR_HI,
    ST_ADDR_HI_GAP,
    ST_READ_REQ,
    ST_READ_WAIT,
    ST_UPLOAD_GAP,
    ST_VERIFY_ADDR_LO,
    ST_VERIFY_ADDR_LO_GAP,
    ST_VERIFY_ADDR_HI,
    ST_VERIFY_ADDR_HI_GAP,
    ST_VERIFY_READ_REQ,
    ST_VERIFY_READ_WAIT,
    ST_VERIFY_READ_LATCH,
    ST_VERIFY_READ_CHECK,
    ST_MASK,
    ST_MASK_GAP,
    ST_MUSIC,
    ST_MUSIC_GAP,
    ST_PLAY,
    ST_REFRESH_WAIT,
    ST_ERROR
  } player_state_t;

  player_state_t state, resume_state;
  logic [12:0] audio_index;
  logic [8:0]  refresh_count;
  logic        refresh_due;
  logic        playing;
  logic        memory_error;
  logic [1:0]  failure_stage; // 0 none, 1 SDRAM, 2 PSG RAM, 3 controller
  logic [31:0] pcm_sig;
  logic [12:0] pcm_sig_count;
  logic        pcm_sig_done;
  logic [63:0] pcm_trace_dbg;

  // DBG_PORT=2 publishes a registered pulse one PSG clock after each committed
  // dry PCM word, when pcm is stable for this same-domain consumer.
  pcm_signature #(.WORD_COUNT(4096)) pcm_sig0(
    .clk(psgclk), .reset,
    .enable(playing && !memory_error),
    .commit(psg_dbg[0]), .pcm,
    .signature(pcm_sig), .count(pcm_sig_count), .done(pcm_sig_done));

  // Preserve exact committed words through the first failing H027 interval.
  // Three words rotate through each G= telemetry page; this is observation-only
  // and does not feed the PSG or audio path.
  pcm_trace_telemetry #(
    .WORD_COUNT(33), .START_WORD(34), .PAGE_BASE(11),
    .PAGE_CYCLES(PSG_CLK_HZ / 4)
  ) pcm_trace0(
    .clk(psgclk), .reset,
    .enable(playing && !memory_error),
    .commit(psg_dbg[0]), .pcm,
    .debug(pcm_trace_dbg));

  always_ff @(posedge psgclk) begin
    if (reset) begin
      state          <= ST_WAIT_SDRAM;
      resume_state   <= ST_WAIT_SDRAM;
      audio_index    <= 0;
      refresh_count  <= 0;
      refresh_due    <= 1'b0;
      playing        <= 1'b0;
      memory_error   <= 1'b0;
      failure_stage  <= 2'd0;
      sdram_rd       <= 1'b0;
      sdram_wr       <= 1'b0;
      sdram_refresh  <= 1'b0;
      sdram_addr     <= 0;
      sdram_din      <= 0;
      psg_cs         <= 1'b0;
      psg_rw         <= 1'b1;
      psg_addr       <= 0;
      psg_di         <= 0;
    end else begin
      sdram_rd      <= 1'b0;
      sdram_wr      <= 1'b0;
      sdram_refresh <= 1'b0;
      psg_cs        <= 1'b0;
      psg_rw        <= 1'b1;

      if (!refresh_due) begin
        if (refresh_count == REFRESH_CYCLES - 1)
          refresh_due <= 1'b1;
        else
          refresh_count <= refresh_count + 1'b1;
      end

      case (state)
        ST_WAIT_SDRAM: begin
          if (sdram_initialized && !sdram_busy)
            state <= ST_WRITE_REQ;
        end

        ST_WRITE_REQ: begin
          if (refresh_due && !sdram_busy) begin
            sdram_refresh <= 1'b1;
            refresh_due   <= 1'b0;
            refresh_count <= 0;
            resume_state  <= ST_WRITE_REQ;
            state         <= ST_REFRESH_WAIT;
          end else if (!sdram_busy) begin
            sdram_addr <= {10'b0, audio_index};
            sdram_din  <= audio_rom[audio_index];
            sdram_wr   <= 1'b1;
            state      <= ST_WRITE_WAIT;
          end
        end

        ST_WRITE_WAIT: begin
          if (!sdram_busy && !sdram_wr) begin
            if (audio_index == AUDIO_BYTES - 1) begin
              audio_index <= 0;
              state <= ST_ADDR_LO;
            end else begin
              audio_index <= audio_index + 1'b1;
              state <= ST_WRITE_REQ;
            end
          end
        end

        ST_ADDR_LO: begin
          psg_addr <= 8'h00;
          psg_di   <= 8'h00;
          psg_cs   <= 1'b1;
          state    <= ST_ADDR_LO_GAP;
        end
        ST_ADDR_LO_GAP: state <= ST_ADDR_HI;

        ST_ADDR_HI: begin
          psg_addr <= 8'h01;
          psg_di   <= 8'h31;
          psg_cs   <= 1'b1;
          state    <= ST_ADDR_HI_GAP;
        end
        ST_ADDR_HI_GAP: state <= ST_READ_REQ;

        ST_READ_REQ: begin
          if (refresh_due && !sdram_busy) begin
            sdram_refresh <= 1'b1;
            refresh_due   <= 1'b0;
            refresh_count <= 0;
            resume_state  <= ST_READ_REQ;
            state         <= ST_REFRESH_WAIT;
          end else if (!sdram_busy) begin
            sdram_addr <= {10'b0, audio_index};
            sdram_rd   <= 1'b1;
            state      <= ST_READ_WAIT;
          end
        end

        ST_READ_WAIT: begin
          if (!sdram_busy && !sdram_rd) begin
            if (sdram_dout != audio_rom[audio_index]) begin
              memory_error <= 1'b1;
              failure_stage <= 2'd1;
              state <= ST_ERROR;
            end else begin
              psg_addr <= 8'h02;
              psg_di   <= sdram_dout;
              psg_cs   <= 1'b1;
              state    <= ST_UPLOAD_GAP;
            end
          end
        end

        ST_UPLOAD_GAP: begin
          if (audio_index == AUDIO_BYTES - 1) begin
            audio_index <= 0;
            state <= ST_VERIFY_ADDR_LO;
          end
          else begin
            audio_index <= audio_index + 1'b1;
            state <= ST_READ_REQ;
          end
        end

        // Rewind the PSG upload pointer and read the inferred audio RAM back
        // through its real synchronous port. The amplifier remains disabled
        // until every byte has survived both storage stages.
        ST_VERIFY_ADDR_LO: begin
          psg_addr <= 8'h00;
          psg_di   <= 8'h00;
          psg_cs   <= 1'b1;
          state    <= ST_VERIFY_ADDR_LO_GAP;
        end
        ST_VERIFY_ADDR_LO_GAP: state <= ST_VERIFY_ADDR_HI;

        ST_VERIFY_ADDR_HI: begin
          psg_addr <= 8'h01;
          psg_di   <= 8'h31;
          psg_cs   <= 1'b1;
          state    <= ST_VERIFY_ADDR_HI_GAP;
        end
        ST_VERIFY_ADDR_HI_GAP: state <= ST_VERIFY_READ_REQ;

        ST_VERIFY_READ_REQ: begin
          psg_addr <= 8'h02;
          psg_rw   <= 1'b0;
          psg_cs   <= 1'b1;
          state    <= ST_VERIFY_READ_WAIT;
        end
        // The PSG first borrows the synchronous RAM port, then registers that
        // byte into dout one clock later. Wait one more edge before comparing
        // so this controller observes the committed dout value.
        ST_VERIFY_READ_WAIT: state <= ST_VERIFY_READ_LATCH;
        ST_VERIFY_READ_LATCH: state <= ST_VERIFY_READ_CHECK;

        ST_VERIFY_READ_CHECK: begin
          if (psg_dout != audio_rom[audio_index]) begin
            memory_error <= 1'b1;
            failure_stage <= 2'd2;
            state <= ST_ERROR;
          end else if (audio_index == AUDIO_BYTES - 1) begin
            state <= ST_MASK;
          end else begin
            audio_index <= audio_index + 1'b1;
            state <= ST_VERIFY_READ_REQ;
          end
        end

        ST_MASK: begin
          psg_addr <= 8'h21;
          psg_di   <= 8'h07;
          psg_cs   <= 1'b1;
          state    <= ST_MASK_GAP;
        end
        ST_MASK_GAP: state <= ST_MUSIC;

        ST_MUSIC: begin
          psg_addr <= 8'h20;
          psg_di   <= 8'd0;
          psg_cs   <= 1'b1;
          state    <= ST_MUSIC_GAP;
        end
        ST_MUSIC_GAP: begin
          playing <= 1'b1;
          state   <= ST_PLAY;
        end

        ST_PLAY: begin
          if (refresh_due && !sdram_busy) begin
            sdram_refresh <= 1'b1;
            refresh_due   <= 1'b0;
            refresh_count <= 0;
            resume_state  <= ST_PLAY;
            state         <= ST_REFRESH_WAIT;
          end
        end

        ST_REFRESH_WAIT: begin
          if (!sdram_busy && !sdram_refresh)
            state <= resume_state;
        end

        ST_ERROR: begin
          playing <= 1'b0;
          state   <= ST_ERROR;
        end

        default: begin
          playing      <= 1'b0;
          memory_error <= 1'b1;
          failure_stage <= 2'd3;
          state        <= ST_ERROR;
        end
      endcase
    end
  end

  // Board LEDs are active low. LED0 means the track reached PLAY; LED1 is
  // normally dark and lights only if SDRAM readback differs from the ROM.
  assign led_playing = ~(playing && !memory_error);
  assign led_error   = ~memory_error;
  assign pa_en       = playing && !memory_error && pll_locked && !reset;

  // The onboard debugger exposes FPGA TX pin 69 as USB serial. Flags are
  // {reset,pll,sdram_init,sdram_busy,refresh_due,error,playing,pa_en}.
  uart_telemetry #(.CLK_HZ(PSG_CLK_HZ), .BAUD(115200), .REPORT_HZ(10)) telemetry0(
    .clk(psgclk), .reset, .state,
    .flags({reset, pll_locked, sdram_initialized, sdram_busy,
            refresh_due, memory_error, playing, pa_en}),
    .index(audio_index), .data(psg_dout), .failure_stage,
    .pcm_signature(pcm_sig), .pcm_count(pcm_sig_count),
    .pcm_done(pcm_sig_done),
    .psg_debug(pcm_trace_dbg),
    .tx(uart_tx_o));
endmodule
