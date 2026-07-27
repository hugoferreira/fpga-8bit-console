/*
 * Shared body of the four per-subsystem synthesis targets.
 *
 * `rtl/target_cpu.sv`, `target_psg.sv`, `target_ppu.sv` and `target_soc.sv` are
 * each one instantiation of this with different parameters. The point of the
 * split (openspec/changes/refactor-build-targets) is that a subsystem's area
 * and Fmax can be measured without the other two, and WITHOUT a hand-written
 * harness that re-describes how the console is wired: this instantiates the
 * same `chip` module that rtl/top.sv and rtl/top_simulator.sv instantiate, and
 * switches subsystems off by parameter. So a change to chip.sv's wiring shows
 * up in every target with no separate edit.
 *
 * Contrast rtl/cpu_fmax_top.sv, which carries a private RAM model written to
 * imitate ram_async.sv's timing. That imitation is correct today and nothing
 * enforces that it stays correct. This one cannot drift.
 *
 * Two clock pins, not one
 * ----------------------
 * The console derives everything from one PLL (rtl/clocks.sv): psgclk is
 * 112.5/4 = 28.125 MHz, and the chip runs at /32. Here they are separate INPUT
 * pins so nextpnr reports an Fmax per domain, which is the question each
 * subsystem actually has. Feeding both from one pin instead would report the
 * minimum across the whole design and attribute it to nothing.
 *
 * Not a functional target
 * -----------------------
 * RAM_ADDR_BITS is small here (see the per-target files), so the address is
 * truncated and $FFFC aliases into the program image - a program will NOT run
 * from these. They are for area and timing. The functional gates are the
 * simulator ones: `make run`, `make ppu-check`, `make psg-wav`.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

`include "chip.sv"
`include "hvsync_generator.sv"

/* verilator lint_off DECLFILENAME */

module target_harness (
    input  logic       clk,       // chip clock (CPU, PPU, arbiter, DMA)
    input  logic       psgclk,    // PSG clock; 28.125 MHz on iCE40 hardware
    input  logic       rst,
    input  logic [7:0] buttons,
    output logic       probe
);

    parameter HAS_PPU = 1, HAS_PSG = 1;

    // 2 KB (11 bits) for the subsystem targets, 8 KB (13) for the full SoC.
    // BRAM is the binding resource on this device - 32 blocks, of which the PSG
    // and the PPU take 16 each - so a target whose main RAM eats 16 more would
    // report "does not place" instead of reporting the subsystem's own cost.
    parameter RAM_ADDR_BITS = 11;

    logic       hsync, vsync, display_on;
    logic [7:0] hpos;
    logic [6:0] vpos;

    // Real video timing, so the PPU's display path is driven the way it is in
    // the console rather than by a constant that would let it be trimmed.
    hvsync_generator hvsync_gen (
        .clk(clk), .reset(rst),
        .hsync(hsync), .vsync(vsync), .display_on(display_on),
        .hpos(hpos), .vpos(vpos)
    );

    localparam int RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE;

    logic [RGB-1:0]     rgb;
    logic signed [15:0] audio;

    // psg_dbg is left UNCONNECTED, exactly as rtl/top.sv leaves it, so yosys
    // trims the 64-bit verification bus. Connecting it - even reduced into the
    // probe below - would pin logic the console does not contain and measure a
    // circuit that never ships. See design.md D3: the PSG does not place as
    // `-top psg` for this reason, and the failure looks like an area problem
    // when it is a pin-budget one.
    /* verilator lint_off PINCONNECTEMPTY */
    chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE("palette565.bin"),
           .CLK_HZ(32'd28_125_000), .REVERB(1),
           .HAS_PPU(HAS_PPU), .HAS_PSG(HAS_PSG),
           .RAM_ADDR_BITS(RAM_ADDR_BITS))
      chip0 (
        .clk(clk), .cpuclk(clk), .psgclk(psgclk), .reset(rst),
        .vsync(vsync), .hsync(hsync), .vpos(vpos), .hpos(hpos),
        .buttons(buttons),
        .rgb(rgb), .audio(audio), .psg_dbg()
      );
    /* verilator lint_on PINCONNECTEMPTY */

    // The chip's REAL outputs, reduced to one registered pin. tq144:4k has 256
    // I/O and this keeps the count near 12, but the reduction exists mainly so
    // that neither the video nor the audio datapath is optimised away for
    // having nowhere to go - and so the four targets are not distorted by
    // differing I/O counts. Same trick, and same reason, as cpu_fmax_top.sv.
    // With no PPU, chip.sv drives rgb from a reduction of the CPU bus rather
    // than zero, so this stays non-constant and the CPU is not trimmed. See
    // the g_no_ppu branch in chip.sv.
    always_ff @(posedge clk) probe <= ^{rgb, audio};

endmodule

/* verilator lint_on DECLFILENAME */
