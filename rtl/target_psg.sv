/*
 * Synthesis target: the PSG alone.
 *
 * Answers the question that motivated the whole split: what area and Fmax does
 * the audio chip have at the rate rtl/clocks.sv actually drives it? The PLL is
 * 112.5 MHz, but the PSG receives its divide-by-four output:
 *
 *     psgclk = 28.125 MHz, CLK_HZ = 28,125,000
 *
 * The old target passed 112,500,000 even after clocks.sv gained PSGDIV=4. That
 * did not change the physical clock constraint, but it did make the PSG's
 * fractional sample divider and all clock-count evidence describe a different
 * circuit from the shipping top. Keep this constant paired with top.sv's
 * PSG_CLK_HZ whenever the divider changes.
 *
 *
 * WHY THIS ONE DOES NOT GO THROUGH chip.sv
 * ----------------------------------------
 * The other three targets instantiate the shipping `chip` with subsystems
 * switched off, which is the whole point of the split (see design.md D1). This
 * one cannot, and both ways of trying were measured:
 *
 *   PSG + CPU + bus     8210 logic cells - 106% of an HX8K, DOES NOT PLACE.
 *                       No placement means no timing report, which is the one
 *                       thing this target exists to produce.
 *
 *   PSG + bus, no CPU   1467 logic cells. Not a smaller design - a folded one.
 *                       With no bus master, cpu_addr is a constant, so psg_cs
 *                       never asserts and yosys constant-folds 78% of the PSG
 *                       away. A measurement of nothing.
 *
 * So the register interface is driven from real pins instead. The drift risk
 * that D1 warns about is low here in a way it is not for the CPU: this
 * instantiates `psg` with its own port list and adds no model of anything -
 * unlike rtl/cpu_fmax_top.sv, which carries a private RAM written to imitate
 * ram_async.sv's timing and can silently stop imitating it.
 *
 * The CPU-drives-the-PSG configuration is still covered, just not by synthesis:
 * `make run` and `make psg-wav` both exercise it.
 *
 *   make synth-psg      area + Fmax at seed 1
 *   make psg-check      the regression testbench
 *   make psg-wav        what it actually sounds like - the real gate
 */

`include "psg.sv"

/* verilator lint_off DECLFILENAME */

module target_psg (
    input  logic       psgclk,
    input  logic       rst,
    input  logic       cs,
    input  logic       rw,
    input  logic [7:0] addr,
    input  logic [7:0] di,
    output logic       probe
);

    logic [7:0]         dout;
    logic signed [15:0] pcm;

    // dbg is left UNCONNECTED, exactly as rtl/top.sv leaves .psg_dbg(), so
    // yosys trims the 64-bit verification bus.
    //
    // This is not a detail. `yosys -top psg` does not place at all - not for
    // area, but because dbg pins 108 of tq144:4k's I/O:
    //
    //     ICESTORM_LC: 6791/7680  88%          <- fits
    //     ERROR: Unable to find a placement location for cell 'dbg[22]$sb_io'
    //
    // and the reflex fix - XOR dbg into the probe below, the way this file
    // does for pcm and dout - makes it place and makes the number wrong, by
    // keeping alive logic the console trims. Match the shipping top, always.
    /* verilator lint_off PINCONNECTEMPTY */
    psg #(.CLK_HZ(32'd28_125_000), .REVERB(1)) psg0 (
        .clk(psgclk), .reset(rst),
        .cs(cs), .rw(rw), .addr(addr), .di(di),
        .dout(dout), .pcm(pcm), .dbg()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // The real outputs, reduced to one registered pin so the datapath that
    // produces them is not optimised away for having nowhere to go.
    always_ff @(posedge psgclk) probe <= ^{dout, pcm};

endmodule

/* verilator lint_on DECLFILENAME */
