// PSG: 4-channel programmable sound generator with a hardware sequencer.
// The note format IS PICO-8's: 16 bits = {custom[15], fx[14:12], vol[11:9],
// wave[8:6], pitch[5:0]} - cart sound data plays natively (effects are
// accepted but not yet interpreted; the cart's sounds bake their fades
// into per-note volumes). A channel is started with 4 register writes
// (start, length, speed, play); the sequencer then steps notes on the
// 60 Hz tick with no CPU involvement - PICO-8's sfx() as hardware.
//
// Registers (byte window):
//   $00 sfx RAM address low   $01 address high (bit 0)
//   $02 sfx RAM data (write stores byte and auto-increments the address)
//   $03 (read) playing status, one bit per channel
//   $10+c*4: +0 start note index, +1 length in notes, +2 speed
//            (frames per note, >=1), +3 control (bit0 play/retrigger,
//            bit1 loop; writing 0 stops the channel)
//
// Waves (PICO-8 indices): 0 tri, 1 tilted saw (~saw), 2 saw, 3 square,
// 4 pulse 25%, 5 organ (~tri), 6 noise (LFSR), 7 phaser (~tri).
module psg(input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           input bit tick,             // 60 Hz sequencer tick
           output logic [7:0] pcm);

  // SFX RAM: 256 notes = 512 bytes, note words little-endian
  logic [7:0] sfxram[0:511];
  logic [8:0] wraddr;

  // Pitch -> phase increment (generated for the simulator clock rate)
  logic [15:0] pinc[0:63];
  initial $readmemh("./rtl/psg_pitch.hex", pinc);

  // Channel state
  logic        playing[0:3];
  logic        looping[0:3];
  logic [7:0]  ch_start[0:3];
  logic [7:0]  ch_len[0:3];
  logic [7:0]  ch_speed[0:3];
  logic [7:0]  ch_off[0:3];
  logic [7:0]  ch_fcnt[0:3];
  logic [5:0]  ch_pitch[0:3];
  logic [2:0]  ch_wave[0:3];
  logic [2:0]  ch_vol[0:3];
  logic [23:0] phase[0:3];

  // ------------------------------------------------------------------
  // Sequencer: one 60 Hz tick walks the four channels serially; a note
  // fetch is lo-read -> hi-read -> load (registered RAM read, 1 cycle)
  // ------------------------------------------------------------------
  typedef enum logic [1:0] { S_IDLE, S_RDLO, S_RDHI, S_LD } sst_t;
  sst_t sst;
  logic [1:0] sch;
  logic       spend;
  logic [7:0] note_lo;
  logic       tick_q;

  wire [7:0] cur_note = ch_start[sch] + ch_off[sch];
  wire [8:0] sq_addr  = {cur_note, sst == S_RDHI};
  logic [7:0] sq_data;
  always_ff @(posedge clk)
    sq_data <= sfxram[sq_addr];

  always_ff @(posedge clk) begin
    if (reset) begin
      sst <= S_IDLE;
      sch <= 0;
      spend <= 0;
      tick_q <= 0;
      for (int c = 0; c < 4; c++) begin
        playing[c] <= 0;
        looping[c] <= 0;
        ch_off[c] <= 0;
        ch_fcnt[c] <= 0;
        ch_pitch[c] <= 0;
        ch_wave[c] <= 0;
        ch_vol[c] <= 0;
      end
    end else begin
      tick_q <= tick;
      if (tick && !tick_q) begin
        sch <= 0;
        spend <= 1;
      end

      case (sst)
        S_IDLE: if (spend) begin
          if (!playing[sch]) begin
            if (sch == 3) spend <= 0;
            sch <= sch + 1;
          end else if (ch_fcnt[sch] == 0) begin
            // just triggered (or just advanced): fetch the current note
            ch_fcnt[sch] <= 1;
            sst <= S_RDLO;
          end else if (ch_fcnt[sch] >= ch_speed[sch]) begin
            // note finished: advance, stop, or loop; fetch if still going
            if (ch_off[sch] + 1 >= ch_len[sch]) begin
              if (looping[sch]) begin
                ch_off[sch] <= 0;
                ch_fcnt[sch] <= 1;
                sst <= S_RDLO;
              end else begin
                playing[sch] <= 0;
                ch_vol[sch] <= 0;
                if (sch == 3) spend <= 0;
                sch <= sch + 1;
              end
            end else begin
              ch_off[sch] <= ch_off[sch] + 1;
              ch_fcnt[sch] <= 1;
              sst <= S_RDLO;
            end
          end else begin
            ch_fcnt[sch] <= ch_fcnt[sch] + 1;
            if (sch == 3) spend <= 0;
            sch <= sch + 1;
          end
        end
        S_RDLO: sst <= S_RDHI;              // lo byte lands in sq_data next
        S_RDHI: begin
          note_lo <= sq_data;               // capture lo; hi lands next
          sst <= S_LD;
        end
        S_LD: begin
          ch_pitch[sch] <= note_lo[5:0];
          ch_wave[sch]  <= {sq_data[0], note_lo[7:6]};
          ch_vol[sch]   <= sq_data[3:1];
          sst <= S_IDLE;
          if (sch == 3) spend <= 0;
          sch <= sch + 1;
        end
      endcase

      // CPU control writes override sequencer state
      if (cs && rw && addr[7:4] == 4'h1 && addr[1:0] == 2'd3) begin
        playing[addr[3:2]] <= di[0];
        looping[addr[3:2]] <= di[1];
        if (di[0]) begin
          ch_off[addr[3:2]] <= 0;
          ch_fcnt[addr[3:2]] <= 0;
        end else
          ch_vol[addr[3:2]] <= 0;
      end
    end
  end

  // ------------------------------------------------------------------
  // Tone generation
  // ------------------------------------------------------------------
  logic [14:0] nlfsr;
  logic [11:0] mixsum;

  always_comb begin
    mixsum = 12'd0;
    for (int c = 0; c < 4; c++) begin
      logic [7:0] ph8, amp;
      ph8 = phase[c][23:16];
      case (ch_wave[c])
        3'd1, 3'd2: amp = ph8;                                          // saws
        3'd3:       amp = ph8[7] ? 8'd255 : 8'd0;                       // square
        3'd4:       amp = (ph8 < 8'd64) ? 8'd255 : 8'd0;                // pulse
        3'd6:       amp = nlfsr[7:0];                                   // noise
        default:    amp = ph8[7] ? {~ph8[6:0], 1'b0} : {ph8[6:0], 1'b0}; // tri
      endcase
      mixsum = mixsum + (({4'b0, amp} * {9'b0, ch_vol[c]}) >> 3);
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      nlfsr <= 15'h2A5F;
      pcm <= 8'h80;
      for (int c = 0; c < 4; c++)
        phase[c] <= 0;
    end else begin
      nlfsr <= {nlfsr[13:0], nlfsr[14] ^ nlfsr[13]};
      for (int c = 0; c < 4; c++)
        phase[c] <= phase[c] + {8'b0, pinc[ch_pitch[c]]};
      pcm <= (mixsum > 12'd255) ? 8'd255 : mixsum[7:0];
    end
  end

  // ------------------------------------------------------------------
  // CPU interface (RAM/address/channel parameter writes; status read)
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (reset) begin
      wraddr <= 0;
      for (int c = 0; c < 4; c++) begin
        ch_start[c] <= 0;
        ch_len[c] <= 0;
        ch_speed[c] <= 1;
      end
    end else if (cs && rw) begin
      case (addr)
        8'h00: wraddr[7:0] <= di;
        8'h01: wraddr[8] <= di[0];
        8'h02: begin
          sfxram[wraddr] <= di;
          wraddr <= wraddr + 1;
        end
        default:
          if (addr[7:4] == 4'h1) begin
            case (addr[1:0])
              2'd0: ch_start[addr[3:2]] <= di;
              2'd1: ch_len[addr[3:2]] <= di;
              2'd2: ch_speed[addr[3:2]] <= di;
              default: ;   // control handled in the sequencer block
            endcase
          end
      endcase
    end else if (cs && !rw) begin
      case (addr)
        8'h03: dout <= {4'b0, playing[3], playing[2], playing[1], playing[0]};
        default: dout <= 8'h00;
      endcase
    end
  end
endmodule
